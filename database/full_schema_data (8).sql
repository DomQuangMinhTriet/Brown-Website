--
-- PostgreSQL database dump
--

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.5

-- Started on 2026-02-27 09:22:48

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
-- TOC entry 499 (class 1255 OID 21750)
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
-- TOC entry 486 (class 1255 OID 20107)
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
-- TOC entry 496 (class 1255 OID 21695)
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
-- TOC entry 425 (class 1259 OID 21617)
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
-- TOC entry 424 (class 1259 OID 21616)
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
-- TOC entry 413 (class 1259 OID 17657)
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
-- TOC entry 412 (class 1259 OID 17656)
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
-- TOC entry 411 (class 1259 OID 17650)
-- Name: carts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.carts (
    user_id uuid NOT NULL,
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.carts OWNER TO postgres;

--
-- TOC entry 394 (class 1259 OID 17497)
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
-- TOC entry 393 (class 1259 OID 17496)
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
-- TOC entry 423 (class 1259 OID 20148)
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
-- TOC entry 422 (class 1259 OID 20147)
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
-- TOC entry 408 (class 1259 OID 17626)
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
-- TOC entry 407 (class 1259 OID 17625)
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
-- TOC entry 419 (class 1259 OID 17721)
-- Name: expense_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.expense_categories (
    id bigint NOT NULL,
    name text NOT NULL,
    description text
);


ALTER TABLE public.expense_categories OWNER TO postgres;

--
-- TOC entry 418 (class 1259 OID 17720)
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
-- TOC entry 421 (class 1259 OID 17729)
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
-- TOC entry 420 (class 1259 OID 17728)
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
-- TOC entry 406 (class 1259 OID 17602)
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
-- TOC entry 405 (class 1259 OID 17601)
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
-- TOC entry 417 (class 1259 OID 17704)
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
-- TOC entry 416 (class 1259 OID 17703)
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
-- TOC entry 415 (class 1259 OID 17674)
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
-- TOC entry 414 (class 1259 OID 17673)
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
-- TOC entry 426 (class 1259 OID 23128)
-- Name: product_collections; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.product_collections (
    product_id bigint NOT NULL,
    category_id bigint NOT NULL
);


ALTER TABLE public.product_collections OWNER TO postgres;

--
-- TOC entry 398 (class 1259 OID 17522)
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
-- TOC entry 397 (class 1259 OID 17521)
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
-- TOC entry 410 (class 1259 OID 17637)
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
-- TOC entry 409 (class 1259 OID 17636)
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
-- TOC entry 404 (class 1259 OID 17585)
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
-- TOC entry 403 (class 1259 OID 17584)
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
-- TOC entry 402 (class 1259 OID 17565)
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
-- TOC entry 401 (class 1259 OID 17564)
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
-- TOC entry 392 (class 1259 OID 17487)
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
-- TOC entry 391 (class 1259 OID 17486)
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
-- TOC entry 396 (class 1259 OID 17513)
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
-- TOC entry 395 (class 1259 OID 17512)
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
-- TOC entry 400 (class 1259 OID 17549)
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
-- TOC entry 399 (class 1259 OID 17548)
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
-- TOC entry 4078 (class 0 OID 21617)
-- Dependencies: 425
-- Data for Name: banners; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.banners (id, title, image_url, link_url, is_active, created_at) FROM stdin;
\.


--
-- TOC entry 4066 (class 0 OID 17657)
-- Dependencies: 413
-- Data for Name: cart_items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.cart_items (id, cart_id, variant_id, quantity) FROM stdin;
\.


--
-- TOC entry 4064 (class 0 OID 17650)
-- Dependencies: 411
-- Data for Name: carts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.carts (user_id, updated_at) FROM stdin;
\.


--
-- TOC entry 4047 (class 0 OID 17497)
-- Dependencies: 394
-- Data for Name: categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.categories (id, name, slug, parent_id, created_at, is_visible_on_home) FROM stdin;
4	JEANS	jeans	\N	2026-01-27 08:56:56.151804+00	f
5	TEST	test	\N	2026-02-03 01:19:02.337362+00	f
3	BIKINI	bikini	\N	2026-01-26 14:29:28.485714+00	t
2	BOTTOMS	bottoms	\N	2026-01-26 14:07:55.177475+00	t
1	TOPS	tops	\N	2026-01-26 13:33:39.51621+00	t
\.


--
-- TOC entry 4076 (class 0 OID 20148)
-- Dependencies: 423
-- Data for Name: content_banners; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.content_banners (id, title, image_url, link_to, display_order, is_active, created_at) FROM stdin;
4	BROWN	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769145/brown_migration/nukinhe2ozewpdgbgrag.webp		0	t	2026-01-27 10:29:56.871449+00
\.


--
-- TOC entry 4061 (class 0 OID 17626)
-- Dependencies: 408
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
10	\N	thuỳ trang 	0987346948	chanxinh2505@gmail.com	282 ấp bình phước	0	2026-01-31 07:16:10.353997+00	user	\N
11	\N	Nguyễn Thị Vân Anh	0857900799	anhnv270199@gmail.com	Toà TNR, 54A Nguyễn Chí Thanh₫	0	2026-01-31 10:54:07.447234+00	user	\N
12	\N	SU	0976685522	\N	chung cư khánh hội 3, 360G Bến Vân Đồn P1, Q4	0	2026-01-31 17:03:43.254711+00	user	\N
13	\N	ngọc ngọc 	0988224226 	\N	132 bến vân đồn P6 Q4	0	2026-02-01 03:32:44.648068+00	user	\N
14	\N	Thuy an	0377029438	\N	183 đan kia phường 7 đà lạt	0	2026-02-01 03:37:41.611836+00	user	\N
15	\N	Tô vân 	0962755240	\N	30 Yên Ninh, Ba Đình, HN 	0	2026-02-01 03:42:25.208591+00	user	\N
16	\N	Phương Thi 	0937809293 	\N	Toà nhà Lafayatte số 8 đường Phùng Khắc Khoan phường Sài Gòn TPHCM - Lầu 2 APRIL	0	2026-02-01 03:45:27.086863+00	user	\N
17	\N	Bảo Trinh	0359501066	tranhabaotrinh@gmail.com	Vinhomes grand park q9 toà Be5	0	2026-02-01 04:35:26.327534+00	user	\N
18	\N	ttrraamm	0789515460	\N	Khách tới nhà lấy	0	2026-02-01 06:19:51.41484+00	user	\N
19	\N	Thư 	 0902905362	\N	114 đồng văn cống, phường cát lái, hcm	0	2026-02-01 06:22:27.932773+00	user	\N
20	\N	Vũ Thái Thanh Hằng 	0972032010	\N	235 hồng thập tự, long khánh, đồng nai	0	2026-02-01 06:24:02.482636+00	user	\N
21	\N	Bích Liên	0964226997	\N	24 lê thánh tôn q1	0	2026-02-01 13:04:01.808492+00	user	\N
22	\N	Kol _kduyeen	0905650280  	\N	20 đường 19c phạm thế hiển p7 q8	0	2026-02-01 13:14:07.040802+00	user	\N
23	\N	Quyên	0901606857	\N	72 lê thánh tôn p bến thành vincom đồng khởi	0	2026-02-01 13:15:16.143126+00	user	\N
24	\N	Phạm Yến	0907673591	\N	B10.09, chung cư The Golden Star, 58B Nguyễn Thị Thập, phường Bình Thuận, quận 7, tp. HCM	0	2026-02-01 13:38:34.858449+00	user	\N
25	\N	Ngọc Phương	0387561470	ngocphuong231102@gmail.com	Hẻm 494, số nhà 494/3	0	2026-02-01 13:46:13.740101+00	user	\N
26	\N	Ig haiien.ho	0388955848	\N	318 Nguyễn Oanh, P17, quận Gò Vấp	0	2026-02-01 14:10:17.666559+00	user	\N
27	\N	Thái Phụng 	0962645716 	\N	385F/39A-B, Đ. Trần Nam Phú, An Khánh, Ninh Kiều, Cần Thơ	0	2026-02-01 15:12:33.339494+00	user	\N
28	\N	Thảo (Huong Xu Le)	0904502318	\N	93, P.Bạch Mai, Q.Hai Bà Trưng, TP.Hà Nội	0	2026-02-01 15:14:00.610974+00	user	\N
29	\N	nhi	12234567	\N	jkdkjgk	0	2026-02-01 15:22:32.186082+00	user	\N
30	\N	Ig Bee	0902616275	\N	162/15 Đường số 42, phường Bình Trưng Đông, Thủ Đức	0	2026-02-02 06:51:22.117704+00	user	\N
31	\N	Ig Ngọc Ngọc	0988224226	\N	132 bến vân đồn quận 4	0	2026-02-02 14:04:05.489841+00	user	\N
32	\N	Ig Huyền Lê	0929333317	\N	333 điện biên phủ, bình thạnh	0	2026-02-02 14:08:39.22389+00	user	\N
33	\N	Ig n.nhii01 ( Nhi )	0941840848	\N	280 nguyễn trường tộ tân hoà biên hoà đồng nai	0	2026-02-02 14:12:44.909718+00	user	\N
34	\N	Ig huỳnh như quỳnh (Như Quỳnh)	0356620045	\N	block b chung cư sunrise riverside, phước kiểng, nhà bè	0	2026-02-02 14:13:48.974587+00	user	\N
35	\N	Ig alna nguyen (alna nguyen)	0937748847	\N	918/9H hương lộ 2 - Phường Bình Trị Đông A - Quận bình tân	0	2026-02-02 14:15:55.763097+00	user	\N
36	\N	Ig uynuyn	0989572278	\N	Tô mì studio đường nguyễn văn linh phường mỹ phước Long Xuyên an giang	0	2026-02-02 14:18:22.339336+00	user	\N
37	\N	Ig bao quyen ( Quyên)	0773872547	\N	k356/h111/3 hoàng diệu,hải châu,đà nẵng ( trước sát nhập )	0	2026-02-02 14:19:08.331017+00	user	\N
38	\N	Ig minh anh (Nguyễn Hoàng Minh Anh)	0395926658	\N	1304, toà N4B khu đô thị Trung Hoà Nhân Chính, Thanh Xuân,Hà Nội	0	2026-02-02 14:20:09.8032+00	user	\N
39	\N	Khánh Linh	0902850016	khnhlin143@gmail.com	6/5 quốc hương	0	2026-02-02 14:59:59.629864+00	user	\N
40	\N	ig Be Han	0933888347	\N	203 cao văn lầu p2 q6 cũ	0	2026-02-02 16:18:36.286129+00	user	\N
41	\N	Ig khánh ngọc 	0328766486	\N	30 lê trung nghĩa p bảy hiền hcm	0	2026-02-02 16:19:31.54394+00	user	\N
42	\N	Ig phuc hanh pham	0855877511	\N	264 nam kì khởi nghĩa, p. Xuân hoà, hcm	0	2026-02-02 17:20:14.03759+00	user	\N
43	\N	Như Ý	0906482677	\N	 86 chu văn an p26 quận bình thạnh	0	2026-02-02 17:58:29.131481+00	user	\N
44	\N	Duy Linh Nguyễn	0931637448	\N	07 Đặng Tất, phường Buôn Hồ, tỉnh ĐakLak	0	2026-02-02 17:59:51.825822+00	user	\N
45	\N	Ig ân nin 	0909215263	\N	1269 phan văn trị p gò vấp 	0	2026-02-03 05:55:11.367659+00	user	\N
46	\N	Ig by_elisette	0397024181	\N	89/13 Nguyễn Thượng Hiền, p5, Bình Thạnh	0	2026-02-03 05:56:15.574452+00	user	\N
47	\N	Thiện Thảo	0898681865	\N	126 đường 38 Bình Trưng Tây - Thủ Đức	0	2026-02-03 05:57:26.880631+00	user	\N
48	\N	Ig bống	0832191587	\N	144 triệu việt vương nguyễn du hai bà trưng hà nội 	0	2026-02-03 06:42:27.68559+00	user	\N
49	00e784a2-eb52-46b0-99c3-123b49a983f4	Pronthip Graitong	+66959635089	maymay123555maymay123555@gmail.com	\N	0	2026-02-03 11:39:44.393562+00	user	\N
50	\N	Ig crtnch 	0325267896	\N	 375 tân thới hiệp 21 , Tổ 3 ,Kp3 ,quận 12 ( nhớ gõ đủ)	0	2026-02-03 16:09:54.763563+00	user	\N
51	\N	Nhi	0909078752	\N	192 nguyễn công trứ phường Bến Thành	0	2026-02-03 16:10:34.285729+00	user	\N
52	\N	Ig thu hà	0398514443	\N	Thôn 7a \nEawy-eahleo-dăk lái	0	2026-02-03 16:11:36.668043+00	user	\N
53	\N	Ig thuý ngọc	0702928310	\N	Ấp 1A , xã Tân Hoà , tp Cần Thơ	0	2026-02-03 16:12:33.782045+00	user	\N
54	\N	Ig nhee nhee	0396994800	\N	Số 38 đường D4, phường chánh nghĩa, thành phố thủ dầu một, bình dương	0	2026-02-03 16:13:37.447516+00	user	\N
55	\N	Ig bow bangkok	0369166.222	\N	163 Trương Thị Hoa, phường Tân Thới Hiệp, Quận 12, thành phố Hồ Chí Minh	0	2026-02-03 16:15:15.193626+00	user	\N
56	\N	Ig bảo loan	0564164989	\N	K486 nguyễn tri phương cẩm nam hội an quảng nam	0	2026-02-03 16:17:00.309066+00	user	\N
57	\N	Ig baconmeocon	0938080124	\N	16 đường số 4, kdc Nam Hùng vương, p an lạc, kp3 quận bình tân, Phường An Lạc, Quận Bình Tân, TP Hồ Chí Minh	0	2026-02-03 16:20:59.006855+00	user	\N
58	\N	Ig ggiantttttt	0918974705	\N	481/23/10 tân kì tân quý, tân phú	0	2026-02-03 16:21:45.51001+00	user	\N
59	\N	Ig em PT mét gữi 	0903522900	\N	48/11 Nguyễn An Ninh, p14 , Q. Bình Thạnh , HCM	0	2026-02-03 16:22:38.154133+00	user	\N
60	\N	ig giang tran 	0907739179	\N	17F2/A42, khu phố 6, phường Trung Dũng, Biên Hoà	0	2026-02-03 16:23:20.345998+00	user	\N
61	\N	Ig Bby 	0769998968	\N	146/2q đường số 30, p6 Gò Vấp	0	2026-02-03 16:24:08.569546+00	user	\N
62	\N	Ig tiểu my 	0988041293	\N	Chung cư Sunshine Diamond River , 422 Đào Trí , Phú Thuận , Q7 	0	2026-02-03 16:24:47.181968+00	user	\N
63	\N	Ig babimilo.11	093360237	\N	436b/17 ba thang hai p12 quan 10	0	2026-02-03 16:25:29.878497+00	user	\N
64	\N	ngọc	0769823114	\N	371 nguyễn oanh, p17 gò vấp	0	2026-02-03 16:53:06.437906+00	user	\N
65	\N	Phạm Thành Khang	0904835375	khangpham.5375@gmail.com	Chung cư Tân Mai, Lê Đức Anh	0	2026-02-03 16:53:41.77257+00	user	\N
66	\N	Ig nguyễn hoàng nhật ái	0777777900	\N	90 Nguyễn Hữu Cảnh , phường 22 , quận Bình Thạnh ,	0	2026-02-03 16:53:52.772227+00	user	\N
67	\N	Phạm ngọc hân 	0384295534	ngochan280811@gmail.com	Số 42d thạnh xuân 37 quận 12( trong bãi vật liệu đức trí fpt)	0	2026-02-04 05:10:09.955119+00	user	\N
68	466cb4fb-784e-4493-98cb-138a11b20565	Phạm ngọc hân	0384295534	ngochan280811@gmail.com	\N	0	2026-02-04 05:11:22.807161+00	user	\N
69	\N	kiều thị kim anh	0839010434	\N	khách sạn hoa sứ, trại bò phúc lộc	0	2026-02-04 07:15:57.339606+00	user	\N
70	\N	Ig nguyễn thị thảo nguyên	0966240425	\N	Ngã tư chánh nhơn cát nhơn phù cát bình định	0	2026-02-04 08:32:34.204708+00	user	\N
71	\N	thanh tuyền	789515460	\N	15NXK	0	2026-02-04 08:36:24.056063+00	user	\N
72	\N	Ig mỹ anh 	0916 520 385	\N	81 Lê Lai , phường Trường Chinh , TP Kon Tum 	0	2026-02-04 09:24:23.134441+00	user	\N
73	\N	Ig kaythy.16	0935539978	\N	270/109/14 phan đình phùng , p1 phú nhuận	0	2026-02-04 12:01:35.999348+00	user	\N
74	\N	Hà Quyên 	0981681406	\N	24 đường b2 Phước hải ( Nhà ngô kỳ nhiên ) 	0	2026-02-04 12:30:33.87382+00	user	\N
75	\N	Hà Quyên	0981671406	\N	28 đường B2 . Phước hải ( nhà ngô kỳ nhiên )	0	2026-02-04 12:53:56.79094+00	user	\N
76	\N	Ig thu lương	0908.603.893	\N	Lương Ngọc Cẩm Thu\nsố nhà 1407, ấp Bình Phú, xã Long Tân , huyện Nhơn Trạch , tỉnh Đồng Nai	0	2026-02-04 13:48:13.780101+00	user	\N
77	\N	Ig Lê Thanh Thảo	0933097084	\N	8/28 nguyễn đình khơi, phường4, tân bình, tphcm	0	2026-02-04 18:18:17.333326+00	user	\N
78	\N	Ig just C 	0379201403	\N	82 Nguyễn Sơn - Ngọc Lâm - Long Biên - Hà Nội 	0	2026-02-05 03:22:25.657044+00	user	\N
79	\N	 Lê Thị Trà My	 03338407494	\N	140 quốc lộ 13, khu phố ninh thịnh, thị trấn Lộc Ninh, Tỉnh Bình Phước	0	2026-02-05 03:23:49.83271+00	user	\N
80	\N	Ig winkzeeee	0933948272	\N	423 Trường Chinh, Phường Đông Hưng Thuận, HCM	0	2026-02-05 03:25:39.004603+00	user	\N
81	\N	Ig trẻ người non stop	0888671434	\N	122/38 Bùi đình tuý,p12, q. Bình thạnh 	0	2026-02-05 03:45:11.238152+00	user	\N
82	\N	Ig thanh tam	0347345259	\N	B48/1 ấp Phước Bình, xã Phước Tỉnh, huyện Long Điền, tỉnh BRVT\nPhuoc Tinh, Long Điền, Tinh Ba Ria - Vung Tau,	0	2026-02-05 04:03:21.539634+00	user	\N
83	\N	Ig phương trinh	0359298912	\N	204/3B Cao Đạt, phường 1, quận 5 	0	2026-02-05 04:44:25.410764+00	user	\N
84	\N	Ig hồng ngân	0779633259	\N	13 xóm vôi p14 q5	0	2026-02-05 06:05:15.100468+00	user	\N
85	\N	Ig tdhtran_	0337552416	\N	1351/9/2 Phan Văn Trị phường 10 Gò Vấp	0	2026-02-05 06:05:50.484543+00	user	\N
86	\N	Ig thu vo 	0932221092	\N	8 tran nao q2	0	2026-02-05 08:22:05.777169+00	user	\N
87	\N	Ig xuý 	0968562187	\N	610 võ văn kiệt phường cầu ông lãnh ạ\n\n	0	2026-02-05 08:24:55.163503+00	user	\N
88	\N	Ig phương linh	0877979798	\N	Khu phố 10, p tân Biên Biên Hoà Đồng Nai	0	2026-02-05 10:37:02.823695+00	user	\N
89	\N	Ig wuenie.gum	0949941439	\N	55a/3 kp3 phường tân hoà biên hoà đồng nai 	0	2026-02-05 11:26:18.011105+00	user	\N
90	\N	Ig lan phương	0395328548	\N	39 nhất chi mai , tân bình	0	2026-02-05 11:27:47.508558+00	user	\N
91	\N	Ig khanhvandoann	0937059890	\N	52 Thành Thái P.12 Q.10 	0	2026-02-05 11:57:50.130232+00	user	\N
92	\N	Phạm Uyên Thy	0858326679	uyenthi6679@gmail.com	145/1, hẻm 145, quốc lộ 13	0	2026-02-05 12:19:12.456787+00	user	\N
93	\N	Phạm Hoài Hải Yến	0913612642	phamhoaihaiyen@gmail.com	122 Ỷ Lan	0	2026-02-05 12:41:54.965864+00	user	\N
94	\N	Mai Phan	0911172812	Maiphannp26@gmail.com	An residence 14 đường số 1 (lý phục man quẹo vô)	0	2026-02-05 13:51:12.51573+00	user	\N
95	\N	ig  nganxiinhiu ( Ngan Pham)	84869726548	\N	Hẻm 240/13 Lê Duẩn, Xã An Phước, Huyện Long Thành, Đồng Nai	0	2026-02-05 14:15:41.328224+00	user	\N
96	\N	Kiều Trang	0393252767	nguyenthivuong0733@gmail.com	63 Nguyễn Ngọc Kỳ 	0	2026-02-05 16:16:23.539534+00	user	\N
97	\N	Ig joice.nn_	0938223711	\N	173/45/36 Khuông Việt, Phú Trung, Tân Phú	0	2026-02-05 18:49:53.803812+00	user	\N
98	\N	Hồ Thị Kim Tho	0797206844	tho.hokimtho01@gmail.com	31 đường số 37 	0	2026-02-06 03:05:52.058916+00	user	\N
99	\N	🏳️‍🌈	0971464109	\N	Chung cư opal garden	0	2026-02-06 03:53:15.106308+00	user	\N
100	\N	Ig ohvielleicht 	+84 79 6256618	\N	428 Võ Nguyên Giáp, Khuê Mỹ, Ngũ Hành Sơn, Đà Nẵng 550000	0	2026-02-06 04:15:07.334407+00	user	\N
101	\N	Ig meii 	0841444661	\N	332/34 độc lậ phú thọ hoà tân phú\n\n	0	2026-02-06 06:14:57.674992+00	user	\N
102	\N	Ig thư	0935883228 	\N	148 trần nam trung, hoà xuân, cẩm lệ, đà nẵng 	0	2026-02-06 06:40:23.762523+00	user	\N
103	\N	Ig tiên tiên	0985037507	\N	02 Nguyễn Lương Bằng - xã Lộc thanh - tp bảo Lộc - lâm đồng \n	0	2026-02-06 07:42:57.648845+00	user	\N
104	\N	Ig bích ngọc 	0905441264	\N	K52/73 Đinh Tiên Hoàng , Đà Nẵng \n	0	2026-02-06 08:15:07.95867+00	user	\N
105	\N	hồng đào Ig 🍒R🍒	0909089356	\N	147/5 thạch lam tân phú HCM	0	2026-02-06 10:35:30.783038+00	user	\N
106	\N	Ig hyhchaah	0985533618	\N	224A kp5 p1 đường 786 tp Tây Ninh	0	2026-02-06 13:43:05.906744+00	user	\N
107	\N	Ig DWF	0376891811	\N	46-48-50 phạm hồng thái, p. bến thành\n- Tuyên 	0	2026-02-06 15:16:48.531028+00	user	\N
108	\N	Ig PHUONG UYEN	0948434814	\N	214 ni sư huỳnh liên p10 quận tb	0	2026-02-07 02:46:20.693285+00	user	\N
109	\N	Ig linh trần 	0886339378	\N	hem 420/18a khu 3 phú lợi đại lộ binh duong\n	0	2026-02-07 02:48:42.551097+00	user	\N
110	\N	Ig ee.sora 	0868774517	\N	\n75 thôn minh tiến,xã hàm minh, huyện Hàm thuận nam tỉnh bình thuận(cũ)\n	0	2026-02-07 02:49:58.656613+00	user	\N
111	\N	Ig y0310_	0899290899	\N	Số nhà 03 (cạnh mẫu giáo xóm đồng), Phường Phong Hải, Thị Xã Quảng Yên, Quảng Ninh\n	0	2026-02-07 04:09:31.272048+00	user	\N
112	\N	Ig lê thảo linh	0915181172	\N	Vinhome grand paảk s7.5\n\n	0	2026-02-07 04:34:10.376977+00	user	\N
113	\N	Ig bchamm_	0357022231	\N	18/17/18 Hương Lộ Ngọc Hiệp, Nha Trang, Khánh Hoà\n	0	2026-02-07 11:15:49.936445+00	user	\N
114	\N	Ig 17dasick	0783396444	\N	348A Trường Chinh, phường 13, Tân Bình	0	2026-02-07 11:16:20.346516+00	user	\N
115	\N	Ig phương trinh 	0359298912 	\N	204/3B Cao Đạt, phường 1, quận 5 	0	2026-02-07 11:16:57.091175+00	user	\N
116	\N	Ig kimm	0706741315	\N	33 nguyễn hữu thọ tân hưng quận 7\nSunrise city view toà B	0	2026-02-07 11:17:43.119849+00	user	\N
117	\N	Ig ivy.trieule	 0349270422	\N	1534 hùng vương, cam phú, cam ranh khánh hoà\n	0	2026-02-07 11:19:28.002261+00	user	\N
118	\N	Ig nguyễn ngọc thiên kiều 	0988949801	\N	96/3 đường s19, p8, gvap	0	2026-02-07 11:20:50.68704+00	user	\N
119	\N	Ig kim chi 	0914019900	\N	19 bàu cát4-ph tân bình -tân binh	0	2026-02-07 11:23:22.337969+00	user	\N
120	\N	The name is Ngan 	0906616319 .	\N	 365/19A đường hậu Giang , phường Bình Phú. Quận 6 tphcm . \n 	0	2026-02-07 11:24:50.542221+00	user	\N
121	\N	Ig mai quỳnh 	0394975445	\N	72-74 Nguyễn Thị Minh Khai, phường 6 quận 3\nCentec Tower	0	2026-02-07 11:25:31.098331+00	user	\N
122	\N	Ig như ngọc nguyễn thị 	0358590047	\N	764 Thọ Hoà, Xuân Thọ, Xuân Lộc, Đồng Nai	0	2026-02-07 11:36:34.999496+00	user	\N
123	\N	Thanh Ngân	0386946804	bcee.stal63@gmail.com	55/4b trương đình hội p16 q8	0	2026-02-07 14:18:33.433835+00	user	\N
124	\N	Minh Ngọc	0329588917	daongoc873@gmail.com	Số nhà 102 khu chăn nuôi Hàm Long	0	2026-02-07 15:46:03.678825+00	user	\N
125	\N	Bảo Thy	0976281379 	thyphan1221@gmail.com	Block A1, Opal riverside, đường số 10	0	2026-02-07 16:03:02.421108+00	user	\N
126	\N	Ig vũ vy 	0904471747 	\N	35 nguyễn đức cảnh, p.thắng lợi, tp.buôn ma thuột	0	2026-02-07 18:27:50.208457+00	user	\N
127	\N	Ig ngocbaongan.	0838812881	\N	37/6/29 hồ văn nhánh kp8 p5 mỹ tho tiền giang	0	2026-02-07 18:28:39.45892+00	user	\N
128	\N	Ig hmgtwm	0827840027	\N	Ba Đình - Nam Ban Lâm Hà - Lâm Đồng	0	2026-02-07 18:29:31.233358+00	user	\N
129	\N	Ig bùi yến vy	0909923466	\N	BlockA, cc Kingdom101, p diên hồng, q10	0	2026-02-07 18:30:36.853459+00	user	\N
130	\N	Ig như quỳnh	0901567568	\N	K408/H29/18 Hoàng Diệu, Phường Hoà Cường, Tp Đà Nẵng	0	2026-02-07 18:31:14.899489+00	user	\N
131	\N	Ig DN 	0931231295	\N	số nhà 24d3 ngõ 689 lạc long quân, phường tây hồ, hà nội	0	2026-02-07 18:32:04.714522+00	user	\N
132	\N	ig kim mỹ hà 	0901115018	\N	104/11 huỳnh mẫn đạt p2 q5 tphcm ( sát nhập 104/11 huỳnh mẫn đạt p chợ quán tphcm )	0	2026-02-07 18:32:47.791071+00	user	\N
133	\N	Kol tuyền 	0966946346 	\N	778 xô viết nghệ tĩnh phường thạnh mỹ tây quận bình thạnh \n\n	0	2026-02-07 18:33:44.62969+00	user	\N
134	\N	Ig lê t. Thu hường	0784649439	\N	Ấp 5 miễu bà 8 long thọ nhơn trạch đồng nai	0	2026-02-08 04:19:14.145729+00	user	\N
135	\N	Ig tamikanguyen	0901104935	\N	501/19 Phạm văn Chiêu phường 13.Quận Gò vấp\n	0	2026-02-08 04:21:12.405837+00	user	\N
136	\N	Ig quỳnh anh	0336823079	\N	Số 39 , ql 13, Lộc Thái , Lộc Ninh, Bình Phước	0	2026-02-08 05:25:50.391069+00	user	\N
137	\N	Ig meehgoxcutie_	0979768986	\N	CityHouse - CD Apartment\n339/24B Đ. Lê Văn Sỹ, Phường 12, Quận 3, Hồ Chí Minh 700000, Vietnam 	0	2026-02-08 05:26:46.534322+00	user	\N
138	\N	Vũ Khánh Huyền 	0382829311	\N	Ngõ 57 K40 khu 2 phường quảng yên	0	2026-02-08 07:24:45.161467+00	user	\N
139	\N	Ig vie	0779078617	\N	152 Lê Quang Định, Bình Thạnh\n	0	2026-02-08 09:06:20.892106+00	user	\N
140	\N	Ig nnphiephe 	0335856599 	\N	Chung cư CT9 Vĩnh Điềm Trung , Phường Vĩnh Hiệp tp Nha Trang \n	0	2026-02-08 09:06:54.603304+00	user	\N
141	\N	Ig jeff	0938780757	\N	Linh Cung \nEco Green Block H, 39B Nguyễn Văn Linh, Tân Thuận Tây, Quận 7\n	0	2026-02-08 09:07:33.656658+00	user	\N
142	\N	Thảo nguyên	0935891747	\N	Saigon south residence 113a Nguyễn Hữu Thọ, Phước Kiển, Nhà Bè\n	0	2026-02-08 09:08:33.691083+00	user	\N
143	\N	Ig NGỌC MAI	0835772142	\N	ố 33, lô D, TTTM BÌNH MINH - K1, P cái vồn, TX Bình minh, Vĩnh Long 	0	2026-02-08 09:21:20.735276+00	user	\N
144	\N	Ngọc trâm	0342617409	\N	94/3 ấp 3	0	2026-02-08 14:41:10.425234+00	user	\N
145	\N	Ig bow bangkok	0369166.222 	\N	163 Trương Thị Hoa, phường Tân Thới Hiệp, Quận 12, thành phố Hồ Chí Minh\n ( Người Nhận BN2705)	0	2026-02-08 15:08:26.202152+00	user	\N
146	\N	 Ig an thuỳ 	0946698781	\N	Ngân Hàng Vib Dĩ An, \nSố 2 Đường M, Khu Trung Tâm Hành Chính, Phường Dĩ An, Thành Phố Dĩ An, Bình Dương\n\nTrần Thuỳ An	0	2026-02-08 15:09:04.0312+00	user	\N
147	\N	Ig quynh anh maria	0369514710	\N	Xóm Miếu, cụm 7, Vĩnh ninh , đại Thanh, Hà Nội\nTên: Nguyễn Thị Thu Trang	0	2026-02-08 15:10:08.996931+00	user	\N
148	\N	Ig thu thuỷ 	0334947873	\N	\nDc sn 5c hẻm 43/99/7 trung kính, trung hoà, cầu giấy Hà Nội	0	2026-02-08 15:10:47.954106+00	user	\N
149	\N	Ig immatcha_cha	0343178558	\N	451 Xuân Đỉnh , Hà Nội	0	2026-02-08 15:11:34.788009+00	user	\N
150	\N	Ig KHIMY 	0908444086	\N	Lô D cc ecogreen ,nguyễn văn linh ,q7\n	0	2026-02-08 15:39:31.443967+00	user	\N
151	\N	Linh Trang	0823236968	abc@gmail.com	81 Thạch Thị Thanh	0	2026-02-08 17:43:52.539768+00	user	\N
152	\N	Nguyễn Ngọc Minh Thư	0918441864	minhthu010720@gmail.com	21B.Nguyễn Thị Thập,Quận 7,phường Tân Phú,TPHCM	0	2026-02-08 19:43:46.394593+00	user	\N
153	\N	Test 	0979116700	\N	15 NXK	0	2026-02-09 02:30:46.554327+00	user	\N
154	\N	Ig jessi.cameronj	0702624572	\N	102/2 võ trứ nha trang , khánh hoà 	0	2026-02-09 03:36:25.041823+00	user	\N
155	\N	Honeyfai_	0818999538   	\N	M Village Ho Bieu Chanh 7 Hồ Biểu Chánh, Phường 12, Phú Nhuận, Thành phố Hồ Chí Minh, Vietnam  	0	2026-02-09 03:37:35.700945+00	user	\N
156	\N	Ig phạm ngọc tuyền	0358137039	\N	Nhà 8a hẻm 35 đường cmt8 kp1 phường 3 tây ninh	0	2026-02-09 03:38:10.439596+00	user	\N
157	\N	ig Vi Nguyễn	0969999346 	\N	Chung Cư CT6 Vĩnh Điềm Trung Nha Trang, Tòa Nhà CT6, Đường B3,\nPhường Tây Nha Trang, Khánh Hòa	0	2026-02-09 05:05:00.61727+00	user	\N
158	\N	Ig zoe 	0932086042	\N	\n908/3 đoàn văn bơ p18 q4	0	2026-02-09 06:16:29.133425+00	user	\N
159	\N	Ig đặng quỳnh	0706772763	\N	atino 73 nguyễn việt hồng , phường an phú , ninh kiều cần thơ\n	0	2026-02-09 06:30:32.125067+00	user	\N
160	\N	Ig tran tran 	0767629111	\N	 105/2 Phạm Phú Thứ P Bình Tiên (p3 q6)	0	2026-02-09 07:43:42.378592+00	user	\N
161	\N	Mi Mi	0796287600	\N	13 bình thới p11 quận 11 	0	2026-02-09 09:57:38.753921+00	user	\N
162	\N	Ig nguyen bich ngoc	0392951733	\N	15 đường 37, phường hiệp bình phước , khu đô thị vạn phúc ,\n\n	0	2026-02-09 09:58:19.183643+00	user	\N
163	\N	Ig nguyen bich ngoc	0392951733	\N	15 đường 37, phường hiệp bình phước , khu đô thị vạn phúc ,\n\n	0	2026-02-09 09:58:19.347774+00	user	\N
164	\N	ig Cam cam	070 3624481	\N	hocmon	0	2026-02-09 13:55:56.878475+00	user	\N
165	\N	Kol hannal	0366986065	\N	Masteri thảo điền, t3, q2	0	2026-02-09 13:56:47.115165+00	user	\N
166	\N	Ig võ thảo ngân 	0795407876	\N	khu dân cư ấp phú thuận xã phú thịnh huyện tam bình tỉnh vĩnh long\n	0	2026-02-09 13:57:25.030726+00	user	\N
167	\N	Đào Lý Thảo Vy	0705992224	vydaolythao@gmail.com	52/12 đường số 17	0	2026-02-09 14:20:15.987618+00	user	\N
168	\N	Ig hathanhthuylinh	0902904947	\N	\n47/17a bùi công trừng nhị bình hóc môn	0	2026-02-09 15:27:42.934372+00	user	\N
169	\N	Ig themtradau	0934142781	\N	15NXK khách ghé lấy	0	2026-02-09 16:34:20.581215+00	user	\N
170	\N	Ig ulsuove_	0364789984 	\N	212/3b phạm văn chiêu phường 9 gò vấp	0	2026-02-09 16:50:53.517004+00	user	\N
171	\N	Maika 	0906777794	\N	50 đường số 3. P an lạc A. \nQuận bình tân	0	2026-02-10 03:15:50.135641+00	user	\N
172	\N	Ig mita.lam	0838081828	\N	7A Hải Thượng Lãn Ông - phường Rạch Sỏi - TP Rạch Giá - Kiên Giang\nTrang 0838081828 ạ	0	2026-02-10 03:49:16.425273+00	user	\N
173	\N	Ig lâm thị mỹ hảo	0384753595	\N	29 trần quang diệu, phường 13, quận 3	0	2026-02-10 06:27:06.280194+00	user	\N
174	\N	Ig hoàng lan 	0931539768	\N	30 Phạm Văn Đồng Khu Cầu Xéo xã long thành đồng nai \n	0	2026-02-10 06:28:58.56069+00	user	\N
175	\N	Ig thanh truc huynh 	086 5767578 	\N	T08-05 The Manhattan, Vinhome Grand Park, Phường Long Bình, TP Thủ Đức	0	2026-02-10 07:51:32.337532+00	user	\N
176	\N	ig _princesshappiii	0786968512	\N	112/114/9 nguyễn thị minh khai quận ninh kiều thành phố cần thơ	0	2026-02-10 08:44:27.201096+00	user	\N
177	\N	Ngọc Nữ	0933850356	glamwithnu@gmail.com	27/29 Điện Biên Phủ	0	2026-02-10 10:27:39.452526+00	user	\N
178	\N	Ig hien le	0969813416	\N	26 Lý Tự Trọng, P. Bến Nghé, TP HCM\n	0	2026-02-10 11:15:36.985851+00	user	\N
179	\N	Ig kiwi1989	0366286418	\N	63-65A11, Khu phố 11, Nguyễn Văn Tiên, Phường Tân Phong, Tp. Biên Hoà, Tỉnh Đồng Nai.	0	2026-02-10 15:03:34.55722+00	user	\N
180	\N	Ig mochisyx	0899903807	\N	204b6/5/2 Nguyễn Văn Hưởng, Thảo Điền	0	2026-02-10 15:05:19.883176+00	user	\N
181	\N	 Quỳnh Như	0978596565 	\N	283 bến vân đồn q4 	0	2026-02-10 17:47:30.895777+00	user	\N
182	\N	Ig kittmy.t	890515460	\N	50/29 nguyễn đình chiểu p4 quận phú nhuận 	0	2026-02-11 04:27:49.767879+00	user	\N
183	\N	ig honeyfai_	0818999538	\N	M village 7 Hồ Biểu Chánh p12 Phú Nhuận	0	2026-02-11 05:37:37.1407+00	user	\N
184	\N	Ig Hiền Phạm	0977415509	\N	431 lê văn sỹ quận 3	0	2026-02-11 07:18:45.96466+00	user	\N
185	\N	ig vivannnguyen90	0933182823	\N	1065 lò góm p7 quận 6	0	2026-02-11 08:49:42.823379+00	user	\N
186	\N	ig hanna_owo2u	0789989206	\N	42/2L ap tien lan ba diem hocmon 	0	2026-02-11 08:52:28.042022+00	user	\N
187	\N	ig nguyễn khánh hà	0867470512	\N	63 đường số 79 tân quy quận 7	0	2026-02-11 12:41:36.970127+00	user	\N
188	\N	ig mai le	0901360708	\N	chung cư rivegate quận 4	0	2026-02-11 12:43:18.682308+00	user	\N
189	\N	ig Kim	0389012992	\N	2 tôn đức thắng vinhome golden river aqua 3, bến nghé	0	2026-02-11 12:49:11.585278+00	user	\N
190	\N	ig Na Phea	093282796	\N	Phnom penh city,  Cambodia	0	2026-02-11 13:28:15.320491+00	user	\N
191	\N	ig nhu nguyen	0865673495	\N	44 đường sô 7 khu đô thị an phú an khánh phường an phú tp thủ đức	0	2026-02-11 15:54:23.906192+00	user	\N
192	\N	ig dương vi	0939688638	\N	75 đường số 26a quận 6	0	2026-02-11 17:08:47.754931+00	user	\N
193	\N	ig hằng	0987030742	\N	Tiệm My nail, só 3 tân thới nhất 1 phường đông hưng thuận bà điểm hocmon	0	2026-02-11 17:20:30.327311+00	user	\N
194	\N	Ig thu diễm	0934511930	\N	17-bt7 khu đô thị Văn Phú, Phú La, Hà Đông, HN	0	2026-02-12 17:44:51.599033+00	user	\N
195	\N	Minh nguyệt	0987569836	meomun2001@gmail.com	Số 79 ngõ 266 phố đội cấn	0	2026-02-21 00:32:06.59954+00	user	\N
196	\N	Thuý An 	0868107862	nguyenthithuyan923@gmail.con	13/20b tạ quang bửu 	0	2026-02-21 08:02:12.731411+00	user	\N
197	\N	Trần Triệu Mai Phương	0964618034	trantrieu1302@gmail.com	20, ngách 8, ngõ 1 Đình Thôn	0	2026-02-21 17:38:49.039181+00	user	\N
198	\N	Vy Vo	0399323601	xmberv@gmail.com	315 Nguyễn Sơn	0	2026-02-22 19:21:30.228803+00	user	\N
199	\N	Trần M Phương	0786797999	mingphuong.29@gmail.com	226 Lê Quang Định	0	2026-02-24 06:15:48.593657+00	user	\N
200	\N	Ig katp9re	0838925459	\N	 Địa chỉ: 128/39, Đường Phạm Văn Hai, Phường 3, Quận Tân Bình, TP. Hồ Chí Minh	0	2026-02-24 14:14:15.89209+00	user	\N
201	\N	Ig trish pham	0765551104 	\N	399 Hai Ba Trưng quận 3	0	2026-02-24 14:16:29.673378+00	user	\N
202	\N	Ig donfetch 	+84 779 805443	\N	\nAddress : Indochine Ben Than Hotel and Apartments , 30 Lưu Văn Lang, Phường Bến Thành, Quận 1, Thành phố Hồ Chí Minh 700000, Vietnam\n\nNo.hp: +84 779 805443\n(can zalo)\n\nNotes: Xin vui lòng gửi ở lễ tân khách sạn	0	2026-02-24 14:22:41.078584+00	user	\N
203	\N	Ig bí nhe 	0944294068	\N	202/51 phạm văn hai p5 qtan bình \n	0	2026-02-24 14:24:37.835277+00	user	\N
204	\N	Ig cry baby	0773105709	\N	Địa chỉ: Chung cư Diamond Riverside, Block D, phòng 26.01, số 1646A, Võ Văn Kiệt, phường Phú Định, quận 8	0	2026-02-25 04:49:54.730869+00	user	\N
205	\N	Ig cẩm nhung 	0775815411	\N	 45 đào duy anh, phường quang trung, tp quy nhơn, tỉnh bình định	0	2026-02-25 04:50:33.898513+00	user	\N
206	\N	Ig vyctorilane	0962409277 	\N	91 Hàm Nghi, p.Ngô Mây, tp Quy Nhơn, Bình Định\n	0	2026-02-25 04:51:20.721515+00	user	\N
207	\N	Ig thuy hang 	0975820878	\N	3/70/Đồng Hòa/Kiến An/TP Hải Phòng	0	2026-02-25 04:51:55.960799+00	user	\N
208	\N	Ig nunu	0899326041	\N	 453/70/52 đường Lê Văn Khương, Khu phố 5, phường Hiệp Thành, Quận 12, Thành phố Hồ Chí Minh, Việt Nam	0	2026-02-25 04:52:37.532751+00	user	\N
209	\N	Ig joiee_devivre	0818887574	\N	Số 16 Ngõ 674 đg Nguyễn Văn Cừ Long biên Hà Nội (sau sát nhập: đg Ng Văn Cừ, phường Bồ Đề Hà Nội)	0	2026-02-25 04:53:24.800606+00	user	\N
210	\N	Ig chau minh 	0936083509 	\N	c1 tôn thất thiệp, điện biên, ba đình, hà nội ak\nMinh Châu	0	2026-02-25 04:54:08.298599+00	user	\N
211	\N	Ig uyên	0981852828	\N	47 đuong 47, p. thao dien q2	0	2026-02-25 04:55:03.822109+00	user	\N
212	\N	Ig nguyen tran khanh dat	0963877579	\N	89/1/84 đường số 8, p Tăng Nhơn Phú B, quận 9\nKhánh Đạt 	0	2026-02-25 04:55:46.228449+00	user	\N
213	\N	Ig linh tran	0868424123	\N	23 Nguyễn An Ninh, Đống Đa, Phường Đống Đa, Thành Phố Vĩnh Yên, Vĩnh Phúc	0	2026-02-25 04:56:36.803443+00	user	\N
214	\N	Ig nguoilanhungquen	0918441864 	\N	21B.Nguyễn Thị Thập,Quận 7,TPHCM (phòng 307)\n	0	2026-02-25 04:57:19.519499+00	user	\N
215	\N	Ig kate lin 	+84938203196	\N	saigon royal 09 nguyễn trường tộ p13 quận 4	0	2026-02-25 04:58:54.160024+00	user	\N
216	\N	Ig thoai.tienn	0937800100	\N	333/23 Lê Văn Sỹ, P1, Tân bình	0	2026-02-25 04:59:41.308294+00	user	\N
217	\N	Ig Doan thu trang	0586338476 	\N	335 Chu Văn An phường 12 Bình Thạnh TPHCM	0	2026-02-25 05:00:27.933211+00	user	\N
218	\N	Ig ngốk	0329123422	\N	730/15/8 lạc long qân p9 tbinh tphcm	0	2026-02-25 05:01:14.984421+00	user	\N
219	\N	ig mimi	0937896863	\N	89/28 Nghĩa Hưng, Phường 6, Tân Bình, Tp.HCM	0	2026-02-25 05:05:50.218216+00	user	\N
220	\N	Ig minhtamtr	0989666805	\N	37C1 ngõ 20 Hồ Tùng Mậu, Cầu Giấy , HN  	0	2026-02-25 05:06:48.098926+00	user	\N
221	\N	Ig gnaschee_05 	0964951368	\N	131/24 tô hiến thành p13 quận 10	0	2026-02-25 05:07:35.888111+00	user	\N
222	\N	Ig dâu 	0866720360	\N	Đối Diện Quán Karaoke Thu Trang 1\nXã Trưng Trắc, Huyện Văn Lâm, Hưng Yên	0	2026-02-25 05:09:37.953839+00	user	\N
223	\N	Ig kim my	0564077912	\N	754 phan văn hớn xã xuân thới thượng, hóc môn tphcm ( VUS phan văn hớn )	0	2026-02-25 05:10:25.432259+00	user	\N
224	\N	Ig bee zzz	0898395188	\N	34 Trần đình xu Quan 1	0	2026-02-25 05:11:36.102609+00	user	\N
225	\N	Ig alena mishkova	0867 743 532	\N	124 Lý Thái Tổ, Đường Đệ, Nha Trang, Khánh Hòa	0	2026-02-25 05:13:11.747156+00	user	\N
226	\N	Mr. Kuo Đài Loan(Gửi phòng bảo vệ)	0937670759	qazxcv74123@gmailc.com	Đường 7C, KCN Nhơn Trạch 2, Nhơn Trạch, Đồng Nai	0	2026-02-25 10:23:36.580813+00	user	\N
227	\N	Ig phi yến 	0932087209	\N	119-121 lê lợi Q1	0	2026-02-25 10:48:08.948805+00	user	\N
228	\N	Ig hà mỹ	0379207027	\N	Thôn 5, xã quãng tân, huyện Tuy Đức, tỉnh Đăk Nông	0	2026-02-25 10:48:45.888472+00	user	\N
229	\N	Ig cún	0972221913	\N	80/15 Dương Quảng Hàm, phường 5, Gò Vấp, Tphcm	0	2026-02-25 10:49:31.73428+00	user	\N
230	\N	Ig mai le	0974274411	\N	mai le\n86 dường số 17 ấp tân tiến xã tân thông hội huyện củ chi\n	0	2026-02-25 11:03:52.926918+00	user	\N
231	\N	Ig thu phuong pham	0888068969	\N	Số nhà 24 ngõ 38 đường Tô Hiệu Cẩm Trung Cẩm Phả Quảng Ninh	0	2026-02-26 03:32:23.583409+00	user	\N
232	\N	Bé thảo ig	0981651629	\N	Phường 10, gò vấp (địa chỉ cũ)\nPhường gò vấp (địa chỉ mới) 	0	2026-02-26 03:33:05.241831+00	user	\N
233	\N	Ig t.mit.ti	0344846390	\N	49 tân thới nhất 1b p. Đông hưng thuận	0	2026-02-26 03:34:25.020326+00	user	\N
234	\N	Thân Thị Ánh 	0393350981	anhthithan383@gmail.com	Nhà số 41	0	2026-02-26 05:06:06.838613+00	user	\N
235	\N	Ig uhuyenday	0379110562	\N	Park 4, 208 Đ. Nguyễn Hữu Cảnh, Vinhomes Tân Cảng, Bình Thạnh, Hồ Chí Minh\n\n	0	2026-02-26 05:25:30.710975+00	user	\N
236	\N	Ig michelle 	0942300185	\N	30/14 Lê Anh Xuân, p. Thới Bình, q. Ninh Kiều, TP. Cần Thơ\n(KOL TẶNG ĐỒ) 	0	2026-02-26 05:26:25.846447+00	user	\N
237	\N	Ig vo hieu thao	0387054842	\N	(Phòng trọ Út Minh) 563/63/32/2A Lê Văn Khương, khu phố 73, phường Tân Thới Hiệp, Tp.Hồ Chí Minh	0	2026-02-26 05:27:11.241147+00	user	\N
238	\N	zalo ngô thị an	092.379.3678	\N	Mặt sau số 168 Trần Thủ Độ, Pháp Vân, Hoàng Liệt, Hoàng Mai, Hà Nội\n(ค้นหา 🔍 sân bóng Đại An)\n☎️ 092.379.3678	0	2026-02-26 05:30:31.55264+00	user	\N
239	\N	Ig rosé rosalie 	0888007659 / 0355180235	\N	Name : Rose Rosalie ( MS0148 )\nContact Numbers:\n0888007659 / 0355180235\nAdd: 131c, phố Thanh Am, phường Thượng Thanh, quận Long Biên, Hà Nội.\nNhớ ghi mã lên kiện hàng :\nMS0148	0	2026-02-26 06:35:07.598479+00	user	\N
240	\N	Nguyễn Hiếu	0927006907	hieuhappy2201@gmail.com	Đường 19/5 chung cư ct2 vĩnh điềm trung	0	2026-02-26 10:45:56.6648+00	user	\N
241	\N	Ig ngoc phuc	0703929339	\N	Chung cư Sky89- đường lê thị chợ- phường phú thuận- quận 7	0	2026-02-26 14:38:46.49958+00	user	\N
242	\N	Ig bống 	0965641518	\N	8bt13 foresa 1 khu đô thị xuân phương nam từ liêm Hà Nội	0	2026-02-26 14:39:30.64205+00	user	\N
243	\N	Ig mifam.store	0839867277	\N	268 đường 3/2 quận 10	0	2026-02-26 14:41:54.199226+00	user	\N
244	\N	Ig hí	0989190214	\N	22A2 Khu Dân Cư Phú Nhuận Phước Long B Quận 9	0	2026-02-26 14:43:55.71235+00	user	\N
\.


--
-- TOC entry 4072 (class 0 OID 17721)
-- Dependencies: 419
-- Data for Name: expense_categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.expense_categories (id, name, description) FROM stdin;
1	Hàng lỗi	\N
2	giấy carton đóng gói	\N
3	tag thank card + tag gắn áo	\N
4	Ads instagram	\N
\.


--
-- TOC entry 4074 (class 0 OID 17729)
-- Dependencies: 421
-- Data for Name: expenses; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.expenses (id, store_id, category_id, amount, expense_date, note, created_at) FROM stdin;
1	1	1	240000	2026-02-02	Váy dài trắng	2026-02-02 17:03:04.46753+00
2	1	1	126000	2026-02-03	Hộp giấy catton 50 cái	2026-02-03 06:49:40.206139+00
3	1	1	378000	2026-02-03	giấy in 2 cuộn 138.000 - bịch niêm phong 301.000	2026-02-03 07:02:09.106432+00
4	1	1	80000	2026-02-04	váy dài trắng lỗi 1	2026-02-04 09:33:35.580601+00
5	1	2	413000	2026-02-04	150 cái hộp giấy	2026-02-04 09:34:14.810887+00
6	1	3	4400000	2026-02-09	thanks card 1000c 1tr5 - tag gắn áo 2000c 2tr9	2026-02-09 10:43:46.507994+00
7	1	4	1380107	2026-02-09	quảng cáo từ ngày 1/2-9/2	2026-02-09 10:45:05.482578+00
8	1	4	931000	2026-02-16	từ ngày 9/2 - 16/2	2026-02-16 05:44:52.997843+00
9	1	2	297000	2026-02-25	100 cái hộp giấy	2026-02-25 11:27:30.923084+00
\.


--
-- TOC entry 4059 (class 0 OID 17602)
-- Dependencies: 406
-- Data for Name: inventory_batches; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.inventory_batches (id, store_id, variant_id, purchase_item_id, original_quantity, quantity_remaining, cost_price, created_at, batch_name, supplier_id, is_adjustment, notes) FROM stdin;
16	1	98	16	10	10	100000	2026-01-27 10:08:20.964716+00	\N	\N	f	\N
21	1	91	21	17	17	150000	2026-01-27 10:10:14.78215+00	\N	\N	f	\N
39	1	51	39	6	6	100000	2026-01-27 10:16:40.435187+00	\N	\N	f	\N
34	1	77	34	1	0	100000	2026-01-27 10:15:07.074612+00	\N	\N	f	\N
58	1	101	\N	-1	-1	100000	2026-01-28 12:24:06.368821+00	\N	\N	t	Cập nhật trực tiếp
25	1	81	25	17	0	100000	2026-01-27 10:11:46.289523+00	\N	\N	f	\N
77	1	94	\N	1	0	100000	2026-01-28 16:34:09.608799+00	\N	\N	t	Điều chỉnh nhanh tại Admin
8	1	97	8	9	0	100000	2026-01-27 10:06:55.273689+00	\N	\N	f	\N
56	1	101	\N	-1	-1	100000	2026-01-28 12:23:54.854373+00	\N	\N	t	Điều chỉnh nhanh tại Admin
57	1	101	\N	-1	-1	100000	2026-01-28 12:23:54.887698+00	\N	\N	t	Điều chỉnh nhanh tại Admin
9	1	97	9	9	0	100000	2026-01-27 10:06:56.088172+00	\N	\N	f	\N
78	1	93	\N	6	7	100000	2026-01-31 16:35:28.022421+00	\N	\N	t	Điều chỉnh nhanh tại Admin
49	1	70	49	5	1	100000	2026-01-27 10:20:51.315734+00	\N	\N	f	\N
66	1	78	\N	-1	-1	100000	2026-01-28 15:43:46.781045+00	\N	\N	t	Điều chỉnh nhanh tại Admin
67	1	78	\N	1	1	100000	2026-01-28 15:44:09.052341+00	\N	\N	t	Điều chỉnh nhanh tại Admin
63	1	35	\N	-10	-10	100000	2026-01-28 15:06:04.077674+00	\N	\N	t	Điều chỉnh nhanh tại Admin
40	1	52	40	6	5	100000	2026-01-27 10:16:54.447379+00	\N	\N	f	\N
65	1	78	\N	1	0	100000	2026-01-28 15:43:26.149321+00	\N	\N	t	Điều chỉnh nhanh tại Admin
74	1	35	\N	1	1	100000	2026-01-28 16:27:54.272133+00	\N	\N	t	Điều chỉnh nhanh tại Admin
5	1	101	5	20	0	100000	2026-01-27 10:01:29.522212+00	\N	\N	f	\N
75	1	93	\N	1	1	100000	2026-01-28 16:29:17.826971+00	\N	\N	t	Điều chỉnh nhanh tại Admin
10	1	92	10	10	0	100000	2026-01-27 10:07:17.134568+00	\N	\N	f	\N
15	1	98	15	10	4	100000	2026-01-27 10:08:18.465898+00	\N	\N	f	\N
33	1	76	33	14	4	100000	2026-01-27 10:14:51.579802+00	\N	\N	f	\N
70	1	77	\N	3	0	100000	2026-01-28 16:01:33.893814+00	\N	\N	t	Điều chỉnh nhanh tại Admin
64	1	50	\N	10	9	100000	2026-01-28 15:41:43.744138+00	\N	\N	t	Điều chỉnh nhanh tại Admin
61	1	101	\N	-2	8	100000	2026-01-28 12:54:59.002217+00	\N	\N	t	Cập nhật trực tiếp
18	1	88	18	15	6	150000	2026-01-27 10:09:29.712624+00	\N	\N	f	\N
60	1	92	\N	1	3	100000	2026-01-28 12:38:23.864251+00	\N	\N	t	Cập nhật trực tiếp
72	1	102	\N	2	0	150000	2026-01-28 16:25:18.145996+00	\N	\N	t	Điều chỉnh nhanh tại Admin
20	1	90	20	22	15	150000	2026-01-27 10:10:00.550071+00	\N	\N	f	\N
50	1	71	50	19	11	100000	2026-01-27 10:21:14.166264+00	\N	\N	f	\N
28	1	83	28	14	0	100000	2026-01-27 10:12:33.646+00	\N	\N	f	\N
37	1	48	37	1	0	100000	2026-01-27 10:16:06.461412+00	\N	\N	f	\N
47	1	28	47	4	0	100000	2026-01-27 10:20:24.283608+00	\N	\N	f	\N
19	1	89	19	15	7	150000	2026-01-27 10:09:47.053578+00	\N	\N	f	\N
29	1	84	29	22	10	100000	2026-01-27 10:12:45.700504+00	\N	\N	f	\N
59	1	101	54	1	0	100000	2026-01-28 12:38:14.70695+00	\N	\N	f	\N
53	1	74	53	9	0	100000	2026-01-27 10:23:03.856962+00	\N	\N	f	\N
3	1	102	3	6	0	150000	2026-01-27 10:01:01.964848+00	\N	\N	f	\N
4	1	101	4	20	0	100000	2026-01-27 10:01:27.589277+00	\N	\N	f	\N
13	1	94	13	10	0	100000	2026-01-27 10:07:48.046742+00	\N	\N	f	\N
80	1	95	\N	11	11	100000	2026-01-31 16:36:37.067685+00	\N	\N	t	Điều chỉnh nhanh tại Admin
30	1	85	30	19	5	100000	2026-01-27 10:12:58.541798+00	\N	\N	f	\N
69	1	23	56	30	0	100000	2026-01-28 15:49:44.066223+00	\N	\N	f	\N
43	1	112	43	6	1	160000	2026-01-27 10:18:56.123022+00	\N	\N	f	\N
26	1	82	26	19	0	100000	2026-01-27 10:12:18.200379+00	\N	\N	f	\N
27	1	82	27	19	16	100000	2026-01-27 10:12:19.893779+00	\N	\N	f	\N
22	1	87	22	10	0	120000	2026-01-27 10:10:42.054529+00	\N	\N	f	\N
12	1	93	12	10	2	100000	2026-01-27 10:07:34.62482+00	\N	\N	f	\N
2	1	35	2	10	8	100000	2026-01-26 16:20:55.194128+00	\N	\N	f	\N
41	1	46	41	11	0	60000	2026-01-27 10:17:21.810722+00	\N	\N	f	\N
45	1	33	45	11	0	100000	2026-01-27 10:19:56.877953+00	\N	\N	f	\N
14	1	95	14	10	0	100000	2026-01-27 10:08:02.881817+00	\N	\N	f	\N
24	1	80	24	14	13	100000	2026-01-27 10:11:27.589533+00	\N	\N	f	\N
52	1	24	52	17	0	100000	2026-01-27 10:21:52.40757+00	\N	\N	f	\N
38	1	49	38	10	4	100000	2026-01-27 10:16:27.031207+00	\N	\N	f	\N
51	1	72	51	2	0	100000	2026-01-27 10:21:26.84691+00	\N	\N	f	\N
44	1	36	44	15	0	100000	2026-01-27 10:19:17.095331+00	\N	\N	f	\N
17	1	99	17	10	9	100000	2026-01-27 10:08:40.495591+00	\N	\N	f	\N
62	1	87	\N	-1	4	120000	2026-01-28 15:01:48.502619+00	\N	\N	t	Điều chỉnh nhanh tại Admin
35	1	78	35	4	0	100000	2026-01-27 10:15:24.43308+00	\N	\N	f	\N
46	1	27	46	6	5	100000	2026-01-27 10:20:13.823501+00	\N	\N	f	\N
42	1	45	42	12	9	60000	2026-01-27 10:17:44.344532+00	\N	\N	f	\N
6	1	100	6	15	3	115000	2026-01-27 10:01:52.209441+00	\N	\N	f	\N
31	1	86	31	22	20	100000	2026-01-27 10:13:12.558445+00	\N	\N	f	\N
76	1	94	\N	2	0	100000	2026-01-28 16:29:30.557113+00	\N	\N	t	Điều chỉnh nhanh tại Admin
79	1	94	\N	5	0	100000	2026-01-31 16:36:04.788618+00	\N	\N	t	Điều chỉnh nhanh tại Admin
48	1	69	48	5	2	100000	2026-01-27 10:20:41.489582+00	\N	\N	f	\N
36	1	47	36	7	4	100000	2026-01-27 10:15:45.866217+00	\N	\N	f	\N
23	1	79	23	16	4	100000	2026-01-27 10:11:14.297816+00	\N	\N	f	\N
81	1	97	\N	12	12	100000	2026-01-31 16:37:40.809508+00	\N	\N	t	Điều chỉnh nhanh tại Admin
82	1	99	\N	6	6	100000	2026-01-31 16:38:23.640761+00	\N	\N	t	Điều chỉnh nhanh tại Admin
83	1	80	\N	3	3	100000	2026-01-31 16:41:27.898633+00	\N	\N	t	Điều chỉnh nhanh tại Admin
84	1	80	\N	1	1	100000	2026-01-31 16:42:28.36622+00	\N	\N	t	Điều chỉnh nhanh tại Admin
85	1	47	\N	1	1	100000	2026-01-31 16:46:59.771474+00	\N	\N	t	Điều chỉnh nhanh tại Admin
86	1	49	\N	20	20	100000	2026-01-31 16:47:52.938654+00	\N	\N	t	Điều chỉnh nhanh tại Admin
87	1	50	\N	8	8	100000	2026-01-31 16:48:28.554369+00	\N	\N	t	Điều chỉnh nhanh tại Admin
89	1	69	\N	2	2	100000	2026-01-31 16:52:29.189704+00	\N	\N	t	Điều chỉnh nhanh tại Admin
73	1	102	\N	1	0	150000	2026-01-28 16:27:07.858101+00	\N	\N	t	Điều chỉnh nhanh tại Admin
111	1	96	\N	1	0	100000	2026-02-05 06:04:35.304656+00	\N	\N	t	Điều chỉnh nhanh tại Admin
94	1	96	\N	1	0	100000	2026-02-03 05:55:26.228818+00	\N	\N	t	Điều chỉnh nhanh tại Admin
112	1	96	69	10	0	100000	2026-02-05 08:10:15.354197+00	\N	\N	f	\N
88	1	46	\N	9	0	60000	2026-01-31 16:50:02.98232+00	\N	\N	t	Điều chỉnh nhanh tại Admin
114	1	96	71	17	0	100000	2026-02-06 12:58:00.297708+00	\N	\N	f	\N
115	1	74	72	16	0	100000	2026-02-06 12:58:53.764705+00	\N	\N	f	\N
125	1	70	\N	1	1	100000	2026-02-25 06:57:40.436453+00	\N	\N	t	Điều chỉnh nhanh tại Admin
121	1	35	\N	1	1	100000	2026-02-10 15:02:51.741533+00	\N	\N	t	Điều chỉnh nhanh tại Admin
113	1	102	70	9	0	120000	2026-02-05 08:12:35.117236+00	\N	\N	f	\N
109	1	78	67	7	7	100000	2026-02-04 09:32:52.032439+00	\N	\N	f	\N
68	1	73	55	80	0	100000	2026-01-28 15:45:41.518783+00	\N	\N	f	\N
92	1	73	\N	1	0	100000	2026-02-02 14:07:28.374147+00	\N	\N	t	Điều chỉnh nhanh tại Admin
96	1	73	59	47	0	100000	2026-02-03 06:45:46.464457+00	\N	\N	f	\N
107	1	73	65	5	0	100000	2026-02-04 09:32:15.930946+00	\N	\N	f	\N
102	1	96	63	10	0	100000	2026-02-03 14:38:59.265787+00	\N	\N	f	\N
103	1	74	64	10	0	100000	2026-02-03 14:39:33.758546+00	\N	\N	f	\N
119	1	112	\N	1	1	160000	2026-02-09 05:09:42.615783+00	\N	\N	t	Điều chỉnh nhanh tại Admin
7	1	96	7	22	0	100000	2026-01-27 10:05:17.272177+00	\N	\N	f	\N
104	1	96	\N	1	0	100000	2026-02-04 08:34:26.078812+00	\N	\N	t	Điều chỉnh nhanh tại Admin
91	1	96	\N	1	0	100000	2026-02-02 14:07:16.977229+00	\N	\N	t	Điều chỉnh nhanh tại Admin
122	1	29	\N	1	0	0	2026-02-10 15:04:09.451727+00	\N	\N	t	Điều chỉnh nhanh tại Admin
95	1	90	\N	1	1	150000	2026-02-03 05:57:37.854938+00	\N	\N	t	Điều chỉnh nhanh tại Admin
97	1	92	60	1	1	100000	2026-02-03 06:46:35.972541+00	\N	\N	f	\N
98	1	88	61	19	19	150000	2026-02-03 06:48:34.877034+00	\N	\N	f	\N
99	1	89	62	19	19	150000	2026-02-03 06:48:47.912817+00	\N	\N	f	\N
100	1	81	\N	1	1	100000	2026-02-03 06:56:53.71384+00	\N	\N	t	Điều chỉnh nhanh tại Admin
101	1	49	\N	1	1	100000	2026-02-03 06:57:01.748953+00	\N	\N	t	Điều chỉnh nhanh tại Admin
110	1	92	68	1	2	100000	2026-02-04 09:33:13.318221+00	\N	\N	f	\N
106	1	96	\N	2	0	100000	2026-02-04 09:31:34.832904+00	\N	\N	t	Điều chỉnh nhanh tại Admin
116	1	83	\N	1	0	100000	2026-02-08 04:18:39.159703+00	\N	\N	t	Điều chỉnh nhanh tại Admin
117	1	83	\N	2	0	100000	2026-02-08 05:26:06.930423+00	\N	\N	t	Điều chỉnh nhanh tại Admin
123	1	28	\N	1	0	100000	2026-02-10 15:04:30.461164+00	\N	\N	t	Điều chỉnh nhanh tại Admin
120	1	73	\N	1	0	100000	2026-02-09 07:43:12.93161+00	\N	\N	t	Điều chỉnh nhanh tại Admin
118	1	96	73	12	11	100000	2026-02-08 15:09:28.297658+00	\N	\N	f	\N
71	1	77	57	20	0	100000	2026-01-28 16:02:18.785583+00	\N	\N	f	\N
105	1	46	\N	1	2	60000	2026-02-04 08:38:35.441536+00	\N	\N	t	Điều chỉnh nhanh tại Admin
90	1	23	\N	1	0	100000	2026-02-02 14:01:00.104034+00	\N	\N	t	Điều chỉnh nhanh tại Admin
108	1	77	66	4	3	100000	2026-02-04 09:32:37.819755+00	\N	\N	f	\N
11	1	92	11	10	3	100000	2026-01-27 10:07:18.342224+00	\N	\N	f	\N
32	1	75	32	14	7	100000	2026-01-27 10:14:36.713263+00	\N	\N	f	\N
124	1	74	\N	30	21	100000	2026-02-11 17:09:01.813497+00	\N	\N	t	Điều chỉnh nhanh tại Admin
\.


--
-- TOC entry 4070 (class 0 OID 17704)
-- Dependencies: 417
-- Data for Name: order_items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.order_items (id, order_id, variant_id, quantity, price_at_purchase, cogs_total) FROM stdin;
4	4	97	1	250000	100000
5	5	87	1	300000	120000
6	6	102	1	320000	150000
7	7	97	1	250000	100000
8	8	73	1	280000	100000
9	9	88	1	400000	150000
185	133	102	1	320000	120000
188	136	101	1	280000	100000
192	139	73	1	280000	100000
193	139	74	1	280000	100000
197	142	101	1	280000	100000
15	15	73	1	280000	100000
16	15	83	1	350000	100000
200	145	73	1	280000	100000
18	17	96	1	250000	100000
19	18	72	1	280000	100000
203	148	73	1	280000	100000
204	148	96	1	250000	100000
210	151	71	1	280000	100000
214	154	96	1	250000	100000
215	154	73	1	280000	100000
220	157	73	1	280000	100000
26	25	87	1	300000	120000
35	31	87	1	300000	120000
221	157	74	1	280000	100000
225	160	83	1	350000	100000
226	161	92	1	250000	100000
227	162	23	1	250000	100000
234	165	83	1	350000	100000
235	165	23	1	250000	100000
243	169	73	1	280000	100000
250	172	23	1	250000	100000
251	172	73	1	280000	100000
257	175	88	1	400000	150000
258	175	71	1	280000	100000
265	179	23	1	250000	100000
270	182	83	1	350000	100000
49	42	96	1	250000	100000
271	182	85	1	350000	100000
272	182	87	1	300000	120000
273	182	23	1	250000	100000
274	182	69	1	280000	100000
275	182	71	1	280000	100000
276	182	78	1	350000	100000
277	182	76	1	350000	100000
280	185	83	2	350000	200000
286	188	73	1	280000	100000
295	192	94	1	250000	100000
298	194	102	2	320000	240000
299	194	69	1	280000	100000
300	194	84	1	350000	100000
303	196	28	1	270000	100000
305	198	84	1	350000	100000
306	198	23	1	250000	100000
308	200	73	1	280000	100000
310	202	100	1	280000	115000
313	205	97	1	250000	100000
314	206	84	1	350000	100000
315	206	70	1	280000	100000
318	208	74	1	280000	100000
320	210	90	1	400000	150000
321	210	85	1	350000	100000
325	212	92	1	250000	100000
328	215	85	1	350000	100000
329	215	24	1	250000	100000
332	217	81	1	350000	100000
333	217	94	1	250000	100000
335	220	46	1	250000	60000
336	219	46	1	250000	60000
337	221	92	1	250000	100000
338	222	101	1	280000	100000
339	222	74	1	280000	100000
340	223	81	1	350000	100000
341	224	79	1	350000	100000
342	224	24	1	250000	0
343	225	79	1	350000	100000
88	72	101	1	280000	100000
89	72	102	1	320000	150000
344	226	89	1	400000	150000
345	227	71	1	280000	100000
346	228	74	1	280000	100000
347	229	84	1	350000	100000
348	229	70	1	280000	100000
349	230	76	1	350000	100000
350	231	23	1	250000	100000
351	232	96	1	250000	100000
352	232	92	1	250000	100000
99	79	96	1	250000	100000
100	79	73	1	280000	100000
353	232	74	1	280000	100000
354	233	96	1	250000	100000
355	233	23	1	250000	100000
356	234	74	1	280000	100000
357	235	81	1	350000	100000
358	236	96	1	250000	100000
359	236	97	1	250000	100000
360	236	95	1	250000	100000
361	237	46	1	250000	60000
362	237	45	1	140000	60000
363	238	81	1	350000	100000
364	239	79	1	350000	100000
365	239	74	1	280000	100000
366	240	96	1	250000	100000
367	240	74	1	280000	100000
368	241	36	1	180000	100000
369	241	86	1	350000	100000
370	242	101	1	280000	100000
371	243	35	1	180000	100000
1	1	77	1	350000	100000
2	2	80	1	350000	100000
3	3	80	1	350000	100000
27	26	97	1	250000	100000
28	27	95	1	250000	100000
29	27	23	1	250000	100000
30	28	73	1	280000	100000
31	29	28	1	270000	100000
32	29	75	1	350000	100000
33	30	97	1	250000	100000
34	30	73	1	280000	100000
186	134	101	1	280000	100000
189	137	73	1	280000	100000
194	140	74	1	280000	100000
195	140	92	1	250000	100000
198	143	96	1	250000	100000
201	146	73	1	280000	100000
205	149	76	1	350000	100000
206	149	88	1	400000	150000
207	149	98	1	250000	100000
211	152	100	1	280000	115000
216	155	96	1	250000	100000
217	155	74	1	280000	100000
222	158	24	1	250000	100000
223	158	81	1	350000	100000
228	163	23	1	250000	100000
136	102	94	1	250000	100000
229	163	83	1	350000	100000
236	166	96	1	250000	100000
139	104	96	1	250000	100000
140	105	24	1	250000	100000
237	166	73	1	280000	100000
244	170	81	1	350000	100000
245	170	36	1	180000	100000
252	173	96	1	250000	100000
253	173	94	1	250000	100000
254	173	73	1	280000	100000
259	176	95	1	250000	100000
260	176	73	1	280000	100000
149	113	24	1	250000	100000
150	114	24	1	250000	100000
266	180	83	1	350000	100000
267	180	84	1	350000	100000
268	180	74	1	280000	100000
278	183	96	1	250000	100000
281	186	96	1	250000	100000
282	186	79	1	350000	100000
283	186	24	1	250000	100000
289	190	33	1	220000	100000
290	190	94	1	250000	100000
291	190	96	2	250000	200000
292	190	73	1	280000	100000
293	190	74	1	280000	100000
296	193	85	1	350000	100000
297	193	97	1	250000	100000
301	195	96	1	250000	100000
302	195	73	1	280000	100000
304	197	24	1	250000	100000
307	199	73	1	280000	100000
309	201	102	1	320000	120000
311	203	101	1	280000	100000
312	204	100	1	280000	115000
316	207	90	1	400000	150000
317	207	84	1	350000	100000
319	209	94	1	250000	100000
322	211	93	1	250000	100000
323	211	86	1	350000	100000
324	211	24	1	250000	100000
326	213	75	1	350000	100000
327	214	97	1	250000	100000
180	128	101	1	280000	100000
330	216	96	1	250000	100000
331	216	73	1	280000	100000
334	218	74	1	280000	100000
184	132	96	1	250000	100000
36	32	73	1	280000	100000
37	33	97	1	250000	100000
38	33	73	1	280000	100000
39	34	36	1	180000	100000
40	34	83	1	350000	100000
41	35	87	1	300000	120000
42	36	93	1	250000	100000
43	37	100	1	280000	115000
44	38	100	1	280000	115000
45	39	94	1	250000	100000
46	40	112	1	350000	160000
47	40	78	1	350000	100000
48	41	79	1	350000	100000
50	43	96	1	250000	100000
51	44	92	1	250000	100000
52	45	81	1	350000	100000
53	45	24	1	250000	100000
54	45	75	1	350000	100000
55	45	90	1	400000	150000
56	46	96	1	250000	100000
57	47	96	1	250000	100000
58	48	96	1	250000	100000
59	49	96	1	250000	100000
60	50	96	2	250000	200000
61	51	96	1	250000	100000
62	52	93	1	250000	100000
63	53	49	1	190000	100000
64	54	112	1	350000	160000
65	57	96	1	250000	100000
66	58	96	1	250000	100000
67	59	95	1	250000	100000
68	59	74	1	280000	100000
69	60	95	1	250000	100000
70	60	74	1	280000	100000
71	61	76	1	350000	100000
72	61	77	1	350000	100000
73	61	89	1	400000	150000
74	61	24	1	250000	100000
75	61	28	1	270000	100000
76	62	24	1	250000	100000
77	63	74	1	280000	100000
78	64	96	1	250000	100000
79	64	73	1	280000	100000
80	65	78	1	350000	100000
81	66	74	1	280000	100000
82	67	102	1	320000	120000
83	68	90	1	400000	150000
84	68	96	1	250000	100000
85	69	23	1	250000	100000
86	70	85	1	350000	100000
87	71	33	1	220000	100000
90	73	88	1	400000	150000
91	73	77	1	350000	100000
92	74	96	1	250000	100000
93	75	73	1	280000	100000
94	76	23	1	250000	100000
95	76	24	1	250000	100000
96	77	73	1	280000	100000
97	77	83	1	350000	100000
98	78	99	1	250000	100000
101	80	96	1	250000	100000
102	81	73	1	280000	100000
103	82	90	1	400000	150000
104	82	79	1	350000	100000
105	83	93	1	250000	100000
106	84	101	1	280000	100000
107	85	100	1	280000	115000
108	86	77	1	350000	100000
109	87	73	1	280000	100000
110	87	97	1	250000	100000
111	88	24	1	250000	100000
112	89	73	1	280000	100000
113	90	36	1	180000	100000
114	90	81	1	350000	100000
115	90	89	1	400000	150000
116	90	102	2	320000	240000
117	90	100	2	280000	230000
118	90	101	1	280000	100000
119	91	97	1	250000	100000
120	92	73	1	280000	100000
121	93	78	1	350000	100000
122	94	33	1	220000	100000
123	94	74	1	280000	100000
124	95	74	1	280000	100000
125	95	96	1	250000	100000
126	96	96	1	250000	100000
127	97	73	1	280000	100000
128	97	96	1	250000	100000
129	98	96	1	250000	100000
130	98	73	1	280000	100000
131	99	73	1	280000	100000
132	99	96	1	250000	100000
133	100	96	1	250000	100000
134	100	73	1	280000	100000
135	101	73	1	280000	100000
137	103	23	1	250000	100000
138	103	83	1	350000	100000
141	106	96	1	250000	100000
142	106	73	1	280000	100000
143	107	49	1	190000	100000
144	108	46	1	250000	60000
145	109	36	1	180000	100000
146	110	46	1	250000	60000
147	111	101	1	280000	100000
148	112	73	1	280000	100000
151	115	97	1	250000	100000
152	115	73	1	280000	100000
153	116	73	1	280000	100000
154	117	96	1	250000	100000
155	118	96	1	250000	100000
156	118	73	1	280000	100000
157	119	98	1	250000	100000
158	119	73	1	280000	100000
159	120	96	1	250000	100000
160	120	73	1	280000	100000
161	121	96	1	250000	100000
162	121	73	1	280000	100000
163	122	23	1	250000	100000
164	122	24	1	250000	100000
165	122	96	1	250000	100000
166	122	93	1	250000	100000
167	122	73	1	280000	100000
168	122	81	1	350000	100000
169	122	78	1	350000	100000
170	123	96	1	250000	100000
171	123	73	1	280000	100000
172	123	77	1	350000	100000
173	124	74	1	280000	100000
174	125	102	1	320000	120000
175	125	100	1	280000	115000
176	125	73	1	280000	100000
177	126	96	1	250000	100000
178	126	73	1	280000	100000
179	127	100	1	280000	115000
181	129	87	1	300000	120000
182	130	24	1	250000	100000
183	131	73	1	280000	100000
187	135	96	1	250000	100000
190	138	73	1	280000	100000
191	138	96	1	250000	100000
196	141	73	2	280000	200000
199	144	102	1	320000	120000
202	147	24	1	250000	100000
208	150	73	1	280000	100000
209	150	96	1	250000	100000
212	153	96	1	250000	100000
213	153	73	1	280000	100000
218	156	73	1	280000	100000
219	156	96	1	250000	100000
224	159	93	1	250000	100000
230	164	71	1	280000	100000
231	164	81	1	350000	100000
232	164	94	1	250000	100000
233	164	73	1	280000	100000
238	167	36	1	180000	100000
239	167	95	1	250000	100000
240	167	28	1	270000	100000
241	167	112	1	350000	160000
242	168	101	1	280000	100000
246	171	49	1	190000	100000
247	171	46	1	250000	60000
248	171	73	1	280000	100000
249	171	33	1	220000	100000
255	174	80	1	350000	100000
256	174	24	1	250000	100000
261	177	23	1	250000	100000
262	178	83	1	350000	100000
263	178	73	1	280000	100000
264	178	88	1	400000	150000
269	181	73	1	280000	100000
279	184	102	1	320000	120000
284	187	94	1	250000	100000
285	187	81	1	350000	100000
287	189	90	1	400000	150000
288	189	73	1	280000	100000
294	191	97	1	250000	100000
372	243	23	1	250000	100000
373	244	28	1	270000	100000
374	244	96	1	250000	100000
375	244	88	1	400000	150000
376	244	74	1	280000	100000
377	245	88	1	400000	150000
378	245	79	1	350000	100000
379	246	23	1	250000	100000
380	247	74	1	280000	100000
381	247	94	1	250000	100000
382	248	77	1	350000	100000
383	249	79	1	350000	100000
384	249	23	1	250000	100000
385	249	74	1	280000	100000
386	250	96	1	250000	100000
387	251	96	1	250000	100000
388	252	75	1	350000	100000
389	253	70	1	280000	100000
390	253	74	1	280000	100000
391	254	95	1	250000	100000
392	254	81	1	350000	100000
393	255	95	1	250000	100000
394	255	76	1	350000	100000
395	256	88	1	400000	150000
396	256	49	1	190000	100000
397	256	77	1	350000	100000
398	257	50	1	190000	100000
399	257	52	1	190000	100000
400	257	69	1	280000	100000
401	257	71	1	280000	100000
402	257	92	1	250000	100000
403	257	94	1	250000	100000
404	257	96	1	250000	100000
405	257	98	1	250000	100000
406	257	23	1	250000	100000
407	258	94	1	250000	100000
408	258	76	1	350000	100000
409	259	96	1	250000	100000
410	260	85	1	350000	100000
411	260	74	1	280000	100000
412	261	94	1	250000	100000
413	261	74	1	280000	100000
414	261	23	1	250000	100000
415	262	76	1	350000	100000
416	263	74	1	280000	100000
417	264	97	1	250000	100000
418	265	101	1	280000	100000
419	266	85	1	350000	100000
420	267	85	1	350000	100000
421	267	89	1	400000	150000
422	268	33	1	220000	100000
423	269	23	1	250000	100000
424	270	100	1	280000	115000
425	271	47	1	190000	100000
426	271	92	1	250000	100000
427	272	101	1	280000	100000
428	273	85	1	350000	100000
429	274	79	1	350000	100000
430	274	88	1	400000	150000
431	275	99	1	250000	100000
432	275	89	1	400000	150000
433	275	33	1	220000	100000
434	275	74	1	280000	100000
435	275	23	1	250000	100000
436	276	77	1	350000	100000
437	277	90	1	400000	150000
438	278	77	1	350000	100000
439	279	96	1	250000	100000
440	280	74	1	280000	100000
441	281	94	1	250000	100000
442	282	92	1	250000	100000
443	283	74	1	280000	100000
444	284	89	1	400000	150000
445	285	97	1	250000	100000
446	286	79	1	350000	100000
447	286	23	1	250000	100000
448	287	46	2	250000	120000
449	287	33	1	220000	100000
450	288	27	1	270000	100000
451	288	96	1	250000	100000
452	289	101	1	280000	100000
453	290	81	1	350000	100000
454	291	97	1	250000	100000
455	292	101	1	280000	100000
456	293	101	1	280000	100000
457	294	85	1	350000	100000
458	294	49	1	190000	100000
459	295	46	1	250000	60000
460	296	77	1	350000	100000
461	297	47	1	190000	100000
462	298	74	1	280000	100000
463	299	100	1	280000	115000
464	299	76	1	350000	100000
465	300	101	1	280000	100000
466	301	94	1	250000	100000
467	302	89	1	400000	150000
468	302	95	1	250000	100000
469	302	97	1	250000	100000
470	302	76	1	350000	100000
471	302	77	1	350000	100000
472	302	74	1	280000	100000
473	303	97	1	250000	100000
474	304	75	1	350000	100000
475	304	85	1	350000	100000
476	305	85	1	350000	100000
477	306	47	1	190000	100000
478	307	74	1	280000	100000
479	307	85	1	350000	100000
480	308	88	1	400000	150000
481	309	74	1	280000	100000
482	310	96	1	250000	100000
483	311	97	1	250000	100000
484	312	93	1	250000	100000
485	312	79	1	350000	100000
486	312	77	1	350000	100000
487	313	84	1	350000	100000
488	314	81	1	350000	100000
489	314	71	1	280000	100000
490	315	23	1	250000	100000
491	315	81	1	350000	100000
492	316	100	1	280000	115000
493	317	77	1	350000	100000
494	318	88	1	400000	150000
495	318	95	1	250000	100000
496	319	101	1	280000	100000
497	320	100	1	280000	115000
498	321	101	1	280000	100000
499	322	97	1	250000	100000
500	323	75	1	350000	100000
501	323	74	1	280000	100000
\.


--
-- TOC entry 4068 (class 0 OID 17674)
-- Dependencies: 415
-- Data for Name: orders; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.orders (id, code, customer_id, store_id, promotion_id, subtotal, discount_amount, shipping_fee, total_amount, payment_method, status, note, created_at, customer_name, customer_phone, customer_address, customer_email, shipping_carrier, shipping_tracking_code, payment_status, email, customer_district_id, customer_ward_code) FROM stdin;
3	#ADM-035074	3	\N	\N	350000	0	0	350000	transfer	cancelled	Ig kiki	2026-01-27 16:40:35.546139+00	Kỳ Kỳ	0708083054	214/C45 Nguyễn Trãi, phường Nguyễn Cư Trinh, Quận 1	\N	\N	\N	unpaid	\N	\N	\N
5	ORD-73511769621093	5	\N	\N	300000	0	20000	320000	banking	cancelled	\N	2026-01-28 17:24:53.187139+00	Đởm Triết	0979911670	15 NXK, Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	1456	21509
6	ORD-48761769621359	5	\N	\N	320000	0	20000	340000	banking	cancelled	\N	2026-01-28 17:29:19.272408+00	Đởm Triết	0979911670	15 NXK, Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	1456	21509
7	ORD-26581769621681	1	\N	\N	250000	0	20000	270000	banking	cancelled	\N	2026-01-28 17:34:40.547563+00	Admin Brown	0900000000	15 NXK, Quận Tân Phú, Hồ Chí Minh	brownvn25@gmail.com	\N	\N	unpaid	\N	1456	21509
8	ORD-64151769777792	7	\N	\N	280000	0	20000	300000	banking	cancelled	\N	2026-01-30 12:56:31.552607+00	Anh thư	0967849849	9/1b xô viết nghệ tĩnh , Quận Ninh Kiều, Cần Thơ	hinhanhthu0197@gmail.com	\N	\N	unpaid	\N	1572	550102
9	ORD-88891769780624	8	\N	\N	400000	0	20000	420000	banking	cancelled	\N	2026-01-30 13:43:44.02047+00	Lu Bu Tông	0881718137	12 Lộp Chộp, huyện Sốp Cộp, Sơn La	jamaica@buchaby.com	\N	\N	unpaid	\N	3266	800118
31	ORD-81081769920527	17	\N	\N	300000	0	20000	320000	banking	cancelled	\N	2026-02-01 04:35:26.819583+00	Bảo Trinh	0359501066	Vinhomes grand park q9 toà Be5, Quận 9, Hồ Chí Minh	tranhabaotrinh@gmail.com	\N	\N	unpaid	\N	1451	20904
25	ORD-43681769875269	5	\N	\N	300000	0	20000	320000	banking	cancelled	\N	2026-01-31 16:01:08.673765+00	Test Email	0979911670	15 NXK, Huyện Tam Đường, Lai Châu	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	2010	70210
17	ORD-27811769843771	10	\N	\N	250000	0	20000	270000	banking	cancelled	\N	2026-01-31 07:16:10.886908+00	thuỳ trang 	0987346948	282 ấp bình phước, Huyện Chợ Mới, An Giang	chanxinh2505@gmail.com	\N	\N	unpaid	\N	1757	510904
37	#ADM-647150	22	\N	\N	280000	0	0	280000	transfer	cancelled	KOL	2026-02-01 13:14:07.241781+00	Kol _kduyeen	0905650280  	20 đường 19c phạm thế hiển p7 q8	\N	\N	\N	unpaid	\N	\N	\N
18	ORD-20481769856848	11	\N	\N	280000	0	20000	300000	banking	completed	\N	2026-01-31 10:54:08.244554+00	Nguyễn Thị Vân Anh	0857900799	Toà TNR, 54A Nguyễn Chí Thanh₫, Quận Đống Đa, Hà Nội	anhnv270199@gmail.com	\N	GY3QDUDW	unpaid	\N	1486	1A0407
15	ORD-66281769788258	9	\N	\N	630000	0	20000	650000	banking	completed	\N	2026-01-30 15:50:57.890721+00	Nguyễn Kế Châu Anh	0911066568	Sky89, 89 Lê Thị Chợ, Quận 7, TPHCM, Quận 7, Hồ Chí Minh	jenninguyenke@gmail.com	\N	GYBMRRLF	unpaid	\N	1449	20702
42	ORD-93101769953574	25	\N	\N	250000	0	20000	270000	banking	cancelled	\N	2026-02-01 13:46:14.288794+00	Ngọc Phương	0387561470	Hẻm 494, số nhà 494/3, Huyện Vĩnh Cửu, Đồng Nai	ngocphuong231102@gmail.com	\N	\N	unpaid	\N	2049	480209
47	#ADM-352296	29	\N	\N	250000	0	0	250000	cod	cancelled		2026-02-01 15:22:32.371293+00	nhi	12234567	jkdkjgk	\N	\N	\N	unpaid	\N	\N	\N
46	#ADM-073734	25	\N	\N	250000	0	0	250000	cod	shipping	Web	2026-02-01 15:17:54.206363+00	Ngọc Phương	0387561470	Địa chỉ giao hàng\nHẻm 494, số nhà 494/3, Huyện Vĩnh Cửu, Đồng Nai	\N	\N	\N	unpaid	\N	\N	\N
45	#ADM-840803	28	\N	\N	1350000	0	0	1350000	transfer	shipping	Ig huong xu le	2026-02-01 15:14:00.919896+00	Thảo (Huong Xu Le)	0904502318	93, P.Bạch Mai, Q.Hai Bà Trưng, TP.Hà Nội	\N	\N	\N	unpaid	\N	\N	\N
44	#ADM-753467	27	\N	\N	250000	0	0	250000	transfer	shipping	Ig inthezone.02.04	2026-02-01 15:12:33.56863+00	Thái Phụng 	0962645716 	385F/39A-B, Đ. Trần Nam Phú, An Khánh, Ninh Kiều, Cần Thơ	\N	\N	\N	unpaid	\N	\N	\N
43	#ADM-017783	26	\N	\N	250000	0	0	250000	transfer	shipping	Ig haiien.ho	2026-02-01 14:10:17.886072+00	Ig haiien.ho	0388955848	318 Nguyễn Oanh, P17, quận Gò Vấp	\N	\N	\N	unpaid	\N	\N	\N
40	#ADM-422686	18	\N	\N	700000	0	0	700000	transfer	shipping	Ig gnasche.lorie	2026-02-01 13:27:02.797571+00	gnasche.lorie	0789515460	15 Nguyễn Xuân Khoát	\N	\N	\N	unpaid	\N	\N	\N
39	#ADM-716235	23	\N	\N	250000	0	0	250000	transfer	shipping	Ig quyên	2026-02-01 13:15:16.328318+00	Quyên	0901606857	72 lê thánh tôn p bến thành vincom đồng khởi	\N	\N	\N	unpaid	\N	\N	\N
36	#ADM-041916	21	\N	\N	250000	0	0	250000	transfer	shipping	Ig Bích Liên	2026-02-01 13:04:02.009185+00	Bích Liên	0964226997	24 lê thánh tôn q1	\N	\N	\N	unpaid	\N	\N	\N
38	#ADM-647561	22	\N	\N	280000	0	0	280000	transfer	completed	KOL	2026-02-01 13:14:07.656013+00	Kol _kduyeen	0905650280  	20 đường 19c phạm thế hiển p7 q8	\N	\N	\N	unpaid	\N	\N	\N
35	#ADM-749363	17	\N	\N	300000	0	0	300000	transfer	shipping	web	2026-02-01 09:55:49.493655+00	Bảo Trinh	0359501066	Vinhomes grand park q9 toà Be5, Quận 9, Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N
34	#ADM-042575	20	\N	\N	530000	0	0	530000	transfer	shipping	Ig thanh hằng	2026-02-01 06:24:02.676784+00	Vũ Thái Thanh Hằng 	0972032010	235 hồng thập tự, long khánh, đồng nai	\N	\N	\N	unpaid	\N	\N	\N
33	#ADM-948065	19	\N	\N	530000	0	0	530000	transfer	shipping	Ig minh thư	2026-02-01 06:22:28.189781+00	Thư 	 0902905362	114 đồng văn cống, phường cát lái, hcm	\N	\N	\N	unpaid	\N	\N	\N
32	#ADM-791546	18	\N	\N	280000	0	0	280000	transfer	shipping	Ig ttrraamm	2026-02-01 06:19:51.64851+00	ttrraamm	0789515460	Khách tới nhà lấy	\N	\N	\N	unpaid	\N	\N	\N
30	#ADM-527225	16	\N	\N	530000	0	0	530000	cod	shipping	Ig thie	2026-02-01 03:45:27.357471+00	Phương Thi 	0937809293 	Toà nhà Lafayatte số 8 đường Phùng Khắc Khoan phường Sài Gòn TPHCM - Lầu 2 APRIL	\N	\N	\N	unpaid	\N	\N	\N
28	#ADM-061726	14	\N	\N	280000	0	0	280000	transfer	shipping	Ig thuý an	2026-02-01 03:37:41.86013+00	Thuy an	0377029438	183 đan kia phường 7 đà lạt	\N	\N	\N	unpaid	\N	\N	\N
27	#ADM-764749	13	\N	\N	500000	0	0	500000	cod	shipping	Ig ngọc ngọc	2026-02-01 03:32:44.853931+00	ngọc ngọc 	0988224226 	132 bến vân đồn P6 Q4	\N	\N	\N	unpaid	\N	\N	\N
26	#ADM-023376	12	\N	\N	250000	0	0	250000	transfer	shipping	Ig su	2026-01-31 17:03:43.480494+00	SU	0976685522	chung cư khánh hội 3, 360G Bến Vân Đồn P1, Q4	\N	\N	\N	unpaid	\N	\N	\N
29	#ADM-345301	15	\N	\N	620000	0	0	620000	transfer	completed	Ig tô vân	2026-02-01 03:42:25.405891+00	Tô vân 	0962755240	30 Yên Ninh, Ba Đình, HN 	\N	\N	\N	unpaid	\N	\N	\N
2	#ADM-034177	3	\N	\N	350000	0	0	350000	transfer	completed	Ig kiki	2026-01-27 16:40:34.327486+00	Kỳ Kỳ	0708083054	214/C45 Nguyễn Trãi, phường Nguyễn Cư Trinh, Quận 1	\N	\N	\N	unpaid	\N	\N	\N
4	ORD-27101769620733	4	\N	\N	250000	0	20000	270000	banking	completed	\N	2026-01-28 17:18:53.284955+00	Hân Kitty Phạm	0325225854	06 Song Hàng An Phú Quận 2 cũ, Thành Phố Thủ Đức, Hồ Chí Minh	phamngochan9694@gmail.com	\N	\N	unpaid	\N	3695	90765
1	#ADM-451432	2	\N	\N	350000	0	0	350000	cod	completed	Ig baongoc08	2026-01-27 10:24:11.543574+00	Ngọc 	0967515969	Midtown The Peak M8 block A đường 15 phường tân phú q7	\N	\N	\N	unpaid	\N	\N	\N
48	#ADM-500909	5	\N	\N	250000	0	0	250000	transfer	cancelled		2026-02-01 15:25:01.035579+00	Test 	0979911670	k;nmjl;kjh	\N	\N	\N	unpaid	\N	\N	\N
49	#ADM-180547	5	\N	\N	250000	0	0	250000	transfer	cancelled	Test	2026-02-01 15:53:00.767728+00	Test	0979911670	15 NXK	\N	\N	\N	unpaid	\N	\N	\N
50	#ADM-258223	5	\N	\N	500000	0	0	500000	transfer	cancelled	Test	2026-02-01 15:54:18.363434+00	Test	0979911670	15 NXK	\N	\N	\N	unpaid	\N	\N	\N
51	#ADM-442918	5	\N	\N	250000	0	0	250000	cod	cancelled	Test	2026-02-01 15:57:23.068419+00	Test 	0979911670	15 NXK	\N	\N	\N	unpaid	\N	\N	\N
57	#ADM-319948	5	\N	\N	250000	0	0	250000	transfer	cancelled	Test	2026-02-02 04:25:20.111663+00	Test 	0979911670	15 NXK	\N	\N	\N	unpaid	\N	\N	\N
74	#ADM-171631	41	\N	\N	250000	0	0	250000	transfer	shipping	Ig	2026-02-02 16:19:31.72944+00	Ig khánh ngọc 	0328766486	30 lê trung nghĩa p bảy hiền hcm	\N	\N	\N	unpaid	\N	\N	\N
58	#ADM-967080	5	\N	\N	250000	0	0	250000	transfer	returned	Test	2026-02-02 04:36:07.246629+00	Test 	0979911670	15 NXK	\N	\N	\N	unpaid	\N	\N	\N
62	#ADM-045605	31	\N	\N	250000	0	0	250000	cod	cancelled	Ig ngọc ngọc	2026-02-02 14:04:05.725914+00	Ig Ngọc Ngọc	0988224226	132 bến vân đồn quận 4	\N	\N	\N	unpaid	\N	\N	\N
72	ORD-43911770044400	39	\N	\N	600000	0	20000	620000	banking	shipping	\N	2026-02-02 15:00:00.067668+00	Khánh Linh	0902850016	6/5 quốc hương, Thành Phố Thủ Đức, Hồ Chí Minh	khnhlin143@gmail.com	\N	\N	unpaid	\N	3695	90764
70	#ADM-948437	37	\N	\N	350000	0	0	350000	transfer	shipping	Ig bao quyen	2026-02-02 14:19:08.536666+00	Ig bao quyen ( Quyên)	0773872547	k356/h111/3 hoàng diệu,hải châu,đà nẵng ( trước sát nhập )	\N	\N	\N	unpaid	\N	\N	\N
73	#ADM-116391	40	\N	\N	750000	0	0	750000	transfer	completed	Ig	2026-02-02 16:18:36.506886+00	ig Be Han	0933888347	203 cao văn lầu p2 q6 cũ	\N	\N	\N	unpaid	\N	\N	\N
69	#ADM-902433	36	\N	\N	250000	0	0	250000	transfer	shipping	Ig uynuyn	2026-02-02 14:18:22.529926+00	Ig uynuyn	0989572278	Tô mì studio đường nguyễn văn linh phường mỹ phước Long Xuyên an giang	\N	\N	\N	unpaid	\N	\N	\N
52	#ADM-788228	18	\N	\N	250000	0	0	250000	transfer	completed	IG	2026-02-02 03:59:48.327476+00	Khánh Huyền	0789515460	15 Nguyễn Xuân Khoát	\N	\N	\N	unpaid	\N	\N	\N
71	#ADM-009896	38	\N	\N	220000	0	0	220000	transfer	shipping	Ig minh anh	2026-02-02 14:20:09.991983+00	Ig minh anh (Nguyễn Hoàng Minh Anh)	0395926658	1304, toà N4B khu đô thị Trung Hoà Nhân Chính, Thanh Xuân,Hà Nội	\N	\N	\N	unpaid	\N	\N	\N
68	#ADM-857245	18	\N	\N	650000	0	0	650000	transfer	shipping	Baby dưa lưới xinh iu	2026-02-02 14:17:37.345771+00	Ig Baby dưa lưới xinh iu 	0789515460	15 nguyễn xuân khoát	\N	\N	\N	unpaid	\N	\N	\N
67	#ADM-755858	35	\N	\N	320000	0	0	320000	transfer	shipping	Ig alna nguyen	2026-02-02 14:15:55.971453+00	Ig alna nguyen (alna nguyen)	0937748847	918/9H hương lộ 2 - Phường Bình Trị Đông A - Quận bình tân	\N	\N	\N	unpaid	\N	\N	\N
66	#ADM-629086	34	\N	\N	280000	0	0	280000	transfer	shipping	Ig huỳnh như quỳnh	2026-02-02 14:13:49.212444+00	Ig huỳnh như quỳnh (Như Quỳnh)	0356620045	block b chung cư sunrise riverside, phước kiểng, nhà bè	\N	\N	\N	unpaid	\N	\N	\N
65	#ADM-565118	33	\N	\N	350000	0	0	350000	transfer	shipping	Ig n.nhii01	2026-02-02 14:12:45.281629+00	Ig n.nhii01 ( Nhi )	0941840848	280 nguyễn trường tộ tân hoà biên hoà đồng nai	\N	\N	\N	unpaid	\N	\N	\N
64	#ADM-319317	32	\N	\N	530000	0	0	530000	transfer	shipping	Ig huyền lê	2026-02-02 14:08:39.410946+00	Ig Huyền Lê	0929333317	333 điện biên phủ, bình thạnh	\N	\N	\N	unpaid	\N	\N	\N
63	#ADM-222468	31	\N	\N	280000	0	0	280000	transfer	shipping	Ig ngọc ngọc	2026-02-02 14:07:02.591082+00	ig ngọc ngọc	0988224226	132 bến vân đồn quận 4	\N	\N	\N	unpaid	\N	\N	\N
61	#ADM-082229	30	\N	\N	1620000	0	0	1620000	transfer	completed	IG	2026-02-02 06:51:22.348334+00	Ig Bee	0902616275	162/15 Đường số 42, phường Bình Trưng Đông, Thủ Đức	\N	\N	\N	unpaid	\N	\N	\N
60	#ADM-714228	18	\N	\N	530000	0	0	530000	transfer	completed	Ig	2026-02-02 05:38:34.377443+00	ig Vicky	0789515460	652 Lạc long Quân quận tân bình	\N	\N	\N	unpaid	\N	\N	\N
59	#ADM-659099	18	\N	\N	530000	0	0	530000	transfer	shipping	IG	2026-02-02 05:37:39.255543+00	Ig iamlekhanh	0789515460	633 hậu giang quận 6	\N	\N	\N	unpaid	\N	\N	\N
41	#ADM-114962	24	\N	\N	350000	0	0	350000	transfer	shipping	Ig pông pính	2026-02-01 13:38:35.066308+00	Phạm Yến	0907673591	B10.09, chung cư The Golden Star, 58B Nguyễn Thị Thập, phường Bình Thuận, quận 7, tp. HCM	\N	\N	\N	unpaid	\N	\N	\N
75	#ADM-814144	42	\N	\N	280000	0	0	280000	transfer	shipping	Ig phuc hanh pham	2026-02-02 17:20:14.251626+00	Ig phuc hanh pham	0855877511	264 nam kì khởi nghĩa, p. Xuân hoà, hcm	\N	\N	\N	unpaid	\N	\N	\N
76	#ADM-109244	43	\N	\N	500000	0	0	500000	transfer	shipping	Ig gud9.nhuy	2026-02-02 17:58:29.3723+00	Như Ý	0906482677	 86 chu văn an p26 quận bình thạnh	\N	\N	\N	unpaid	\N	\N	\N
77	#ADM-191920	44	\N	\N	630000	0	0	630000	transfer	shipping	Ig duy linh nguyen	2026-02-02 17:59:52.041413+00	Duy Linh Nguyễn	0931637448	07 Đặng Tất, phường Buôn Hồ, tỉnh ĐakLak	\N	\N	\N	unpaid	\N	\N	\N
78	#ADM-976805	18	\N	\N	250000	0	0	250000	transfer	completed	Ig vicky	2026-02-02 19:36:16.975577+00	Ig Vicky 	0789515460	652 lạc long quân phường tân hoà quận tân bình	\N	\N	\N	unpaid	\N	\N	\N
79	ORD-81081770094385	17	\N	\N	530000	0	20000	550000	banking	shipping	\N	2026-02-03 04:53:04.833109+00	Bảo Trinh	0359501066	VinHomes grand park sảnh Be5, Thành Phố Thủ Đức, Hồ Chí Minh	tranhabaotrinh@gmail.com	\N	\N	unpaid	\N	3695	90752
83	#ADM-935640	46	\N	\N	250000	0	0	250000	transfer	shipping	Ig by_elisette	2026-02-03 06:08:55.836905+00	Ig by_elisette	0397024181	89/13 Nguyễn Thượng Hiền, p5, Bình Thạnh	\N	\N	\N	unpaid	\N	\N	\N
82	#ADM-246965	47	\N	\N	750000	0	0	750000	transfer	shipping	Thiện Thảo KOl	2026-02-03 05:57:27.070152+00	Thiện Thảo	0898681865	126 đường 38 Bình Trưng Tây - Thủ Đức	\N	\N	\N	unpaid	\N	\N	\N
80	#ADM-111467	45	\N	\N	250000	0	0	250000	transfer	shipping	Ig ân nin	2026-02-03 05:55:11.568092+00	Ig ân nin 	0909215263	1269 phan văn trị p gò vấp 	\N	\N	\N	unpaid	\N	\N	\N
81	#ADM-175660	46	\N	\N	280000	0	0	280000	transfer	shipping	Ig by_elisette	2026-02-03 05:56:15.761212+00	Ig by_elisette	0397024181	89/13 Nguyễn Thượng Hiền, p5, Bình Thạnh	\N	\N	\N	unpaid	\N	\N	\N
54	#ADM-939466	18	\N	\N	350000	0	0	350000	transfer	shipping	Shopee	2026-02-02 04:02:19.562971+00	Nguyễn Bích Huyền shopee	0789515460	45/7, Nguyễn Công Trứ, Phường 8,\nThành Phố Đà Lạt, Lâm Đồng	\N	\N	\N	unpaid	\N	\N	\N
53	#ADM-882607	18	\N	\N	190000	0	0	190000	transfer	shipping	shopee	2026-02-02 04:01:22.719378+00	Minh Tâm shopee	0789515460	Khu Ba Đình, Thị Trấn Nam Ban,\nHuyện Lâm Hà, Lâm Đồng	\N	\N	\N	unpaid	\N	\N	\N
85	#ADM-994854	50	\N	\N	280000	0	0	280000	transfer	shipping	Ig crtnch	2026-02-03 16:09:54.971957+00	Ig crtnch 	0325267896	 375 tân thới hiệp 21 , Tổ 3 ,Kp3 ,quận 12 ( nhớ gõ đủ)	\N	\N	\N	unpaid	\N	\N	\N
86	#ADM-034357	51	\N	\N	350000	0	0	350000	transfer	shipping	Ig hanjin_wb	2026-02-03 16:10:34.486226+00	Nhi	0909078752	192 nguyễn công trứ phường Bến Thành	\N	\N	\N	unpaid	\N	\N	\N
102	ORD-47431770137622	65	\N	\N	250000	0	20000	270000	banking	shipping	\N	2026-02-03 16:53:42.179006+00	Phạm Thành Khang	0904835375	Chung cư Tân Mai, Lê Đức Anh, Quận Bình Tân, Hồ Chí Minh	khangpham.5375@gmail.com	\N	\N	unpaid	\N	1458	21909
104	ORD-20921770181811	67	\N	\N	250000	0	20000	270000	banking	shipping	\N	2026-02-04 05:10:10.750667+00	Phạm ngọc hân 	0384295534	Số 42d thạnh xuân 37 quận 12( trong bãi vật liệu đức trí fpt), Quận 12, Hồ Chí Minh	ngochan280811@gmail.com	\N	\N	unpaid	\N	1454	21209
105	ORD-21381770189358	69	\N	\N	250000	0	20000	270000	banking	shipping	\N	2026-02-04 07:15:57.826099+00	kiều thị kim anh	0839010434	khách sạn hoa sứ, trại bò phúc lộc, Huyện Châu Thành, Tiền Giang		\N	\N	unpaid	\N	1740	530518
113	ORD-30151770208234	74	\N	\N	250000	0	20000	270000	banking	cancelled	\N	2026-02-04 12:30:34.361422+00	Hà Quyên 	0981681406	24 đường b2 Phước hải ( Nhà ngô kỳ nhiên ) , Thành phố Nha Trang, Khánh Hòa		\N	\N	unpaid	\N	1548	410103
84	#ADM-947792	48	\N	\N	280000	0	0	280000	transfer	shipping	Ig bống	2026-02-03 06:42:27.895815+00	Ig bống	0832191587	144 triệu việt vương nguyễn du hai bà trưng hà nội 	\N	\N	\N	unpaid	\N	\N	\N
87	#ADM-096741	52	\N	\N	530000	0	0	530000	transfer	shipping	Ig thu hà	2026-02-03 16:11:36.859056+00	Ig thu hà	0398514443	Thôn 7a \nEawy-eahleo-dăk lái	\N	\N	\N	unpaid	\N	\N	\N
88	#ADM-153851	53	\N	\N	250000	0	0	250000	transfer	shipping	Ig thuý ngọc	2026-02-03 16:12:33.972456+00	Ig thuý ngọc	0702928310	Ấp 1A , xã Tân Hoà , tp Cần Thơ	\N	\N	\N	unpaid	\N	\N	\N
89	#ADM-217521	54	\N	\N	280000	0	0	280000	transfer	shipping	Ig nhee nhee	2026-02-03 16:13:37.632741+00	Ig nhee nhee	0396994800	Số 38 đường D4, phường chánh nghĩa, thành phố thủ dầu một, bình dương	\N	\N	\N	unpaid	\N	\N	\N
90	#ADM-315303	55	\N	\N	2410000	0	0	2410000	transfer	shipping	Ig bow bangkok	2026-02-03 16:15:15.438053+00	Ig bow bangkok	0369166.222	163 Trương Thị Hoa, phường Tân Thới Hiệp, Quận 12, thành phố Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N
91	#ADM-378951	32	\N	\N	250000	0	0	250000	transfer	shipping	Ig huyền lê	2026-02-03 16:16:19.094561+00	Ig huyền lê 	0929333317	333 điện biên phủ, bình thạnh	\N	\N	\N	unpaid	\N	\N	\N
92	#ADM-420380	56	\N	\N	280000	0	0	280000	transfer	shipping	Ig bảo loan	2026-02-03 16:17:00.502284+00	Ig bảo loan	0564164989	K486 nguyễn tri phương cẩm nam hội an quảng nam	\N	\N	\N	unpaid	\N	\N	\N
93	#ADM-466026	18	\N	\N	350000	0	0	350000	transfer	shipping	Sarah ig	2026-02-03 16:17:46.170009+00	Sarah ig	0789515460	15 nguyễn xuân khoát	\N	\N	\N	unpaid	\N	\N	\N
94	#ADM-659081	57	\N	\N	500000	0	0	500000	transfer	shipping	Ig baconmeocon	2026-02-03 16:20:59.195182+00	Ig baconmeocon	0938080124	16 đường số 4, kdc Nam Hùng vương, p an lạc, kp3 quận bình tân, Phường An Lạc, Quận Bình Tân, TP Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N
95	#ADM-705579	58	\N	\N	530000	0	0	530000	transfer	shipping	Ig ggiantttttt	2026-02-03 16:21:45.695577+00	Ig ggiantttttt	0918974705	481/23/10 tân kì tân quý, tân phú	\N	\N	\N	unpaid	\N	\N	\N
96	#ADM-758270	59	\N	\N	250000	0	0	250000	transfer	shipping	Ig em PT mét gữi	2026-02-03 16:22:38.400281+00	Ig em PT mét gữi 	0903522900	48/11 Nguyễn An Ninh, p14 , Q. Bình Thạnh , HCM	\N	\N	\N	unpaid	\N	\N	\N
97	#ADM-800426	60	\N	\N	530000	0	0	530000	transfer	shipping	ig giang tran	2026-02-03 16:23:20.556046+00	ig giang tran 	0907739179	17F2/A42, khu phố 6, phường Trung Dũng, Biên Hoà	\N	\N	\N	unpaid	\N	\N	\N
106	#ADM-954329	70	\N	\N	530000	0	0	530000	cod	shipping	Ig nguyễn thị thảo nguyên	2026-02-04 08:32:34.428825+00	Ig nguyễn thị thảo nguyên	0966240425	Ngã tư chánh nhơn cát nhơn phù cát bình định	\N	\N	\N	unpaid	\N	\N	\N
98	#ADM-848656	61	\N	\N	530000	0	0	530000	transfer	shipping	Ig Bby	2026-02-03 16:24:08.770986+00	Ig Bby 	0769998968	146/2q đường số 30, p6 Gò Vấp	\N	\N	\N	unpaid	\N	\N	\N
99	#ADM-887254	62	\N	\N	530000	0	0	530000	transfer	shipping	Ig tiểu my	2026-02-03 16:24:47.389922+00	Ig tiểu my 	0988041293	Chung cư Sunshine Diamond River , 422 Đào Trí , Phú Thuận , Q7 	\N	\N	\N	unpaid	\N	\N	\N
100	#ADM-929946	63	\N	\N	530000	0	0	530000	transfer	shipping	Ig babimilo.11	2026-02-03 16:25:30.066045+00	Ig babimilo.11	093360237	436b/17 ba thang hai p12 quan 10	\N	\N	\N	unpaid	\N	\N	\N
101	#ADM-586560	64	\N	\N	280000	0	0	280000	transfer	shipping	Ig	2026-02-03 16:53:06.686113+00	ngọc	0769823114	371 nguyễn oanh, p17 gò vấp	\N	\N	\N	unpaid	\N	\N	\N
103	#ADM-632848	66	\N	\N	600000	0	0	600000	transfer	shipping	Ig nguyễn hoàng nhật ái	2026-02-03 16:53:52.963505+00	Ig nguyễn hoàng nhật ái	0777777900	90 Nguyễn Hữu Cảnh , phường 22 , quận Bình Thạnh ,	\N	\N	\N	unpaid	\N	\N	\N
112	#ADM-496122	73	\N	\N	280000	0	0	280000	transfer	shipping	Ig kaythy.16	2026-02-04 12:01:36.232859+00	Ig kaythy.16	0935539978	270/109/14 phan đình phùng , p1 phú nhuận	\N	\N	\N	unpaid	\N	\N	\N
107	#ADM-184142	71	\N	\N	190000	0	0	190000	transfer	shipping	shopee	2026-02-04 08:36:24.252948+00	thanh tuyền	789515460	15NXK	\N	\N	\N	unpaid	\N	\N	\N
108	#ADM-220578	71	\N	\N	250000	0	0	250000	transfer	shipping	shopee	2026-02-04 08:37:00.692294+00	hà kiều oanh	789515460	15NXK	\N	\N	\N	unpaid	\N	\N	\N
109	#ADM-247362	71	\N	\N	180000	0	0	180000	transfer	shipping	shopee	2026-02-04 08:37:27.481851+00	hoai vy	789515460	15NXK	\N	\N	\N	unpaid	\N	\N	\N
110	#ADM-269429	71	\N	\N	250000	0	0	250000	transfer	shipping	shopee	2026-02-04 08:37:49.541158+00	Minh Thư	789515460	15NXK	\N	\N	\N	unpaid	\N	\N	\N
111	#ADM-063255	72	\N	\N	280000	0	0	280000	transfer	shipping	Ig mỹ anh	2026-02-04 09:24:23.356142+00	Ig mỹ anh 	0916 520 385	81 Lê Lai , phường Trường Chinh , TP Kon Tum 	\N	\N	\N	unpaid	\N	\N	\N
114	ORD-50311770209638	75	\N	\N	250000	0	20000	270000	banking	shipping	\N	2026-02-04 12:53:57.568925+00	Hà Quyên	0981671406	28 đường B2 . Phước hải ( nhà ngô kỳ nhiên ), Thành phố Nha Trang, Khánh Hòa		\N	\N	unpaid	\N	1548	410103
115	#ADM-893900	76	\N	\N	530000	0	0	530000	transfer	shipping	Ig thu lương	2026-02-04 13:48:14.041962+00	Ig thu lương	0908.603.893	Lương Ngọc Cẩm Thu\nsố nhà 1407, ấp Bình Phú, xã Long Tân , huyện Nhơn Trạch , tỉnh Đồng Nai	\N	\N	\N	unpaid	\N	\N	\N
116	#ADM-097432	77	\N	\N	280000	0	0	280000	transfer	shipping	Ig Lê Thanh Thảo	2026-02-04 18:18:17.544691+00	Ig Lê Thanh Thảo	0933097084	8/28 nguyễn đình khơi, phường4, tân bình, tphcm	\N	\N	\N	unpaid	\N	\N	\N
118	#ADM-829924	79	\N	\N	530000	0	0	530000	transfer	shipping	Ig trà my	2026-02-05 03:23:50.021196+00	 Lê Thị Trà My	 03338407494	140 quốc lộ 13, khu phố ninh thịnh, thị trấn Lộc Ninh, Tỉnh Bình Phước	\N	\N	\N	unpaid	\N	\N	\N
119	#ADM-939096	80	\N	\N	530000	0	0	530000	transfer	shipping	Ig winkzeeee	2026-02-05 03:25:39.19676+00	Ig winkzeeee	0933948272	423 Trường Chinh, Phường Đông Hưng Thuận, HCM	\N	\N	\N	unpaid	\N	\N	\N
120	#ADM-111357	81	\N	\N	530000	0	0	530000	transfer	shipping	Ig trẻ người non stop	2026-02-05 03:45:11.455322+00	Ig trẻ người non stop	0888671434	122/38 Bùi đình tuý,p12, q. Bình thạnh 	\N	\N	\N	unpaid	\N	\N	\N
117	#ADM-745814	78	\N	\N	250000	0	0	250000	transfer	shipping	Ig just C	2026-02-05 03:22:25.947765+00	Ig just C 	0379201403	82 Nguyễn Sơn - Ngọc Lâm - Long Biên - Hà Nội 	\N	\N	\N	unpaid	\N	\N	\N
121	#ADM-201668	82	\N	\N	530000	0	0	530000	transfer	shipping	Ig thanh tam	2026-02-05 04:03:21.789406+00	Ig thanh tam	0347345259	B48/1 ấp Phước Bình, xã Phước Tỉnh, huyện Long Điền, tỉnh BRVT\nPhuoc Tinh, Long Điền, Tinh Ba Ria - Vung Tau,	\N	\N	\N	unpaid	\N	\N	\N
122	#ADM-665529	83	\N	\N	1980000	0	0	1980000	transfer	shipping	Ig phương trinh	2026-02-05 04:44:25.635217+00	Ig phương trinh	0359298912	204/3B Cao Đạt, phường 1, quận 5 	\N	\N	\N	unpaid	\N	\N	\N
123	#ADM-515179	84	\N	\N	880000	0	0	880000	transfer	shipping	Ig hồng ngân	2026-02-05 06:05:15.28651+00	Ig hồng ngân	0779633259	13 xóm vôi p14 q5	\N	\N	\N	unpaid	\N	\N	\N
124	#ADM-550563	85	\N	\N	280000	0	0	280000	transfer	shipping	Ig tdhtran_	2026-02-05 06:05:50.681702+00	Ig tdhtran_	0337552416	1351/9/2 Phan Văn Trị phường 10 Gò Vấp	\N	\N	\N	unpaid	\N	\N	\N
128	ORD-23531770290512	5	\N	\N	280000	0	20000	300000	banking	cancelled	\N	2026-02-05 11:21:52.25591+00	Test	0979911670	15 Nguyễn Xuân Khoát, Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	1456	21509
134	#ADM-783317	5	\N	\N	280000	0	0	280000	transfer	returned	Test	2026-02-05 12:49:43.505331+00	Test	0979911670	15 NXK	\N	\N	\N	unpaid	\N	\N	\N
125	#ADM-725883	86	\N	\N	880000	0	0	880000	transfer	completed	Ig thu vo	2026-02-05 08:22:05.982852+00	Ig thu vo 	0932221092	8 tran nao q2	\N	\N	\N	unpaid	\N	\N	\N
126	#ADM-895272	87	\N	\N	530000	0	0	530000	transfer	completed	Ig xuý	2026-02-05 08:24:55.394751+00	Ig xuý 	0968562187	610 võ văn kiệt phường cầu ông lãnh ạ\n\n	\N	\N	\N	unpaid	\N	\N	\N
127	#ADM-822937	88	\N	\N	280000	0	0	280000	transfer	shipping	Ig phương linh	2026-02-05 10:37:03.070746+00	Ig phương linh	0877979798	Khu phố 10, p tân Biên Biên Hoà Đồng Nai	\N	\N	\N	unpaid	\N	\N	\N
129	#ADM-778103	89	\N	\N	300000	0	0	300000	transfer	shipping	Ig wuenie.gum	2026-02-05 11:26:18.206568+00	Ig wuenie.gum	0949941439	55a/3 kp3 phường tân hoà biên hoà đồng nai 	\N	\N	\N	unpaid	\N	\N	\N
143	#ADM-214455	91	\N	\N	250000	0	0	250000	transfer	shipping	Ig khanhvandoann	2026-02-06 04:13:34.597893+00	Ig khanhvandoann	0937059890	\n\n52 Thành Thái P.12 Q.10	\N	\N	\N	unpaid	\N	\N	\N
130	#ADM-867589	90	\N	\N	250000	0	0	250000	transfer	completed	Ig lan phương	2026-02-05 11:27:47.690145+00	Ig lan phương	0395328548	39 nhất chi mai , tân bình	\N	\N	\N	unpaid	\N	\N	\N
131	#ADM-670234	91	\N	\N	280000	0	0	280000	transfer	shipping	Ig khanhvandoann	2026-02-05 11:57:50.349516+00	Ig khanhvandoann	0937059890	52 Thành Thái P.12 Q.10 	\N	\N	\N	unpaid	\N	\N	\N
132	ORD-49991770293953	92	\N	\N	250000	0	20000	270000	banking	shipping	\N	2026-02-05 12:19:12.91067+00	Phạm Uyên Thy	0858326679	145/1, hẻm 145, quốc lộ 13, Quận Thủ Đức, Hồ Chí Minh	uyenthi6679@gmail.com	\N	\N	unpaid	\N	1463	21803
133	ORD-76141770295315	93	\N	\N	320000	0	20000	340000	banking	shipping	\N	2026-02-05 12:41:55.377881+00	Phạm Hoài Hải Yến	0913612642	122 Ỷ Lan, Thành phố Quy Nhơn, Bình Định	phamhoaihaiyen@gmail.com	\N	\N	unpaid	\N	1662	370113
135	ORD-91881770299473	94	\N	\N	250000	0	20000	270000	banking	shipping	\N	2026-02-05 13:51:13.121597+00	Mai Phan	0911172812	An residence 14 đường số 1 (lý phục man quẹo vô), Quận 7, Hồ Chí Minh	Maiphannp26@gmail.com	\N	\N	unpaid	\N	1449	20701
137	#ADM-178644	71	\N	\N	280000	0	0	280000	transfer	shipping	Ig hân hânn	2026-02-05 14:36:18.754102+00	Ig hân hânn	789515460	15NXK	\N	\N	\N	unpaid	\N	\N	\N
136	#ADM-941453	95	\N	\N	280000	0	0	280000	transfer	shipping	ig nganxiinhiu	2026-02-05 14:15:41.869504+00	ig  nganxiinhiu ( Ngan Pham)	84869726548	Hẻm 240/13 Lê Duẩn, Xã An Phước, Huyện Long Thành, Đồng Nai	\N	\N	\N	unpaid	\N	\N	\N
138	ORD-23641770308185	96	\N	\N	530000	0	20000	550000	banking	shipping	\N	2026-02-05 16:16:25.279819+00	Kiều Trang	0393252767	63 Nguyễn Ngọc Kỳ , Thị xã La Gi, Bình Thuận	nguyenthivuong0733@gmail.com	\N	\N	unpaid	\N	1778	471002
139	#ADM-393898	97	\N	\N	560000	0	0	560000	transfer	shipping	Ig joice.nn_	2026-02-05 18:49:54.016158+00	Ig joice.nn_	0938223711	173/45/36 Khuông Việt, Phú Trung, Tân Phú	\N	\N	\N	unpaid	\N	\N	\N
140	ORD-49341770347153	98	\N	\N	530000	0	20000	550000	banking	shipping	\N	2026-02-06 03:05:52.933821+00	Hồ Thị Kim Tho	0797206844	31 đường số 37 , Quận 2, Hồ Chí Minh	tho.hokimtho01@gmail.com	\N	\N	unpaid	\N	1443	20201
142	ORD-92051770350527	1	\N	\N	280000	0	20000	300000	banking	cancelled	\N	2026-02-06 04:02:07.424667+00	Admin Brown	0900000000	15 Nguyễn Xuân Khoát, Quận Tân Phú, Hồ Chí Minh	brownvn25@gmail.com	\N	\N	unpaid	\N	1456	21509
141	#ADM-995215	99	\N	\N	560000	0	0	560000	transfer	shipping	Ig	2026-02-06 03:53:15.31578+00	🏳️‍🌈	0971464109	Chung cư opal garden	\N	\N	\N	unpaid	\N	\N	\N
144	#ADM-307436	100	\N	\N	320000	0	0	320000	transfer	shipping	Ig ohvielleicht	2026-02-06 04:15:07.530557+00	Ig ohvielleicht 	+84 79 6256618	428 Võ Nguyên Giáp, Khuê Mỹ, Ngũ Hành Sơn, Đà Nẵng 550000	\N	\N	\N	unpaid	\N	\N	\N
145	#ADM-504165	71	\N	\N	280000	0	0	280000	transfer	shipping	Ig vy	2026-02-06 04:18:24.26482+00	Ig vy	789515460	121 cô giang, phường Cầu ông lãnh	\N	\N	\N	unpaid	\N	\N	\N
146	#ADM-497758	101	\N	\N	280000	0	0	280000	transfer	shipping	Ig meii	2026-02-06 06:14:57.87019+00	Ig meii 	0841444661	332/34 độc lậ phú thọ hoà tân phú\n\n	\N	\N	\N	unpaid	\N	\N	\N
147	#ADM-023870	102	\N	\N	250000	0	0	250000	transfer	shipping	Ig thư	2026-02-06 06:40:24.017629+00	Ig thư	0935883228 	148 trần nam trung, hoà xuân, cẩm lệ, đà nẵng 	\N	\N	\N	unpaid	\N	\N	\N
148	#ADM-103489	50	\N	\N	530000	0	0	530000	transfer	shipping	Wind xpress ig	2026-02-06 06:41:43.653975+00	Wind xpress ig	0325267896	Địa chỉ: 375 tân thới hiệp 21 , Tổ 3 ,Kp3 ,quận 12\nW24130 Miki brown	\N	\N	\N	unpaid	\N	\N	\N
149	#ADM-777755	103	\N	\N	1000000	0	0	1000000	transfer	shipping	Ig tiên tiên	2026-02-06 07:42:57.875681+00	Ig tiên tiên	0985037507	02 Nguyễn Lương Bằng - xã Lộc thanh - tp bảo Lộc - lâm đồng \n	\N	\N	\N	unpaid	\N	\N	\N
150	#ADM-708067	104	\N	\N	530000	0	0	530000	transfer	shipping	Ig bích ngọc	2026-02-06 08:15:08.16877+00	Ig bích ngọc 	0905441264	K52/73 Đinh Tiên Hoàng , Đà Nẵng \n	\N	\N	\N	unpaid	\N	\N	\N
151	#ADM-130905	105	\N	\N	280000	0	0	280000	transfer	shipping	hồng đào Ig 🍒R🍒	2026-02-06 10:35:31.056049+00	hồng đào Ig 🍒R🍒	0909089356	147/5 thạch lam tân phú HCM	\N	\N	\N	unpaid	\N	\N	\N
152	#ADM-386015	106	\N	\N	280000	0	0	280000	transfer	shipping	Ig hyhchaah	2026-02-06 13:43:06.123385+00	Ig hyhchaah	0985533618	224A kp5 p1 đường 786 tp Tây Ninh	\N	\N	\N	unpaid	\N	\N	\N
153	#ADM-008640	107	\N	\N	530000	0	0	530000	transfer	shipping	Ig DWF	2026-02-06 15:16:48.765142+00	Ig DWF	0376891811	46-48-50 phạm hồng thái, p. bến thành\n- Tuyên 	\N	\N	\N	unpaid	\N	\N	\N
155	#ADM-522642	109	\N	\N	530000	0	0	530000	transfer	shipping	Ig linh trần	2026-02-07 02:48:42.749184+00	Ig linh trần 	0886339378	hem 420/18a khu 3 phú lợi đại lộ binh duong\n	\N	\N	\N	unpaid	\N	\N	\N
159	ORD-11621770443916	5	\N	\N	250000	0	20000	270000	banking	cancelled	\N	2026-02-07 05:58:35.900981+00	Test Tết	0979911670	15 Nxk, Huyện Ninh Phước, Ninh Thuận	thiemd779@gmail.com	\N	\N	unpaid	\N	1986	450406
156	#ADM-598741	110	\N	\N	530000	0	0	530000	transfer	shipping	Ig ee.sora	2026-02-07 02:49:58.846338+00	Ig ee.sora 	0868774517	\n75 thôn minh tiến,xã hàm minh, huyện Hàm thuận nam tỉnh bình thuận(cũ)\n	\N	\N	\N	unpaid	\N	\N	\N
158	#ADM-850496	112	\N	\N	600000	0	0	600000	transfer	shipping	Ig lê thảo linh	2026-02-07 04:34:10.657541+00	Ig lê thảo linh	0915181172	Vinhome grand paảk s7.5\n\n	\N	\N	\N	unpaid	\N	\N	\N
160	#ADM-950043	113	\N	\N	350000	0	0	350000	transfer	shipping	Ig bchamm_	2026-02-07 11:15:50.145092+00	Ig bchamm_	0357022231	18/17/18 Hương Lộ Ngọc Hiệp, Nha Trang, Khánh Hoà\n	\N	\N	\N	unpaid	\N	\N	\N
161	#ADM-980437	114	\N	\N	250000	0	0	250000	transfer	shipping	Ig 17dasick	2026-02-07 11:16:20.533955+00	Ig 17dasick	0783396444	348A Trường Chinh, phường 13, Tân Bình	\N	\N	\N	unpaid	\N	\N	\N
162	#ADM-017180	115	\N	\N	250000	0	0	250000	transfer	shipping	Ig phương trinh	2026-02-07 11:16:57.278066+00	Ig phương trinh 	0359298912 	204/3B Cao Đạt, phường 1, quận 5 	\N	\N	\N	unpaid	\N	\N	\N
163	#ADM-063216	116	\N	\N	600000	0	0	600000	transfer	shipping	Ig kimm	2026-02-07 11:17:43.309907+00	Ig kimm	0706741315	33 nguyễn hữu thọ tân hưng quận 7\nSunrise city view toà B	\N	\N	\N	unpaid	\N	\N	\N
164	#ADM-168093	117	\N	\N	1160000	0	0	1160000	transfer	shipping	Ig ivy.trieule	2026-02-07 11:19:28.195647+00	Ig ivy.trieule	 0349270422	1534 hùng vương, cam phú, cam ranh khánh hoà\n	\N	\N	\N	unpaid	\N	\N	\N
165	#ADM-250777	118	\N	\N	600000	0	0	600000	transfer	shipping	Ig nguyễn ngọc thiên kiều	2026-02-07 11:20:50.878053+00	Ig nguyễn ngọc thiên kiều 	0988949801	96/3 đường s19, p8, gvap	\N	\N	\N	unpaid	\N	\N	\N
167	#ADM-490633	120	\N	\N	1050000	0	0	1050000	transfer	shipping	The name is Ngan	2026-02-07 11:24:50.726933+00	The name is Ngan 	0906616319 .	 365/19A đường hậu Giang , phường Bình Phú. Quận 6 tphcm . \n 	\N	\N	\N	unpaid	\N	\N	\N
168	#ADM-531189	121	\N	\N	280000	0	0	280000	transfer	shipping	Ig mai quỳnh	2026-02-07 11:25:31.284259+00	Ig mai quỳnh 	0394975445	72-74 Nguyễn Thị Minh Khai, phường 6 quận 3\nCentec Tower	\N	\N	\N	unpaid	\N	\N	\N
169	#ADM-195106	122	\N	\N	280000	0	0	280000	transfer	shipping	Ig như ngọc nguyễn thị	2026-02-07 11:36:35.222478+00	Ig như ngọc nguyễn thị 	0358590047	764 Thọ Hoà, Xuân Thọ, Xuân Lộc, Đồng Nai	\N	\N	\N	unpaid	\N	\N	\N
171	ORD-45041770479165	124	\N	\N	940000	0	20000	960000	banking	shipping	\N	2026-02-07 15:46:04.884702+00	Minh Ngọc	0329588917	Số nhà 102 khu chăn nuôi Hàm Long, Huyện Thủy Nguyên, Hải Phòng	daongoc873@gmail.com	\N	\N	unpaid	\N	1726	30902
172	ORD-45611770480184	125	\N	\N	530000	0	20000	550000	banking	shipping	\N	2026-02-07 16:03:03.742137+00	Bảo Thy	0976281379 	Block A1, Opal riverside, đường số 10, Thành Phố Thủ Đức, Hồ Chí Minh	thyphan1221@gmail.com	\N	\N	unpaid	\N	3695	90741
174	#ADM-919554	127	\N	\N	600000	0	0	600000	transfer	shipping	Ig ngocbaongan.	2026-02-07 18:28:39.652775+00	Ig ngocbaongan.	0838812881	37/6/29 hồ văn nhánh kp8 p5 mỹ tho tiền giang	\N	\N	\N	unpaid	\N	\N	\N
173	#ADM-870328	126	\N	\N	780000	0	0	780000	transfer	shipping	Ig vũ vy	2026-02-07 18:27:50.429146+00	Ig vũ vy 	0904471747 	35 nguyễn đức cảnh, p.thắng lợi, tp.buôn ma thuột	\N	\N	\N	unpaid	\N	\N	\N
175	#ADM-971328	128	\N	\N	680000	0	0	680000	transfer	shipping	Ig hmgtwm	2026-02-07 18:29:31.417648+00	Ig hmgtwm	0827840027	Ba Đình - Nam Ban Lâm Hà - Lâm Đồng	\N	\N	\N	unpaid	\N	\N	\N
176	#ADM-036949	129	\N	\N	530000	0	0	530000	transfer	shipping	Ig bùi yến vy	2026-02-07 18:30:37.043631+00	Ig bùi yến vy	0909923466	BlockA, cc Kingdom101, p diên hồng, q10	\N	\N	\N	unpaid	\N	\N	\N
177	#ADM-075010	130	\N	\N	250000	0	0	250000	transfer	shipping	Ig như quỳnh	2026-02-07 18:31:15.102462+00	Ig như quỳnh	0901567568	K408/H29/18 Hoàng Diệu, Phường Hoà Cường, Tp Đà Nẵng	\N	\N	\N	unpaid	\N	\N	\N
179	#ADM-167886	132	\N	\N	250000	0	0	250000	transfer	shipping	ig kim mỹ hà	2026-02-07 18:32:47.978098+00	ig kim mỹ hà 	0901115018	104/11 huỳnh mẫn đạt p2 q5 tphcm ( sát nhập 104/11 huỳnh mẫn đạt p chợ quán tphcm )	\N	\N	\N	unpaid	\N	\N	\N
178	#ADM-124830	131	\N	\N	1030000	0	0	1030000	transfer	shipping	Ig DN	2026-02-07 18:32:04.939013+00	Ig DN 	0931231295	số nhà 24d3 ngõ 689 lạc long quân, phường tây hồ, hà nội	\N	\N	\N	unpaid	\N	\N	\N
180	#ADM-224726	133	\N	\N	980000	0	0	980000	transfer	shipping	Kol tuyền	2026-02-07 18:33:44.821545+00	Kol tuyền 	0966946346 	778 xô viết nghệ tĩnh phường thạnh mỹ tây quận bình thạnh \n\n	\N	\N	\N	unpaid	\N	\N	\N
181	#ADM-354253	134	\N	\N	280000	0	0	280000	transfer	shipping	Ig lê t. Thu hường	2026-02-08 04:19:14.367039+00	Ig lê t. Thu hường	0784649439	Ấp 5 miễu bà 8 long thọ nhơn trạch đồng nai	\N	\N	\N	unpaid	\N	\N	\N
182	#ADM-472520	135	\N	\N	2510000	0	0	2510000	transfer	shipping	Ig tamikanguyen	2026-02-08 04:21:12.630345+00	Ig tamikanguyen	0901104935	501/19 Phạm văn Chiêu phường 13.Quận Gò vấp\n	\N	\N	\N	unpaid	\N	\N	\N
183	#ADM-350499	136	\N	\N	250000	0	0	250000	transfer	shipping	Ig quỳnh anh	2026-02-08 05:25:50.598883+00	Ig quỳnh anh	0336823079	Số 39 , ql 13, Lộc Thái , Lộc Ninh, Bình Phước	\N	\N	\N	unpaid	\N	\N	\N
185	#ADM-471396	47	\N	\N	700000	0	0	700000	transfer	shipping	Thiện Thảo	2026-02-08 05:27:51.514789+00	Thiện Thảo	0898681865	126 đường 38 Bình Trưng Tây - Thủ Đức	\N	\N	\N	unpaid	\N	\N	\N
184	#ADM-406622	137	\N	\N	320000	0	0	320000	transfer	shipping	Ig meehgoxcutie_	2026-02-08 05:26:46.718724+00	Ig meehgoxcutie_	0979768986	CityHouse - CD Apartment\n339/24B Đ. Lê Văn Sỹ, Phường 12, Quận 3, Hồ Chí Minh 700000, Vietnam 	\N	\N	\N	unpaid	\N	\N	\N
186	ORD-79171770535486	138	\N	\N	850000	0	20000	870000	banking	shipping	\N	2026-02-08 07:24:46.258204+00	Vũ Khánh Huyền 	0382829311	Ngõ 57 K40 khu 2 phường quảng yên, Thị xã Quảng Yên, Quảng Ninh		\N	\N	unpaid	\N	2066	171108
187	#ADM-581023	139	\N	\N	600000	0	0	600000	transfer	shipping	Ig vie	2026-02-08 09:06:21.152468+00	Ig vie	0779078617	152 Lê Quang Định, Bình Thạnh\n	\N	\N	\N	unpaid	\N	\N	\N
188	#ADM-614686	140	\N	\N	280000	0	0	280000	transfer	shipping	Ig nnphiephe	2026-02-08 09:06:54.786005+00	Ig nnphiephe 	0335856599 	Chung cư CT9 Vĩnh Điềm Trung , Phường Vĩnh Hiệp tp Nha Trang \n	\N	\N	\N	unpaid	\N	\N	\N
189	#ADM-653746	141	\N	\N	680000	0	0	680000	transfer	shipping	Ig jeff	2026-02-08 09:07:33.848518+00	Ig jeff	0938780757	Linh Cung \nEco Green Block H, 39B Nguyễn Văn Linh, Tân Thuận Tây, Quận 7\n	\N	\N	\N	unpaid	\N	\N	\N
190	#ADM-713775	142	\N	\N	1530000	0	0	1530000	transfer	shipping	Ig Thảo nguyên	2026-02-08 09:08:33.882352+00	Thảo nguyên	0935891747	Saigon south residence 113a Nguyễn Hữu Thọ, Phước Kiển, Nhà Bè\n	\N	\N	\N	unpaid	\N	\N	\N
166	#ADM-402459	119	\N	\N	530000	0	0	530000	transfer	returned	Ig kim chi	2026-02-07 11:23:22.571748+00	Ig kim chi 	0914019900	19 bàu cát4-ph tân bình -tân binh	\N	\N	\N	unpaid	\N	\N	\N
154	#ADM-380783	108	\N	\N	530000	0	0	530000	transfer	shipping	Ig PHUONG UYEN	2026-02-07 02:46:20.886975+00	Ig PHUONG UYEN	0948434814	214 ni sư huỳnh liên p10 quận tb	\N	\N	\N	unpaid	\N	\N	\N
157	#ADM-371376	111	\N	\N	560000	0	0	560000	transfer	shipping	Ig y0310_	2026-02-07 04:09:31.47746+00	Ig y0310_	0899290899	Số nhà 03 (cạnh mẫu giáo xóm đồng), Phường Phong Hải, Thị Xã Quảng Yên, Quảng Ninh\n	\N	\N	\N	unpaid	\N	\N	\N
170	ORD-21601770473914	123	\N	\N	530000	0	20000	550000	banking	shipping	\N	2026-02-07 14:18:34.253249+00	Thanh Ngân	0386946804	55/4b trương đình hội p16 q8, Quận 8, Hồ Chí Minh	bcee.stal63@gmail.com	\N	\N	unpaid	\N	1450	20816
201	ORD-17111770579827	152	\N	\N	320000	0	20000	340000	banking	shipping	\N	2026-02-08 19:43:47.118528+00	Nguyễn Ngọc Minh Thư	0918441864	21B.Nguyễn Thị Thập,Quận 7,phường Tân Phú,TPHCM, Quận 7, Hồ Chí Minh	minhthu010720@gmail.com	\N	\N	unpaid	\N	1449	20707
191	#ADM-480836	143	\N	\N	250000	0	0	250000	transfer	shipping	Ig NGỌC MAI	2026-02-08 09:21:20.940197+00	Ig NGỌC MAI	0835772142	ố 33, lô D, TTTM BÌNH MINH - K1, P cái vồn, TX Bình minh, Vĩnh Long 	\N	\N	\N	unpaid	\N	\N	\N
192	#ADM-525772	58	\N	\N	250000	0	0	250000	transfer	shipping	ig	2026-02-08 09:22:05.897243+00	Giang TKTQ	0918974705	tân kỳ tân quý	\N	\N	\N	unpaid	\N	\N	\N
193	ORD-21721770561671	144	\N	\N	600000	0	20000	620000	banking	shipping	\N	2026-02-08 14:41:11.2406+00	Ngọc trâm	0342617409	94/3 ấp 3, Huyện Bình Đại, Bến Tre		\N	\N	unpaid	\N	1895	560602
194	#ADM-306293	145	\N	\N	1270000	0	0	1270000	transfer	shipping	Ig bow bangkok	2026-02-08 15:08:26.400932+00	Ig bow bangkok	0369166.222 	163 Trương Thị Hoa, phường Tân Thới Hiệp, Quận 12, thành phố Hồ Chí Minh\n ( Người Nhận BN2705)	\N	\N	\N	unpaid	\N	\N	\N
195	#ADM-344122	146	\N	\N	530000	0	0	530000	transfer	shipping	Ig an thuỳ	2026-02-08 15:09:04.224343+00	 Ig an thuỳ 	0946698781	Ngân Hàng Vib Dĩ An, \nSố 2 Đường M, Khu Trung Tâm Hành Chính, Phường Dĩ An, Thành Phố Dĩ An, Bình Dương\n\nTrần Thuỳ An	\N	\N	\N	unpaid	\N	\N	\N
196	#ADM-409078	147	\N	\N	270000	0	0	270000	transfer	shipping	Ig quynh anh maria	2026-02-08 15:10:09.191844+00	Ig quynh anh maria	0369514710	Xóm Miếu, cụm 7, Vĩnh ninh , đại Thanh, Hà Nội\nTên: Nguyễn Thị Thu Trang	\N	\N	\N	unpaid	\N	\N	\N
197	#ADM-448036	148	\N	\N	250000	0	0	250000	transfer	shipping	Ig thu thuỷ	2026-02-08 15:10:48.141107+00	Ig thu thuỷ 	0334947873	\nDc sn 5c hẻm 43/99/7 trung kính, trung hoà, cầu giấy Hà Nội	\N	\N	\N	unpaid	\N	\N	\N
198	#ADM-494871	149	\N	\N	600000	0	0	600000	transfer	shipping	Ig immatcha_cha	2026-02-08 15:11:34.973831+00	Ig immatcha_cha	0343178558	451 Xuân Đỉnh , Hà Nội	\N	\N	\N	unpaid	\N	\N	\N
199	#ADM-171555	150	\N	\N	280000	0	0	280000	transfer	shipping	Ig KHIMY	2026-02-08 15:39:31.976044+00	Ig KHIMY 	0908444086	Lô D cc ecogreen ,nguyễn văn linh ,q7\n	\N	\N	\N	unpaid	\N	\N	\N
200	ORD-65901770572633	151	\N	\N	280000	0	20000	300000	banking	shipping	\N	2026-02-08 17:43:53.407474+00	Linh Trang	0823236968	81 Thạch Thị Thanh, Quận 1, Hồ Chí Minh	abc@gmail.com	\N	\N	unpaid	\N	1442	20110
204	#ADM-289408	5	\N	\N	280000	0	0	280000	transfer	cancelled	[ĐÃ THANH TOÁN]	2026-02-09 02:31:30.063323+00	Test	0979911670	15 NXK	\N	\N	\N	unpaid	\N	\N	\N
203	#ADM-246216	153	\N	\N	280000	0	0	280000	transfer	cancelled	[ĐÃ THANH TOÁN]	2026-02-09 02:30:46.731155+00	Test 	0979116700	15 NXK	\N	\N	\N	unpaid	\N	\N	\N
202	ORD-21671770604194	5	\N	\N	280000	0	20000	300000	banking	returned	\N	2026-02-09 02:29:54.346636+00	Test 	0979911670	15 NXK, Quận Tân Phú, Hồ Chí Minh	thiemd779@gmail.com	\N	\N	unpaid	\N	1456	21509
205	#ADM-141679	71	\N	\N	250000	0	0	250000	transfer	shipping	ien.00 [ĐÃ THANH TOÁN]	2026-02-09 03:35:41.804035+00	ien.00	789515460	15 NXK khách ghé lấy	\N	\N	\N	unpaid	\N	\N	\N
206	#ADM-185130	154	\N	\N	630000	0	0	630000	transfer	shipping	Ig jessi.cameronj [ĐÃ THANH TOÁN]	2026-02-09 03:36:25.235536+00	Ig jessi.cameronj	0702624572	102/2 võ trứ nha trang , khánh hoà 	\N	\N	\N	unpaid	\N	\N	\N
207	#ADM-255802	155	\N	\N	750000	0	0	750000	transfer	shipping	Honeyfai_ [ĐÃ THANH TOÁN]	2026-02-09 03:37:35.920963+00	Honeyfai_	0818999538   	M Village Ho Bieu Chanh 7 Hồ Biểu Chánh, Phường 12, Phú Nhuận, Thành phố Hồ Chí Minh, Vietnam  	\N	\N	\N	unpaid	\N	\N	\N
208	#ADM-290522	156	\N	\N	280000	0	0	280000	transfer	shipping	Ig phạm ngọc tuyền [ĐÃ THANH TOÁN]	2026-02-09 03:38:10.627367+00	Ig phạm ngọc tuyền	0358137039	Nhà 8a hẻm 35 đường cmt8 kp1 phường 3 tây ninh	\N	\N	\N	unpaid	\N	\N	\N
212	ORD-85311770615659	5	\N	\N	250000	0	20000	270000	banking	cancelled	\N	2026-02-09 05:40:58.706937+00	Đởm Triết	0979911670	15 NXK, Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	1456	21508
209	#ADM-500720	157	\N	\N	250000	0	0	250000	transfer	shipping	ig Vi Nguyễn [ĐÃ THANH TOÁN]	2026-02-09 05:05:00.86792+00	ig Vi Nguyễn	0969999346 	Chung Cư CT6 Vĩnh Điềm Trung Nha Trang, Tòa Nhà CT6, Đường B3,\nPhường Tây Nha Trang, Khánh Hòa	\N	\N	\N	unpaid	\N	\N	\N
210	#ADM-592064	71	\N	\N	750000	0	0	750000	transfer	shipping	Ig wie [ĐÃ THANH TOÁN]	2026-02-09 05:06:32.199223+00	Ig wie	789515460	17 hoà hưng phường 12 quận 10	\N	\N	\N	unpaid	\N	\N	\N
211	#ADM-715344	71	\N	\N	850000	0	0	850000	transfer	shipping	Ig zina  [ĐÃ THANH TOÁN]	2026-02-09 05:08:35.455899+00	Ig zina 	789515460	Quận 7. Lê văn lương	\N	\N	\N	unpaid	\N	\N	\N
213	#ADM-755605	71	\N	\N	350000	0	0	350000	transfer	shipping	Ig wie  [ĐÃ THANH TOÁN]	2026-02-09 06:15:55.763292+00	Ig wie 	789515460	15NXK KHÁCH GHÉ LẤY	\N	\N	\N	unpaid	\N	\N	\N
214	#ADM-789222	158	\N	\N	250000	0	0	250000	transfer	shipping	Ig zoe  [ĐÃ THANH TOÁN]	2026-02-09 06:16:29.325734+00	Ig zoe 	0932086042	\n908/3 đoàn văn bơ p18 q4	\N	\N	\N	unpaid	\N	\N	\N
215	#ADM-632227	159	\N	\N	600000	0	0	600000	transfer	shipping	Ig đặng quỳnh [ĐÃ THANH TOÁN]	2026-02-09 06:30:32.332419+00	Ig đặng quỳnh	0706772763	atino 73 nguyễn việt hồng , phường an phú , ninh kiều cần thơ\n	\N	\N	\N	unpaid	\N	\N	\N
220	#ADM-099424	163	\N	\N	250000	0	0	250000	transfer	shipping	Ig nguyen bich ngoc [ĐÃ THANH TOÁN]	2026-02-09 09:58:19.535975+00	Ig nguyen bich ngoc	0392951733	15 đường 37, phường hiệp bình phước , khu đô thị vạn phúc ,\n\n	\N	\N	\N	unpaid	\N	\N	\N
218	#ADM-058834	161	\N	\N	280000	0	0	280000	transfer	shipping	ig  [ĐÃ THANH TOÁN]	2026-02-09 09:57:38.951196+00	Mi Mi	0796287600	13 bình thới p11 quận 11 	\N	\N	\N	unpaid	\N	\N	\N
217	#ADM-021568	103	\N	\N	600000	0	0	600000	transfer	shipping	Ig tiên tiên  [ĐÃ THANH TOÁN]	2026-02-09 09:57:01.695754+00	Ig tiên tiên 	0985037507	88/4 Đoàn Thị Điểm - xã Lộc thanh - tp bảo Lộc	\N	\N	\N	unpaid	\N	\N	\N
216	#ADM-022483	160	\N	\N	530000	0	0	530000	transfer	shipping	Ig tran tran  [ĐÃ THANH TOÁN]	2026-02-09 07:43:42.597559+00	Ig tran tran 	0767629111	 105/2 Phạm Phú Thứ P Bình Tiên (p3 q6)	\N	\N	\N	unpaid	\N	\N	\N
219	#ADM-099257	162	\N	\N	250000	0	0	250000	transfer	returned	Ig nguyen bich ngoc [ĐÃ THANH TOÁN]	2026-02-09 09:58:19.367887+00	Ig nguyen bich ngoc	0392951733	15 đường 37, phường hiệp bình phước , khu đô thị vạn phúc ,\n\n	\N	\N	\N	unpaid	\N	\N	\N
223	#ADM-445109	166	\N	\N	350000	0	0	350000	transfer	shipping	Ig võ thảo ngân  [ĐÃ THANH TOÁN]	2026-02-09 13:57:25.220578+00	Ig võ thảo ngân 	0795407876	khu dân cư ấp phú thuận xã phú thịnh huyện tam bình tỉnh vĩnh long\n	\N	\N	\N	unpaid	\N	\N	\N
222	#ADM-407207	165	\N	\N	560000	0	0	560000	transfer	shipping	Kol hannal [ĐÃ THANH TOÁN]	2026-02-09 13:56:47.34857+00	Kol hannal	0366986065	Masteri thảo điền, t3, q2	\N	\N	\N	unpaid	\N	\N	\N
221	#ADM-357022	164	\N	\N	250000	0	0	250000	transfer	shipping	ig Cam cam [ĐÃ THANH TOÁN]	2026-02-09 13:55:57.164651+00	ig Cam cam	070 3624481	hocmon	\N	\N	\N	unpaid	\N	\N	\N
225	#ADM-863065	168	\N	\N	350000	0	0	350000	transfer	shipping	Ig hathanhthuylinh [ĐÃ THANH TOÁN]	2026-02-09 15:27:43.210588+00	Ig hathanhthuylinh	0902904947	\n47/17a bùi công trừng nhị bình hóc môn	\N	\N	\N	unpaid	\N	\N	\N
228	#ADM-853617	170	\N	\N	280000	0	0	280000	transfer	shipping	Ig ulsuove_ [ĐÃ THANH TOÁN]	2026-02-09 16:50:53.728799+00	Ig ulsuove_	0364789984 	212/3b phạm văn chiêu phường 9 gò vấp	\N	\N	\N	unpaid	\N	\N	\N
224	ORD-77001770646817	167	\N	\N	600000	0	20000	620000	banking	shipping	\N	2026-02-09 14:20:16.867056+00	Đào Lý Thảo Vy	0705992224	52/12 đường số 17, Quận 7, Hồ Chí Minh	vydaolythao@gmail.com	\N	\N	unpaid	\N	1449	20710
226	#ADM-258187	129	\N	\N	400000	0	0	400000	transfer	shipping	Ig bùi yến vy [ĐÃ THANH TOÁN]	2026-02-09 15:50:58.318214+00	Ig bùi yến vy	0909923466	BlockA, cc Kingdom101, p diên hồng, q10\n	\N	\N	\N	unpaid	\N	\N	\N
227	#ADM-860680	169	\N	\N	280000	0	0	280000	transfer	shipping	Ig themtradau [ĐÃ THANH TOÁN]	2026-02-09 16:34:20.804593+00	Ig themtradau	0934142781	15NXK khách ghé lấy	\N	\N	\N	unpaid	\N	\N	\N
229	#ADM-515535	161	\N	\N	630000	0	0	630000	transfer	shipping	Ig sấm [ĐÃ THANH TOÁN]	2026-02-09 17:35:15.661936+00	Ig sấm	0796287600	13 bình thới quận 1	\N	\N	\N	unpaid	\N	\N	\N
230	#ADM-350224	171	\N	\N	350000	0	0	350000	transfer	shipping	Maika  [ĐÃ THANH TOÁN]	2026-02-10 03:15:50.333977+00	Maika 	0906777794	50 đường số 3. P an lạc A. \nQuận bình tân	\N	\N	\N	unpaid	\N	\N	\N
231	#ADM-424641	71	\N	\N	250000	0	0	250000	transfer	shipping	JANNIE [ĐÃ THANH TOÁN]	2026-02-10 03:17:04.795688+00	JANNIE	789515460	15 NXK 	\N	\N	\N	unpaid	\N	\N	\N
232	#ADM-356533	172	\N	\N	780000	0	0	780000	transfer	shipping	Ig mita.lam [ĐÃ THANH TOÁN]	2026-02-10 03:49:16.647519+00	Ig mita.lam	0838081828	7A Hải Thượng Lãn Ông - phường Rạch Sỏi - TP Rạch Giá - Kiên Giang\nTrang 0838081828 ạ	\N	\N	\N	unpaid	\N	\N	\N
233	#ADM-826405	173	\N	\N	500000	0	0	500000	transfer	shipping	Ig lâm thị mỹ hảo [ĐÃ THANH TOÁN]	2026-02-10 06:27:06.54033+00	Ig lâm thị mỹ hảo	0384753595	29 trần quang diệu, phường 13, quận 3	\N	\N	\N	unpaid	\N	\N	\N
234	#ADM-860218	71	\N	\N	280000	0	0	280000	transfer	shipping	Ig LTB  [ĐÃ THANH TOÁN]	2026-02-10 06:27:40.336912+00	Ig LTB 	789515460	15 NXK\n	\N	\N	\N	unpaid	\N	\N	\N
235	#ADM-894715	71	\N	\N	350000	0	0	350000	transfer	shipping	Ig jackie  [ĐÃ THANH TOÁN]	2026-02-10 06:28:14.831126+00	Ig jackie 	789515460	\nHai bà trưng q3	\N	\N	\N	unpaid	\N	\N	\N
236	#ADM-938647	174	\N	\N	750000	0	0	750000	transfer	shipping	Ig hoàng lan  [ĐÃ THANH TOÁN]	2026-02-10 06:28:58.759184+00	Ig hoàng lan 	0931539768	30 Phạm Văn Đồng Khu Cầu Xéo xã long thành đồng nai \n	\N	\N	\N	unpaid	\N	\N	\N
237	#ADM-892447	175	\N	\N	390000	0	0	390000	transfer	shipping	Ig thanh truc huynh  [ĐÃ THANH TOÁN]	2026-02-10 07:51:32.569104+00	Ig thanh truc huynh 	086 5767578 	T08-05 The Manhattan, Vinhome Grand Park, Phường Long Bình, TP Thủ Đức	\N	\N	\N	unpaid	\N	\N	\N
238	#ADM-067304	176	\N	\N	350000	0	0	350000	transfer	shipping	ig _princesshappiii [ĐÃ THANH TOÁN]	2026-02-10 08:44:27.406754+00	ig _princesshappiii	0786968512	112/114/9 nguyễn thị minh khai quận ninh kiều thành phố cần thơ	\N	\N	\N	unpaid	\N	\N	\N
239	ORD-55501770719260	177	\N	\N	630000	0	20000	650000	banking	shipping	\N	2026-02-10 10:27:40.277133+00	Ngọc Nữ	0933850356	27/29 Điện Biên Phủ, Quận Bình Thạnh, Hồ Chí Minh	glamwithnu@gmail.com	\N	\N	unpaid	\N	1462	21611
246	#ADM-069882	182	\N	\N	250000	0	0	250000	transfer	shipping	Ig kittmy.t [ĐÃ THANH TOÁN]	2026-02-11 04:27:49.981918+00	Ig kittmy.t	890515460	50/29 nguyễn đình chiểu p4 quận phú nhuận 	\N	\N	\N	unpaid	\N	\N	\N
242	ORD-86671770730296	5	\N	\N	280000	0	20000	300000	banking	cancelled	\N	2026-02-10 13:31:35.722048+00	Test	0979911670	15 NXK, Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	1456	21509
241	#ADM-137147	178	\N	\N	530000	0	0	530000	transfer	shipping	Ig hien le [ĐÃ THANH TOÁN]	2026-02-10 11:15:37.257805+00	Ig hien le	0969813416	26 Lý Tự Trọng, P. Bến Nghé, TP HCM\n	\N	\N	\N	unpaid	\N	\N	\N
243	#ADM-814691	179	\N	\N	430000	0	0	430000	transfer	shipping	Ig kiwi1989 [ĐÃ THANH TOÁN]	2026-02-10 15:03:34.784574+00	Ig kiwi1989	0366286418	63-65A11, Khu phố 11, Nguyễn Văn Tiên, Phường Tân Phong, Tp. Biên Hoà, Tỉnh Đồng Nai.	\N	\N	\N	unpaid	\N	\N	\N
244	#ADM-919989	180	\N	\N	1200000	0	0	1200000	transfer	shipping	Ig mochisyx [ĐÃ THANH TOÁN]	2026-02-10 15:05:20.082758+00	Ig mochisyx	0899903807	204b6/5/2 Nguyễn Văn Hưởng, Thảo Điền	\N	\N	\N	unpaid	\N	\N	\N
245	#ADM-651036	181	\N	\N	750000	0	0	750000	transfer	shipping	ig Quỳnh Như [ĐÃ THANH TOÁN]	2026-02-10 17:47:31.135503+00	 Quỳnh Như	0978596565 	283 bến vân đồn q4 	\N	\N	\N	unpaid	\N	\N	\N
240	#ADM-097303	71	\N	\N	530000	0	0	530000	transfer	returned	ig tudocuavii [ĐÃ THANH TOÁN]	2026-02-10 10:58:17.461822+00	ig tudocuavii	789515460	Trần Coa vân q3	\N	\N	\N	unpaid	\N	\N	\N
248	#ADM-257239	183	\N	\N	350000	0	0	350000	transfer	shipping	ig honeyfai_ [ĐÃ THANH TOÁN]	2026-02-11 05:37:37.353863+00	ig honeyfai_	0818999538	M village 7 Hồ Biểu Chánh p12 Phú Nhuận	\N	\N	\N	unpaid	\N	\N	\N
247	#ADM-174168	71	\N	\N	530000	0	0	530000	transfer	shipping	ig tr.trang1837 [ĐÃ THANH TOÁN]	2026-02-11 05:36:14.316582+00	ig tr.trang1837	789515460	107 Trần huy liệu p12 quận phú nhuận	\N	\N	\N	unpaid	\N	\N	\N
249	#ADM-326080	184	\N	\N	880000	0	0	880000	transfer	shipping	Ig Hiền Phạm [ĐÃ THANH TOÁN]	2026-02-11 07:18:46.174007+00	Ig Hiền Phạm	0977415509	431 lê văn sỹ quận 3	\N	\N	\N	unpaid	\N	\N	\N
250	#ADM-234095	134	\N	\N	250000	0	0	250000	transfer	cancelled	Ig lê t.thu hường [ĐÃ THANH TOÁN]	2026-02-11 07:33:54.236652+00	Ig lê t.thu hường	0784649439	Ấp 5 miễu bà 8 long thọ nhơn trạch đồng nai	\N	\N	\N	unpaid	\N	\N	\N
251	#ADM-234408	134	\N	\N	250000	0	0	250000	transfer	shipping	Ig lê t.thu hường [ĐÃ THANH TOÁN]	2026-02-11 07:33:54.499761+00	Ig lê t.thu hường	0784649439	Ấp 5 miễu bà 8 long thọ nhơn trạch đồng nai	\N	\N	\N	unpaid	\N	\N	\N
253	#ADM-948160	186	\N	\N	560000	0	0	560000	transfer	shipping	ig hanna_owo2u [ĐÃ THANH TOÁN]	2026-02-11 08:52:28.293158+00	ig hanna_owo2u	0789989206	42/2L ap tien lan ba diem hocmon 	\N	\N	\N	unpaid	\N	\N	\N
252	#ADM-782933	185	\N	\N	350000	0	0	350000	transfer	shipping	ig vivannnguyen90 [ĐÃ THANH TOÁN]	2026-02-11 08:49:43.048072+00	ig vivannnguyen90	0933182823	1065 lò góm p7 quận 6	\N	\N	\N	unpaid	\N	\N	\N
254	#ADM-697052	187	\N	\N	600000	0	0	600000	transfer	shipping	ig nguyễn khánh hà [ĐÃ THANH TOÁN]	2026-02-11 12:41:37.190296+00	ig nguyễn khánh hà	0867470512	63 đường số 79 tân quy quận 7	\N	\N	\N	unpaid	\N	\N	\N
255	#ADM-798737	188	\N	\N	600000	0	0	600000	transfer	shipping	ig mai le [ĐÃ THANH TOÁN]	2026-02-11 12:43:18.8697+00	ig mai le	0901360708	chung cư rivegate quận 4	\N	\N	\N	unpaid	\N	\N	\N
256	#ADM-151652	189	\N	\N	940000	0	0	940000	transfer	shipping	ig Kim [ĐÃ THANH TOÁN]	2026-02-11 12:49:11.803553+00	ig Kim	0389012992	2 tôn đức thắng vinhome golden river aqua 3, bến nghé	\N	\N	\N	unpaid	\N	\N	\N
257	#ADM-495437	190	\N	\N	2190000	0	0	2190000	transfer	shipping	ig Na Phea [ĐÃ THANH TOÁN]	2026-02-11 13:28:15.55213+00	ig Na Phea	093282796	Phnom penh city,  Cambodia	\N	\N	\N	unpaid	\N	\N	\N
258	#ADM-141755	71	\N	\N	600000	0	0	600000	transfer	shipping	ig em quỳnh [ĐÃ THANH TOÁN]	2026-02-11 15:52:21.882832+00	ig em quỳnh	789515460	96C võ thị sau phường tân định quận 1	\N	\N	\N	unpaid	\N	\N	\N
259	#ADM-264068	191	\N	\N	250000	0	0	250000	transfer	shipping	ig nhu nguyen [ĐÃ THANH TOÁN]	2026-02-11 15:54:24.201995+00	ig nhu nguyen	0865673495	44 đường sô 7 khu đô thị an phú an khánh phường an phú tp thủ đức	\N	\N	\N	unpaid	\N	\N	\N
260	#ADM-727874	192	\N	\N	630000	0	0	630000	transfer	cancelled	ig dương vi [ĐÃ THANH TOÁN]	2026-02-11 17:08:47.979832+00	ig dương vi	0939688638	75 đường số 26a quận 6	\N	\N	\N	unpaid	\N	\N	\N
263	#ADM-067528	71	\N	\N	280000	0	0	280000	transfer	shipping	ig ellie [ĐÃ THANH TOÁN]	2026-02-11 17:31:08.024593+00	ig ellie	789515460	emilyy Spa Thủ Đức	\N	\N	\N	unpaid	\N	\N	\N
262	#ADM-430423	193	\N	\N	350000	0	0	350000	transfer	shipping	ig hằng [ĐÃ THANH TOÁN]	2026-02-11 17:20:30.538106+00	ig hằng	0987030742	Tiệm My nail, só 3 tân thới nhất 1 phường đông hưng thuận bà điểm hocmon	\N	\N	\N	unpaid	\N	\N	\N
261	#ADM-348290	192	\N	\N	780000	0	0	780000	transfer	shipping	ig dương vi [ĐÃ THANH TOÁN]	2026-02-11 17:19:08.431698+00	ig dương vi	0939688638	75 đường số 26a quận 6	\N	\N	\N	unpaid	\N	\N	\N
264	#ADM-553281	71	\N	\N	250000	0	0	250000	transfer	shipping	ig mỹ phương [ĐÃ THANH TOÁN]	2026-02-11 17:39:13.740667+00	ig mỹ phương	789515460	27N đường 32A p10 quận 6	\N	\N	\N	unpaid	\N	\N	\N
265	#ADM-830562	71	\N	\N	280000	0	0	280000	transfer	shipping	Ig Meii [ĐÃ THANH TOÁN]	2026-02-12 14:00:31.013426+00	Ig Meii	789515460	Độc Lập	\N	\N	\N	unpaid	\N	\N	\N
266	#ADM-963078	3	\N	\N	350000	0	0	350000	transfer	shipping	ig kiki [ĐÃ THANH TOÁN]	2026-02-12 16:32:43.517636+00	ig kiki	0708083054	214/C45 nguễn trãi phường nguyễn cư trinh quận 1	\N	\N	\N	unpaid	\N	\N	\N
267	#ADM-291718	194	\N	\N	750000	0	0	750000	transfer	shipping	Ig thu diễm [ĐÃ THANH TOÁN]	2026-02-12 17:44:51.809611+00	Ig thu diễm	0934511930	17-bt7 khu đô thị Văn Phú, Phú La, Hà Đông, HN	\N	\N	\N	unpaid	\N	\N	\N
268	#ADM-931961	71	\N	\N	220000	0	0	220000	transfer	shipping	Ig mwyuht.ah  [ĐÃ THANH TOÁN]	2026-02-13 04:12:12.408863+00	Ig mwyuht.ah 	789515460	227/8 điện biên phủ bình thạnh	\N	\N	\N	unpaid	\N	\N	\N
271	ORD-74781771695530	197	\N	\N	440000	0	20000	460000	banking	shipping	\N	2026-02-21 17:38:49.853472+00	Trần Triệu Mai Phương	0964618034	20, ngách 8, ngõ 1 Đình Thôn, Quận Nam Từ Liêm, Hà Nội	trantrieu1302@gmail.com	\N	\N	unpaid	\N	3440	13004
274	#ADM-456019	200	\N	\N	750000	0	0	750000	transfer	shipping	Ig katp9re [ĐÃ THANH TOÁN]	2026-02-24 14:14:16.158624+00	Ig katp9re	0838925459	 Địa chỉ: 128/39, Đường Phạm Văn Hai, Phường 3, Quận Tân Bình, TP. Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N
270	ORD-77981771660933	196	\N	\N	280000	0	20000	300000	banking	shipping	\N	2026-02-21 08:02:13.363686+00	Thuý An 	0868107862	13/20b tạ quang bửu , Quận 8, Hồ Chí Minh	nguyenthithuyan923@gmail.con	\N	\N	unpaid	\N	1450	20804
275	#ADM-589785	201	\N	\N	1400000	0	0	1400000	transfer	shipping	Ig trish pham [ĐÃ THANH TOÁN]	2026-02-24 14:16:29.900779+00	Ig trish pham	0765551104 	399 Hai Ba Trưng quận 3	\N	\N	\N	unpaid	\N	\N	\N
276	#ADM-798769	55	\N	\N	350000	0	0	350000	transfer	shipping	Ig KANYARAT  [ĐÃ THANH TOÁN]	2026-02-24 14:19:58.885412+00	Ig KANYARAT 	0369166.222	163 Trương Thị Hoa, phường Tân Thới Hiệp, Quận 12, thành phố Hồ Chí Minh\n sdt : 0369166.222 ( Người Nhận BN2705)	\N	\N	\N	unpaid	\N	\N	\N
277	#ADM-961183	202	\N	\N	400000	0	0	400000	transfer	shipping	Ig donfetch  [ĐÃ THANH TOÁN]	2026-02-24 14:22:41.295115+00	Ig donfetch 	+84 779 805443	\nAddress : Indochine Ben Than Hotel and Apartments , 30 Lưu Văn Lang, Phường Bến Thành, Quận 1, Thành phố Hồ Chí Minh 700000, Vietnam\n\nNo.hp: +84 779 805443\n(can zalo)\n\nNotes: Xin vui lòng gửi ở lễ tân khách sạn	\N	\N	\N	unpaid	\N	\N	\N
278	#ADM-077964	203	\N	\N	350000	0	0	350000	transfer	shipping	Ig bí nhe  [ĐÃ THANH TOÁN]	2026-02-24 14:24:38.095322+00	Ig bí nhe 	0944294068	202/51 phạm văn hai p5 qtan bình \n	\N	\N	\N	unpaid	\N	\N	\N
269	ORD-16151771633927	195	\N	\N	250000	0	20000	270000	banking	shipping	\N	2026-02-21 00:32:07.49585+00	Minh nguyệt	0987569836	Số 79 ngõ 266 phố đội cấn, Quận Ba Đình, Hà Nội	meomun2001@gmail.com	\N	\N	unpaid	\N	1484	1A0101
272	ORD-14901771788091	198	\N	\N	280000	0	20000	300000	banking	shipping	\N	2026-02-22 19:21:30.878964+00	Vy Vo	0399323601	315 Nguyễn Sơn, Quận Tân Phú, Hồ Chí Minh	xmberv@gmail.com	\N	\N	unpaid	\N	1456	21503
273	ORD-60441771913750	199	\N	\N	350000	0	20000	370000	banking	shipping	\N	2026-02-24 06:15:49.702454+00	Trần M Phương	0786797999	226 Lê Quang Định, Quận Bình Thạnh, Hồ Chí Minh	mingphuong.29@gmail.com	\N	\N	unpaid	\N	1462	21610
280	#ADM-033994	205	\N	\N	280000	0	0	280000	transfer	shipping	Ig cẩm nhung  [ĐÃ THANH TOÁN]	2026-02-25 04:50:34.08299+00	Ig cẩm nhung 	0775815411	 45 đào duy anh, phường quang trung, tp quy nhơn, tỉnh bình định	\N	\N	\N	unpaid	\N	\N	\N
281	#ADM-080919	206	\N	\N	250000	0	0	250000	transfer	shipping	Ig vyctorilane [ĐÃ THANH TOÁN]	2026-02-25 04:51:21.002159+00	Ig vyctorilane	0962409277 	91 Hàm Nghi, p.Ngô Mây, tp Quy Nhơn, Bình Định\n	\N	\N	\N	unpaid	\N	\N	\N
282	#ADM-116184	207	\N	\N	250000	0	0	250000	transfer	shipping	Ig thuy hang  [ĐÃ THANH TOÁN]	2026-02-25 04:51:56.310424+00	Ig thuy hang 	0975820878	3/70/Đồng Hòa/Kiến An/TP Hải Phòng	\N	\N	\N	unpaid	\N	\N	\N
283	#ADM-157653	208	\N	\N	280000	0	0	280000	transfer	shipping	Ig nunu [ĐÃ THANH TOÁN]	2026-02-25 04:52:37.777645+00	Ig nunu	0899326041	 453/70/52 đường Lê Văn Khương, Khu phố 5, phường Hiệp Thành, Quận 12, Thành phố Hồ Chí Minh, Việt Nam	\N	\N	\N	unpaid	\N	\N	\N
284	#ADM-204903	209	\N	\N	400000	0	0	400000	transfer	shipping	Ig joiee_devivre [ĐÃ THANH TOÁN]	2026-02-25 04:53:24.988609+00	Ig joiee_devivre	0818887574	Số 16 Ngõ 674 đg Nguyễn Văn Cừ Long biên Hà Nội (sau sát nhập: đg Ng Văn Cừ, phường Bồ Đề Hà Nội)	\N	\N	\N	unpaid	\N	\N	\N
285	#ADM-248393	210	\N	\N	250000	0	0	250000	transfer	shipping	Ig chau minh  [ĐÃ THANH TOÁN]	2026-02-25 04:54:08.480194+00	Ig chau minh 	0936083509 	c1 tôn thất thiệp, điện biên, ba đình, hà nội ak\nMinh Châu	\N	\N	\N	unpaid	\N	\N	\N
279	#ADM-994882	204	\N	\N	250000	0	0	250000	transfer	shipping	Ig cry baby [ĐÃ THANH TOÁN]	2026-02-25 04:49:54.98178+00	Ig cry baby	0773105709	Địa chỉ: Chung cư Diamond Riverside, Block D, phòng 26.01, số 1646A, Võ Văn Kiệt, phường Phú Định, quận 8	\N	\N	\N	unpaid	\N	\N	\N
286	#ADM-303932	211	\N	\N	600000	0	0	600000	transfer	shipping	Ig uyên [ĐÃ THANH TOÁN]	2026-02-25 04:55:04.024645+00	Ig uyên	0981852828	47 đuong 47, p. thao dien q2	\N	\N	\N	unpaid	\N	\N	\N
287	#ADM-346355	212	\N	\N	720000	0	0	720000	transfer	shipping	Ig nguyen tran khanh dat [ĐÃ THANH TOÁN]	2026-02-25 04:55:46.443665+00	Ig nguyen tran khanh dat	0963877579	89/1/84 đường số 8, p Tăng Nhơn Phú B, quận 9\nKhánh Đạt 	\N	\N	\N	unpaid	\N	\N	\N
288	#ADM-396894	213	\N	\N	520000	0	0	520000	transfer	shipping	Ig linh tran [ĐÃ THANH TOÁN]	2026-02-25 04:56:36.981708+00	Ig linh tran	0868424123	23 Nguyễn An Ninh, Đống Đa, Phường Đống Đa, Thành Phố Vĩnh Yên, Vĩnh Phúc	\N	\N	\N	unpaid	\N	\N	\N
289	#ADM-439709	214	\N	\N	280000	0	0	280000	transfer	shipping	Ig nguoilanhungquen [ĐÃ THANH TOÁN]	2026-02-25 04:57:19.816456+00	Ig nguoilanhungquen	0918441864 	21B.Nguyễn Thị Thập,Quận 7,TPHCM (phòng 307)\n	\N	\N	\N	unpaid	\N	\N	\N
290	#ADM-534274	215	\N	\N	350000	0	0	350000	transfer	shipping	Ig kate lin  [ĐÃ THANH TOÁN]	2026-02-25 04:58:54.389302+00	Ig kate lin 	+84938203196	saigon royal 09 nguyễn trường tộ p13 quận 4	\N	\N	\N	unpaid	\N	\N	\N
291	#ADM-581416	216	\N	\N	250000	0	0	250000	transfer	shipping	Ig thoai.tienn [ĐÃ THANH TOÁN]	2026-02-25 04:59:41.509075+00	Ig thoai.tienn	0937800100	333/23 Lê Văn Sỹ, P1, Tân bình	\N	\N	\N	unpaid	\N	\N	\N
292	#ADM-628036	217	\N	\N	280000	0	0	280000	transfer	shipping	Ig Doan thu trang [ĐÃ THANH TOÁN]	2026-02-25 05:00:28.130179+00	Ig Doan thu trang	0586338476 	335 Chu Văn An phường 12 Bình Thạnh TPHCM	\N	\N	\N	unpaid	\N	\N	\N
293	#ADM-675083	218	\N	\N	280000	0	0	280000	transfer	shipping	Ig ngốk [ĐÃ THANH TOÁN]	2026-02-25 05:01:15.169667+00	Ig ngốk	0329123422	730/15/8 lạc long qân p9 tbinh tphcm	\N	\N	\N	unpaid	\N	\N	\N
294	#ADM-741013	103	\N	\N	540000	0	0	540000	transfer	shipping	Ig tiên tiên [ĐÃ THANH TOÁN]	2026-02-25 05:02:21.115804+00	Ig tiên tiên	0985037507	02 Nguyễn Lương Bằng - xã Lộc thanh - tp bảo Lộc - lâm đồng 	\N	\N	\N	unpaid	\N	\N	\N
295	#ADM-819422	127	\N	\N	250000	0	0	250000	transfer	shipping	Ig ngocbaongan.  [ĐÃ THANH TOÁN]	2026-02-25 05:03:39.602455+00	Ig ngocbaongan. 	0838812881	37/6/29 hồ văn nhánh kp8 p5 mỹ tho tiền giang	\N	\N	\N	unpaid	\N	\N	\N
296	#ADM-950334	219	\N	\N	350000	0	0	350000	transfer	shipping	ig mimi [ĐÃ THANH TOÁN]	2026-02-25 05:05:50.420019+00	ig mimi	0937896863	89/28 Nghĩa Hưng, Phường 6, Tân Bình, Tp.HCM	\N	\N	\N	unpaid	\N	\N	\N
297	#ADM-008193	220	\N	\N	190000	0	0	190000	transfer	shipping	Ig minhtamtr [ĐÃ THANH TOÁN]	2026-02-25 05:06:48.283455+00	Ig minhtamtr	0989666805	37C1 ngõ 20 Hồ Tùng Mậu, Cầu Giấy , HN  	\N	\N	\N	unpaid	\N	\N	\N
298	#ADM-055983	221	\N	\N	280000	0	0	280000	transfer	shipping	Ig gnaschee_05  [ĐÃ THANH TOÁN]	2026-02-25 05:07:36.073533+00	Ig gnaschee_05 	0964951368	131/24 tô hiến thành p13 quận 10	\N	\N	\N	unpaid	\N	\N	\N
299	#ADM-117860	100	\N	\N	630000	0	0	630000	transfer	shipping	Ig ohvielleicht [ĐÃ THANH TOÁN]	2026-02-25 05:08:37.970759+00	Ig ohvielleicht	+84 79 6256618	Adress: 428 Võ Nguyên Giáp, Khuê Mỹ, Ngũ Hành Sơn, Đà Nẵng 550000	\N	\N	\N	unpaid	\N	\N	\N
300	#ADM-178070	222	\N	\N	280000	0	0	280000	transfer	shipping	Ig dâu  [ĐÃ THANH TOÁN]	2026-02-25 05:09:38.180086+00	Ig dâu 	0866720360	Đối Diện Quán Karaoke Thu Trang 1\nXã Trưng Trắc, Huyện Văn Lâm, Hưng Yên	\N	\N	\N	unpaid	\N	\N	\N
301	#ADM-225562	223	\N	\N	250000	0	0	250000	transfer	shipping	Ig kim my [ĐÃ THANH TOÁN]	2026-02-25 05:10:25.653239+00	Ig kim my	0564077912	754 phan văn hớn xã xuân thới thượng, hóc môn tphcm ( VUS phan văn hớn )	\N	\N	\N	unpaid	\N	\N	\N
302	#ADM-296195	224	\N	\N	1880000	0	0	1880000	transfer	shipping	Ig bee zzz [ĐÃ THANH TOÁN]	2026-02-25 05:11:36.286628+00	Ig bee zzz	0898395188	34 Trần đình xu Quan 1	\N	\N	\N	unpaid	\N	\N	\N
303	#ADM-391871	225	\N	\N	250000	0	0	250000	transfer	shipping	Ig alena mishkova [ĐÃ THANH TOÁN]	2026-02-25 05:13:11.981307+00	Ig alena mishkova	0867 743 532	124 Lý Thái Tổ, Đường Đệ, Nha Trang, Khánh Hòa	\N	\N	\N	unpaid	\N	\N	\N
304	ORD-16881772015017	226	\N	\N	700000	0	20000	720000	banking	shipping	\N	2026-02-25 10:23:37.449768+00	Mr. Kuo Đài Loan(Gửi phòng bảo vệ)	0937670759	Đường 7C, KCN Nhơn Trạch 2, Nhơn Trạch, Đồng Nai, Huyện Nhơn Trạch, Đồng Nai	qazxcv74123@gmailc.com	\N	\N	unpaid	\N	1708	480906
308	#ADM-433085	230	\N	\N	400000	0	0	400000	transfer	shipping	Ig mai le [ĐÃ THANH TOÁN]	2026-02-25 11:03:53.210823+00	Ig mai le	0974274411	mai le\n86 dường số 17 ấp tân tiến xã tân thông hội huyện củ chi\n	\N	\N	\N	unpaid	\N	\N	\N
305	#ADM-489083	227	\N	\N	350000	0	0	350000	transfer	shipping	Ig phi yến  [ĐÃ THANH TOÁN]	2026-02-25 10:48:09.172061+00	Ig phi yến 	0932087209	119-121 lê lợi Q1	\N	\N	\N	unpaid	\N	\N	\N
306	#ADM-525991	228	\N	\N	190000	0	0	190000	transfer	shipping	Ig hà mỹ [ĐÃ THANH TOÁN]	2026-02-25 10:48:46.117894+00	Ig hà mỹ	0379207027	Thôn 5, xã quãng tân, huyện Tuy Đức, tỉnh Đăk Nông	\N	\N	\N	unpaid	\N	\N	\N
307	#ADM-571844	229	\N	\N	630000	0	0	630000	transfer	shipping	Ig cún [ĐÃ THANH TOÁN]	2026-02-25 10:49:31.933409+00	Ig cún	0972221913	80/15 Dương Quảng Hàm, phường 5, Gò Vấp, Tphcm	\N	\N	\N	unpaid	\N	\N	\N
309	#ADM-743803	231	\N	\N	280000	0	0	280000	transfer	shipping	Ig thu phuong pham [ĐÃ THANH TOÁN]	2026-02-26 03:32:23.901277+00	Ig thu phuong pham	0888068969	Số nhà 24 ngõ 38 đường Tô Hiệu Cẩm Trung Cẩm Phả Quảng Ninh	\N	\N	\N	unpaid	\N	\N	\N
310	#ADM-785375	232	\N	\N	250000	0	0	250000	transfer	shipping	ig Bé thảo [ĐÃ THANH TOÁN]	2026-02-26 03:33:05.491054+00	Bé thảo ig	0981651629	Phường 10, gò vấp (địa chỉ cũ)\nPhường gò vấp (địa chỉ mới) 	\N	\N	\N	unpaid	\N	\N	\N
311	#ADM-865149	233	\N	\N	250000	0	0	250000	transfer	shipping	Ig t.mit.ti [ĐÃ THANH TOÁN]	2026-02-26 03:34:25.265344+00	Ig t.mit.ti	0344846390	49 tân thới nhất 1b p. Đông hưng thuận	\N	\N	\N	unpaid	\N	\N	\N
312	ORD-56921772082368	234	\N	\N	950000	0	20000	970000	banking	shipping	\N	2026-02-26 05:06:08.072324+00	Thân Thị Ánh 	0393350981	Nhà số 41, Huyện Việt Yên, Bắc Giang	anhthithan383@gmail.com	\N	\N	unpaid	\N	1763	180918
313	#ADM-530865	235	\N	\N	350000	0	0	350000	transfer	shipping	Ig uhuyenday [ĐÃ THANH TOÁN]	2026-02-26 05:25:31.003173+00	Ig uhuyenday	0379110562	Park 4, 208 Đ. Nguyễn Hữu Cảnh, Vinhomes Tân Cảng, Bình Thạnh, Hồ Chí Minh\n\n	\N	\N	\N	unpaid	\N	\N	\N
314	#ADM-586001	236	\N	\N	630000	0	0	630000	transfer	shipping	Ig michelle  [ĐÃ THANH TOÁN]	2026-02-26 05:26:26.128679+00	Ig michelle 	0942300185	30/14 Lê Anh Xuân, p. Thới Bình, q. Ninh Kiều, TP. Cần Thơ\n(KOL TẶNG ĐỒ) 	\N	\N	\N	unpaid	\N	\N	\N
319	ORD-30741772102757	240	\N	\N	280000	0	20000	300000	banking	pending	\N	2026-02-26 10:45:57.332724+00	Nguyễn Hiếu	0927006907	Đường 19/5 chung cư ct2 vĩnh điềm trung, Thành phố Nha Trang, Khánh Hòa	hieuhappy2201@gmail.com	\N	\N	unpaid	\N	1548	410121
315	#ADM-631339	237	\N	\N	600000	0	0	600000	transfer	shipping	Ig vo hieu thao [ĐÃ THANH TOÁN]	2026-02-26 05:27:11.423275+00	Ig vo hieu thao	0387054842	(Phòng trọ Út Minh) 563/63/32/2A Lê Văn Khương, khu phố 73, phường Tân Thới Hiệp, Tp.Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N
316	#ADM-831692	238	\N	\N	280000	0	0	280000	transfer	shipping	zalo ngô thị an [ĐÃ THANH TOÁN]	2026-02-26 05:30:31.818201+00	zalo ngô thị an	092.379.3678	Mặt sau số 168 Trần Thủ Độ, Pháp Vân, Hoàng Liệt, Hoàng Mai, Hà Nội\n(ค้นหา 🔍 sân bóng Đại An)\n☎️ 092.379.3678	\N	\N	\N	unpaid	\N	\N	\N
317	#ADM-295964	42	\N	\N	350000	0	0	350000	transfer	shipping	Ig phuc hanh pham [ĐÃ THANH TOÁN]	2026-02-26 06:28:16.443968+00	Ig phuc hanh pham	0855877511	Địa chỉ:264 nam kì khởi nghĩa, p. Xuân hoà, hcm 	\N	\N	\N	unpaid	\N	\N	\N
318	#ADM-707752	239	\N	\N	650000	0	0	650000	transfer	shipping	Ig rosé rosalie  [ĐÃ THANH TOÁN]	2026-02-26 06:35:07.892136+00	Ig rosé rosalie 	0888007659 / 0355180235	Name : Rose Rosalie ( MS0148 )\nContact Numbers:\n0888007659 / 0355180235\nAdd: 131c, phố Thanh Am, phường Thượng Thanh, quận Long Biên, Hà Nội.\nNhớ ghi mã lên kiện hàng :\nMS0148	\N	\N	\N	unpaid	\N	\N	\N
320	#ADM-726639	241	\N	\N	280000	0	0	280000	transfer	pending	Ig ngoc phuc [ĐÃ THANH TOÁN]	2026-02-26 14:38:46.771442+00	Ig ngoc phuc	0703929339	Chung cư Sky89- đường lê thị chợ- phường phú thuận- quận 7	\N	\N	\N	unpaid	\N	\N	\N
321	#ADM-770743	242	\N	\N	280000	0	0	280000	transfer	pending	Ig bống  [ĐÃ THANH TOÁN]	2026-02-26 14:39:30.856289+00	Ig bống 	0965641518	8bt13 foresa 1 khu đô thị xuân phương nam từ liêm Hà Nội	\N	\N	\N	unpaid	\N	\N	\N
322	#ADM-914327	243	\N	\N	250000	0	0	250000	transfer	pending	Ig mifam.store [ĐÃ THANH TOÁN]	2026-02-26 14:41:54.421621+00	Ig mifam.store	0839867277	268 đường 3/2 quận 10	\N	\N	\N	unpaid	\N	\N	\N
323	#ADM-035857	244	\N	\N	630000	0	0	630000	transfer	pending	Ig hí [ĐÃ THANH TOÁN]	2026-02-26 14:43:55.984857+00	Ig hí	0989190214	22A2 Khu Dân Cư Phú Nhuận Phước Long B Quận 9	\N	\N	\N	unpaid	\N	\N	\N
\.


--
-- TOC entry 4079 (class 0 OID 23128)
-- Dependencies: 426
-- Data for Name: product_collections; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.product_collections (product_id, category_id) FROM stdin;
12	2
13	1
10	1
9	2
\.


--
-- TOC entry 4051 (class 0 OID 17522)
-- Dependencies: 398
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.products (id, name, slug, description, base_price, images, is_active, created_at, category_id, size_chart_url) FROM stdin;
19	SOLÉ BIKINI	sole-bikini-1769507676713	Chất liệu : Thun \nThành phần : 75% Nylon 25% Elastane\nCó mút ngực \nCả quần và áo đều được may 2lớp	280000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769265/brown_migration/fimz294eg3kkb8bmjctt.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769267/brown_migration/blrjy2iae3xn7xfqfuai.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769271/brown_migration/gnqcsbph4qyzuduzoxid.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769275/brown_migration/qf174raoukionl7cd67i.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769280/brown_migration/s8rm3td058juezupbsnd.webp}	t	2026-01-27 09:54:36.85854+00	3	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770118/brown_migration/gfvwpyokghhjz1ktexit.webp
20	BRONZE BIKINI	bronze-bikini-1769507808808	Chất liệu : Thun \nThành phần : 75% Nylon 25% Elastane\nCó mút ngực \nCả quần và áo đều được may 2lớp.	320000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769284/brown_migration/xys4exdoboqao5ze6jwm.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769286/brown_migration/pwemx2jz1eqhswgemb4d.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769293/brown_migration/rak674jj3lqghlhzzmgn.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769297/brown_migration/ffoeunremjgu2tfm1ttd.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769301/brown_migration/mhyoonmu4pxtbcdj5twr.webp}	t	2026-01-27 09:56:48.95231+00	3	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770124/brown_migration/pbnrq6mmjc3jlcio7eok.webp
3	SKIRT HONEY DRESS 	skirt-honey-dress--1769437468949	Chất liệu : Thun\nThành phần : 75% Nylon 25% Elastane \nChân váy dài lưng thấp cạp xéo, gập viền hoặc không tuỳ thích.\nTất cả các phép đo kích thước đều được tính bằng cm.	280000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769147/brown_migration/kyszl10ert2ngyvc6vij.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769151/brown_migration/apufsmwgkprd1rrwdl1n.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769156/brown_migration/po4bwi2i55biign1hr36.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769161/brown_migration/sl5qtgwzqijx7uue9m4k.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769168/brown_migration/uyt1n3r6yonaoqyfyd9c.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769176/brown_migration/cjkaparblrcgv4p5gopr.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769184/brown_migration/q6obkn2chidncrrcd4sk.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769192/brown_migration/mq3ldjmbwsixdhqjtzp8.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769200/brown_migration/swpapgojvfwml0lcjvm7.webp}	t	2026-01-26 14:24:29.537851+00	2	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770122/brown_migration/scokzjry0upfhbseds3a.webp
18	IVORY BIKINI	ivory-bikini-1769507588435	Chất liệu : Thun \nThành phần : 75% Nylon 25% Elastane\nCó mút ngực \nCả quần và áo đều được may 2lớp.\n	280000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769238/brown_migration/h7vio5lvckeyedu6aklx.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769242/brown_migration/jti5uw9gwcctjhuigqsu.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769249/brown_migration/to8sbr8myovk7sfymmcr.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769255/brown_migration/gm03cfq2wruleg0gkk60.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769262/brown_migration/zawq3rrtwepqbo0b0bkx.webp}	t	2026-01-27 09:53:08.685456+00	3	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770116/brown_migration/cydhbuknueywtpxpmgme.webp
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
8	LAROSE CAMI	larose-cami-1769441181303	Chất liệu : Thun \nThành phần : 75% Nylon 25% Elastane\n Áo 2 dây cổ tim có chiết eo & may viền giúp nâng phần ngực\nTất cả các phép đo kích thước đều được tính bằng cm.	180000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769729/brown_migration/dfaaotoh2yto0fyrjt7z.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769731/brown_migration/tyga5pulcglsjro479cq.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769733/brown_migration/u60gui7osk7rbwqobjdd.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769734/brown_migration/d0hawe3icq8kga62pvse.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769736/brown_migration/cmrrb2oapi8iuusc0vsw.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769738/brown_migration/rgfgb4jocgvy3scl79kv.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769740/brown_migration/c5rd7lc3salihqnqgdoa.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769742/brown_migration/knbsdq9wqqm9ebuuwyeq.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769744/brown_migration/p6qkrvzql6dnt5hzczfz.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769747/brown_migration/ad0zrcun2hqzbsk5voqm.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769749/brown_migration/bxnpvv51crgv7ebdghdb.webp}	t	2026-01-26 15:26:21.856187+00	1	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770162/brown_migration/kce1rbd3e2mso4kbxdiw.webp
13	GLOW HALTER	glow-halter-1769505948457	Chất liệu : Thun \nThành phần : 75% Nylon 25% Elastane\nÁo yếm may 2 lớp - có cài nút ở cổ - có tăng đơ điều chỉnh ở sau lưng - cột dây để thoải mái điều chỉnh theo số đo của mỗi người.\nTất cả các phép đo kích thước đều được tính bằng cm.	350000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769482/brown_migration/cidhikd6f1l2ug49f9an.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769483/brown_migration/toe9bcc2kjgjbwcyy2fr.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769486/brown_migration/vuvuqzebbdayvbuiikyz.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769489/brown_migration/ozmadjfwcwqnmrviqh7j.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769491/brown_migration/ok9to3b3vhxh3uj6f3sa.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769495/brown_migration/jkhvlnukhvhudaoxchkb.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769498/brown_migration/tmavg80cxetwmntcmppo.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769501/brown_migration/udr2pxu4ucmqkxam3ftd.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769505/brown_migration/t8y1uj4vkygmrbct1e24.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769508/brown_migration/aribh4jpydgr2vapokgg.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769512/brown_migration/x7edgrapr3keykfayemh.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769516/brown_migration/wtyzqctczheqwam8lxzn.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769520/brown_migration/zdodv4fxdhrifto4alun.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769523/brown_migration/kerrpltna5drf85ntfy4.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769526/brown_migration/erzaemhnaa7o0i5x7qqh.webp}	t	2026-01-27 09:25:48.591654+00	1	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770160/brown_migration/ibqomgahjpwtnfzgeoin.webp
16	FLARE PANTS 	flare-pants--1769506994720	Chất liệu : Thun \nThành phần : 75% Nylon 25% Elastane\nQuần loe lưng thấp cạp xéo có gập viền - phần lưng gập không may cố định, khách có thể tuỳ ý gập độ cao thấp theo ý muốn - phần hông có nhún nhẹ hai bên để che phần bụng dưới.\nTất cả các phép đo kích thước đều được tính bằng cm.	400000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769586/brown_migration/xjzur47dba6slonhwjrr.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769588/brown_migration/xxpkcjbeizwzwq5nykrc.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769591/brown_migration/defwkphwuckv04l8vbk2.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769594/brown_migration/fxesxbce1zabpoqgqzcc.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769598/brown_migration/mlsiyzfmczpqq1tspnak.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769602/brown_migration/tiflllnnxip0cbiv9nqw.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769606/brown_migration/cwtrrwrzjg7m606mvmcl.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769610/brown_migration/m4jqo3b87qyp0e1ilwtm.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769614/brown_migration/iabh4onwu9vndvp9xztv.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769618/brown_migration/sdhylixku4x8umpumfgc.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769622/brown_migration/f9mmyk5ep2pixv4kcyt3.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769626/brown_migration/up7qzcljalwrgyxoams9.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769630/brown_migration/jh6vyi2ln28xnfofp9ew.webp}	t	2026-01-27 09:43:15.154499+00	2	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770154/brown_migration/fz8hjwjeylh8klih8u9y.webp
\.


--
-- TOC entry 4063 (class 0 OID 17637)
-- Dependencies: 410
-- Data for Name: promotions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.promotions (id, code, description, discount_type, discount_value, min_order_value, start_date, end_date, requires_account, is_active, usage_limit, used_count, max_discount_amount) FROM stdin;
\.


--
-- TOC entry 4057 (class 0 OID 17585)
-- Dependencies: 404
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
59	59	73	47	100000
60	60	92	1	100000
61	61	88	19	150000
62	62	89	19	150000
63	63	96	10	100000
64	64	74	10	100000
65	65	73	5	100000
66	66	77	4	100000
67	67	78	7	100000
68	68	92	1	100000
69	69	96	10	100000
70	70	102	9	120000
71	71	96	17	100000
72	72	74	16	100000
73	73	96	12	100000
\.


--
-- TOC entry 4055 (class 0 OID 17565)
-- Dependencies: 402
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
58	1	1	10000	\N	2026-02-03 01:39:32.345942+00	\N	\N
59	1	1	4700000	\N	2026-02-03 06:45:45.999699+00	\N	\N
60	1	1	100000	\N	2026-02-03 06:46:35.516485+00	\N	\N
61	1	1	2850000	\N	2026-02-03 06:48:34.447107+00	\N	\N
62	1	1	2850000	\N	2026-02-03 06:48:47.52297+00	\N	\N
63	1	1	1000000	\N	2026-02-03 14:38:58.513743+00	\N	\N
64	1	1	1000000	\N	2026-02-03 14:39:33.312054+00	\N	\N
65	1	1	500000	\N	2026-02-04 09:32:15.421118+00	\N	\N
66	1	1	400000	\N	2026-02-04 09:32:37.395267+00	\N	\N
67	1	1	700000	\N	2026-02-04 09:32:51.608229+00	\N	\N
68	1	1	100000	\N	2026-02-04 09:33:12.932135+00	\N	\N
69	1	1	1000000	\N	2026-02-05 08:10:14.887408+00	\N	\N
70	1	1	1080000	\N	2026-02-05 08:12:34.708281+00	\N	\N
71	1	1	1700000	\N	2026-02-06 12:57:59.836332+00	\N	\N
72	1	1	1600000	\N	2026-02-06 12:58:53.064569+00	\N	\N
73	1	1	1200000	\N	2026-02-08 15:09:27.891702+00	\N	\N
\.


--
-- TOC entry 4045 (class 0 OID 17487)
-- Dependencies: 392
-- Data for Name: stores; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.stores (id, name, address, phone, is_active, created_at) FROM stdin;
1	15 Nguyễn Xuân Khoát	\N	\N	t	2026-01-26 14:30:34.21197+00
\.


--
-- TOC entry 4049 (class 0 OID 17513)
-- Dependencies: 396
-- Data for Name: suppliers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.suppliers (id, name, created_at, phone, address) FROM stdin;
1	Qlee	2026-01-26 14:30:15.248688+00	\N	\N
\.


--
-- TOC entry 4053 (class 0 OID 17549)
-- Dependencies: 400
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
35	8	2S Vàng S	S	Vàng	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769731/brown_migration/tyga5pulcglsjro479cq.webp	2026-01-26 15:26:22.190999+00	500
37	8	2S Trắng S	S	Trắng	\N	\N	2026-01-26 15:26:22.190999+00	500
38	8	2S Trắng M	M	Trắng	\N	\N	2026-01-26 15:26:22.190999+00	500
39	8	2S Đen S	S	Đen	\N	\N	2026-01-26 15:26:22.190999+00	500
40	8	2S Đen M	M	Đen	\N	\N	2026-01-26 15:26:22.190999+00	500
41	8	2S Nâu S	S	Nâu 	\N	\N	2026-01-26 15:26:22.190999+00	500
42	8	2S Nâu M	M	Nâu	\N	\N	2026-01-26 15:26:22.190999+00	500
100	18	Bikini Cherry Trắng	Free	Trắng	\N	\N	2026-01-27 09:53:08.914811+00	500
101	19	Bikini Xanh	Free	Xanh	\N	\N	2026-01-27 09:54:37.063319+00	500
110	9	Jeans S	S	Trắng	\N	\N	2026-01-27 10:18:26.343445+00	500
111	9	Jeans M	M	Trắng	\N	\N	2026-01-27 10:18:26.343445+00	500
112	9	Jeans L	L	Trắng	\N	\N	2026-01-27 10:18:26.343445+00	500
98	17	Áo Thun Xám S	S	Xám	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769816/brown_migration/egnb2jhvee4rkz3fkjg6.webp	2026-01-27 09:50:46.963978+00	500
99	17	Áo Thun Xám M	M	Xám	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769819/brown_migration/xawni7fqx1z55a5dqthv.webp	2026-01-27 09:50:46.963978+00	500
36	8	2S Vàng M	M	Vàng	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769731/brown_migration/tyga5pulcglsjro479cq.webp	2026-01-26 15:26:22.190999+00	500
102	20	Bikini Xám	Free	Xám	\N	\N	2026-01-27 09:56:49.155595+00	500
\.


--
-- TOC entry 4119 (class 0 OID 0)
-- Dependencies: 424
-- Name: banners_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.banners_id_seq', 1, false);


--
-- TOC entry 4120 (class 0 OID 0)
-- Dependencies: 412
-- Name: cart_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.cart_items_id_seq', 1, false);


--
-- TOC entry 4121 (class 0 OID 0)
-- Dependencies: 393
-- Name: categories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.categories_id_seq', 5, true);


--
-- TOC entry 4122 (class 0 OID 0)
-- Dependencies: 422
-- Name: content_banners_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.content_banners_id_seq', 4, true);


--
-- TOC entry 4123 (class 0 OID 0)
-- Dependencies: 407
-- Name: customers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.customers_id_seq', 244, true);


--
-- TOC entry 4124 (class 0 OID 0)
-- Dependencies: 418
-- Name: expense_categories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.expense_categories_id_seq', 4, true);


--
-- TOC entry 4125 (class 0 OID 0)
-- Dependencies: 420
-- Name: expenses_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.expenses_id_seq', 9, true);


--
-- TOC entry 4126 (class 0 OID 0)
-- Dependencies: 405
-- Name: inventory_batches_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.inventory_batches_id_seq', 125, true);


--
-- TOC entry 4127 (class 0 OID 0)
-- Dependencies: 416
-- Name: order_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.order_items_id_seq', 501, true);


--
-- TOC entry 4128 (class 0 OID 0)
-- Dependencies: 414
-- Name: orders_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.orders_id_seq', 323, true);


--
-- TOC entry 4129 (class 0 OID 0)
-- Dependencies: 397
-- Name: products_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.products_id_seq', 23, true);


--
-- TOC entry 4130 (class 0 OID 0)
-- Dependencies: 409
-- Name: promotions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.promotions_id_seq', 1, false);


--
-- TOC entry 4131 (class 0 OID 0)
-- Dependencies: 403
-- Name: purchase_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.purchase_items_id_seq', 73, true);


--
-- TOC entry 4132 (class 0 OID 0)
-- Dependencies: 401
-- Name: purchase_orders_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.purchase_orders_id_seq', 73, true);


--
-- TOC entry 4133 (class 0 OID 0)
-- Dependencies: 391
-- Name: stores_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.stores_id_seq', 1, true);


--
-- TOC entry 4134 (class 0 OID 0)
-- Dependencies: 395
-- Name: suppliers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.suppliers_id_seq', 1, true);


--
-- TOC entry 4135 (class 0 OID 0)
-- Dependencies: 399
-- Name: variants_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.variants_id_seq', 117, true);


--
-- TOC entry 3823 (class 2606 OID 21625)
-- Name: banners banners_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.banners
    ADD CONSTRAINT banners_pkey PRIMARY KEY (id);


--
-- TOC entry 3806 (class 2606 OID 17662)
-- Name: cart_items cart_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cart_items
    ADD CONSTRAINT cart_items_pkey PRIMARY KEY (id);


--
-- TOC entry 3804 (class 2606 OID 17655)
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
-- TOC entry 3821 (class 2606 OID 20157)
-- Name: content_banners content_banners_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_banners
    ADD CONSTRAINT content_banners_pkey PRIMARY KEY (id);


--
-- TOC entry 3796 (class 2606 OID 17634)
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- TOC entry 3817 (class 2606 OID 17727)
-- Name: expense_categories expense_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.expense_categories
    ADD CONSTRAINT expense_categories_pkey PRIMARY KEY (id);


--
-- TOC entry 3819 (class 2606 OID 17737)
-- Name: expenses expenses_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_pkey PRIMARY KEY (id);


--
-- TOC entry 3794 (class 2606 OID 17608)
-- Name: inventory_batches inventory_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_pkey PRIMARY KEY (id);


--
-- TOC entry 3815 (class 2606 OID 17709)
-- Name: order_items order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (id);


--
-- TOC entry 3809 (class 2606 OID 17687)
-- Name: orders orders_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_code_key UNIQUE (code);


--
-- TOC entry 3811 (class 2606 OID 17685)
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- TOC entry 3825 (class 2606 OID 23132)
-- Name: product_collections product_collections_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_collections
    ADD CONSTRAINT product_collections_pkey PRIMARY KEY (product_id, category_id);


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
-- TOC entry 3800 (class 2606 OID 17649)
-- Name: promotions promotions_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promotions
    ADD CONSTRAINT promotions_code_key UNIQUE (code);


--
-- TOC entry 3802 (class 2606 OID 17647)
-- Name: promotions promotions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promotions
    ADD CONSTRAINT promotions_pkey PRIMARY KEY (id);


--
-- TOC entry 3791 (class 2606 OID 17590)
-- Name: purchase_items purchase_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_items
    ADD CONSTRAINT purchase_items_pkey PRIMARY KEY (id);


--
-- TOC entry 3787 (class 2606 OID 21610)
-- Name: purchase_orders purchase_orders_code_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_code_unique UNIQUE (code);


--
-- TOC entry 3789 (class 2606 OID 17573)
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
-- TOC entry 3783 (class 2606 OID 17556)
-- Name: variants variants_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.variants
    ADD CONSTRAINT variants_pkey PRIMARY KEY (id);


--
-- TOC entry 3785 (class 2606 OID 17558)
-- Name: variants variants_sku_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.variants
    ADD CONSTRAINT variants_sku_key UNIQUE (sku);


--
-- TOC entry 3807 (class 1259 OID 22937)
-- Name: idx_cart_items_variant_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cart_items_variant_id ON public.cart_items USING btree (variant_id);


--
-- TOC entry 3797 (class 1259 OID 17635)
-- Name: idx_customer_phone; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_customer_phone ON public.customers USING btree (phone);


--
-- TOC entry 3798 (class 1259 OID 23174)
-- Name: idx_customers_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_customers_user_id ON public.customers USING btree (user_id);


--
-- TOC entry 3792 (class 1259 OID 17624)
-- Name: idx_inventory_fifo; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_inventory_fifo ON public.inventory_batches USING btree (store_id, variant_id, created_at);


--
-- TOC entry 3812 (class 1259 OID 22935)
-- Name: idx_order_items_order_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_order_items_order_id ON public.order_items USING btree (order_id);


--
-- TOC entry 3813 (class 1259 OID 22936)
-- Name: idx_order_items_variant_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_order_items_variant_id ON public.order_items USING btree (variant_id);


--
-- TOC entry 3848 (class 2620 OID 21696)
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
-- TOC entry 3826 (class 2606 OID 17507)
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
-- TOC entry 3827 (class 2606 OID 23169)
-- Name: products fk_products_main_category; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT fk_products_main_category FOREIGN KEY (category_id) REFERENCES public.categories(id);


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
-- TOC entry 3846 (class 2606 OID 23138)
-- Name: product_collections product_collections_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_collections
    ADD CONSTRAINT product_collections_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id) ON DELETE CASCADE;


--
-- TOC entry 3847 (class 2606 OID 23133)
-- Name: product_collections product_collections_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_collections
    ADD CONSTRAINT product_collections_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


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
-- TOC entry 4031 (class 3256 OID 22904)
-- Name: categories Admin All Categories; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Categories" ON public.categories USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4023 (class 3256 OID 22896)
-- Name: customers Admin All Customers; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Customers" ON public.customers USING ((EXISTS ( SELECT 1
   FROM public.customers customers_1
  WHERE ((customers_1.user_id = auth.uid()) AND (customers_1.role = 'admin'::text)))));


--
-- TOC entry 4025 (class 3256 OID 22898)
-- Name: expenses Admin All Expenses; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Expenses" ON public.expenses USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4026 (class 3256 OID 22899)
-- Name: inventory_batches Admin All Inventory; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Inventory" ON public.inventory_batches USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4034 (class 3256 OID 22928)
-- Name: order_items Admin All Order Items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Order Items" ON public.order_items USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4020 (class 3256 OID 22893)
-- Name: orders Admin All Orders; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Orders" ON public.orders USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4019 (class 3256 OID 22892)
-- Name: products Admin All Products; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Products" ON public.products USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4027 (class 3256 OID 22900)
-- Name: promotions Admin All Promotions; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Promotions" ON public.promotions USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4029 (class 3256 OID 22902)
-- Name: variants Admin All Variants; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Variants" ON public.variants USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4039 (class 3256 OID 22933)
-- Name: banners Admin Manage Banners; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin Manage Banners" ON public.banners USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4017 (class 3256 OID 20159)
-- Name: content_banners Admin Manage Banners; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin Manage Banners" ON public.content_banners USING ((auth.role() = 'authenticated'::text));


--
-- TOC entry 4040 (class 3256 OID 22934)
-- Name: content_banners Admin Manage Content Banners; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin Manage Content Banners" ON public.content_banners USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4037 (class 3256 OID 22931)
-- Name: banners Public Read Banners; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Banners" ON public.banners FOR SELECT USING (true);


--
-- TOC entry 4016 (class 3256 OID 20158)
-- Name: content_banners Public Read Banners; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Banners" ON public.content_banners FOR SELECT USING (true);


--
-- TOC entry 4030 (class 3256 OID 22903)
-- Name: categories Public Read Categories; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Categories" ON public.categories FOR SELECT USING (true);


--
-- TOC entry 4038 (class 3256 OID 22932)
-- Name: content_banners Public Read Content Banners; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Content Banners" ON public.content_banners FOR SELECT USING (true);


--
-- TOC entry 4018 (class 3256 OID 22891)
-- Name: products Public Read Products; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Products" ON public.products FOR SELECT USING (true);


--
-- TOC entry 4028 (class 3256 OID 22901)
-- Name: variants Public Read Variants; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Variants" ON public.variants FOR SELECT USING (true);


--
-- TOC entry 4036 (class 3256 OID 22930)
-- Name: order_items User Create Order Items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User Create Order Items" ON public.order_items FOR INSERT WITH CHECK (true);


--
-- TOC entry 4022 (class 3256 OID 22895)
-- Name: orders User Create Orders; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User Create Orders" ON public.orders FOR INSERT WITH CHECK (true);


--
-- TOC entry 4024 (class 3256 OID 22897)
-- Name: customers User Manage Self; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User Manage Self" ON public.customers USING ((user_id = auth.uid()));


--
-- TOC entry 4033 (class 3256 OID 22927)
-- Name: carts User Own Cart; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User Own Cart" ON public.carts USING ((user_id = auth.uid()));


--
-- TOC entry 4032 (class 3256 OID 22926)
-- Name: cart_items User Own Cart Items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User Own Cart Items" ON public.cart_items USING (((EXISTS ( SELECT 1
   FROM public.carts
  WHERE ((carts.user_id = cart_items.cart_id) AND (carts.user_id = auth.uid())))) OR ((cart_id)::text = (auth.uid())::text)));


--
-- TOC entry 4035 (class 3256 OID 22929)
-- Name: order_items User View Own Order Items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User View Own Order Items" ON public.order_items FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.orders
  WHERE ((orders.id = order_items.order_id) AND (EXISTS ( SELECT 1
           FROM public.customers
          WHERE ((customers.id = orders.customer_id) AND (customers.user_id = auth.uid()))))))));


--
-- TOC entry 4021 (class 3256 OID 22894)
-- Name: orders User View Own Orders; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User View Own Orders" ON public.orders FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.id = orders.customer_id) AND (customers.user_id = auth.uid())))));


--
-- TOC entry 4014 (class 0 OID 21617)
-- Dependencies: 425
-- Name: banners; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.banners ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4008 (class 0 OID 17657)
-- Dependencies: 413
-- Name: cart_items; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4007 (class 0 OID 17650)
-- Dependencies: 411
-- Name: carts; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.carts ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 3998 (class 0 OID 17497)
-- Dependencies: 394
-- Name: categories; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4013 (class 0 OID 20148)
-- Dependencies: 423
-- Name: content_banners; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.content_banners ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4005 (class 0 OID 17626)
-- Dependencies: 408
-- Name: customers; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4011 (class 0 OID 17721)
-- Dependencies: 419
-- Name: expense_categories; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.expense_categories ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4012 (class 0 OID 17729)
-- Dependencies: 421
-- Name: expenses; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4004 (class 0 OID 17602)
-- Dependencies: 406
-- Name: inventory_batches; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.inventory_batches ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4010 (class 0 OID 17704)
-- Dependencies: 417
-- Name: order_items; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4009 (class 0 OID 17674)
-- Dependencies: 415
-- Name: orders; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4015 (class 0 OID 23128)
-- Dependencies: 426
-- Name: product_collections; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.product_collections ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4000 (class 0 OID 17522)
-- Dependencies: 398
-- Name: products; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4006 (class 0 OID 17637)
-- Dependencies: 410
-- Name: promotions; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.promotions ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4003 (class 0 OID 17585)
-- Dependencies: 404
-- Name: purchase_items; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.purchase_items ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4002 (class 0 OID 17565)
-- Dependencies: 402
-- Name: purchase_orders; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 3997 (class 0 OID 17487)
-- Dependencies: 392
-- Name: stores; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.stores ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 3999 (class 0 OID 17513)
-- Dependencies: 396
-- Name: suppliers; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4001 (class 0 OID 17549)
-- Dependencies: 400
-- Name: variants; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.variants ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4085 (class 0 OID 0)
-- Dependencies: 50
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE USAGE ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO PUBLIC;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- TOC entry 4086 (class 0 OID 0)
-- Dependencies: 413
-- Name: TABLE cart_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.cart_items TO service_role;
GRANT SELECT ON TABLE public.cart_items TO anon;


--
-- TOC entry 4087 (class 0 OID 0)
-- Dependencies: 412
-- Name: SEQUENCE cart_items_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.cart_items_id_seq TO service_role;


--
-- TOC entry 4088 (class 0 OID 0)
-- Dependencies: 411
-- Name: TABLE carts; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.carts TO service_role;
GRANT SELECT ON TABLE public.carts TO anon;


--
-- TOC entry 4089 (class 0 OID 0)
-- Dependencies: 394
-- Name: TABLE categories; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.categories TO service_role;
GRANT SELECT ON TABLE public.categories TO anon;


--
-- TOC entry 4090 (class 0 OID 0)
-- Dependencies: 393
-- Name: SEQUENCE categories_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.categories_id_seq TO service_role;


--
-- TOC entry 4091 (class 0 OID 0)
-- Dependencies: 423
-- Name: TABLE content_banners; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.content_banners TO service_role;
GRANT SELECT ON TABLE public.content_banners TO anon;
GRANT SELECT ON TABLE public.content_banners TO authenticated;


--
-- TOC entry 4092 (class 0 OID 0)
-- Dependencies: 408
-- Name: TABLE customers; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.customers TO service_role;
GRANT SELECT ON TABLE public.customers TO anon;
GRANT SELECT,UPDATE ON TABLE public.customers TO authenticated;


--
-- TOC entry 4093 (class 0 OID 0)
-- Dependencies: 407
-- Name: SEQUENCE customers_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.customers_id_seq TO service_role;


--
-- TOC entry 4094 (class 0 OID 0)
-- Dependencies: 419
-- Name: TABLE expense_categories; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.expense_categories TO service_role;
GRANT SELECT ON TABLE public.expense_categories TO anon;


--
-- TOC entry 4095 (class 0 OID 0)
-- Dependencies: 418
-- Name: SEQUENCE expense_categories_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.expense_categories_id_seq TO service_role;


--
-- TOC entry 4096 (class 0 OID 0)
-- Dependencies: 421
-- Name: TABLE expenses; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.expenses TO service_role;
GRANT SELECT ON TABLE public.expenses TO anon;


--
-- TOC entry 4097 (class 0 OID 0)
-- Dependencies: 420
-- Name: SEQUENCE expenses_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.expenses_id_seq TO service_role;


--
-- TOC entry 4098 (class 0 OID 0)
-- Dependencies: 406
-- Name: TABLE inventory_batches; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.inventory_batches TO service_role;
GRANT SELECT ON TABLE public.inventory_batches TO anon;


--
-- TOC entry 4099 (class 0 OID 0)
-- Dependencies: 405
-- Name: SEQUENCE inventory_batches_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.inventory_batches_id_seq TO service_role;


--
-- TOC entry 4100 (class 0 OID 0)
-- Dependencies: 417
-- Name: TABLE order_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.order_items TO service_role;
GRANT SELECT ON TABLE public.order_items TO anon;


--
-- TOC entry 4101 (class 0 OID 0)
-- Dependencies: 416
-- Name: SEQUENCE order_items_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.order_items_id_seq TO service_role;


--
-- TOC entry 4102 (class 0 OID 0)
-- Dependencies: 415
-- Name: TABLE orders; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.orders TO service_role;
GRANT SELECT ON TABLE public.orders TO anon;


--
-- TOC entry 4103 (class 0 OID 0)
-- Dependencies: 414
-- Name: SEQUENCE orders_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.orders_id_seq TO service_role;


--
-- TOC entry 4104 (class 0 OID 0)
-- Dependencies: 426
-- Name: TABLE product_collections; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.product_collections TO service_role;
GRANT ALL ON TABLE public.product_collections TO anon;
GRANT ALL ON TABLE public.product_collections TO authenticated;


--
-- TOC entry 4105 (class 0 OID 0)
-- Dependencies: 398
-- Name: TABLE products; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.products TO service_role;
GRANT SELECT ON TABLE public.products TO anon;


--
-- TOC entry 4106 (class 0 OID 0)
-- Dependencies: 397
-- Name: SEQUENCE products_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.products_id_seq TO service_role;


--
-- TOC entry 4107 (class 0 OID 0)
-- Dependencies: 410
-- Name: TABLE promotions; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.promotions TO service_role;
GRANT SELECT ON TABLE public.promotions TO anon;


--
-- TOC entry 4108 (class 0 OID 0)
-- Dependencies: 409
-- Name: SEQUENCE promotions_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.promotions_id_seq TO service_role;


--
-- TOC entry 4109 (class 0 OID 0)
-- Dependencies: 404
-- Name: TABLE purchase_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.purchase_items TO service_role;
GRANT SELECT ON TABLE public.purchase_items TO anon;


--
-- TOC entry 4110 (class 0 OID 0)
-- Dependencies: 403
-- Name: SEQUENCE purchase_items_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.purchase_items_id_seq TO service_role;


--
-- TOC entry 4111 (class 0 OID 0)
-- Dependencies: 402
-- Name: TABLE purchase_orders; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.purchase_orders TO service_role;
GRANT SELECT ON TABLE public.purchase_orders TO anon;


--
-- TOC entry 4112 (class 0 OID 0)
-- Dependencies: 401
-- Name: SEQUENCE purchase_orders_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.purchase_orders_id_seq TO service_role;


--
-- TOC entry 4113 (class 0 OID 0)
-- Dependencies: 392
-- Name: TABLE stores; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.stores TO service_role;
GRANT SELECT ON TABLE public.stores TO anon;


--
-- TOC entry 4114 (class 0 OID 0)
-- Dependencies: 391
-- Name: SEQUENCE stores_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.stores_id_seq TO service_role;


--
-- TOC entry 4115 (class 0 OID 0)
-- Dependencies: 396
-- Name: TABLE suppliers; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.suppliers TO service_role;
GRANT SELECT ON TABLE public.suppliers TO anon;


--
-- TOC entry 4116 (class 0 OID 0)
-- Dependencies: 395
-- Name: SEQUENCE suppliers_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.suppliers_id_seq TO service_role;


--
-- TOC entry 4117 (class 0 OID 0)
-- Dependencies: 400
-- Name: TABLE variants; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.variants TO service_role;
GRANT SELECT ON TABLE public.variants TO anon;


--
-- TOC entry 4118 (class 0 OID 0)
-- Dependencies: 399
-- Name: SEQUENCE variants_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.variants_id_seq TO service_role;


-- Completed on 2026-02-27 09:23:07

--
-- PostgreSQL database dump complete
--

