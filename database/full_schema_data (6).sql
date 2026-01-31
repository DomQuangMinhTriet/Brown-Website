--
-- PostgreSQL database dump
--

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.5

-- Started on 2026-01-31 10:13:08

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
-- TOC entry 506 (class 1255 OID 21750)
-- Name: create_order_transaction(bigint, jsonb, text, numeric, numeric, text, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_order_transaction(p_customer_id bigint, p_customer_info jsonb, p_payment_method text, p_shipping_fee numeric, p_discount_amount numeric, p_voucher_code text, p_items jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
    v_order_id BIGINT;
    v_order_code TEXT;
    v_subtotal NUMERIC := 0;
    v_total_amount NUMERIC;
    v_item JSONB;
    v_variant_id BIGINT;
    v_buy_qty INT;
    v_real_price NUMERIC;
    v_total_stock INT;
    v_promotion_id BIGINT;
    v_needed_qty INT;
    v_batch RECORD;
    v_take_qty INT;
    v_item_cogs NUMERIC;
BEGIN
    v_order_code := 'ORD-' || FLOOR(RANDOM() * 8999 + 1000) || CAST(EXTRACT(EPOCH FROM NOW()) AS BIGINT);

    IF p_voucher_code IS NOT NULL AND p_voucher_code <> '' THEN
        SELECT id INTO v_promotion_id FROM promotions WHERE code = p_voucher_code LIMIT 1;
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_variant_id := CAST(v_item->>'variant_id' AS BIGINT);
        v_buy_qty := CAST(v_item->>'quantity' AS INT);
        SELECT COALESCE(v.current_price, p.base_price) INTO v_real_price
        FROM variants v JOIN products p ON v.product_id = p.id WHERE v.id = v_variant_id;
        IF v_real_price IS NULL THEN RAISE EXCEPTION 'Sản phẩm % không tồn tại', v_variant_id; END IF;
        v_subtotal := v_subtotal + (v_buy_qty * v_real_price);
    END LOOP;

    v_total_amount := v_subtotal + p_shipping_fee - p_discount_amount;
    IF v_total_amount < 0 THEN v_total_amount := 0; END IF;

    -- [ĐOẠN QUAN TRỌNG NHẤT: INSERT ID QUẬN/HUYỆN]
    INSERT INTO orders (
        code, customer_id, 
        customer_name, customer_phone, customer_email, customer_address,
        customer_district_id,       -- Cột này phải có dữ liệu
        customer_ward_code,         -- Cột này phải có dữ liệu
        payment_method, status, payment_status,
        subtotal, discount_amount, shipping_fee, total_amount, 
        promotion_id, shipping_tracking_code, created_at
    ) VALUES (
        v_order_code, p_customer_id,
        p_customer_info->>'name', 
        p_customer_info->>'phone', 
        p_customer_info->>'email', 
        p_customer_info->>'address',
        CAST(p_customer_info->>'district_id' AS INT), -- Lấy từ JSON Frontend gửi
        p_customer_info->>'ward_code',                -- Lấy từ JSON Frontend gửi
        p_payment_method, 'pending', 'unpaid',
        v_subtotal, p_discount_amount, p_shipping_fee, v_total_amount,
        v_promotion_id, NULL, NOW()
    ) RETURNING id INTO v_order_id;

    -- Xử lý kho (giữ nguyên logic của bạn)
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_variant_id := CAST(v_item->>'variant_id' AS BIGINT);
        v_buy_qty := CAST(v_item->>'quantity' AS INT);
        SELECT COALESCE(v.current_price, p.base_price) INTO v_real_price
        FROM variants v JOIN products p ON v.product_id = p.id WHERE v.id = v_variant_id;
        
        v_needed_qty := v_buy_qty;
        v_item_cogs := 0;
        
        FOR v_batch IN SELECT * FROM inventory_batches WHERE variant_id = v_variant_id AND quantity_remaining > 0 ORDER BY created_at ASC FOR UPDATE 
        LOOP
            IF v_needed_qty > 0 THEN
                IF v_batch.quantity_remaining >= v_needed_qty THEN v_take_qty := v_needed_qty;
                ELSE v_take_qty := v_batch.quantity_remaining; END IF;
                UPDATE inventory_batches SET quantity_remaining = quantity_remaining - v_take_qty WHERE id = v_batch.id;
                v_item_cogs := v_item_cogs + (v_take_qty * v_batch.cost_price);
                v_needed_qty := v_needed_qty - v_take_qty;
            END IF;
        END LOOP;
        
        INSERT INTO order_items (order_id, variant_id, quantity, price_at_purchase, cogs_total) 
        VALUES (v_order_id, v_variant_id, v_buy_qty, v_real_price, v_item_cogs);
    END LOOP;

    RETURN jsonb_build_object('success', true, 'order_id', v_order_id, 'order_code', v_order_code);
END;
$$;


ALTER FUNCTION public.create_order_transaction(p_customer_id bigint, p_customer_info jsonb, p_payment_method text, p_shipping_fee numeric, p_discount_amount numeric, p_voucher_code text, p_items jsonb) OWNER TO postgres;

--
-- TOC entry 490 (class 1255 OID 20107)
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
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

--
-- TOC entry 502 (class 1255 OID 21695)
-- Name: restore_inventory_on_cancel(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.restore_inventory_on_cancel() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_item RECORD;
    v_target_batch_id BIGINT;
BEGIN
    -- Chỉ chạy logic khi trạng thái chuyển từ 'khác cancelled' sang 'cancelled'
    IF NEW.status = 'cancelled' AND OLD.status <> 'cancelled' THEN
        
        -- Lặp qua tất cả sản phẩm trong đơn hàng bị hủy
        FOR v_item IN 
            SELECT variant_id, quantity 
            FROM order_items 
            WHERE order_id = NEW.id
        LOOP
            -- CHIẾN LƯỢC HOÀN KHO:
            -- Tìm lô hàng (Batch) nhập gần đây nhất của sản phẩm đó để cộng lại số lượng.
            -- (Ta chọn lô mới nhất để đảm bảo hàng luôn có date mới hoặc đơn giản là logic LIFO cho hàng trả về)
            
            SELECT id INTO v_target_batch_id
            FROM inventory_batches
            WHERE variant_id = v_item.variant_id
            ORDER BY created_at DESC
            LIMIT 1;

            -- Nếu tìm thấy lô hàng, thực hiện cộng lại kho
            IF v_target_batch_id IS NOT NULL THEN
                UPDATE inventory_batches
                SET quantity_remaining = quantity_remaining + v_item.quantity
                WHERE id = v_target_batch_id;
            ELSE
                -- Trường hợp hiếm: Không còn lô nào tồn tại (đã bị xóa), 
                -- ta có thể chọn tạo lô mới hoặc bỏ qua (ở đây ta chọn ghi log cảnh báo)
                RAISE WARNING 'Không tìm thấy lô hàng để hoàn kho cho variant_id: %', v_item.variant_id;
            END IF;
        END LOOP;
        
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.restore_inventory_on_cancel() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 426 (class 1259 OID 21617)
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
-- TOC entry 425 (class 1259 OID 21616)
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
-- TOC entry 414 (class 1259 OID 17657)
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
-- TOC entry 413 (class 1259 OID 17656)
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
-- TOC entry 412 (class 1259 OID 17650)
-- Name: carts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.carts (
    user_id uuid NOT NULL,
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.carts OWNER TO postgres;

--
-- TOC entry 395 (class 1259 OID 17497)
-- Name: categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.categories (
    id bigint NOT NULL,
    name text NOT NULL,
    slug text NOT NULL,
    parent_id bigint,
    created_at timestamp with time zone DEFAULT now(),
    is_visible_on_home boolean DEFAULT true
);


ALTER TABLE public.categories OWNER TO postgres;

--
-- TOC entry 394 (class 1259 OID 17496)
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
-- TOC entry 424 (class 1259 OID 20148)
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
-- TOC entry 423 (class 1259 OID 20147)
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
-- TOC entry 409 (class 1259 OID 17626)
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
    created_at timestamp with time zone DEFAULT now(),
    role text DEFAULT 'user'::text,
    avatar_url text
);


ALTER TABLE public.customers OWNER TO postgres;

--
-- TOC entry 408 (class 1259 OID 17625)
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
-- TOC entry 420 (class 1259 OID 17721)
-- Name: expense_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.expense_categories (
    id bigint NOT NULL,
    name text NOT NULL,
    description text
);


ALTER TABLE public.expense_categories OWNER TO postgres;

--
-- TOC entry 419 (class 1259 OID 17720)
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
-- TOC entry 422 (class 1259 OID 17729)
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
-- TOC entry 421 (class 1259 OID 17728)
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
-- TOC entry 407 (class 1259 OID 17602)
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
    is_adjustment boolean DEFAULT false,
    notes text
);


ALTER TABLE public.inventory_batches OWNER TO postgres;

--
-- TOC entry 406 (class 1259 OID 17601)
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
-- TOC entry 418 (class 1259 OID 17704)
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
-- TOC entry 417 (class 1259 OID 17703)
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
-- TOC entry 416 (class 1259 OID 17674)
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
    email text,
    customer_district_id integer,
    customer_ward_code text
);


ALTER TABLE public.orders OWNER TO postgres;

--
-- TOC entry 415 (class 1259 OID 17673)
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
-- TOC entry 429 (class 1259 OID 23128)
-- Name: product_collections; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.product_collections (
    product_id bigint NOT NULL,
    category_id bigint NOT NULL
);


ALTER TABLE public.product_collections OWNER TO postgres;

--
-- TOC entry 399 (class 1259 OID 17522)
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
    category_id bigint,
    size_chart_url text
);


ALTER TABLE public.products OWNER TO postgres;

--
-- TOC entry 398 (class 1259 OID 17521)
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
-- TOC entry 411 (class 1259 OID 17637)
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
-- TOC entry 410 (class 1259 OID 17636)
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
-- TOC entry 405 (class 1259 OID 17585)
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
-- TOC entry 404 (class 1259 OID 17584)
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
-- TOC entry 403 (class 1259 OID 17565)
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
-- TOC entry 402 (class 1259 OID 17564)
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
-- TOC entry 393 (class 1259 OID 17487)
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
-- TOC entry 392 (class 1259 OID 17486)
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
-- TOC entry 397 (class 1259 OID 17513)
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
-- TOC entry 396 (class 1259 OID 17512)
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
-- TOC entry 401 (class 1259 OID 17549)
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
-- TOC entry 400 (class 1259 OID 17548)
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
-- TOC entry 4087 (class 0 OID 21617)
-- Dependencies: 426
-- Data for Name: banners; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.banners (id, title, image_url, link_url, is_active, created_at) FROM stdin;
\.


--
-- TOC entry 4075 (class 0 OID 17657)
-- Dependencies: 414
-- Data for Name: cart_items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.cart_items (id, cart_id, variant_id, quantity) FROM stdin;
\.


--
-- TOC entry 4073 (class 0 OID 17650)
-- Dependencies: 412
-- Data for Name: carts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.carts (user_id, updated_at) FROM stdin;
\.


--
-- TOC entry 4056 (class 0 OID 17497)
-- Dependencies: 395
-- Data for Name: categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.categories (id, name, slug, parent_id, created_at, is_visible_on_home) FROM stdin;
1	TOPS	tops	\N	2026-01-26 13:33:39.51621+00	t
2	BOTTOMS	bottoms	\N	2026-01-26 14:07:55.177475+00	t
3	BIKINI	bikini	\N	2026-01-26 14:29:28.485714+00	t
4	JEANS	jeans	\N	2026-01-27 08:56:56.151804+00	f
\.


--
-- TOC entry 4085 (class 0 OID 20148)
-- Dependencies: 424
-- Data for Name: content_banners; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.content_banners (id, title, image_url, link_to, display_order, is_active, created_at) FROM stdin;
4	BROWN	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769145/brown_migration/nukinhe2ozewpdgbgrag.webp		0	t	2026-01-27 10:29:56.871449+00
\.


--
-- TOC entry 4070 (class 0 OID 17626)
-- Dependencies: 409
-- Data for Name: customers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.customers (id, user_id, full_name, phone, email, address, loyalty_points, created_at, role, avatar_url) FROM stdin;
1	ec819d8a-eea4-457a-b6fb-bcd522478d40	Admin Brown	0900000000	brownvn25@gmail.com	\N	0	2026-01-26 15:45:19.754264+00	admin	\N
2	\N	Ngọc 	0967515969	\N	Midtown The Peak M8 block A đường 15 phường tân phú q7	0	2026-01-27 10:24:11.339587+00	user	\N
3	\N	Kỳ Kỳ	0708083054	\N	214/C45 Nguyễn Trãi, phường Nguyễn Cư Trinh, Quận 1	0	2026-01-27 16:40:34.019692+00	user	\N
4	\N	Hân Kitty Phạm	0325225854	phamngochan9694@gmail.com	06 Song Hàng An Phú Quận 2 cũ	0	2026-01-28 17:18:52.731632+00	user	\N
5	\N	Đởm Triết	0979911670	domquangminhtriet17@gmail.com	15 NXK	0	2026-01-28 17:24:52.633655+00	user	\N
6	9c289498-3269-4410-9fb1-433113fada0f	Kunthida 	0643320919	tookkie678@gmail.com	\N	0	2026-01-29 12:41:09.884045+00	user	\N
7	\N	Anh thư	0967849849	hinhanhthu0197@gmail.com	9/1b xô viết nghệ tĩnh 	0	2026-01-30 12:56:31.132347+00	user	\N
8	\N	Lu Bu Tông	0881718137	jamaica@buchaby.com	12 Lộp Chộp	0	2026-01-30 13:43:43.246598+00	user	\N
9	\N	Nguyễn Kế Châu Anh	0911066568	jenninguyenke@gmail.com	Sky89, 89 Lê Thị Chợ, Quận 7, TPHCM	0	2026-01-30 15:50:57.413192+00	user	\N
\.


--
-- TOC entry 4081 (class 0 OID 17721)
-- Dependencies: 420
-- Data for Name: expense_categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.expense_categories (id, name, description) FROM stdin;
\.


--
-- TOC entry 4083 (class 0 OID 17729)
-- Dependencies: 422
-- Data for Name: expenses; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.expenses (id, store_id, category_id, amount, expense_date, note, created_at) FROM stdin;
\.


--
-- TOC entry 4068 (class 0 OID 17602)
-- Dependencies: 407
-- Data for Name: inventory_batches; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.inventory_batches (id, store_id, variant_id, purchase_item_id, original_quantity, quantity_remaining, cost_price, created_at, batch_name, supplier_id, is_adjustment, notes) FROM stdin;
5	1	101	5	20	20	100000	2026-01-27 10:01:29.522212+00	\N	\N	f	\N
6	1	100	6	15	15	115000	2026-01-27 10:01:52.209441+00	\N	\N	f	\N
11	1	92	11	10	10	100000	2026-01-27 10:07:18.342224+00	\N	\N	f	\N
14	1	95	14	10	10	100000	2026-01-27 10:08:02.881817+00	\N	\N	f	\N
15	1	98	15	10	10	100000	2026-01-27 10:08:18.465898+00	\N	\N	f	\N
16	1	98	16	10	10	100000	2026-01-27 10:08:20.964716+00	\N	\N	f	\N
17	1	99	17	10	10	100000	2026-01-27 10:08:40.495591+00	\N	\N	f	\N
19	1	89	19	15	15	150000	2026-01-27 10:09:47.053578+00	\N	\N	f	\N
20	1	90	20	22	22	150000	2026-01-27 10:10:00.550071+00	\N	\N	f	\N
21	1	91	21	17	17	150000	2026-01-27 10:10:14.78215+00	\N	\N	f	\N
23	1	79	23	16	16	100000	2026-01-27 10:11:14.297816+00	\N	\N	f	\N
25	1	81	25	17	17	100000	2026-01-27 10:11:46.289523+00	\N	\N	f	\N
26	1	82	26	19	19	100000	2026-01-27 10:12:18.200379+00	\N	\N	f	\N
27	1	82	27	19	19	100000	2026-01-27 10:12:19.893779+00	\N	\N	f	\N
29	1	84	29	22	22	100000	2026-01-27 10:12:45.700504+00	\N	\N	f	\N
30	1	85	30	19	19	100000	2026-01-27 10:12:58.541798+00	\N	\N	f	\N
31	1	86	31	22	22	100000	2026-01-27 10:13:12.558445+00	\N	\N	f	\N
33	1	76	33	14	14	100000	2026-01-27 10:14:51.579802+00	\N	\N	f	\N
35	1	78	35	4	4	100000	2026-01-27 10:15:24.43308+00	\N	\N	f	\N
36	1	47	36	7	7	100000	2026-01-27 10:15:45.866217+00	\N	\N	f	\N
37	1	48	37	1	1	100000	2026-01-27 10:16:06.461412+00	\N	\N	f	\N
38	1	49	38	10	10	100000	2026-01-27 10:16:27.031207+00	\N	\N	f	\N
39	1	51	39	6	6	100000	2026-01-27 10:16:40.435187+00	\N	\N	f	\N
40	1	52	40	6	6	100000	2026-01-27 10:16:54.447379+00	\N	\N	f	\N
41	1	46	41	11	11	60000	2026-01-27 10:17:21.810722+00	\N	\N	f	\N
42	1	45	42	12	12	60000	2026-01-27 10:17:44.344532+00	\N	\N	f	\N
43	1	112	43	6	6	160000	2026-01-27 10:18:56.123022+00	\N	\N	f	\N
44	1	36	44	15	15	100000	2026-01-27 10:19:17.095331+00	\N	\N	f	\N
45	1	33	45	11	11	100000	2026-01-27 10:19:56.877953+00	\N	\N	f	\N
46	1	27	46	6	6	100000	2026-01-27 10:20:13.823501+00	\N	\N	f	\N
47	1	28	47	4	4	100000	2026-01-27 10:20:24.283608+00	\N	\N	f	\N
48	1	69	48	5	5	100000	2026-01-27 10:20:41.489582+00	\N	\N	f	\N
49	1	70	49	5	5	100000	2026-01-27 10:20:51.315734+00	\N	\N	f	\N
50	1	71	50	19	19	100000	2026-01-27 10:21:14.166264+00	\N	\N	f	\N
51	1	72	51	2	2	100000	2026-01-27 10:21:26.84691+00	\N	\N	f	\N
52	1	24	52	17	17	100000	2026-01-27 10:21:52.40757+00	\N	\N	f	\N
53	1	74	53	9	9	100000	2026-01-27 10:23:03.856962+00	\N	\N	f	\N
34	1	77	34	1	0	100000	2026-01-27 10:15:07.074612+00	\N	\N	f	\N
58	1	101	\N	-1	-1	100000	2026-01-28 12:24:06.368821+00	\N	\N	t	Cập nhật trực tiếp
61	1	101	\N	-2	2	100000	2026-01-28 12:54:59.002217+00	\N	\N	t	Cập nhật trực tiếp
70	1	77	\N	3	3	100000	2026-01-28 16:01:33.893814+00	\N	\N	t	Điều chỉnh nhanh tại Admin
24	1	80	24	14	14	100000	2026-01-27 10:11:27.589533+00	\N	\N	f	\N
59	1	101	54	1	1	100000	2026-01-28 12:38:14.70695+00	\N	\N	f	\N
69	1	23	56	30	30	100000	2026-01-28 15:49:44.066223+00	\N	\N	f	\N
71	1	77	57	20	20	100000	2026-01-28 16:02:18.785583+00	\N	\N	f	\N
56	1	101	\N	-1	-1	100000	2026-01-28 12:23:54.854373+00	\N	\N	t	Điều chỉnh nhanh tại Admin
57	1	101	\N	-1	-1	100000	2026-01-28 12:23:54.887698+00	\N	\N	t	Điều chỉnh nhanh tại Admin
68	1	73	55	80	80	100000	2026-01-28 15:45:41.518783+00	\N	\N	f	\N
62	1	87	\N	-1	1	120000	2026-01-28 15:01:48.502619+00	\N	\N	t	Điều chỉnh nhanh tại Admin
72	1	102	\N	2	2	150000	2026-01-28 16:25:18.145996+00	\N	\N	t	Điều chỉnh nhanh tại Admin
65	1	78	\N	1	1	100000	2026-01-28 15:43:26.149321+00	\N	\N	t	Điều chỉnh nhanh tại Admin
66	1	78	\N	-1	-1	100000	2026-01-28 15:43:46.781045+00	\N	\N	t	Điều chỉnh nhanh tại Admin
67	1	78	\N	1	1	100000	2026-01-28 15:44:09.052341+00	\N	\N	t	Điều chỉnh nhanh tại Admin
63	1	35	\N	-10	-10	100000	2026-01-28 15:06:04.077674+00	\N	\N	t	Điều chỉnh nhanh tại Admin
64	1	50	\N	10	10	100000	2026-01-28 15:41:43.744138+00	\N	\N	t	Điều chỉnh nhanh tại Admin
8	1	97	8	9	7	100000	2026-01-27 10:06:55.273689+00	\N	\N	f	\N
74	1	35	\N	1	1	100000	2026-01-28 16:27:54.272133+00	\N	\N	t	Điều chỉnh nhanh tại Admin
4	1	101	4	20	1	100000	2026-01-27 10:01:27.589277+00	\N	\N	f	\N
75	1	93	\N	1	1	100000	2026-01-28 16:29:17.826971+00	\N	\N	t	Điều chỉnh nhanh tại Admin
12	1	93	12	10	9	100000	2026-01-27 10:07:34.62482+00	\N	\N	f	\N
76	1	94	\N	2	2	100000	2026-01-28 16:29:30.557113+00	\N	\N	t	Điều chỉnh nhanh tại Admin
2	1	35	2	10	9	100000	2026-01-26 16:20:55.194128+00	\N	\N	f	\N
32	1	75	32	14	15	100000	2026-01-27 10:14:36.713263+00	\N	\N	f	\N
77	1	94	\N	1	1	100000	2026-01-28 16:34:09.608799+00	\N	\N	t	Điều chỉnh nhanh tại Admin
13	1	94	13	10	7	100000	2026-01-27 10:07:48.046742+00	\N	\N	f	\N
22	1	87	22	10	9	120000	2026-01-27 10:10:42.054529+00	\N	\N	f	\N
3	1	102	3	6	4	150000	2026-01-27 10:01:01.964848+00	\N	\N	f	\N
73	1	102	\N	1	3	150000	2026-01-28 16:27:07.858101+00	\N	\N	t	Điều chỉnh nhanh tại Admin
9	1	97	9	9	11	100000	2026-01-27 10:06:56.088172+00	\N	\N	f	\N
18	1	88	18	15	16	150000	2026-01-27 10:09:29.712624+00	\N	\N	f	\N
10	1	92	10	10	9	100000	2026-01-27 10:07:17.134568+00	\N	\N	f	\N
7	1	96	7	22	23	100000	2026-01-27 10:05:17.272177+00	\N	\N	f	\N
60	1	92	\N	1	2	100000	2026-01-28 12:38:23.864251+00	\N	\N	t	Cập nhật trực tiếp
28	1	83	28	14	13	100000	2026-01-27 10:12:33.646+00	\N	\N	f	\N
\.


--
-- TOC entry 4079 (class 0 OID 17704)
-- Dependencies: 418
-- Data for Name: order_items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.order_items (id, order_id, variant_id, quantity, price_at_purchase, cogs_total) FROM stdin;
1	1	77	1	350000	0
2	2	80	1	350000	0
3	3	80	1	350000	0
4	4	97	1	250000	100000
5	5	87	1	300000	120000
6	6	102	1	320000	150000
7	7	97	1	250000	100000
8	8	73	1	280000	100000
9	9	88	1	400000	150000
10	10	101	1	280000	100000
11	11	75	1	350000	100000
12	12	96	1	250000	100000
13	13	101	1	280000	100000
14	14	92	1	250000	100000
15	15	73	1	280000	100000
16	15	83	1	350000	100000
17	16	101	1	280000	100000
\.


--
-- TOC entry 4077 (class 0 OID 17674)
-- Dependencies: 416
-- Data for Name: orders; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.orders (id, code, customer_id, store_id, promotion_id, subtotal, discount_amount, shipping_fee, total_amount, payment_method, status, note, created_at, customer_name, customer_phone, customer_address, customer_email, shipping_carrier, shipping_tracking_code, payment_status, email, customer_district_id, customer_ward_code) FROM stdin;
1	#ADM-451432	2	\N	\N	350000	0	0	350000	cod	pending	Ig baongoc08	2026-01-27 10:24:11.543574+00	Ngọc 	0967515969	Midtown The Peak M8 block A đường 15 phường tân phú q7	\N	\N	\N	unpaid	\N	\N	\N
2	#ADM-034177	3	\N	\N	350000	0	0	350000	transfer	pending	Ig kiki	2026-01-27 16:40:34.327486+00	Kỳ Kỳ	0708083054	214/C45 Nguyễn Trãi, phường Nguyễn Cư Trinh, Quận 1	\N	\N	\N	unpaid	\N	\N	\N
3	#ADM-035074	3	\N	\N	350000	0	0	350000	transfer	cancelled	Ig kiki	2026-01-27 16:40:35.546139+00	Kỳ Kỳ	0708083054	214/C45 Nguyễn Trãi, phường Nguyễn Cư Trinh, Quận 1	\N	\N	\N	unpaid	\N	\N	\N
4	ORD-27101769620733	4	\N	\N	250000	0	20000	270000	banking	pending	\N	2026-01-28 17:18:53.284955+00	Hân Kitty Phạm	0325225854	06 Song Hàng An Phú Quận 2 cũ, Thành Phố Thủ Đức, Hồ Chí Minh	phamngochan9694@gmail.com	\N	\N	unpaid	\N	3695	90765
5	ORD-73511769621093	5	\N	\N	300000	0	20000	320000	banking	cancelled	\N	2026-01-28 17:24:53.187139+00	Đởm Triết	0979911670	15 NXK, Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	1456	21509
6	ORD-48761769621359	5	\N	\N	320000	0	20000	340000	banking	cancelled	\N	2026-01-28 17:29:19.272408+00	Đởm Triết	0979911670	15 NXK, Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	1456	21509
7	ORD-26581769621681	1	\N	\N	250000	0	20000	270000	banking	cancelled	\N	2026-01-28 17:34:40.547563+00	Admin Brown	0900000000	15 NXK, Quận Tân Phú, Hồ Chí Minh	brownvn25@gmail.com	\N	\N	unpaid	\N	1456	21509
8	ORD-64151769777792	7	\N	\N	280000	0	20000	300000	banking	cancelled	\N	2026-01-30 12:56:31.552607+00	Anh thư	0967849849	9/1b xô viết nghệ tĩnh , Quận Ninh Kiều, Cần Thơ	hinhanhthu0197@gmail.com	\N	\N	unpaid	\N	1572	550102
9	ORD-88891769780624	8	\N	\N	400000	0	20000	420000	banking	cancelled	\N	2026-01-30 13:43:44.02047+00	Lu Bu Tông	0881718137	12 Lộp Chộp, huyện Sốp Cộp, Sơn La	jamaica@buchaby.com	\N	\N	unpaid	\N	3266	800118
10	ORD-97791769781867	5	\N	\N	280000	0	20000	300000	banking	cancelled	\N	2026-01-30 14:04:27.05563+00	Test Email	0979911670	15 Nguyễn Xuân Khoát, Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	1456	21509
11	ORD-56791769782123	5	\N	\N	350000	0	20000	370000	banking	cancelled	\N	2026-01-30 14:08:43.365738+00	Test Email	0979911670	15 Nguyễn Xuân Khoát, Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	1456	21509
12	ORD-75361769783047	5	\N	\N	250000	0	20000	270000	banking	cancelled	\N	2026-01-30 14:24:07.031802+00	Test Email	0979911670	15 Nguyễn Xuân Khoát, Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	1456	21509
13	ORD-79141769784204	5	\N	\N	280000	0	20000	300000	banking	cancelled	\N	2026-01-30 14:43:23.958923+00	Test Email	0979911670	15 Nguyễn Xuân Khoát, Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	1456	21509
14	ORD-50861769785620	5	\N	\N	250000	0	20000	270000	banking	returned	\N	2026-01-30 15:06:59.789747+00	Test Email	0979911670	15 Nguyễn Xuân Khoát, Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	GYBMRUQQ	unpaid	\N	1456	21509
15	ORD-66281769788258	9	\N	\N	630000	0	20000	650000	banking	shipping	\N	2026-01-30 15:50:57.890721+00	Nguyễn Kế Châu Anh	0911066568	Sky89, 89 Lê Thị Chợ, Quận 7, TPHCM, Quận 7, Hồ Chí Minh	jenninguyenke@gmail.com	\N	GYBMRRLF	unpaid	\N	1449	20702
16	ORD-30451769827329	5	\N	\N	280000	0	20000	300000	banking	pending	\N	2026-01-31 02:42:09.22943+00	Test Email	0979911670	15 Nguyễn Xuân Khoát, Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	1456	21509
\.


--
-- TOC entry 4088 (class 0 OID 23128)
-- Dependencies: 429
-- Data for Name: product_collections; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.product_collections (product_id, category_id) FROM stdin;
12	2
13	1
10	1
9	2
\.


--
-- TOC entry 4060 (class 0 OID 17522)
-- Dependencies: 399
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.products (id, name, slug, description, base_price, images, is_active, created_at, category_id, size_chart_url) FROM stdin;
19	SOLÉ BIKINI	sole-bikini-1769507676713	Chất liệu : Thun \nThành phần : 75% Nylon 25% Elastane\nCó mút ngực \nCả quần và áo đều được may 2lớp	280000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769265/brown_migration/fimz294eg3kkb8bmjctt.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769267/brown_migration/blrjy2iae3xn7xfqfuai.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769271/brown_migration/gnqcsbph4qyzuduzoxid.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769275/brown_migration/qf174raoukionl7cd67i.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769280/brown_migration/s8rm3td058juezupbsnd.webp}	t	2026-01-27 09:54:36.85854+00	3	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770118/brown_migration/gfvwpyokghhjz1ktexit.webp
3	SKIRT HONEY DRESS 	skirt-honey-dress--1769437468949	Chất liệu : Thun\nThành phần : 75% Nylon 25% Elastane \nChân váy dài lưng thấp cạp xéo, gập viền hoặc không tuỳ thích.\nTất cả các phép đo kích thước đều được tính bằng cm.	280000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769147/brown_migration/kyszl10ert2ngyvc6vij.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769151/brown_migration/apufsmwgkprd1rrwdl1n.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769156/brown_migration/po4bwi2i55biign1hr36.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769161/brown_migration/sl5qtgwzqijx7uue9m4k.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769168/brown_migration/uyt1n3r6yonaoqyfyd9c.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769176/brown_migration/cjkaparblrcgv4p5gopr.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769184/brown_migration/q6obkn2chidncrrcd4sk.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769192/brown_migration/mq3ldjmbwsixdhqjtzp8.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769200/brown_migration/swpapgojvfwml0lcjvm7.webp}	t	2026-01-26 14:24:29.537851+00	2	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770122/brown_migration/scokzjry0upfhbseds3a.webp
18	IVORY BIKINI	ivory-bikini-1769507588435	Chất liệu : Thun \nThành phần : 75% Nylon 25% Elastane\nCó mút ngực \nCả quần và áo đều được may 2lớp.\n	280000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769238/brown_migration/h7vio5lvckeyedu6aklx.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769242/brown_migration/jti5uw9gwcctjhuigqsu.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769249/brown_migration/to8sbr8myovk7sfymmcr.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769255/brown_migration/gm03cfq2wruleg0gkk60.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769262/brown_migration/zawq3rrtwepqbo0b0bkx.webp}	t	2026-01-27 09:53:08.685456+00	3	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770116/brown_migration/cydhbuknueywtpxpmgme.webp
20	BRONZE BIKINI	bronze-bikini-1769507808808	Chất liệu : Thun \nThành phần : 75% Nylon 25% Elastane\nCó mút ngực \nCả quần và áo đều được may 2lớp.	320000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769284/brown_migration/xys4exdoboqao5ze6jwm.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769286/brown_migration/pwemx2jz1eqhswgemb4d.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769293/brown_migration/rak674jj3lqghlhzzmgn.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769297/brown_migration/ffoeunremjgu2tfm1ttd.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769301/brown_migration/mhyoonmu4pxtbcdj5twr.webp}	t	2026-01-27 09:56:48.95231+00	3	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770124/brown_migration/pbnrq6mmjc3jlcio7eok.webp
6	POLO BABY MILK	polo-baby-milk-1769440246795	Chất liệu : Thun\nThành phần : 75% Nylon 25% Elastane\nÁo polo có dây kéo chiết eo form ôm\nTất cả các phép đo kích thước đều được tính bằng cm.\n	270000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769305/brown_migration/eqrrbcn5tekteu2whp4q.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769307/brown_migration/mhpgqrliufhay6qqacoy.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769310/brown_migration/xjgjpalel3djkdjni1le.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769313/brown_migration/mjft8wv3gcoenricxjvw.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769315/brown_migration/tm94a27ikqbarhmbudlc.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769317/brown_migration/jjb8gl2ckpt0xc3shfjv.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769319/brown_migration/d0x6rp1fpdniv0sy96t9.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769321/brown_migration/igpmpzhywm04gswnsf41.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769322/brown_migration/ij50plqnqaw1s3rltuqw.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769324/brown_migration/tqma4mec48smtnt4pefl.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769325/brown_migration/vlwg32erow1iz19vjtkt.webp}	t	2026-01-26 15:10:46.901889+00	1	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770129/brown_migration/niwshy0nr9wlq5j21pa1.webp
7	LILY TOP	lily-top-1769440684492	Chất liệu : Thun\nThành phần : 75% Nylon 25% Elastane\nTrễ vai xếp li có chiết eo.\nTất cả các phép đo kích thước đều được tính bằng cm.	220000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769327/brown_migration/vwjdcdmysqqgudsbau4l.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769328/brown_migration/jsmvqacu6twpsh3pc05s.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769330/brown_migration/scn5dhd2mtclpncvwbgr.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769333/brown_migration/reh6ctnyj9jg8fdcborq.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769335/brown_migration/a5hsjvv8zvbv6fo0kqae.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769338/brown_migration/cadubruecnlcf3mpdfsf.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769339/brown_migration/com4ydtvcp9ptbnhnquq.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769341/brown_migration/qsqsqgxh29yaltzncs2y.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769342/brown_migration/rkwli0mnyv2sop9bkmpi.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769344/brown_migration/c1m63jdfy2u19fbyynnm.webp}	t	2026-01-26 15:18:04.742783+00	1	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770130/brown_migration/klvg7rguwskb3zqtsvki.webp
10	BOWTIE BRA	bowtie-bra-1769504853531	Chất liệu : Thun gân \nThành phần : 100% cotton\nCó Mút (phía sau cột dây).\nTất cả các phép đo kích thước đều được tính bằng cm.	140000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769346/brown_migration/qbgq7yey2o015msj8jak.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769350/brown_migration/a2exvpvjlqoio3cludwh.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769354/brown_migration/lbmeneigyo1mell84k31.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769357/brown_migration/rzsbxreysks3iuxlso8j.webp}	t	2026-01-27 09:07:33.657681+00	1	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770133/brown_migration/sa811cg0qn5fg53lzwwm.webp
11	CHIC TEE	chic-tee-1769505018586	Chất liệu : Thun\nThành phần : 100% Cotton\nÁo trễ vai form rộng.\nTất cả các phép đo kích thước đều được tính bằng cm.\n	250000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769359/brown_migration/pxm1doryh6ed5rrbf9hq.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769363/brown_migration/vxazrgfyrgf7l9nr6jau.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769367/brown_migration/fiymjzfxadllihihwdq1.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769372/brown_migration/gyof4bu1aym7wjuylgi4.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769377/brown_migration/df9vil9dpvrga10wzn3a.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769381/brown_migration/ocnovzpndd1znwskbagj.webp}	t	2026-01-27 09:10:18.734267+00	1	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770137/brown_migration/jksoxzclunfwlg5mzxmt.webp
9	BROWN JEANS 	brown-jeans--1769504400203	Chất liệu : Jeans\nQuần jean cạp thấp ống suông loe.\nTất cả các phép đo kích thước đều được tính bằng cm.	350000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769383/brown_migration/hos5bhzhdhq8cs4oizwz.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769386/brown_migration/mfymgbvnidrtvdskytk0.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769390/brown_migration/eo8liycalufpjx2hvpa5.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769395/brown_migration/aancpavcvwjziasdjsln.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769399/brown_migration/iprgujtdc4rlkzxu84xp.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769404/brown_migration/prtlkn0xhfmzslrlltai.webp}	t	2026-01-27 09:00:00.443461+00	2	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770127/brown_migration/png214owqgqrhfqfvbdi.webp
12	JOLIE SHORT	jolie-short-1769505269364	Chất liệu : Thun \nThành phần : 75% Nylon 25% Elastane\nQuần ngắn lưng thấp cạp xéo gập viền) phần lưng gập không may cố định, khách có thể tuỳ ý gập độ cao thấp theo ý muốn.\nTất cả các phép đo kích thước đều được tính bằng cm.\n	190000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769406/brown_migration/jybin2sh2xzbfsivx9r8.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769409/brown_migration/y5asx9s7fdb053fjlzi4.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769413/brown_migration/just5ckf8nojlpwdjgvd.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769418/brown_migration/txieounny2ytydks4wuh.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769422/brown_migration/rcylwlnmurp6yykakwwd.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769426/brown_migration/otedbjtshnnmsldtuofp.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769430/brown_migration/n3mk6pmdjp48t0deasnp.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769435/brown_migration/rj9osvbfy0ozzbsquvwb.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769439/brown_migration/nqnfj9x8nxzbk1dertin.webp}	t	2026-01-27 09:14:29.521543+00	2	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770140/brown_migration/kvcdlkewxs5p5gil9j3e.webp
5	CAPRI AMOR	capri-amor-1769439895584	Chất liệu : Thun\nThành phần : 75% Nylon 25% Elastane\nQuần lửng lưng thấp cạp xéo có gập viền lưng & xẻ tà) - phần lưng gập không may cố định, khách có thể tuỳ ý gập độ cao thấp theo ý muốn.\nTất cả các phép đo kích thước đều được tính bằng cm.	280000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769441/brown_migration/m8oykrhpgdvs5n0v8she.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769445/brown_migration/zcgq1fmdtxzrkqhnibls.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769450/brown_migration/o3wnacphtsudq70qp43r.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769454/brown_migration/ecjru6bobh1qsd5fun32.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769458/brown_migration/mffweov4dxca1dn46uuw.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769462/brown_migration/necycwdv4kr6azxmn0p7.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769467/brown_migration/ex2xi5rimhfixt4updhv.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769471/brown_migration/ancvg43qsx0paxixnnmv.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769475/brown_migration/oyhtzskcsgucvkkidqtx.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769480/brown_migration/mwptz6t6zqteh4w7tlyo.webp}	t	2026-01-26 15:04:55.851048+00	2	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770144/brown_migration/f48da1b4l0hndpm2bwxj.webp
15	BLOOM SKIRT 	bloom-skirt--1769506794547	Chất liệu quần: Thun \nThành phần váy : 100% Poly\nSet chân váy bí kèm quần KHÔNG TÁCH LẺ - váy không may liền quần nên khách có thể tự điều chỉnh độ dài ngắn hoặc độ phồng ít nhiều tùy theo sở thích.\nTất cả các phép đo kích thước đều được tính bằng cm.	300000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769684/brown_migration/rafbqsj4b8suk9fqhjcd.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769687/brown_migration/qmupauvcpv7vwwpsykxp.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769691/brown_migration/r62o8dcebwdym6vysi62.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769698/brown_migration/h3exsna0pgueo8sacs7z.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769705/brown_migration/qdnx2mtw7vokussfmx5x.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769711/brown_migration/eesrfr1wujqod7jcoxwh.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769717/brown_migration/ctsr31wjcy2onboopmlo.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769724/brown_migration/yf5abmoi50sb9xnky7jh.webp}	t	2026-01-27 09:39:54.787998+00	2	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770152/brown_migration/ebix2ukd6tktryu58gex.webp
14	MUSE TOP	muse-top-1769506615428	Chất liệu : Thun \nThành phần : 75% Nylon 25% Elastane\nÁo cổ tim cột cổ - phần ngực được may 2 lớp \nKhoét sâu gom tạo nâng v1.\nTất cả các phép đo kích thước đều được tính bằng cm.	350000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769530/brown_migration/ck5be2swlyecywfndtte.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769532/brown_migration/cpdhakri54g7leblzuuv.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769535/brown_migration/r7de4sncipfqlamnmyka.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769538/brown_migration/o0c8mahl4haswxzpmbl3.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769541/brown_migration/er2i6b39saecyeizlcu5.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769545/brown_migration/uvkyq6b3tfa8blmngytw.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769548/brown_migration/wagd6q4hhcki8wjgny8e.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769555/brown_migration/n66pmbwk5ubdatzio5uq.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769559/brown_migration/r260gxghtjmc7aiwfhl3.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769563/brown_migration/q0lex2q2r9vxcm419xcl.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769567/brown_migration/cnwer2afc0azhvnwxxdr.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769571/brown_migration/hjusocu1uciyh5dgfvam.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769575/brown_migration/ruiv0uanr3rceh382jwi.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769579/brown_migration/dxu3fno1popswrihgpwc.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769583/brown_migration/geocpgm0p7gtycnqwpag.webp}	t	2026-01-27 09:36:55.718592+00	1	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770147/brown_migration/opmiuh65xyrfelx7dg4f.webp
17	CURVE TEE	curve-tee-1769507446512	Chất liệu : Thun \nThành phần : 75% Nylon 25% Elastane\nÁo thun ôm body thêu chữ - có dây kéo phía sau cổ cho các nàng dễ dàng mặc và cởi.\nTất cả các phép đo kích thước đều được tính bằng cm.	250000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769634/brown_migration/ri6ahfxobbvjlh8pzv8c.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769635/brown_migration/shzjw1zlmnumnxqctsce.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769638/brown_migration/ojmz13bky8o3rqlwtgqs.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769641/brown_migration/a1iaxp7g7djrwjpt5pfp.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769643/brown_migration/s0cnysy3qvcl5o116ykr.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769646/brown_migration/qejovny0wf6cpx6bigyv.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769649/brown_migration/cu7zc3ftoknkceewzxlk.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769652/brown_migration/lkvqaeft4wl2yeuar1wm.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769656/brown_migration/murfru8fzojzbuobb3wc.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769660/brown_migration/m411k8bo4mlbr1arg8gi.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769663/brown_migration/epqivpuhwfjqpty8w0jg.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769667/brown_migration/wxcpnsz5h5lpexynrsvo.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769670/brown_migration/w9lq33te7gzss1rxmbke.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769673/brown_migration/ryqiwbb0mpmwdeifvvko.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769677/brown_migration/ycutnhkbnre0wnvtnpkk.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769680/brown_migration/oybwqiyhpiq2hr72stxs.webp}	t	2026-01-27 09:50:46.761579+00	1	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770148/brown_migration/skyb2bekih1vwydauvsu.webp
4	SKIRT HONEY 	skirt-honey--1769439364870	Chất liệu : Thun\nThành phần : 75% Nylon 25% Elastane \nChân váy ngắn lưng thấp có quần bảo hộ.\nTất cả các phép đo kích thước đều được tính bằng cm.	250000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769204/brown_migration/k8x4ejlvgecq2ara4mkv.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769207/brown_migration/qyh1ijwnjbdw6c010jq6.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769210/brown_migration/lfhxzfuj5frvapkbwum5.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769214/brown_migration/ruxr8dqbmuvboeptn5oz.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769219/brown_migration/pw905k5etgv7o9axi9ap.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769224/brown_migration/tuchxkgjglrw9kqrmnbs.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769228/brown_migration/csle3ezhy8uvbgkf7brj.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769232/brown_migration/tg29tqwkzajoztmsxhsv.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769236/brown_migration/g3ocoq4uhrbvttpwvilj.webp}	t	2026-01-26 14:56:05.130846+00	2	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770158/brown_migration/jdk3gedmqtocqabjsmsj.webp
13	GLOW HALTER	glow-halter-1769505948457	Chất liệu : Thun \nThành phần : 75% Nylon 25% Elastane\nÁo yếm may 2 lớp - có cài nút ở cổ - có tăng đơ điều chỉnh ở sau lưng - cột dây để thoải mái điều chỉnh theo số đo của mỗi người.\nTất cả các phép đo kích thước đều được tính bằng cm.	350000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769482/brown_migration/cidhikd6f1l2ug49f9an.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769483/brown_migration/toe9bcc2kjgjbwcyy2fr.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769486/brown_migration/vuvuqzebbdayvbuiikyz.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769489/brown_migration/ozmadjfwcwqnmrviqh7j.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769491/brown_migration/ok9to3b3vhxh3uj6f3sa.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769495/brown_migration/jkhvlnukhvhudaoxchkb.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769498/brown_migration/tmavg80cxetwmntcmppo.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769501/brown_migration/udr2pxu4ucmqkxam3ftd.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769505/brown_migration/t8y1uj4vkygmrbct1e24.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769508/brown_migration/aribh4jpydgr2vapokgg.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769512/brown_migration/x7edgrapr3keykfayemh.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769516/brown_migration/wtyzqctczheqwam8lxzn.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769520/brown_migration/zdodv4fxdhrifto4alun.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769523/brown_migration/kerrpltna5drf85ntfy4.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769526/brown_migration/erzaemhnaa7o0i5x7qqh.webp}	t	2026-01-27 09:25:48.591654+00	1	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770160/brown_migration/ibqomgahjpwtnfzgeoin.webp
16	FLARE PANTS 	flare-pants--1769506994720	Chất liệu : Thun \nThành phần : 75% Nylon 25% Elastane\nQuần loe lưng thấp cạp xéo có gập viền - phần lưng gập không may cố định, khách có thể tuỳ ý gập độ cao thấp theo ý muốn - phần hông có nhún nhẹ hai bên để che phần bụng dưới.\nTất cả các phép đo kích thước đều được tính bằng cm.	400000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769586/brown_migration/xjzur47dba6slonhwjrr.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769588/brown_migration/xxpkcjbeizwzwq5nykrc.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769591/brown_migration/defwkphwuckv04l8vbk2.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769594/brown_migration/fxesxbce1zabpoqgqzcc.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769598/brown_migration/mlsiyzfmczpqq1tspnak.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769602/brown_migration/tiflllnnxip0cbiv9nqw.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769606/brown_migration/cwtrrwrzjg7m606mvmcl.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769610/brown_migration/m4jqo3b87qyp0e1ilwtm.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769614/brown_migration/iabh4onwu9vndvp9xztv.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769618/brown_migration/sdhylixku4x8umpumfgc.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769622/brown_migration/f9mmyk5ep2pixv4kcyt3.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769626/brown_migration/up7qzcljalwrgyxoams9.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769630/brown_migration/jh6vyi2ln28xnfofp9ew.webp}	t	2026-01-27 09:43:15.154499+00	2	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770154/brown_migration/fz8hjwjeylh8klih8u9y.webp
8	LAROSE CAMI	larose-cami-1769441181303	Chất liệu : Thun \nThành phần : 75% Nylon 25% Elastane\n Áo 2 dây cổ tim có chiết eo & may viền giúp nâng phần ngực\nTất cả các phép đo kích thước đều được tính bằng cm.	180000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769729/brown_migration/dfaaotoh2yto0fyrjt7z.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769731/brown_migration/tyga5pulcglsjro479cq.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769733/brown_migration/u60gui7osk7rbwqobjdd.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769734/brown_migration/d0hawe3icq8kga62pvse.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769736/brown_migration/cmrrb2oapi8iuusc0vsw.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769738/brown_migration/rgfgb4jocgvy3scl79kv.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769740/brown_migration/c5rd7lc3salihqnqgdoa.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769742/brown_migration/knbsdq9wqqm9ebuuwyeq.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769744/brown_migration/p6qkrvzql6dnt5hzczfz.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769747/brown_migration/ad0zrcun2hqzbsk5voqm.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769749/brown_migration/bxnpvv51crgv7ebdghdb.webp}	t	2026-01-26 15:26:21.856187+00	1	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770162/brown_migration/kce1rbd3e2mso4kbxdiw.webp
\.


--
-- TOC entry 4072 (class 0 OID 17637)
-- Dependencies: 411
-- Data for Name: promotions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.promotions (id, code, description, discount_type, discount_value, min_order_value, start_date, end_date, requires_account, is_active, usage_limit, used_count, max_discount_amount) FROM stdin;
\.


--
-- TOC entry 4066 (class 0 OID 17585)
-- Dependencies: 405
-- Data for Name: purchase_items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.purchase_items (id, purchase_order_id, variant_id, quantity, unit_cost) FROM stdin;
2	2	35	10	90500
3	3	102	6	150000
4	4	101	20	100000
5	5	101	20	100000
6	6	100	15	115000
7	7	96	22	100000
8	8	97	9	100000
9	9	97	9	100000
10	10	92	10	100000
11	11	92	10	100000
12	12	93	10	100000
13	13	94	10	100000
14	14	95	10	100000
15	15	98	10	100000
16	16	98	10	100000
17	17	99	10	100000
18	18	88	15	150000
19	19	89	15	150000
20	20	90	22	150000
21	21	91	17	150000
22	22	87	10	120000
23	23	79	16	100000
24	24	80	14	100000
25	25	81	17	100000
26	26	82	19	100000
27	27	82	19	100000
28	28	83	14	100000
29	29	84	22	100000
30	30	85	19	100000
31	31	86	22	100000
32	32	75	14	100000
33	33	76	14	100000
34	34	77	1	100000
35	35	78	4	100000
36	36	47	7	100000
37	37	48	1	100000
38	38	49	10	100000
39	39	51	6	100000
40	40	52	6	100000
41	41	46	11	60000
42	42	45	12	60000
43	43	112	6	160000
44	44	36	15	100000
45	45	33	11	100000
46	46	27	6	100000
47	47	28	4	100000
48	48	69	5	100000
49	49	70	5	100000
50	50	71	19	100000
51	51	72	2	100000
52	52	24	17	100000
53	53	74	9	100000
54	54	101	1	100000
55	55	73	80	100000
56	56	23	30	100000
57	57	77	20	100000
\.


--
-- TOC entry 4064 (class 0 OID 17565)
-- Dependencies: 403
-- Data for Name: purchase_orders; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.purchase_orders (id, supplier_id, store_id, total_cost, note, purchase_date, code, status) FROM stdin;
1	1	1	2000000	\N	2026-01-26 14:30:59.902993+00	\N	\N
2	1	1	905000	\N	2026-01-26 16:20:54.728835+00	\N	\N
3	1	1	900000	\N	2026-01-27 10:01:01.484681+00	\N	\N
4	1	1	2000000	\N	2026-01-27 10:01:27.181301+00	\N	\N
5	1	1	2000000	\N	2026-01-27 10:01:29.118656+00	\N	\N
6	1	1	1725000	\N	2026-01-27 10:01:51.818215+00	\N	\N
7	1	1	2200000	\N	2026-01-27 10:05:16.79212+00	\N	\N
8	1	1	900000	\N	2026-01-27 10:06:54.15778+00	\N	\N
9	1	1	900000	\N	2026-01-27 10:06:55.679558+00	\N	\N
10	1	1	1000000	\N	2026-01-27 10:07:16.741013+00	\N	\N
11	1	1	1000000	\N	2026-01-27 10:07:17.97237+00	\N	\N
12	1	1	1000000	\N	2026-01-27 10:07:34.24103+00	\N	\N
13	1	1	1000000	\N	2026-01-27 10:07:47.668241+00	\N	\N
14	1	1	1000000	\N	2026-01-27 10:08:02.501589+00	\N	\N
15	1	1	1000000	\N	2026-01-27 10:08:18.078559+00	\N	\N
16	1	1	1000000	\N	2026-01-27 10:08:20.599354+00	\N	\N
17	1	1	1000000	\N	2026-01-27 10:08:40.106816+00	\N	\N
18	1	1	2250000	\N	2026-01-27 10:09:28.972086+00	\N	\N
19	1	1	2250000	\N	2026-01-27 10:09:46.66353+00	\N	\N
20	1	1	3300000	\N	2026-01-27 10:10:00.167062+00	\N	\N
21	1	1	2550000	\N	2026-01-27 10:10:14.393178+00	\N	\N
22	1	1	1200000	\N	2026-01-27 10:10:41.659822+00	\N	\N
23	1	1	1600000	\N	2026-01-27 10:11:13.882606+00	\N	\N
24	1	1	1400000	\N	2026-01-27 10:11:27.209235+00	\N	\N
25	1	1	1700000	\N	2026-01-27 10:11:45.867258+00	\N	\N
26	1	1	1900000	\N	2026-01-27 10:12:17.630238+00	\N	\N
27	1	1	1900000	\N	2026-01-27 10:12:19.515695+00	\N	\N
28	1	1	1400000	\N	2026-01-27 10:12:33.258546+00	\N	\N
29	1	1	2200000	\N	2026-01-27 10:12:45.31487+00	\N	\N
30	1	1	1900000	\N	2026-01-27 10:12:58.143+00	\N	\N
31	1	1	2200000	\N	2026-01-27 10:13:12.170578+00	\N	\N
32	1	1	1400000	\N	2026-01-27 10:14:36.294959+00	\N	\N
33	1	1	1400000	\N	2026-01-27 10:14:51.193832+00	\N	\N
34	1	1	100000	\N	2026-01-27 10:15:06.673182+00	\N	\N
35	1	1	400000	\N	2026-01-27 10:15:24.053488+00	\N	\N
36	1	1	700000	\N	2026-01-27 10:15:45.483579+00	\N	\N
37	1	1	100000	\N	2026-01-27 10:16:06.048598+00	\N	\N
38	1	1	1000000	\N	2026-01-27 10:16:26.645366+00	\N	\N
39	1	1	600000	\N	2026-01-27 10:16:40.048147+00	\N	\N
40	1	1	600000	\N	2026-01-27 10:16:54.065696+00	\N	\N
41	1	1	660000	\N	2026-01-27 10:17:21.41946+00	\N	\N
42	1	1	720000	\N	2026-01-27 10:17:43.950084+00	\N	\N
43	1	1	960000	\N	2026-01-27 10:18:55.737431+00	\N	\N
44	1	1	1500000	\N	2026-01-27 10:19:16.707105+00	\N	\N
45	1	1	1100000	\N	2026-01-27 10:19:56.471329+00	\N	\N
46	1	1	600000	\N	2026-01-27 10:20:13.439732+00	\N	\N
47	1	1	400000	\N	2026-01-27 10:20:23.898092+00	\N	\N
48	1	1	500000	\N	2026-01-27 10:20:41.111058+00	\N	\N
49	1	1	500000	\N	2026-01-27 10:20:50.92347+00	\N	\N
50	1	1	1900000	\N	2026-01-27 10:21:13.465553+00	\N	\N
51	1	1	200000	\N	2026-01-27 10:21:26.449181+00	\N	\N
52	1	1	1700000	\N	2026-01-27 10:21:52.005109+00	\N	\N
53	1	1	900000	\N	2026-01-27 10:23:03.396644+00	\N	\N
54	1	1	100000	\N	2026-01-28 12:38:14.209706+00	\N	\N
55	1	1	8000000	\N	2026-01-28 15:45:40.96862+00	\N	\N
56	1	1	3000000	\N	2026-01-28 15:49:43.532149+00	\N	\N
57	1	1	2000000	\N	2026-01-28 16:02:18.104927+00	\N	\N
\.


--
-- TOC entry 4054 (class 0 OID 17487)
-- Dependencies: 393
-- Data for Name: stores; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.stores (id, name, address, phone, is_active, created_at) FROM stdin;
1	15 Nguyễn Xuân Khoát	\N	\N	t	2026-01-26 14:30:34.21197+00
\.


--
-- TOC entry 4058 (class 0 OID 17513)
-- Dependencies: 397
-- Data for Name: suppliers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.suppliers (id, name, created_at, phone, address) FROM stdin;
1	Qlee	2026-01-26 14:30:15.248688+00	\N	\N
\.


--
-- TOC entry 4062 (class 0 OID 17549)
-- Dependencies: 401
-- Data for Name: variants; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.variants (id, product_id, sku, size, color, current_price, image_url, created_at, weight) FROM stdin;
23	4	Váy Ngắn Trắng	Free	Trắng	\N	\N	2026-01-26 15:05:40.605075+00	500
24	4	Váy Ngắn Đen	Free	Đen	\N	\N	2026-01-26 15:05:40.605075+00	500
27	6	Polo Trắng S	S	Trắng	\N	\N	2026-01-26 15:10:47.11471+00	500
28	6	Polo Trắng M	M	Trắng	\N	\N	2026-01-26 15:10:47.11471+00	500
29	6	Polo Đen S	S	Đen	\N	\N	2026-01-26 15:10:47.11471+00	500
30	6	Polo Đen M	M	Đen	\N	\N	2026-01-26 15:10:47.11471+00	500
31	7	Trễ Vai Trắng S	S	Trắng	\N	\N	2026-01-26 15:18:04.988012+00	500
32	7	Trễ Vai Trắng M	M 	Trắng	\N	\N	2026-01-26 15:18:04.988012+00	500
33	7	Trễ Vai Đen S	S	Đen	\N	\N	2026-01-26 15:18:04.988012+00	500
34	7	Trễ Vai Đen M	M	Đen	\N	\N	2026-01-26 15:18:04.988012+00	500
35	8	2S Vàng S	S	Vàng	\N	\N	2026-01-26 15:26:22.190999+00	500
36	8	2S Vàng M	M	Vàng	\N	\N	2026-01-26 15:26:22.190999+00	500
37	8	2S Trắng S	S	Trắng	\N	\N	2026-01-26 15:26:22.190999+00	500
38	8	2S Trắng M	M	Trắng	\N	\N	2026-01-26 15:26:22.190999+00	500
39	8	2S Đen S	S	Đen	\N	\N	2026-01-26 15:26:22.190999+00	500
40	8	2S Đen M	M	Đen	\N	\N	2026-01-26 15:26:22.190999+00	500
41	8	2S Nâu S	S	Nâu 	\N	\N	2026-01-26 15:26:22.190999+00	500
42	8	2S Nâu M	M	Nâu	\N	\N	2026-01-26 15:26:22.190999+00	500
45	10	Bra Xám	Free	Xám	\N	\N	2026-01-27 09:07:34.070857+00	500
46	11	Tee trễ vai trắng	Free	Trắng	\N	\N	2026-01-27 09:10:18.943612+00	500
47	12	Quần Ngắn Trắng S	S	Trắng	\N	\N	2026-01-27 09:14:29.970962+00	500
48	12	Quần Ngắn Trắng M	M	Trắng	\N	\N	2026-01-27 09:14:29.970962+00	500
49	12	Quần Ngắn Đen S	S	Đen	\N	\N	2026-01-27 09:14:29.970962+00	500
50	12	Quần Ngắn Đen M	M	Đen	\N	\N	2026-01-27 09:14:29.970962+00	500
51	12	Quần Ngắn Nâu S	S	Nâu	\N	\N	2026-01-27 09:14:29.970962+00	500
52	12	Quần Ngắn Nâu M	M	Nâu	\N	\N	2026-01-27 09:14:29.970962+00	500
69	5	Capri Trắng S	S	Trắng	\N	\N	2026-01-27 09:15:51.449335+00	500
70	5	Capri trắng M	M	Trắng	\N	\N	2026-01-27 09:15:51.449335+00	500
71	5	Capri Đen S	S	Đen	\N	\N	2026-01-27 09:15:51.449335+00	500
72	5	Capri Đen M	M	Đen	\N	\N	2026-01-27 09:15:51.449335+00	500
73	3	Váy Dài Trắng	Free	Trắng	\N	\N	2026-01-27 09:16:12.934687+00	500
74	3	Váy Dài Đen	Free	Đen	\N	\N	2026-01-27 09:16:12.934687+00	500
75	13	Yếm Trắng	Free	Trắng	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769751/brown_migration/aexlwla8a0z8ayi0md5v.webp	2026-01-27 09:25:49.000084+00	500
76	13	Yếm Đen	Free	Đen	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769754/brown_migration/bopvf4amdptwfdfch7fe.webp	2026-01-27 09:25:49.000084+00	500
77	13	Yếm Xám	Free	Xám	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769757/brown_migration/okvqkxoh7tvgugiipw9p.webp	2026-01-27 09:25:49.000084+00	500
78	13	Yếm Xanh	Free	Xanh	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769760/brown_migration/fypcmzt3dv942lgijgvp.webp	2026-01-27 09:25:49.000084+00	500
79	14	Áo Tim Xanh S	S	Xanh	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769763/brown_migration/kpdiraemztfkexff5pch.webp	2026-01-27 09:36:55.99799+00	500
80	14	Áo Tim Xanh M	M	Xanh	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769765/brown_migration/gia1no6rg1qoldibsole.webp	2026-01-27 09:36:55.99799+00	500
81	14	Áo Tim Đen S	S	Đen	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769768/brown_migration/yh5apxjxznekjhngzqsg.webp	2026-01-27 09:36:55.99799+00	500
82	14	Áo Tim Đen M	M	Đen	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769771/brown_migration/wyqxuirvcahssmzli1nv.webp	2026-01-27 09:36:55.99799+00	500
83	14	Áo Tim Trắng S	S	Trắng	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769773/brown_migration/k8jrfsplszhxwzk4gsfr.webp	2026-01-27 09:36:55.99799+00	500
84	14	Áo Tim Trắng M	M	Trắng	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769776/brown_migration/grq3y4vpgnsoi0ivrkff.webp	2026-01-27 09:36:55.99799+00	500
85	14	Áo Tim Xám S	S	Xám	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769778/brown_migration/d1wjkqitwkjglwtmhbd4.webp	2026-01-27 09:36:55.99799+00	500
86	14	Áo Tim Xám M	M	Xám	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769781/brown_migration/tiayaqkuoj4bg5j8dcyp.webp	2026-01-27 09:36:55.99799+00	500
87	15	Váy Bí Trắng	Free	Trắng	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769786/brown_migration/xk1wdojb2bnpkhonrhru.webp	2026-01-27 09:39:54.994873+00	500
88	16	Quần Loe Đen S	S	Đen	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769789/brown_migration/nuze6xytm19axcrfgtyn.webp	2026-01-27 09:43:15.43895+00	500
89	16	Quần Loe Đen M	M	Đen	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769792/brown_migration/noakewjw5ntcruwnatug.webp	2026-01-27 09:43:15.43895+00	500
90	16	Quần Loe Trắng S	S	Trắng	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769795/brown_migration/npeqmmpkagruvnidxf0d.webp	2026-01-27 09:43:15.43895+00	500
91	16	Quần Loe Trắng M	M	Trắng	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769798/brown_migration/lfrisp4yqbtxdfhs1jxd.webp	2026-01-27 09:43:15.43895+00	500
92	17	Áo Thun Trắng S	S	Trắng	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769800/brown_migration/jib0srnxuzhoskxupd6n.webp	2026-01-27 09:50:46.963978+00	500
93	17	Áo Thun Trắng M	M	Trắng	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769803/brown_migration/npp8gyl4vvaduzu96ecf.webp	2026-01-27 09:50:46.963978+00	500
94	17	Áo Thun Đen S	S	Đen	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769806/brown_migration/y0qz98n4zyy8mqbfottm.webp	2026-01-27 09:50:46.963978+00	500
95	17	Áo Thun Đen M	M	Đen	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769808/brown_migration/avlkmlrgsilrcfi1qvdn.webp	2026-01-27 09:50:46.963978+00	500
96	17	Áo Thun Xanh S	S	Xanh	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769811/brown_migration/ofnl17sqvdgb7zawcc6q.webp	2026-01-27 09:50:46.963978+00	500
97	17	Áo Thun Xanh M	M	Xanh	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769813/brown_migration/j5pis9noptfjcwd5bxgl.webp	2026-01-27 09:50:46.963978+00	500
100	18	Bikini Cherry Trắng	Free	Trắng	\N	\N	2026-01-27 09:53:08.914811+00	500
101	19	Bikini Xanh	Free	Xanh	\N	\N	2026-01-27 09:54:37.063319+00	500
102	20	Bikini Xám	Free	Xám	\N	\N	2026-01-27 09:56:49.155595+00	500
110	9	Jeans S	S	Trắng	\N	\N	2026-01-27 10:18:26.343445+00	500
111	9	Jeans M	M	Trắng	\N	\N	2026-01-27 10:18:26.343445+00	500
112	9	Jeans L	L	Trắng	\N	\N	2026-01-27 10:18:26.343445+00	500
98	17	Áo Thun Xám S	S	Xám	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769816/brown_migration/egnb2jhvee4rkz3fkjg6.webp	2026-01-27 09:50:46.963978+00	500
99	17	Áo Thun Xám M	M	Xám	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769819/brown_migration/xawni7fqx1z55a5dqthv.webp	2026-01-27 09:50:46.963978+00	500
\.


--
-- TOC entry 4128 (class 0 OID 0)
-- Dependencies: 425
-- Name: banners_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.banners_id_seq', 1, false);


--
-- TOC entry 4129 (class 0 OID 0)
-- Dependencies: 413
-- Name: cart_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.cart_items_id_seq', 1, false);


--
-- TOC entry 4130 (class 0 OID 0)
-- Dependencies: 394
-- Name: categories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.categories_id_seq', 4, true);


--
-- TOC entry 4131 (class 0 OID 0)
-- Dependencies: 423
-- Name: content_banners_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.content_banners_id_seq', 4, true);


--
-- TOC entry 4132 (class 0 OID 0)
-- Dependencies: 408
-- Name: customers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.customers_id_seq', 9, true);


--
-- TOC entry 4133 (class 0 OID 0)
-- Dependencies: 419
-- Name: expense_categories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.expense_categories_id_seq', 1, false);


--
-- TOC entry 4134 (class 0 OID 0)
-- Dependencies: 421
-- Name: expenses_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.expenses_id_seq', 1, false);


--
-- TOC entry 4135 (class 0 OID 0)
-- Dependencies: 406
-- Name: inventory_batches_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.inventory_batches_id_seq', 77, true);


--
-- TOC entry 4136 (class 0 OID 0)
-- Dependencies: 417
-- Name: order_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.order_items_id_seq', 17, true);


--
-- TOC entry 4137 (class 0 OID 0)
-- Dependencies: 415
-- Name: orders_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.orders_id_seq', 16, true);


--
-- TOC entry 4138 (class 0 OID 0)
-- Dependencies: 398
-- Name: products_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.products_id_seq', 20, true);


--
-- TOC entry 4139 (class 0 OID 0)
-- Dependencies: 410
-- Name: promotions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.promotions_id_seq', 1, false);


--
-- TOC entry 4140 (class 0 OID 0)
-- Dependencies: 404
-- Name: purchase_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.purchase_items_id_seq', 57, true);


--
-- TOC entry 4141 (class 0 OID 0)
-- Dependencies: 402
-- Name: purchase_orders_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.purchase_orders_id_seq', 57, true);


--
-- TOC entry 4142 (class 0 OID 0)
-- Dependencies: 392
-- Name: stores_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.stores_id_seq', 1, true);


--
-- TOC entry 4143 (class 0 OID 0)
-- Dependencies: 396
-- Name: suppliers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.suppliers_id_seq', 1, true);


--
-- TOC entry 4144 (class 0 OID 0)
-- Dependencies: 400
-- Name: variants_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.variants_id_seq', 112, true);


--
-- TOC entry 3832 (class 2606 OID 21625)
-- Name: banners banners_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.banners
    ADD CONSTRAINT banners_pkey PRIMARY KEY (id);


--
-- TOC entry 3815 (class 2606 OID 17662)
-- Name: cart_items cart_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cart_items
    ADD CONSTRAINT cart_items_pkey PRIMARY KEY (id);


--
-- TOC entry 3813 (class 2606 OID 17655)
-- Name: carts carts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.carts
    ADD CONSTRAINT carts_pkey PRIMARY KEY (user_id);


--
-- TOC entry 3782 (class 2606 OID 17504)
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- TOC entry 3784 (class 2606 OID 17506)
-- Name: categories categories_slug_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_slug_key UNIQUE (slug);


--
-- TOC entry 3830 (class 2606 OID 20157)
-- Name: content_banners content_banners_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_banners
    ADD CONSTRAINT content_banners_pkey PRIMARY KEY (id);


--
-- TOC entry 3805 (class 2606 OID 17634)
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- TOC entry 3826 (class 2606 OID 17727)
-- Name: expense_categories expense_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.expense_categories
    ADD CONSTRAINT expense_categories_pkey PRIMARY KEY (id);


--
-- TOC entry 3828 (class 2606 OID 17737)
-- Name: expenses expenses_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_pkey PRIMARY KEY (id);


--
-- TOC entry 3803 (class 2606 OID 17608)
-- Name: inventory_batches inventory_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_pkey PRIMARY KEY (id);


--
-- TOC entry 3824 (class 2606 OID 17709)
-- Name: order_items order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (id);


--
-- TOC entry 3818 (class 2606 OID 17687)
-- Name: orders orders_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_code_key UNIQUE (code);


--
-- TOC entry 3820 (class 2606 OID 17685)
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- TOC entry 3834 (class 2606 OID 23132)
-- Name: product_collections product_collections_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_collections
    ADD CONSTRAINT product_collections_pkey PRIMARY KEY (product_id, category_id);


--
-- TOC entry 3788 (class 2606 OID 17530)
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- TOC entry 3790 (class 2606 OID 17532)
-- Name: products products_slug_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_slug_key UNIQUE (slug);


--
-- TOC entry 3809 (class 2606 OID 17649)
-- Name: promotions promotions_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promotions
    ADD CONSTRAINT promotions_code_key UNIQUE (code);


--
-- TOC entry 3811 (class 2606 OID 17647)
-- Name: promotions promotions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promotions
    ADD CONSTRAINT promotions_pkey PRIMARY KEY (id);


--
-- TOC entry 3800 (class 2606 OID 17590)
-- Name: purchase_items purchase_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_items
    ADD CONSTRAINT purchase_items_pkey PRIMARY KEY (id);


--
-- TOC entry 3796 (class 2606 OID 21610)
-- Name: purchase_orders purchase_orders_code_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_code_unique UNIQUE (code);


--
-- TOC entry 3798 (class 2606 OID 17573)
-- Name: purchase_orders purchase_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_pkey PRIMARY KEY (id);


--
-- TOC entry 3780 (class 2606 OID 17495)
-- Name: stores stores_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stores
    ADD CONSTRAINT stores_pkey PRIMARY KEY (id);


--
-- TOC entry 3786 (class 2606 OID 17520)
-- Name: suppliers suppliers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_pkey PRIMARY KEY (id);


--
-- TOC entry 3792 (class 2606 OID 17556)
-- Name: variants variants_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.variants
    ADD CONSTRAINT variants_pkey PRIMARY KEY (id);


--
-- TOC entry 3794 (class 2606 OID 17558)
-- Name: variants variants_sku_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.variants
    ADD CONSTRAINT variants_sku_key UNIQUE (sku);


--
-- TOC entry 3816 (class 1259 OID 22937)
-- Name: idx_cart_items_variant_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cart_items_variant_id ON public.cart_items USING btree (variant_id);


--
-- TOC entry 3806 (class 1259 OID 17635)
-- Name: idx_customer_phone; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_customer_phone ON public.customers USING btree (phone);


--
-- TOC entry 3807 (class 1259 OID 23174)
-- Name: idx_customers_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_customers_user_id ON public.customers USING btree (user_id);


--
-- TOC entry 3801 (class 1259 OID 17624)
-- Name: idx_inventory_fifo; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_inventory_fifo ON public.inventory_batches USING btree (store_id, variant_id, created_at);


--
-- TOC entry 3821 (class 1259 OID 22935)
-- Name: idx_order_items_order_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_order_items_order_id ON public.order_items USING btree (order_id);


--
-- TOC entry 3822 (class 1259 OID 22936)
-- Name: idx_order_items_variant_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_order_items_variant_id ON public.order_items USING btree (variant_id);


--
-- TOC entry 3857 (class 2620 OID 21696)
-- Name: orders trigger_restore_inventory; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_restore_inventory AFTER UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.restore_inventory_on_cancel();


--
-- TOC entry 3846 (class 2606 OID 17663)
-- Name: cart_items cart_items_cart_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cart_items
    ADD CONSTRAINT cart_items_cart_id_fkey FOREIGN KEY (cart_id) REFERENCES public.carts(user_id) ON DELETE CASCADE;


--
-- TOC entry 3847 (class 2606 OID 17668)
-- Name: cart_items cart_items_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cart_items
    ADD CONSTRAINT cart_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.variants(id);


--
-- TOC entry 3835 (class 2606 OID 17507)
-- Name: categories categories_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.categories(id) ON DELETE SET NULL;


--
-- TOC entry 3853 (class 2606 OID 17743)
-- Name: expenses expenses_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.expense_categories(id);


--
-- TOC entry 3854 (class 2606 OID 17738)
-- Name: expenses expenses_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id);


--
-- TOC entry 3836 (class 2606 OID 23169)
-- Name: products fk_products_main_category; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT fk_products_main_category FOREIGN KEY (category_id) REFERENCES public.categories(id);


--
-- TOC entry 3842 (class 2606 OID 17619)
-- Name: inventory_batches inventory_batches_purchase_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_purchase_item_id_fkey FOREIGN KEY (purchase_item_id) REFERENCES public.purchase_items(id);


--
-- TOC entry 3843 (class 2606 OID 17609)
-- Name: inventory_batches inventory_batches_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id);


--
-- TOC entry 3844 (class 2606 OID 17883)
-- Name: inventory_batches inventory_batches_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id);


--
-- TOC entry 3845 (class 2606 OID 17614)
-- Name: inventory_batches inventory_batches_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.variants(id);


--
-- TOC entry 3851 (class 2606 OID 17710)
-- Name: order_items order_items_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- TOC entry 3852 (class 2606 OID 17715)
-- Name: order_items order_items_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.variants(id);


--
-- TOC entry 3848 (class 2606 OID 17688)
-- Name: orders orders_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- TOC entry 3849 (class 2606 OID 17698)
-- Name: orders orders_promotion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_promotion_id_fkey FOREIGN KEY (promotion_id) REFERENCES public.promotions(id);


--
-- TOC entry 3850 (class 2606 OID 17693)
-- Name: orders orders_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id);


--
-- TOC entry 3855 (class 2606 OID 23138)
-- Name: product_collections product_collections_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_collections
    ADD CONSTRAINT product_collections_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id) ON DELETE CASCADE;


--
-- TOC entry 3856 (class 2606 OID 23133)
-- Name: product_collections product_collections_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_collections
    ADD CONSTRAINT product_collections_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- TOC entry 3840 (class 2606 OID 17591)
-- Name: purchase_items purchase_items_purchase_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_items
    ADD CONSTRAINT purchase_items_purchase_order_id_fkey FOREIGN KEY (purchase_order_id) REFERENCES public.purchase_orders(id) ON DELETE CASCADE;


--
-- TOC entry 3841 (class 2606 OID 17596)
-- Name: purchase_items purchase_items_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_items
    ADD CONSTRAINT purchase_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.variants(id);


--
-- TOC entry 3838 (class 2606 OID 17579)
-- Name: purchase_orders purchase_orders_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id);


--
-- TOC entry 3839 (class 2606 OID 17574)
-- Name: purchase_orders purchase_orders_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id);


--
-- TOC entry 3837 (class 2606 OID 17559)
-- Name: variants variants_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.variants
    ADD CONSTRAINT variants_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- TOC entry 4040 (class 3256 OID 22904)
-- Name: categories Admin All Categories; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Categories" ON public.categories USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4032 (class 3256 OID 22896)
-- Name: customers Admin All Customers; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Customers" ON public.customers USING ((EXISTS ( SELECT 1
   FROM public.customers customers_1
  WHERE ((customers_1.user_id = auth.uid()) AND (customers_1.role = 'admin'::text)))));


--
-- TOC entry 4034 (class 3256 OID 22898)
-- Name: expenses Admin All Expenses; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Expenses" ON public.expenses USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4035 (class 3256 OID 22899)
-- Name: inventory_batches Admin All Inventory; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Inventory" ON public.inventory_batches USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4043 (class 3256 OID 22928)
-- Name: order_items Admin All Order Items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Order Items" ON public.order_items USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4029 (class 3256 OID 22893)
-- Name: orders Admin All Orders; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Orders" ON public.orders USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4028 (class 3256 OID 22892)
-- Name: products Admin All Products; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Products" ON public.products USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4036 (class 3256 OID 22900)
-- Name: promotions Admin All Promotions; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Promotions" ON public.promotions USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4038 (class 3256 OID 22902)
-- Name: variants Admin All Variants; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Variants" ON public.variants USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4048 (class 3256 OID 22933)
-- Name: banners Admin Manage Banners; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin Manage Banners" ON public.banners USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4026 (class 3256 OID 20159)
-- Name: content_banners Admin Manage Banners; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin Manage Banners" ON public.content_banners USING ((auth.role() = 'authenticated'::text));


--
-- TOC entry 4049 (class 3256 OID 22934)
-- Name: content_banners Admin Manage Content Banners; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin Manage Content Banners" ON public.content_banners USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4046 (class 3256 OID 22931)
-- Name: banners Public Read Banners; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Banners" ON public.banners FOR SELECT USING (true);


--
-- TOC entry 4025 (class 3256 OID 20158)
-- Name: content_banners Public Read Banners; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Banners" ON public.content_banners FOR SELECT USING (true);


--
-- TOC entry 4039 (class 3256 OID 22903)
-- Name: categories Public Read Categories; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Categories" ON public.categories FOR SELECT USING (true);


--
-- TOC entry 4047 (class 3256 OID 22932)
-- Name: content_banners Public Read Content Banners; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Content Banners" ON public.content_banners FOR SELECT USING (true);


--
-- TOC entry 4027 (class 3256 OID 22891)
-- Name: products Public Read Products; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Products" ON public.products FOR SELECT USING (true);


--
-- TOC entry 4037 (class 3256 OID 22901)
-- Name: variants Public Read Variants; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Variants" ON public.variants FOR SELECT USING (true);


--
-- TOC entry 4045 (class 3256 OID 22930)
-- Name: order_items User Create Order Items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User Create Order Items" ON public.order_items FOR INSERT WITH CHECK (true);


--
-- TOC entry 4031 (class 3256 OID 22895)
-- Name: orders User Create Orders; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User Create Orders" ON public.orders FOR INSERT WITH CHECK (true);


--
-- TOC entry 4033 (class 3256 OID 22897)
-- Name: customers User Manage Self; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User Manage Self" ON public.customers USING ((user_id = auth.uid()));


--
-- TOC entry 4042 (class 3256 OID 22927)
-- Name: carts User Own Cart; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User Own Cart" ON public.carts USING ((user_id = auth.uid()));


--
-- TOC entry 4041 (class 3256 OID 22926)
-- Name: cart_items User Own Cart Items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User Own Cart Items" ON public.cart_items USING (((EXISTS ( SELECT 1
   FROM public.carts
  WHERE ((carts.user_id = cart_items.cart_id) AND (carts.user_id = auth.uid())))) OR ((cart_id)::text = (auth.uid())::text)));


--
-- TOC entry 4044 (class 3256 OID 22929)
-- Name: order_items User View Own Order Items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User View Own Order Items" ON public.order_items FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.orders
  WHERE ((orders.id = order_items.order_id) AND (EXISTS ( SELECT 1
           FROM public.customers
          WHERE ((customers.id = orders.customer_id) AND (customers.user_id = auth.uid()))))))));


--
-- TOC entry 4030 (class 3256 OID 22894)
-- Name: orders User View Own Orders; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User View Own Orders" ON public.orders FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.id = orders.customer_id) AND (customers.user_id = auth.uid())))));


--
-- TOC entry 4023 (class 0 OID 21617)
-- Dependencies: 426
-- Name: banners; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.banners ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4017 (class 0 OID 17657)
-- Dependencies: 414
-- Name: cart_items; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4016 (class 0 OID 17650)
-- Dependencies: 412
-- Name: carts; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.carts ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4007 (class 0 OID 17497)
-- Dependencies: 395
-- Name: categories; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4022 (class 0 OID 20148)
-- Dependencies: 424
-- Name: content_banners; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.content_banners ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4014 (class 0 OID 17626)
-- Dependencies: 409
-- Name: customers; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4020 (class 0 OID 17721)
-- Dependencies: 420
-- Name: expense_categories; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.expense_categories ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4021 (class 0 OID 17729)
-- Dependencies: 422
-- Name: expenses; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4013 (class 0 OID 17602)
-- Dependencies: 407
-- Name: inventory_batches; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.inventory_batches ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4019 (class 0 OID 17704)
-- Dependencies: 418
-- Name: order_items; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4018 (class 0 OID 17674)
-- Dependencies: 416
-- Name: orders; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4024 (class 0 OID 23128)
-- Dependencies: 429
-- Name: product_collections; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.product_collections ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4009 (class 0 OID 17522)
-- Dependencies: 399
-- Name: products; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4015 (class 0 OID 17637)
-- Dependencies: 411
-- Name: promotions; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.promotions ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4012 (class 0 OID 17585)
-- Dependencies: 405
-- Name: purchase_items; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.purchase_items ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4011 (class 0 OID 17565)
-- Dependencies: 403
-- Name: purchase_orders; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4006 (class 0 OID 17487)
-- Dependencies: 393
-- Name: stores; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.stores ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4008 (class 0 OID 17513)
-- Dependencies: 397
-- Name: suppliers; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4010 (class 0 OID 17549)
-- Dependencies: 401
-- Name: variants; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.variants ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4094 (class 0 OID 0)
-- Dependencies: 50
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE USAGE ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO PUBLIC;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- TOC entry 4095 (class 0 OID 0)
-- Dependencies: 414
-- Name: TABLE cart_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.cart_items TO service_role;
GRANT SELECT ON TABLE public.cart_items TO anon;


--
-- TOC entry 4096 (class 0 OID 0)
-- Dependencies: 413
-- Name: SEQUENCE cart_items_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.cart_items_id_seq TO service_role;


--
-- TOC entry 4097 (class 0 OID 0)
-- Dependencies: 412
-- Name: TABLE carts; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.carts TO service_role;
GRANT SELECT ON TABLE public.carts TO anon;


--
-- TOC entry 4098 (class 0 OID 0)
-- Dependencies: 395
-- Name: TABLE categories; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.categories TO service_role;
GRANT SELECT ON TABLE public.categories TO anon;


--
-- TOC entry 4099 (class 0 OID 0)
-- Dependencies: 394
-- Name: SEQUENCE categories_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.categories_id_seq TO service_role;


--
-- TOC entry 4100 (class 0 OID 0)
-- Dependencies: 424
-- Name: TABLE content_banners; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.content_banners TO service_role;
GRANT SELECT ON TABLE public.content_banners TO anon;
GRANT SELECT ON TABLE public.content_banners TO authenticated;


--
-- TOC entry 4101 (class 0 OID 0)
-- Dependencies: 409
-- Name: TABLE customers; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.customers TO service_role;
GRANT SELECT ON TABLE public.customers TO anon;
GRANT SELECT,UPDATE ON TABLE public.customers TO authenticated;


--
-- TOC entry 4102 (class 0 OID 0)
-- Dependencies: 408
-- Name: SEQUENCE customers_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.customers_id_seq TO service_role;


--
-- TOC entry 4103 (class 0 OID 0)
-- Dependencies: 420
-- Name: TABLE expense_categories; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.expense_categories TO service_role;
GRANT SELECT ON TABLE public.expense_categories TO anon;


--
-- TOC entry 4104 (class 0 OID 0)
-- Dependencies: 419
-- Name: SEQUENCE expense_categories_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.expense_categories_id_seq TO service_role;


--
-- TOC entry 4105 (class 0 OID 0)
-- Dependencies: 422
-- Name: TABLE expenses; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.expenses TO service_role;
GRANT SELECT ON TABLE public.expenses TO anon;


--
-- TOC entry 4106 (class 0 OID 0)
-- Dependencies: 421
-- Name: SEQUENCE expenses_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.expenses_id_seq TO service_role;


--
-- TOC entry 4107 (class 0 OID 0)
-- Dependencies: 407
-- Name: TABLE inventory_batches; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.inventory_batches TO service_role;
GRANT SELECT ON TABLE public.inventory_batches TO anon;


--
-- TOC entry 4108 (class 0 OID 0)
-- Dependencies: 406
-- Name: SEQUENCE inventory_batches_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.inventory_batches_id_seq TO service_role;


--
-- TOC entry 4109 (class 0 OID 0)
-- Dependencies: 418
-- Name: TABLE order_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.order_items TO service_role;
GRANT SELECT ON TABLE public.order_items TO anon;


--
-- TOC entry 4110 (class 0 OID 0)
-- Dependencies: 417
-- Name: SEQUENCE order_items_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.order_items_id_seq TO service_role;


--
-- TOC entry 4111 (class 0 OID 0)
-- Dependencies: 416
-- Name: TABLE orders; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.orders TO service_role;
GRANT SELECT ON TABLE public.orders TO anon;


--
-- TOC entry 4112 (class 0 OID 0)
-- Dependencies: 415
-- Name: SEQUENCE orders_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.orders_id_seq TO service_role;


--
-- TOC entry 4113 (class 0 OID 0)
-- Dependencies: 429
-- Name: TABLE product_collections; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.product_collections TO service_role;
GRANT ALL ON TABLE public.product_collections TO anon;
GRANT ALL ON TABLE public.product_collections TO authenticated;


--
-- TOC entry 4114 (class 0 OID 0)
-- Dependencies: 399
-- Name: TABLE products; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.products TO service_role;
GRANT SELECT ON TABLE public.products TO anon;


--
-- TOC entry 4115 (class 0 OID 0)
-- Dependencies: 398
-- Name: SEQUENCE products_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.products_id_seq TO service_role;


--
-- TOC entry 4116 (class 0 OID 0)
-- Dependencies: 411
-- Name: TABLE promotions; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.promotions TO service_role;
GRANT SELECT ON TABLE public.promotions TO anon;


--
-- TOC entry 4117 (class 0 OID 0)
-- Dependencies: 410
-- Name: SEQUENCE promotions_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.promotions_id_seq TO service_role;


--
-- TOC entry 4118 (class 0 OID 0)
-- Dependencies: 405
-- Name: TABLE purchase_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.purchase_items TO service_role;
GRANT SELECT ON TABLE public.purchase_items TO anon;


--
-- TOC entry 4119 (class 0 OID 0)
-- Dependencies: 404
-- Name: SEQUENCE purchase_items_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.purchase_items_id_seq TO service_role;


--
-- TOC entry 4120 (class 0 OID 0)
-- Dependencies: 403
-- Name: TABLE purchase_orders; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.purchase_orders TO service_role;
GRANT SELECT ON TABLE public.purchase_orders TO anon;


--
-- TOC entry 4121 (class 0 OID 0)
-- Dependencies: 402
-- Name: SEQUENCE purchase_orders_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.purchase_orders_id_seq TO service_role;


--
-- TOC entry 4122 (class 0 OID 0)
-- Dependencies: 393
-- Name: TABLE stores; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.stores TO service_role;
GRANT SELECT ON TABLE public.stores TO anon;


--
-- TOC entry 4123 (class 0 OID 0)
-- Dependencies: 392
-- Name: SEQUENCE stores_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.stores_id_seq TO service_role;


--
-- TOC entry 4124 (class 0 OID 0)
-- Dependencies: 397
-- Name: TABLE suppliers; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.suppliers TO service_role;
GRANT SELECT ON TABLE public.suppliers TO anon;


--
-- TOC entry 4125 (class 0 OID 0)
-- Dependencies: 396
-- Name: SEQUENCE suppliers_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.suppliers_id_seq TO service_role;


--
-- TOC entry 4126 (class 0 OID 0)
-- Dependencies: 401
-- Name: TABLE variants; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.variants TO service_role;
GRANT SELECT ON TABLE public.variants TO anon;


--
-- TOC entry 4127 (class 0 OID 0)
-- Dependencies: 400
-- Name: SEQUENCE variants_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.variants_id_seq TO service_role;


-- Completed on 2026-01-31 10:13:28

--
-- PostgreSQL database dump complete
--

