--
-- PostgreSQL database dump
--

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.5

-- Started on 2026-01-20 19:28:55

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 50 (class 2615 OID 17485)
-- Name: public; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA public;


ALTER SCHEMA public OWNER TO postgres;

--
-- TOC entry 527 (class 1255 OID 20133)
-- Name: create_order_transaction(bigint, jsonb, text, numeric, numeric, text, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_order_transaction(p_customer_id bigint, p_customer_info jsonb, p_payment_method text, p_shipping_fee numeric, p_discount_amount numeric, p_voucher_code text, p_items jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_order_id BIGINT;
    v_order_code TEXT;
    v_subtotal NUMERIC := 0;
    v_total_amount NUMERIC;
    v_item JSONB;
    v_variant_id BIGINT;
    v_buy_qty INT;
    v_price NUMERIC;
    v_needed_qty INT;
    v_batch RECORD;
    v_take_qty INT;
    v_item_cogs NUMERIC;
    v_total_stock INT;
BEGIN
    -- 1. Tạo mã đơn hàng tự động (Ví dụ: ORD-TIMESTAMP-RANDOM)
    v_order_code := 'ORD-' || CAST(EXTRACT(EPOCH FROM NOW()) * 1000 AS BIGINT);

    -- 2. Tính lại Subtotal từ danh sách items gửi lên (Để bảo mật giá)
    -- Lưu ý: Node.js nên truyền giá đã validate, nhưng SQL tính lại tổng cho chắc
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_subtotal := v_subtotal + (CAST(v_item->>'quantity' AS INT) * CAST(v_item->>'unit_price' AS NUMERIC));
    END LOOP;

    v_total_amount := v_subtotal + p_shipping_fee - p_discount_amount;
    IF v_total_amount < 0 THEN v_total_amount := 0; END IF;

    -- 3. Tạo Đơn hàng (Insert vào bảng orders)
    INSERT INTO orders (
        code, customer_id, 
        customer_name, customer_phone, customer_email, customer_address,
        payment_method, status, 
        subtotal, discount_amount, shipping_fee, total_amount, 
        shipping_carrier, shipping_tracking_code, 
        created_at
    ) VALUES (
        v_order_code, p_customer_id,
        p_customer_info->>'name', p_customer_info->>'phone', p_customer_info->>'email', p_customer_info->>'address',
        p_payment_method, 'pending',
        v_subtotal, p_discount_amount, p_shipping_fee, v_total_amount,
        'SPX', 'SPX' || CAST(EXTRACT(EPOCH FROM NOW()) AS TEXT), -- Giả lập mã vận đơn
        NOW()
    ) RETURNING id INTO v_order_id;

    -- 4. Xử lý từng sản phẩm: Trừ kho FIFO & Lưu Order Items
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_variant_id := CAST(v_item->>'variant_id' AS BIGINT);
        v_buy_qty := CAST(v_item->>'quantity' AS INT);
        v_price := CAST(v_item->>'unit_price' AS NUMERIC);
        
        v_needed_qty := v_buy_qty;
        v_item_cogs := 0; -- Tổng giá vốn của item này

        -- Kiểm tra tổng tồn kho trước
        SELECT COALESCE(SUM(quantity_remaining), 0) INTO v_total_stock
        FROM inventory_batches
        WHERE variant_id = v_variant_id;

        IF v_total_stock < v_buy_qty THEN
            RAISE EXCEPTION 'Sản phẩm ID % không đủ hàng trong kho (Còn: %, Cần: %)', v_variant_id, v_total_stock, v_buy_qty;
        END IF;

        -- Vòng lặp lấy lô hàng (FIFO + Khóa dòng FOR UPDATE)
        FOR v_batch IN 
            SELECT * FROM inventory_batches 
            WHERE variant_id = v_variant_id AND quantity_remaining > 0 
            ORDER BY created_at ASC 
            FOR UPDATE -- <--- QUAN TRỌNG: Khóa dòng này lại, không ai được đụng vào khi đang xử lý
        LOOP
            IF v_needed_qty > 0 THEN
                -- Lấy số lượng có thể từ lô này
                IF v_batch.quantity_remaining >= v_needed_qty THEN
                    v_take_qty := v_needed_qty;
                ELSE
                    v_take_qty := v_batch.quantity_remaining;
                END IF;

                -- Trừ kho
                UPDATE inventory_batches 
                SET quantity_remaining = quantity_remaining - v_take_qty
                WHERE id = v_batch.id;

                -- Cộng dồn giá vốn (Số lượng lấy * Giá vốn lô đó)
                v_item_cogs := v_item_cogs + (v_take_qty * v_batch.cost_price);

                v_needed_qty := v_needed_qty - v_take_qty;
            END IF;
        END LOOP;

        -- Lưu chi tiết đơn hàng (Order Item)
        INSERT INTO order_items (
            order_id, variant_id, quantity, price_at_purchase, cogs_total
        ) VALUES (
            v_order_id, v_variant_id, v_buy_qty, v_price, v_item_cogs
        );
    END LOOP;

    -- 5. Trả về kết quả JSON
    RETURN jsonb_build_object(
        'success', true,
        'order_id', v_order_id,
        'order_code', v_order_code,
        'message', 'Tạo đơn hàng thành công'
    );
END;
$$;


ALTER FUNCTION public.create_order_transaction(p_customer_id bigint, p_customer_info jsonb, p_payment_method text, p_shipping_fee numeric, p_discount_amount numeric, p_voucher_code text, p_items jsonb) OWNER TO postgres;

--
-- TOC entry 526 (class 1255 OID 20107)
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
  INSERT INTO public.customers (user_id, email, full_name, phone)
  VALUES (
    new.id, 
    new.email, 
    new.raw_user_meta_data->>'full_name', -- Lấy tên từ metadata
    new.raw_user_meta_data->>'phone'      -- Lấy sđt từ metadata
  );
  RETURN new;
END;
$$;


ALTER FUNCTION public.handle_new_user() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 399 (class 1259 OID 21617)
-- Name: banners; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.banners (
    id bigint NOT NULL,
    title text,
    image_url text NOT NULL,
    link_url text,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.banners OWNER TO postgres;

--
-- TOC entry 398 (class 1259 OID 21616)
-- Name: banners_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.banners ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.banners_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 381 (class 1259 OID 17657)
-- Name: cart_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.cart_items (
    id bigint NOT NULL,
    cart_id uuid,
    variant_id bigint,
    quantity integer NOT NULL,
    CONSTRAINT cart_items_quantity_check CHECK ((quantity > 0))
);


ALTER TABLE public.cart_items OWNER TO postgres;

--
-- TOC entry 380 (class 1259 OID 17656)
-- Name: cart_items_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.cart_items ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.cart_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 379 (class 1259 OID 17650)
-- Name: carts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.carts (
    user_id uuid NOT NULL,
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.carts OWNER TO postgres;

--
-- TOC entry 361 (class 1259 OID 17497)
-- Name: categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.categories (
    id bigint NOT NULL,
    name text NOT NULL,
    slug text NOT NULL,
    parent_id bigint,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.categories OWNER TO postgres;

--
-- TOC entry 360 (class 1259 OID 17496)
-- Name: categories_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.categories ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.categories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 391 (class 1259 OID 20148)
-- Name: content_banners; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.content_banners (
    id bigint NOT NULL,
    title text,
    image_url text NOT NULL,
    link_to text,
    display_order integer DEFAULT 0,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.content_banners OWNER TO postgres;

--
-- TOC entry 390 (class 1259 OID 20147)
-- Name: content_banners_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.content_banners ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.content_banners_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 376 (class 1259 OID 17626)
-- Name: customers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.customers (
    id bigint NOT NULL,
    user_id uuid,
    full_name text NOT NULL,
    phone text,
    email text,
    address text,
    loyalty_points integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.customers OWNER TO postgres;

--
-- TOC entry 375 (class 1259 OID 17625)
-- Name: customers_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.customers ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.customers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 387 (class 1259 OID 17721)
-- Name: expense_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.expense_categories (
    id bigint NOT NULL,
    name text NOT NULL,
    description text
);


ALTER TABLE public.expense_categories OWNER TO postgres;

--
-- TOC entry 386 (class 1259 OID 17720)
-- Name: expense_categories_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.expense_categories ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.expense_categories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 389 (class 1259 OID 17729)
-- Name: expenses; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.expenses (
    id bigint NOT NULL,
    store_id bigint,
    category_id bigint,
    amount numeric(12,0) NOT NULL,
    expense_date date DEFAULT CURRENT_DATE,
    note text,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.expenses OWNER TO postgres;

--
-- TOC entry 388 (class 1259 OID 17728)
-- Name: expenses_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.expenses ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.expenses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 374 (class 1259 OID 17602)
-- Name: inventory_batches; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.inventory_batches (
    id bigint NOT NULL,
    store_id bigint,
    variant_id bigint,
    purchase_item_id bigint,
    original_quantity integer NOT NULL,
    quantity_remaining integer NOT NULL,
    cost_price numeric(12,0) NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    batch_name text,
    supplier_id bigint,
    CONSTRAINT inventory_batches_quantity_remaining_check CHECK ((quantity_remaining >= 0))
);


ALTER TABLE public.inventory_batches OWNER TO postgres;

--
-- TOC entry 373 (class 1259 OID 17601)
-- Name: inventory_batches_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.inventory_batches ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.inventory_batches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 385 (class 1259 OID 17704)
-- Name: order_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.order_items (
    id bigint NOT NULL,
    order_id bigint,
    variant_id bigint,
    quantity integer NOT NULL,
    price_at_purchase numeric(12,0) NOT NULL,
    cogs_total numeric(12,0) DEFAULT 0
);


ALTER TABLE public.order_items OWNER TO postgres;

--
-- TOC entry 384 (class 1259 OID 17703)
-- Name: order_items_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.order_items ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.order_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 383 (class 1259 OID 17674)
-- Name: orders; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.orders (
    id bigint NOT NULL,
    code text NOT NULL,
    customer_id bigint,
    store_id bigint,
    promotion_id bigint,
    subtotal numeric(12,0) NOT NULL,
    discount_amount numeric(12,0) DEFAULT 0,
    shipping_fee numeric(12,0) DEFAULT 0,
    total_amount numeric(12,0) NOT NULL,
    payment_method text DEFAULT 'cod'::text,
    status text DEFAULT 'pending'::text,
    note text,
    created_at timestamp with time zone DEFAULT now(),
    customer_name text,
    customer_phone text,
    customer_address text,
    customer_email text,
    shipping_carrier text,
    shipping_tracking_code text,
    payment_status text DEFAULT 'unpaid'::text,
    email text
);


ALTER TABLE public.orders OWNER TO postgres;

--
-- TOC entry 382 (class 1259 OID 17673)
-- Name: orders_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.orders ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.orders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 366 (class 1259 OID 17533)
-- Name: product_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.product_categories (
    product_id bigint NOT NULL,
    category_id bigint NOT NULL
);


ALTER TABLE public.product_categories OWNER TO postgres;

--
-- TOC entry 365 (class 1259 OID 17522)
-- Name: products; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.products (
    id bigint NOT NULL,
    name text NOT NULL,
    slug text NOT NULL,
    description text,
    base_price numeric(12,0) NOT NULL,
    images text[],
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    category_id bigint
);


ALTER TABLE public.products OWNER TO postgres;

--
-- TOC entry 364 (class 1259 OID 17521)
-- Name: products_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.products ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.products_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 378 (class 1259 OID 17637)
-- Name: promotions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.promotions (
    id bigint NOT NULL,
    code text NOT NULL,
    description text,
    discount_type text,
    discount_value numeric(12,0) NOT NULL,
    min_order_value numeric(12,0) DEFAULT 0,
    start_date timestamp with time zone,
    end_date timestamp with time zone,
    requires_account boolean DEFAULT true,
    is_active boolean DEFAULT true,
    usage_limit integer DEFAULT 100,
    used_count integer DEFAULT 0,
    max_discount_amount numeric(12,0) DEFAULT 0,
    CONSTRAINT promotions_discount_type_check CHECK ((discount_type = ANY (ARRAY['percent'::text, 'fixed'::text])))
);


ALTER TABLE public.promotions OWNER TO postgres;

--
-- TOC entry 377 (class 1259 OID 17636)
-- Name: promotions_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.promotions ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.promotions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 372 (class 1259 OID 17585)
-- Name: purchase_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.purchase_items (
    id bigint NOT NULL,
    purchase_order_id bigint,
    variant_id bigint,
    quantity integer NOT NULL,
    unit_cost numeric(12,0) NOT NULL,
    CONSTRAINT purchase_items_quantity_check CHECK ((quantity > 0))
);


ALTER TABLE public.purchase_items OWNER TO postgres;

--
-- TOC entry 371 (class 1259 OID 17584)
-- Name: purchase_items_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.purchase_items ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.purchase_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 370 (class 1259 OID 17565)
-- Name: purchase_orders; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.purchase_orders (
    id bigint NOT NULL,
    supplier_id bigint,
    store_id bigint,
    total_cost numeric(12,0) DEFAULT 0 NOT NULL,
    note text,
    purchase_date timestamp with time zone DEFAULT now(),
    code text,
    status text
);


ALTER TABLE public.purchase_orders OWNER TO postgres;

--
-- TOC entry 369 (class 1259 OID 17564)
-- Name: purchase_orders_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.purchase_orders ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.purchase_orders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 359 (class 1259 OID 17487)
-- Name: stores; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stores (
    id bigint NOT NULL,
    name text NOT NULL,
    address text,
    phone text,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.stores OWNER TO postgres;

--
-- TOC entry 358 (class 1259 OID 17486)
-- Name: stores_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.stores ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.stores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 363 (class 1259 OID 17513)
-- Name: suppliers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.suppliers (
    id bigint NOT NULL,
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    phone text,
    address text
);


ALTER TABLE public.suppliers OWNER TO postgres;

--
-- TOC entry 362 (class 1259 OID 17512)
-- Name: suppliers_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.suppliers ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.suppliers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 368 (class 1259 OID 17549)
-- Name: variants; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.variants (
    id bigint NOT NULL,
    product_id bigint,
    sku text NOT NULL,
    size text NOT NULL,
    color text NOT NULL,
    current_price numeric(12,0),
    image_url text,
    created_at timestamp with time zone DEFAULT now(),
    weight integer DEFAULT 500
);


ALTER TABLE public.variants OWNER TO postgres;

--
-- TOC entry 367 (class 1259 OID 17548)
-- Name: variants_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.variants ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.variants_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 4012 (class 0 OID 21617)
-- Dependencies: 399
-- Data for Name: banners; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.banners (id, title, image_url, link_url, is_active, created_at) FROM stdin;
\.


--
-- TOC entry 4000 (class 0 OID 17657)
-- Dependencies: 381
-- Data for Name: cart_items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.cart_items (id, cart_id, variant_id, quantity) FROM stdin;
\.


--
-- TOC entry 3998 (class 0 OID 17650)
-- Dependencies: 379
-- Data for Name: carts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.carts (user_id, updated_at) FROM stdin;
\.


--
-- TOC entry 3980 (class 0 OID 17497)
-- Dependencies: 361
-- Data for Name: categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.categories (id, name, slug, parent_id, created_at) FROM stdin;
1	Áo thun và Polo	ao-thun-va-polo	\N	2026-01-19 12:47:16.49794+00
\.


--
-- TOC entry 4010 (class 0 OID 20148)
-- Dependencies: 391
-- Data for Name: content_banners; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.content_banners (id, title, image_url, link_to, display_order, is_active, created_at) FROM stdin;
\.


--
-- TOC entry 3995 (class 0 OID 17626)
-- Dependencies: 376
-- Data for Name: customers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.customers (id, user_id, full_name, phone, email, address, loyalty_points, created_at) FROM stdin;
1	bfc8ddbd-98c5-46da-95ba-76c1e8e94b18	Đởm Triết	0979911670	thiemd779@gmail.com	\N	0	2026-01-19 15:04:10.929744+00
\.


--
-- TOC entry 4006 (class 0 OID 17721)
-- Dependencies: 387
-- Data for Name: expense_categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.expense_categories (id, name, description) FROM stdin;
1	Marketing	\N
\.


--
-- TOC entry 4008 (class 0 OID 17729)
-- Dependencies: 389
-- Data for Name: expenses; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.expenses (id, store_id, category_id, amount, expense_date, note, created_at) FROM stdin;
1	2	1	100000	2026-01-19	test	2026-01-19 16:20:08.324463+00
\.


--
-- TOC entry 3993 (class 0 OID 17602)
-- Dependencies: 374
-- Data for Name: inventory_batches; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.inventory_batches (id, store_id, variant_id, purchase_item_id, original_quantity, quantity_remaining, cost_price, created_at, batch_name, supplier_id) FROM stdin;
3	2	4	3	2	1	90500	2026-01-19 15:01:52.593982+00	\N	\N
1	1	2	1	2	1	90500	2026-01-19 13:46:54.335709+00	\N	\N
2	1	3	2	2	1	90500	2026-01-19 14:16:07.086943+00	\N	\N
\.


--
-- TOC entry 4004 (class 0 OID 17704)
-- Dependencies: 385
-- Data for Name: order_items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.order_items (id, order_id, variant_id, quantity, price_at_purchase, cogs_total) FROM stdin;
1	1	2	1	190000	90500
2	1	4	1	190000	90500
3	2	3	1	190000	90500
4	3	2	1	190000	90500
5	6	4	1	190000	90500
6	8	3	1	190000	90500
7	9	3	1	190000	90500
\.


--
-- TOC entry 4002 (class 0 OID 17674)
-- Dependencies: 383
-- Data for Name: orders; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.orders (id, code, customer_id, store_id, promotion_id, subtotal, discount_amount, shipping_fee, total_amount, payment_method, status, note, created_at, customer_name, customer_phone, customer_address, customer_email, shipping_carrier, shipping_tracking_code, payment_status, email) FROM stdin;
1	ORD-1768834973991	\N	\N	\N	380000	0	30000	410000	banking	shipping	\N	2026-01-19 15:02:53.991015+00	Đởm Triết	0979911670	15 Nguyễn Xuân Khoát	domquangminhtriet17@gmail.com	SPX	SPX1768834973.991015	unpaid	\N
2	ORD-1768835090217	\N	\N	\N	190000	0	30000	220000	banking	shipping	\N	2026-01-19 15:04:50.216778+00	Đởm Triết	0979911670	17 Nguyễn Xuân Khoát 	thiemd779@gmail.com	SPX	SPX1768835090.216778	unpaid	\N
8	ORD-1768836426119	\N	\N	\N	190000	0	30000	220000	banking	cancelled	\N	2026-01-19 15:27:06.118839+00	Đởm Triết	0979911670	15 NXK	thiemd779@gmail.com	SPX	SPX1768836426.118839	unpaid	\N
6	ORD-1768836333251	\N	\N	\N	190000	0	30000	220000	banking	cancelled	\N	2026-01-19 15:25:33.250503+00	Đởm Triết	0979911670	15 NXK	thiemd779@gmail.com	SPX	SPX1768836333.250503	unpaid	\N
3	ORD-1768836286716	\N	\N	\N	190000	0	30000	220000	banking	cancelled	\N	2026-01-19 15:24:46.716322+00	Đởm Triết	0979911670	15 NXK	thiemd779@gmail.com	SPX	SPX1768836286.716322	unpaid	\N
9	ORD-1768836570106	\N	\N	\N	190000	0	30000	220000	banking	cancelled	\N	2026-01-19 15:29:30.106057+00	Đởm Triết	0979911670	15 NXK	thiemd779@gmail.com	SPX	SPX1768836570.106057	unpaid	\N
\.


--
-- TOC entry 3985 (class 0 OID 17533)
-- Dependencies: 366
-- Data for Name: product_categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.product_categories (product_id, category_id) FROM stdin;
2	1
\.


--
-- TOC entry 3984 (class 0 OID 17522)
-- Dependencies: 365
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.products (id, name, slug, description, base_price, images, is_active, created_at, category_id) FROM stdin;
2	LAROSE CAMI	larose-cami	Áo Hai Dây Chiết Eo Ôm Body Brown LAROSE CAMI (áo 2 dây cổ tim có chiết eo & may viền giúp nâng phần ngực)\n\nMàu sắc: Trắng/Đen/ Vàng/ Nâu\n\n- Áo Hai Dây ôm body\n* Chất liệu: Thun\n*Thành Phần: 75% Nylon 25% Elastane\n* Đặt điểm: Độ co giãn 4 chiều cao, mặt vải mềm mịn, không nhão, không phai màu, thấm hút tốt.\n\n*LƯU Ý: Bảng size và hình ảnh mẫu chỉ mang tính chất tham khảo và có thể xê dịch 1-2cm.	200000	{https://dbuwgocouxlpxulnlajl.supabase.co/storage/v1/object/public/products/1768828435616-757383411.png}	t	2026-01-19 13:15:20.520197+00	\N
\.


--
-- TOC entry 3997 (class 0 OID 17637)
-- Dependencies: 378
-- Data for Name: promotions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.promotions (id, code, description, discount_type, discount_value, min_order_value, start_date, end_date, requires_account, is_active, usage_limit, used_count, max_discount_amount) FROM stdin;
\.


--
-- TOC entry 3991 (class 0 OID 17585)
-- Dependencies: 372
-- Data for Name: purchase_items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.purchase_items (id, purchase_order_id, variant_id, quantity, unit_cost) FROM stdin;
1	2	2	2	90500
2	3	3	2	90500
3	4	4	2	90500
\.


--
-- TOC entry 3989 (class 0 OID 17565)
-- Dependencies: 370
-- Data for Name: purchase_orders; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.purchase_orders (id, supplier_id, store_id, total_cost, note, purchase_date, code, status) FROM stdin;
1	2	1	181000	\N	2026-01-19 13:45:12.120981+00	\N	\N
2	2	1	181000	\N	2026-01-19 13:46:53.534091+00	\N	\N
3	2	1	181000	\N	2026-01-19 14:16:06.508877+00	\N	\N
4	3	2	181000	\N	2026-01-19 15:01:52.160286+00	\N	\N
\.


--
-- TOC entry 3978 (class 0 OID 17487)
-- Dependencies: 359
-- Data for Name: stores; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.stores (id, name, address, phone, is_active, created_at) FROM stdin;
1	Kho 15NXK	\N	\N	t	2026-01-19 13:38:55.850716+00
2	Test	\N	\N	t	2026-01-19 14:58:27.312318+00
\.


--
-- TOC entry 3982 (class 0 OID 17513)
-- Dependencies: 363
-- Data for Name: suppliers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.suppliers (id, name, created_at, phone, address) FROM stdin;
1	QLEE	2026-01-19 13:38:49.746345+00	\N	\N
2	Reset	2026-01-19 13:39:41.667611+00	\N	\N
3	Test	2026-01-19 14:58:23.142363+00	\N	\N
\.


--
-- TOC entry 3987 (class 0 OID 17549)
-- Dependencies: 368
-- Data for Name: variants; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.variants (id, product_id, sku, size, color, current_price, image_url, created_at, weight) FROM stdin;
2	2	A2STS	S	Trắng	190000	\N	2026-01-19 13:15:21.071732+00	500
3	2	A2SĐS	S	Đen	190000	\N	2026-01-19 13:15:21.071732+00	500
4	2	A2SVS	S	Vàng	190000	\N	2026-01-19 13:15:21.071732+00	500
5	2	A2SNS	S	Nâu	190000	\N	2026-01-19 13:15:21.071732+00	500
6	2	A2STM	M	Trắng	190000	\N	2026-01-19 13:15:21.071732+00	500
7	2	A2SĐM	M	Đen	190000	\N	2026-01-19 13:15:21.071732+00	500
8	2	A2SVM	M	Vàng	190000	\N	2026-01-19 13:15:21.071732+00	500
9	2	A2SNM	M	Nâu	190000	\N	2026-01-19 13:15:21.071732+00	500
\.


--
-- TOC entry 4051 (class 0 OID 0)
-- Dependencies: 398
-- Name: banners_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.banners_id_seq', 1, false);


--
-- TOC entry 4052 (class 0 OID 0)
-- Dependencies: 380
-- Name: cart_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.cart_items_id_seq', 1, false);


--
-- TOC entry 4053 (class 0 OID 0)
-- Dependencies: 360
-- Name: categories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.categories_id_seq', 1, true);


--
-- TOC entry 4054 (class 0 OID 0)
-- Dependencies: 390
-- Name: content_banners_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.content_banners_id_seq', 1, false);


--
-- TOC entry 4055 (class 0 OID 0)
-- Dependencies: 375
-- Name: customers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.customers_id_seq', 1, true);


--
-- TOC entry 4056 (class 0 OID 0)
-- Dependencies: 386
-- Name: expense_categories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.expense_categories_id_seq', 1, true);


--
-- TOC entry 4057 (class 0 OID 0)
-- Dependencies: 388
-- Name: expenses_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.expenses_id_seq', 1, true);


--
-- TOC entry 4058 (class 0 OID 0)
-- Dependencies: 373
-- Name: inventory_batches_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.inventory_batches_id_seq', 3, true);


--
-- TOC entry 4059 (class 0 OID 0)
-- Dependencies: 384
-- Name: order_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.order_items_id_seq', 7, true);


--
-- TOC entry 4060 (class 0 OID 0)
-- Dependencies: 382
-- Name: orders_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.orders_id_seq', 9, true);


--
-- TOC entry 4061 (class 0 OID 0)
-- Dependencies: 364
-- Name: products_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.products_id_seq', 3, true);


--
-- TOC entry 4062 (class 0 OID 0)
-- Dependencies: 377
-- Name: promotions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.promotions_id_seq', 1, false);


--
-- TOC entry 4063 (class 0 OID 0)
-- Dependencies: 371
-- Name: purchase_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.purchase_items_id_seq', 3, true);


--
-- TOC entry 4064 (class 0 OID 0)
-- Dependencies: 369
-- Name: purchase_orders_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.purchase_orders_id_seq', 4, true);


--
-- TOC entry 4065 (class 0 OID 0)
-- Dependencies: 358
-- Name: stores_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.stores_id_seq', 2, true);


--
-- TOC entry 4066 (class 0 OID 0)
-- Dependencies: 362
-- Name: suppliers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.suppliers_id_seq', 3, true);


--
-- TOC entry 4067 (class 0 OID 0)
-- Dependencies: 367
-- Name: variants_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.variants_id_seq', 10, true);


--
-- TOC entry 3793 (class 2606 OID 21625)
-- Name: banners banners_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.banners
    ADD CONSTRAINT banners_pkey PRIMARY KEY (id);


--
-- TOC entry 3779 (class 2606 OID 17662)
-- Name: cart_items cart_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cart_items
    ADD CONSTRAINT cart_items_pkey PRIMARY KEY (id);


--
-- TOC entry 3777 (class 2606 OID 17655)
-- Name: carts carts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.carts
    ADD CONSTRAINT carts_pkey PRIMARY KEY (user_id);


--
-- TOC entry 3745 (class 2606 OID 17504)
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- TOC entry 3747 (class 2606 OID 17506)
-- Name: categories categories_slug_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_slug_key UNIQUE (slug);


--
-- TOC entry 3791 (class 2606 OID 20157)
-- Name: content_banners content_banners_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_banners
    ADD CONSTRAINT content_banners_pkey PRIMARY KEY (id);


--
-- TOC entry 3770 (class 2606 OID 17634)
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- TOC entry 3787 (class 2606 OID 17727)
-- Name: expense_categories expense_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.expense_categories
    ADD CONSTRAINT expense_categories_pkey PRIMARY KEY (id);


--
-- TOC entry 3789 (class 2606 OID 17737)
-- Name: expenses expenses_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_pkey PRIMARY KEY (id);


--
-- TOC entry 3768 (class 2606 OID 17608)
-- Name: inventory_batches inventory_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_pkey PRIMARY KEY (id);


--
-- TOC entry 3785 (class 2606 OID 17709)
-- Name: order_items order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (id);


--
-- TOC entry 3781 (class 2606 OID 17687)
-- Name: orders orders_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_code_key UNIQUE (code);


--
-- TOC entry 3783 (class 2606 OID 17685)
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- TOC entry 3755 (class 2606 OID 17537)
-- Name: product_categories product_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_categories
    ADD CONSTRAINT product_categories_pkey PRIMARY KEY (product_id, category_id);


--
-- TOC entry 3751 (class 2606 OID 17530)
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- TOC entry 3753 (class 2606 OID 17532)
-- Name: products products_slug_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_slug_key UNIQUE (slug);


--
-- TOC entry 3773 (class 2606 OID 17649)
-- Name: promotions promotions_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promotions
    ADD CONSTRAINT promotions_code_key UNIQUE (code);


--
-- TOC entry 3775 (class 2606 OID 17647)
-- Name: promotions promotions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promotions
    ADD CONSTRAINT promotions_pkey PRIMARY KEY (id);


--
-- TOC entry 3765 (class 2606 OID 17590)
-- Name: purchase_items purchase_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_items
    ADD CONSTRAINT purchase_items_pkey PRIMARY KEY (id);


--
-- TOC entry 3761 (class 2606 OID 21610)
-- Name: purchase_orders purchase_orders_code_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_code_unique UNIQUE (code);


--
-- TOC entry 3763 (class 2606 OID 17573)
-- Name: purchase_orders purchase_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_pkey PRIMARY KEY (id);


--
-- TOC entry 3743 (class 2606 OID 17495)
-- Name: stores stores_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stores
    ADD CONSTRAINT stores_pkey PRIMARY KEY (id);


--
-- TOC entry 3749 (class 2606 OID 17520)
-- Name: suppliers suppliers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_pkey PRIMARY KEY (id);


--
-- TOC entry 3757 (class 2606 OID 17556)
-- Name: variants variants_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.variants
    ADD CONSTRAINT variants_pkey PRIMARY KEY (id);


--
-- TOC entry 3759 (class 2606 OID 17558)
-- Name: variants variants_sku_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.variants
    ADD CONSTRAINT variants_sku_key UNIQUE (sku);


--
-- TOC entry 3771 (class 1259 OID 17635)
-- Name: idx_customer_phone; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_customer_phone ON public.customers USING btree (phone);


--
-- TOC entry 3766 (class 1259 OID 17624)
-- Name: idx_inventory_fifo; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_inventory_fifo ON public.inventory_batches USING btree (store_id, variant_id, created_at);


--
-- TOC entry 3806 (class 2606 OID 17663)
-- Name: cart_items cart_items_cart_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cart_items
    ADD CONSTRAINT cart_items_cart_id_fkey FOREIGN KEY (cart_id) REFERENCES public.carts(user_id) ON DELETE CASCADE;


--
-- TOC entry 3807 (class 2606 OID 17668)
-- Name: cart_items cart_items_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cart_items
    ADD CONSTRAINT cart_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.variants(id);


--
-- TOC entry 3794 (class 2606 OID 17507)
-- Name: categories categories_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.categories(id) ON DELETE SET NULL;


--
-- TOC entry 3813 (class 2606 OID 17743)
-- Name: expenses expenses_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.expense_categories(id);


--
-- TOC entry 3814 (class 2606 OID 17738)
-- Name: expenses expenses_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id);


--
-- TOC entry 3802 (class 2606 OID 17619)
-- Name: inventory_batches inventory_batches_purchase_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_purchase_item_id_fkey FOREIGN KEY (purchase_item_id) REFERENCES public.purchase_items(id);


--
-- TOC entry 3803 (class 2606 OID 17609)
-- Name: inventory_batches inventory_batches_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id);


--
-- TOC entry 3804 (class 2606 OID 17883)
-- Name: inventory_batches inventory_batches_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id);


--
-- TOC entry 3805 (class 2606 OID 17614)
-- Name: inventory_batches inventory_batches_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.variants(id);


--
-- TOC entry 3811 (class 2606 OID 17710)
-- Name: order_items order_items_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- TOC entry 3812 (class 2606 OID 17715)
-- Name: order_items order_items_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.variants(id);


--
-- TOC entry 3808 (class 2606 OID 17688)
-- Name: orders orders_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- TOC entry 3809 (class 2606 OID 17698)
-- Name: orders orders_promotion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_promotion_id_fkey FOREIGN KEY (promotion_id) REFERENCES public.promotions(id);


--
-- TOC entry 3810 (class 2606 OID 17693)
-- Name: orders orders_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id);


--
-- TOC entry 3795 (class 2606 OID 17543)
-- Name: product_categories product_categories_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_categories
    ADD CONSTRAINT product_categories_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id) ON DELETE CASCADE;


--
-- TOC entry 3796 (class 2606 OID 17538)
-- Name: product_categories product_categories_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_categories
    ADD CONSTRAINT product_categories_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- TOC entry 3800 (class 2606 OID 17591)
-- Name: purchase_items purchase_items_purchase_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_items
    ADD CONSTRAINT purchase_items_purchase_order_id_fkey FOREIGN KEY (purchase_order_id) REFERENCES public.purchase_orders(id) ON DELETE CASCADE;


--
-- TOC entry 3801 (class 2606 OID 17596)
-- Name: purchase_items purchase_items_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_items
    ADD CONSTRAINT purchase_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.variants(id);


--
-- TOC entry 3798 (class 2606 OID 17579)
-- Name: purchase_orders purchase_orders_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id);


--
-- TOC entry 3799 (class 2606 OID 17574)
-- Name: purchase_orders purchase_orders_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id);


--
-- TOC entry 3797 (class 2606 OID 17559)
-- Name: variants variants_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.variants
    ADD CONSTRAINT variants_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- TOC entry 3973 (class 3256 OID 20159)
-- Name: content_banners Admin Manage Banners; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin Manage Banners" ON public.content_banners USING ((auth.role() = 'authenticated'::text));


--
-- TOC entry 3971 (class 3256 OID 17847)
-- Name: products Enable read access for all users; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Enable read access for all users" ON public.products FOR SELECT USING (true);


--
-- TOC entry 3972 (class 3256 OID 20158)
-- Name: content_banners Public Read Banners; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Banners" ON public.content_banners FOR SELECT USING (true);


--
-- TOC entry 3969 (class 3256 OID 17849)
-- Name: categories Public Read Categories; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Categories" ON public.categories FOR SELECT USING (true);


--
-- TOC entry 3970 (class 3256 OID 17850)
-- Name: product_categories Public Read Product Categories; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Product Categories" ON public.product_categories FOR SELECT USING (true);


--
-- TOC entry 3968 (class 3256 OID 17848)
-- Name: variants Public Read Variants; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Variants" ON public.variants FOR SELECT USING (true);


--
-- TOC entry 3963 (class 0 OID 17497)
-- Dependencies: 361
-- Name: categories; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 3967 (class 0 OID 20148)
-- Dependencies: 391
-- Name: content_banners; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.content_banners ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 3965 (class 0 OID 17533)
-- Dependencies: 366
-- Name: product_categories; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.product_categories ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 3964 (class 0 OID 17522)
-- Dependencies: 365
-- Name: products; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 3966 (class 0 OID 17549)
-- Dependencies: 368
-- Name: variants; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.variants ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4018 (class 0 OID 0)
-- Dependencies: 50
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE USAGE ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO PUBLIC;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- TOC entry 4019 (class 0 OID 0)
-- Dependencies: 381
-- Name: TABLE cart_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.cart_items TO service_role;
GRANT SELECT ON TABLE public.cart_items TO anon;


--
-- TOC entry 4020 (class 0 OID 0)
-- Dependencies: 380
-- Name: SEQUENCE cart_items_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.cart_items_id_seq TO service_role;


--
-- TOC entry 4021 (class 0 OID 0)
-- Dependencies: 379
-- Name: TABLE carts; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.carts TO service_role;
GRANT SELECT ON TABLE public.carts TO anon;


--
-- TOC entry 4022 (class 0 OID 0)
-- Dependencies: 361
-- Name: TABLE categories; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.categories TO service_role;
GRANT SELECT ON TABLE public.categories TO anon;


--
-- TOC entry 4023 (class 0 OID 0)
-- Dependencies: 360
-- Name: SEQUENCE categories_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.categories_id_seq TO service_role;


--
-- TOC entry 4024 (class 0 OID 0)
-- Dependencies: 376
-- Name: TABLE customers; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.customers TO service_role;
GRANT SELECT ON TABLE public.customers TO anon;
GRANT SELECT,UPDATE ON TABLE public.customers TO authenticated;


--
-- TOC entry 4025 (class 0 OID 0)
-- Dependencies: 375
-- Name: SEQUENCE customers_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.customers_id_seq TO service_role;


--
-- TOC entry 4026 (class 0 OID 0)
-- Dependencies: 387
-- Name: TABLE expense_categories; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.expense_categories TO service_role;
GRANT SELECT ON TABLE public.expense_categories TO anon;


--
-- TOC entry 4027 (class 0 OID 0)
-- Dependencies: 386
-- Name: SEQUENCE expense_categories_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.expense_categories_id_seq TO service_role;


--
-- TOC entry 4028 (class 0 OID 0)
-- Dependencies: 389
-- Name: TABLE expenses; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.expenses TO service_role;
GRANT SELECT ON TABLE public.expenses TO anon;


--
-- TOC entry 4029 (class 0 OID 0)
-- Dependencies: 388
-- Name: SEQUENCE expenses_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.expenses_id_seq TO service_role;


--
-- TOC entry 4030 (class 0 OID 0)
-- Dependencies: 374
-- Name: TABLE inventory_batches; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.inventory_batches TO service_role;
GRANT SELECT ON TABLE public.inventory_batches TO anon;


--
-- TOC entry 4031 (class 0 OID 0)
-- Dependencies: 373
-- Name: SEQUENCE inventory_batches_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.inventory_batches_id_seq TO service_role;


--
-- TOC entry 4032 (class 0 OID 0)
-- Dependencies: 385
-- Name: TABLE order_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.order_items TO service_role;
GRANT SELECT ON TABLE public.order_items TO anon;


--
-- TOC entry 4033 (class 0 OID 0)
-- Dependencies: 384
-- Name: SEQUENCE order_items_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.order_items_id_seq TO service_role;


--
-- TOC entry 4034 (class 0 OID 0)
-- Dependencies: 383
-- Name: TABLE orders; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.orders TO service_role;
GRANT SELECT ON TABLE public.orders TO anon;


--
-- TOC entry 4035 (class 0 OID 0)
-- Dependencies: 382
-- Name: SEQUENCE orders_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.orders_id_seq TO service_role;


--
-- TOC entry 4036 (class 0 OID 0)
-- Dependencies: 366
-- Name: TABLE product_categories; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.product_categories TO service_role;
GRANT SELECT ON TABLE public.product_categories TO anon;


--
-- TOC entry 4037 (class 0 OID 0)
-- Dependencies: 365
-- Name: TABLE products; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.products TO service_role;
GRANT SELECT ON TABLE public.products TO anon;


--
-- TOC entry 4038 (class 0 OID 0)
-- Dependencies: 364
-- Name: SEQUENCE products_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.products_id_seq TO service_role;


--
-- TOC entry 4039 (class 0 OID 0)
-- Dependencies: 378
-- Name: TABLE promotions; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.promotions TO service_role;
GRANT SELECT ON TABLE public.promotions TO anon;


--
-- TOC entry 4040 (class 0 OID 0)
-- Dependencies: 377
-- Name: SEQUENCE promotions_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.promotions_id_seq TO service_role;


--
-- TOC entry 4041 (class 0 OID 0)
-- Dependencies: 372
-- Name: TABLE purchase_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.purchase_items TO service_role;
GRANT SELECT ON TABLE public.purchase_items TO anon;


--
-- TOC entry 4042 (class 0 OID 0)
-- Dependencies: 371
-- Name: SEQUENCE purchase_items_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.purchase_items_id_seq TO service_role;


--
-- TOC entry 4043 (class 0 OID 0)
-- Dependencies: 370
-- Name: TABLE purchase_orders; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.purchase_orders TO service_role;
GRANT SELECT ON TABLE public.purchase_orders TO anon;


--
-- TOC entry 4044 (class 0 OID 0)
-- Dependencies: 369
-- Name: SEQUENCE purchase_orders_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.purchase_orders_id_seq TO service_role;


--
-- TOC entry 4045 (class 0 OID 0)
-- Dependencies: 359
-- Name: TABLE stores; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.stores TO service_role;
GRANT SELECT ON TABLE public.stores TO anon;


--
-- TOC entry 4046 (class 0 OID 0)
-- Dependencies: 358
-- Name: SEQUENCE stores_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.stores_id_seq TO service_role;


--
-- TOC entry 4047 (class 0 OID 0)
-- Dependencies: 363
-- Name: TABLE suppliers; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.suppliers TO service_role;
GRANT SELECT ON TABLE public.suppliers TO anon;


--
-- TOC entry 4048 (class 0 OID 0)
-- Dependencies: 362
-- Name: SEQUENCE suppliers_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.suppliers_id_seq TO service_role;


--
-- TOC entry 4049 (class 0 OID 0)
-- Dependencies: 368
-- Name: TABLE variants; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.variants TO service_role;
GRANT SELECT ON TABLE public.variants TO anon;


--
-- TOC entry 4050 (class 0 OID 0)
-- Dependencies: 367
-- Name: SEQUENCE variants_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.variants_id_seq TO service_role;


-- Completed on 2026-01-20 19:29:13

--
-- PostgreSQL database dump complete
--

