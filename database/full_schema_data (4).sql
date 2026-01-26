--
-- PostgreSQL database dump
--

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.5

-- Started on 2026-01-26 21:55:41

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
-- TOC entry 498 (class 1255 OID 21750)
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
-- TOC entry 482 (class 1255 OID 20107)
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
-- TOC entry 494 (class 1255 OID 21695)
-- Name: restore_inventory_on_cancel(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.restore_inventory_on_cancel() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
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
-- TOC entry 419 (class 1259 OID 21617)
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
-- TOC entry 418 (class 1259 OID 21616)
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
-- TOC entry 407 (class 1259 OID 17657)
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
-- TOC entry 406 (class 1259 OID 17656)
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
-- TOC entry 405 (class 1259 OID 17650)
-- Name: carts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.carts (
    user_id uuid NOT NULL,
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.carts OWNER TO postgres;

--
-- TOC entry 387 (class 1259 OID 17497)
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
-- TOC entry 386 (class 1259 OID 17496)
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
-- TOC entry 417 (class 1259 OID 20148)
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
-- TOC entry 416 (class 1259 OID 20147)
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
-- TOC entry 402 (class 1259 OID 17626)
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
-- TOC entry 401 (class 1259 OID 17625)
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
-- TOC entry 413 (class 1259 OID 17721)
-- Name: expense_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.expense_categories (
    id bigint NOT NULL,
    name text NOT NULL,
    description text
);


ALTER TABLE public.expense_categories OWNER TO postgres;

--
-- TOC entry 412 (class 1259 OID 17720)
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
-- TOC entry 415 (class 1259 OID 17729)
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
-- TOC entry 414 (class 1259 OID 17728)
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
-- TOC entry 400 (class 1259 OID 17602)
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
-- TOC entry 399 (class 1259 OID 17601)
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
-- TOC entry 411 (class 1259 OID 17704)
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
-- TOC entry 410 (class 1259 OID 17703)
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
-- TOC entry 409 (class 1259 OID 17674)
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
-- TOC entry 408 (class 1259 OID 17673)
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
-- TOC entry 392 (class 1259 OID 17533)
-- Name: product_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.product_categories (
    product_id bigint NOT NULL,
    category_id bigint NOT NULL
);


ALTER TABLE public.product_categories OWNER TO postgres;

--
-- TOC entry 391 (class 1259 OID 17522)
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
-- TOC entry 390 (class 1259 OID 17521)
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
-- TOC entry 404 (class 1259 OID 17637)
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
-- TOC entry 403 (class 1259 OID 17636)
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
-- TOC entry 398 (class 1259 OID 17585)
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
-- TOC entry 397 (class 1259 OID 17584)
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
-- TOC entry 396 (class 1259 OID 17565)
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
-- TOC entry 395 (class 1259 OID 17564)
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
-- TOC entry 385 (class 1259 OID 17487)
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
-- TOC entry 384 (class 1259 OID 17486)
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
-- TOC entry 389 (class 1259 OID 17513)
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
-- TOC entry 388 (class 1259 OID 17512)
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
-- TOC entry 394 (class 1259 OID 17549)
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
-- TOC entry 393 (class 1259 OID 17548)
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
-- TOC entry 4073 (class 0 OID 21617)
-- Dependencies: 419
-- Data for Name: banners; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.banners (id, title, image_url, link_url, is_active, created_at) FROM stdin;
\.


--
-- TOC entry 4061 (class 0 OID 17657)
-- Dependencies: 407
-- Data for Name: cart_items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.cart_items (id, cart_id, variant_id, quantity) FROM stdin;
\.


--
-- TOC entry 4059 (class 0 OID 17650)
-- Dependencies: 405
-- Data for Name: carts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.carts (user_id, updated_at) FROM stdin;
\.


--
-- TOC entry 4041 (class 0 OID 17497)
-- Dependencies: 387
-- Data for Name: categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.categories (id, name, slug, parent_id, created_at) FROM stdin;
1	TOPS	tops	\N	2026-01-26 13:33:39.51621+00
2	BOTTOMS	bottoms	\N	2026-01-26 14:07:55.177475+00
3	BIKINI	bikini	\N	2026-01-26 14:29:28.485714+00
\.


--
-- TOC entry 4071 (class 0 OID 20148)
-- Dependencies: 417
-- Data for Name: content_banners; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.content_banners (id, title, image_url, link_to, display_order, is_active, created_at) FROM stdin;
1	NEW COLLECTION	https://dbuwgocouxlpxulnlajl.supabase.co/storage/v1/object/public/products/1769434732353-776223602.png	/collection 	1	t	2026-01-26 13:38:53.880967+00
\.


--
-- TOC entry 4056 (class 0 OID 17626)
-- Dependencies: 402
-- Data for Name: customers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.customers (id, user_id, full_name, phone, email, address, loyalty_points, created_at, role, avatar_url) FROM stdin;
\.


--
-- TOC entry 4067 (class 0 OID 17721)
-- Dependencies: 413
-- Data for Name: expense_categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.expense_categories (id, name, description) FROM stdin;
\.


--
-- TOC entry 4069 (class 0 OID 17729)
-- Dependencies: 415
-- Data for Name: expenses; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.expenses (id, store_id, category_id, amount, expense_date, note, created_at) FROM stdin;
\.


--
-- TOC entry 4054 (class 0 OID 17602)
-- Dependencies: 400
-- Data for Name: inventory_batches; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.inventory_batches (id, store_id, variant_id, purchase_item_id, original_quantity, quantity_remaining, cost_price, created_at, batch_name, supplier_id) FROM stdin;
\.


--
-- TOC entry 4065 (class 0 OID 17704)
-- Dependencies: 411
-- Data for Name: order_items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.order_items (id, order_id, variant_id, quantity, price_at_purchase, cogs_total) FROM stdin;
\.


--
-- TOC entry 4063 (class 0 OID 17674)
-- Dependencies: 409
-- Data for Name: orders; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.orders (id, code, customer_id, store_id, promotion_id, subtotal, discount_amount, shipping_fee, total_amount, payment_method, status, note, created_at, customer_name, customer_phone, customer_address, customer_email, shipping_carrier, shipping_tracking_code, payment_status, email, customer_district_id, customer_ward_code) FROM stdin;
\.


--
-- TOC entry 4046 (class 0 OID 17533)
-- Dependencies: 392
-- Data for Name: product_categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.product_categories (product_id, category_id) FROM stdin;
\.


--
-- TOC entry 4045 (class 0 OID 17522)
-- Dependencies: 391
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.products (id, name, slug, description, base_price, images, is_active, created_at, category_id, size_chart_url) FROM stdin;
3	SKIRT HONEY DRESS 	skirt-honey-dress--1769437468949	Thành phần : 75% Nylon 25% Elastane \nChân váy dài lưng thấp cạp xéo, gập viền hoặc ko tuỳ thích.\nTất cả các phép đo kích thước đều được tính bằng cm.	280000	{https://dbuwgocouxlpxulnlajl.supabase.co/storage/v1/object/public/products/1769437256940-692183683.png,https://dbuwgocouxlpxulnlajl.supabase.co/storage/v1/object/public/products/1769437291447-883303566.jpg,https://dbuwgocouxlpxulnlajl.supabase.co/storage/v1/object/public/products/1769437298628-945059495.jpg,https://dbuwgocouxlpxulnlajl.supabase.co/storage/v1/object/public/products/1769437320838-245200297.jpg,https://dbuwgocouxlpxulnlajl.supabase.co/storage/v1/object/public/products/1769437326442-534215007.jpg,https://dbuwgocouxlpxulnlajl.supabase.co/storage/v1/object/public/products/1769437328584-961862475.jpg,https://dbuwgocouxlpxulnlajl.supabase.co/storage/v1/object/public/products/1769437343187-144847436.jpg,https://dbuwgocouxlpxulnlajl.supabase.co/storage/v1/object/public/products/1769437347076-493215297.jpg,https://dbuwgocouxlpxulnlajl.supabase.co/storage/v1/object/public/products/1769437346958-571725637.jpg}	t	2026-01-26 14:24:29.537851+00	2	https://dbuwgocouxlpxulnlajl.supabase.co/storage/v1/object/public/products/1769437412978-266722519.png
\.


--
-- TOC entry 4058 (class 0 OID 17637)
-- Dependencies: 404
-- Data for Name: promotions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.promotions (id, code, description, discount_type, discount_value, min_order_value, start_date, end_date, requires_account, is_active, usage_limit, used_count, max_discount_amount) FROM stdin;
\.


--
-- TOC entry 4052 (class 0 OID 17585)
-- Dependencies: 398
-- Data for Name: purchase_items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.purchase_items (id, purchase_order_id, variant_id, quantity, unit_cost) FROM stdin;
\.


--
-- TOC entry 4050 (class 0 OID 17565)
-- Dependencies: 396
-- Data for Name: purchase_orders; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.purchase_orders (id, supplier_id, store_id, total_cost, note, purchase_date, code, status) FROM stdin;
1	1	1	2000000	\N	2026-01-26 14:30:59.902993+00	\N	\N
\.


--
-- TOC entry 4039 (class 0 OID 17487)
-- Dependencies: 385
-- Data for Name: stores; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.stores (id, name, address, phone, is_active, created_at) FROM stdin;
1	15 Nguyễn Xuân Khoát	\N	\N	t	2026-01-26 14:30:34.21197+00
\.


--
-- TOC entry 4043 (class 0 OID 17513)
-- Dependencies: 389
-- Data for Name: suppliers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.suppliers (id, name, created_at, phone, address) FROM stdin;
1	Qlee	2026-01-26 14:30:15.248688+00	\N	\N
\.


--
-- TOC entry 4048 (class 0 OID 17549)
-- Dependencies: 394
-- Data for Name: variants; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.variants (id, product_id, sku, size, color, current_price, image_url, created_at, weight) FROM stdin;
13	3	Váy Dài Trắng	Free	Trắng	\N	\N	2026-01-26 14:24:29.889264+00	500
14	3	Váy Dài Đen	Free	Đen	\N	\N	2026-01-26 14:24:29.889264+00	500
\.


--
-- TOC entry 4113 (class 0 OID 0)
-- Dependencies: 418
-- Name: banners_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.banners_id_seq', 1, false);


--
-- TOC entry 4114 (class 0 OID 0)
-- Dependencies: 406
-- Name: cart_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.cart_items_id_seq', 1, false);


--
-- TOC entry 4115 (class 0 OID 0)
-- Dependencies: 386
-- Name: categories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.categories_id_seq', 3, true);


--
-- TOC entry 4116 (class 0 OID 0)
-- Dependencies: 416
-- Name: content_banners_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.content_banners_id_seq', 2, true);


--
-- TOC entry 4117 (class 0 OID 0)
-- Dependencies: 401
-- Name: customers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.customers_id_seq', 1, false);


--
-- TOC entry 4118 (class 0 OID 0)
-- Dependencies: 412
-- Name: expense_categories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.expense_categories_id_seq', 1, false);


--
-- TOC entry 4119 (class 0 OID 0)
-- Dependencies: 414
-- Name: expenses_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.expenses_id_seq', 1, false);


--
-- TOC entry 4120 (class 0 OID 0)
-- Dependencies: 399
-- Name: inventory_batches_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.inventory_batches_id_seq', 1, true);


--
-- TOC entry 4121 (class 0 OID 0)
-- Dependencies: 410
-- Name: order_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.order_items_id_seq', 1, false);


--
-- TOC entry 4122 (class 0 OID 0)
-- Dependencies: 408
-- Name: orders_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.orders_id_seq', 1, false);


--
-- TOC entry 4123 (class 0 OID 0)
-- Dependencies: 390
-- Name: products_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.products_id_seq', 3, true);


--
-- TOC entry 4124 (class 0 OID 0)
-- Dependencies: 403
-- Name: promotions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.promotions_id_seq', 1, false);


--
-- TOC entry 4125 (class 0 OID 0)
-- Dependencies: 397
-- Name: purchase_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.purchase_items_id_seq', 1, true);


--
-- TOC entry 4126 (class 0 OID 0)
-- Dependencies: 395
-- Name: purchase_orders_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.purchase_orders_id_seq', 1, true);


--
-- TOC entry 4127 (class 0 OID 0)
-- Dependencies: 384
-- Name: stores_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.stores_id_seq', 1, true);


--
-- TOC entry 4128 (class 0 OID 0)
-- Dependencies: 388
-- Name: suppliers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.suppliers_id_seq', 1, true);


--
-- TOC entry 4129 (class 0 OID 0)
-- Dependencies: 393
-- Name: variants_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.variants_id_seq', 14, true);


--
-- TOC entry 3824 (class 2606 OID 21625)
-- Name: banners banners_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.banners
    ADD CONSTRAINT banners_pkey PRIMARY KEY (id);


--
-- TOC entry 3807 (class 2606 OID 17662)
-- Name: cart_items cart_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cart_items
    ADD CONSTRAINT cart_items_pkey PRIMARY KEY (id);


--
-- TOC entry 3805 (class 2606 OID 17655)
-- Name: carts carts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.carts
    ADD CONSTRAINT carts_pkey PRIMARY KEY (user_id);


--
-- TOC entry 3773 (class 2606 OID 17504)
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- TOC entry 3775 (class 2606 OID 17506)
-- Name: categories categories_slug_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_slug_key UNIQUE (slug);


--
-- TOC entry 3822 (class 2606 OID 20157)
-- Name: content_banners content_banners_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_banners
    ADD CONSTRAINT content_banners_pkey PRIMARY KEY (id);


--
-- TOC entry 3798 (class 2606 OID 17634)
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- TOC entry 3818 (class 2606 OID 17727)
-- Name: expense_categories expense_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.expense_categories
    ADD CONSTRAINT expense_categories_pkey PRIMARY KEY (id);


--
-- TOC entry 3820 (class 2606 OID 17737)
-- Name: expenses expenses_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_pkey PRIMARY KEY (id);


--
-- TOC entry 3796 (class 2606 OID 17608)
-- Name: inventory_batches inventory_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_pkey PRIMARY KEY (id);


--
-- TOC entry 3816 (class 2606 OID 17709)
-- Name: order_items order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (id);


--
-- TOC entry 3810 (class 2606 OID 17687)
-- Name: orders orders_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_code_key UNIQUE (code);


--
-- TOC entry 3812 (class 2606 OID 17685)
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- TOC entry 3783 (class 2606 OID 17537)
-- Name: product_categories product_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_categories
    ADD CONSTRAINT product_categories_pkey PRIMARY KEY (product_id, category_id);


--
-- TOC entry 3779 (class 2606 OID 17530)
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- TOC entry 3781 (class 2606 OID 17532)
-- Name: products products_slug_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_slug_key UNIQUE (slug);


--
-- TOC entry 3801 (class 2606 OID 17649)
-- Name: promotions promotions_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promotions
    ADD CONSTRAINT promotions_code_key UNIQUE (code);


--
-- TOC entry 3803 (class 2606 OID 17647)
-- Name: promotions promotions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promotions
    ADD CONSTRAINT promotions_pkey PRIMARY KEY (id);


--
-- TOC entry 3793 (class 2606 OID 17590)
-- Name: purchase_items purchase_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_items
    ADD CONSTRAINT purchase_items_pkey PRIMARY KEY (id);


--
-- TOC entry 3789 (class 2606 OID 21610)
-- Name: purchase_orders purchase_orders_code_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_code_unique UNIQUE (code);


--
-- TOC entry 3791 (class 2606 OID 17573)
-- Name: purchase_orders purchase_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_pkey PRIMARY KEY (id);


--
-- TOC entry 3771 (class 2606 OID 17495)
-- Name: stores stores_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stores
    ADD CONSTRAINT stores_pkey PRIMARY KEY (id);


--
-- TOC entry 3777 (class 2606 OID 17520)
-- Name: suppliers suppliers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_pkey PRIMARY KEY (id);


--
-- TOC entry 3785 (class 2606 OID 17556)
-- Name: variants variants_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.variants
    ADD CONSTRAINT variants_pkey PRIMARY KEY (id);


--
-- TOC entry 3787 (class 2606 OID 17558)
-- Name: variants variants_sku_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.variants
    ADD CONSTRAINT variants_sku_key UNIQUE (sku);


--
-- TOC entry 3808 (class 1259 OID 22937)
-- Name: idx_cart_items_variant_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cart_items_variant_id ON public.cart_items USING btree (variant_id);


--
-- TOC entry 3799 (class 1259 OID 17635)
-- Name: idx_customer_phone; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_customer_phone ON public.customers USING btree (phone);


--
-- TOC entry 3794 (class 1259 OID 17624)
-- Name: idx_inventory_fifo; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_inventory_fifo ON public.inventory_batches USING btree (store_id, variant_id, created_at);


--
-- TOC entry 3813 (class 1259 OID 22935)
-- Name: idx_order_items_order_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_order_items_order_id ON public.order_items USING btree (order_id);


--
-- TOC entry 3814 (class 1259 OID 22936)
-- Name: idx_order_items_variant_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_order_items_variant_id ON public.order_items USING btree (variant_id);


--
-- TOC entry 3846 (class 2620 OID 21696)
-- Name: orders trigger_restore_inventory; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_restore_inventory AFTER UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.restore_inventory_on_cancel();


--
-- TOC entry 3837 (class 2606 OID 17663)
-- Name: cart_items cart_items_cart_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cart_items
    ADD CONSTRAINT cart_items_cart_id_fkey FOREIGN KEY (cart_id) REFERENCES public.carts(user_id) ON DELETE CASCADE;


--
-- TOC entry 3838 (class 2606 OID 17668)
-- Name: cart_items cart_items_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cart_items
    ADD CONSTRAINT cart_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.variants(id);


--
-- TOC entry 3825 (class 2606 OID 17507)
-- Name: categories categories_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.categories(id) ON DELETE SET NULL;


--
-- TOC entry 3844 (class 2606 OID 17743)
-- Name: expenses expenses_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.expense_categories(id);


--
-- TOC entry 3845 (class 2606 OID 17738)
-- Name: expenses expenses_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id);


--
-- TOC entry 3833 (class 2606 OID 17619)
-- Name: inventory_batches inventory_batches_purchase_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_purchase_item_id_fkey FOREIGN KEY (purchase_item_id) REFERENCES public.purchase_items(id);


--
-- TOC entry 3834 (class 2606 OID 17609)
-- Name: inventory_batches inventory_batches_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id);


--
-- TOC entry 3835 (class 2606 OID 17883)
-- Name: inventory_batches inventory_batches_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id);


--
-- TOC entry 3836 (class 2606 OID 17614)
-- Name: inventory_batches inventory_batches_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.variants(id);


--
-- TOC entry 3842 (class 2606 OID 17710)
-- Name: order_items order_items_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- TOC entry 3843 (class 2606 OID 17715)
-- Name: order_items order_items_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.variants(id);


--
-- TOC entry 3839 (class 2606 OID 17688)
-- Name: orders orders_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- TOC entry 3840 (class 2606 OID 17698)
-- Name: orders orders_promotion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_promotion_id_fkey FOREIGN KEY (promotion_id) REFERENCES public.promotions(id);


--
-- TOC entry 3841 (class 2606 OID 17693)
-- Name: orders orders_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id);


--
-- TOC entry 3826 (class 2606 OID 17543)
-- Name: product_categories product_categories_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_categories
    ADD CONSTRAINT product_categories_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id) ON DELETE CASCADE;


--
-- TOC entry 3827 (class 2606 OID 17538)
-- Name: product_categories product_categories_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_categories
    ADD CONSTRAINT product_categories_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- TOC entry 3831 (class 2606 OID 17591)
-- Name: purchase_items purchase_items_purchase_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_items
    ADD CONSTRAINT purchase_items_purchase_order_id_fkey FOREIGN KEY (purchase_order_id) REFERENCES public.purchase_orders(id) ON DELETE CASCADE;


--
-- TOC entry 3832 (class 2606 OID 17596)
-- Name: purchase_items purchase_items_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_items
    ADD CONSTRAINT purchase_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.variants(id);


--
-- TOC entry 3829 (class 2606 OID 17579)
-- Name: purchase_orders purchase_orders_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id);


--
-- TOC entry 3830 (class 2606 OID 17574)
-- Name: purchase_orders purchase_orders_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id);


--
-- TOC entry 3828 (class 2606 OID 17559)
-- Name: variants variants_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.variants
    ADD CONSTRAINT variants_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- TOC entry 4025 (class 3256 OID 22904)
-- Name: categories Admin All Categories; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Categories" ON public.categories USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4017 (class 3256 OID 22896)
-- Name: customers Admin All Customers; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Customers" ON public.customers USING ((EXISTS ( SELECT 1
   FROM public.customers customers_1
  WHERE ((customers_1.user_id = auth.uid()) AND (customers_1.role = 'admin'::text)))));


--
-- TOC entry 4019 (class 3256 OID 22898)
-- Name: expenses Admin All Expenses; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Expenses" ON public.expenses USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4020 (class 3256 OID 22899)
-- Name: inventory_batches Admin All Inventory; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Inventory" ON public.inventory_batches USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4028 (class 3256 OID 22928)
-- Name: order_items Admin All Order Items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Order Items" ON public.order_items USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4014 (class 3256 OID 22893)
-- Name: orders Admin All Orders; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Orders" ON public.orders USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4013 (class 3256 OID 22892)
-- Name: products Admin All Products; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Products" ON public.products USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4021 (class 3256 OID 22900)
-- Name: promotions Admin All Promotions; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Promotions" ON public.promotions USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4023 (class 3256 OID 22902)
-- Name: variants Admin All Variants; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Variants" ON public.variants USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4033 (class 3256 OID 22933)
-- Name: banners Admin Manage Banners; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin Manage Banners" ON public.banners USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4011 (class 3256 OID 20159)
-- Name: content_banners Admin Manage Banners; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin Manage Banners" ON public.content_banners USING ((auth.role() = 'authenticated'::text));


--
-- TOC entry 4034 (class 3256 OID 22934)
-- Name: content_banners Admin Manage Content Banners; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin Manage Content Banners" ON public.content_banners USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4031 (class 3256 OID 22931)
-- Name: banners Public Read Banners; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Banners" ON public.banners FOR SELECT USING (true);


--
-- TOC entry 4010 (class 3256 OID 20158)
-- Name: content_banners Public Read Banners; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Banners" ON public.content_banners FOR SELECT USING (true);


--
-- TOC entry 4024 (class 3256 OID 22903)
-- Name: categories Public Read Categories; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Categories" ON public.categories FOR SELECT USING (true);


--
-- TOC entry 4032 (class 3256 OID 22932)
-- Name: content_banners Public Read Content Banners; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Content Banners" ON public.content_banners FOR SELECT USING (true);


--
-- TOC entry 4009 (class 3256 OID 17850)
-- Name: product_categories Public Read Product Categories; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Product Categories" ON public.product_categories FOR SELECT USING (true);


--
-- TOC entry 4012 (class 3256 OID 22891)
-- Name: products Public Read Products; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Products" ON public.products FOR SELECT USING (true);


--
-- TOC entry 4022 (class 3256 OID 22901)
-- Name: variants Public Read Variants; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Variants" ON public.variants FOR SELECT USING (true);


--
-- TOC entry 4030 (class 3256 OID 22930)
-- Name: order_items User Create Order Items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User Create Order Items" ON public.order_items FOR INSERT WITH CHECK (true);


--
-- TOC entry 4016 (class 3256 OID 22895)
-- Name: orders User Create Orders; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User Create Orders" ON public.orders FOR INSERT WITH CHECK (true);


--
-- TOC entry 4018 (class 3256 OID 22897)
-- Name: customers User Manage Self; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User Manage Self" ON public.customers USING ((user_id = auth.uid()));


--
-- TOC entry 4027 (class 3256 OID 22927)
-- Name: carts User Own Cart; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User Own Cart" ON public.carts USING ((user_id = auth.uid()));


--
-- TOC entry 4026 (class 3256 OID 22926)
-- Name: cart_items User Own Cart Items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User Own Cart Items" ON public.cart_items USING (((EXISTS ( SELECT 1
   FROM public.carts
  WHERE ((carts.user_id = cart_items.cart_id) AND (carts.user_id = auth.uid())))) OR ((cart_id)::text = (auth.uid())::text)));


--
-- TOC entry 4029 (class 3256 OID 22929)
-- Name: order_items User View Own Order Items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User View Own Order Items" ON public.order_items FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.orders
  WHERE ((orders.id = order_items.order_id) AND (EXISTS ( SELECT 1
           FROM public.customers
          WHERE ((customers.id = orders.customer_id) AND (customers.user_id = auth.uid()))))))));


--
-- TOC entry 4015 (class 3256 OID 22894)
-- Name: orders User View Own Orders; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User View Own Orders" ON public.orders FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.id = orders.customer_id) AND (customers.user_id = auth.uid())))));


--
-- TOC entry 4008 (class 0 OID 21617)
-- Dependencies: 419
-- Name: banners; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.banners ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4003 (class 0 OID 17657)
-- Dependencies: 407
-- Name: cart_items; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4002 (class 0 OID 17650)
-- Dependencies: 405
-- Name: carts; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.carts ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 3995 (class 0 OID 17497)
-- Dependencies: 387
-- Name: categories; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4007 (class 0 OID 20148)
-- Dependencies: 417
-- Name: content_banners; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.content_banners ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4000 (class 0 OID 17626)
-- Dependencies: 402
-- Name: customers; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4006 (class 0 OID 17729)
-- Dependencies: 415
-- Name: expenses; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 3999 (class 0 OID 17602)
-- Dependencies: 400
-- Name: inventory_batches; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.inventory_batches ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4005 (class 0 OID 17704)
-- Dependencies: 411
-- Name: order_items; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4004 (class 0 OID 17674)
-- Dependencies: 409
-- Name: orders; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 3997 (class 0 OID 17533)
-- Dependencies: 392
-- Name: product_categories; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.product_categories ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 3996 (class 0 OID 17522)
-- Dependencies: 391
-- Name: products; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4001 (class 0 OID 17637)
-- Dependencies: 404
-- Name: promotions; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.promotions ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 3998 (class 0 OID 17549)
-- Dependencies: 394
-- Name: variants; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.variants ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4079 (class 0 OID 0)
-- Dependencies: 50
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE USAGE ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO PUBLIC;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- TOC entry 4080 (class 0 OID 0)
-- Dependencies: 407
-- Name: TABLE cart_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.cart_items TO service_role;
GRANT SELECT ON TABLE public.cart_items TO anon;


--
-- TOC entry 4081 (class 0 OID 0)
-- Dependencies: 406
-- Name: SEQUENCE cart_items_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.cart_items_id_seq TO service_role;


--
-- TOC entry 4082 (class 0 OID 0)
-- Dependencies: 405
-- Name: TABLE carts; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.carts TO service_role;
GRANT SELECT ON TABLE public.carts TO anon;


--
-- TOC entry 4083 (class 0 OID 0)
-- Dependencies: 387
-- Name: TABLE categories; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.categories TO service_role;
GRANT SELECT ON TABLE public.categories TO anon;


--
-- TOC entry 4084 (class 0 OID 0)
-- Dependencies: 386
-- Name: SEQUENCE categories_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.categories_id_seq TO service_role;


--
-- TOC entry 4085 (class 0 OID 0)
-- Dependencies: 417
-- Name: TABLE content_banners; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.content_banners TO service_role;
GRANT SELECT ON TABLE public.content_banners TO anon;
GRANT SELECT ON TABLE public.content_banners TO authenticated;


--
-- TOC entry 4086 (class 0 OID 0)
-- Dependencies: 402
-- Name: TABLE customers; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.customers TO service_role;
GRANT SELECT ON TABLE public.customers TO anon;
GRANT SELECT,UPDATE ON TABLE public.customers TO authenticated;


--
-- TOC entry 4087 (class 0 OID 0)
-- Dependencies: 401
-- Name: SEQUENCE customers_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.customers_id_seq TO service_role;


--
-- TOC entry 4088 (class 0 OID 0)
-- Dependencies: 413
-- Name: TABLE expense_categories; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.expense_categories TO service_role;
GRANT SELECT ON TABLE public.expense_categories TO anon;


--
-- TOC entry 4089 (class 0 OID 0)
-- Dependencies: 412
-- Name: SEQUENCE expense_categories_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.expense_categories_id_seq TO service_role;


--
-- TOC entry 4090 (class 0 OID 0)
-- Dependencies: 415
-- Name: TABLE expenses; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.expenses TO service_role;
GRANT SELECT ON TABLE public.expenses TO anon;


--
-- TOC entry 4091 (class 0 OID 0)
-- Dependencies: 414
-- Name: SEQUENCE expenses_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.expenses_id_seq TO service_role;


--
-- TOC entry 4092 (class 0 OID 0)
-- Dependencies: 400
-- Name: TABLE inventory_batches; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.inventory_batches TO service_role;
GRANT SELECT ON TABLE public.inventory_batches TO anon;


--
-- TOC entry 4093 (class 0 OID 0)
-- Dependencies: 399
-- Name: SEQUENCE inventory_batches_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.inventory_batches_id_seq TO service_role;


--
-- TOC entry 4094 (class 0 OID 0)
-- Dependencies: 411
-- Name: TABLE order_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.order_items TO service_role;
GRANT SELECT ON TABLE public.order_items TO anon;


--
-- TOC entry 4095 (class 0 OID 0)
-- Dependencies: 410
-- Name: SEQUENCE order_items_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.order_items_id_seq TO service_role;


--
-- TOC entry 4096 (class 0 OID 0)
-- Dependencies: 409
-- Name: TABLE orders; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.orders TO service_role;
GRANT SELECT ON TABLE public.orders TO anon;


--
-- TOC entry 4097 (class 0 OID 0)
-- Dependencies: 408
-- Name: SEQUENCE orders_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.orders_id_seq TO service_role;


--
-- TOC entry 4098 (class 0 OID 0)
-- Dependencies: 392
-- Name: TABLE product_categories; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.product_categories TO service_role;
GRANT SELECT ON TABLE public.product_categories TO anon;


--
-- TOC entry 4099 (class 0 OID 0)
-- Dependencies: 391
-- Name: TABLE products; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.products TO service_role;
GRANT SELECT ON TABLE public.products TO anon;


--
-- TOC entry 4100 (class 0 OID 0)
-- Dependencies: 390
-- Name: SEQUENCE products_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.products_id_seq TO service_role;


--
-- TOC entry 4101 (class 0 OID 0)
-- Dependencies: 404
-- Name: TABLE promotions; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.promotions TO service_role;
GRANT SELECT ON TABLE public.promotions TO anon;


--
-- TOC entry 4102 (class 0 OID 0)
-- Dependencies: 403
-- Name: SEQUENCE promotions_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.promotions_id_seq TO service_role;


--
-- TOC entry 4103 (class 0 OID 0)
-- Dependencies: 398
-- Name: TABLE purchase_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.purchase_items TO service_role;
GRANT SELECT ON TABLE public.purchase_items TO anon;


--
-- TOC entry 4104 (class 0 OID 0)
-- Dependencies: 397
-- Name: SEQUENCE purchase_items_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.purchase_items_id_seq TO service_role;


--
-- TOC entry 4105 (class 0 OID 0)
-- Dependencies: 396
-- Name: TABLE purchase_orders; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.purchase_orders TO service_role;
GRANT SELECT ON TABLE public.purchase_orders TO anon;


--
-- TOC entry 4106 (class 0 OID 0)
-- Dependencies: 395
-- Name: SEQUENCE purchase_orders_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.purchase_orders_id_seq TO service_role;


--
-- TOC entry 4107 (class 0 OID 0)
-- Dependencies: 385
-- Name: TABLE stores; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.stores TO service_role;
GRANT SELECT ON TABLE public.stores TO anon;


--
-- TOC entry 4108 (class 0 OID 0)
-- Dependencies: 384
-- Name: SEQUENCE stores_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.stores_id_seq TO service_role;


--
-- TOC entry 4109 (class 0 OID 0)
-- Dependencies: 389
-- Name: TABLE suppliers; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.suppliers TO service_role;
GRANT SELECT ON TABLE public.suppliers TO anon;


--
-- TOC entry 4110 (class 0 OID 0)
-- Dependencies: 388
-- Name: SEQUENCE suppliers_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.suppliers_id_seq TO service_role;


--
-- TOC entry 4111 (class 0 OID 0)
-- Dependencies: 394
-- Name: TABLE variants; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.variants TO service_role;
GRANT SELECT ON TABLE public.variants TO anon;


--
-- TOC entry 4112 (class 0 OID 0)
-- Dependencies: 393
-- Name: SEQUENCE variants_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.variants_id_seq TO service_role;


-- Completed on 2026-01-26 21:55:59

--
-- PostgreSQL database dump complete
--

