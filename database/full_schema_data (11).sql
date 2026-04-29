--
-- PostgreSQL database dump
--

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.5

-- Started on 2026-04-15 09:25:29

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
-- TOC entry 501 (class 1255 OID 21750)
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
-- TOC entry 488 (class 1255 OID 20107)
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
-- TOC entry 498 (class 1255 OID 21695)
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
    is_visible_on_home boolean DEFAULT true,
    name_en character varying(255)
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
    customer_ward_code text,
    exported_at timestamp with time zone,
    exported_sapo_at timestamp with time zone,
    exported_spx_at timestamp with time zone
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
    size_chart_url text,
    name_en character varying(255),
    description_en text,
    is_preorder boolean DEFAULT false,
    preorder_note text
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
    weight integer DEFAULT 500,
    color_en text
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
-- TOC entry 4085 (class 0 OID 21617)
-- Dependencies: 425
-- Data for Name: banners; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.banners (id, title, image_url, link_url, is_active, created_at) FROM stdin;
\.


--
-- TOC entry 4073 (class 0 OID 17657)
-- Dependencies: 413
-- Data for Name: cart_items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.cart_items (id, cart_id, variant_id, quantity) FROM stdin;
\.


--
-- TOC entry 4071 (class 0 OID 17650)
-- Dependencies: 411
-- Data for Name: carts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.carts (user_id, updated_at) FROM stdin;
\.


--
-- TOC entry 4054 (class 0 OID 17497)
-- Dependencies: 394
-- Data for Name: categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.categories (id, name, slug, parent_id, created_at, is_visible_on_home, name_en) FROM stdin;
4	JEANS	jeans	\N	2026-01-27 08:56:56.151804+00	f	JEANS
5	TEST	test	\N	2026-02-03 01:19:02.337362+00	f	TEST
3	BIKINI	bikini	\N	2026-01-26 14:29:28.485714+00	t	BIKINI
2	BOTTOMS	bottoms	\N	2026-01-26 14:07:55.177475+00	t	BOTTOMS
1	TOPS	tops	\N	2026-01-26 13:33:39.51621+00	t	TOPS
6	ACCESSORIES	accessories	\N	2026-04-08 09:46:05.60156+00	t	ACCESSORIES
\.


--
-- TOC entry 4083 (class 0 OID 20148)
-- Dependencies: 423
-- Data for Name: content_banners; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.content_banners (id, title, image_url, link_to, display_order, is_active, created_at) FROM stdin;
4	BROWN	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769145/brown_migration/nukinhe2ozewpdgbgrag.webp		0	t	2026-01-27 10:29:56.871449+00
\.


--
-- TOC entry 4068 (class 0 OID 17626)
-- Dependencies: 408
-- Data for Name: customers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.customers (id, user_id, full_name, phone, email, address, loyalty_points, created_at, role, avatar_url) FROM stdin;
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
245	\N	Ig Dương Kim Yên	082.77.888.55	\N	Số 15 đường 27, KDC An Khánh, An Khánh, Ninh Kiều, Cần Thơ	0	2026-02-27 04:38:37.15835+00	user	\N
246	\N	Ig ahihi1632	0937926358	\N	 1243 ql20, xã đại lào ,bảo lộc -Lâm đồng( cơm niêu thuận kiều)	0	2026-02-27 04:39:19.257278+00	user	\N
247	\N	Ig vy vy	0865911606 	\N	33 hoa mai , phú nhuận	0	2026-02-27 12:13:06.680253+00	user	\N
248	\N	Ig bao t truong	0367055470	\N	B161C khu phố 3, phường đông hưng thuận,quận 12, hcm	0	2026-02-27 12:13:50.196804+00	user	\N
249	\N	Ig loan sansa	0979537084	\N	Số 6 ngõ 444 thuỵ khuê, tây hồ, hà nội	0	2026-02-27 12:14:40.490708+00	user	\N
250	\N	Ig em my	 0377211144	\N	Đc ấp mỹ lộ phường mỹ Đức tp Hà tiên tỉnh kiên Giang	0	2026-02-27 12:15:23.121472+00	user	\N
251	\N	Ig imkkiil ( 🧚‍♀️)	0889993313	\N	Nhà văn hoá khu 5- Hải Yên-Móng Cái-Quảng Ninh	0	2026-02-27 12:16:41.245635+00	user	\N
252	\N	Ig lưu hồng duyên	 0919732358	\N	Đc: 191 Tô Hiến Thành p5 Cà Mau 	0	2026-02-27 12:17:27.915267+00	user	\N
253	\N	Ig jan miki 	 0325267896	\N	375 tân thới hiệp 21 , Tổ 3 ,Kp3 ,quận 12 ( nhớ gõ đủ)\nSố kho : 0325267896  ( nhớ ghi mã khách hàng ) \n\nNhớ ghi mã lên kiện hàng : W24130 Miki brown	0	2026-02-27 12:18:23.597513+00	user	\N
254	\N	ig Van	0964432596 	\N	26A phạm thế hiển p thắng tam tpvt\nVân anh	0	2026-02-27 12:19:24.711846+00	user	\N
255	\N	Ig nguyễn phương thảo	0902933723	\N	5/13，đường Nguyễn văn Vĩnh ,P4,Q Tân bình	0	2026-02-27 12:21:20.486492+00	user	\N
256	\N	Ig dogsea	0923789902 	\N	54/3 Đào Duy Anh p9 Phú Nhuận - ( Phương Thảo )	0	2026-02-27 12:22:28.980671+00	user	\N
257	\N	phamthanhtra_	 0372328696	\N	•  Địa chỉ: 158A Bùi Thị Xuân, Phường Phạm Ngũ Lão, Quận 1	0	2026-02-27 12:48:03.693704+00	user	\N
258	\N	phạm ngọc trang	0986667499	trangmits.99@gmail.com	Royal City (sảnh R5), 72 Nguyễn Trãi 	0	2026-02-27 12:52:56.487765+00	user	\N
259	\N	Ig huỳnh vyvy	0909961295	\N	441/59c p25 điện biên phủ bình thanh 	0	2026-02-27 13:41:33.06326+00	user	\N
260	\N	Ig ngọc anh 	0822691939	\N	Khóm 1 thị trấn mỹ an huyện tháp mười tỉnh đồng tháp\n	0	2026-02-27 13:46:07.403981+00	user	\N
261	\N	Ig sbabie_	0826350862	\N	địa chỉ ấp minh Tân xã minh hoà huyện châu thành tỉnh kiên Giang	0	2026-02-27 13:48:29.069927+00	user	\N
262	\N	Ig phi nguyen	0934100243	\N	124/7 mễ cốc p15 q8\n	0	2026-02-27 13:50:33.482104+00	user	\N
263	\N	Ig minthu	0374263243	\N	Apc Corporation, 30/7, Trương Văn , Khu Phố Tân Hiệp, Phường Tân Bình, Thành Phố Dĩ An, Bình Dương	0	2026-02-27 15:13:56.85247+00	user	\N
624	\N	Ig MJ	0886493061	\N	278a nguyễn đình chiểu, q3 	0	2026-03-27 12:19:18.979445+00	user	\N
264	\N	Nguyễn Quỳnh Chi	0968006054	nguyenquynhchi297@gmail.com	40 ngách 175 Thịnh Quang	0	2026-02-27 19:05:53.275982+00	user	\N
265	\N	Test Email	+14155550198	domquangminhtriet17@gmail.com	15 Test Street	0	2026-02-28 03:03:19.955219+00	user	\N
266	\N	Test 2	+1 415 555 0198	domquangminhtriet17@gmail.com	15 Street	0	2026-02-28 03:56:00.710279+00	user	\N
267	\N	Ig donfetch 	+84357012453	\N	Ibis Saigon Airport Hotel, Room 931\n2 Hồng Hà, Phường 2, Tân Bình, Thành phố Hồ Chí Minh 700000, Vietnam\n	0	2026-02-28 11:46:46.768773+00	user	\N
268	\N	Ig bé ý	0902650169	\N	72 lên thánh tôn q1 ạ\n\n	0	2026-02-28 11:47:57.394717+00	user	\N
269	\N	Ig trần yến oanh 	0939 741 868	\N	Vincom My Tho, số 1A đường Hùng Vương, p1, Mỹ Tho, Tiền Giang ( căn PG02-33) 	0	2026-02-28 11:49:18.856597+00	user	\N
270	\N	Ig tuyên du	0845352059	\N	9A Đường Thạnh Xuân 13, Thạnh Xuân, Quận 12, Thành phố Hồ Chí Minh	0	2026-02-28 11:58:15.603851+00	user	\N
271	\N	Ig wyn	0364309690 	\N	710 Nguyễn Thị Minh khai khu phố đông Thành phường Tân Đông Hiệp dĩ an Bình Dương	0	2026-02-28 11:58:53.148385+00	user	\N
272	\N	Ig hồng hân 	0939553828	\N	19 Đường Nguyễn Công Trứ , Phường Long Hưng , Thị Xã Tân Châu , An Giang	0	2026-02-28 12:00:57.67615+00	user	\N
273	\N	Ig qingyi8802	0396504228	\N	Số 51, ngõ 31, B6 Khu nhà ở Mai Dịch, đường Nguyễn Khả Trạc, Phường Phú Diễn, Thành phố Hà Nội, Việt Nam (phường Mai Dịch, Cầu Giấy cũ)	0	2026-02-28 12:02:41.439481+00	user	\N
274	\N	Ig hien huynh	0919170394	\N	10a Huyền trân công chúa p4 thành phố Đà Lạt	0	2026-02-28 12:03:47.186664+00	user	\N
275	\N	Ig anbeoo	0906969933	\N	nhà số 9, đường số 8, kdc ven sông, tân phong q7	0	2026-02-28 12:06:35.223554+00	user	\N
276	\N	Ig jade nguyen 	0765009732 	\N	114A Trịnh Phong, Phường, Nha Trang, Khánh Hòa	0	2026-02-28 12:09:39.492803+00	user	\N
277	\N	Ig lucy 	0788221551	\N	chung cư miếu nổi, 54 vũ huy tấn 	0	2026-02-28 12:10:09.573534+00	user	\N
278	\N	Ig nm.nguye7723	0908561539	\N	126/1d tôn thất đạm f bến nghé q1\n	0	2026-02-28 16:22:06.649635+00	user	\N
279	\N	Ig phương anh	0888066234	\N	ngõ 76 nhà số 2 , đường nguyễn công hoan , phường bắc lý , tp đồng hới tỉnh quảng bình, Phường Bắc Lý, Thành phố Đồng Hới, Quảng Bình 	0	2026-02-28 17:22:01.325666+00	user	\N
280	\N	Ig tô yến	0986238325	\N	10 Kha Vạn Cân p An Bình, Dĩ An, Bình Dương (chung cư Opal Boulevard)	0	2026-02-28 17:24:41.326605+00	user	\N
281	\N	Ig phương uyên nè	0899478507 	\N	10/4 đường 68 phường hiệp Phú thủ Đức	0	2026-03-01 09:00:40.996009+00	user	\N
282	\N	ig Feng	0966811696	\N	96/4 Võ Thành Trang, Phường 11, Tân Bình \n	0	2026-03-01 09:01:28.765676+00	user	\N
283	\N	Ig Lê Nguyễn Minh Thư	0828464976	\N	145 ấp Mỹ Thạnh, phường Mỹ Phong tỉnh Đồng Tháp	0	2026-03-01 09:02:30.52609+00	user	\N
284	\N	Ig daanauuuu	0799079940	\N	 36/36 Nguyễn Triệu Luật, Tân Tạo, Bình Tân - Sđt: 	0	2026-03-01 10:22:48.468264+00	user	\N
285	\N	Ig huỳnh thư	0373290600	\N	107 Nguyễn Văn Linh, P.Tân thuận tây, quận 7  ecogen lock H	0	2026-03-01 10:23:22.7442+00	user	\N
286	\N	Test	+1 854 098 09	domquangminhtriet17@gmail.com	15 Street	0	2026-03-01 10:34:04.929061+00	user	\N
287	\N	Yuyi Liu	3024202474	yui89jp@icloud.com	46 Albe dr  Ste 1 HW1211360	0	2026-03-01 15:59:31.375059+00	user	\N
288	\N	Ig cao song nghi 	0868795525	\N	11 đường số 10, khu phố 4, hiệp bình chánh, thủ đức	0	2026-03-02 09:34:04.16269+00	user	\N
289	\N	Ig thuan.ng87 	0938801987 	\N	27 Nguyễn Hữu Thọ,tháp X2 Sunrise City North, Tân Hưng, q7	0	2026-03-02 09:41:09.550936+00	user	\N
290	\N	Ig iimvananh	0938547603 	\N	c2/26 phạm hùng xã bình hưng huyện bình chánh tphcm	0	2026-03-02 10:04:49.552533+00	user	\N
291	\N	Ig mô	0334232268	\N	112 Yên Phụ nhỏ, phường Yên Phụ, quận Tây Hồ, TP Hà Nội	0	2026-03-02 10:05:31.829009+00	user	\N
292	\N	Ig THU TRANG TRAN	0934331193 	\N	Chung cư New City -  toà Hawai 1 - p2101 số 17 Mai Chí Thọ - p An Khánh - tp Thủ Đức - HCM 	0	2026-03-02 10:12:05.660331+00	user	\N
293	\N	Ig kieuan_7 	0329873525	\N	Hestia Bakery & Coffee, Số 73, Lê Văn Thọ , Phường 8 , Quận Gò Vấp\n\n	0	2026-03-02 10:15:11.665649+00	user	\N
294	\N	Ig celineharu 	0335587187	\N	ố 15 ngách 82/122 ngõ 166 kim mã, ba đình, hn	0	2026-03-02 10:18:43.996171+00	user	\N
295	\N	Ig mai mai 	0972270801	\N	275 Lê Lợi, Ngô Quyền Hải Phòng 	0	2026-03-02 10:21:50.082065+00	user	\N
296	\N	ig Phors	 0346086663	\N	301 Phạm Ngũ Lão, Phường Phạm Ngũ Lão, Quận 1, Hồ Chí Minh, District 1, 	0	2026-03-02 10:26:07.449245+00	user	\N
297	\N	ig Be han	0933888347 	\N	203 cao văn lầu p2 q6 cũ\n	0	2026-03-02 10:27:47.423763+00	user	\N
298	\N	Ig iemboee	0946757175	\N	153 đường số 4 , p16 gò vấp tphcm\n	0	2026-03-02 10:30:05.105631+00	user	\N
299	\N	Ig cammuy 	0977790977	\N	478/a hai bà trưng phường tân định quận 1	0	2026-03-02 10:33:11.406579+00	user	\N
300	\N	Ig shizukeoo	0787612039	\N	 182 Ngô Huy Diễn, p. Hoà Xuân, q.Cẩm Lệ. Tp Đà Nẵng\n	0	2026-03-02 10:35:30.443351+00	user	\N
301	\N	Ig vy 	 0777055049	\N	10/76/31 hoàng hoa thám p7 bình thạnh	0	2026-03-02 10:37:47.26862+00	user	\N
302	\N	Phạm Yến Vy	0796689118	vyphamyen0311@gmail.com	132 Bến Vân Đồn Phường 6 Quận 4 TPHCM	0	2026-03-02 14:27:39.931154+00	user	\N
303	\N	Ig an nhi	0824100205	\N	10/4 Kỳ Đồng, phường 9, Quận 3. TP HCM	0	2026-03-02 14:59:44.621531+00	user	\N
304	\N	Ig emy 	0779937230	\N	Số 2 lô o cư xá vĩnh hội đường nguyễn hữu hào P9 Q4	0	2026-03-02 15:00:22.146218+00	user	\N
305	\N	Ig yennyenyn 	0987659810	\N	6 Nguyễn thiện thuật đồng xuân hoàn kiếm hà nội 	0	2026-03-02 15:00:57.485694+00	user	\N
306	\N	Ig nm.le 	0936135601	\N	số nhà 11, ngách 1/1 đường An Dương Vương, Phú Thượng, Tây Hồ, Hà Nội 	0	2026-03-02 15:02:38.481021+00	user	\N
307	\N	vsv	cdv	\N	27136bkjb	0	2026-03-02 15:03:10.385809+00	user	\N
308	\N	Ig chu thị thuỷ tiên	0393222393	\N	17 mai chí thọ an khánh q2, newcity bali\n	0	2026-03-02 15:14:24.190869+00	user	\N
309	\N	TEst	0978919874	\N	test	0	2026-03-02 16:34:56.035213+00	user	\N
310	\N	test	ád	\N	ádf	0	2026-03-02 16:44:33.23459+00	user	\N
1	ec819d8a-eea4-457a-b6fb-bcd522478d40	Admin Brown	0900000000	brownvn25@gmail.com		0	2026-01-26 15:45:19.754264+00	admin	\N
311	1651318f-e91e-441d-aa39-6587b6f9cdf7	Trà My	0868808283	ngtrinhtramy1310@gmail.com	\N	0	2026-03-02 17:34:01.961505+00	user	\N
312	\N	Đặng Khánh Linh	0911862338	\N	Số 3, Nguyễn Viết Xuân, phường Khương Mai, quận Thanh Xuân	0	2026-03-02 17:35:47.504427+00	user	\N
313	\N	Vy Truong	0938656758	\N	48/8 nguyễn thanh tuyền	0	2026-03-03 00:46:32.938578+00	user	\N
314	744894ba-8d64-48c6-b059-bc5bf4372029	Ms Quynh	0825240605	truongnhuquynh@gmail.com	\N	0	2026-03-03 06:39:46.380244+00	user	\N
625	\N	Bảo bối	0828392000	\N	17 ngõ 31/21 nguyễn cao hbt hn	0	2026-03-27 12:19:42.405615+00	user	\N
315	\N	Ig afterfive.offcial  	09 0268 4984	\N	100/82 thích quảng đức, p5, quận Phú nhuận\n	0	2026-03-03 09:39:47.253005+00	user	\N
316	\N	Ig huyền trang 	0399522524	\N	45 Nguyễn Sơn, Ngọc Lâm, Long Biên	0	2026-03-03 09:50:58.61386+00	user	\N
317	\N	Ig hoàng thu trang 	0941388237	\N	Toà F, chung cư Feliz Home, 293 Hoàng Mai, phường Hoàng Văn Thụ, quận Hai Bà Trưng, Hà Nội	0	2026-03-03 09:51:27.144237+00	user	\N
318	\N	Ig .ariel 	0702601138	\N	 33 nguyễn chí thanh,thạch thang,hải châu,tp đà nẵng	0	2026-03-03 09:52:10.658849+00	user	\N
319	\N	Ig kiwi1989	0908709018	\N	63-65A11, Khu phố 11, Nguyễn Văn Tiên, Phường Tân Phong, Tp. Biên Hoà, Tỉnh Đồng Nai	0	2026-03-03 09:52:43.385924+00	user	\N
320	\N	Ig thanhthubeauty2310	0963873132	\N	Tháp 2 Toà Time tower 35 lê văn lương, nhân chính, thanh xuân hn\n	0	2026-03-03 10:09:14.763556+00	user	\N
321	\N	Ig my hoang huyen	096-792-1229 	\N	số 16-18 galaxy 1, khu đô thị ngân hà, hà đông, hà nội 	0	2026-03-03 10:09:49.006315+00	user	\N
322	\N	Ig nguyễn hương	397 507 979	\N	39 Thôn Nam Trang\nXã Đinh Trang Hòa, Huyện Di Linh, Lâm Đồng	0	2026-03-03 10:13:40.172995+00	user	\N
323	\N	Ig jennie	0905579126	\N	29 Lê Huân, Thuận Hoà, Huế, Thành phố Huế, Vietnam	0	2026-03-03 10:15:24.419035+00	user	\N
324	\N	Ig tam_dhin 	0961068025	\N	Số 20, Ngõ 394 Đường Mỹ Đình, Phường Mỹ Đình 1, Quận Nam Từ Liêm, Hà Nội\nSdt: 0961068025\nNgười nhận: Đinh Thị Tâm	0	2026-03-03 10:15:57.625954+00	user	\N
325	\N	Ig hong tham ngo	0933333373	\N	số 8 đường 47 phường 4 quận 4 ( sài gòn ) 	0	2026-03-03 10:17:14.249066+00	user	\N
326	\N	Ig nguyễn phương thảo	0962821709	\N	BS8 The Berverly Solari, Vinhomes Grand Park, phường Long Bình, q9, Thủ Đức, HCM	0	2026-03-03 13:17:56.630796+00	user	\N
327	\N	Ig hmtbhappi 	(+84) 859 828 504	\N	Phòng 201, 57B Ngõ 98 Thái Hà, Phường Trung Liệt, Quận Đống Đa, Hà Nội	0	2026-03-04 12:18:40.147725+00	user	\N
328	\N	Ig vũ thị luyến	0352692759	\N	Số 8 kinh dương vương suối hoa tp bn cũ ạ g la phường kinh bắc 	0	2026-03-04 12:20:44.800632+00	user	\N
329	\N	Ig hương nguyễn	0931602299	\N	S10.03 vinhomes grand park, nguyễn xiễn, long bình, quận 9, tphcm	0	2026-03-04 12:21:16.664237+00	user	\N
330	\N	Ig kiko 	0359864888	\N	Toà D 6th element Xuân La Tây hồ HN	0	2026-03-04 12:21:56.187147+00	user	\N
331	\N	Ig ocethuw 	038 2043805	\N	Chợ mỹ hiệp, xã mỹ hiệp, huyện cao lãnh, tỉnh đồng tháp\n	0	2026-03-04 12:22:51.511152+00	user	\N
332	\N	Ig KANYARAT 	 0369166.222	\N	( BN2705)\n163 Trương Thị Hoa, phường Tân Thới Hiệp, Quận 12, thành phố Hồ Chí Minh\n sdt : 0369166.222 ( Người Nhận BN2705)\n	0	2026-03-04 12:24:18.232721+00	user	\N
333	\N	Ig tu tu 	0972060321	\N	96 hữu lê- hữu hoà- thanh trì- hà nội\nCẩm tú	0	2026-03-04 12:37:24.008732+00	user	\N
334	\N	 Diễm My	0377746617	\N	126/1d Tôn Thất Đạm phường Bến Nghé quận 1	0	2026-03-04 12:38:12.238191+00	user	\N
335	\N	Ig venus_saohom 	0908088988	\N	206 ng van huong,quan 2 	0	2026-03-04 12:40:48.101538+00	user	\N
336	\N	Ig gg	 0779117207 	\N	263/8 Điện Biên Phủ.  F15.  Quận Bình Thạnh.  \nPhone 0779117207 Bác Liễu	0	2026-03-04 12:41:44.018728+00	user	\N
337	\N	Ig dương thị kim ngân	0706109051	\N	33 nguyễn bỉnh khiêm, da kao, q1	0	2026-03-04 12:42:18.483536+00	user	\N
338	\N	Ig tracy 	0354053241	\N	82/2C1 đường 494, phường tăng nhơn phú a, thủ đức\nBích Trâm	0	2026-03-04 12:44:03.964147+00	user	\N
339	\N	Ig thu hồng 	0981676578	\N	Địa chỉ cũ Công ty THNN Tung Yang xã cẩm phúc huyện cẩm giàng tỉnh Hải Dương	0	2026-03-04 12:44:46.652781+00	user	\N
340	\N	Ig vvmman	0936311118	\N	kiôt 220 chợ Phạm Thế Hiển ( đối diện hàng gạo ) tạp hoá Kim Phương\nphường chánh hưng tphcm ( p4 q8 cũ )\n	0	2026-03-04 12:45:41.451348+00	user	\N
341	\N	Ig bich tuyn 	0373912352	\N	712/ tỉnh lộ 10\nBình trị đông \nBình tân\nHcm	0	2026-03-04 14:33:40.447069+00	user	\N
342	\N	Ig dan thanh 	0383445592 	\N	13, đường số 17, khu phố 2,phường bình chiểu , Tp Thủ Đức	0	2026-03-04 14:34:19.714582+00	user	\N
343	\N	Ig nguyen quynh traang 	0866716280	\N	cuối ngõ 14 phố Lụa, Vạn Phúc, Hà Đông, HN\n	0	2026-03-04 16:03:18.862238+00	user	\N
344	\N	pass đồ 	0902173763	\N	15 Nguyễn xuân Khoát	0	2026-03-04 16:14:23.787777+00	user	\N
345	\N	IG Ngân	0356848574	\N	14 đường số 6 khu phố 4 hiệp bình chánh thủ đức\nĐịa chỉ mới 14 đường số 6 kp56 hiệp bình	0	2026-03-04 16:24:27.954974+00	user	\N
346	\N	Ig hoàng nguyên trương 	0973 820 020	\N	Đường nhựa bên trái dưới chân cầu đối diện chợ Thạnh Hoà Sơn, ấp Cầu Vĩ, xã Thạnh Hoà Sơn, huyện Cầu Ngang, tỉnh Trà Vinh	0	2026-03-04 16:44:40.678972+00	user	\N
347	\N	Kim Chi	+84896749101	\N	185A Liêu Bình Hương	0	2026-03-04 23:51:52.457994+00	user	\N
348	\N	Lý Trần Bích Thuỷ	0967817921	lythuy16081999@gmail.com	197 Trần Nhật Duật	0	2026-03-05 02:52:28.525524+00	user	\N
349	\N	Cao Hồng Nhung	0855255253	chnhung0200@gmail.com	4A Lê Thánh Tông	0	2026-03-05 06:25:41.130575+00	user	\N
350	\N	My Nguyễn	0906502085	nngthmy@gmail.com	535/47 Thống Nhất	0	2026-03-05 08:37:24.334439+00	user	\N
351	\N	Ig vani	(+84) 797026555	\N	Zalo Ntram\nTPHCM Q TÂN BÌNH P1\n\n281/36, Lê Văn Sĩ	0	2026-03-05 11:36:50.043994+00	user	\N
352	\N	Ig kimchi_boo	+84896749101 	\N	185a liêu bình hương, tân thông hội, củ chi	0	2026-03-05 11:37:46.14077+00	user	\N
353	\N	Ig kristina	0938059936	\N	202/18 võ văn tần p5 q3	0	2026-03-05 11:38:33.37858+00	user	\N
354	\N	Ig nguyễn thanh trúc 	0981798729	\N	88 Ngọc Lâm - Long Biên - Hà Nội\n	0	2026-03-05 11:39:14.789065+00	user	\N
355	\N	Ig kelly 	0977661777	\N	La Rosa Apartment\n25 đường số 61, Thảo Điền, Q2 cũ, TP.HCM	0	2026-03-05 11:39:38.002581+00	user	\N
356	\N	Ig embotocvanghoe	0979200903	\N	lô d2 chung cư mỹ đức phường 19 bình thạnh	0	2026-03-05 11:40:02.515899+00	user	\N
357	\N	Ig lily 	0929610964	\N	46/33 bạch đằng f24 quận Bình Thạnh\n	0	2026-03-05 11:40:38.597577+00	user	\N
358	\N	Ig greenfast_	0792516411	\N	39b ng văn linh q7\n	0	2026-03-05 11:41:00.510107+00	user	\N
359	\N	Ig ngoc phong 	0772184758	\N	Toà C , Central Garden, 328 Võ Văn Kiệt, phường Cô Giang, q1 \nTên: Ngọc Phong	0	2026-03-05 11:42:17.64649+00	user	\N
360	\N	bùi trân	0905790628	buihoangbaotran785@gmail.com	340/29 phan châu trinh	0	2026-03-05 11:58:40.968194+00	user	\N
361	\N	Ig lâm thuý an	0366949072	\N	57 Nguyễn Trọng Lội, Q. Tân Bình	0	2026-03-05 14:09:35.254863+00	user	\N
362	\N	Ig vivs	0797131533	\N	860/67 xo viet nghe tinh phuong 25  quan binh thanh thanh pho ho chi minh	0	2026-03-05 15:40:34.827552+00	user	\N
363	\N	Ig meskmuse_	0908799311  	\N	252/11 lý chính thắng p9 q3 	0	2026-03-05 16:18:15.473753+00	user	\N
364	9a2b054f-9804-4419-80c6-ec35a9e00f93	Nguyễn Kiều Mai Vy	09897267	vybeo150805@gmail.com	46 DC8 phường Sơn kỳ quận Tân Phú 	0	2026-03-05 17:41:50.26723+00	user	\N
365	\N	Nguyễn nga	0862166028	nga433080@gmail.com	Số 2 hẻm 2 ngách 53 ngõ 165 cầu giấy	0	2026-03-06 02:57:08.405971+00	user	\N
366	\N	Ig uyên nhật	0822101634	\N	Chợ bình triệu, tiệm vàng ngon nhân trong chợ, phường hiệp bình chánh, thủ đức\n	0	2026-03-06 04:16:44.939222+00	user	\N
367	\N	Ig mya_nh54 	0354395608 	\N	30 tùng thiện vương phường Phú định Q8 	0	2026-03-06 04:17:32.218326+00	user	\N
368	\N	Ig anhh.tn	0983690744	\N	Số 6 ngõ 54/1 thượng thuỵ đức thượng hoài đức hà nội 	0	2026-03-06 04:19:03.889078+00	user	\N
369	\N	Lâm Thanh Kiều Tiên	0346009498	kieutien98er@gmail.com	208 Thống Nhất Mới	0	2026-03-06 08:39:47.186312+00	user	\N
370	\N	Ig thiên thương	0919288118	\N	Toà B chung cư n04 Hoàng Đạo Thuý quận cầu giấy Hn \t\t	0	2026-03-06 14:16:19.147696+00	user	\N
371	\N	Ig thuy linh truong 	0949866289	\N	số nhà 39 ngách 53/22 ngõ 68 cầu giấy\n	0	2026-03-06 14:18:22.38764+00	user	\N
372	\N	Ig fenndinhh	0935415274 	\N	97 Ngô Quyền, Thành phố Quảng Ngãi	0	2026-03-07 06:24:07.485347+00	user	\N
373	\N	Ig luong ngoc diep 	0842509333 	\N	5b/46 nhân hoà, thanh xuân, hà nội 	0	2026-03-07 06:24:34.367204+00	user	\N
374	\N	Nguyễn Lan Anh	0981589630	lananhng185@gmail.com	48 Trần Quốc Toản	0	2026-03-07 06:28:20.64866+00	user	\N
375	\N	Ig pass đồ - tly	0392378870	\N	373/1/4 lý thường kiệt, p9 quận Tân Bình tpHCM	0	2026-03-08 07:38:39.008266+00	user	\N
376	\N	Ig th.d82	0982080802	\N	Park 8, Times City, phường Vĩnh Tuy, thành phố Hà Nội	0	2026-03-08 07:41:19.160376+00	user	\N
377	\N	Ig th.d82	0982080802	\N	Park 8, Times City, phường Vĩnh Tuy, thành phố Hà Nội	0	2026-03-08 07:41:19.199902+00	user	\N
378	\N	Ig y băng ng 	0965304907	\N	Đường số 11, hẻm 11C, phước tân 2, xã Tân Hưng, tp Bà rịa	0	2026-03-08 07:42:32.316+00	user	\N
379	\N	Ig trần phú quý  Quý 	0968288637	\N	652/55 cộng hoà	0	2026-03-08 07:43:11.555833+00	user	\N
380	\N	Ig van pham	 0379733739	\N	Chung cư EcoGreen - block G, 39B Nguyễn Văn Linh, phường Tân Thuận Tây, quận 7	0	2026-03-08 08:08:57.100242+00	user	\N
381	\N	Ig caleb.gurl 	0383456677	\N	chung cư Galaxy 9, số 9 Nguyễn Khoái, quận 4\n	0	2026-03-08 08:09:27.927695+00	user	\N
382	\N	Ig chloe nguyễn 	0963091319	\N	Bali 1 cc new city thủ thiên an khánh	0	2026-03-08 08:09:57.388895+00	user	\N
383	\N	Ig sarahlnaa	0379.907.234	\N	42a Nguyễn du - hồ xá - Vĩnh linh - quảng trị	0	2026-03-08 08:18:13.526355+00	user	\N
384	\N	Ig thhuyanh	0916549550	\N	35/12 Ấp 4 Hoà An Phụng Hiệp Hậu Giang	0	2026-03-08 08:19:43.624639+00	user	\N
385	\N	Ig jehegwjsbv 	087 633 7187	\N	Etipol Express \nVận tải Campuchia \nThông Tin Gửi Hàng \n* ETV So Ct (EV23837)\n· Địa Chỉ: 315/18/6 Nhuyễn Thị Tú, Phường Bình Hưng Hòa B, Quận Bình Tân, Hồ Chí Minh 	0	2026-03-08 08:20:39.990617+00	user	\N
386	\N	Ig nguyễn huỳnh lâm ngọc	0981 771 340	\N	320/16a Nguyễn Văn Linh, phường Bình Thuận  quận 7, hcm\n	0	2026-03-08 08:29:59.634826+00	user	\N
387	\N	Ig congchuaoriii	789515469	\N	30/95 Đỗ Nhuận, Sơn Kì, Tân Phú	0	2026-03-08 15:43:25.205364+00	user	\N
388	\N	Ig ulsuove_ 	0364789984	\N	212/3b phạm văn chiêu phường 9 gò vấp\n	0	2026-03-08 15:46:54.464044+00	user	\N
389	\N	Ig kay 	0907807661	\N	21 Ký Hoà P11 Q5	0	2026-03-08 15:49:36.148418+00	user	\N
390	\N	Ig lac ngoc nhi	0796117375	\N	12/17 nguyễn lâm p6 q10	0	2026-03-08 15:52:56.943416+00	user	\N
391	\N	Uyển Nhi	0905045576	uyennhi081106@gmail.com	55 đường số 11	0	2026-03-09 08:27:08.536309+00	user	\N
392	\N	Ig gbee_	0367826546 	\N	30/3 pasteur p4 Đà Lạt	0	2026-03-09 10:57:37.668581+00	user	\N
393	\N	Ig gbee_	0367826546 	\N	30/3 pasteur p4 Đà Lạt	0	2026-03-09 10:57:37.833823+00	user	\N
394	\N	Ig minhhtthanh	0568685030	\N	111 dương bá trạc phường 1 quận 8 	0	2026-03-09 11:00:01.412236+00	user	\N
395	\N	Ig ur honey 	0908300521 	\N	26 Lý Tự Trọng, Q1\n	0	2026-03-09 11:01:29.993953+00	user	\N
396	\N	Ig ngoctho_0201 	0987691425	\N	58 Chu Văn An , phường Tân Thành, TPHCM\n\nQuỳnh Như	0	2026-03-09 11:02:06.703416+00	user	\N
397	\N	Tiktok bông nè 	0902696551	\N	149/53/15 trịnh đình trọng tân phú	0	2026-03-09 11:03:21.6703+00	user	\N
398	\N	Ig nguyễn thị mai linh 	0367160843	\N	Văn Môn-Yên Phong-Bắc Ninh	0	2026-03-09 11:03:53.388779+00	user	\N
399	\N	ig Mai jun 	 0935146101	\N	Khu phố phước thịnh thị trấn Phú thứ tây hòa phú yên\n	0	2026-03-09 11:04:37.771454+00	user	\N
400	\N	Ig hoàng nguyên trương	0973 820 020 	\N	Đường nhựa bên trái dưới chân cầu đối diện chợ Thạnh Hoà Sơn, ấp Cầu Vĩ, xã Thạnh Hoà Sơn, huyện Cầu Ngang, tỉnh Trà Vinh\n\nGiờ là ấp Cầu Vĩ, xã Ngũ Lạc, tỉnh Vĩnh Long	0	2026-03-09 11:41:17.078378+00	user	\N
401	\N	Ig hồng trâm 	 (+84) 787 726 763	\N	15/3, Trần Hưng Đạo\nPhường 6, Thành Phố Mỹ Tho, Tiền Giang	0	2026-03-09 11:57:24.739655+00	user	\N
402	\N	Ig iloveapricot	0836588889	\N	411/32 Nguyễn đình chiểu, p5, q3	0	2026-03-09 11:58:50.65101+00	user	\N
403	\N	Ig kimnhi_2910	0971351900	\N	299/16/4L Lý Thường Kiệt, phường Phú Thọ, hcm	0	2026-03-09 13:56:12.062339+00	user	\N
404	\N	Ig yến 	0867928063	\N	139 nguyên suý, tân phú	0	2026-03-09 16:08:30.582851+00	user	\N
405	\N	đỗ ly	0948370303	camlydoabc@gmail.com	106 đường số 51 	0	2026-03-10 12:02:19.288181+00	user	\N
406	\N	Ig elma_hus 	Thuỵ Sỹ	\N	Elma Husic \nChemin de Chantemerle 21 \n1350 Orbe \nSuisse \n078/791.24.97	0	2026-03-10 14:30:28.918611+00	user	\N
407	\N	Ig sắn 	0919386166	\N	Toà c6, chung cư d'capital, yên hoà HN	0	2026-03-10 14:31:30.259237+00	user	\N
408	\N	Ig nguyễn nguyệt	0989366708	\N	Đc:74/14, Phan Đăng Lưu, Phường 5, Quận Phú Nhuận, TP. Hồ Chí Minh	0	2026-03-10 14:32:35.314414+00	user	\N
409	\N	Ig lê salan 	0784250794	\N	90 nguyễn hữu cảnh p22 quận bình thạnh . \nSunwah Pearl Golden House 	0	2026-03-10 14:34:00.131168+00	user	\N
410	\N	Hùng anh	0888324293	tothuhoai62@gmail.com	27 Võ Trường Toản	0	2026-03-11 05:39:17.202177+00	user	\N
411	\N	Trần Thu Uyên	0344671610	thu.uyenn1610@gmail.com	Chung cư Sunrise City Central - Toà W2 - 25 Nguyễn Hữu Thọ	0	2026-03-11 09:48:52.71853+00	user	\N
412	\N	Dịu	0898075217	diun2506@gmail.com	45- An Hạ 3- An Thượng- Hoài Đức- HN	0	2026-03-11 10:37:37.037143+00	user	\N
413	\N	Đàm Thị Ngọc Anh	0908284907	dtnanh20092007@gmail.com	175 Võ Văn Ngân, phường Linh Chiểu ,tp Thủ Đức, Hồ Chí Minh	0	2026-03-11 11:40:02.564737+00	user	\N
414	\N	Ig đang nhập	0947204452	\N	144/1/3 bình lợi, p13, bình thạnh	0	2026-03-11 13:40:47.112695+00	user	\N
415	\N	Ig tieu han tran 	0839946946	\N	203 mai thị hồng hạnh phường vĩnh lợi thành phố rạch giá kiên giang	0	2026-03-11 13:41:53.90837+00	user	\N
416	\N	Ig evey 	0963189389	\N	350, đ. Hoàng Liên, p. Lào Cai (p. Kim tân, tp. Lào Cai cũ), tỉnh Lào Cai	0	2026-03-11 13:42:41.362951+00	user	\N
417	\N	Ig mai hân hân 	0934155514	\N	331 bến vân đồn q4	0	2026-03-11 13:43:18.896052+00	user	\N
418	\N	Ig thục đoan woong 	0784689885 	\N	442/10 Lê Quang ĐỊnh, quận Bình Thạnh\n	0	2026-03-11 13:44:38.005619+00	user	\N
419	\N	Ig N	0374671733	\N	Căn hộ citizent - đường 9A - khu trung sơn - bình hưng - Bình Chánh 	0	2026-03-11 13:48:09.403482+00	user	\N
420	\N	Ig phuong dung chu	0368823044 	\N	· Địa chỉ: Move Vietnam, 27E Võ Trường Toản, Thảo Điền, quận 2 	0	2026-03-11 13:49:40.105314+00	user	\N
421	\N	Ig jie71104	0931393787 	\N	07 Thai Dương-Phường Thuận An-Tp Huế-sđt 	0	2026-03-11 13:50:27.757308+00	user	\N
422	\N	Ig tamnhu nguyen3	0938227331	\N	11 thuận kiều p4 q11	0	2026-03-11 16:39:34.871408+00	user	\N
423	\N	Ig milynnguyen 	0899960366	\N	407 nguyễn văn khối,p8,gv hcm	0	2026-03-11 16:40:42.147082+00	user	\N
424	\N	Ig baotran	0362799723 	\N	6/205D Bưng Ông Thoàn tăng nhơn phú B thủ đức tphcm	0	2026-03-11 17:00:08.53188+00	user	\N
425	\N	Ig nu 	0778988112	\N	13.04 S6, The Sun Anenue, 28 Đ. Mai Chí Thọ, An Phú, Thành phố Thủ Đức	0	2026-03-12 03:04:04.443065+00	user	\N
426	\N	 Lan Dang ig	(786) 502 0870	\N	16714 sw 39th st Miramar FL,33027\n(786) 502 0870	0	2026-03-12 15:27:29.170172+00	user	\N
427	\N	Ig imi	0976441633 	\N	Cc hoàng anh thanh bình\nĐường d4 phường tân hưng quận 7 \nNhư	0	2026-03-12 15:28:19.505567+00	user	\N
428	\N	Ig kiraikini	0966655088	\N	số 9 bế văn cấm quận 7 nha\n	0	2026-03-12 15:28:55.566976+00	user	\N
429	\N	Ig anni 	0909318058 	\N	7/7 Nguyen Trai Ben Thanh .aspire Sai Gon	0	2026-03-12 15:31:41.664095+00	user	\N
430	\N	Ig hanjin_wb	0909078752 	\N	192 nguyễn công trứ phường Bến Thành	0	2026-03-12 15:32:17.180217+00	user	\N
431	\N	Ig haaaviii	0965203289	\N	50 Tạ Quang Bửu, Hai Bà Trưng, Hà Nội	0	2026-03-12 15:32:45.953778+00	user	\N
432	\N	Ig thuý hằng	0374714319	\N	Sảnh cư dân landmark 81	0	2026-03-12 15:33:55.395869+00	user	\N
433	\N	Ig bí nhe	0944294068 	\N	202/51 phạm văn hai p5 qtan bình 	0	2026-03-12 15:34:40.819838+00	user	\N
434	\N	Ig quỳnh như	0374801159 	\N	45a đươnhf 3/2 p11 quận 10 	0	2026-03-12 15:35:18.05731+00	user	\N
435	\N	Ig an huệ	0902116728	\N	Chung cư Decapella, 116 Lương Định Của, Phường An Khánh TP Thủ đức	0	2026-03-12 15:36:16.709154+00	user	\N
436	\N	Ig tram anh	0976132961	\N	163 võ thành trang, p bảy hiền ( p11 cũ ) quận tân bình	0	2026-03-12 15:38:50.169053+00	user	\N
437	\N	Ig nauy	0787074452	\N	07 hoàng sĩ khải đà nẵng	0	2026-03-12 15:39:41.486066+00	user	\N
438	\N	Phạm Nguyễn Bảo Quyên	0707121103	p.n.b.quyen12.11@gmail.com	463/15b Kha Vạn Cân	0	2026-03-13 06:03:31.978577+00	user	\N
439	\N	VIKTORIIA konik	+84 39 2340891	vikakotatko@gmail.com	Hiyori Garden Tower 611	0	2026-03-13 09:28:13.555486+00	user	\N
440	\N	Ig gagayeong	 82 10 2076 1821	\N	 Gayeong kim\nPhone : 82 10 2076 1821\nEmail : rkdud1821@naver.com\nShipping address : \n\n601 ho, 312, Bongeunsa-ro, Gangnam-gu, Seoul, Republic of Korea	0	2026-03-13 11:42:55.131249+00	user	\N
441	\N	Ig gagayeong	82 10 2076 1821	\N	Name : Gayeong kim\nPhone : 82 10 2076 1821\nEmail : rkdud1821@naver.com\nShipping address : \n\n601 ho, 312, Bongeunsa-ro, Gangnam-gu, Seoul, Republic of Korea	0	2026-03-13 11:45:48.867753+00	user	\N
442	\N	Ig minh ngọc	+84 38 4045461‬‬	\N	Ấp tân hiệp A, thị trấn Óc Eo, huyện Thoại Sơn, tỉnh An Giang	0	2026-03-13 11:46:20.609974+00	user	\N
443	\N	Ig vũ tường vi	0981078612	\N	57 Phó Đức Chính- P. Nguyễn Thái Bình- Q1	0	2026-03-13 11:48:05.985616+00	user	\N
444	\N	Ig nguyễn bảo uyên	 0901848308	\N	259 Phan Đình Phùng p15 qPN	0	2026-03-13 11:48:34.703731+00	user	\N
445	\N	Ig petit amour	0909967633	\N	18L Điện Biên Phủ quận 1	0	2026-03-13 11:50:32.059948+00	user	\N
446	\N	Ig __strawbeerry	0946335555	\N	số 2 thác mạ 5 phường đông kinh tp lạng sơn	0	2026-03-13 11:51:32.323854+00	user	\N
447	\N	Ig nhi pham	0399433526	\N	843/16/6 Nguyễn Kiệm, p Hạnh Thông (p3 cũ), Gò Vấp, TP HCM	0	2026-03-13 11:52:01.714439+00	user	\N
448	\N	Lê salan 	0784250794.	\N	90 nguyễn hữu cảnh p22 quận bình thạnh . \nSunwah Pearl Golden House .	0	2026-03-13 12:14:26.11462+00	user	\N
449	\N	Ig my.freaky.	0779800109	\N	36a Út tịch, tân bình	0	2026-03-13 14:27:09.36261+00	user	\N
450	\N	Ig haânbala333	0983703307	\N	35 Nguyễn Văn Bá, Bình Thọ, Thủ Đức\n	0	2026-03-14 03:38:46.619624+00	user	\N
451	\N	Ig an	0909056816	\N	Số Nhà 26 Lô U, Đường Cư Xá Phú Lâm D, Phường 10, Quận 6, TP. Hồ Chí Minh\n	0	2026-03-14 03:40:01.782007+00	user	\N
452	\N	Lelinh	0977463201	lehoangphuonglinh16091995@gmai.com	133 huỳnh thúc kháng	0	2026-03-14 06:05:22.646444+00	user	\N
453	3c2288fb-28c0-4f3b-846f-b611d9d593ac	Byun Seyoung	0789841731	seyoung.byun0531@gmail.com	\N	0	2026-03-14 07:14:35.034723+00	user	\N
454	\N	Ig yanie.th	0384643228	\N	Tổ 1, Khu Phố Tiến Hưng 3, Phước, Tỉnh Đồng Nai (Hẻm 167 Số Nhà 47), Xã Tiến Hưng, Thành Phố Đồng Xoài, Bình Phước	0	2026-03-14 12:46:04.447726+00	user	\N
455	\N	Ig minh anh	0788655755	\N	04 phan chu trinh, p bình thạnh tp hcm\n	0	2026-03-14 12:46:34.534565+00	user	\N
456	\N	Ig chenniii	0902847090 	\N	46 Hoa Đào P2 Phú Nhuận	0	2026-03-14 12:47:02.850232+00	user	\N
457	\N	Azjargal Amar	038 5846270	azjargla0125@gmail.com	38/29 Nguyen Cong Hoan	0	2026-03-14 12:47:54.943275+00	user	\N
458	\N	Ig thu yoga & qigong	0962482428	\N	6/5/10 chế lan viên, ngũ hành sơn, đà nẵng	0	2026-03-14 12:48:31.626806+00	user	\N
459	\N	Ig douneo_123	0949855883	\N	74 cử trị châu đốc an giang	0	2026-03-14 12:48:50.663808+00	user	\N
460	\N	Ig ngọc hà	0937408700	\N	Block B Chung cư Eco Green, Nguyễn Văn Linh, Phường tân thuận tây, Quận 7	0	2026-03-14 13:26:29.738176+00	user	\N
461	\N	Ig cam	0786594301	\N	496/93/7 dương quãng hàm p6 gv	0	2026-03-14 13:29:50.383421+00	user	\N
462	\N	Ig jasmine	0934040535	\N	100/15 dương bá trạc p2 q8	0	2026-03-14 16:28:46.762357+00	user	\N
463	\N	Ig amber 	0969998916	\N	lâm viên complex 107a nguyễn phong sắc cầu giấy hn\nphòng 20-01	0	2026-03-14 16:29:26.037219+00	user	\N
464	\N	Nguyễn Thị Thuỷ Tiên	0374354658	ntun.cen16@gmail.com	Thôn 7, xã Lý Trạch, huyện Bố Trạch, tỉnh Quảng Bình	0	2026-03-15 01:51:07.809801+00	user	\N
465	\N	Nhi	0938855752	voyennhi8396@gmail.com	282 nguyễn thị định	0	2026-03-15 15:12:43.043015+00	user	\N
466	\N	Ig tô như huỳnh	 0862087248	\N	006/AL Kp An lợi TT Tiệm Tôm Ba Tri Bến Tre 	0	2026-03-15 16:42:32.343629+00	user	\N
467	\N	Ig rosa nguyen	+16083819852	\N	274 Calle Canals apt 1001, San Juan PR 00907 \nRnguyen12919@gmail.com	0	2026-03-15 16:43:26.590412+00	user	\N
468	\N	Ig minh anh	0846970367	\N	 116/36, bình lợi, bình thạnh 	0	2026-03-15 16:45:31.701084+00	user	\N
469	\N	Ig võ quỳnh nhi 	0945796060	\N	Chung cư rivana phường vĩnh phú thuận an bình dương	0	2026-03-15 16:46:11.22977+00	user	\N
470	\N	Ig phan gia ân	đặng thúc vịnh  0938489922 	\N	211 ấp 7 xã đông thạnh hóc môn đường \nGiao ở áo cưới nhất linh (note) 	0	2026-03-15 16:46:43.4868+00	user	\N
471	\N	Ig nguyet thao nguyen	0769844844	\N	215 Nam Kỳ Khởi Nghĩa quận 3	0	2026-03-15 16:47:11.725742+00	user	\N
472	\N	Ig phuong uyen	0378020197	\N	Căn số 40 khu biệt thự Ngân Long, Phước Kiển, Nhà Bè, TPHCM\nPhương Uyên	0	2026-03-15 16:48:08.065813+00	user	\N
473	\N	Ig yeubonthui	+84 87 9832607	\N	toà nhà BRG, 198 Trần Quang Khải, Lý Thái Tổ, Hoàn Kiếm, Hà Nội 	0	2026-03-15 16:49:13.460691+00	user	\N
474	\N	Ig lihn	0963894934 	\N	Tổ dân phố tuân cáo, phường nam hoa lư \n	0	2026-03-15 16:49:44.663603+00	user	\N
475	\N	Ig pheoo 	0963617696	\N	Số 21, khu C ngách 1194/61/3A, Láng Thượng, Đống Đa, HN	0	2026-03-15 16:50:21.217572+00	user	\N
476	\N	Ig insightofan	 0908931940	\N	địa chỉ: 884/85 Lê Đức Thọ phường 15 quận Gò Vấp TP.HCM	0	2026-03-15 17:20:25.687701+00	user	\N
477	\N	SHUNFEI （#43301）	0383163470	jamiefong0213@gmail.com	Số 160/46 Phan huy ích ，Phường 12 ，quận Gò Vấp TP Hồ Chí Minh	0	2026-03-16 03:02:09.111025+00	user	\N
478	\N	Ig qiennnn_	0934007053	\N	405/8A Thống Nhất, phường Thông Tây Hội\nTp Hồ Chí Minh	0	2026-03-16 07:02:06.97977+00	user	\N
479	\N	Ig duality	0909938897	\N	•  Địa chỉ: 6.08 Toà Sapphire 1, Saigon Pearl, 92 Nguyen Hữu Cảnh, Bình Thạnh	0	2026-03-16 07:04:35.789493+00	user	\N
480	\N	Ig yen anh	0376554218	\N	232 Võ Thị Sáu, Phường Xuân Hoà, TPHCM	0	2026-03-16 07:05:14.572562+00	user	\N
481	\N	Ig jenny	092.379.3678  	\N	Mã khách hàng :  K258\nĐịa chỉ: Mặt sau số 168 Trần thủ độ, Pháp vân , Hoàng liệt , Hoàng mai , Hà nội.\n( gõ tìm kiếm 🔍 sân bóng đại an ) \n	0	2026-03-16 07:06:11.987773+00	user	\N
482	\N	Ig phphuongg	0907469268	\N	2/42 cao thắng p5q3	0	2026-03-16 07:06:56.135817+00	user	\N
483	\N	Ig acidcxc	0949.006083	\N	153, Luong Nhu Hoc, phường chợ lớn, tphcm \nPIC: Nguyen (Becky)	0	2026-03-16 07:08:33.204576+00	user	\N
484	\N	Ig audet elisabeth	0933782889	\N	 Tòa Nhà Sky 89, Số 39, Đường Lê Thị Chợ Căn 20-01, Phường Phú Mỹ, Quận 7, TP. Hồ Chí Minh	0	2026-03-16 07:24:50.768769+00	user	\N
485	\N	Nguyễn Thị Phương Thảo	0365 081621	ducpham1219@gmail.com	38 Ngõ 213	0	2026-03-16 09:37:55.579109+00	user	\N
486	\N	Ig nina	0906852624 	\N	633 ấp 1 Nguyễn Văn Tạo Hiệp Phước Nhà Bè HCM	0	2026-03-16 09:44:24.594586+00	user	\N
487	\N	Lưu Điệp	0965256838	lisaluu2001@icloud.com	247 nguyễn thị lắng	0	2026-03-16 10:49:26.318371+00	user	\N
488	\N	nhật hà	0866833245	hanhatlebui2001@gmail.com	Số nhà 53 ngõ 766 La Thành, Giảng Võ	0	2026-03-16 13:35:17.158759+00	user	\N
489	\N	Ig thuý nga	0931822004	\N	53 đg só 19 kp 19 phường bhh 	0	2026-03-16 14:56:44.243078+00	user	\N
490	\N	Ig Đào Kha Anh Thuyên	0939839866	\N	110 Bà Hạt quận 10	0	2026-03-16 17:10:50.007067+00	user	\N
491	\N	Quốc Đại Minh Châu	0975865887	\N	262/26/3 Lũy Bán Bích, phường Hòa Thạnh, Quận Tân Phú, tp HCM	0	2026-03-17 05:22:12.714124+00	user	\N
492	\N	Ig ytwying 	0915559528	\N	Crowne Plaza Danang City Centre\n17 Quang Trung Street\nHai Chau I Ward, Hai Chau District\nDa Nang 550000\nVietnam	0	2026-03-17 12:52:15.908414+00	user	\N
493	\N	Ig v.aa.n	0889384808	\N	19 đường 11, KĐT Vạn Phúc, Phường Hiệp Bình Phước, TP Thủ Đức, TP.HCM	0	2026-03-17 12:54:36.947607+00	user	\N
494	\N	Ig phors	 098439373	\N	📍 301 Phạm Ngũ Lão, Phường Phạm Ngũ Lão, Quận 1, Hồ Chí Minh, District 1	0	2026-03-17 12:56:20.168037+00	user	\N
495	\N	Ig nguyễn nam phương 	0788089773	\N	Số 4- khu tập thế 5 tầng- ngõ 92 cửa bắc- quán thánh- ba đình - hanoi( k liên lạc dc thì gọi Zalo nh	0	2026-03-17 12:56:53.722134+00	user	\N
496	\N	Ig pho lâu tùm lum	0971883190	\N	232/12 Nguyễn Thượng Hiền, phường 5, Phú Nhuận, Tp HCM	0	2026-03-17 12:57:24.272341+00	user	\N
497	\N	Ig V	0938886869 	\N	58/14/77 đường số 4 phường bình hưng hoà A quận bình tân	0	2026-03-17 12:58:46.763865+00	user	\N
498	\N	Ig an an	0789440224	\N	68 phạm thị liên , phường kim long , huế	0	2026-03-17 12:59:09.897996+00	user	\N
499	\N	Ig nhu quynh	0349355535	\N	38 Mai Anh Đào, phường 8, Đà Lạt	0	2026-03-17 13:00:05.201487+00	user	\N
500	\N	Ig glo	0703685858	\N	14 đường 6 p.Bình Trưng (Bình Trưng Đông cũ) TpHCM 	0	2026-03-17 13:00:33.648883+00	user	\N
501	\N	IG YẾN BẮP	0384388532	\N	399/7 nguyễn đình chiểu khu phố 26, phường bàn cờ 	0	2026-03-17 13:02:56.546316+00	user	\N
502	\N	Ig ddanthnhahh	0932989120	\N	90 đường 77 Tân Quy Quận 7 nha	0	2026-03-17 13:04:28.298322+00	user	\N
503	\N	Quỳnh Giao	0946942767	hqunhgiao.18@gmail.com	Sarina Block C, Đường B2	0	2026-03-17 14:50:01.988834+00	user	\N
504	\N	Ig võ oanh vũ	0935096199	\N	Tòa T3, chung cư masteri thảo điền	0	2026-03-17 15:35:13.947595+00	user	\N
505	\N	Trang Tran	096 4155465	thithutrang11@gmail.com	6 Nguyen Khac Hieu	0	2026-03-17 17:24:54.421281+00	user	\N
506	\N	Minh Thơ	0906870356	ngthminhtho253@gmail.com	1 Lê Hiến Mai, Phường Thạnh Mỹ Lợi, Thủ Đức, Thành phố Hồ Chí Minh	0	2026-03-18 02:48:02.034717+00	user	\N
507	\N	Ig ngocnhii_zt	(+84) 818 613 364	\N	D-72 Tái Định Cư Kp10 Phú Quốc Phường Dương Đông, Thành Phố Phú Quốc, Kiên Giang	0	2026-03-18 03:10:40.773537+00	user	\N
508	\N	Ig minieeeee	0904177271	\N	C13/26 tôn đản phường 13 quận 4	0	2026-03-18 03:11:06.070091+00	user	\N
509	\N	Ig qingyi8802	0396504228 	\N	Số 51, ngõ 31, B6 Khu nhà ở Mai Dịch, đường Nguyễn Khả Trạc, Phường Phú Diễn, Thành phố Hà Nội, Việt Nam (phường Mai Dịch, Cầu Giấy cũ)\nNgười nhận: JM TQ\n	0	2026-03-18 03:11:41.734496+00	user	\N
510	\N	Ig qingyi8802	0962875123 	\N	85 Hàng Bạc Hoàn Kiếm Hà Nội	0	2026-03-18 03:12:09.797715+00	user	\N
511	\N	ig miuiuuuuu_00	0962875123	\N	Địa chỉ giao hàng\n85 Hàng Bạc Hoàn Kiếm Hà Nội	0	2026-03-18 03:14:56.641835+00	user	\N
512	\N	Ig trang lê	0932506553	\N	No 99/18-18A , Nguyen Thai Binh Street, Ward 4, District Tan Binh, TP. Hồ Chí Minh	0	2026-03-18 04:05:54.453503+00	user	\N
513	\N	Thuy Dat	0862728912	freakkymelly@gmail.com	P2 Pavilion Vinhomes Ocean Park	0	2026-03-18 09:59:31.902809+00	user	\N
514	\N	Ig katie nguyen 	0915043806	\N	321/1 Quốc lộ 1 phường 4, TP Tân An, Long An	0	2026-03-18 13:00:53.804096+00	user	\N
515	\N	Ig thriftwith	0765488828	\N	ទីតាំងឃ្លាំងទទួលទំនិញនៅវៀតណាម \n\nលេខឃ្លាំង៖ \n154 tuệ tĩnh p12 q11 tphcm VTV To Cambodian Monyrothna Leng TKK 067234568   Postal code  : 72600	0	2026-03-18 13:01:27.579811+00	user	\N
516	\N	Ig hoàng lê kim	0934034199 	\N	37 hoa sứ phường cầu kiệu tphcm	0	2026-03-18 13:01:56.125605+00	user	\N
517	\N	Ig chib.bong	0794999769	\N	21b bùi thị xuân phường bến thành quận 1	0	2026-03-18 13:02:37.812588+00	user	\N
518	\N	Ig chang chang	0904467252	\N	Địa chỉ: 220/85/2 Hoàng Hoa Thám, Phường 5, quận Bình Thạnh, TP.HCM	0	2026-03-18 13:04:02.108788+00	user	\N
519	\N	Ig N	0818891141	\N	12 Đặng Như Mai, phường Phước Mỹ, tp. Phan Rang-Tháp Chàm, tỉnh Ninh Thuận	0	2026-03-18 13:31:21.789313+00	user	\N
520	\N	Ig nina	0906852624	\N	633 ấp 1 Nguyễn Văn Tạo Hiệp Phước Nhà Bè HCM\n	0	2026-03-18 13:31:51.740572+00	user	\N
521	\N	Ig liêu thị thanh ngân	0819717639 	\N	53 thủ khoa huân p1 mỹ tho	0	2026-03-18 13:36:23.952292+00	user	\N
522	\N	Lin Shihhan 	0903665872	\N	D12A-07 Midtown M7	0	2026-03-18 14:45:23.302788+00	user	\N
523	\N	Ig hồng trâm	(+84) 787 726 763	\N	15/3, Trần Hưng Đạo\nPhường 6, Thành Phố Mỹ Tho, Tiền Giang	0	2026-03-18 16:45:20.37297+00	user	\N
524	\N	Ig hellokittybby_x	0936058181	\N	243 Vành đai trong, P. Bình trị đông B, bình tân	0	2026-03-18 16:45:53.731129+00	user	\N
525	\N	Ig nhung hi	0337126660	\N	Ấp 2 phước bình long thành đồng nai	0	2026-03-18 16:50:14.505639+00	user	\N
526	\N	Ig onlykitty.ty	0778683355	\N	A4.23 kdc cotec phú xuân nhà bè	0	2026-03-19 03:39:54.031045+00	user	\N
527	\N	Ig dpt_232 	0364565231 	\N	35 trục chính tam hiệp - phúc thọ - HN	0	2026-03-19 03:40:21.759269+00	user	\N
528	\N	Ig thuỳ trang 	0912287577 	\N	39 dương văn đồng hới quảng trị	0	2026-03-19 03:45:11.002338+00	user	\N
529	\N	Trân	0853273175	Vohoangbaotran971@gmail.com	421 Trần Xuân Soạn phường Tân Kiểng quận 7	0	2026-03-19 08:00:16.395995+00	user	\N
530	\N	Ig fairy	 0906082741	\N	Địa chỉ số 7 đường 46 phường 2 quận 4	0	2026-03-19 10:41:51.694575+00	user	\N
531	\N	Ig chakriya meun	0708163707	\N	Street:  177c, Đường Số 1, P Bình Hưng Hòa B, Q Bình Tân, Hồ Chí Minh\nKHE1600108	0	2026-03-19 10:42:17.290254+00	user	\N
532	\N	Ig rlrde9	0363485698	\N	30 Đường Nguyễn Hữu Cảnh, Bình Thạnh, Thành phố Hồ Chí Minh 700000	0	2026-03-19 10:43:25.285874+00	user	\N
533	\N	Ig jie71104	0931393787	\N	07 Thai Dương-Phường Thuận An-Tp Huế	0	2026-03-19 15:54:36.133462+00	user	\N
534	\N	Ig thanh	0357361236	\N	đchi: 5/73e nguyễn hữu cảnh, phường an tây , huế\n	0	2026-03-19 15:55:06.721479+00	user	\N
535	\N	Ig nn.ricci	0985561610 	\N	46-46Bis Thủ Khoa Huân, Street, Quận 1 	0	2026-03-19 16:59:41.196164+00	user	\N
536	\N	Châu Ngọc Thảo Uyên	0902574509	uyenthxo209@gmail.com	25 hồ thành biên	0	2026-03-20 03:25:30.576981+00	user	\N
537	\N	Ig tú hoàng	0933474541	\N	Nguyen huu hao p9 q4	0	2026-03-20 03:41:06.924321+00	user	\N
538	\N	Ig gonnyne	0912562355	\N	19/22 nam kỳ khởi nghĩa , p1 , đà lạt ( nhà số 68 đối diện ) 	0	2026-03-20 12:27:01.92443+00	user	\N
539	\N	Ig mỹ linh	0343389986	\N	397 lê lợi, ngô quyền, hp\nNg nhận: mỹ linh	0	2026-03-20 12:27:37.09809+00	user	\N
540	\N	Ig pee pov 	0935906826	\N	Hẻm 114 năm châu phường 12 quận tân bình tp hcm\nThuỷ Tiên	0	2026-03-20 12:28:54.280866+00	user	\N
541	\N	Ig linh chu	0347070305	\N	Tổ 19 KDL thác Prenn phường 03 Đà Lạt	0	2026-03-20 12:29:36.969553+00	user	\N
542	\N	Ig quin	0935185706	\N	Lô C2 chung cư Nguyễn đinh chiểu, Dakao \nSđt: 0935185706 ( Ngân)	0	2026-03-20 12:31:09.511625+00	user	\N
543	\N	Ig hoàng anh pmha	0916168968	\N	09 Nguyễn Hữu Huân\nPhường Nha Trang\n	0	2026-03-20 12:35:09.738982+00	user	\N
544	\N	Ig shanwydd	65 88763319 	\N	107 /16 Trương Định, Phường 6, Quận 3, Hồ Chí Minh, Vietnam\nRoom 113, under Arno Anton	0	2026-03-20 12:37:15.70757+00	user	\N
545	\N	Ig beiu_pass	0373678242	\N	150 đội cấn, ba đình, hà nội\n	0	2026-03-21 04:40:45.683341+00	user	\N
546	\N	Ig trần hồng ân	 0932393943	\N	Địa chỉ: 346/7/34/2 Khu phố 1,    Phường Tân Hoà, Tp. Biên Hoà, Đồng Nai	0	2026-03-21 04:41:26.050729+00	user	\N
547	\N	Ig b.thehappyyou 	0909966195 	\N	Sunshine diamond river\n422 đào trí phú thuận quận 7	0	2026-03-21 04:41:56.072314+00	user	\N
548	\N	Thy Thy	0933945837	\N	35/6 đường TMT9	0	2026-03-21 05:33:02.811908+00	user	\N
550	\N	Ngân	0915249585	ngocngan25899@gmail.com	2/27a cao thắng	0	2026-03-21 11:34:00.416687+00	user	\N
551	\N	test preorder	0979911679	thiemd779@gmail.com	15 NXK	0	2026-03-21 12:59:16.225298+00	user	\N
552	\N	test preorder 2	0978564302	\N	15 NXK	0	2026-03-21 13:00:17.867857+00	user	\N
553	\N	Lương Huyền Trâm	0778063851	\N	566/99 nguyễn thái sơn p6 gò vấp	0	2026-03-21 13:12:24.5717+00	user	\N
554	\N	test preorder	0978563489	thiemd779@gmail.com	15 NXK	0	2026-03-21 13:13:00.68516+00	user	\N
555	\N	Nguyễn Trần Lan Anh 	0919799472	anh.lannt153@gmail.com	123 Nguyễn Chích	0	2026-03-21 13:28:04.219467+00	user	\N
556	\N	Ig Lauren Brown 	+1 2897833327	\N	4814 King St, Beamsville, ON L3J 0N5\nEmail: lauren.brown14@live.co.uk	0	2026-03-21 13:50:39.26996+00	user	\N
557	\N	Ig sandie 	0368606295	\N	67 nguyễn thị minh khai, bến thành\n	0	2026-03-21 14:01:28.891103+00	user	\N
558	\N	Ig jenny	0586898742	\N	283 bến vân đồn q4	0	2026-03-21 14:02:57.303802+00	user	\N
559	\N	Đặng Phương Thảo	0373334772	anna.wilson1177@gmail.com	Số 1 ngách 42/3 đường Nguyễn Đổng Chi, Nam Từ Liêm, Hà Nội	0	2026-03-21 16:47:34.955368+00	user	\N
560	\N	Trương Tuyết Vy	0941659865	tuyetvya3pcd@gmail.com	174/6 Lê Lai	0	2026-03-22 09:50:26.674534+00	user	\N
565	\N	Ig maize	+84) 979 528 244	\N	Bcons Green Topaz Đường Tôn Thất Tùng, Phường Đông Hòa, Thành Phố Dĩ An, Bình Dương	0	2026-03-22 16:16:44.64037+00	user	\N
566	\N	Ig yen.nhune	0779676550	\N	63a điện biên phủ, phường 2, quận bình thạnh ( chung cư ngân hàng ACB ) 	0	2026-03-22 16:17:10.596223+00	user	\N
549	abf51b62-af78-4c58-a807-d4df6658a337	Jisu Yi	+821085861517	jisuyi0105@gmail.com		0	2026-03-21 08:41:55.94551+00	user	\N
561	9e52976c-4406-4e74-a702-e51cd0c6a530	Don THi Thuy Tien	0389580786	linhtinhcuatien@gmail.com	\N	0	2026-03-22 13:40:01.20083+00	user	\N
562	\N	Khánh Băng	0327161600	ngantran224310410.dlsg@gmail.com	29A Lương Minh Nguyệt	0	2026-03-22 15:08:26.310819+00	user	\N
563	\N	Hồng Cẩm	0948290496	camdh96@gmail.com	49 Trường Sơn	0	2026-03-22 15:12:29.376986+00	user	\N
564	\N	Ig lăng quỳnh 	0393349698	\N	Địa: 122 Trung Hòa, phường Yên Hòa, thành phố Hà Nội, Việt Nam\n	0	2026-03-22 16:13:49.479529+00	user	\N
567	\N	Ig irene	0967117904	\N	Địa chỉ: số 297, ấp 4, Phước Lợi, Bến Lức, Long An ( Tây Ninh mới)	0	2026-03-22 16:17:34.556781+00	user	\N
568	\N	Ig ái nhung	(+84) 777512322	\N	Quan Tan Binh\nPhường 2\n25/21, Đường Cửu Long	0	2026-03-22 16:20:16.359684+00	user	\N
569	\N	Ig vani 	+0328504510	\N	tổ 29-kp.gia huỳnh -p trảng bàng -tây ninh, Phường Trảng Bàng, Thị Xã Trảng Bàng, Tây Ninh	0	2026-03-22 16:22:26.632504+00	user	\N
570	\N	Kiều Chinh	0971325517	kieuchinh1604@gmail.com	Cc Đông Hải	0	2026-03-23 01:43:01.205688+00	user	\N
571	\N	LANGLANG 	0987409832	ylingyidan@gmail.com	11/543 Nguyen Trai St. • 11( cạnh 15A)  Ngõ 543 Nguyễn Trãi, P.Thanh Xuân Nam	0	2026-03-23 03:34:59.365422+00	user	\N
572	\N	Jeongbeen Seo	+82 1087573181	\N	jbeen030@naver.com\n\nAddress\n-State/Province: Seoul\n-City: Songpa-gu\n-House number / Street name: Room 318, 3F, Sangsang Class Jamsil Branch, 18-23, Olympic-ro 32-gil\n-Zip code:05548	0	2026-03-23 15:57:19.187619+00	user	\N
573	\N	Ig t.laneflow	0368086824	\N	Tecco, 6-8 Nguyễn Thiện Thuật, phường Bình Thạnh, Tp HCM\nRoom : 203	0	2026-03-23 16:00:31.122984+00	user	\N
574	\N	Ig thanh ngan 	0909205514	\N	17/1 phan đình thông phường an lạc, bình tân	0	2026-03-23 16:13:01.263809+00	user	\N
575	\N	Ig KVK 	0786442110	\N	151/5E hàn hải nguyên p.2 q11\nNg nhận: Thịnh Trương	0	2026-03-23 16:13:26.856305+00	user	\N
576	\N	Ig zina	0949935669	\N	Số 7 năm châu tân bình hcm	0	2026-03-23 16:13:45.04942+00	user	\N
577	\N	Ig ng ot	0794700757 	\N	1468 ấp 1 xã đạo Thạnh thành phố Mỹ tho tỉnh tiền Giang 	0	2026-03-23 16:15:54.207818+00	user	\N
578	\N	Ig gem gem	 0971994048	\N	Chung cư carillon 7 - số 33 lương minh nguyệt , phường tân thới hoà , quận tân phú	0	2026-03-23 16:16:33.866074+00	user	\N
579	\N	Ig bailey 	0357118521	\N	298/28 nơ trang long, p.12, q. Bthanh	0	2026-03-23 16:17:07.990241+00	user	\N
580	\N	Triệu Minh	0905237120	trieuminh13199@gmail.com	148 Nguyễn Thị Minh Khai	0	2026-03-23 17:55:49.468447+00	user	\N
581	\N	Jialina.sb	(+84) 866 641 535	\N	Nhà Nghỉ Thanh Trà 2, Ngách 20/105 Doãn Kế Thiện Phường Mai Dịch, Quận Cầu Giấy, Hà Nội\n	0	2026-03-24 05:25:19.312271+00	user	\N
582	\N	Ig followdao2222	 0399749576	\N	Đchi: 29 trần nguyên hãn, phường đông thọ, thành phố thanh hoá	0	2026-03-24 05:25:50.14511+00	user	\N
583	\N	Ig tiên tiên	0948627026	\N	Block B2, Chung cư Boulevard, đường Nguyễn Lương Bằng, Phường Phú Mỹ, Quận 7, Thành phố Hồ Chí Minh.	0	2026-03-24 05:26:19.326194+00	user	\N
584	\N	Thuỳ anh	0968953341	thuyanhphanq123@gmail.com	25/27 Trương Văn Thành, Phường Hiệp Phú, Thành phố Thủ Đức, Thành phố Hồ Chí Minh	0	2026-03-24 12:27:34.964196+00	user	\N
585	\N	Ig huỳnh ngọc bảo ngân	0909676790	\N	87/2E Trung Mỹ Tây, Trung Chánh, Hóc Môn, Tp.HCM\n	0	2026-03-24 13:18:30.85162+00	user	\N
586	\N	Ig n zy	0363760545	\N	44 nguyễn trọng trí, phường an lạc a, quận bình Tân	0	2026-03-24 13:19:24.330838+00	user	\N
587	\N	Ig van le	0919880890	\N	S6 office 02-14 The sun avenue, \n28 mai chí thọ, an phú, thủ Đức	0	2026-03-24 13:21:26.790918+00	user	\N
588	\N	Ig aiden.C 	0965592198	\N	19 hồ tùng mậu, mai dịch, cầu giấy hn\n	0	2026-03-24 13:45:03.007929+00	user	\N
589	\N	Mai Hương	0898215310	huongtee39@gmail.com	222 Pasteur	0	2026-03-24 16:26:33.502975+00	user	\N
590	\N	Nguyễn Ngọc Bảo Trân 	0393788221	baotran.joellenguyen12@gmail.com	165-167 Phan Đình Phùng 	0	2026-03-25 05:44:18.969804+00	user	\N
591	\N	Ig phirun	0906.984.493	\N	275/14B1 Đặng Nguyên Cẩn, Phường Phú Lâm, TP. Hồ Chí Minh	0	2026-03-25 12:55:05.519214+00	user	\N
592	\N	Ig tran thi my tuyen	0938603662	\N	Chung cư The Grande M5 Midtown\nĐường số 16, P Tân Phú, Q7 tphcm (Block A, Căn A18.11) (Đc cũ)	0	2026-03-25 12:55:43.353121+00	user	\N
593	\N	Ig tracy vo	0766865000	\N	Tổ dân phố yên trung ,phường yên sơn ninh bình	0	2026-03-25 12:56:03.691488+00	user	\N
594	\N	Ig kim anh tran 	0336585212	\N	98 Cồn Dầu 19, phường Hoà Xuân, TP Đà Nẵng\nKOL TẶNG ĐỒ	0	2026-03-25 12:56:54.474537+00	user	\N
595	\N	Ig yeeling18_ 	 0178763508	\N	15 Jalan Batu Nilam 26 Bandar Bukit Tinggi 2 Klang Selangor Malaysia 	0	2026-03-25 12:57:49.119249+00	user	\N
596	\N	Ig yeeling18_ 	0178763508	\N	15 Jalan Batu Nilam 26 Bandar Bukit Tinggi 2 Klang Selangor Malaysia 	0	2026-03-25 12:58:52.235925+00	user	\N
597	\N	Ig im4iden	0397317719	\N	104 lê trọng tấn , tây thạnh , tân phú \n	0	2026-03-25 12:59:35.40444+00	user	\N
598	\N	Ig grace thường	0586670080	\N	58 Quốc Hương, B08.06, Thao Dien	0	2026-03-25 13:00:07.467167+00	user	\N
599	\N	Ig yogingngoc_1908	0975557678	\N	34/4/1 nguyễn thị huê đông lân bà điểm hóc môn	0	2026-03-25 13:00:31.742634+00	user	\N
600	\N	Ig khả dinh 	0838121036 	\N	Công ty Phú Thành, Xã Vĩnh Hải, Tp Sóc Trăng	0	2026-03-26 12:07:56.796416+00	user	\N
601	\N	Ig huonghtnt	0389069723	\N	TDP Hải Thế, Phường Phong Quảng, Thành Phố Huế	0	2026-03-26 12:08:33.905526+00	user	\N
602	\N	ig Amy Lupercio 	(425)263-7069	\N	\n1235 E 43rd St Los Angeles, CA \n90011\nsuppamyyy@gmail.com	0	2026-03-26 12:16:13.02557+00	user	\N
603	\N	Ig _beebowwbeww_	0388874407	\N	18 Nguyễn văn trỗi, phường Tân An, thị xã La Gi, Tỉnh Bình Thuận	0	2026-03-26 12:17:26.290603+00	user	\N
604	\N	Ig trần ngọc quyên	0924686789	\N	245/30F Bình Lợi p13, bình thạnh.	0	2026-03-26 12:18:17.393449+00	user	\N
605	\N	Ig do thi thuy trang	0987838370	\N	263/11 lê văn việt phường hiệp phú quận 9 ( phường mới tăng nhơn phú )	0	2026-03-26 12:19:06.71588+00	user	\N
606	\N	Tran phuong sol	0363331143	\N	87 Nguyễn Cơ Thạch , kdt Sala, p An Khánh	0	2026-03-26 12:19:33.340566+00	user	\N
607	\N	Ig lynn	0947704089	\N	41F/25, Đ. Đặng Thuỳ Trâm, Phường 13, Bình Lợi Trung, Hồ Chí Minh 700000	0	2026-03-26 12:20:16.995615+00	user	\N
608	\N	Ig 9pass99	038869989	\N	Chung cư Grand Riverside , 283 Bến Vân đồn , Phường 2 , Q4, HCM 	0	2026-03-26 12:20:40.441947+00	user	\N
609	\N	Ig pham hong phuong	0942388188	\N	572/12/4 âu cơ p10 tân bình hcm	0	2026-03-26 13:09:04.632582+00	user	\N
610	\N	Ig đàm trang	0355094855	\N	B1104, Toà B Udic Complex Hoàng Đạo Thuý, Trung Hoà, Hà Nội	0	2026-03-26 14:33:15.985099+00	user	\N
611	\N	Ig duong	0962522440	\N	290/34/12 đường hiệp thành 13 quận 12 , phường tân thới hiệp	0	2026-03-26 16:35:39.337911+00	user	\N
612	\N	Ig ngoc anh	0964989250	\N	275 Nguyễn Trãi- Thanh Xuân - Hn 	0	2026-03-26 16:36:57.315527+00	user	\N
613	\N	Hoàng Thư	0918158185	thuhoag12345678@gmail.com	87B/17 Kp1	0	2026-03-26 19:00:27.941335+00	user	\N
614	\N	Nguyễn Kim Hoàng Hà 	0965584096 	ilovebanhmino.1@gmail.com	Số 14 ngõ 217, định công thượng, hoàng mai, hà nội	0	2026-03-27 04:26:36.559808+00	user	\N
615	\N	Ig p.khmyy	0988668664	\N	19 hùng duệ vương , hồng bàng hải phòng 	0	2026-03-27 12:12:31.301319+00	user	\N
616	\N	Ig Lquinn	0369236444	\N	203/19/2 hẻm hàm nghi phường duy tân tp kontum 	0	2026-03-27 12:13:33.903424+00	user	\N
617	\N	 Ig dieuryu76	0943071567	\N	Xóm 4, xã xuân tiến, huyện Xuân trường, tp Nam định	0	2026-03-27 12:14:38.381233+00	user	\N
618	\N	Ig hari lăng quăng	0982650780	\N	chợ quảng sơn , ninh sơn ninh thuận	0	2026-03-27 12:15:13.496041+00	user	\N
619	\N	0969178898	Ig trang vy	\N	P503, số 6 Nguyễn Công Hoan, Ngọc Khánh, Ba Đình, Hà Nội (Chung cư Platinum)	0	2026-03-27 12:16:42.009567+00	user	\N
620	\N	Ig thục yến	0938859589	\N	85B bà hom p13 q6	0	2026-03-27 12:17:11.281297+00	user	\N
621	\N	0764506174	Ig win	\N	50 lê thiện trị , hoà hải , ngũ hành sơn đà nẵng	0	2026-03-27 12:17:46.085003+00	user	\N
623	\N	Ig khánh linh	0824097890	\N	56A Ng. 619 Vũ Tông Phan Khương Đình Thanh Xuân Hà Nội 	0	2026-03-27 12:18:36.741999+00	user	\N
622	\N	Ig kim anh	0775036405	\N	290/51/36a Nơ Trang Long p12 quận Bình Thạnh	0	2026-03-27 12:18:14.493049+00	user	\N
626	\N	Nguyễn Anh Thư	0913969687	anhthung2011@gmail.com	78/22/35 Tôn Thất Thuyết	0	2026-03-27 13:14:56.183958+00	user	\N
627	\N	Rose Rosalie	 0898650608	\N	Hotel: CityHouse - Nest DC\n361/12 Nguyễn Đình Chiểu,\nPhường 5, Bàn Cờ, Hồ Chí Minh\n700000\nRoom:101 \nName: Rose Rosalie	0	2026-03-27 13:57:42.351528+00	user	\N
628	\N	Ig rose	(+84) 902 456 158	\N	Tháp Hawaii - Đảo Kim Cương (H0507), Phường Bình Trưng Tây, Thành Phố Thủ Đức, TP. Hồ Chí Minh	0	2026-03-27 14:43:07.239723+00	user	\N
629	\N	Hoàng Oanh	0866063740	oanhnvh0311@gmail.com	1163/16 Lê Đức Thọ phường 13 quận Gò Vấp	0	2026-03-27 18:00:54.522957+00	user	\N
630	\N	Ig my võ 	 0939806696	\N	696 Trần Hưng Đạo, p.2, Q.5, tp.hcm	0	2026-03-28 04:13:45.311984+00	user	\N
631	\N	Fifi Kuan	‪+84 90 622 92 35‬ ‬	fifikuan0427@gmail.com	63a Đ. Nguyễn Cừ	0	2026-03-28 04:43:33.689377+00	user	\N
632	\N	Ig thi	 0334407364	\N	261/40/2, Chu Văn An, Phường 12, Quận Bình Thạnh, TP. Hồ Chí Minh\n	0	2026-03-28 04:51:30.652843+00	user	\N
633	\N	Ig camii.ng 	0374440182	\N	64 Trung tả ,văn miếu quốc tử giám hà nội \nSđt : 0374440182\nTên : Thảo vân	0	2026-03-28 05:18:51.635998+00	user	\N
634	\N	Vân Anh	0964102004	blva0410@gmail.com	161/31/28 đường Đông Hưng Thuận 02, khu phố 62	0	2026-03-28 07:05:50.073975+00	user	\N
635	87ad1663-1bba-4a3c-b739-dcfac531246c	Vân Anh	0964102004	blva0410@gmail.com	\N	0	2026-03-28 07:10:02.983671+00	user	\N
636	\N	Ig _neverchaseabitch_00	0827405569	\N	 ccmn 1092 nguyễn khoái, thanh trì, hoàng mai, hà nội ạ\n	0	2026-03-28 09:32:07.342239+00	user	\N
637	\N	Ig như thảo	0392178841 	\N	461/16 Hải Phòng, P. Chính Gián, Q.Thanh Khê, TP Đà Nẵng	0	2026-03-28 09:32:37.157426+00	user	\N
638	\N	ig J.	 0907867994 	\N	Block B eco green q7 nha ạ	0	2026-03-28 09:33:15.152568+00	user	\N
639	\N	Ig tú an / sapo	0348893881	\N	33 lê minh xuân p7 tân bình	0	2026-03-28 09:34:11.468277+00	user	\N
640	\N	ig Lê hồng bảo trân / sapo	0844488829	\N	277 Võ Nguyên Giáp, An Phú, An Khánh, Hồ Chí Minh 70000\neast tower 2907\n	0	2026-03-28 09:35:04.299481+00	user	\N
641	\N	Ig anh.trn / sapo	0348284747	\N	525/15 Quang Trung, P10 Gò Vấp\nNgọc Anh	0	2026-03-28 11:30:58.479945+00	user	\N
642	\N	Ig tuyết linh / sapo	 0358476051	\N	217/70/35 bùi đình tuý,p24, bình thạnh, HCM	0	2026-03-28 11:32:02.062656+00	user	\N
643	\N	Ig NT phương thảo	0916240805	\N	Xóm 13 vĩnh trà nam\nTrung tiền hải thái bình	0	2026-03-29 11:50:41.781076+00	user	\N
644	\N	Ig huy lâm	0938144013	\N	73/18 huynh van banh\nP17 phu nhuan	0	2026-03-29 11:54:55.543891+00	user	\N
645	\N	Ig kimberly nguyễn	0939968676	\N	422 võ văn kiệt, phường cầu ông lãnh q1.	0	2026-03-29 11:56:27.111045+00	user	\N
646	\N	Ig nancy do	0397135528	\N	 67B đường T5, phường Tây Thạnh, quận Tân Phú	0	2026-03-29 11:59:29.556932+00	user	\N
647	\N	Ig minh ngọc	‭‭+84 38 4045461‬‬	\N	Ấp tân hiệp A, thị trấn Óc Eo, huyện Thoại Sơn, tỉnh An Giang	0	2026-03-29 12:00:38.988644+00	user	\N
648	\N	Ig hoàng lan anh	0966079275	\N	Số 35 ngách 123/41 Xuân Phương, Phương Canh, Nam Từ Liêm, Hà Nội	0	2026-03-29 12:36:17.409327+00	user	\N
649	\N	Ig _klhm	+886 928273350	\N	9-23 Lam Son Square, Bến Nghé, Sài Gòn, Hồ Chí Minh, Vietnam	0	2026-03-29 12:37:54.917252+00	user	\N
650	\N	Ig trâm lê	0389717351	\N	80/3 phan đình phùng pleiku gia lai \n	0	2026-03-29 12:38:16.253641+00	user	\N
651	\N	Ig cao nguyen dang khoa/ sapo	0942879351	\N	429 Hoàng Hữu Nam Long Bình TP. Thủ Đức	0	2026-03-29 12:39:01.406088+00	user	\N
652	\N	Ig prv.sushiwasabi	0919686592	\N	•Chung cư Tây Đô plaza , Xã Tân Phú Thạnh, Huyện Châu Thành A, Hậu Giang	0	2026-03-29 12:39:37.631641+00	user	\N
653	\N	Ig myoiw	0336323793	\N	41/1 trần hưng đạo, p6 , thành phố mỹ tho\n	0	2026-03-29 12:40:04.732965+00	user	\N
654	\N	Ig uyenahh	0979879425	\N	204/3B Cao Đạt F1 Q5 HCM	0	2026-03-29 12:41:55.834774+00	user	\N
655	\N	Ig vũ thị kiều trinh / Sapo	0835116169	\N	39 Bến Vân Đồn, Phường 13, Quận 4, Hồ Chí Minh\nChung cư The Tresor \nSảnh Ap1 2806	0	2026-03-29 12:50:22.033256+00	user	\N
656	\N	Ig yến nhi	0386683498	\N	17/9 đường 59 phường thảo điền quan 2\nIg yến nhi\n17/9 đường 59 phường thảo điền quan 2\n	0	2026-03-29 12:50:52.580541+00	user	\N
657	\N	Ig yeolan	0974250498 	\N	Chung cư Pegasuite 2, 1079 tạ quang bửu, p6, q8, HCM	0	2026-03-29 12:56:05.257506+00	user	\N
658	\N	Ig doanvananhh	0967 771 771  	\N	50/6 khu phố 2, đường Bà Triệu, Hóc Môn ( hẻm đối diện HD bank) \nSdt 0967 771 771  (Huy)\n50/6 khu phố 2, đường Bà Triệu, Hóc Môn ( hẻm đối diện HD bank) \n\n	0	2026-03-29 12:56:40.641935+00	user	\N
659	\N	Ig nguyễn kim huệ	0903029673	\N	số 71 đường số 3 phường an khánh tp thủ đức ( quận 2 )\n	0	2026-03-29 12:57:22.349546+00	user	\N
660	\N	Ig mai thanh	0528593977 	\N	Đường 27 giữa ngã tư số 8 và 10. Nhà tuyền đồ mỹ Xã Nghĩa Thành, Huyện Châu Đức, Bà Rịa Vũng Tàu	0	2026-03-29 13:02:06.984221+00	user	\N
661	\N	Ig kim hạnh	0339418412	\N	300/23/21 Đường Nguyễn Văn Linh, Bình Thuận, Quận 7, Thành phố Hồ Chí Minh	0	2026-03-29 13:02:53.601525+00	user	\N
662	\N	Ig lee's house 	0904002200	\N	 Đường 21, thôn Vinh Sơn xã Nghĩa Thành huyện Châu Đức tỉnh Bà Rịa Vũng Tàu	0	2026-03-29 13:19:16.119429+00	user	\N
663	\N	Như Quỳnh	0979929540	quynhquynhcutie@gmail.com	55/4 Phan Đình Phùng	0	2026-03-29 13:49:11.270161+00	user	\N
664	\N	Huỳnh Ngọc Mai Lâm	0764466036	huynhngocmailam@gmail.com	144/11A đường số 9	0	2026-03-29 17:06:09.364844+00	user	\N
665	\N	test	097991170	\N	15 nxk	0	2026-03-30 10:52:20.584914+00	user	\N
666	\N	Nguyễn Ngọc Mai	0385418958	nnm2109001@gmail.com	Cổng làng đình cả 	0	2026-03-30 12:58:44.275155+00	user	\N
667	\N	Ig mai thanh	0528593977	\N	Đường 27 giữa ngã tư số 8 và 10. Nhà tuyền đồ mỹ Xã Nghĩa Thành, Huyện Châu Đức, Bà Rịa Vũng Tàu	0	2026-03-30 14:07:52.369857+00	user	\N
668	\N	Ig foundnotfound101	0394999300	\N	Toà West - Lumiere Riverside, Số 2, Võ Trường Toản, Phường An Phú, Thành Phố Thủ Đức, TP. Hồ Chí Minh	0	2026-03-30 14:08:55.871343+00	user	\N
669	\N	Ig thảo vy / Sapo	0975921045 	\N	363/46 Đinh Bộ Lĩnh p26 Bình thạnh\n	0	2026-03-30 14:10:03.247736+00	user	\N
670	\N	Ig minh thư	0902905362	\N	114 đồng văn cống, phường cát lái, hcm	0	2026-03-30 14:10:46.089316+00	user	\N
671	\N	Ig mliinhh	0943870098	\N	Địa chỉ: 56a Ngõ Yết Kiêu, Cửa Nam, Hoàn Kiếm, Hà Nội 11000	0	2026-03-30 14:11:16.031157+00	user	\N
672	\N	Ig mai my anh / Sapo	0938469019	\N	44 Trần Văn Danh p13 Quận Tân Bình TPHCM	0	2026-03-30 14:13:02.717766+00	user	\N
673	\N	Ig hoàng long	0913733636	\N	305A Lý Thường Kiệt P15 Q11	0	2026-03-30 14:13:41.335564+00	user	\N
674	\N	Ig minh anh pham thi	0393603214	\N	số 4 ngách 36 ngõ 12 nguyễn văn trỗi, phương liệt, thanh xuân, hà nội 	0	2026-03-30 14:17:03.950577+00	user	\N
675	\N	Ig mei mei Kol tặng đồ	0984729933	\N	Toà Landmark Plus ,Vinhomes Central Park, 720A Điện Biên Phủ, phường Thạnh Mỹ Tây, thành phố Hồ Chí Minh	0	2026-03-30 14:23:07.611765+00	user	\N
676	\N	Ig aaliyahanhkieu / sapo	0704471334 	\N	12/1/25 đặng minh trứ, tân bình	0	2026-03-30 14:23:54.603647+00	user	\N
677	\N	Ig nguyễn thuỳ linh 	0911949101	\N	13B phạm minh Đức ngô quyền Hải phòng	0	2026-03-30 14:26:01.287108+00	user	\N
678	\N	Ig irina / Sapo	076 9468394	\N	6 Khuê Mỹ Đông 7, Khuê Mỹ, Ngũ Hành Sơn, Đà Nẵng 550000\n	0	2026-03-30 14:28:16.364811+00	user	\N
679	\N	Ig phuong anh	0859926708	\N	35 tổ 2 ấp 3 xã an thái trung, huyện cái bè ,tỉnh tiền giang \n 	0	2026-03-30 14:28:55.939158+00	user	\N
680	\N	Ig oink_pg	84 23538-89999	\N	Amina Lantana Hoi An Hotel & Spa	0	2026-03-30 14:32:02.60234+00	user	\N
681	\N	Ig katty nguyen	0388372768	\N	770 lý thái tổ, phường hoà phú, tp thủ dầu một, bình dương	0	2026-03-30 14:33:00.090641+00	user	\N
682	\N	Ig ly ha ai tran	 0939092540	\N	48/12 hẻm 1 mậu thân, phường xuân khánh, quận ninh kiều, cần thơ	0	2026-03-30 14:33:23.48077+00	user	\N
683	\N	Kol sym	0879572999	\N	Toà Parkview Residence, 152 điện biên phủ, phường 25, q.Bình Thạnh, Tp Hcm\nCăn 12A-03\n0879572999\nToà Parkview Residence, 152 điện biên phủ, phường 25, q.Bình Thạnh, Tp Hcm\nCăn 12A-03	0	2026-03-30 14:34:13.021649+00	user	\N
684	\N	Ig trần thanh thuý / sapo	0976781461	\N	Vinhome Grand Park phường Long Bình tp Thủ Đức HCM ( toà BS12)	0	2026-03-30 14:35:24.331098+00	user	\N
685	\N	Ig bmqin	0977586904	\N	Vinhomes Grand Park, The Origami - S9.01 	0	2026-03-30 14:35:51.553433+00	user	\N
686	\N	Ig khahchin_	094 2676286	\N	ct3 yên hoà parkview, 3 Vũ Phạm Hàm, Yên Hoà, Cầu Giấy, Hà Nội	0	2026-03-30 14:37:25.60795+00	user	\N
687	\N	Ig đăng vi	 0984108804	\N	39b Nguyễn Văn Linh , phường Tân Thuận Tây , quận 7 . Chung cư Eco Green block C	0	2026-03-30 15:40:51.078229+00	user	\N
688	\N	Ig tiffanywong3042	0839100901	\N	 5 Lương Ngọc Quyến, quận Hải Châu, Đà Nẵng	0	2026-03-30 15:42:47.904308+00	user	\N
689	\N	Như Ý	0367761313	nguyendonhuy301106@gmail.com	622/10 đường cộng hoà	0	2026-03-31 13:10:16.539776+00	user	\N
690	\N	Ig piedi.ary29	0947252705	\N	2 ngõ Hàng Chỉ, Hoàn Kiếm, Hà Nội	0	2026-03-31 14:17:27.160469+00	user	\N
691	\N	Ig mai thanh	035 446 8559	\N	shillamonogram đà nẵng	0	2026-03-31 14:21:20.00414+00	user	\N
692	\N	Ig ngọc nhân	0842421488	\N	số nhà 308 nguyễn văn thoại tiệm tóc rùa barber châu phú A châu đốc an giang	0	2026-03-31 14:22:28.273767+00	user	\N
693	\N	Ig đinh nguyễn nhi	0779631653	\N	Dc 1/2 tân hoà 2, phường hiệp phú, quận 9 cũ Thủ Đức	0	2026-03-31 14:23:37.028334+00	user	\N
694	\N	Ig plchmsva	0368308053	\N	Nam Nha Trang, Khánh Hòa, room 507	0	2026-03-31 14:25:58.268193+00	user	\N
695	\N	Ig như xinh lắm	0797908294 	\N	9h8 đường dd12, tân hưng thuận q.12	0	2026-03-31 14:26:28.240535+00	user	\N
696	\N	Ig jan miki	0369166222	\N	163 Đường Trương Thị Hoa, phường Tân Thới Hiệp quận 12 ,tphcm	0	2026-03-31 14:27:55.565188+00	user	\N
697	\N	Ig hoonxxd	0902906841	\N	Vinhome central 3 , nguyễn hữu cảnh 	0	2026-03-31 14:28:25.023945+00	user	\N
698	\N	Ig hai yen	0329371321	\N	Bệnh viện Sản - Nhi Bắc Ninh số 2\nĐường Huyền Quang, phường Võ Cường, Tỉnh Bắc Ninh	0	2026-03-31 14:29:09.116911+00	user	\N
699	\N	Ig krystal	0909529474	\N	Thu Tuyền 17/21a Tân Thuận Tây p Bình Thuận q7	0	2026-03-31 14:29:46.961942+00	user	\N
700	\N	Ig k.nguyene	0935167396	\N	5 Quốc sử quán, phường Đông Ba, Tp Huế	0	2026-03-31 14:30:20.77308+00	user	\N
701	\N	Ig mãi hận math bio chem	0934140424	\N	cosmo city 99 nguyễn thị thập phường tân phú quận 7 tphcm\n	0	2026-03-31 14:32:19.111381+00	user	\N
702	\N	Ig phanyen.b	0938946935	\N	822/125 hương lộ 2, bình trị đông , bình tân 	0	2026-03-31 14:33:25.137896+00	user	\N
703	\N	Ig donfetch	0876868440	\N	: 60 Đường số 46, Bình Trưng Đông, Thủ Đức, Thành phố Hồ Chí Minh, Vietnam	0	2026-03-31 14:35:21.439643+00	user	\N
704	\N	Ig phạm hoàng yến	0702639591	\N	43/4b  đường số 7,kp5, linh tây thủ đức	0	2026-03-31 14:36:20.966215+00	user	\N
705	\N	Ig nhittlam	0968081005	\N	94A phạm đình hổ p2 q6	0	2026-03-31 14:38:11.4375+00	user	\N
706	\N	Ig _emthuyy	0354468559	\N	shillamonogram đà nẵng	0	2026-03-31 14:38:57.25119+00	user	\N
707	\N	Ig succub.kyuubi	0338 796036	\N	saigon, diamond island, maldives tower, post office box number 14.09	0	2026-03-31 14:40:27.688143+00	user	\N
708	\N	Ig mongthuong.15 	0968816281	\N	Hẻm 350/17C\nLê Văn Quới , Khu Phố 80, Bình Hưng Hoà. HCM\nSdt:0968816281Hẻm 350/17C\nLê Văn Quới , Khu Phố 80, Bình Hưng Hoà. HCM	0	2026-03-31 14:42:05.929043+00	user	\N
709	\N	Ig võ hoàng an	0399955343	\N	39 đường số 2, phường Tam Phú, Tp. thủ đức\n	0	2026-03-31 15:03:12.111081+00	user	\N
710	\N	Ig duyen	0867 324 906	\N	6 nguyễn bỉnh khiêm xã liên nghĩa tỉnh đức trọng huyện lâm đồng	0	2026-03-31 15:08:24.012844+00	user	\N
711	\N	Ig fern	035 467 7196	\N	 Toà nhà Vinaconax 7\n61 Nguyễn Văn Giap , Phường Cầu Diễn \nQuận Nam Từ Liêm , Hà nội	0	2026-03-31 16:30:43.851792+00	user	\N
712	\N	Ig chemical romance 	0912020515	\N	The Ninety Complex, 90 Đ. Láng, Ngã Tư Sở, Đống Đa, Hà Nội	0	2026-03-31 16:31:26.230037+00	user	\N
713	\N	Ig kim ngânn	0972587185	\N	23 cù chính lan tx hn	0	2026-04-01 03:05:36.393418+00	user	\N
714	\N	Ig thien.nhi	0764747859	\N	K18/15 Nguyễn Văn Thoại, Ngũ Hành Sơn, Đà Nẵng	0	2026-04-01 03:07:22.147267+00	user	\N
715	\N	Ig huong tran	0901669963	\N	100 Lê Lợi, Lộc Thanh, Bảo Lộc - Lâm Đồng \n( địa chỉ xác nhập 100 Lê Lợi, Phường 1, Bảo Lộc - Lâm Đồng )	0	2026-04-01 03:07:48.737359+00	user	\N
716	\N	Dương Thị Hồng Mẫn	0772064405	duongthihongman09@gmail.com	29a, Phạm Ngũ Lão	0	2026-04-01 04:53:23.020846+00	user	\N
717	\N	Ig maria kim  TẶNG ĐỒ KOL	+84 32 5733980	\N	51A Đ. Mê Linh, Tân Lập, Nha Trang, Khánh Hòa 650000\n	0	2026-04-01 12:39:53.19641+00	user	\N
718	\N	Ig jessica 	0827368345	\N	NUE Noble Srinakarin Lasalle นิว โนเบิล ศรีนครินทร์ – ลาซาล\nSrinagarindra Rd, Samrong Nuea, Mueang Samut Prakan District, Samut Prakan 10270, Thailand	0	2026-04-01 12:40:43.349056+00	user	\N
719	\N	Ig Thao	0977490522	\N	21/20 Trường Sơn, P4, Tân Bình\n	0	2026-04-01 12:44:20.604173+00	user	\N
720	\N	Ig ashley nguyen 	0906418882	\N	Số 16 STH12A đường số 5 , khu đô thị Hà Quang 1 , phường Nam Nha Trang , Khánh Hoà 	0	2026-04-01 12:46:11.999112+00	user	\N
721	\N	Ig thanhpham	0902420680	\N	 keangnam landmark72 đường phạm hùng, phường yên hoà hà nội	0	2026-04-01 12:48:16.648625+00	user	\N
722	\N	Ig  Nguyễn ngọc	0919176105	\N	scsc building 30 phan thúc duyện, phường 4 , quận tân bình; thành phố Hồ Chí Minh	0	2026-04-01 12:52:50.389591+00	user	\N
723	\N	vy	0945857868	ngocvycampham@gmail.com	228 khu bến xe	0	2026-04-02 01:11:44.805178+00	user	\N
724	\N	Ig trinh tú	0819420586 	\N	134/117/66,ph2 phường long bình đồng nai\n	0	2026-04-02 03:14:36.690355+00	user	\N
725	\N	Ig hân 	0367913910	\N	\nD6/1 đường 385, p.Tăng Nhơn Phú A	0	2026-04-02 03:15:05.920062+00	user	\N
726	\N	Ig _pycnngan_	0931830452	\N	574/3/27d đường Kinh Dương Vương, P.An Lạc, Q.Bình Tân 	0	2026-04-02 03:15:29.205051+00	user	\N
727	\N	Ig nhu pham	 0905753333	\N	Sunrise Riverside Block D Phước Kiển Nhà Bè 	0	2026-04-02 03:15:57.153857+00	user	\N
728	\N	Ig emma	0869042525	\N	182 phố an dương, phường hồng hà hà nội	0	2026-04-02 03:16:36.781427+00	user	\N
729	\N	Ig benhi123	0356210297	\N	482/69A Lê Quang Định p11 Bình Thạnh	0	2026-04-02 03:17:39.464966+00	user	\N
730	\N	Ig trafbae	0938682503	\N	số nhà 15b, ngõ 17, tổ 4, phường Phú Lương, quận Hà Đông, TP. Hà Nội 	0	2026-04-02 03:18:32.731726+00	user	\N
731	\N	Ig luctramachiato	0835082727	\N	C148 Lê Thị Riêng, phường Thới An, Quận 12, tphcm	0	2026-04-02 03:19:20.90222+00	user	\N
732	\N	Van tran	0933931727	vanbhm.789@gmail.com	Số 29 đường 54	0	2026-04-02 04:27:21.765492+00	user	\N
733	\N	trần phương trang	0848616136	tranphuongtrang.10032003@gmail.com	143 ngõ 2 tổ 3 đa sỹ kiến hưng hà đông	0	2026-04-02 10:15:42.240592+00	user	\N
734	\N	Cao Hồng Yến	0987792504	hongyen4422004@gmail.com	Vinhomes Central Park toà C1, 208 Nguyễn Hữu Cảnh	0	2026-04-02 12:54:09.777106+00	user	\N
735	\N	Ig mai huong	0823523265	\N	Thao Dien Green, 192 Nguyễn Văn Hưởng, Thảo Điền, Thành phố Thủ Đức, Thành phố Hồ Chí Minh\n	0	2026-04-02 13:08:01.003853+00	user	\N
736	\N	Ig mika 	0933519007	\N	25/2 huỳnh văn gấm, tây thạnh, tân phú\n	0	2026-04-02 13:08:50.911054+00	user	\N
737	\N	Ig kim mì	0338370618	\N	76 chung cư Ngô Tất Tố, lô C, phường 19, quận Bình Thạnh (mới là phường Thạnh Mỹ Tây), tpHCM\n	0	2026-04-02 13:10:02.413248+00	user	\N
738	\N	Ig tracy	0933933871	\N	  Địa chỉ: 159, đường Cách Mạng Tháng 8, khu phố 4, phường Phước Hiệp, TP. Bà Rịa, BRVT (địa chỉ cũ)\n	0	2026-04-02 13:10:30.022706+00	user	\N
739	\N	Ig nguyễn diễm hằng	0983423895	\N	52 Thành Thái phường 12 quận 10\n	0	2026-04-02 13:10:55.601328+00	user	\N
740	\N	Ig thu anh	0375033886	\N	Sảnh T1, số 3 Lương Yên, HBT, Hà Nội\n	0	2026-04-02 13:12:10.621452+00	user	\N
741	\N	Ig trinh trinh nguyễn	0966720842	\N	41F/98 Đặng Thuỳ Trâm P13 Bình Thạnh	0	2026-04-02 13:13:58.892797+00	user	\N
742	\N	Ig j	089 9900934	\N	6274749392	0	2026-04-02 13:14:46.094809+00	user	\N
743	\N	Ig salty	0866879713	\N	27/3 đường số 10, p.Bình Thuận, q7\nPhường Tân Thuận (mới)\n.Khanh 	0	2026-04-02 13:15:37.141719+00	user	\N
744	\N	Ig thy	0919500600	\N	68/6 Thống Nhất, p10, gò vấp, hcm \n\n	0	2026-04-02 17:00:13.710583+00	user	\N
745	\N	Ig nhã phương	0909070512	\N	\nĐC: 31/2 Nguyễn Đình Khơi, P4, Q Tân Bình	0	2026-04-02 17:01:06.416986+00	user	\N
746	\N	Ig ANNA_0000	0868340088	\N	Đại lý thông diễm, ngã tư bsek, xã dlieyang, huyện eahleo, tỉnh đăk lăk	0	2026-04-02 17:02:05.38802+00	user	\N
747	\N	Ig kimdunkim	0914150196	\N	La astoria 2, thủ đức	0	2026-04-02 17:02:51.240959+00	user	\N
748	\N	ig avoé	0776657798	\N	9A Tân thới nhất 8- phường Tân thới nhất-q12\n\nND logistics	0	2026-04-02 17:52:03.061563+00	user	\N
749	\N	Phạm thị Mỹ trinh 	0374909137	phamtrinh999@gmail.com	Số 34 Chu văn an long thành đồng nai	0	2026-04-03 03:23:25.619256+00	user	\N
750	\N	Ig thục an	0977354744	\N	\n25/3C khu phố Long Thới, phường Lái Thiêu, Thuận An, Bình Dương\n	0	2026-04-03 03:50:14.078153+00	user	\N
751	\N	Ig linh	0911710023	\N	198 Nguyễn Thị Minh Khai, Q3, HCM (Tòa báo lao động)	0	2026-04-03 04:09:38.177715+00	user	\N
752	\N	Ig phạm yến nhi	0986818823	\N	AMZ pilates and yoga , Đối diện 357 Nguyễn Hoàng Tôn ,Xuân Tảo ,Hà Nội .	0	2026-04-03 14:13:57.675991+00	user	\N
753	\N	Ig my võ	0939806696	\N	696 Trần Hưng Đạo, p.2, Q.5, tp.hcm	0	2026-04-03 14:15:46.117415+00	user	\N
754	\N	Ig phạm ý th	0944531150 	\N	 \nVista Verde - 8 Nguyễn Thanh Sơn, pThạnh Mỹ Lợi, quận 2, HCM\n	0	2026-04-03 14:18:25.382181+00	user	\N
755	\N	Ig kiw.ainh	0779976289	\N	 ấp8 an phước long thành đồng nai ạ\n	0	2026-04-03 14:18:51.939331+00	user	\N
756	\N	Ig balm 	0904473553	\N	(SS2645 - Mr.skill)\nSS Cargo Shipping \n674 đường số 2, Phường 13, Quận 6. TPHCM 	0	2026-04-03 14:21:00.359045+00	user	\N
757	\N	Ig chang phạm	0911607234 	\N	S10.05 Vinhomes Grandpark\n	0	2026-04-03 14:22:22.107385+00	user	\N
758	\N	Ig phuong thao	 0934001194	\N	sav 3 the sun avenue, 28 mai chí thọ phường an phú quận 2	0	2026-04-03 14:23:02.921796+00	user	\N
759	\N	Ig peon!e`	0988930849	\N	29/31 Hoàng Hoa Thám phường gia định\n\n	0	2026-04-03 14:23:42.516511+00	user	\N
760	\N	Ig myhanhhbae	0773696382	\N	598/58 dien bien phu p22 quan binh thanh\n	0	2026-04-03 14:24:30.368896+00	user	\N
761	\N	Ig kiemot2	0393794930	\N	364/23/20a thoại ngọc hầu tân phú\n\n	0	2026-04-03 14:25:08.740581+00	user	\N
762	\N	Ig vy vo	0931737703	\N	15 nguyễn cơ thạch phường An Khánh, tp hcm ạ	0	2026-04-03 14:27:15.357012+00	user	\N
763	\N	Ig trinh nguyễn	0903503415	\N	34 cao thắng p5 q3 hcm\n	0	2026-04-03 14:27:58.387488+00	user	\N
764	\N	Ig jane	 0792238801	\N	Chung cu Infiniti Riviera Point \n2 Nguyễn Văn Tưởng, Tân Phú, Quận 7, Thành phố Hồ Chí Minh\n	0	2026-04-03 14:28:39.042294+00	user	\N
765	\N	Ig ngoc linh 	 0966454626	\N	151/1/41 lạc long quân, p1, quận 11	0	2026-04-03 14:57:55.618447+00	user	\N
766	\N	ig minhanh	0939479449	\N	99 Nguyễn Thị Thập, phường tân phú, quận 7, Thành phố Hồ Chí Minh, chung cư Docklands	0	2026-04-03 15:02:46.982475+00	user	\N
767	\N	Lý	0886357201	lyly112024@gmail.com	132 đường số 1 	0	2026-04-03 17:27:22.683619+00	user	\N
768	\N	bi võ	0966449908	bivo4969@gmail.com	Tổ 4 Ấp Thạnh Sơn 2A (nhà trọ văn minh)	0	2026-04-03 21:48:46.855925+00	user	\N
769	8aca3941-400b-4ee8-af43-455f61379c7c	Tram Hua	7819214858	huatram0709@gmail.com	\N	0	2026-04-04 02:50:35.07588+00	user	\N
770	\N	Loveututhemoon	0867230909	\N	\nĐịa Chỉ: 22/20a1, đường số 26, Hiệp Bình Chánh, Thủ Đức, HCM	0	2026-04-04 04:08:14.822135+00	user	\N
771	\N	Ig insightofan	0908931940	\N	 884/85 Lê Đức Thọ phường 15 quận Gò Vấp TP.HCM	0	2026-04-04 04:09:28.657305+00	user	\N
772	\N	Ig ginkeight	0898503801	\N	105 nơ trang long p11 bình thạnh	0	2026-04-04 04:10:20.030235+00	user	\N
773	9a700fa8-d517-4d6d-9609-651297406db0	Valerya Kha	+84 39 4719241	valeriachasanova@gmail.com	\N	0	2026-04-04 04:38:17.798154+00	user	\N
774	\N	Phạm Thị Diễm My	0886327889	tamdannguyen21121999@gmail.com	52/1 đường Đồng Tâm	0	2026-04-04 05:55:43.911122+00	user	\N
775	\N	Lương Gia Linh	0937303307	linhlg190406@gmail.com	207c nguyễn xí ( chung cư richmond )	0	2026-04-04 12:57:04.547872+00	user	\N
776	\N	Thảo Trân	0989585837	\N	Nhà Trọ Thầy Ngân, Số 2, Đường Nguyễn Thị Định, Khóm Đông Thịnh 8, Phường Mỹ Phước, Thành phố Long Xuyên, An Giang	0	2026-04-04 13:13:48.781912+00	user	\N
777	\N	Ig kimchi_boo	085.373.9999	\N	Ct2a ngõ 34 hoàng cầu, chợ dừa, đống đa\n.0794666888 	0	2026-04-04 13:32:06.816676+00	user	\N
778	\N	Ig iemvy31	0905479510	\N	02 hải hồ, phường thanh bình, quận hải châu, đà nẵng	0	2026-04-04 13:33:02.149688+00	user	\N
779	\N	Ig D A S H A	0867314648	\N	Nha Trang Napoleon castle ￼25 Đ. Nguyễn Đình Chiểu, Bắc Nha Trang, Khánh Hòa 650000	0	2026-04-04 13:34:30.58915+00	user	\N
780	\N	Ig minh ngọcc	0935814465	\N	206/32 đường số 20 phường An Nhơn Gò Vấp TpHCM	0	2026-04-04 13:34:52.600149+00	user	\N
781	\N	Ig suhyn	0946340006	\N	57, đường số 1 khu tái định cư phường Tương Bình Hiệp tp TDM Bình Dương	0	2026-04-04 13:36:03.450598+00	user	\N
782	\N	Ig ngọc hoàng trịnh 	0901311298	\N	8 hoàng văn thái PMH tower q7	0	2026-04-04 13:37:23.66791+00	user	\N
783	\N	Ig T	 0989585837. 	\N	Nhà Trọ Thầy Ngân, Số 2, Đường Nguyễn Thị Định, Khóm Đông Thịnh 8, Phường Mỹ Phước, Thành Phố Long Xuyên, An Giang	0	2026-04-04 14:12:32.794143+00	user	\N
784	\N	Ig hong_._anh	0354417211	\N	20/40/32, Tổ 3 xóm Trung Đằng Giang, Phường Đằng Giang, Quận Ngô Quyền, Hải Phòng	0	2026-04-05 03:49:26.674518+00	user	\N
785	\N	Ig zuilennha	0797487077	\N	38/48/7 Trần Khắc Chân, Tân Định, Q1, TP HCM 	0	2026-04-05 03:49:51.377929+00	user	\N
786	\N	ig Quỳnh Như	0917134700	\N	91/59B Phạm Văn Chiêu P14 Gò Vấp	0	2026-04-05 03:50:23.91714+00	user	\N
787	\N	Khánh Ngọc	0888077424	Huynhtrankhanhngoc@gmail.com	99/5A đường 30/4 phường Ninh Kiều, TPCT ( hẻm 99 kế Cỏ Mềm Homelab, chạy vào 5m bên tay trái có cổng rào màu đen )	0	2026-04-05 09:44:15.976453+00	user	\N
788	\N	Ig mì	0868108834	\N	5/16, Đường Nguyễn Văn Khối, Phường 11, Quận Gò Vấp, TP. Hồ Chí Minh	0	2026-04-05 12:30:47.50183+00	user	\N
789	\N	Ig ánh hồng	0867731354	\N	55/21 đường tây lân khu phố 44 phường Bình Tân HCM 	0	2026-04-05 12:31:42.772622+00	user	\N
790	\N	Ig kim linh	0342544676	\N	s111 ocean park 1 đa tốn gia lâm hn\n	0	2026-04-05 12:32:17.39887+00	user	\N
791	\N	Ig phan trần phương thảo	0387468011	\N	10 hẻm 25/119 ngõ Thổ Quan, Khâm Thiên, Đống Đa, Hà Nội	0	2026-04-05 12:32:44.31337+00	user	\N
792	\N	Ig tthaomay	0394280699	\N	72 Trần Hưng Đạo, phường Trần Hưng Đạo, TP Hạ Long, tỉnh Quảng Ninh\n	0	2026-04-05 12:33:05.480118+00	user	\N
793	\N	Ig _phbento	0867388676 	\N	178 Trần Phú, p.Diên Hồng, tp Pleiku, Gia Lai 	0	2026-04-05 12:33:32.90167+00	user	\N
794	\N	Ig winnie	0901202196	\N	45/38 Nguyễn đôn tiết, phường Bình trưng Đông, quận 2, hcm	0	2026-04-05 12:33:51.69263+00	user	\N
795	\N	Ig sbryieeee	0903305740	\N	411 Kha Vạn Cân, phường Hiệp Bình Chánh, TP Thủ Đức, Hồ Chí Minh (Quán Cao Nguyên Xanh)	0	2026-04-05 12:34:38.249752+00	user	\N
796	\N	Ig irisngn	0905859393	\N	Nhà 48, hoa phượng 3, vinhomes riverside long biên, phúc lợi, hà nội	0	2026-04-05 12:35:37.638796+00	user	\N
797	\N	Ig kelsey	0829408425	\N	 nhà 14 ngõ 66/16/3 Ngọc Thuỵ, Long Biên, Hà Nội	0	2026-04-05 12:36:28.367791+00	user	\N
798	\N	Kim sonin	0399.888.688	\N	363 Hùng Vương, Phường An Đông, TP.HCM	0	2026-04-05 12:38:07.688031+00	user	\N
799	\N	Ig bunny.huynh	0947777456	\N	Xe điện thiện phát 3 ( nội thất đào 9be, đối diện trường thcs nguyễn quang sáng), Mỹ Luông, Chợ Mới, An Giang	0	2026-04-05 12:41:11.445787+00	user	\N
800	2e663bf7-50b9-40cb-a734-647ae3036ddd	Trần Văn Thường	0343495167	vanthuongsbtc@gmail.com	\N	0	2026-04-05 15:26:10.85949+00	user	\N
801	\N	Trần Văn Thường - Trần Kim Ngân	0982164198	vanthuongsbtc@gmail.com	Nhà hàng Cơm Niêu Tài Lộc - Cẩm Khê - Tứ Minh - Hải Dương	0	2026-04-05 15:33:09.189499+00	user	\N
802	\N	Thê Thê	0399750010	callthuongbaby@gmail.com	Toà B chung cư The Zei- Số 8 Lê Đức Thọ 	0	2026-04-05 15:41:20.224682+00	user	\N
803	\N	Ig concameokhongat_22	0943354366	\N	Chung cư đất phương nam chu văn an p12 quận bình thạnh 	0	2026-04-05 15:49:13.492132+00	user	\N
804	\N	Ig tuyet bach	0384499397	\N	Cây nhãn khu phố 2 thị trấn Bến Cầu huyện bến Cầu tỉnh Tây Ninh.	0	2026-04-05 15:49:36.056761+00	user	\N
805	\N	Ig thuhuyen tran	0388777937	\N	162 trần bình trọng , lộc phát , bảo lộc , lâm đồng	0	2026-04-05 15:50:26.813884+00	user	\N
806	\N	Ig bet.chayyyy	4086306196	\N	1782 Penwood St, San Jose, CA 95133	0	2026-04-05 15:59:30.762062+00	user	\N
807	d940f748-6f3b-4a02-ab25-29803e68d029	Nisarat	0824971924	piployyrosus@gmail.com	\N	0	2026-04-05 17:13:01.192475+00	user	\N
808	\N	Nguyễn Thị Thu Hiền	0966788294	\N	Số 11, ngõ 18 Lê Hồng Phong	0	2026-04-06 03:33:32.583943+00	user	\N
809	\N	Ig gladysbay_	 +84 96 696 11 31	\N	OTIS APARTMENT AND HOTEL 33 Trần Kế Xương, Phường 1, Phú Nhuận, Hồ Chí Minh 700000, Việt Nam	0	2026-04-06 04:36:31.410763+00	user	\N
810	\N	Hoàng Ngọc Ánh	0965122063	hna170803@gmail.com	2C32/8 ấp 70 xã Tân vĩnh lộc	0	2026-04-06 13:34:45.536453+00	user	\N
811	\N	Ig __mhangg_	0869669092	\N	221 Hoàng Hoa Thám, Ba Đình, Hà Nội	0	2026-04-06 14:45:33.679992+00	user	\N
812	\N	Ig jade	 0964677183	\N	Sảnh A, toà River, Chung cư Eurowindow, Đông Hội, Đông Anh, Hà Nội	0	2026-04-06 14:47:57.783719+00	user	\N
813	\N	Ig nhu y	0942092705	\N	947 Quang Trung,p14, Gò Vấp	0	2026-04-06 14:48:18.703016+00	user	\N
814	\N	Ig tit.princess	0378404004 	\N	132 nguyễn trãi bến thành q1	0	2026-04-06 14:48:40.596485+00	user	\N
815	\N	Ig vân	0903516873	\N	141 đô đốc tuýet, hoà xuân, đà nẵng\n	0	2026-04-06 14:49:03.471842+00	user	\N
816	\N	Ig sithanh	0938709011	\N	11 , đường 34 , an phú , q2 , thủ đưc	0	2026-04-06 14:50:11.171888+00	user	\N
817	\N	Ig anothermythh	0932633789	\N	49 vũ trọng phụng, p.tân thành quận tân phú tphcm	0	2026-04-06 14:55:15.153277+00	user	\N
818	\N	Ig mynart	0528626051	\N	253 hoàng văn thụ p2 tân bình	0	2026-04-06 14:55:53.269837+00	user	\N
819	\N	Nâu	0968654470	duongdiepnhuhuynh@gmail.com	33 mạc đỉnh chi	0	2026-04-06 15:04:10.276941+00	user	\N
820	\N	Ig nguyễn trần bảo linh	0368933154	\N	201/65/14 Nguyễn Xí Bình Thạnh HCM	0	2026-04-06 16:01:26.642656+00	user	\N
821	\N	Quỳnh Anh	0961859543	nghoangquynhanh@gmail.com	The Marq - Căn hộ A20.10, 29B Nguyễn Đình Chiểu	0	2026-04-06 17:22:49.508597+00	user	\N
822	\N	Duy Ngọc	0779512164	phanthiduyngoc@gmail.com	148/7 Hoàng Diệu 2	0	2026-04-06 17:22:50.784677+00	user	\N
823	\N	Jun 	0966401556	\N	Nhà số 7 ngõ 91 Đặng Tiến Đông	0	2026-04-07 03:52:39.915623+00	user	\N
824	\N	Ig lozova_hanna	380990053866 	\N	603 - 42/11 + 42/13 Da Tuong, Vinh Nguyen ward, Nha Trang city, Khanh Hoa province\n	0	2026-04-07 04:18:28.090873+00	user	\N
825	\N	Ig 1808kg_	0708474923	\N	144 Trần Phú khóm2 phường 1 Sa Đéc - Đồng Tháp	0	2026-04-07 04:19:26.847526+00	user	\N
826	\N	Ig prepretty	+84-818999538	\N	7/1 Hồ Biểu Chánh, Phú Nhuận, TP. Hồ Chí Minh	0	2026-04-07 04:20:28.294291+00	user	\N
827	\N	Tú Anh	0365699083	Anhltt201@gmail.com	40 Phan Đăng Lưu, Kiến An	0	2026-04-07 13:30:55.725368+00	user	\N
828	\N	Ig phan ngọc thơ	0389211072	\N	chung cư rivergate 155 bến vân đồn quận 4	0	2026-04-07 13:56:55.989794+00	user	\N
829	\N	Ig tống gia yến	0868745716	\N	41 Trần Quang diệu khu phố 2 thị trấn Đông Nam Phước Vĩnh huyện Phú Giáo tỉnh Bình dương	0	2026-04-07 14:00:08.245842+00	user	\N
830	\N	Ig amy	0939312605	\N	Số 4 dương văn dương, phường sơn kỳ, quận tân phú, hcm	0	2026-04-07 14:00:58.870147+00	user	\N
831	\N	Ig thu đông	0939872600	\N	267/61b bùi đình tuý, bình thanh 	0	2026-04-07 14:01:25.05057+00	user	\N
832	\N	Ig ningning	0363423121	\N	205 yên duyên yên sở hoàng mai hn	0	2026-04-07 14:01:52.382054+00	user	\N
833	\N	Ig itduongnhieuda	(+84) 886 144 500	\N	Kí Túc Xá Đh Mỹ Thuật, 27/15 Đường 27 Phường Hiệp Bình Chánh, Thành Phố Thủ Đức	0	2026-04-07 14:04:25.309348+00	user	\N
834	\N	Ig huỳnh nhi	0768024698	\N	153/10b nguyễn Thông q3 	0	2026-04-07 14:05:05.936855+00	user	\N
835	\N	Ig phùng thuỳ dung	0383215995	\N	S2.03 Ocean Park, Đa Tốn, Gia Lâm, HN	0	2026-04-07 14:05:37.56786+00	user	\N
836	\N	Ig haidiep	0339387192	\N	55 Phố Tô Vĩnh Diện - Khương Đình - Hà Nội	0	2026-04-07 14:06:02.840921+00	user	\N
837	\N	Ig ivy trúc phương	0345203628	\N	577/8 , ấp Tân Đông , xã Mỹ Phú Đông , huyện Thoại Sơn , tỉnh An Giang	0	2026-04-07 14:44:07.802757+00	user	\N
838	\N	Nguyễn Cẩm Nhung	0344325671	nguyencamnhung152641@gmail.com	Khu tập thể in ngân hàng, phố Tôn Đức Thắng	0	2026-04-07 15:25:41.387184+00	user	\N
839	\N	Ig thuỳvân nguyễn	0938122996	\N	tòa nhà cảng vụ hàng không miền nam, sân bay tân sơn nhất, đường trường sơn, p2, tân bình  	0	2026-04-07 16:08:41.123927+00	user	\N
840	\N	Ig vy	0818924998 	\N	121 cô giang, phường Cầu ông lãnh\n\n	0	2026-04-07 16:44:02.82369+00	user	\N
841	1ff5a05d-1529-487c-80ed-09ab7e457c45	jinghui ling	15221280008	1447525149@qq.com	\N	0	2026-04-08 05:02:38.929766+00	user	\N
842	\N	Nguyễn Tường Vi 	0918452222	\N	Ấp 3 	0	2026-04-08 10:54:51.707157+00	user	\N
843	\N	Ig noemie paris bảo nhi	0903010865	\N	citi alto cát lái block D 	0	2026-04-08 15:09:07.32838+00	user	\N
844	\N	Ig ynhinn.16	0344425259	\N	đội 19, thôn câu lâu tây, duy phước, duy xuyên, quảng nam 	0	2026-04-08 15:09:36.235768+00	user	\N
845	\N	Ig thechxxu	0865409688	\N	72a nguyễn trãi thanh xuân thượng đình Hà Nội \nChung cư roayl city r4 thương mại\n	0	2026-04-08 15:10:14.95635+00	user	\N
846	\N	Ig bống	0367229158	\N	Địa chỉ: 167 Cộng Hoà, p.12, Tân Bình	0	2026-04-08 15:10:45.41135+00	user	\N
847	\N	Ig _ntuynnn	0923757531	\N	số 10 hưng gia 3 phường tân phong quận 7\n	0	2026-04-08 15:11:45.698208+00	user	\N
848	\N	Ig thy thy	0896562195	\N	625 nguyễn đình chiểu phường bàn cờ quận 3	0	2026-04-08 15:12:09.755374+00	user	\N
849	\N	Ig hin	0787887362	\N	Nhà trọ Minh Nhựt, 113, Đường 3/2, An Bình, Ninh Kiều, Cần Thơ	0	2026-04-08 15:12:38.028871+00	user	\N
850	\N	Ig nguyen hoang yen nhi	0912516282	\N	Căn C105, chung cư Hiệp Thành 3, đường số 8, phường Hiệp Thành, Thủ Dầu Một, Bình Dương	0	2026-04-08 15:13:03.834342+00	user	\N
851	\N	Ig archivemehuh	0985835533	\N	Địa chỉ 21 Trương Công Định,P14, Quận Tân Bình, HCM 	0	2026-04-08 15:14:43.705255+00	user	\N
852	\N	Ig bảo uyên	0938181222	\N	18 trần hoành đà nẵng\nnguyễn bảo uyên\n	0	2026-04-08 15:15:08.715992+00	user	\N
853	\N	Ig trâm anh	090 3879361	\N	280/8 huỳnh văn bánh p11 phú nhuận	0	2026-04-08 15:17:38.172854+00	user	\N
854	\N	Ig poni	0376893928	\N	· Đc: số nhà 26 ngách 48 ngõ 426 đường láng, đống đa, HN 	0	2026-04-08 15:18:14.451111+00	user	\N
855	\N	Ig tớ là chin	0929499652	\N	48 đường số 31A, khu đô thị An Phú An Khánh, Phường An Phú, Thủ Đức	0	2026-04-08 15:18:39.467073+00	user	\N
856	\N	Ig T/anne	0969598289	\N	56B Bà Triệu, Phường Cửa Nam, Hà Nội 	0	2026-04-08 15:19:07.352876+00	user	\N
857	\N	Ig bu	0984761299	\N	64 trần thị liền phước kiển nhà bè	0	2026-04-08 15:19:31.017725+00	user	\N
858	\N	Ig plchmsva	84368308053	\N	Sth32A.12 Đường Số 37, Hà Quang 1, Nha Trang, Phường Phước Hải, Thành Phố Nha Trang, Khánh Hòa	0	2026-04-08 15:21:37.358231+00	user	\N
859	\N	Ig linh nguyen	0938400603	\N	1A16 Đông Tây 1, An Phú, quận 2 	0	2026-04-08 15:26:31.938846+00	user	\N
860	\N	Ig jasmine	+852 9388 1755	\N	66C Mount Davis Rd, Pok Fu Lam, Hong Kong\n	0	2026-04-08 16:28:28.746711+00	user	\N
861	\N	Ig vũ lâm oanh	0866160699 	\N	T3 times city, phường vĩnh tuy hn	0	2026-04-08 16:29:24.961601+00	user	\N
862	e94565fe-3fdc-4d54-845f-2c98daa09e72	Nwachukwu Victoria 	08103525938	victoria.nwachukwu2005@gmail.com	\N	0	2026-04-09 01:07:18.773666+00	user	\N
863	\N	Như Thuỷ	0774455240	tp.ame284@gmail.com	18 mỹ đa đông 3	0	2026-04-09 14:17:49.778431+00	user	\N
864	\N	Ig _._.kemne	0386181997	\N	Chung cư paragon số 86 Duy Tân/ Dịch Vọng Hậu/ Cầu Giấy/ HN\n	0	2026-04-09 14:45:21.007476+00	user	\N
865	\N	Ig sylvie.lii	0965892979	\N	18/6 đường số 41 phường An Khánh Q2\n\n	0	2026-04-09 14:46:01.841984+00	user	\N
866	\N	Ig hoàng thạch	0949877788	\N	Block B, Căn B.23.10, chung cư Eco Green, 39B Nguyễn Văn Linh, Tân Thuận Tây, Quận 7, Hồ Chí Minh	0	2026-04-09 14:53:00.849243+00	user	\N
867	\N	Ig catherine phu	(+84) 901 835 167	\N	Building H, Midtown - The Peak M8, Unit 18.01, Đường số 16, Khu đô thị Phú Mỹ Hưng\nPhường Tân Phú, Quận 7, 	0	2026-04-09 14:57:04.434524+00	user	\N
868	\N	Ig hhiihi.2409	(+84) 898 379 194	\N	Uy ban nhân dân xã diên an, Xã Diên An, Huyện Diên Khánh, Khánh Hòa	0	2026-04-09 14:59:44.03317+00	user	\N
869	\N	Ig lê thảo	  0795602420	\N	235 gò xoài quận bình tân tp HCM 	0	2026-04-09 15:03:08.206766+00	user	\N
870	\N	Ig ngndd_	0339653665	\N	799/22/6 Nguyễn Kiệm, p3, Gò Vấp	0	2026-04-09 15:03:41.40299+00	user	\N
871	\N	Ig haahluu	0989273116	\N	56 Lê Hồng Phong, phường Hà Cầu, quận Hà Đông, HN	0	2026-04-09 15:04:06.461666+00	user	\N
872	\N	Ig duyên đặng	0889632951	\N	Số 48 ngõ 177 đường cầu diễn, nam từ liêm, hà nội	0	2026-04-09 16:59:41.944801+00	user	\N
873	\N	Ig cát tiên	0901662195	\N	16/2/4/10 đường 44 phường hiệp bình chánh, TP HCM	0	2026-04-09 17:19:49.715816+00	user	\N
874	\N	Ig vy	0399136615 	\N	V6-01 , Diamond brilliant , tân phú	0	2026-04-09 17:20:39.306195+00	user	\N
875	\N	Đặng Ly	0888009921	imdangly@gmail.com	Số nhà 9A, ngách 19 ngõ 127 Phùng Khoang	0	2026-04-09 20:05:59.772275+00	user	\N
876	\N	Ig trrngg	0765750384	\N	428 Lê Hồng Phong, p1 q10\n	0	2026-04-10 03:07:12.53217+00	user	\N
877	\N	Linh	0856111165	\N	343/30 Trần Thủ Độ	0	2026-04-10 12:24:21.859918+00	user	\N
878	\N	Hồ Minh Mỹ Hảo	0902389940	me.mm1505@gmail.com	74 Tô Hiệu	0	2026-04-10 15:31:41.832611+00	user	\N
879	\N	Khánh linh	0986579314	yen675663@gmail.com	51 nguyên hồng - bích động - việt yên - bắc ninh ( bắc giang cũ )	0	2026-04-11 01:08:54.753044+00	user	\N
880	\N	Hoàng Ái Vy	0833179044	hoangaivy14012004@gmail.com	43 ngõ 33 Chùa Láng	0	2026-04-11 04:04:30.386239+00	user	\N
881	\N	Lê Giáng Mi	0902574526	gmi61127@gmail.com	2864/1b hẻm 99 đường an phú đông 10	0	2026-04-11 07:09:59.552029+00	user	\N
882	fbc73a7a-b47f-445a-bdee-3e316ac15e0a	Lê Giáng Mi	0902574526	gmi61127@gmail.com	\N	0	2026-04-11 07:12:06.405261+00	user	\N
883	\N	Ig quinn (quynh trang)	0909750265	\N	216/1/1 Nguyễn Văn Hưởng thảo điền (phường an khánh mới)\nBi tím	0	2026-04-11 09:59:40.577933+00	user	\N
884	\N	Ig dydy_002	0972632503 	\N	17b nguyễn trãi , xuân hoà , long khánh 	0	2026-04-11 10:00:12.48783+00	user	\N
885	\N	Ig n.traang	0903208989	\N	Biệt thự 25, khu đô thị Nghĩa Đô, ngõ 106 Hoàng Quốc Việt, p. Cổ Nhuế 1, Q. Bắc Từ Liêm, Hà Nội	0	2026-04-11 10:01:39.824352+00	user	\N
886	\N	Ig vũ lê	0795600204	\N	LôB 14-15 Nguyễn Đình Hoàn, P.Nại Hiên Đông, Q. Sơn Trà, TP. Đà Nẵng\n	0	2026-04-11 10:02:25.927076+00	user	\N
887	\N	Ig thỏ	0908223822	\N	16/47/21 nguyễn thiện thuật q3	0	2026-04-11 10:03:09.727509+00	user	\N
888	\N	Ig hongphuc1237	0963000866	\N	35 tôn đức thắng p bến nghé quận 1 	0	2026-04-11 10:03:48.316221+00	user	\N
889	\N	Ig nguyễn bảo trân	0903114446	\N	135 phạm văn hai p5 tân bình	0	2026-04-11 10:04:43.900022+00	user	\N
890	\N	Ig milyn 	 0909333871	\N	Bitexco, Ngô Đức Kế, P. Bến Nghé, Q1	0	2026-04-11 10:05:11.223757+00	user	\N
891	\N	Ig aren_pre	0879230235	\N	793/10 trấn xuân soạn Q7, hcm	0	2026-04-11 10:09:40.40574+00	user	\N
892	\N	Eden Comilang	0353896406	\N	29 Huỳnh Văn Bánh, Phường 15, Phú Nhuận, Hồ Chí Minh 	0	2026-04-11 10:16:54.226385+00	user	\N
893	\N	Ig nhật lệ	0384305303	\N	132 bến vaan đồn cho mình 	0	2026-04-11 10:17:53.478869+00	user	\N
894	\N	Ig gn.archivesxx	‪+84 96 376 54 74‬ 	\N	240/2A D. Le Thanh Ton Phuong Ben Thanh Quan 1 Thanh pho, Ben Thanh Hcm\n	0	2026-04-11 10:18:54.521191+00	user	\N
895	\N	Ig rítttt_hồ 	0909868757	\N	Bãi Xe Container Thạnh Đức, Ấp 1, Xã Bình Đức, Tỉnh Tây Ninh (Long An cũ)	0	2026-04-11 10:20:24.057859+00	user	\N
896	\N	Ig ngocquinh_	0828020068	\N	Nhà 2A Ngõ 322/95/29/30, Mỹ Đình 1 , Hà Nội	0	2026-04-11 10:20:52.752379+00	user	\N
897	\N	Ig thena	530 360 8924	\N	Tonicervantess@icloud.com\n3855 Archwood rd, cameron park CA 95682 USA	0	2026-04-11 10:23:18.014703+00	user	\N
898	\N	Ig trangg_vht	 0328700916 	\N	Số 96, Châu Văn Lồng, Phường Long Bình Tân, Thành Phố Biên Hòa, Đồng Nai	0	2026-04-11 10:25:26.47649+00	user	\N
899	\N	Ig india ali	9493242914	\N	14271 jeffrey rd #194, irvine CA 92620	0	2026-04-11 10:26:37.572725+00	user	\N
900	\N	Ig ANNA_0000	0585500046	\N	400/35 nguyễn đức thiệu, dĩ an, dĩ an, bình dương	0	2026-04-11 10:28:27.150298+00	user	\N
901	\N	Ig soi215	032 7113054	\N	15/7 Lương Thế Vinh, phường Xuân Hương, tp Đà Lạt\nPhương Thành	0	2026-04-11 10:28:56.639228+00	user	\N
902	\N	Ig trâm anh	0979251679	\N	8/7 nguyễn đức cảnh, tp pleiku, gia lai 	0	2026-04-11 10:29:37.197409+00	user	\N
903	\N	Ig thiên thảo	0937501804	\N	109/39 Nguyễn Thiện Thuật p2 q3 	0	2026-04-11 10:30:11.854155+00	user	\N
904	\N	Ig khailina 	0908315806	\N	VietAviation Logistics Co., 6bis Thăng Long, Phường 4, Tân Bình, Ho Chi Minh, Vietnam  (Hồng -Truc Shanghai Hangzhou 	0	2026-04-11 10:31:45.560966+00	user	\N
905	\N	Ig ohsomeyeen	0849436685	\N	87a hàm nghi, P Nguyễn Thái Bình, Q1	0	2026-04-11 14:56:18.117612+00	user	\N
906	\N	Ig quienphm	0706201066	\N	 Lô 15 Ô CL 13 đường số 9 Hòn Rớ 2, xã Phước Đồng, Nha Trang\n	0	2026-04-11 14:56:43.978096+00	user	\N
907	\N	Ig nguyễn diễm quỳnh nga	0334418259	\N	Số nhà 68, ngõ 44 Trần Thái Tông,Dịch vọng hậu Cầu giấy\n	0	2026-04-11 14:57:54.094697+00	user	\N
908	\N	Ig yciiii_0.001	0353271774	\N	 35/3A ấp 7, Xã Xuân Thới Thượng, Hóc Môn, TPHCM 	0	2026-04-11 14:58:18.534482+00	user	\N
909	\N	Ig qazxcv74123	(+84) 343 621 271	\N	Masa (Xưởng Số 6. Cty Sakura. Đối Diện INOX ASIA)Lô C3.1, Đường D 1, Khu Công Nghiệp Đồng An 2, Phường Hòa Phú, Thành Phố Thủ Dầu Một, Bình Dương	0	2026-04-11 14:59:00.828044+00	user	\N
910	\N	Ig emb3_raica	0914721224 	\N	Uyên Khương\nOrange town 180A vườn lài, an phú đông, q12 	0	2026-04-11 15:00:26.590189+00	user	\N
911	\N	Ig jauawjwh.171 	0339876978	\N	26 phan đình phùng-liên nghĩa-đức trọng-lâm đồng	0	2026-04-11 15:00:50.942144+00	user	\N
912	\N	Ig hathuylinh.eyelash	0961571039	\N	4 Long biên 2 long biên hn \n	0	2026-04-11 15:01:19.961237+00	user	\N
913	\N	Ig hoài danh	0937720053	\N	: 128/78C Lê Văn Duyệt, phường 1, quận Bình Thạnh, TP.HCM\n	0	2026-04-11 15:01:45.666872+00	user	\N
914	\N	Ig kitty	0926777966	\N	Amamy JAHX73 Ngọc\n(Cửa hàng Amamy Post đối diện số nhà 56 ngách 93/20, ngõ 93 Hoàng Văn Thái, Khương Trung, Thanh Xuân, Hà Nội)	0	2026-04-11 15:02:35.737426+00	user	\N
915	\N	Ig ngọc nguyễn	0369552337	\N	Ấp 4 Xã Mỹ Tân thành phố Cao Lãnh tỉnh Đồng tháp( ngay chợ bình Trị)\n	0	2026-04-11 15:03:05.484675+00	user	\N
916	\N	Hà Ngọc Anh	0975451521	ngocanhha0104@gmail.com	18 đường số 14 Khu Đô Thị Vạn Phúc	0	2026-04-12 04:34:13.858845+00	user	\N
917	\N	Nguyễn Trần Lan Anh 	0919799472 	anh.lannt153@gmail.com	578 Hoàng Văn Thụ	0	2026-04-12 05:18:37.193038+00	user	\N
918	\N	Ig bim	0934730483 	\N	430 Võ Văn Đặng, Hoà Hải, Ngũ Hành Sơn, Đà Nẵng ( ANNA's HOME )	0	2026-04-12 09:58:49.530376+00	user	\N
919	\N	Ig Béeeeee Kemmm	0356478016	\N	87/29 đường số 27 p6 gò vấp	0	2026-04-12 09:59:21.002499+00	user	\N
920	\N	Ig lily	0908040593	\N	2/8 đường số 31, P.An Khánh, Q.2	0	2026-04-12 10:00:06.012027+00	user	\N
921	\N	Ig mỹ uyên	0353679949	\N	10 nguyễn thị minh khai, phường phú nhuận, quận thuận hoá, thành phố huế	0	2026-04-12 10:00:59.27763+00	user	\N
922	\N	Ig hoàng hiếu 	0387825807	\N	229/2D khu phố Thạnh bình phường an thạnh thành phố thuận an tỉnh bình dương	0	2026-04-12 10:01:27.950946+00	user	\N
923	\N	 Ig anastasiia_kinder	+84342253533	\N	Scenia Bay, Phường Vĩnh Hải, Nha Trang City, Khanh Hoa Province.	0	2026-04-12 10:02:49.449652+00	user	\N
924	\N	Ig lê ngọc mai	0916586373	\N	98 chu văn an phường 26, bình thanh 	0	2026-04-12 10:04:00.764599+00	user	\N
925	\N	Ig Presaigon.bkk	0355180235	\N	31c, phố Thanh Am, phường Thượng Thanh, quận Long Biên, Hà Nội.”	0	2026-04-12 10:05:35.154421+00	user	\N
926	\N	Ig bánh cờ rếp	0375451108	\N	656/19 cmt8 p11 q3	0	2026-04-12 10:06:27.528969+00	user	\N
927	\N	Ig teddy	0914649545	\N	355/6 đường bùi quốc khánh phường chánh nghĩa thủ dầu một Bình Dương 	0	2026-04-12 10:06:54.781783+00	user	\N
928	\N	Ig teddy	0914649545	\N	355/6 đường bùi quốc khánh phường chánh nghĩa thủ dầu một Bình Dương 	0	2026-04-12 10:06:54.93421+00	user	\N
929	\N	Ig lâm ánh quỳnh	0775773167	\N	Chung cư Citiesto - Cát Lái - Block C - Căn hộ C19.10	0	2026-04-12 10:07:40.90141+00	user	\N
930	\N	Ig hangtr__	0347135579	\N	285 Đội Cấn, Liễu Giai, Ba Đình, HN giúp m nhé\n	0	2026-04-12 10:08:38.368898+00	user	\N
931	\N	Ig đoàn phương uyên	0783694723	\N	202  Hoàng Diệu , phường thanh sơn , phan rang ninh thuận 	0	2026-04-12 15:15:41.902857+00	user	\N
932	\N	Ig thuỳ linh	0345026058	\N	152 hoa bằng,yên hoà,cầu giấy , hà nội	0	2026-04-12 15:16:05.636294+00	user	\N
933	\N	Ig mai thanh 	+84) 528 593 977	\N	Đường 27 giữa ngã tư số 8 số 10. Nhà tuyền đồ mỹ Xã Nghĩa Thành, Huyện Châu Đức, Bà Rịa - Vũng Tàu	0	2026-04-12 15:21:14.481813+00	user	\N
934	\N	Ig 777	07562744259	\N	9 Grove shaw Kingswood, Surrey, KT20 6QL, United Kingdom	0	2026-04-12 15:23:34.062954+00	user	\N
935	\N	Ig celine pham	0931595999	\N	10/119 Miếu Hai Xã, phường Hồ Nam, quận Lê Chân, TP. Hải Phòng	0	2026-04-12 15:24:58.196064+00	user	\N
936	\N	Ig hiếu kiên	0355505838	\N	214/2e vạn kiếp, phường 3, quận Bình Thạnh 	0	2026-04-12 15:25:32.963846+00	user	\N
937	\N	Minh Phương	0906140069	dominhphuong2911@gmail.com	29 ngõ 19 Tố Hữu	0	2026-04-12 16:12:51.409052+00	user	\N
938	\N	Anh Phương	0933006410	anhphuong.280698@gmail.com	220/15/9c âu cơ	0	2026-04-13 04:47:44.292919+00	user	\N
939	\N	Ig phương nhi võ	0915591550	\N	6g25 Trần Não, phường An Khánh, Quận 2 ( đầu hẽm 151 Trần Não) 	0	2026-04-13 07:41:33.005607+00	user	\N
940	\N	Ig ngọc anh nguyễn 	0896025025	\N	số nhà 76, đường 23, khu đô thị thành phố Giao Lưu, Cổ Nhuế 2, quan Bắc Từ Liêm, Hà Nội	0	2026-04-13 07:42:22.851167+00	user	\N
941	\N	Ig thảo nguyên	0389525658	\N	Tầng 5, tòa nhà 29T1, đường Hoàng Đạo Thúy, Phường Yên Hoà, Thành phố Hà Nội, Việt Nam	0	2026-04-13 07:42:47.84875+00	user	\N
942	\N	Ig eint_chit3	0798361288	\N	341/17c lạc Long quân phường 5 quận 11 tp HCM	0	2026-04-13 07:44:03.134191+00	user	\N
943	\N	Ig camtien_	0382679931	\N	146 Nguyễn đình chiểu phường 6 (địa chỉ mới phường Xuân Hoà), quận 3, TPHCM\nToà nhà Endovina Tower	0	2026-04-13 07:44:32.184236+00	user	\N
944	\N	Bùi Ngọc Ánh	0359366756	anhbuingoc1999@gmail.com	Phòng M808, chung cư HDI, 158 Võ Chí Công	0	2026-04-13 11:54:58.183198+00	user	\N
945	\N	Nguyễn Ngọc Quỳnh Chi	0978781586	nnqc11082005@gmail.com	Số 2 - ngách 464/1 - Âu Cơ	0	2026-04-13 12:32:28.127092+00	user	\N
946	\N	Ig hnil 	0936526288	\N	 số 502 Tôn Đức Thắng - phường An Đồng - quận An Dương - tp Hải Phòng	0	2026-04-13 16:45:14.841782+00	user	\N
947	\N	Ig nanfeng.studio 	0976387001	\N	 20 Tân Thới Nhất 17, Phường Tân Thới Nhất, Quận 12, Thành phố Hồ Chí Minh	0	2026-04-13 16:46:56.685261+00	user	\N
948	\N	Ig baobeiii	0976248195	\N	463 An Dương Vương, Đông Ngạc, Bắc Từ Liêm, Hà Nội 	0	2026-04-13 16:47:24.850194+00	user	\N
949	\N	Ig thuỳ linh	 0867716136	\N	 Máy Xông Tinh Dầu , Máy Khuếch Tán Tinh Dầu Thiên Nhiên Lorita, 602/39/20, Đường Điện Biên Phủ, p22, quận Bình Thạnh, tp HCM.	0	2026-04-13 17:05:28.409229+00	user	\N
950	\N	Nguyễn Ngọc Bảo Trân	0337085521	baotran12022019@gmail.com	461 Trần Phú (Cửa Hàng Phụ Kiện Điện Thoại Hoàng Kim)	0	2026-04-13 17:11:38.263743+00	user	\N
951	\N	Ig donfetch	0886508026	\N	8C lam son , tan binh, HCMC\nRoom 203	0	2026-04-13 17:21:33.04969+00	user	\N
952	\N	Trúc 	+84 90 6964204	thanhtructruong2014@gmail.com	Sunrise city north toà x2 căn 2405	0	2026-04-13 19:05:51.99128+00	user	\N
953	50b0978c-5fa3-44d1-86be-88ab63d3289d	RYU JUNGSUN	01021048416	ccnj11141801@gmail.com	\N	0	2026-04-14 04:51:55.631411+00	user	\N
954	\N	Ig Kl Lil Như	0777783293	\N	B2810 Sun Cosmo, Trần Thị Lý,Ngũ Hành Sơn, Đà Nẵng\n	0	2026-04-14 06:10:03.804215+00	user	\N
955	\N	Ig hạnh nguyên	0832204686	\N	Đường số 1 khu dân cư Thạnh Mỹ phường Lê Bình quận Cái Răng Cần Thơ	0	2026-04-14 06:15:35.089976+00	user	\N
956	\N	Ig i am autumn	0866841318	\N	số 14 ngõ 252 ngõ chợ khâm thiên, phường trung phụng, quận đống đa, hà nội	0	2026-04-14 06:16:00.030402+00	user	\N
957	\N	Ig lan dang	0336609654	\N	137 kỳ đồng , phường thanh khê đông quận thanh khê tp đà nẵng	0	2026-04-14 06:17:05.475798+00	user	\N
958	\N	Ig tra nguyen	 0856574104 	\N	400/8B Ung Văn Khiêm, P.25, Q.Bình Thạnh \nToà nhà Hahalolo	0	2026-04-14 06:17:42.446385+00	user	\N
959	\N	Ig stunnarchives	6562098281	\N	 30617 casewell pl Wesley chapel Fl, 33545	0	2026-04-14 06:19:31.440861+00	user	\N
960	\N	Ig katherine tran	+84 93 8921937	\N	Empire city- tòa linden - T1A -15.01	0	2026-04-14 06:21:49.929529+00	user	\N
961	\N	Ig cheetah.88539212	0904266855	\N	Toà W3, Vinhomes westpoint Pham Hung, phường Mễ Trì, Nam Từ Liêm, Hà Nội	0	2026-04-14 06:22:34.575419+00	user	\N
963	\N	sofia pham	0968461084	\N	Cường Thịnh Homestay - Trọ Nhatrang, 158/12, Hương Lộ Ngọc Hiệp, Xóm Hộ, Phường Ngọc Hiệp, Thành Phố Nha Trang, Khánh Hòa	0	2026-04-14 08:09:30.576479+00	user	\N
964	c3d220cc-fa64-4610-83c1-de022688770e	monmi	8822452109	imonmibor1@gmail.com	\N	0	2026-04-14 12:11:52.053908+00	user	\N
965	\N	Ig amy 	+61 493 016 563	\N	1204/10 Vista St, Surfers Paradise, Gold Coast, 4217, Australia	0	2026-04-14 15:02:07.254904+00	user	\N
966	\N	Ig _byphung_	0396825329	\N	số nhà 26 ngõ 280, đường Trần Nguyên Hãn, Lê Chân, Hải Phòng	0	2026-04-14 15:03:05.990028+00	user	\N
967	\N	Ig joetran23_11	0919118600	\N	222 hà tôn quyền p6 q11 hcm \n	0	2026-04-14 15:06:18.565125+00	user	\N
968	\N	Ig phạm mỹ	0375868570	\N	30A, đường số 2, Cát Lái, Thủ Đức, HCM	0	2026-04-14 15:06:53.991002+00	user	\N
969	\N	Ig ha phung 	0919220469	\N	60 Huyền Trân Công Chúa, Hội An Đông, Đà Nẵng\nĐịa chỉ cũ: 60 Huyền Trân Công Chúa, p.Cẩm Châu, Hội An, Quảng Nam	0	2026-04-14 15:07:33.388637+00	user	\N
970	\N	Ig đinh hồng anh	0934932239    	\N	A-013 Chung cư GREEN RIVER, Phạm Thế Hiển, Phường 6, Quận 8, Sài Gòn 	0	2026-04-14 15:08:14.675304+00	user	\N
971	\N	Lương Thị Bích Phượng	0707707878	luongphuong3444@gmail.com	305 Võ Thành Trang	0	2026-04-14 15:11:07.744534+00	user	\N
972	\N	Ig avoe.official 	0365786150	\N	o A10 KCN Minh Hưng-sikico, Xã Đồng Nơ, Huyện Hớn quản, Tỉnh Bình Phước \nCÔNG TY NGŨ KIM YOUDE	0	2026-04-14 15:29:11.904705+00	user	\N
973	\N	Lê Ngọc Anh	033 2708119	duong.xu.98@gmail.com	Số 5 ngõ 44 hào nam phường ô chợ dừa đống đa hà nội	0	2026-04-14 18:24:41.767124+00	user	\N
974	7695d0e8-751d-4329-bc0f-3c72ac754a24	Luisa Barrios	8177233368	luisacbarrios03@gmail.com	\N	0	2026-04-14 23:13:25.26383+00	user	\N
962	06e31dd2-bd7a-457d-9bb4-ee5cd797ef91	Nguyễn Khánh Linh	0345992382	daizuki8@gmail.com	số nhà 93C ngách 99/110 định công hạ	0	2026-04-14 06:34:56.629361+00	user	\N
\.


--
-- TOC entry 4079 (class 0 OID 17721)
-- Dependencies: 419
-- Data for Name: expense_categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.expense_categories (id, name, description) FROM stdin;
1	Hàng lỗi	\N
2	giấy carton đóng gói	\N
3	tag thank card + tag gắn áo	\N
4	Ads instagram	\N
5	Giấy Thơm	\N
6	Giấy Thơm	\N
7	Bịch đóng gói	\N
8	Đăng ký hộ kinh doanh	\N
9	book studio	\N
10	book studio	\N
11	chụp hình 3D ss33	\N
12	Cân điện tử	\N
13	Làm rập Tài	\N
14	mua hoá đơn chũ ký số	\N
15	Kol	\N
16	Kol	\N
17	Tiền Bị khờ	\N
18	Tiền Bị khờ	\N
19	tiền thuê máy ảnh chụp	\N
20	Lương tháng3	\N
21	kol chun	\N
22	kol chun	\N
23	kol chun	\N
\.


--
-- TOC entry 4081 (class 0 OID 17729)
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
13	1	4	1008228	2026-03-06	1/2 - 6-3	2026-03-06 15:24:48.934596+00
17	1	1	60000	2026-03-07	Hàng lỗi: 1x BOWTIE BRA (Free - Xám) - Lý do: Test 4	2026-03-07 09:43:30.086718+00
19	1	8	2000000	2026-03-09		2026-03-09 14:01:01.585452+00
20	1	4	1008228	2026-03-14	ads ins	2026-03-14 13:20:09.228149+00
21	1	10	1200000	2026-03-16	chụp ss3 + ss2	2026-03-16 12:55:56.467644+00
22	1	11	972000	2026-03-16	áo 2 dây và váy ngắn	2026-03-16 12:56:34.946835+00
23	1	12	90000	2026-03-16		2026-03-16 12:57:08.522215+00
24	1	13	800000	2026-03-16	Áo 2dây + 2bikini	2026-03-16 12:57:44.307428+00
25	1	14	4900000	2026-03-17		2026-03-17 14:52:47.210966+00
26	1	16	600000	2026-03-17	Thanh tuyền	2026-03-17 14:53:32.745424+00
27	1	17	1000000	2026-03-17	Cisup khờ	2026-03-17 14:54:22.625227+00
28	1	4	1265000	2026-03-21	14/3 - 21-3	2026-03-21 16:24:08.912003+00
29	1	19	400000	2026-03-23	thuê máy ảnh tại studio	2026-03-23 17:45:00.477168+00
30	1	9	300000	2026-03-23		2026-03-23 17:45:36.08165+00
31	1	15	9000000	2026-03-23	tiếng 1tr7	2026-03-23 17:46:13.346616+00
32	1	4	1008228	2026-03-27	21/3-27/3	2026-03-27 16:50:02.466863+00
33	1	20	24585000	2026-03-31	Lương tháng 3	2026-03-31 16:46:56.499874+00
34	1	16	1000000	2026-04-02	kol kim thúy	2026-04-02 14:40:42.901225+00
35	1	15	700000	2026-04-04	kol an phạm	2026-04-04 13:00:50.759128+00
36	1	15	1000000	2026-04-04	kol quyên	2026-04-04 13:01:04.22712+00
37	1	4	2016000	2026-04-06	28/3 - 6/4	2026-04-06 04:52:23.059976+00
38	1	15	2500000	2026-04-11	kol chun	2026-04-11 10:33:35.56787+00
39	1	15	3000000	2026-04-11	Kol Linh Chip	2026-04-11 11:11:28.950481+00
40	1	4	1010000	2026-04-11	6/4-11/4	2026-04-11 15:51:54.665612+00
41	1	15	2000000	2026-04-12	KoL sym meo	2026-04-12 10:09:33.257226+00
42	1	15	2200000	2026-04-12	kol miến	2026-04-12 15:26:13.182249+00
43	1	1	999999	2026-04-14	lập soạn đơn	2026-04-14 12:35:37.618862+00
\.


--
-- TOC entry 4066 (class 0 OID 17602)
-- Dependencies: 406
-- Data for Name: inventory_batches; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.inventory_batches (id, store_id, variant_id, purchase_item_id, original_quantity, quantity_remaining, cost_price, created_at, batch_name, supplier_id, is_adjustment, notes) FROM stdin;
50	1	71	50	19	0	100000	2026-01-27 10:21:14.166264+00	\N	\N	f	\N
75	1	93	\N	1	0	100000	2026-01-28 16:29:17.826971+00	\N	\N	t	Điều chỉnh nhanh tại Admin
39	1	51	39	6	6	100000	2026-01-27 10:16:40.435187+00	\N	\N	f	\N
19	1	89	19	15	0	150000	2026-01-27 10:09:47.053578+00	\N	\N	f	\N
29	1	84	29	22	0	100000	2026-01-27 10:12:45.700504+00	\N	\N	f	\N
15	1	98	15	10	0	100000	2026-01-27 10:08:18.465898+00	\N	\N	f	\N
34	1	77	34	1	0	100000	2026-01-27 10:15:07.074612+00	\N	\N	f	\N
58	1	101	\N	-1	-1	100000	2026-01-28 12:24:06.368821+00	\N	\N	t	Cập nhật trực tiếp
25	1	81	25	17	0	100000	2026-01-27 10:11:46.289523+00	\N	\N	f	\N
77	1	94	\N	1	0	100000	2026-01-28 16:34:09.608799+00	\N	\N	t	Điều chỉnh nhanh tại Admin
8	1	97	8	9	0	100000	2026-01-27 10:06:55.273689+00	\N	\N	f	\N
49	1	70	49	5	0	100000	2026-01-27 10:20:51.315734+00	\N	\N	f	\N
38	1	49	38	10	0	100000	2026-01-27 10:16:27.031207+00	\N	\N	f	\N
56	1	101	\N	-1	-1	100000	2026-01-28 12:23:54.854373+00	\N	\N	t	Điều chỉnh nhanh tại Admin
57	1	101	\N	-1	-1	100000	2026-01-28 12:23:54.887698+00	\N	\N	t	Điều chỉnh nhanh tại Admin
9	1	97	9	9	0	100000	2026-01-27 10:06:56.088172+00	\N	\N	f	\N
144	1	81	\N	15	0	100000	2026-03-05 11:09:08.608796+00	\N	\N	t	Điều chỉnh nhanh tại Admin
24	1	80	24	14	0	100000	2026-01-27 10:11:27.589533+00	\N	\N	f	\N
31	1	86	31	22	0	100000	2026-01-27 10:13:12.558445+00	\N	\N	f	\N
66	1	78	\N	-1	-1	100000	2026-01-28 15:43:46.781045+00	\N	\N	t	Điều chỉnh nhanh tại Admin
63	1	35	\N	-10	-10	100000	2026-01-28 15:06:04.077674+00	\N	\N	t	Điều chỉnh nhanh tại Admin
178	1	78	94	10	0	120000	2026-03-15 16:44:53.75442+00	\N	\N	f	\N
65	1	78	\N	1	0	100000	2026-01-28 15:43:26.149321+00	\N	\N	t	Điều chỉnh nhanh tại Admin
74	1	35	\N	1	1	100000	2026-01-28 16:27:54.272133+00	\N	\N	t	Điều chỉnh nhanh tại Admin
5	1	101	5	20	0	100000	2026-01-27 10:01:29.522212+00	\N	\N	f	\N
10	1	92	10	10	0	100000	2026-01-27 10:07:17.134568+00	\N	\N	f	\N
67	1	78	\N	1	0	100000	2026-01-28 15:44:09.052341+00	\N	\N	t	Điều chỉnh nhanh tại Admin
70	1	77	\N	3	0	100000	2026-01-28 16:01:33.893814+00	\N	\N	t	Điều chỉnh nhanh tại Admin
40	1	52	40	6	3	100000	2026-01-27 10:16:54.447379+00	\N	\N	f	\N
80	1	95	\N	11	0	100000	2026-01-31 16:36:37.067685+00	\N	\N	t	Điều chỉnh nhanh tại Admin
166	1	96	85	16	0	120000	2026-03-12 15:23:45.863706+00	\N	\N	f	\N
17	1	99	17	10	1	100000	2026-01-27 10:08:40.495591+00	\N	\N	f	\N
72	1	102	\N	2	0	150000	2026-01-28 16:25:18.145996+00	\N	\N	t	Điều chỉnh nhanh tại Admin
30	1	85	30	19	0	100000	2026-01-27 10:12:58.541798+00	\N	\N	f	\N
23	1	79	23	16	0	100000	2026-01-27 10:11:14.297816+00	\N	\N	f	\N
28	1	83	28	14	0	100000	2026-01-27 10:12:33.646+00	\N	\N	f	\N
37	1	48	37	1	0	100000	2026-01-27 10:16:06.461412+00	\N	\N	f	\N
6	1	100	6	15	0	115000	2026-01-27 10:01:52.209441+00	\N	\N	f	\N
16	1	98	16	10	4	100000	2026-01-27 10:08:20.964716+00	\N	\N	f	\N
181	1	74	97	9	0	120000	2026-03-16 06:58:35.604748+00	\N	\N	f	\N
59	1	101	54	1	0	100000	2026-01-28 12:38:14.70695+00	\N	\N	f	\N
53	1	74	53	9	0	100000	2026-01-27 10:23:03.856962+00	\N	\N	f	\N
3	1	102	3	6	0	150000	2026-01-27 10:01:01.964848+00	\N	\N	f	\N
4	1	101	4	20	0	100000	2026-01-27 10:01:27.589277+00	\N	\N	f	\N
13	1	94	13	10	0	100000	2026-01-27 10:07:48.046742+00	\N	\N	f	\N
42	1	45	42	12	3	60000	2026-01-27 10:17:44.344532+00	\N	\N	f	\N
69	1	23	56	30	0	100000	2026-01-28 15:49:44.066223+00	\N	\N	f	\N
78	1	93	\N	6	0	100000	2026-01-31 16:35:28.022421+00	\N	\N	t	Điều chỉnh nhanh tại Admin
26	1	82	26	19	0	100000	2026-01-27 10:12:18.200379+00	\N	\N	f	\N
36	1	47	36	7	0	100000	2026-01-27 10:15:45.866217+00	\N	\N	f	\N
2	1	35	2	10	8	100000	2026-01-26 16:20:55.194128+00	\N	\N	f	\N
45	1	33	45	11	0	100000	2026-01-27 10:19:56.877953+00	\N	\N	f	\N
14	1	95	14	10	0	100000	2026-01-27 10:08:02.881817+00	\N	\N	f	\N
20	1	90	20	22	0	150000	2026-01-27 10:10:00.550071+00	\N	\N	f	\N
52	1	24	52	17	0	100000	2026-01-27 10:21:52.40757+00	\N	\N	f	\N
51	1	72	51	2	0	100000	2026-01-27 10:21:26.84691+00	\N	\N	f	\N
44	1	36	44	15	0	100000	2026-01-27 10:19:17.095331+00	\N	\N	f	\N
60	1	92	\N	1	0	100000	2026-01-28 12:38:23.864251+00	\N	\N	t	Cập nhật trực tiếp
12	1	93	12	10	0	100000	2026-01-27 10:07:34.62482+00	\N	\N	f	\N
35	1	78	35	4	0	100000	2026-01-27 10:15:24.43308+00	\N	\N	f	\N
33	1	76	33	14	0	100000	2026-01-27 10:14:51.579802+00	\N	\N	f	\N
27	1	82	27	19	0	100000	2026-01-27 10:12:19.893779+00	\N	\N	f	\N
48	1	69	48	5	0	100000	2026-01-27 10:20:41.489582+00	\N	\N	f	\N
124	1	74	\N	30	0	100000	2026-02-11 17:09:01.813497+00	\N	\N	t	Điều chỉnh nhanh tại Admin
76	1	94	\N	2	0	100000	2026-01-28 16:29:30.557113+00	\N	\N	t	Điều chỉnh nhanh tại Admin
79	1	94	\N	5	0	100000	2026-01-31 16:36:04.788618+00	\N	\N	t	Điều chỉnh nhanh tại Admin
18	1	88	18	15	0	150000	2026-01-27 10:09:29.712624+00	\N	\N	f	\N
61	1	101	\N	-2	0	100000	2026-01-28 12:54:59.002217+00	\N	\N	t	Cập nhật trực tiếp
175	1	72	92	5	0	120000	2026-03-13 11:44:23.279197+00	\N	\N	f	\N
21	1	91	21	17	0	150000	2026-01-27 10:10:14.78215+00	\N	\N	f	\N
82	1	99	\N	6	6	100000	2026-01-31 16:38:23.640761+00	\N	\N	t	Điều chỉnh nhanh tại Admin
169	1	73	88	10	0	120000	2026-03-12 15:35:39.589201+00	\N	\N	f	\N
73	1	102	\N	1	0	150000	2026-01-28 16:27:07.858101+00	\N	\N	t	Điều chỉnh nhanh tại Admin
126	1	73	\N	1	0	100000	2026-02-27 04:37:54.071618+00	\N	\N	t	Điều chỉnh nhanh tại Admin
111	1	96	\N	1	0	100000	2026-02-05 06:04:35.304656+00	\N	\N	t	Điều chỉnh nhanh tại Admin
94	1	96	\N	1	0	100000	2026-02-03 05:55:26.228818+00	\N	\N	t	Điều chỉnh nhanh tại Admin
112	1	96	69	10	0	100000	2026-02-05 08:10:15.354197+00	\N	\N	f	\N
86	1	49	\N	20	5	100000	2026-01-31 16:47:52.938654+00	\N	\N	t	Điều chỉnh nhanh tại Admin
125	1	70	\N	1	0	100000	2026-02-25 06:57:40.436453+00	\N	\N	t	Điều chỉnh nhanh tại Admin
114	1	96	71	17	0	100000	2026-02-06 12:58:00.297708+00	\N	\N	f	\N
95	1	90	\N	1	0	150000	2026-02-03 05:57:37.854938+00	\N	\N	t	Điều chỉnh nhanh tại Admin
100	1	81	\N	1	0	100000	2026-02-03 06:56:53.71384+00	\N	\N	t	Điều chỉnh nhanh tại Admin
115	1	74	72	16	0	100000	2026-02-06 12:58:53.764705+00	\N	\N	f	\N
121	1	35	\N	1	1	100000	2026-02-10 15:02:51.741533+00	\N	\N	t	Điều chỉnh nhanh tại Admin
113	1	102	70	9	0	120000	2026-02-05 08:12:35.117236+00	\N	\N	f	\N
68	1	73	55	80	0	100000	2026-01-28 15:45:41.518783+00	\N	\N	f	\N
92	1	73	\N	1	0	100000	2026-02-02 14:07:28.374147+00	\N	\N	t	Điều chỉnh nhanh tại Admin
96	1	73	59	47	0	100000	2026-02-03 06:45:46.464457+00	\N	\N	f	\N
107	1	73	65	5	0	100000	2026-02-04 09:32:15.930946+00	\N	\N	f	\N
102	1	96	63	10	0	100000	2026-02-03 14:38:59.265787+00	\N	\N	f	\N
103	1	74	64	10	0	100000	2026-02-03 14:39:33.758546+00	\N	\N	f	\N
99	1	89	62	19	0	150000	2026-02-03 06:48:47.912817+00	\N	\N	f	\N
7	1	96	7	22	0	100000	2026-01-27 10:05:17.272177+00	\N	\N	f	\N
104	1	96	\N	1	0	100000	2026-02-04 08:34:26.078812+00	\N	\N	t	Điều chỉnh nhanh tại Admin
91	1	96	\N	1	0	100000	2026-02-02 14:07:16.977229+00	\N	\N	t	Điều chỉnh nhanh tại Admin
32	1	75	32	14	0	100000	2026-01-27 10:14:36.713263+00	\N	\N	f	\N
118	1	96	73	12	0	100000	2026-02-08 15:09:28.297658+00	\N	\N	f	\N
106	1	96	\N	2	0	100000	2026-02-04 09:31:34.832904+00	\N	\N	t	Điều chỉnh nhanh tại Admin
116	1	83	\N	1	0	100000	2026-02-08 04:18:39.159703+00	\N	\N	t	Điều chỉnh nhanh tại Admin
170	1	79	\N	10	0	100000	2026-03-12 17:06:10.653246+00	\N	\N	t	Điều chỉnh nhanh tại Admin
117	1	83	\N	2	0	100000	2026-02-08 05:26:06.930423+00	\N	\N	t	Điều chỉnh nhanh tại Admin
146	1	101	\N	20	0	100000	2026-03-06 14:12:52.345405+00	\N	\N	t	Điều chỉnh nhanh tại Admin
130	1	73	\N	1	0	100000	2026-02-27 13:45:28.449056+00	\N	\N	t	Điều chỉnh nhanh tại Admin
120	1	73	\N	1	0	100000	2026-02-09 07:43:12.93161+00	\N	\N	t	Điều chỉnh nhanh tại Admin
128	1	73	\N	9	0	100000	2026-02-27 12:07:28.916721+00	\N	\N	t	Điều chỉnh nhanh tại Admin
71	1	77	57	20	0	100000	2026-01-28 16:02:18.785583+00	\N	\N	f	\N
131	1	73	\N	22	0	100000	2026-02-28 11:45:20.506086+00	\N	\N	t	Điều chỉnh nhanh tại Admin
90	1	23	\N	1	0	100000	2026-02-02 14:01:00.104034+00	\N	\N	t	Điều chỉnh nhanh tại Admin
97	1	92	60	1	0	100000	2026-02-03 06:46:35.972541+00	\N	\N	f	\N
11	1	92	11	10	0	100000	2026-01-27 10:07:18.342224+00	\N	\N	f	\N
129	1	73	\N	1	0	100000	2026-02-27 12:47:16.554065+00	\N	\N	t	Điều chỉnh nhanh tại Admin
135	1	101	\N	5	0	100000	2026-03-02 10:27:12.25215+00	\N	\N	t	Điều chỉnh nhanh tại Admin
108	1	77	66	4	0	100000	2026-02-04 09:32:37.819755+00	\N	\N	f	\N
138	1	101	\N	14	0	100000	2026-03-03 09:37:31.964846+00	\N	\N	t	Điều chỉnh nhanh tại Admin
83	1	80	\N	3	0	100000	2026-01-31 16:41:27.898633+00	\N	\N	t	Điều chỉnh nhanh tại Admin
127	1	24	\N	10	0	100000	2026-02-27 12:04:38.313041+00	\N	\N	t	Điều chỉnh nhanh tại Admin
139	1	102	\N	1	0	120000	2026-03-03 09:37:34.986857+00	\N	\N	t	Điều chỉnh nhanh tại Admin
140	1	24	\N	1	0	100000	2026-03-03 09:49:56.590917+00	\N	\N	t	Điều chỉnh nhanh tại Admin
136	1	101	\N	1	0	100000	2026-03-02 15:02:03.47538+00	\N	\N	t	Điều chỉnh nhanh tại Admin
137	1	101	\N	1	0	100000	2026-03-02 15:14:01.680769+00	\N	\N	t	Điều chỉnh nhanh tại Admin
101	1	49	\N	1	2	100000	2026-02-03 06:57:01.748953+00	\N	\N	t	Điều chỉnh nhanh tại Admin
84	1	80	\N	1	0	100000	2026-01-31 16:42:28.36622+00	\N	\N	t	Điều chỉnh nhanh tại Admin
167	1	77	86	9	0	120000	2026-03-12 15:24:04.503415+00	\N	\N	f	\N
147	1	102	\N	2	0	120000	2026-03-06 14:13:01.531979+00	\N	\N	t	Điều chỉnh nhanh tại Admin
141	1	102	\N	15	0	120000	2026-03-04 10:41:03.949431+00	\N	\N	t	Điều chỉnh nhanh tại Admin
110	1	92	68	1	0	100000	2026-02-04 09:33:13.318221+00	\N	\N	f	\N
176	1	78	\N	1	0	120000	2026-03-13 14:26:23.971093+00	\N	\N	t	Điều chỉnh nhanh tại Admin
145	1	102	\N	1	0	120000	2026-03-06 04:18:12.194807+00	\N	\N	t	Điều chỉnh nhanh tại Admin
81	1	97	\N	12	0	100000	2026-01-31 16:37:40.809508+00	\N	\N	t	Điều chỉnh nhanh tại Admin
85	1	47	\N	1	0	100000	2026-01-31 16:46:59.771474+00	\N	\N	t	Điều chỉnh nhanh tại Admin
142	1	24	\N	10	0	100000	2026-03-04 12:17:12.20472+00	\N	\N	t	Điều chỉnh nhanh tại Admin
109	1	78	67	7	0	100000	2026-02-04 09:32:52.032439+00	\N	\N	f	\N
87	1	50	\N	8	0	100000	2026-01-31 16:48:28.554369+00	\N	\N	t	Điều chỉnh nhanh tại Admin
179	1	81	95	19	0	120000	2026-03-16 06:57:47.042631+00	\N	\N	f	\N
89	1	69	\N	2	0	100000	2026-01-31 16:52:29.189704+00	\N	\N	t	Điều chỉnh nhanh tại Admin
161	1	78	81	5	0	120000	2026-03-10 14:27:14.193097+00	\N	\N	f	\N
152	1	45	\N	-1	0	60000	2026-03-07 09:43:29.856183+00	\N	\N	t	[HÀNG LỖI] Test 4
162	1	78	\N	1	0	120000	2026-03-10 14:41:27.476477+00	\N	\N	t	Điều chỉnh nhanh tại Admin
159	1	102	79	10	0	140000	2026-03-10 14:26:24.430682+00	\N	\N	f	\N
190	1	73	\N	2	0	120000	2026-03-17 14:49:21.542079+00	\N	\N	t	Điều chỉnh nhanh tại Admin
64	1	50	\N	10	0	100000	2026-01-28 15:41:43.744138+00	\N	\N	t	Điều chỉnh nhanh tại Admin
182	1	102	\N	1	0	140000	2026-03-16 07:03:27.048653+00	\N	\N	t	Điều chỉnh nhanh tại Admin
195	1	101	104	5	0	120000	2026-03-18 13:36:05.25125+00	\N	\N	f	\N
98	1	88	61	19	0	150000	2026-02-03 06:48:34.877034+00	\N	\N	f	\N
157	1	78	\N	1	0	100000	2026-03-09 10:58:56.920104+00	\N	\N	t	Điều chỉnh nhanh tại Admin
164	1	96	83	5	0	120000	2026-03-11 11:10:34.741591+00	\N	\N	f	\N
183	1	102	\N	1	0	140000	2026-03-16 07:05:45.697841+00	\N	\N	t	Điều chỉnh nhanh tại Admin
153	1	73	76	30	0	110000	2026-03-08 08:06:56.094099+00	\N	\N	f	\N
199	1	79	108	10	0	120000	2026-03-20 12:02:42.048078+00	\N	\N	f	\N
154	1	75	77	20	0	110000	2026-03-08 08:07:20.11168+00	\N	\N	f	\N
208	1	101	114	13	0	120000	2026-03-23 16:12:11.751243+00	\N	\N	f	\N
158	1	78	\N	1	0	100000	2026-03-09 10:59:05.299259+00	\N	\N	t	Điều chỉnh nhanh tại Admin
156	1	83	78	10	0	120000	2026-03-09 10:50:53.788938+00	\N	\N	f	\N
212	1	69	118	13	5	120000	2026-03-25 13:06:01.022252+00	\N	\N	f	\N
194	1	75	103	5	0	120000	2026-03-18 12:54:11.625513+00	\N	\N	f	\N
217	1	162	121	10	2	120000	2026-03-26 12:23:14.058335+00	\N	\N	f	\N
205	\N	131	\N	0	0	0	2026-03-21 13:13:06.515228+00	\N	\N	t	Lô âm tự động (Khách Preorder)
180	1	83	96	12	0	120000	2026-03-16 06:58:07.910092+00	\N	\N	f	\N
189	1	82	\N	7	0	100000	2026-03-17 14:48:25.751881+00	\N	\N	t	Điều chỉnh nhanh tại Admin
168	1	78	87	5	0	120000	2026-03-12 15:24:17.784757+00	\N	\N	f	\N
193	1	73	102	10	0	120000	2026-03-18 12:53:43.829532+00	\N	\N	f	\N
173	1	73	90	10	0	120000	2026-03-13 11:43:51.785624+00	\N	\N	f	\N
155	1	75	\N	1	0	110000	2026-03-09 10:50:22.886332+00	\N	\N	t	Điều chỉnh nhanh tại Admin
165	1	94	84	5	0	120000	2026-03-11 11:10:49.497444+00	\N	\N	f	\N
172	1	83	89	5	0	120000	2026-03-13 11:43:34.815892+00	\N	\N	f	\N
222	1	161	126	10	2	120000	2026-03-26 12:24:06.013456+00	\N	\N	f	\N
188	1	84	\N	6	0	100000	2026-03-17 14:47:12.082646+00	\N	\N	t	Điều chỉnh nhanh tại Admin
163	1	76	82	12	0	120000	2026-03-11 11:10:12.376319+00	\N	\N	f	\N
207	1	91	\N	1	0	150000	2026-03-23 16:00:46.33753+00	\N	\N	t	Điều chỉnh nhanh tại Admin
202	1	48	111	10	1	120000	2026-03-20 12:03:31.722762+00	\N	\N	f	\N
214	1	102	\N	1	0	140000	2026-03-26 12:09:40.851755+00	\N	\N	t	Điều chỉnh nhanh tại Admin
187	1	95	99	12	0	120000	2026-03-17 12:37:33.005646+00	\N	\N	f	\N
201	1	78	110	5	0	120000	2026-03-20 12:03:17.929841+00	\N	\N	f	\N
186	1	102	98	15	0	140000	2026-03-17 12:37:04.574881+00	\N	\N	f	\N
196	1	72	105	6	0	120000	2026-03-19 11:40:36.062585+00	\N	\N	f	\N
215	1	23	120	31	0	110000	2026-03-26 12:10:38.455351+00	\N	\N	f	\N
204	1	83	\N	4	0	120000	2026-03-20 14:47:59.579621+00	\N	\N	t	Điều chỉnh nhanh tại Admin
198	1	101	107	3	0	120000	2026-03-19 11:41:15.793889+00	\N	\N	f	\N
185	1	90	\N	2	0	150000	2026-03-16 16:04:30.468587+00	\N	\N	t	Điều chỉnh nhanh tại Admin
221	1	160	125	10	0	120000	2026-03-26 12:24:06.013456+00	\N	\N	f	\N
219	1	158	123	10	1	120000	2026-03-26 12:24:06.013456+00	\N	\N	f	\N
143	1	24	\N	14	0	100000	2026-03-05 11:08:55.402751+00	\N	\N	t	Điều chỉnh nhanh tại Admin
216	1	102	\N	1	0	140000	2026-03-26 12:11:35.281948+00	\N	\N	t	Điều chỉnh nhanh tại Admin
174	1	77	91	1	0	120000	2026-03-13 11:44:06.688554+00	\N	\N	f	\N
200	1	75	109	7	0	120000	2026-03-20 12:02:58.234426+00	\N	\N	f	\N
192	1	97	101	20	0	120000	2026-03-18 12:53:26.84469+00	\N	\N	f	\N
226	1	102	\N	1	0	140000	2026-03-26 16:35:07.210932+00	\N	\N	t	Điều chỉnh nhanh tại Admin
223	1	101	\N	1	0	120000	2026-03-26 14:33:25.278505+00	\N	\N	t	Điều chỉnh nhanh tại Admin
227	\N	164	\N	0	-1	0	2026-03-26 19:00:29.473088+00	\N	\N	t	Lô âm tự động (Khách Preorder)
132	1	23	\N	34	0	100000	2026-02-28 11:45:26.53442+00	\N	\N	t	Điều chỉnh nhanh tại Admin
218	1	163	122	10	4	120000	2026-03-26 12:24:06.013456+00	\N	\N	f	\N
220	1	159	124	10	8	120000	2026-03-26 12:24:06.013456+00	\N	\N	f	\N
229	1	162	128	18	19	120000	2026-03-27 12:07:21.422151+00	\N	\N	f	\N
213	1	71	119	6	0	120000	2026-03-25 13:06:13.001417+00	\N	\N	f	\N
209	1	143	115	9	0	120000	2026-03-24 15:21:01.15472+00	\N	\N	f	\N
177	1	79	93	8	0	120000	2026-03-14 13:05:15.255893+00	\N	\N	f	\N
228	1	160	127	20	14	120000	2026-03-27 12:07:21.422151+00	\N	\N	f	\N
197	1	70	106	9	3	120000	2026-03-19 11:40:59.564654+00	\N	\N	f	\N
160	1	100	80	18	0	120000	2026-03-10 14:26:49.710526+00	\N	\N	f	\N
225	1	86	\N	3	1	100000	2026-03-26 16:07:34.175076+00	\N	\N	t	Điều chỉnh nhanh tại Admin
224	1	88	\N	10	0	150000	2026-03-26 14:45:48.031737+00	\N	\N	t	Điều chỉnh nhanh tại Admin
171	1	85	\N	10	0	100000	2026-03-12 17:06:22.356891+00	\N	\N	t	Điều chỉnh nhanh tại Admin
191	1	95	100	8	5	120000	2026-03-18 12:53:05.255495+00	\N	\N	f	\N
210	1	24	116	20	0	120000	2026-03-24 15:21:17.779535+00	\N	\N	f	\N
232	1	163	131	19	19	120000	2026-03-27 12:07:21.422151+00	\N	\N	f	\N
233	1	161	132	13	13	120000	2026-03-27 12:07:21.422151+00	\N	\N	f	\N
274	1	101	\N	1	0	110000	2026-03-31 14:24:55.761126+00	\N	\N	t	Điều chỉnh nhanh tại Admin
244	1	101	\N	3	0	110000	2026-03-29 16:24:07.293293+00	\N	\N	t	Điều chỉnh nhanh tại Admin
281	1	101	\N	1	0	110000	2026-04-01 03:06:59.494772+00	\N	\N	t	Điều chỉnh nhanh tại Admin
255	1	100	\N	1	0	120000	2026-03-30 14:12:30.025785+00	\N	\N	t	Điều chỉnh nhanh tại Admin
266	1	96	\N	4	0	120000	2026-03-30 16:16:37.878737+00	\N	\N	t	Điều chỉnh nhanh tại Admin
230	1	159	129	19	20	120000	2026-03-27 12:07:21.422151+00	\N	\N	f	\N
256	1	102	\N	1	0	120000	2026-03-30 14:15:34.495638+00	\N	\N	t	Điều chỉnh nhanh tại Admin
231	1	158	130	19	26	120000	2026-03-27 12:07:21.422151+00	\N	\N	f	\N
282	1	74	\N	1	0	120000	2026-04-01 12:32:42.554011+00	\N	\N	t	Điều chỉnh nhanh tại Admin
238	1	101	137	7	0	110000	2026-03-29 12:32:44.049454+00	\N	\N	f	\N
257	1	102	\N	1	0	120000	2026-03-30 14:25:30.506657+00	\N	\N	t	Điều chỉnh nhanh tại Admin
258	1	102	\N	1	0	120000	2026-03-30 14:26:50.012057+00	\N	\N	t	Điều chỉnh nhanh tại Admin
259	1	100	\N	1	0	120000	2026-03-30 14:26:50.304953+00	\N	\N	t	Điều chỉnh nhanh tại Admin
242	1	69	141	9	9	120000	2026-03-29 12:34:29.899946+00	\N	\N	f	\N
260	1	102	\N	1	0	120000	2026-03-30 14:28:34.671281+00	\N	\N	t	Điều chỉnh nhanh tại Admin
237	1	102	136	11	0	120000	2026-03-27 12:09:27.854593+00	\N	\N	f	\N
236	1	101	135	6	0	120000	2026-03-27 12:09:27.854593+00	\N	\N	f	\N
261	1	102	\N	1	0	120000	2026-03-30 14:29:21.588498+00	\N	\N	t	Điều chỉnh nhanh tại Admin
262	1	101	\N	1	0	110000	2026-03-30 14:29:22.235025+00	\N	\N	t	Điều chỉnh nhanh tại Admin
234	1	83	133	8	0	120000	2026-03-27 12:07:55.718942+00	\N	\N	f	\N
265	1	102	\N	1	0	120000	2026-03-30 15:42:27.602509+00	\N	\N	t	Điều chỉnh nhanh tại Admin
250	\N	165	\N	0	-1	0	2026-03-29 17:06:11.341217+00	\N	\N	t	Lô âm tự động (Khách Preorder)
263	1	102	\N	1	0	120000	2026-03-30 14:32:34.413206+00	\N	\N	t	Điều chỉnh nhanh tại Admin
246	1	94	\N	4	0	120000	2026-03-29 16:29:13.03981+00	\N	\N	t	Điều chỉnh nhanh tại Admin
276	1	100	\N	1	0	120000	2026-03-31 14:29:27.225423+00	\N	\N	t	Điều chỉnh nhanh tại Admin
286	1	101	\N	4	0	110000	2026-04-01 16:01:03.945865+00	\N	\N	t	Điều chỉnh nhanh tại Admin
264	1	101	\N	1	0	110000	2026-03-30 14:36:53.544357+00	\N	\N	t	Điều chỉnh nhanh tại Admin
277	1	101	\N	1	0	110000	2026-03-31 14:30:01.413957+00	\N	\N	t	Điều chỉnh nhanh tại Admin
278	1	101	\N	1	0	110000	2026-03-31 14:33:00.532444+00	\N	\N	t	Điều chỉnh nhanh tại Admin
203	1	73	112	46	0	120000	2026-03-20 12:03:49.103606+00	\N	\N	f	\N
272	1	100	\N	1	0	120000	2026-03-31 14:21:56.398643+00	\N	\N	t	Điều chỉnh nhanh tại Admin
247	1	96	\N	2	0	120000	2026-03-29 16:30:33.739839+00	\N	\N	t	Điều chỉnh nhanh tại Admin
273	1	100	\N	1	0	120000	2026-03-31 14:23:13.287225+00	\N	\N	t	Điều chỉnh nhanh tại Admin
284	1	100	\N	2	0	120000	2026-04-01 12:50:08.40617+00	\N	\N	t	Điều chỉnh nhanh tại Admin
252	1	164	144	11	0	120000	2026-03-30 14:02:12.377452+00	\N	\N	f	\N
275	1	101	\N	1	0	110000	2026-03-31 14:28:48.604168+00	\N	\N	t	Điều chỉnh nhanh tại Admin
249	1	80	\N	3	2	100000	2026-03-29 16:33:08.212448+00	\N	\N	t	Điều chỉnh nhanh tại Admin
279	1	100	\N	1	0	120000	2026-03-31 14:37:07.568244+00	\N	\N	t	Điều chỉnh nhanh tại Admin
211	1	142	117	36	0	120000	2026-03-25 13:05:37.413636+00	\N	\N	f	\N
269	1	102	148	13	0	120000	2026-03-31 14:16:19.027031+00	\N	\N	f	\N
280	1	101	\N	1	0	110000	2026-03-31 14:43:40.051748+00	\N	\N	t	Điều chỉnh nhanh tại Admin
245	1	92	\N	1	0	100000	2026-03-29 16:26:37.192409+00	\N	\N	t	Điều chỉnh nhanh tại Admin
287	1	102	\N	1	0	120000	2026-04-01 16:01:11.044406+00	\N	\N	t	Điều chỉnh nhanh tại Admin
283	1	101	\N	1	0	110000	2026-04-01 12:43:45.640988+00	\N	\N	t	Điều chỉnh nhanh tại Admin
285	1	101	\N	1	0	110000	2026-04-01 13:17:10.477683+00	\N	\N	t	Điều chỉnh nhanh tại Admin
240	1	23	139	1	0	120000	2026-03-29 12:34:29.899946+00	\N	\N	f	\N
243	1	75	142	28	10	120000	2026-03-29 12:34:29.899946+00	\N	\N	f	\N
289	1	102	\N	1	0	120000	2026-04-02 03:17:03.839313+00	\N	\N	t	Điều chỉnh nhanh tại Admin
294	1	100	\N	1	0	120000	2026-04-02 13:13:34.03223+00	\N	\N	t	Điều chỉnh nhanh tại Admin
271	1	165	150	3	0	120000	2026-03-31 14:16:19.027031+00	\N	\N	f	\N
251	1	165	143	12	0	120000	2026-03-30 14:02:12.377452+00	\N	\N	f	\N
290	1	100	\N	1	0	120000	2026-04-02 13:07:28.079614+00	\N	\N	t	Điều chỉnh nhanh tại Admin
340	1	79	159	22	10	120000	2026-04-06 14:41:10.178316+00	\N	\N	f	\N
235	1	23	134	6	0	120000	2026-03-27 12:09:27.854593+00	\N	\N	f	\N
292	1	102	\N	1	0	120000	2026-04-02 13:11:47.520101+00	\N	\N	t	Điều chỉnh nhanh tại Admin
267	1	82	\N	3	0	100000	2026-03-30 16:18:02.916468+00	\N	\N	t	Điều chỉnh nhanh tại Admin
293	1	102	\N	1	0	120000	2026-04-02 13:13:28.926598+00	\N	\N	t	Điều chỉnh nhanh tại Admin
295	1	101	\N	1	0	110000	2026-04-02 13:14:08.222266+00	\N	\N	t	Điều chỉnh nhanh tại Admin
363	1	47	166	6	3	120000	2026-04-08 15:07:41.743601+00	\N	\N	f	\N
206	1	76	113	12	0	120000	2026-03-21 13:47:26.55693+00	\N	\N	f	\N
254	1	81	146	10	0	120000	2026-03-30 14:02:12.377452+00	\N	\N	f	\N
241	1	71	140	11	0	120000	2026-03-29 12:34:29.899946+00	\N	\N	f	\N
270	1	78	149	13	0	120000	2026-03-31 14:16:19.027031+00	\N	\N	f	\N
253	1	83	145	16	17	120000	2026-03-30 14:02:12.377452+00	\N	\N	f	\N
239	1	83	138	17	0	120000	2026-03-29 12:33:32.594353+00	\N	\N	f	\N
288	1	101	\N	4	0	110000	2026-04-02 03:13:38.464571+00	\N	\N	t	Điều chỉnh nhanh tại Admin
296	1	102	\N	1	0	120000	2026-04-02 13:15:10.807157+00	\N	\N	t	Điều chỉnh nhanh tại Admin
319	1	101	\N	1	0	110000	2026-04-04 04:05:54.718044+00	\N	\N	t	Điều chỉnh nhanh tại Admin
291	1	101	\N	4	0	110000	2026-04-02 13:09:39.195066+00	\N	\N	t	Điều chỉnh nhanh tại Admin
301	1	102	\N	14	0	120000	2026-04-02 17:46:01.435848+00	\N	\N	t	Điều chỉnh nhanh tại Admin
297	1	101	\N	1	0	110000	2026-04-02 17:00:46.366157+00	\N	\N	t	Điều chỉnh nhanh tại Admin
298	1	101	\N	1	0	110000	2026-04-02 17:03:11.765057+00	\N	\N	t	Điều chỉnh nhanh tại Admin
299	1	100	\N	5	0	120000	2026-04-02 17:45:49.959606+00	\N	\N	t	Điều chỉnh nhanh tại Admin
302	1	102	\N	1	0	120000	2026-04-03 03:49:09.010023+00	\N	\N	t	Điều chỉnh nhanh tại Admin
303	1	100	\N	1	0	120000	2026-04-03 03:49:11.017238+00	\N	\N	t	Điều chỉnh nhanh tại Admin
305	1	102	\N	1	0	120000	2026-04-03 04:09:14.426637+00	\N	\N	t	Điều chỉnh nhanh tại Admin
306	1	102	\N	1	0	120000	2026-04-03 14:15:17.637999+00	\N	\N	t	Điều chỉnh nhanh tại Admin
307	1	100	\N	1	0	120000	2026-04-03 14:17:58.351732+00	\N	\N	t	Điều chỉnh nhanh tại Admin
308	1	100	\N	1	0	120000	2026-04-03 14:19:09.800111+00	\N	\N	t	Điều chỉnh nhanh tại Admin
311	1	102	\N	1	0	120000	2026-04-03 14:24:09.261188+00	\N	\N	t	Điều chỉnh nhanh tại Admin
300	1	101	\N	8	0	110000	2026-04-02 17:45:55.583702+00	\N	\N	t	Điều chỉnh nhanh tại Admin
313	1	100	\N	1	0	120000	2026-04-03 14:25:31.841862+00	\N	\N	t	Điều chỉnh nhanh tại Admin
314	1	102	\N	1	0	120000	2026-04-03 14:26:50.026042+00	\N	\N	t	Điều chỉnh nhanh tại Admin
304	1	165	\N	1	0	120000	2026-04-03 03:49:15.003962+00	\N	\N	t	Điều chỉnh nhanh tại Admin
309	1	101	\N	1	0	110000	2026-04-03 14:21:56.823555+00	\N	\N	t	Điều chỉnh nhanh tại Admin
318	1	102	\N	3	0	120000	2026-04-04 04:05:46.903412+00	\N	\N	t	Điều chỉnh nhanh tại Admin
315	1	165	\N	1	0	120000	2026-04-03 14:28:16.469446+00	\N	\N	t	Điều chỉnh nhanh tại Admin
321	1	72	\N	1	0	120000	2026-04-04 04:09:04.065263+00	\N	\N	t	Điều chỉnh nhanh tại Admin
322	1	102	\N	1	0	120000	2026-04-04 04:10:05.139843+00	\N	\N	t	Điều chỉnh nhanh tại Admin
310	1	101	\N	1	0	110000	2026-04-03 14:22:39.272656+00	\N	\N	t	Điều chỉnh nhanh tại Admin
312	1	101	\N	1	0	110000	2026-04-03 14:24:47.000621+00	\N	\N	t	Điều chỉnh nhanh tại Admin
329	1	102	\N	1	0	120000	2026-04-04 13:12:46.823052+00	\N	\N	t	Điều chỉnh nhanh tại Admin
330	1	102	\N	1	0	120000	2026-04-04 13:33:55.948986+00	\N	\N	t	Điều chỉnh nhanh tại Admin
331	1	100	\N	1	0	120000	2026-04-04 13:35:33.677313+00	\N	\N	t	Điều chỉnh nhanh tại Admin
332	1	100	\N	1	0	120000	2026-04-05 03:49:07.366157+00	\N	\N	t	Điều chỉnh nhanh tại Admin
333	1	100	\N	1	0	120000	2026-04-05 12:30:21.216878+00	\N	\N	t	Điều chỉnh nhanh tại Admin
334	1	100	\N	1	0	120000	2026-04-05 12:30:57.547784+00	\N	\N	t	Điều chỉnh nhanh tại Admin
335	1	100	\N	1	0	120000	2026-04-05 12:32:00.731067+00	\N	\N	t	Điều chỉnh nhanh tại Admin
345	1	101	\N	1	0	120000	2026-04-06 14:45:54.066229+00	\N	\N	t	Điều chỉnh nhanh tại Admin
320	1	165	\N	1	0	120000	2026-04-04 04:08:50.078067+00	\N	\N	t	Điều chỉnh nhanh tại Admin
360	1	100	\N	1	0	120000	2026-04-07 16:08:20.685163+00	\N	\N	t	Điều chỉnh nhanh tại Admin
336	1	100	\N	1	0	120000	2026-04-05 12:34:07.003736+00	\N	\N	t	Điều chỉnh nhanh tại Admin
337	1	100	\N	1	0	120000	2026-04-05 12:35:21.530005+00	\N	\N	t	Điều chỉnh nhanh tại Admin
350	1	100	\N	1	0	120000	2026-04-07 04:14:19.358409+00	\N	\N	t	Điều chỉnh nhanh tại Admin
352	1	100	\N	1	0	120000	2026-04-07 04:17:44.105512+00	\N	\N	t	Điều chỉnh nhanh tại Admin
348	1	101	\N	1	0	120000	2026-04-06 16:01:04.755973+00	\N	\N	t	Điều chỉnh nhanh tại Admin
339	1	102	158	2	0	120000	2026-04-06 14:41:10.178316+00	\N	\N	f	\N
317	1	164	\N	1	0	120000	2026-04-03 14:57:32.936725+00	\N	\N	t	Điều chỉnh nhanh tại Admin
338	1	89	\N	1	0	150000	2026-04-06 06:52:29.455483+00	\N	\N	t	Điều chỉnh nhanh tại Admin
351	1	100	\N	1	0	120000	2026-04-07 04:16:36.072502+00	\N	\N	t	Điều chỉnh nhanh tại Admin
323	1	101	152	12	0	120000	2026-04-04 04:58:04.525635+00	\N	\N	f	\N
344	1	100	163	8	0	120000	2026-04-06 14:44:58.171437+00	\N	\N	f	\N
353	1	100	\N	1	0	120000	2026-04-07 04:19:07.764148+00	\N	\N	t	Điều chỉnh nhanh tại Admin
354	1	102	\N	1	0	120000	2026-04-07 04:19:53.085715+00	\N	\N	t	Điều chỉnh nhanh tại Admin
356	1	80	\N	3	3	100000	2026-04-07 09:30:02.266158+00	\N	\N	t	Điều chỉnh nhanh tại Admin
346	1	101	\N	1	0	120000	2026-04-06 14:47:40.982729+00	\N	\N	t	Điều chỉnh nhanh tại Admin
347	1	101	\N	1	0	120000	2026-04-06 14:55:38.940599+00	\N	\N	t	Điều chỉnh nhanh tại Admin
328	1	165	157	6	0	120000	2026-04-04 13:05:48.003134+00	\N	\N	f	\N
341	1	92	160	10	7	120000	2026-04-06 14:41:10.178316+00	\N	\N	f	\N
327	1	164	156	20	0	120000	2026-04-04 13:05:48.003134+00	\N	\N	f	\N
358	1	100	\N	1	0	120000	2026-04-07 14:00:33.959404+00	\N	\N	t	Điều chỉnh nhanh tại Admin
359	1	100	\N	1	0	120000	2026-04-07 14:01:38.412722+00	\N	\N	t	Điều chỉnh nhanh tại Admin
343	1	165	162	20	0	120000	2026-04-06 14:41:10.178316+00	\N	\N	f	\N
324	1	164	153	12	0	120000	2026-04-04 04:58:04.525635+00	\N	\N	f	\N
316	1	77	151	9	5	120000	2026-04-03 14:29:16.511773+00	\N	\N	f	\N
362	1	100	165	9	0	120000	2026-04-08 15:07:41.743601+00	\N	\N	f	\N
357	1	78	\N	9	8	120000	2026-04-07 09:31:46.672338+00	\N	\N	t	Điều chỉnh nhanh tại Admin
326	1	74	155	5	0	120000	2026-04-04 13:05:48.003134+00	\N	\N	f	\N
325	1	72	154	5	0	120000	2026-04-04 13:05:48.003134+00	\N	\N	f	\N
355	1	101	\N	20	0	120000	2026-04-07 09:29:01.690892+00	\N	\N	t	Điều chỉnh nhanh tại Admin
398	1	102	\N	1	0	120000	2026-04-14 06:07:33.837757+00	\N	\N	t	Điều chỉnh nhanh tại Admin
248	1	84	\N	8	5	100000	2026-03-29 16:31:26.872761+00	\N	\N	t	Điều chỉnh nhanh tại Admin
401	1	102	\N	1	0	120000	2026-04-14 06:20:49.013239+00	\N	\N	t	Điều chỉnh nhanh tại Admin
368	1	82	\N	9	9	100000	2026-04-08 17:07:21.01654+00	\N	\N	t	Điều chỉnh nhanh tại Admin
371	1	86	\N	10	10	100000	2026-04-08 17:07:51.132019+00	\N	\N	t	Điều chỉnh nhanh tại Admin
384	1	23	181	32	25	120000	2026-04-09 16:13:51.133348+00	\N	\N	f	\N
268	1	143	147	28	4	120000	2026-03-31 14:16:19.027031+00	\N	\N	f	\N
370	1	85	\N	9	8	100000	2026-04-08 17:07:44.032248+00	\N	\N	t	Điều chỉnh nhanh tại Admin
342	1	73	161	10	0	120000	2026-04-06 14:41:10.178316+00	\N	\N	f	\N
366	1	74	169	4	2	120000	2026-04-08 15:07:41.743601+00	\N	\N	f	\N
375	1	82	172	10	10	120000	2026-04-09 16:13:51.133348+00	\N	\N	f	\N
376	1	81	173	11	11	120000	2026-04-09 16:13:51.133348+00	\N	\N	f	\N
378	1	78	175	16	16	120000	2026-04-09 16:13:51.133348+00	\N	\N	f	\N
379	1	47	176	11	11	120000	2026-04-09 16:13:51.133348+00	\N	\N	f	\N
380	1	92	177	14	14	120000	2026-04-09 16:13:51.133348+00	\N	\N	f	\N
383	1	75	180	5	5	120000	2026-04-09 16:13:51.133348+00	\N	\N	f	\N
367	1	89	\N	1	0	150000	2026-04-08 17:04:28.883413+00	\N	\N	t	Điều chỉnh nhanh tại Admin
405	1	102	\N	2	0	120000	2026-04-14 15:00:07.541497+00	\N	\N	t	Điều chỉnh nhanh tại Admin
372	1	100	170	15	0	120000	2026-04-09 14:47:59.078057+00	\N	\N	f	\N
388	1	143	183	72	72	120000	2026-04-11 15:47:47.817538+00	\N	\N	f	\N
386	1	96	\N	2	1	120000	2026-04-09 16:57:49.104335+00	\N	\N	t	Điều chỉnh nhanh tại Admin
390	1	79	185	10	10	120000	2026-04-11 15:47:47.817538+00	\N	\N	f	\N
391	1	80	186	7	7	120000	2026-04-11 15:47:47.817538+00	\N	\N	f	\N
392	1	92	187	3	3	120000	2026-04-11 15:47:47.817538+00	\N	\N	f	\N
393	1	23	188	19	19	120000	2026-04-11 15:47:47.817538+00	\N	\N	f	\N
394	1	24	189	10	10	120000	2026-04-11 15:47:47.817538+00	\N	\N	f	\N
397	1	94	\N	3	3	120000	2026-04-13 17:46:39.980325+00	\N	\N	t	Điều chỉnh nhanh tại Admin
395	1	85	190	23	23	120000	2026-04-11 15:47:47.817538+00	\N	\N	f	\N
396	1	86	191	10	10	120000	2026-04-11 15:47:47.817538+00	\N	\N	f	\N
407	1	102	\N	8	0	120000	2026-04-14 15:26:25.552666+00	\N	\N	t	Điều chỉnh nhanh tại Admin
385	1	24	\N	5	1	120000	2026-04-09 16:14:05.042515+00	\N	\N	t	Điều chỉnh nhanh tại Admin
403	1	165	192	10	10	120000	2026-04-14 14:59:46.354384+00	\N	\N	f	\N
373	1	100	\N	2	0	120000	2026-04-09 16:10:38.186428+00	\N	\N	t	Điều chỉnh nhanh tại Admin
387	1	102	182	20	0	120000	2026-04-11 10:24:55.571926+00	\N	\N	f	\N
389	1	142	184	15	12	120000	2026-04-11 15:47:47.817538+00	\N	\N	f	\N
381	1	93	178	10	10	120000	2026-04-09 16:13:51.133348+00	\N	\N	f	\N
404	1	100	193	47	40	120000	2026-04-14 14:59:46.354384+00	\N	\N	f	\N
402	1	165	\N	6	5	120000	2026-04-14 13:30:06.641062+00	\N	\N	t	Điều chỉnh nhanh tại Admin
382	1	76	179	22	16	120000	2026-04-09 16:13:51.133348+00	\N	\N	f	\N
369	1	81	\N	10	5	120000	2026-04-08 17:07:28.920357+00	\N	\N	t	Điều chỉnh nhanh tại Admin
400	1	165	\N	1	0	120000	2026-04-14 06:18:46.843354+00	\N	\N	t	Điều chỉnh nhanh tại Admin
364	1	71	167	20	15	120000	2026-04-08 15:07:41.743601+00	\N	\N	f	\N
374	1	101	171	29	9	120000	2026-04-09 16:13:51.133348+00	\N	\N	f	\N
361	1	169	164	99999	99986	1	2026-04-08 10:00:08.452954+00	\N	\N	f	\N
377	1	73	174	27	21	120000	2026-04-09 16:13:51.133348+00	\N	\N	f	\N
365	1	72	168	4	1	120000	2026-04-08 15:07:41.743601+00	\N	\N	f	\N
399	1	165	\N	1	0	120000	2026-04-14 06:16:35.788453+00	\N	\N	t	Điều chỉnh nhanh tại Admin
406	1	164	\N	5	5	120000	2026-04-14 15:26:19.71912+00	\N	\N	t	Điều chỉnh nhanh tại Admin
\.


--
-- TOC entry 4077 (class 0 OID 17704)
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
502	324	73	1	280000	100000
503	324	96	1	250000	100000
504	325	101	1	280000	100000
505	326	46	1	250000	60000
506	327	101	1	280000	100000
507	328	101	1	280000	100000
508	328	81	1	350000	100000
509	329	97	1	250000	100000
510	330	97	1	250000	100000
511	331	101	1	280000	100000
512	331	76	1	350000	100000
513	332	73	1	280000	100000
514	333	73	1	280000	100000
515	334	96	1	250000	100000
516	334	73	1	280000	100000
517	335	73	1	280000	100000
518	336	73	1	280000	100000
519	336	24	1	250000	100000
520	337	89	1	400000	150000
521	337	76	1	350000	100000
522	337	100	1	280000	115000
523	338	73	5	280000	500000
524	338	96	5	250000	500000
525	338	97	1	250000	100000
526	339	101	1	280000	100000
527	339	24	1	250000	100000
528	339	80	1	350000	100000
529	340	96	1	250000	100000
530	340	73	1	280000	100000
531	341	98	1	250000	100000
532	341	81	1	350000	0
533	341	74	1	280000	100000
534	342	84	1	350000	100000
535	342	91	1	400000	150000
536	343	96	1	250000	100000
537	343	73	1	280000	100000
538	344	92	1	250000	100000
539	345	24	1	250000	100000
540	346	97	1	250000	100000
541	347	101	1	280000	100000
542	348	77	1	350000	100000
543	349	96	1	250000	100000
544	350	92	1	250000	100000
545	351	92	1	250000	100000
546	352	92	1	250000	100000
547	353	92	1	250000	100000
548	354	82	1	350000	100000
549	355	23	1	250000	100000
550	355	84	1	350000	100000
551	356	96	1	250000	100000
552	356	23	1	250000	100000
553	357	87	1	300000	120000
554	357	79	1	350000	100000
555	358	24	1	250000	100000
556	358	84	1	350000	100000
557	359	24	1	250000	100000
558	360	99	1	250000	100000
559	360	73	1	280000	100000
560	361	92	1	250000	100000
561	361	47	1	190000	100000
562	362	73	4	280000	400000
563	363	75	1	350000	100000
564	363	73	1	280000	100000
565	364	71	2	280000	200000
566	364	82	1	350000	100000
567	365	73	1	280000	100000
568	366	74	1	280000	100000
569	367	90	1	400000	150000
570	368	73	1	280000	100000
571	369	80	1	350000	100000
572	369	84	1	350000	100000
573	370	23	1	250000	100000
574	370	24	1	250000	100000
575	371	73	1	280000	100000
576	372	73	1	280000	100000
577	372	74	1	280000	100000
578	373	93	1	250000	100000
579	374	84	1	350000	100000
580	374	82	1	350000	100000
581	375	73	1	280000	100000
582	376	79	1	350000	100000
583	377	96	1	250000	100000
585	379	73	1	280000	100000
586	379	74	1	280000	100000
587	380	73	1	280000	100000
588	381	73	1	280000	100000
589	381	95	1	250000	100000
590	382	73	1	280000	100000
591	383	87	1	300000	120000
592	383	78	1	350000	100000
593	384	73	1	280000	100000
594	385	90	1	400000	150000
595	385	92	1	250000	100000
596	385	73	1	280000	100000
597	386	99	1	250000	100000
598	386	24	1	250000	100000
599	387	75	1	350000	100000
600	387	73	1	280000	100000
601	388	82	1	350000	100000
602	388	74	1	280000	100000
603	389	95	1	250000	100000
604	389	23	1	250000	100000
605	390	82	1	350000	100000
606	391	101	1	280000	100000
607	391	73	1	280000	100000
608	392	101	1	280000	100000
609	393	101	1	280000	100000
610	394	101	1	280000	100000
611	395	101	1	280000	100000
612	396	73	1	280000	100000
613	396	24	1	250000	100000
614	397	82	1	350000	100000
615	397	96	1	250000	100000
616	398	78	1	350000	100000
617	399	93	1	250000	100000
618	399	73	1	280000	100000
619	400	101	1	280000	100000
620	400	82	1	350000	100000
621	400	24	1	250000	100000
622	401	27	1	270000	100000
623	402	101	1	280000	100000
624	403	100	1	280000	115000
625	404	100	1	280000	115000
626	405	100	1	280000	115000
627	406	74	1	280000	100000
628	406	23	1	250000	100000
629	407	97	1	250000	100000
630	407	75	1	350000	100000
631	408	75	1	350000	100000
632	409	101	1	280000	100000
633	410	49	1	190000	100000
634	411	24	1	250000	100000
635	412	101	1	280000	100000
636	413	101	1	280000	100000
637	414	101	1	280000	100000
638	415	101	1	280000	100000
639	416	74	1	280000	100000
640	417	101	1	280000	100000
641	418	75	1	350000	100000
642	419	95	1	250000	100000
643	419	85	1	350000	100000
644	419	76	1	350000	100000
645	419	50	1	190000	100000
646	419	74	1	280000	100000
647	420	74	1	280000	100000
648	421	100	1	280000	115000
649	421	102	1	320000	120000
650	422	95	1	250000	100000
651	422	50	1	190000	100000
652	423	82	1	350000	100000
653	424	102	1	320000	120000
654	425	84	1	350000	100000
655	426	102	1	320000	120000
656	427	102	1	320000	120000
657	428	102	1	320000	120000
658	429	74	1	280000	100000
659	430	50	1	190000	100000
660	430	95	1	250000	100000
661	431	102	1	320000	120000
662	431	71	1	280000	100000
663	432	102	2	320000	240000
664	433	102	1	320000	120000
665	433	46	1	250000	60000
666	434	75	1	350000	100000
667	434	23	1	250000	100000
668	434	82	1	350000	100000
669	435	79	1	350000	100000
670	436	101	1	280000	100000
671	437	90	1	400000	150000
672	437	71	1	280000	100000
673	438	86	1	350000	100000
674	438	85	1	350000	100000
675	438	82	1	350000	100000
676	438	74	1	280000	100000
677	438	71	1	280000	100000
678	439	92	1	250000	100000
679	439	74	1	280000	100000
680	440	69	1	280000	100000
681	440	102	2	320000	240000
682	440	101	1	280000	100000
683	440	84	1	350000	100000
684	440	82	1	350000	100000
685	441	101	1	280000	100000
686	442	24	1	250000	100000
687	443	24	1	250000	100000
688	444	24	1	250000	100000
689	445	23	1	250000	100000
690	445	24	1	250000	100000
691	446	101	1	280000	100000
692	447	102	1	320000	120000
693	448	27	5	270000	500000
694	449	102	1	320000	120000
695	450	76	1	350000	100000
696	450	47	1	190000	100000
697	450	49	1	190000	100000
698	451	75	1	350000	100000
699	451	23	1	250000	100000
700	452	23	1	250000	100000
701	453	74	1	280000	100000
702	454	88	1	400000	150000
703	454	77	1	350000	100000
704	455	45	2	140000	120000
705	455	78	1	350000	100000
706	455	74	1	280000	100000
707	456	88	1	400000	150000
708	456	24	1	250000	100000
709	456	81	1	350000	100000
710	457	88	1	400000	150000
711	457	24	1	250000	100000
712	457	81	1	350000	100000
713	458	101	1	280000	100000
714	459	101	1	280000	100000
715	460	101	1	280000	100000
716	461	84	1	350000	100000
717	461	23	1	250000	100000
718	462	74	1	280000	100000
719	463	69	1	280000	100000
720	463	84	1	350000	100000
721	464	82	1	350000	100000
722	465	91	1	400000	150000
723	465	78	1	350000	100000
724	466	23	1	250000	100000
725	467	81	1	350000	100000
726	467	23	2	300000	200000
727	468	78	1	350000	100000
728	468	74	1	350000	100000
729	468	45	2	140000	120000
730	469	47	1	250000	100000
731	470	87	2	300000	240000
732	471	81	1	350000	100000
733	471	50	1	250000	100000
734	472	95	1	300000	100000
735	473	102	1	320000	120000
736	474	81	1	350000	100000
737	474	24	1	300000	100000
738	475	102	1	320000	120000
739	476	101	1	300000	100000
740	477	78	1	350000	100000
741	478	101	1	300000	100000
742	479	92	1	300000	100000
743	479	90	1	400000	150000
744	480	101	1	300000	100000
745	481	102	1	320000	120000
746	482	81	1	350000	100000
747	482	24	1	300000	100000
748	483	24	1	300000	100000
749	483	81	1	350000	100000
750	484	95	1	300000	100000
751	485	101	1	300000	100000
752	485	23	1	300000	100000
753	486	101	1	300000	100000
754	487	71	1	300000	100000
755	488	71	1	300000	100000
756	489	78	1	350000	100000
757	490	85	1	350000	100000
758	491	75	1	350000	110000
759	491	73	1	350000	110000
760	492	75	1	350000	110000
761	492	73	1	350000	110000
762	493	73	1	350000	110000
763	494	73	1	350000	110000
764	495	73	2	350000	220000
765	495	97	1	300000	100000
766	496	97	1	300000	100000
767	496	73	1	350000	110000
768	497	75	1	350000	110000
769	497	73	1	350000	110000
770	498	75	1	350000	110000
771	498	95	1	300000	100000
772	499	73	1	350000	110000
773	500	73	1	350000	110000
774	501	102	1	320000	120000
775	502	24	1	300000	100000
776	503	79	1	350000	100000
777	503	73	1	350000	110000
778	504	73	1	350000	110000
779	505	88	1	400000	150000
780	505	78	1	350000	100000
781	506	23	1	300000	100000
782	507	23	1	300000	100000
783	508	78	1	350000	100000
784	508	73	1	350000	110000
785	508	101	1	300000	100000
786	509	78	1	350000	100000
787	509	88	1	400000	150000
788	510	23	1	300000	100000
789	511	101	1	300000	100000
790	512	73	1	350000	110000
791	513	73	1	350000	110000
792	514	101	1	300000	100000
793	515	24	1	300000	100000
794	516	83	1	350000	120000
795	517	90	1	400000	150000
796	518	75	1	350000	110000
797	519	83	1	350000	120000
798	520	73	1	350000	110000
799	520	97	1	300000	100000
800	521	97	1	300000	100000
801	521	73	1	350000	110000
802	522	101	1	300000	100000
803	523	73	1	350000	110000
804	524	90	1	400000	150000
805	524	88	1	400000	150000
806	524	81	1	350000	100000
807	524	83	1	350000	120000
808	525	83	1	350000	120000
809	526	92	1	300000	100000
810	526	73	1	350000	110000
811	527	100	1	300000	120000
812	527	102	1	320000	140000
813	528	100	1	300000	120000
814	528	83	1	350000	120000
815	529	100	2	300000	240000
816	530	78	1	350000	120000
817	531	102	1	320000	140000
818	532	83	1	350000	120000
819	532	90	1	400000	150000
820	533	97	1	300000	100000
821	533	73	1	350000	110000
822	534	98	1	300000	100000
823	534	88	1	400000	150000
824	534	83	1	350000	120000
825	534	73	1	350000	110000
826	534	78	1	350000	120000
827	535	85	1	350000	100000
828	536	101	1	300000	100000
829	537	75	1	350000	110000
830	538	80	1	350000	100000
831	539	80	1	350000	100000
832	540	80	2	350000	200000
833	541	101	1	300000	100000
834	542	76	1	350000	120000
835	543	76	1	350000	120000
836	544	78	1	350000	120000
837	545	78	1	350000	120000
838	546	96	1	300000	120000
839	546	73	1	350000	110000
840	547	101	1	300000	100000
841	548	85	1	350000	100000
842	549	75	1	350000	110000
843	549	73	1	350000	110000
844	549	50	1	250000	100000
845	549	71	1	300000	100000
846	549	47	1	250000	100000
847	550	89	1	400000	150000
848	550	95	1	300000	100000
849	551	73	1	350000	110000
850	551	96	1	300000	120000
851	552	23	1	300000	100000
852	552	83	1	350000	120000
853	553	76	1	350000	120000
854	553	24	1	300000	100000
855	553	102	1	320000	140000
856	554	101	1	300000	100000
857	555	78	1	350000	120000
858	555	75	1	350000	110000
859	555	73	1	350000	110000
860	555	74	1	350000	100000
861	556	97	1	300000	100000
862	556	73	1	350000	110000
863	557	73	1	350000	110000
864	558	81	1	350000	100000
865	558	88	1	400000	150000
866	559	78	1	350000	120000
867	559	75	1	350000	110000
868	559	47	1	250000	100000
869	559	49	1	250000	100000
870	559	90	1	400000	150000
871	559	88	1	400000	150000
872	559	92	1	300000	100000
873	559	94	1	300000	120000
874	559	96	1	300000	120000
875	559	98	1	300000	100000
876	559	73	1	350000	110000
877	559	74	1	350000	100000
878	560	90	1	400000	150000
879	561	73	1	350000	110000
880	561	75	1	350000	110000
881	562	75	1	350000	110000
882	562	73	1	350000	110000
883	563	74	1	350000	100000
884	563	95	1	300000	100000
885	564	76	1	350000	120000
886	564	75	1	350000	110000
887	564	78	1	350000	120000
888	564	71	1	300000	100000
889	565	74	1	350000	100000
890	566	23	1	300000	100000
891	567	94	1	300000	120000
892	567	98	1	300000	100000
893	567	92	1	300000	100000
894	567	81	1	350000	100000
895	567	24	1	300000	100000
896	567	73	1	350000	110000
897	567	88	1	400000	150000
898	568	88	1	400000	150000
899	568	83	1	350000	120000
900	569	93	1	300000	100000
901	569	73	1	350000	110000
902	570	70	1	300000	100000
903	571	71	1	300000	100000
904	571	84	1	350000	100000
905	571	102	1	320000	140000
906	572	23	1	300000	100000
907	572	75	1	350000	110000
908	573	96	1	300000	120000
909	573	23	1	300000	100000
910	574	81	1	350000	100000
911	574	74	1	350000	100000
912	575	78	1	350000	120000
913	576	87	1	300000	120000
914	576	95	1	300000	100000
915	576	79	1	350000	100000
916	576	73	1	350000	120000
917	576	78	1	350000	120000
918	577	81	1	350000	100000
919	577	83	1	350000	120000
920	577	80	1	350000	100000
921	578	81	1	350000	100000
922	578	83	1	350000	120000
923	578	80	1	350000	100000
924	578	50	1	250000	100000
925	578	72	1	300000	120000
926	578	73	1	350000	120000
927	578	74	1	350000	100000
928	579	101	1	300000	100000
929	580	102	1	320000	140000
930	581	90	1	400000	150000
931	581	83	1	350000	120000
932	582	97	1	300000	100000
933	582	73	1	350000	120000
934	583	100	1	300000	120000
935	584	73	1	350000	120000
936	584	78	1	350000	120000
937	585	88	1	400000	150000
938	586	88	1	400000	150000
939	587	24	1	300000	100000
940	587	81	1	350000	100000
941	587	88	1	400000	150000
942	587	83	1	350000	120000
943	588	75	1	350000	110000
944	588	73	1	350000	120000
945	589	73	1	350000	120000
946	590	80	1	350000	100000
947	590	83	1	350000	120000
948	590	90	1	400000	150000
949	591	75	1	350000	110000
950	592	78	1	350000	120000
951	593	92	1	300000	100000
952	593	73	1	350000	120000
953	594	101	1	300000	100000
954	594	100	1	300000	120000
955	595	71	1	300000	100000
956	595	49	1	250000	100000
957	596	101	1	300000	100000
958	597	50	1	250000	100000
959	597	72	1	300000	120000
960	598	90	1	400000	150000
961	598	83	1	350000	120000
962	599	101	1	300000	100000
963	600	88	1	400000	150000
964	600	90	1	400000	150000
965	601	101	1	300000	100000
966	602	81	1	350000	100000
967	603	73	1	350000	120000
968	603	75	1	350000	110000
969	604	83	1	350000	120000
970	604	90	1	400000	150000
971	605	102	1	320000	140000
972	606	93	1	300000	100000
973	606	73	1	350000	120000
974	607	24	1	300000	100000
975	608	23	1	300000	100000
976	609	81	1	350000	100000
977	609	98	1	300000	100000
978	610	75	1	350000	110000
979	610	74	1	350000	100000
980	611	94	1	300000	120000
981	611	98	1	300000	100000
982	611	71	1	300000	100000
983	611	73	1	350000	120000
984	612	79	1	350000	100000
985	612	102	1	320000	140000
986	613	101	1	300000	100000
987	614	102	1	320000	140000
988	614	101	1	300000	100000
989	614	100	1	300000	120000
990	614	76	1	350000	120000
991	614	70	1	300000	100000
992	614	72	1	300000	120000
993	615	78	1	350000	120000
994	616	74	1	350000	100000
995	616	99	1	300000	100000
996	617	102	1	320000	140000
997	618	78	1	350000	120000
998	619	73	1	350000	120000
999	620	102	1	320000	140000
1000	621	101	1	300000	100000
1001	622	81	1	350000	100000
1002	623	81	1	350000	100000
1003	623	74	1	350000	100000
1004	624	73	1	350000	120000
1005	625	50	1	250000	100000
1006	625	79	1	350000	120000
1007	626	102	1	320000	140000
1008	626	89	1	400000	150000
1009	626	77	1	350000	120000
1010	626	73	1	350000	120000
1011	627	78	1	350000	120000
1012	627	88	1	400000	150000
1013	627	50	1	250000	100000
1014	628	102	1	320000	140000
1015	629	75	1	350000	110000
1016	629	78	1	350000	120000
1017	629	73	1	350000	120000
1018	629	90	1	400000	150000
1019	630	96	1	300000	120000
1020	630	73	1	350000	120000
1021	631	102	1	320000	140000
1022	632	74	1	350000	120000
1023	633	78	3	350000	360000
1024	633	76	1	350000	120000
1025	633	75	1	350000	110000
1026	634	100	1	300000	120000
1027	635	98	1	300000	100000
1028	635	79	1	350000	120000
1029	636	81	1	350000	100000
1030	636	49	1	250000	100000
1031	637	73	1	350000	120000
1032	637	75	1	350000	110000
1033	638	88	1	400000	150000
1034	638	77	1	350000	120000
1035	639	91	1	400000	150000
1036	639	79	1	350000	100000
1037	639	73	1	350000	120000
1038	640	79	1	350000	120000
1039	641	89	1	400000	150000
1040	642	23	1	300000	100000
1041	642	75	1	350000	110000
1042	643	81	1	350000	120000
1043	643	71	1	300000	100000
1044	644	102	1	320000	140000
1045	644	73	1	350000	120000
1046	644	49	1	250000	100000
1047	644	75	1	350000	110000
1048	645	96	1	300000	120000
1049	645	95	1	300000	120000
1050	646	49	1	250000	100000
1051	647	102	1	320000	140000
1052	648	49	1	250000	100000
1053	649	102	1	320000	140000
1054	650	73	1	350000	120000
1055	651	97	1	300000	100000
1056	652	79	1	350000	120000
1057	653	81	1	350000	120000
1058	654	73	1	350000	120000
1059	654	96	1	300000	120000
1060	655	24	1	300000	100000
1061	656	72	1	300000	120000
1062	657	91	1	400000	150000
1063	657	73	1	350000	120000
1064	658	76	1	350000	120000
1065	658	81	1	350000	120000
1066	658	74	1	350000	120000
1067	659	75	1	350000	110000
1068	660	23	1	300000	100000
1069	661	89	1	400000	150000
1070	662	73	1	350000	120000
1071	663	102	1	320000	140000
1072	664	102	1	320000	140000
1073	665	96	1	300000	120000
1074	665	86	1	350000	100000
1075	665	79	1	350000	120000
1076	665	69	1	300000	100000
1077	665	50	1	250000	100000
1078	666	69	1	300000	100000
1079	667	78	1	350000	120000
1080	668	89	1	400000	150000
1081	669	73	1	350000	120000
1082	670	85	1	350000	100000
1083	671	76	1	350000	120000
1084	671	83	1	350000	120000
1085	672	102	1	320000	140000
1086	673	75	1	350000	120000
1087	674	101	1	300000	120000
1088	675	76	1	350000	120000
1089	675	75	1	350000	120000
1090	676	96	1	300000	120000
1091	676	73	1	350000	120000
1092	677	83	1	350000	120000
1093	678	97	1	300000	120000
1094	678	73	1	350000	120000
1095	679	73	1	350000	120000
1096	680	101	1	300000	120000
1097	681	78	1	350000	120000
1098	681	90	1	400000	150000
1099	682	79	1	350000	120000
1100	683	76	1	350000	120000
1101	684	73	1	350000	120000
1102	685	86	1	350000	100000
1103	686	76	1	350000	120000
1104	686	88	1	400000	150000
1105	686	91	1	400000	150000
1106	686	98	1	300000	100000
1107	686	75	1	350000	120000
1108	687	82	1	350000	100000
1109	687	24	1	300000	100000
1110	687	102	1	320000	140000
1111	688	90	1	400000	150000
1112	689	101	1	300000	120000
1113	690	93	1	300000	100000
1114	690	50	1	250000	100000
1115	690	81	1	350000	120000
1116	691	101	1	300000	100000
1117	691	23	1	300000	100000
1118	692	101	1	300000	120000
1119	692	23	1	300000	100000
1120	693	97	1	300000	120000
1121	693	73	1	350000	120000
1122	694	82	1	350000	100000
1123	695	96	1	300000	120000
1124	696	74	1	350000	120000
1125	697	95	1	300000	120000
1126	697	73	1	350000	120000
1127	698	83	1	350000	120000
1128	699	96	1	300000	120000
1129	699	73	1	350000	120000
1130	700	23	1	300000	100000
1131	700	24	1	300000	100000
1132	700	50	1	250000	100000
1133	700	48	1	250000	120000
1134	700	89	1	400000	150000
1135	701	83	1	350000	120000
1136	701	88	1	400000	150000
1137	701	23	1	300000	100000
1138	702	75	1	350000	120000
1139	702	73	1	350000	120000
1140	703	100	1	300000	120000
1141	704	72	1	300000	120000
1142	704	82	1	350000	100000
1143	705	83	1	350000	120000
1144	706	102	1	320000	140000
1145	707	70	1	300000	120000
1146	707	72	1	300000	120000
1147	707	81	1	350000	120000
1148	707	83	1	350000	120000
1149	708	86	1	350000	100000
1150	709	96	1	300000	120000
1151	710	75	1	350000	120000
1152	711	131	1	100000	0
1153	712	131	1	100000	0
1154	713	101	1	300000	120000
1155	714	131	1	100000	0
1156	715	72	1	300000	120000
1157	716	82	1	350000	100000
1158	716	80	1	350000	100000
1159	716	84	1	350000	100000
1160	716	86	1	350000	100000
1161	716	76	1	350000	120000
1162	716	75	1	350000	120000
1163	716	77	1	350000	120000
1164	716	48	1	250000	120000
1165	716	50	1	250000	100000
1166	716	52	1	250000	100000
1167	716	72	1	300000	120000
1168	716	91	1	400000	150000
1169	716	89	1	400000	150000
1170	716	24	1	300000	100000
1171	716	23	1	300000	100000
1172	717	88	1	400000	150000
1173	718	49	1	250000	100000
1174	718	81	1	350000	120000
1175	718	24	1	300000	100000
1176	719	83	1	350000	120000
1177	719	73	1	350000	120000
1178	720	73	1	350000	120000
1179	721	96	1	300000	120000
1180	721	73	1	350000	120000
1181	722	72	1	300000	120000
1182	722	89	1	400000	150000
1183	722	24	1	300000	100000
1184	722	81	1	350000	120000
1185	722	75	1	350000	120000
1186	722	73	1	350000	120000
1187	722	74	1	350000	120000
1188	722	96	1	300000	120000
1189	722	76	1	350000	120000
1190	722	85	1	350000	100000
1191	723	73	1	350000	120000
1192	724	86	1	350000	100000
1193	725	101	1	300000	120000
1194	726	102	1	320000	140000
1195	727	70	1	300000	120000
1196	727	88	1	400000	150000
1197	728	73	1	350000	120000
1198	729	101	1	300000	120000
1199	730	101	1	300000	120000
1200	731	72	1	300000	120000
1201	731	101	1	300000	120000
1202	731	97	1	300000	120000
1203	731	73	1	350000	120000
1204	732	88	1	400000	150000
1205	733	79	1	350000	100000
1206	734	73	1	350000	120000
1207	734	96	1	300000	120000
1208	734	75	1	350000	120000
1209	735	73	1	350000	120000
1210	736	83	1	350000	120000
1211	736	23	1	300000	100000
1212	737	75	1	350000	120000
1213	737	90	1	400000	150000
1214	737	73	1	350000	120000
1215	737	79	1	350000	120000
1216	738	101	1	300000	120000
1217	739	102	1	320000	140000
1218	740	101	1	300000	120000
1219	740	95	1	300000	120000
1220	741	91	1	400000	150000
1221	741	89	1	400000	150000
1222	741	76	1	350000	120000
1223	741	77	1	350000	120000
1224	741	75	1	350000	120000
1225	741	78	1	350000	120000
1226	742	97	1	300000	120000
1227	743	73	1	350000	120000
1228	744	77	1	350000	120000
1229	744	74	1	350000	120000
1230	745	101	1	300000	120000
1231	746	86	1	350000	100000
1232	747	102	1	320000	140000
1233	748	73	1	350000	120000
1234	749	102	1	320000	140000
1235	749	101	1	300000	120000
1236	750	101	1	300000	120000
1237	751	77	1	350000	120000
1238	751	80	1	350000	100000
1239	752	97	1	300000	120000
1240	752	73	1	350000	120000
1241	752	82	1	350000	100000
1242	753	23	1	300000	100000
1243	753	95	1	300000	120000
1244	754	101	1	300000	120000
1245	755	79	1	350000	120000
1246	755	83	1	350000	120000
1247	755	81	1	350000	120000
1248	756	101	1	300000	120000
1249	756	75	1	350000	120000
1250	756	23	1	300000	100000
1251	757	49	1	250000	100000
1252	758	102	2	320000	280000
1253	758	81	1	350000	120000
1254	758	24	1	300000	100000
1255	759	73	1	350000	120000
1256	759	88	1	400000	150000
1257	760	102	1	320000	140000
1258	761	23	1	300000	100000
1259	762	24	1	300000	120000
1260	763	88	1	400000	150000
1261	764	102	1	320000	140000
1262	764	101	1	300000	120000
1263	765	75	1	350000	120000
1264	765	88	1	400000	150000
1265	766	78	1	350000	120000
1266	766	88	1	400000	150000
1267	767	78	1	350000	120000
1268	767	79	1	350000	120000
1269	767	88	1	400000	150000
1270	767	73	1	350000	120000
1271	768	74	1	350000	120000
1272	768	83	1	350000	120000
1273	769	101	1	300000	120000
1274	770	23	1	300000	100000
1275	770	83	1	350000	120000
1276	771	69	1	300000	120000
1277	771	73	1	350000	120000
1278	771	96	1	300000	120000
1279	772	88	1	400000	150000
1280	773	101	1	300000	120000
1281	773	79	1	350000	120000
1282	774	102	1	320000	140000
1283	774	142	1	300000	120000
1284	775	102	1	320000	140000
1285	775	142	1	300000	120000
1286	776	24	1	300000	120000
1287	776	23	1	300000	110000
1288	776	48	1	250000	120000
1289	776	72	1	300000	120000
1290	776	75	1	350000	120000
1291	777	23	1	300000	110000
1292	777	84	1	350000	100000
1293	778	96	1	300000	120000
1294	779	88	1	400000	150000
1295	779	73	1	350000	120000
1296	780	84	1	350000	100000
1297	781	101	1	300000	120000
1298	782	85	1	350000	100000
1299	783	101	1	300000	120000
1300	784	96	1	300000	120000
1301	785	89	1	400000	150000
1302	786	23	1	300000	110000
1303	787	101	1	300000	120000
1304	788	102	1	320000	140000
1305	788	142	1	300000	120000
1306	789	97	1	300000	120000
1307	789	93	1	300000	100000
1308	790	73	1	350000	120000
1309	791	164	1	320000	0
1310	791	24	1	300000	120000
1311	792	101	1	300000	120000
1312	792	143	1	300000	120000
1313	793	142	1	300000	120000
1314	794	101	1	300000	120000
1315	795	88	1	400000	150000
1316	795	69	1	300000	120000
1317	795	83	1	350000	120000
1318	795	73	1	350000	120000
1319	796	79	1	350000	120000
1320	796	96	1	300000	120000
1321	797	102	1	320000	120000
1322	798	96	1	300000	120000
1323	798	73	1	350000	120000
1324	799	160	1	300000	120000
1325	800	160	1	300000	120000
1326	800	73	1	350000	120000
1327	801	81	1	350000	120000
1328	801	74	1	350000	120000
1329	801	143	1	300000	120000
1330	801	160	1	300000	120000
1331	801	158	1	300000	120000
1332	802	161	1	300000	120000
1333	803	81	1	350000	120000
1334	803	24	1	300000	120000
1339	807	101	1	300000	120000
1340	808	102	1	320000	120000
1439	862	73	1	350000	120000
1440	862	95	1	300000	120000
1444	865	165	1	350000	120000
1450	870	96	2	300000	240000
1451	870	73	1	350000	120000
1452	870	23	1	300000	120000
1457	873	158	1	300000	120000
1461	876	102	1	320000	120000
1462	876	142	1	300000	120000
1467	879	102	1	320000	120000
1468	879	101	1	300000	110000
1469	879	76	1	350000	120000
1470	879	143	1	300000	120000
1471	879	142	1	300000	120000
1475	882	164	1	320000	120000
1479	885	88	1	400000	150000
1480	885	73	1	350000	120000
1483	887	101	1	300000	110000
1484	887	23	1	300000	120000
1490	890	102	1	320000	120000
1494	893	97	1	300000	120000
1499	897	100	1	300000	120000
1504	899	23	1	300000	120000
1508	902	76	1	350000	120000
1509	902	75	1	350000	120000
1510	903	101	1	300000	110000
1511	904	100	1	300000	120000
1515	907	164	1	320000	120000
1516	908	102	1	320000	120000
1524	911	79	1	350000	120000
1525	911	48	1	250000	120000
1526	912	80	1	350000	100000
1527	912	78	1	350000	120000
1528	912	102	1	320000	120000
1529	912	100	1	300000	120000
1531	914	142	1	300000	120000
1532	914	48	1	250000	120000
1533	914	160	1	300000	120000
1534	914	164	1	320000	120000
1537	916	79	1	350000	120000
1538	916	102	1	320000	120000
1540	918	89	1	400000	150000
1541	918	73	1	350000	120000
1543	920	99	1	300000	100000
1545	922	164	1	320000	120000
1553	925	101	1	300000	110000
1557	927	101	1	300000	110000
1559	929	83	1	350000	120000
1560	929	96	1	300000	120000
1561	929	161	1	300000	120000
1562	929	73	1	350000	120000
1564	931	74	1	350000	120000
1566	933	70	1	300000	120000
1567	933	160	1	300000	120000
1568	934	86	1	350000	100000
1569	934	24	1	300000	120000
1572	936	101	1	300000	110000
1577	938	94	1	300000	120000
1580	940	79	1	350000	120000
1582	942	102	5	320000	600000
1583	942	101	5	300000	550000
1584	942	142	3	300000	360000
1585	942	143	3	300000	360000
1588	944	165	1	350000	120000
1596	948	101	1	300000	110000
1599	951	101	1	300000	110000
1600	952	98	1	300000	100000
1601	952	142	1	300000	120000
1603	954	165	1	350000	120000
1606	956	100	1	300000	120000
1607	956	23	1	300000	120000
1609	958	101	1	300000	110000
1610	959	101	1	300000	110000
1616	964	96	1	300000	120000
1617	965	101	1	300000	110000
1618	965	100	1	300000	120000
1619	965	102	1	320000	120000
1620	966	101	2	300000	220000
1621	967	102	1	320000	120000
1630	969	165	1	350000	120000
1631	969	101	1	300000	110000
1633	971	73	1	350000	120000
1634	971	143	1	300000	120000
1635	971	85	1	350000	100000
1636	972	101	1	300000	110000
1638	974	102	14	320000	1680000
1639	974	101	8	300000	880000
1640	974	100	5	300000	600000
1641	974	143	6	300000	720000
1642	974	23	3	300000	360000
1643	974	142	1	300000	120000
1644	974	24	6	300000	720000
1645	974	78	3	350000	360000
1646	974	75	2	350000	240000
1647	974	77	3	350000	360000
1648	974	79	2	350000	240000
1649	974	80	1	350000	100000
1650	974	83	2	350000	240000
1651	974	84	1	350000	100000
1652	974	82	1	350000	100000
1653	974	81	1	350000	120000
1654	974	85	1	350000	100000
1655	974	89	2	400000	300000
1656	974	71	1	300000	120000
1657	974	73	2	350000	240000
1658	974	87	1	300000	120000
1660	976	143	1	300000	120000
1663	978	165	1	350000	120000
1664	978	102	1	320000	120000
1665	978	100	1	300000	120000
1666	978	79	1	350000	120000
1667	978	73	1	350000	120000
1668	978	23	1	300000	120000
1670	980	102	1	320000	120000
1672	982	102	1	320000	120000
1679	987	142	1	300000	120000
1335	804	24	1	300000	120000
1336	804	82	1	350000	100000
1441	863	160	1	300000	120000
1445	866	83	1	350000	120000
1453	871	102	1	320000	120000
1454	871	142	1	300000	120000
1458	874	165	1	350000	120000
1459	874	164	1	320000	120000
1463	877	102	1	320000	120000
1464	877	100	1	300000	120000
1465	877	23	1	300000	120000
1472	880	102	1	320000	120000
1473	880	142	1	300000	120000
1476	883	165	1	350000	120000
1477	883	142	1	300000	120000
1485	888	71	1	300000	120000
1486	888	81	1	350000	120000
1487	888	164	1	320000	120000
1491	891	75	1	350000	120000
1492	891	73	1	350000	120000
1495	894	165	1	350000	120000
1500	898	164	1	320000	120000
1501	898	101	1	300000	110000
1502	898	102	1	320000	120000
1503	898	75	1	350000	120000
1505	900	74	1	350000	120000
1506	901	160	1	300000	120000
1507	901	23	1	300000	120000
1512	905	101	1	300000	110000
1513	906	102	1	320000	120000
1514	906	142	1	300000	120000
1517	909	165	1	350000	120000
1518	909	101	1	300000	110000
1519	909	23	1	300000	120000
1520	910	76	1	350000	120000
1521	910	158	1	300000	120000
1522	910	143	1	300000	120000
1523	910	71	1	300000	120000
1530	913	165	1	350000	120000
1535	915	48	1	250000	120000
1536	915	52	1	250000	100000
1539	917	101	1	300000	110000
1542	919	102	1	320000	120000
1544	921	78	1	350000	120000
1546	923	164	1	320000	120000
1547	923	102	1	320000	120000
1548	923	165	1	350000	120000
1549	923	100	1	300000	120000
1550	923	142	1	300000	120000
1551	924	142	1	300000	120000
1552	924	102	1	320000	120000
1554	926	82	1	350000	100000
1555	926	95	1	300000	120000
1556	926	74	1	350000	120000
1558	928	79	1	350000	120000
1563	930	102	1	320000	120000
1565	932	71	3	300000	360000
1570	935	84	1	350000	100000
1571	935	73	1	350000	120000
1573	937	80	1	350000	100000
1574	937	71	1	300000	120000
1575	937	75	1	350000	120000
1576	937	73	1	350000	120000
1578	939	100	2	300000	240000
1579	939	23	1	300000	120000
1581	941	101	1	300000	110000
1586	943	94	1	300000	120000
1587	943	96	1	300000	120000
1589	945	77	1	350000	120000
1590	945	75	1	350000	120000
1591	945	142	1	300000	120000
1592	945	143	1	300000	120000
1593	945	101	1	300000	110000
1594	946	101	1	300000	110000
1595	947	73	1	350000	120000
1597	949	71	1	300000	120000
1598	950	102	1	320000	120000
1602	953	92	1	300000	100000
1604	955	82	1	350000	100000
1605	955	89	1	400000	150000
1608	957	165	1	350000	120000
1611	960	89	1	400000	150000
1612	961	78	1	350000	120000
1613	961	50	1	250000	100000
1614	963	102	1	320000	120000
1615	963	142	1	300000	120000
1622	968	47	1	250000	100000
1623	968	49	1	250000	100000
1624	968	96	1	300000	120000
1625	968	94	1	300000	120000
1626	968	83	1	350000	120000
1627	968	81	1	350000	120000
1628	968	88	1	400000	150000
1629	968	78	1	350000	120000
1632	970	23	1	300000	120000
1637	973	92	1	300000	100000
1659	975	71	1	300000	120000
1661	977	73	1	350000	120000
1662	977	94	1	300000	120000
1669	979	160	1	300000	120000
1671	981	78	3	350000	360000
1673	983	100	1	300000	120000
1674	984	73	1	350000	120000
1675	985	100	1	300000	120000
1676	985	23	1	300000	120000
1677	986	79	1	350000	120000
1678	986	23	1	300000	120000
1680	987	159	1	300000	120000
1681	988	101	1	300000	110000
1682	988	143	1	300000	120000
1683	989	101	1	300000	110000
1684	990	73	1	350000	120000
1685	991	102	1	320000	120000
1686	991	142	1	300000	120000
1687	992	101	1	300000	110000
1688	993	100	1	300000	120000
1689	994	100	1	300000	120000
1690	995	164	1	320000	120000
1691	995	102	1	320000	120000
1692	996	75	1	350000	120000
1337	805	101	1	300000	120000
1338	806	142	1	300000	120000
1341	809	158	1	300000	120000
1342	809	73	1	350000	120000
1343	810	160	1	300000	120000
1344	810	49	1	250000	100000
1345	810	142	1	300000	120000
1346	811	97	1	300000	120000
1347	811	86	1	350000	100000
1348	811	71	1	300000	120000
1349	812	101	1	300000	120000
1350	813	78	1	350000	120000
1351	813	160	1	300000	120000
1352	814	81	1	350000	120000
1353	814	83	1	350000	120000
1354	814	69	1	300000	120000
1355	814	71	1	300000	120000
1356	814	76	1	350000	120000
1357	815	102	1	320000	120000
1358	816	97	1	300000	120000
1359	816	73	1	350000	120000
1360	817	73	1	350000	120000
1361	818	102	1	320000	120000
1362	818	142	1	300000	120000
1363	819	142	1	300000	120000
1364	820	102	1	320000	120000
1365	821	101	1	300000	120000
1366	822	23	1	300000	120000
1367	823	96	1	300000	120000
1368	823	101	1	300000	120000
1369	823	73	1	350000	120000
1370	824	97	1	300000	120000
1371	825	73	1	350000	120000
1372	825	24	1	300000	120000
1373	826	102	1	320000	120000
1374	827	102	1	320000	120000
1375	828	102	1	320000	120000
1376	828	161	1	300000	120000
1377	828	24	1	300000	120000
1378	829	71	1	300000	120000
1379	829	50	1	250000	100000
1380	829	163	1	300000	120000
1381	829	142	1	300000	120000
1382	830	102	1	320000	120000
1383	830	100	1	300000	120000
1384	830	71	1	300000	120000
1385	830	49	1	250000	100000
1386	830	24	1	300000	120000
1387	830	142	1	300000	120000
1388	830	88	1	400000	150000
1389	830	162	1	300000	120000
1390	830	163	2	300000	240000
1391	830	161	1	300000	120000
1392	831	143	1	300000	120000
1393	832	101	1	300000	110000
1394	833	24	1	300000	120000
1395	833	142	1	300000	120000
1396	833	102	1	320000	120000
1397	833	161	1	300000	120000
1398	833	160	1	300000	120000
1399	834	100	1	300000	120000
1400	835	100	1	300000	120000
1401	836	102	1	320000	120000
1402	837	97	1	300000	120000
1403	837	73	1	350000	120000
1404	838	101	1	300000	110000
1405	839	100	1	300000	120000
1406	840	101	1	300000	110000
1407	840	143	1	300000	120000
1408	841	100	1	300000	120000
1409	841	23	1	300000	120000
1410	842	78	1	350000	120000
1411	843	143	1	300000	120000
1412	843	101	1	300000	110000
1413	844	101	1	300000	110000
1414	844	143	1	300000	120000
1415	845	95	1	300000	120000
1416	845	99	1	300000	100000
1417	846	89	1	400000	150000
1418	846	82	1	350000	100000
1419	847	100	1	300000	120000
1420	848	101	1	300000	110000
1421	848	143	1	300000	120000
1422	849	98	1	300000	100000
1423	849	94	1	300000	120000
1424	849	47	1	250000	100000
1425	850	101	1	300000	110000
1426	851	100	1	300000	120000
1427	852	95	1	300000	120000
1428	853	165	1	350000	0
1429	853	100	1	300000	120000
1430	853	23	1	300000	110000
1431	854	158	1	300000	120000
1432	855	158	1	300000	120000
1433	856	158	1	300000	120000
1434	857	158	1	300000	120000
1435	858	158	1	300000	120000
1436	859	158	1	300000	120000
1437	860	101	1	300000	110000
1438	861	85	1	350000	100000
1442	864	101	1	300000	110000
1443	864	143	1	300000	120000
1446	867	88	1	400000	150000
1447	868	100	1	300000	120000
1448	869	23	1	300000	120000
1449	869	75	1	350000	120000
1455	872	71	1	300000	120000
1456	872	88	1	400000	150000
1460	875	101	1	300000	110000
1466	878	102	1	320000	120000
1474	881	165	1	350000	120000
1478	884	164	1	320000	120000
1481	886	88	1	400000	150000
1482	886	73	1	350000	120000
1488	889	73	1	350000	120000
1489	889	75	1	350000	120000
1493	892	165	1	350000	120000
1496	895	102	1	320000	120000
1497	895	100	1	300000	120000
1498	896	165	1	350000	120000
1693	996	81	1	350000	120000
1694	997	165	1	350000	120000
1695	998	164	1	320000	120000
1696	999	76	1	350000	120000
1697	1000	96	1	300000	120000
1698	1001	24	1	300000	120000
1699	1002	101	1	300000	110000
1700	1002	102	3	320000	360000
1701	1003	69	1	300000	120000
1702	1004	75	1	350000	120000
1703	1005	165	1	350000	120000
1704	1005	72	1	300000	120000
1705	1006	102	1	320000	120000
1706	1007	101	1	300000	110000
1707	1008	98	1	300000	100000
1708	1009	101	1	300000	120000
1709	1010	101	1	300000	110000
1710	1011	102	1	320000	120000
1711	1012	162	1	300000	120000
1712	1012	163	1	300000	120000
1713	1013	73	1	350000	120000
1714	1013	93	1	300000	100000
1715	1014	102	1	320000	120000
1716	1015	101	1	300000	120000
1717	1016	100	1	300000	120000
1718	1017	72	1	300000	120000
1719	1018	83	1	350000	120000
1720	1019	142	1	300000	120000
1721	1020	83	1	350000	120000
1722	1021	100	1	300000	120000
1723	1022	78	1	350000	120000
1724	1023	24	1	300000	120000
1725	1024	23	1	300000	110000
1726	1025	100	1	300000	120000
1727	1025	23	1	300000	120000
1728	1026	100	1	300000	120000
1729	1027	100	1	300000	120000
1730	1028	101	1	300000	120000
1731	1028	143	1	300000	120000
1732	1029	101	1	300000	120000
1733	1030	165	1	350000	120000
1734	1031	101	1	300000	120000
1735	1031	143	1	300000	120000
1736	1032	100	1	300000	120000
1737	1033	100	1	300000	120000
1738	1034	83	1	350000	120000
1739	1035	165	1	350000	120000
1740	1036	75	1	350000	120000
1741	1036	73	1	350000	120000
1742	1037	165	1	350000	120000
1743	1037	162	1	300000	120000
1744	1037	73	1	350000	120000
1745	1038	73	1	350000	120000
1746	1039	79	1	350000	120000
1747	1039	23	1	300000	120000
1748	1040	165	1	350000	120000
1749	1041	101	1	300000	120000
1750	1042	99	1	300000	100000
1751	1042	142	1	300000	120000
1752	1042	71	2	300000	240000
1753	1042	161	1	300000	120000
1754	1043	101	1	300000	120000
1755	1044	101	1	300000	120000
1756	1045	160	1	300000	120000
1757	1045	23	1	300000	120000
1758	1046	143	1	300000	120000
1759	1046	81	1	350000	120000
1760	1046	72	1	300000	120000
1761	1046	101	1	300000	120000
1762	1047	50	1	250000	100000
1763	1047	23	1	300000	110000
1764	1048	83	1	350000	120000
1765	1049	165	1	350000	120000
1766	1049	48	1	250000	120000
1767	1050	164	1	320000	120000
1768	1051	89	1	400000	150000
1769	1051	78	1	350000	120000
1770	1052	100	1	300000	120000
1771	1052	23	1	300000	120000
1772	1053	101	1	300000	120000
1773	1054	101	1	300000	120000
1774	1055	164	1	320000	120000
1775	1056	100	1	300000	120000
1776	1057	100	1	300000	120000
1777	1058	165	1	350000	120000
1778	1058	73	1	350000	120000
1779	1059	100	1	300000	120000
1780	1059	23	1	300000	120000
1781	1060	162	1	300000	120000
1782	1061	162	1	300000	120000
1783	1062	102	1	320000	120000
1784	1063	101	1	300000	120000
1785	1064	164	1	320000	120000
1786	1065	164	1	320000	120000
1787	1066	100	1	300000	120000
1788	1067	101	1	300000	120000
1789	1068	164	1	320000	120000
1790	1069	165	1	350000	120000
1791	1070	100	1	300000	120000
1792	1071	100	1	300000	120000
1793	1071	85	1	350000	100000
1794	1071	75	2	350000	240000
1795	1071	76	1	350000	120000
1796	1071	87	1	300000	120000
1797	1071	143	1	300000	120000
1798	1071	97	1	300000	120000
1799	1072	100	1	300000	120000
1800	1072	23	1	300000	120000
1801	1073	100	1	300000	120000
1802	1073	23	1	300000	120000
1803	1074	100	1	300000	120000
1804	1075	102	1	320000	120000
1805	1075	142	1	300000	120000
1806	1076	101	1	300000	120000
1807	1077	101	1	300000	120000
1808	1078	165	1	350000	120000
1809	1079	101	1	300000	120000
1810	1079	143	1	300000	120000
1811	1080	164	1	320000	120000
1812	1081	101	1	300000	120000
1813	1082	78	1	350000	120000
1814	1082	73	1	350000	120000
1815	1083	100	1	300000	120000
1817	1085	100	1	300000	120000
1816	1084	79	1	350000	120000
1818	1086	24	1	300000	120000
1819	1086	81	1	350000	120000
1820	1087	85	1	350000	100000
1821	1088	101	1	300000	120000
1822	1088	143	1	300000	120000
1823	1089	101	1	300000	120000
1824	1090	101	1	300000	120000
1825	1090	143	1	300000	120000
1826	1091	101	1	300000	120000
1827	1091	143	1	300000	120000
1828	1092	101	1	300000	120000
1829	1092	100	1	300000	120000
1830	1093	85	1	350000	100000
1831	1093	72	1	300000	120000
1832	1094	169	1	100000	1
1833	1094	164	1	320000	120000
1834	1095	73	1	350000	120000
1835	1095	79	1	350000	120000
1836	1096	73	1	350000	120000
1837	1096	169	1	15000	1
1838	1097	73	1	350000	120000
1839	1098	73	1	350000	120000
1840	1099	164	1	320000	120000
1841	1100	100	1	300000	120000
1842	1101	100	1	300000	120000
1843	1101	101	1	300000	120000
1844	1101	23	1	300000	120000
1845	1101	143	1	300000	120000
1846	1101	79	1	350000	120000
1847	1101	97	1	300000	120000
1848	1102	71	1	300000	120000
1849	1103	73	1	350000	120000
1850	1104	100	1	300000	120000
1851	1105	83	1	350000	120000
1852	1105	69	1	300000	120000
1853	1106	49	1	250000	100000
1854	1107	100	1	300000	120000
1855	1108	47	1	250000	120000
1856	1108	92	1	300000	120000
1857	1109	47	1	250000	120000
1858	1109	81	1	350000	120000
1859	1110	100	1	300000	120000
1860	1110	159	1	300000	120000
1861	1111	84	1	350000	100000
1862	1111	23	1	300000	120000
1863	1112	160	1	300000	120000
1864	1113	101	1	300000	120000
1865	1114	73	1	350000	120000
1866	1115	100	1	300000	120000
1867	1116	101	1	300000	120000
1868	1117	101	1	300000	120000
1869	1117	81	1	350000	120000
1870	1117	72	1	300000	120000
1871	1117	169	1	20000	1
1872	1118	101	1	300000	120000
1873	1119	79	1	350000	120000
1874	1119	83	1	350000	120000
1875	1119	75	1	350000	120000
1876	1119	73	1	350000	120000
1877	1119	74	1	350000	120000
1878	1119	72	1	300000	120000
1879	1119	48	1	250000	120000
1880	1120	100	1	300000	120000
1881	1120	23	1	300000	120000
1882	1121	73	1	350000	120000
1883	1122	23	1	300000	120000
1884	1123	100	1	300000	120000
1885	1124	100	1	300000	120000
1886	1125	100	1	300000	120000
1887	1126	100	1	300000	120000
1888	1126	23	1	300000	120000
1889	1127	164	1	320000	120000
1890	1127	165	1	350000	120000
1891	1127	101	1	300000	120000
1892	1127	76	1	350000	120000
1893	1127	82	1	350000	100000
1894	1127	24	1	300000	120000
1895	1127	142	1	300000	120000
1896	1127	143	1	300000	120000
1897	1127	50	1	250000	100000
1898	1127	52	1	250000	100000
1899	1128	100	1	300000	120000
1900	1129	161	1	300000	120000
1901	1129	83	1	350000	120000
1902	1129	142	1	300000	120000
1903	1129	98	1	300000	100000
1904	1129	169	1	25000	1
1905	1130	101	1	300000	120000
1906	1131	75	1	350000	120000
1907	1131	73	1	350000	120000
1908	1131	100	1	300000	120000
1909	1132	101	1	300000	120000
1910	1133	164	1	320000	120000
1911	1134	101	1	300000	120000
1912	1134	77	1	350000	120000
1913	1135	76	1	350000	120000
1914	1135	88	1	400000	150000
1915	1135	94	1	300000	120000
1916	1135	49	1	250000	100000
1917	1135	24	1	300000	120000
1918	1135	23	1	300000	120000
1919	1136	165	1	350000	120000
1920	1137	165	1	350000	120000
1921	1138	76	1	350000	120000
1922	1139	76	1	350000	120000
1923	1140	24	1	300000	120000
1924	1140	73	1	350000	120000
1925	1141	165	1	350000	120000
1926	1141	47	1	250000	120000
1927	1141	79	1	350000	120000
1928	1142	96	1	300000	120000
1929	1143	164	1	320000	120000
1930	1143	169	1	1000	1
1931	1144	100	1	300000	120000
1932	1145	164	1	320000	120000
1933	1146	165	1	350000	120000
1934	1147	24	1	300000	120000
1935	1147	73	1	350000	120000
1936	1148	165	1	350000	120000
1937	1149	73	1	350000	120000
1938	1149	160	1	300000	120000
1939	1150	165	1	350000	120000
1940	1151	165	1	350000	120000
1941	1151	164	1	320000	120000
1942	1152	101	1	300000	120000
1943	1153	164	1	320000	120000
1944	1154	100	1	300000	120000
1945	1154	23	1	300000	120000
1946	1155	79	1	350000	120000
1947	1156	73	1	350000	120000
1948	1157	101	1	300000	120000
1949	1158	100	1	300000	120000
1950	1159	24	1	300000	120000
1951	1159	23	1	300000	120000
1952	1159	169	1	50000	1
1953	1160	164	1	320000	120000
1954	1160	169	1	30000	1
1955	1161	160	1	300000	120000
1956	1161	23	1	300000	120000
1957	1162	24	1	300000	120000
1958	1164	165	1	350000	120000
1959	1164	164	1	320000	120000
1960	1164	169	1	15000	1
1961	1165	78	1	350000	120000
1962	1166	164	1	320000	120000
1963	1166	100	1	300000	120000
1964	1167	71	1	300000	120000
1965	1167	69	1	300000	120000
1966	1167	23	1	300000	120000
1967	1167	100	1	300000	120000
1968	1167	165	1	350000	120000
1969	1167	162	1	300000	120000
1970	1167	79	1	350000	120000
1971	1168	102	1	320000	120000
1972	1169	74	1	350000	120000
1973	1169	76	1	350000	120000
1974	1170	93	1	300000	120000
1975	1171	164	1	320000	120000
1976	1172	70	1	300000	120000
1977	1172	23	1	300000	120000
1978	1173	97	1	300000	120000
1979	1174	83	1	350000	120000
1980	1174	49	1	250000	100000
1981	1174	71	1	300000	120000
1982	1174	101	1	300000	120000
1983	1175	164	1	320000	120000
1984	1176	93	1	300000	120000
1985	1177	164	1	320000	120000
1986	1178	75	1	350000	120000
1987	1178	79	1	350000	120000
1988	1178	74	1	350000	120000
1989	1179	102	1	320000	120000
1990	1180	102	1	320000	120000
1991	1181	101	1	300000	120000
1992	1182	102	1	320000	120000
1993	1183	102	1	320000	120000
1994	1184	102	1	320000	120000
1995	1184	142	1	300000	120000
1996	1184	77	1	350000	120000
1997	1185	102	1	320000	120000
1998	1185	142	1	300000	120000
1999	1185	77	1	350000	120000
2000	1186	102	1	320000	120000
2001	1187	102	1	320000	120000
2002	1188	102	1	320000	120000
2003	1189	101	1	300000	120000
2004	1189	165	1	350000	120000
2005	1190	100	1	300000	120000
2006	1190	23	1	300000	120000
2007	1190	169	1	15000	1
2008	1191	164	1	320000	120000
2009	1191	165	1	350000	120000
2010	1191	102	1	320000	120000
2011	1191	101	1	300000	120000
2012	1191	100	1	300000	120000
2013	1192	101	1	300000	120000
2014	1193	101	1	300000	120000
2015	1194	102	1	320000	120000
2016	1195	74	1	350000	120000
2017	1196	70	1	300000	120000
2018	1196	23	1	300000	120000
2019	1196	100	1	300000	120000
2020	1197	79	1	350000	120000
2021	1198	165	1	350000	120000
2022	1199	163	1	300000	120000
2023	1199	76	1	350000	120000
2024	1199	81	1	350000	120000
2025	1199	102	1	320000	120000
2026	1199	169	1	15000	1
2027	1200	142	1	300000	120000
2028	1200	102	1	320000	120000
2029	1201	165	1	350000	120000
2030	1202	101	1	300000	120000
2031	1203	102	2	320000	240000
2032	1203	142	1	300000	120000
2033	1203	169	1	25000	1
2034	1204	76	1	350000	120000
2035	1204	74	1	350000	120000
2036	1205	165	1	350000	120000
2037	1206	165	1	350000	120000
2038	1207	102	1	320000	120000
2039	1208	165	1	350000	120000
2040	1209	102	1	320000	120000
2041	1210	101	1	300000	120000
2042	1211	83	1	350000	120000
2043	1212	165	1	350000	120000
2044	1212	102	1	320000	120000
2045	1212	81	1	350000	120000
2046	1212	83	1	350000	120000
2047	1212	48	1	250000	120000
2048	1212	49	1	250000	100000
2049	1212	70	1	300000	120000
2050	1213	165	1	350000	120000
2051	1214	102	1	320000	120000
2052	1214	142	1	300000	120000
2053	1214	85	1	350000	120000
2054	1215	23	1	300000	120000
2055	1216	164	1	320000	120000
2056	1217	100	1	300000	120000
2057	1217	23	1	300000	120000
2058	1217	77	1	350000	120000
2059	1218	164	1	320000	120000
2060	1219	100	1	300000	120000
2061	1219	73	1	350000	120000
2062	1219	160	1	300000	120000
2063	1219	23	1	300000	120000
2064	1220	101	1	300000	120000
2065	1221	100	1	300000	120000
2066	1221	23	1	300000	120000
2067	1222	92	1	300000	120000
2068	1222	73	1	350000	120000
2069	1222	169	1	30000	1
2070	1223	100	1	300000	120000
2071	1224	165	1	350000	120000
2072	1225	101	1	300000	120000
2073	1226	100	1	300000	120000
2074	1227	160	1	300000	120000
2075	1227	162	1	300000	120000
2076	1227	99	1	300000	100000
2077	1227	169	1	25000	1
2078	1228	100	1	300000	120000
2079	1229	102	1	320000	120000
2080	1230	101	1	300000	120000
2081	1231	71	1	300000	120000
2082	1231	69	1	300000	120000
2083	1231	81	1	350000	120000
2084	1231	169	1	28000	1
2085	1232	74	1	350000	120000
2086	1233	102	1	320000	120000
2087	1234	49	1	250000	100000
2088	1235	94	1	300000	120000
2089	1236	101	1	300000	120000
2090	1237	165	1	350000	120000
2091	1237	69	1	300000	120000
2092	1238	101	1	300000	120000
2093	1239	165	1	350000	120000
2094	1239	164	1	320000	120000
2095	1239	102	1	320000	120000
2096	1239	99	1	300000	100000
2097	1240	164	1	320000	120000
2098	1240	102	1	320000	120000
2099	1240	71	1	300000	120000
2100	1240	83	1	350000	120000
2101	1240	81	1	350000	120000
2102	1240	23	1	300000	120000
2103	1241	85	1	350000	120000
2104	1241	74	1	350000	120000
2105	1242	94	1	300000	120000
2106	1242	76	1	350000	120000
2107	1243	164	1	320000	120000
2108	1244	76	1	350000	120000
2109	1244	142	1	300000	120000
2110	1244	49	1	250000	100000
2111	1244	163	1	300000	120000
2112	1244	102	1	320000	120000
2113	1244	165	1	350000	120000
2114	1245	164	1	320000	120000
2115	1246	72	2	300000	240000
2116	1246	169	1	60000	1
2117	1247	92	1	300000	120000
2118	1248	164	1	320000	120000
2119	1249	97	1	300000	120000
2120	1249	101	1	300000	120000
2121	1250	48	1	250000	120000
2122	1250	101	1	300000	120000
2123	1251	72	1	300000	120000
2124	1252	101	7	300000	840000
2125	1252	102	9	320000	1080000
2126	1252	100	7	300000	840000
2127	1252	164	6	320000	720000
2128	1252	165	1	350000	120000
2129	1252	76	2	350000	240000
2130	1252	77	1	350000	120000
2131	1252	75	1	350000	120000
2132	1252	78	1	350000	120000
2133	1252	79	1	350000	120000
2134	1252	81	1	350000	120000
2135	1252	162	1	300000	120000
2136	1252	161	1	300000	120000
2137	1252	71	1	300000	120000
2138	1253	101	1	300000	120000
2139	1254	101	1	300000	120000
2140	1254	75	1	350000	120000
2141	1254	73	1	350000	120000
\.


--
-- TOC entry 4075 (class 0 OID 17674)
-- Dependencies: 415
-- Data for Name: orders; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.orders (id, code, customer_id, store_id, promotion_id, subtotal, discount_amount, shipping_fee, total_amount, payment_method, status, note, created_at, customer_name, customer_phone, customer_address, customer_email, shipping_carrier, shipping_tracking_code, payment_status, email, customer_district_id, customer_ward_code, exported_at, exported_sapo_at, exported_spx_at) FROM stdin;
3	#ADM-035074	3	\N	\N	350000	0	0	350000	transfer	cancelled	Ig kiki	2026-01-27 16:40:35.546139+00	Kỳ Kỳ	0708083054	214/C45 Nguyễn Trãi, phường Nguyễn Cư Trinh, Quận 1	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
5	ORD-73511769621093	5	\N	\N	300000	0	20000	320000	banking	cancelled	\N	2026-01-28 17:24:53.187139+00	Đởm Triết	0979911670	15 NXK, Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	1456	21509	\N	\N	\N
6	ORD-48761769621359	5	\N	\N	320000	0	20000	340000	banking	cancelled	\N	2026-01-28 17:29:19.272408+00	Đởm Triết	0979911670	15 NXK, Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	1456	21509	\N	\N	\N
7	ORD-26581769621681	1	\N	\N	250000	0	20000	270000	banking	cancelled	\N	2026-01-28 17:34:40.547563+00	Admin Brown	0900000000	15 NXK, Quận Tân Phú, Hồ Chí Minh	brownvn25@gmail.com	\N	\N	unpaid	\N	1456	21509	\N	\N	\N
8	ORD-64151769777792	7	\N	\N	280000	0	20000	300000	banking	cancelled	\N	2026-01-30 12:56:31.552607+00	Anh thư	0967849849	9/1b xô viết nghệ tĩnh , Quận Ninh Kiều, Cần Thơ	hinhanhthu0197@gmail.com	\N	\N	unpaid	\N	1572	550102	\N	\N	\N
9	ORD-88891769780624	8	\N	\N	400000	0	20000	420000	banking	cancelled	\N	2026-01-30 13:43:44.02047+00	Lu Bu Tông	0881718137	12 Lộp Chộp, huyện Sốp Cộp, Sơn La	jamaica@buchaby.com	\N	\N	unpaid	\N	3266	800118	\N	\N	\N
31	ORD-81081769920527	17	\N	\N	300000	0	20000	320000	banking	cancelled	\N	2026-02-01 04:35:26.819583+00	Bảo Trinh	0359501066	Vinhomes grand park q9 toà Be5, Quận 9, Hồ Chí Minh	tranhabaotrinh@gmail.com	\N	\N	unpaid	\N	1451	20904	\N	\N	\N
25	ORD-43681769875269	5	\N	\N	300000	0	20000	320000	banking	cancelled	\N	2026-01-31 16:01:08.673765+00	Test Email	0979911670	15 NXK, Huyện Tam Đường, Lai Châu	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	2010	70210	\N	\N	\N
17	ORD-27811769843771	10	\N	\N	250000	0	20000	270000	banking	cancelled	\N	2026-01-31 07:16:10.886908+00	thuỳ trang 	0987346948	282 ấp bình phước, Huyện Chợ Mới, An Giang	chanxinh2505@gmail.com	\N	\N	unpaid	\N	1757	510904	\N	\N	\N
37	#ADM-647150	22	\N	\N	280000	0	0	280000	transfer	cancelled	KOL	2026-02-01 13:14:07.241781+00	Kol _kduyeen	0905650280  	20 đường 19c phạm thế hiển p7 q8	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
18	ORD-20481769856848	11	\N	\N	280000	0	20000	300000	banking	completed	\N	2026-01-31 10:54:08.244554+00	Nguyễn Thị Vân Anh	0857900799	Toà TNR, 54A Nguyễn Chí Thanh₫, Quận Đống Đa, Hà Nội	anhnv270199@gmail.com	\N	GY3QDUDW	unpaid	\N	1486	1A0407	\N	\N	\N
15	ORD-66281769788258	9	\N	\N	630000	0	20000	650000	banking	completed	\N	2026-01-30 15:50:57.890721+00	Nguyễn Kế Châu Anh	0911066568	Sky89, 89 Lê Thị Chợ, Quận 7, TPHCM, Quận 7, Hồ Chí Minh	jenninguyenke@gmail.com	\N	GYBMRRLF	unpaid	\N	1449	20702	\N	\N	\N
42	ORD-93101769953574	25	\N	\N	250000	0	20000	270000	banking	cancelled	\N	2026-02-01 13:46:14.288794+00	Ngọc Phương	0387561470	Hẻm 494, số nhà 494/3, Huyện Vĩnh Cửu, Đồng Nai	ngocphuong231102@gmail.com	\N	\N	unpaid	\N	2049	480209	\N	\N	\N
47	#ADM-352296	29	\N	\N	250000	0	0	250000	cod	cancelled		2026-02-01 15:22:32.371293+00	nhi	12234567	jkdkjgk	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
44	#ADM-753467	27	\N	\N	250000	0	0	250000	transfer	completed	Ig inthezone.02.04	2026-02-01 15:12:33.56863+00	Thái Phụng 	0962645716 	385F/39A-B, Đ. Trần Nam Phú, An Khánh, Ninh Kiều, Cần Thơ	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
43	#ADM-017783	26	\N	\N	250000	0	0	250000	transfer	completed	Ig haiien.ho	2026-02-01 14:10:17.886072+00	Ig haiien.ho	0388955848	318 Nguyễn Oanh, P17, quận Gò Vấp	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
40	#ADM-422686	18	\N	\N	700000	0	0	700000	transfer	completed	Ig gnasche.lorie	2026-02-01 13:27:02.797571+00	gnasche.lorie	0789515460	15 Nguyễn Xuân Khoát	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
39	#ADM-716235	23	\N	\N	250000	0	0	250000	transfer	completed	Ig quyên	2026-02-01 13:15:16.328318+00	Quyên	0901606857	72 lê thánh tôn p bến thành vincom đồng khởi	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
36	#ADM-041916	21	\N	\N	250000	0	0	250000	transfer	completed	Ig Bích Liên	2026-02-01 13:04:02.009185+00	Bích Liên	0964226997	24 lê thánh tôn q1	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
35	#ADM-749363	17	\N	\N	300000	0	0	300000	transfer	completed	web	2026-02-01 09:55:49.493655+00	Bảo Trinh	0359501066	Vinhomes grand park q9 toà Be5, Quận 9, Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
38	#ADM-647561	22	\N	\N	280000	0	0	280000	transfer	completed	KOL	2026-02-01 13:14:07.656013+00	Kol _kduyeen	0905650280  	20 đường 19c phạm thế hiển p7 q8	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
34	#ADM-042575	20	\N	\N	530000	0	0	530000	transfer	completed	Ig thanh hằng	2026-02-01 06:24:02.676784+00	Vũ Thái Thanh Hằng 	0972032010	235 hồng thập tự, long khánh, đồng nai	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
33	#ADM-948065	19	\N	\N	530000	0	0	530000	transfer	completed	Ig minh thư	2026-02-01 06:22:28.189781+00	Thư 	 0902905362	114 đồng văn cống, phường cát lái, hcm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
32	#ADM-791546	18	\N	\N	280000	0	0	280000	transfer	completed	Ig ttrraamm	2026-02-01 06:19:51.64851+00	ttrraamm	0789515460	Khách tới nhà lấy	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
30	#ADM-527225	16	\N	\N	530000	0	0	530000	cod	completed	Ig thie	2026-02-01 03:45:27.357471+00	Phương Thi 	0937809293 	Toà nhà Lafayatte số 8 đường Phùng Khắc Khoan phường Sài Gòn TPHCM - Lầu 2 APRIL	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
28	#ADM-061726	14	\N	\N	280000	0	0	280000	transfer	completed	Ig thuý an	2026-02-01 03:37:41.86013+00	Thuy an	0377029438	183 đan kia phường 7 đà lạt	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
45	#ADM-840803	28	\N	\N	1350000	0	0	1350000	transfer	completed	Ig huong xu le	2026-02-01 15:14:00.919896+00	Thảo (Huong Xu Le)	0904502318	93, P.Bạch Mai, Q.Hai Bà Trưng, TP.Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
27	#ADM-764749	13	\N	\N	500000	0	0	500000	cod	completed	Ig ngọc ngọc	2026-02-01 03:32:44.853931+00	ngọc ngọc 	0988224226 	132 bến vân đồn P6 Q4	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
26	#ADM-023376	12	\N	\N	250000	0	0	250000	transfer	completed	Ig su	2026-01-31 17:03:43.480494+00	SU	0976685522	chung cư khánh hội 3, 360G Bến Vân Đồn P1, Q4	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
46	#ADM-073734	25	\N	\N	250000	0	0	250000	cod	completed	Web	2026-02-01 15:17:54.206363+00	Ngọc Phương	0387561470	Địa chỉ giao hàng\nHẻm 494, số nhà 494/3, Huyện Vĩnh Cửu, Đồng Nai	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
29	#ADM-345301	15	\N	\N	620000	0	0	620000	transfer	completed	Ig tô vân	2026-02-01 03:42:25.405891+00	Tô vân 	0962755240	30 Yên Ninh, Ba Đình, HN 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
2	#ADM-034177	3	\N	\N	350000	0	0	350000	transfer	completed	Ig kiki	2026-01-27 16:40:34.327486+00	Kỳ Kỳ	0708083054	214/C45 Nguyễn Trãi, phường Nguyễn Cư Trinh, Quận 1	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
4	ORD-27101769620733	4	\N	\N	250000	0	20000	270000	banking	completed	\N	2026-01-28 17:18:53.284955+00	Hân Kitty Phạm	0325225854	06 Song Hàng An Phú Quận 2 cũ, Thành Phố Thủ Đức, Hồ Chí Minh	phamngochan9694@gmail.com	\N	\N	unpaid	\N	3695	90765	\N	\N	\N
1	#ADM-451432	2	\N	\N	350000	0	0	350000	cod	completed	Ig baongoc08	2026-01-27 10:24:11.543574+00	Ngọc 	0967515969	Midtown The Peak M8 block A đường 15 phường tân phú q7	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
48	#ADM-500909	5	\N	\N	250000	0	0	250000	transfer	cancelled		2026-02-01 15:25:01.035579+00	Test 	0979911670	k;nmjl;kjh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
49	#ADM-180547	5	\N	\N	250000	0	0	250000	transfer	cancelled	Test	2026-02-01 15:53:00.767728+00	Test	0979911670	15 NXK	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
50	#ADM-258223	5	\N	\N	500000	0	0	500000	transfer	cancelled	Test	2026-02-01 15:54:18.363434+00	Test	0979911670	15 NXK	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
51	#ADM-442918	5	\N	\N	250000	0	0	250000	cod	cancelled	Test	2026-02-01 15:57:23.068419+00	Test 	0979911670	15 NXK	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
57	#ADM-319948	5	\N	\N	250000	0	0	250000	transfer	cancelled	Test	2026-02-02 04:25:20.111663+00	Test 	0979911670	15 NXK	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
75	#ADM-814144	42	\N	\N	280000	0	0	280000	transfer	completed	Ig phuc hanh pham	2026-02-02 17:20:14.251626+00	Ig phuc hanh pham	0855877511	264 nam kì khởi nghĩa, p. Xuân hoà, hcm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
58	#ADM-967080	5	\N	\N	250000	0	0	250000	transfer	returned	Test	2026-02-02 04:36:07.246629+00	Test 	0979911670	15 NXK	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
62	#ADM-045605	31	\N	\N	250000	0	0	250000	cod	cancelled	Ig ngọc ngọc	2026-02-02 14:04:05.725914+00	Ig Ngọc Ngọc	0988224226	132 bến vân đồn quận 4	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
74	#ADM-171631	41	\N	\N	250000	0	0	250000	transfer	completed	Ig	2026-02-02 16:19:31.72944+00	Ig khánh ngọc 	0328766486	30 lê trung nghĩa p bảy hiền hcm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
71	#ADM-009896	38	\N	\N	220000	0	0	220000	transfer	completed	Ig minh anh	2026-02-02 14:20:09.991983+00	Ig minh anh (Nguyễn Hoàng Minh Anh)	0395926658	1304, toà N4B khu đô thị Trung Hoà Nhân Chính, Thanh Xuân,Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
73	#ADM-116391	40	\N	\N	750000	0	0	750000	transfer	completed	Ig	2026-02-02 16:18:36.506886+00	ig Be Han	0933888347	203 cao văn lầu p2 q6 cũ	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
70	#ADM-948437	37	\N	\N	350000	0	0	350000	transfer	completed	Ig bao quyen	2026-02-02 14:19:08.536666+00	Ig bao quyen ( Quyên)	0773872547	k356/h111/3 hoàng diệu,hải châu,đà nẵng ( trước sát nhập )	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
52	#ADM-788228	18	\N	\N	250000	0	0	250000	transfer	completed	IG	2026-02-02 03:59:48.327476+00	Khánh Huyền	0789515460	15 Nguyễn Xuân Khoát	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
72	ORD-43911770044400	39	\N	\N	600000	0	20000	620000	banking	completed	\N	2026-02-02 15:00:00.067668+00	Khánh Linh	0902850016	6/5 quốc hương, Thành Phố Thủ Đức, Hồ Chí Minh	khnhlin143@gmail.com	\N	\N	unpaid	\N	3695	90764	\N	\N	\N
69	#ADM-902433	36	\N	\N	250000	0	0	250000	transfer	completed	Ig uynuyn	2026-02-02 14:18:22.529926+00	Ig uynuyn	0989572278	Tô mì studio đường nguyễn văn linh phường mỹ phước Long Xuyên an giang	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
68	#ADM-857245	18	\N	\N	650000	0	0	650000	transfer	completed	Baby dưa lưới xinh iu	2026-02-02 14:17:37.345771+00	Ig Baby dưa lưới xinh iu 	0789515460	15 nguyễn xuân khoát	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
67	#ADM-755858	35	\N	\N	320000	0	0	320000	transfer	completed	Ig alna nguyen	2026-02-02 14:15:55.971453+00	Ig alna nguyen (alna nguyen)	0937748847	918/9H hương lộ 2 - Phường Bình Trị Đông A - Quận bình tân	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
66	#ADM-629086	34	\N	\N	280000	0	0	280000	transfer	completed	Ig huỳnh như quỳnh	2026-02-02 14:13:49.212444+00	Ig huỳnh như quỳnh (Như Quỳnh)	0356620045	block b chung cư sunrise riverside, phước kiểng, nhà bè	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
65	#ADM-565118	33	\N	\N	350000	0	0	350000	transfer	completed	Ig n.nhii01	2026-02-02 14:12:45.281629+00	Ig n.nhii01 ( Nhi )	0941840848	280 nguyễn trường tộ tân hoà biên hoà đồng nai	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
64	#ADM-319317	32	\N	\N	530000	0	0	530000	transfer	completed	Ig huyền lê	2026-02-02 14:08:39.410946+00	Ig Huyền Lê	0929333317	333 điện biên phủ, bình thạnh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
61	#ADM-082229	30	\N	\N	1620000	0	0	1620000	transfer	completed	IG	2026-02-02 06:51:22.348334+00	Ig Bee	0902616275	162/15 Đường số 42, phường Bình Trưng Đông, Thủ Đức	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
60	#ADM-714228	18	\N	\N	530000	0	0	530000	transfer	completed	Ig	2026-02-02 05:38:34.377443+00	ig Vicky	0789515460	652 Lạc long Quân quận tân bình	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
63	#ADM-222468	31	\N	\N	280000	0	0	280000	transfer	completed	Ig ngọc ngọc	2026-02-02 14:07:02.591082+00	ig ngọc ngọc	0988224226	132 bến vân đồn quận 4	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
86	#ADM-034357	51	\N	\N	350000	0	0	350000	transfer	completed	Ig hanjin_wb	2026-02-03 16:10:34.486226+00	Nhi	0909078752	192 nguyễn công trứ phường Bến Thành	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
76	#ADM-109244	43	\N	\N	500000	0	0	500000	transfer	completed	Ig gud9.nhuy	2026-02-02 17:58:29.3723+00	Như Ý	0906482677	 86 chu văn an p26 quận bình thạnh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
78	#ADM-976805	18	\N	\N	250000	0	0	250000	transfer	completed	Ig vicky	2026-02-02 19:36:16.975577+00	Ig Vicky 	0789515460	652 lạc long quân phường tân hoà quận tân bình	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
77	#ADM-191920	44	\N	\N	630000	0	0	630000	transfer	completed	Ig duy linh nguyen	2026-02-02 17:59:52.041413+00	Duy Linh Nguyễn	0931637448	07 Đặng Tất, phường Buôn Hồ, tỉnh ĐakLak	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
1238	#ADM-462554	958	\N	\N	300000	0	0	300000	cod	shipping	Ig tra nguyen	2026-04-14 06:17:42.647035+00	Ig tra nguyen	 0856574104 	400/8B Ung Văn Khiêm, P.25, Q.Bình Thạnh \nToà nhà Hahalolo	\N	\N	\N	unpaid	\N	\N	\N	2026-04-14 15:32:14.742+00	\N	\N
82	#ADM-246965	47	\N	\N	750000	0	0	750000	transfer	completed	Thiện Thảo KOl	2026-02-03 05:57:27.070152+00	Thiện Thảo	0898681865	126 đường 38 Bình Trưng Tây - Thủ Đức	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
81	#ADM-175660	46	\N	\N	280000	0	0	280000	transfer	completed	Ig by_elisette	2026-02-03 05:56:15.761212+00	Ig by_elisette	0397024181	89/13 Nguyễn Thượng Hiền, p5, Bình Thạnh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
79	ORD-81081770094385	17	\N	\N	530000	0	20000	550000	banking	completed	\N	2026-02-03 04:53:04.833109+00	Bảo Trinh	0359501066	VinHomes grand park sảnh Be5, Thành Phố Thủ Đức, Hồ Chí Minh	tranhabaotrinh@gmail.com	\N	\N	unpaid	\N	3695	90752	\N	\N	\N
80	#ADM-111467	45	\N	\N	250000	0	0	250000	transfer	completed	Ig ân nin	2026-02-03 05:55:11.568092+00	Ig ân nin 	0909215263	1269 phan văn trị p gò vấp 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
59	#ADM-659099	18	\N	\N	530000	0	0	530000	transfer	completed	IG	2026-02-02 05:37:39.255543+00	Ig iamlekhanh	0789515460	633 hậu giang quận 6	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
54	#ADM-939466	18	\N	\N	350000	0	0	350000	transfer	completed	Shopee	2026-02-02 04:02:19.562971+00	Nguyễn Bích Huyền shopee	0789515460	45/7, Nguyễn Công Trứ, Phường 8,\nThành Phố Đà Lạt, Lâm Đồng	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
83	#ADM-935640	46	\N	\N	250000	0	0	250000	transfer	completed	Ig by_elisette	2026-02-03 06:08:55.836905+00	Ig by_elisette	0397024181	89/13 Nguyễn Thượng Hiền, p5, Bình Thạnh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
53	#ADM-882607	18	\N	\N	190000	0	0	190000	transfer	completed	shopee	2026-02-02 04:01:22.719378+00	Minh Tâm shopee	0789515460	Khu Ba Đình, Thị Trấn Nam Ban,\nHuyện Lâm Hà, Lâm Đồng	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
85	#ADM-994854	50	\N	\N	280000	0	0	280000	transfer	completed	Ig crtnch	2026-02-03 16:09:54.971957+00	Ig crtnch 	0325267896	 375 tân thới hiệp 21 , Tổ 3 ,Kp3 ,quận 12 ( nhớ gõ đủ)	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
101	#ADM-586560	64	\N	\N	280000	0	0	280000	transfer	completed	Ig	2026-02-03 16:53:06.686113+00	ngọc	0769823114	371 nguyễn oanh, p17 gò vấp	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
103	#ADM-632848	66	\N	\N	600000	0	0	600000	transfer	completed	Ig nguyễn hoàng nhật ái	2026-02-03 16:53:52.963505+00	Ig nguyễn hoàng nhật ái	0777777900	90 Nguyễn Hữu Cảnh , phường 22 , quận Bình Thạnh ,	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
104	ORD-20921770181811	67	\N	\N	250000	0	20000	270000	banking	completed	\N	2026-02-04 05:10:10.750667+00	Phạm ngọc hân 	0384295534	Số 42d thạnh xuân 37 quận 12( trong bãi vật liệu đức trí fpt), Quận 12, Hồ Chí Minh	ngochan280811@gmail.com	\N	\N	unpaid	\N	1454	21209	\N	\N	\N
113	ORD-30151770208234	74	\N	\N	250000	0	20000	270000	banking	cancelled	\N	2026-02-04 12:30:34.361422+00	Hà Quyên 	0981681406	24 đường b2 Phước hải ( Nhà ngô kỳ nhiên ) , Thành phố Nha Trang, Khánh Hòa		\N	\N	unpaid	\N	1548	410103	\N	\N	\N
116	#ADM-097432	77	\N	\N	280000	0	0	280000	transfer	completed	Ig Lê Thanh Thảo	2026-02-04 18:18:17.544691+00	Ig Lê Thanh Thảo	0933097084	8/28 nguyễn đình khơi, phường4, tân bình, tphcm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
84	#ADM-947792	48	\N	\N	280000	0	0	280000	transfer	completed	Ig bống	2026-02-03 06:42:27.895815+00	Ig bống	0832191587	144 triệu việt vương nguyễn du hai bà trưng hà nội 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
87	#ADM-096741	52	\N	\N	530000	0	0	530000	transfer	completed	Ig thu hà	2026-02-03 16:11:36.859056+00	Ig thu hà	0398514443	Thôn 7a \nEawy-eahleo-dăk lái	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
88	#ADM-153851	53	\N	\N	250000	0	0	250000	transfer	completed	Ig thuý ngọc	2026-02-03 16:12:33.972456+00	Ig thuý ngọc	0702928310	Ấp 1A , xã Tân Hoà , tp Cần Thơ	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
89	#ADM-217521	54	\N	\N	280000	0	0	280000	transfer	completed	Ig nhee nhee	2026-02-03 16:13:37.632741+00	Ig nhee nhee	0396994800	Số 38 đường D4, phường chánh nghĩa, thành phố thủ dầu một, bình dương	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
90	#ADM-315303	55	\N	\N	2410000	0	0	2410000	transfer	completed	Ig bow bangkok	2026-02-03 16:15:15.438053+00	Ig bow bangkok	0369166.222	163 Trương Thị Hoa, phường Tân Thới Hiệp, Quận 12, thành phố Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
91	#ADM-378951	32	\N	\N	250000	0	0	250000	transfer	completed	Ig huyền lê	2026-02-03 16:16:19.094561+00	Ig huyền lê 	0929333317	333 điện biên phủ, bình thạnh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
92	#ADM-420380	56	\N	\N	280000	0	0	280000	transfer	completed	Ig bảo loan	2026-02-03 16:17:00.502284+00	Ig bảo loan	0564164989	K486 nguyễn tri phương cẩm nam hội an quảng nam	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
93	#ADM-466026	18	\N	\N	350000	0	0	350000	transfer	completed	Sarah ig	2026-02-03 16:17:46.170009+00	Sarah ig	0789515460	15 nguyễn xuân khoát	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
115	#ADM-893900	76	\N	\N	530000	0	0	530000	transfer	completed	Ig thu lương	2026-02-04 13:48:14.041962+00	Ig thu lương	0908.603.893	Lương Ngọc Cẩm Thu\nsố nhà 1407, ấp Bình Phú, xã Long Tân , huyện Nhơn Trạch , tỉnh Đồng Nai	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
120	#ADM-111357	81	\N	\N	530000	0	0	530000	transfer	completed	Ig trẻ người non stop	2026-02-05 03:45:11.455322+00	Ig trẻ người non stop	0888671434	122/38 Bùi đình tuý,p12, q. Bình thạnh 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
96	#ADM-758270	59	\N	\N	250000	0	0	250000	transfer	completed	Ig em PT mét gữi	2026-02-03 16:22:38.400281+00	Ig em PT mét gữi 	0903522900	48/11 Nguyễn An Ninh, p14 , Q. Bình Thạnh , HCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
105	ORD-21381770189358	69	\N	\N	250000	0	20000	270000	banking	completed	\N	2026-02-04 07:15:57.826099+00	kiều thị kim anh	0839010434	khách sạn hoa sứ, trại bò phúc lộc, Huyện Châu Thành, Tiền Giang		\N	\N	unpaid	\N	1740	530518	\N	\N	\N
97	#ADM-800426	60	\N	\N	530000	0	0	530000	transfer	completed	ig giang tran	2026-02-03 16:23:20.556046+00	ig giang tran 	0907739179	17F2/A42, khu phố 6, phường Trung Dũng, Biên Hoà	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
98	#ADM-848656	61	\N	\N	530000	0	0	530000	transfer	completed	Ig Bby	2026-02-03 16:24:08.770986+00	Ig Bby 	0769998968	146/2q đường số 30, p6 Gò Vấp	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
99	#ADM-887254	62	\N	\N	530000	0	0	530000	transfer	completed	Ig tiểu my	2026-02-03 16:24:47.389922+00	Ig tiểu my 	0988041293	Chung cư Sunshine Diamond River , 422 Đào Trí , Phú Thuận , Q7 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
100	#ADM-929946	63	\N	\N	530000	0	0	530000	transfer	completed	Ig babimilo.11	2026-02-03 16:25:30.066045+00	Ig babimilo.11	093360237	436b/17 ba thang hai p12 quan 10	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
102	ORD-47431770137622	65	\N	\N	250000	0	20000	270000	banking	completed	\N	2026-02-03 16:53:42.179006+00	Phạm Thành Khang	0904835375	Chung cư Tân Mai, Lê Đức Anh, Quận Bình Tân, Hồ Chí Minh	khangpham.5375@gmail.com	\N	\N	unpaid	\N	1458	21909	\N	\N	\N
111	#ADM-063255	72	\N	\N	280000	0	0	280000	transfer	completed	Ig mỹ anh	2026-02-04 09:24:23.356142+00	Ig mỹ anh 	0916 520 385	81 Lê Lai , phường Trường Chinh , TP Kon Tum 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
106	#ADM-954329	70	\N	\N	530000	0	0	530000	cod	completed	Ig nguyễn thị thảo nguyên	2026-02-04 08:32:34.428825+00	Ig nguyễn thị thảo nguyên	0966240425	Ngã tư chánh nhơn cát nhơn phù cát bình định	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
107	#ADM-184142	71	\N	\N	190000	0	0	190000	transfer	completed	shopee	2026-02-04 08:36:24.252948+00	thanh tuyền	789515460	15NXK	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
108	#ADM-220578	71	\N	\N	250000	0	0	250000	transfer	completed	shopee	2026-02-04 08:37:00.692294+00	hà kiều oanh	789515460	15NXK	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
109	#ADM-247362	71	\N	\N	180000	0	0	180000	transfer	completed	shopee	2026-02-04 08:37:27.481851+00	hoai vy	789515460	15NXK	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
110	#ADM-269429	71	\N	\N	250000	0	0	250000	transfer	completed	shopee	2026-02-04 08:37:49.541158+00	Minh Thư	789515460	15NXK	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
112	#ADM-496122	73	\N	\N	280000	0	0	280000	transfer	completed	Ig kaythy.16	2026-02-04 12:01:36.232859+00	Ig kaythy.16	0935539978	270/109/14 phan đình phùng , p1 phú nhuận	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
114	ORD-50311770209638	75	\N	\N	250000	0	20000	270000	banking	completed	\N	2026-02-04 12:53:57.568925+00	Hà Quyên	0981671406	28 đường B2 . Phước hải ( nhà ngô kỳ nhiên ), Thành phố Nha Trang, Khánh Hòa		\N	\N	unpaid	\N	1548	410103	\N	\N	\N
119	#ADM-939096	80	\N	\N	530000	0	0	530000	transfer	completed	Ig winkzeeee	2026-02-05 03:25:39.19676+00	Ig winkzeeee	0933948272	423 Trường Chinh, Phường Đông Hưng Thuận, HCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
118	#ADM-829924	79	\N	\N	530000	0	0	530000	transfer	completed	Ig trà my	2026-02-05 03:23:50.021196+00	 Lê Thị Trà My	 03338407494	140 quốc lộ 13, khu phố ninh thịnh, thị trấn Lộc Ninh, Tỉnh Bình Phước	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
95	#ADM-705579	58	\N	\N	530000	0	0	530000	transfer	completed	Ig ggiantttttt	2026-02-03 16:21:45.695577+00	Ig ggiantttttt	0918974705	481/23/10 tân kì tân quý, tân phú	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
117	#ADM-745814	78	\N	\N	250000	0	0	250000	transfer	completed	Ig just C	2026-02-05 03:22:25.947765+00	Ig just C 	0379201403	82 Nguyễn Sơn - Ngọc Lâm - Long Biên - Hà Nội 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
121	#ADM-201668	82	\N	\N	530000	0	0	530000	transfer	completed	Ig thanh tam	2026-02-05 04:03:21.789406+00	Ig thanh tam	0347345259	B48/1 ấp Phước Bình, xã Phước Tỉnh, huyện Long Điền, tỉnh BRVT\nPhuoc Tinh, Long Điền, Tinh Ba Ria - Vung Tau,	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
122	#ADM-665529	83	\N	\N	1980000	0	0	1980000	transfer	completed	Ig phương trinh	2026-02-05 04:44:25.635217+00	Ig phương trinh	0359298912	204/3B Cao Đạt, phường 1, quận 5 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
123	#ADM-515179	84	\N	\N	880000	0	0	880000	transfer	completed	Ig hồng ngân	2026-02-05 06:05:15.28651+00	Ig hồng ngân	0779633259	13 xóm vôi p14 q5	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
128	ORD-23531770290512	5	\N	\N	280000	0	20000	300000	banking	cancelled	\N	2026-02-05 11:21:52.25591+00	Test	0979911670	15 Nguyễn Xuân Khoát, Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	1456	21509	\N	\N	\N
134	#ADM-783317	5	\N	\N	280000	0	0	280000	transfer	returned	Test	2026-02-05 12:49:43.505331+00	Test	0979911670	15 NXK	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
125	#ADM-725883	86	\N	\N	880000	0	0	880000	transfer	completed	Ig thu vo	2026-02-05 08:22:05.982852+00	Ig thu vo 	0932221092	8 tran nao q2	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
126	#ADM-895272	87	\N	\N	530000	0	0	530000	transfer	completed	Ig xuý	2026-02-05 08:24:55.394751+00	Ig xuý 	0968562187	610 võ văn kiệt phường cầu ông lãnh ạ\n\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
124	#ADM-550563	85	\N	\N	280000	0	0	280000	transfer	completed	Ig tdhtran_	2026-02-05 06:05:50.681702+00	Ig tdhtran_	0337552416	1351/9/2 Phan Văn Trị phường 10 Gò Vấp	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
127	#ADM-822937	88	\N	\N	280000	0	0	280000	transfer	completed	Ig phương linh	2026-02-05 10:37:03.070746+00	Ig phương linh	0877979798	Khu phố 10, p tân Biên Biên Hoà Đồng Nai	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
141	#ADM-995215	99	\N	\N	560000	0	0	560000	transfer	completed	Ig	2026-02-06 03:53:15.31578+00	🏳️‍🌈	0971464109	Chung cư opal garden	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
130	#ADM-867589	90	\N	\N	250000	0	0	250000	transfer	completed	Ig lan phương	2026-02-05 11:27:47.690145+00	Ig lan phương	0395328548	39 nhất chi mai , tân bình	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
129	#ADM-778103	89	\N	\N	300000	0	0	300000	transfer	completed	Ig wuenie.gum	2026-02-05 11:26:18.206568+00	Ig wuenie.gum	0949941439	55a/3 kp3 phường tân hoà biên hoà đồng nai 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
131	#ADM-670234	91	\N	\N	280000	0	0	280000	transfer	completed	Ig khanhvandoann	2026-02-05 11:57:50.349516+00	Ig khanhvandoann	0937059890	52 Thành Thái P.12 Q.10 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
132	ORD-49991770293953	92	\N	\N	250000	0	20000	270000	banking	completed	\N	2026-02-05 12:19:12.91067+00	Phạm Uyên Thy	0858326679	145/1, hẻm 145, quốc lộ 13, Quận Thủ Đức, Hồ Chí Minh	uyenthi6679@gmail.com	\N	\N	unpaid	\N	1463	21803	\N	\N	\N
133	ORD-76141770295315	93	\N	\N	320000	0	20000	340000	banking	completed	\N	2026-02-05 12:41:55.377881+00	Phạm Hoài Hải Yến	0913612642	122 Ỷ Lan, Thành phố Quy Nhơn, Bình Định	phamhoaihaiyen@gmail.com	\N	\N	unpaid	\N	1662	370113	\N	\N	\N
136	#ADM-941453	95	\N	\N	280000	0	0	280000	transfer	completed	ig nganxiinhiu	2026-02-05 14:15:41.869504+00	ig  nganxiinhiu ( Ngan Pham)	84869726548	Hẻm 240/13 Lê Duẩn, Xã An Phước, Huyện Long Thành, Đồng Nai	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
135	ORD-91881770299473	94	\N	\N	250000	0	20000	270000	banking	completed	\N	2026-02-05 13:51:13.121597+00	Mai Phan	0911172812	An residence 14 đường số 1 (lý phục man quẹo vô), Quận 7, Hồ Chí Minh	Maiphannp26@gmail.com	\N	\N	unpaid	\N	1449	20701	\N	\N	\N
137	#ADM-178644	71	\N	\N	280000	0	0	280000	transfer	completed	Ig hân hânn	2026-02-05 14:36:18.754102+00	Ig hân hânn	789515460	15NXK	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
139	#ADM-393898	97	\N	\N	560000	0	0	560000	transfer	completed	Ig joice.nn_	2026-02-05 18:49:54.016158+00	Ig joice.nn_	0938223711	173/45/36 Khuông Việt, Phú Trung, Tân Phú	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
142	ORD-92051770350527	1	\N	\N	280000	0	20000	300000	banking	cancelled	\N	2026-02-06 04:02:07.424667+00	Admin Brown	0900000000	15 Nguyễn Xuân Khoát, Quận Tân Phú, Hồ Chí Minh	brownvn25@gmail.com	\N	\N	unpaid	\N	1456	21509	\N	\N	\N
140	ORD-49341770347153	98	\N	\N	530000	0	20000	550000	banking	completed	\N	2026-02-06 03:05:52.933821+00	Hồ Thị Kim Tho	0797206844	31 đường số 37 , Quận 2, Hồ Chí Minh	tho.hokimtho01@gmail.com	\N	\N	unpaid	\N	1443	20201	\N	\N	\N
143	#ADM-214455	91	\N	\N	250000	0	0	250000	transfer	completed	Ig khanhvandoann	2026-02-06 04:13:34.597893+00	Ig khanhvandoann	0937059890	\n\n52 Thành Thái P.12 Q.10	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
144	#ADM-307436	100	\N	\N	320000	0	0	320000	transfer	completed	Ig ohvielleicht	2026-02-06 04:15:07.530557+00	Ig ohvielleicht 	+84 79 6256618	428 Võ Nguyên Giáp, Khuê Mỹ, Ngũ Hành Sơn, Đà Nẵng 550000	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
145	#ADM-504165	71	\N	\N	280000	0	0	280000	transfer	completed	Ig vy	2026-02-06 04:18:24.26482+00	Ig vy	789515460	121 cô giang, phường Cầu ông lãnh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
146	#ADM-497758	101	\N	\N	280000	0	0	280000	transfer	completed	Ig meii	2026-02-06 06:14:57.87019+00	Ig meii 	0841444661	332/34 độc lậ phú thọ hoà tân phú\n\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
147	#ADM-023870	102	\N	\N	250000	0	0	250000	transfer	completed	Ig thư	2026-02-06 06:40:24.017629+00	Ig thư	0935883228 	148 trần nam trung, hoà xuân, cẩm lệ, đà nẵng 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
148	#ADM-103489	50	\N	\N	530000	0	0	530000	transfer	completed	Wind xpress ig	2026-02-06 06:41:43.653975+00	Wind xpress ig	0325267896	Địa chỉ: 375 tân thới hiệp 21 , Tổ 3 ,Kp3 ,quận 12\nW24130 Miki brown	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
149	#ADM-777755	103	\N	\N	1000000	0	0	1000000	transfer	completed	Ig tiên tiên	2026-02-06 07:42:57.875681+00	Ig tiên tiên	0985037507	02 Nguyễn Lương Bằng - xã Lộc thanh - tp bảo Lộc - lâm đồng \n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
150	#ADM-708067	104	\N	\N	530000	0	0	530000	transfer	completed	Ig bích ngọc	2026-02-06 08:15:08.16877+00	Ig bích ngọc 	0905441264	K52/73 Đinh Tiên Hoàng , Đà Nẵng \n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
151	#ADM-130905	105	\N	\N	280000	0	0	280000	transfer	completed	hồng đào Ig 🍒R🍒	2026-02-06 10:35:31.056049+00	hồng đào Ig 🍒R🍒	0909089356	147/5 thạch lam tân phú HCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
152	#ADM-386015	106	\N	\N	280000	0	0	280000	transfer	completed	Ig hyhchaah	2026-02-06 13:43:06.123385+00	Ig hyhchaah	0985533618	224A kp5 p1 đường 786 tp Tây Ninh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
153	#ADM-008640	107	\N	\N	530000	0	0	530000	transfer	completed	Ig DWF	2026-02-06 15:16:48.765142+00	Ig DWF	0376891811	46-48-50 phạm hồng thái, p. bến thành\n- Tuyên 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
138	ORD-23641770308185	96	\N	\N	530000	0	20000	550000	banking	completed	\N	2026-02-05 16:16:25.279819+00	Kiều Trang	0393252767	63 Nguyễn Ngọc Kỳ , Thị xã La Gi, Bình Thuận	nguyenthivuong0733@gmail.com	\N	\N	unpaid	\N	1778	471002	\N	\N	\N
155	#ADM-522642	109	\N	\N	530000	0	0	530000	transfer	completed	Ig linh trần	2026-02-07 02:48:42.749184+00	Ig linh trần 	0886339378	hem 420/18a khu 3 phú lợi đại lộ binh duong\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
159	ORD-11621770443916	5	\N	\N	250000	0	20000	270000	banking	cancelled	\N	2026-02-07 05:58:35.900981+00	Test Tết	0979911670	15 Nxk, Huyện Ninh Phước, Ninh Thuận	thiemd779@gmail.com	\N	\N	unpaid	\N	1986	450406	\N	\N	\N
181	#ADM-354253	134	\N	\N	280000	0	0	280000	transfer	completed	Ig lê t. Thu hường	2026-02-08 04:19:14.367039+00	Ig lê t. Thu hường	0784649439	Ấp 5 miễu bà 8 long thọ nhơn trạch đồng nai	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
156	#ADM-598741	110	\N	\N	530000	0	0	530000	transfer	completed	Ig ee.sora	2026-02-07 02:49:58.846338+00	Ig ee.sora 	0868774517	\n75 thôn minh tiến,xã hàm minh, huyện Hàm thuận nam tỉnh bình thuận(cũ)\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
158	#ADM-850496	112	\N	\N	600000	0	0	600000	transfer	completed	Ig lê thảo linh	2026-02-07 04:34:10.657541+00	Ig lê thảo linh	0915181172	Vinhome grand paảk s7.5\n\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
190	#ADM-713775	142	\N	\N	1530000	0	0	1530000	transfer	completed	Ig Thảo nguyên	2026-02-08 09:08:33.882352+00	Thảo nguyên	0935891747	Saigon south residence 113a Nguyễn Hữu Thọ, Phước Kiển, Nhà Bè\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
161	#ADM-980437	114	\N	\N	250000	0	0	250000	transfer	completed	Ig 17dasick	2026-02-07 11:16:20.533955+00	Ig 17dasick	0783396444	348A Trường Chinh, phường 13, Tân Bình	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
162	#ADM-017180	115	\N	\N	250000	0	0	250000	transfer	completed	Ig phương trinh	2026-02-07 11:16:57.278066+00	Ig phương trinh 	0359298912 	204/3B Cao Đạt, phường 1, quận 5 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
163	#ADM-063216	116	\N	\N	600000	0	0	600000	transfer	completed	Ig kimm	2026-02-07 11:17:43.309907+00	Ig kimm	0706741315	33 nguyễn hữu thọ tân hưng quận 7\nSunrise city view toà B	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
160	#ADM-950043	113	\N	\N	350000	0	0	350000	transfer	completed	Ig bchamm_	2026-02-07 11:15:50.145092+00	Ig bchamm_	0357022231	18/17/18 Hương Lộ Ngọc Hiệp, Nha Trang, Khánh Hoà\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
164	#ADM-168093	117	\N	\N	1160000	0	0	1160000	transfer	completed	Ig ivy.trieule	2026-02-07 11:19:28.195647+00	Ig ivy.trieule	 0349270422	1534 hùng vương, cam phú, cam ranh khánh hoà\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
165	#ADM-250777	118	\N	\N	600000	0	0	600000	transfer	completed	Ig nguyễn ngọc thiên kiều	2026-02-07 11:20:50.878053+00	Ig nguyễn ngọc thiên kiều 	0988949801	96/3 đường s19, p8, gvap	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
167	#ADM-490633	120	\N	\N	1050000	0	0	1050000	transfer	completed	The name is Ngan	2026-02-07 11:24:50.726933+00	The name is Ngan 	0906616319 .	 365/19A đường hậu Giang , phường Bình Phú. Quận 6 tphcm . \n 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
168	#ADM-531189	121	\N	\N	280000	0	0	280000	transfer	completed	Ig mai quỳnh	2026-02-07 11:25:31.284259+00	Ig mai quỳnh 	0394975445	72-74 Nguyễn Thị Minh Khai, phường 6 quận 3\nCentec Tower	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
169	#ADM-195106	122	\N	\N	280000	0	0	280000	transfer	completed	Ig như ngọc nguyễn thị	2026-02-07 11:36:35.222478+00	Ig như ngọc nguyễn thị 	0358590047	764 Thọ Hoà, Xuân Thọ, Xuân Lộc, Đồng Nai	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
171	ORD-45041770479165	124	\N	\N	940000	0	20000	960000	banking	completed	\N	2026-02-07 15:46:04.884702+00	Minh Ngọc	0329588917	Số nhà 102 khu chăn nuôi Hàm Long, Huyện Thủy Nguyên, Hải Phòng	daongoc873@gmail.com	\N	\N	unpaid	\N	1726	30902	\N	\N	\N
173	#ADM-870328	126	\N	\N	780000	0	0	780000	transfer	completed	Ig vũ vy	2026-02-07 18:27:50.429146+00	Ig vũ vy 	0904471747 	35 nguyễn đức cảnh, p.thắng lợi, tp.buôn ma thuột	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
172	ORD-45611770480184	125	\N	\N	530000	0	20000	550000	banking	completed	\N	2026-02-07 16:03:03.742137+00	Bảo Thy	0976281379 	Block A1, Opal riverside, đường số 10, Thành Phố Thủ Đức, Hồ Chí Minh	thyphan1221@gmail.com	\N	\N	unpaid	\N	3695	90741	\N	\N	\N
174	#ADM-919554	127	\N	\N	600000	0	0	600000	transfer	completed	Ig ngocbaongan.	2026-02-07 18:28:39.652775+00	Ig ngocbaongan.	0838812881	37/6/29 hồ văn nhánh kp8 p5 mỹ tho tiền giang	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
175	#ADM-971328	128	\N	\N	680000	0	0	680000	transfer	completed	Ig hmgtwm	2026-02-07 18:29:31.417648+00	Ig hmgtwm	0827840027	Ba Đình - Nam Ban Lâm Hà - Lâm Đồng	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
176	#ADM-036949	129	\N	\N	530000	0	0	530000	transfer	completed	Ig bùi yến vy	2026-02-07 18:30:37.043631+00	Ig bùi yến vy	0909923466	BlockA, cc Kingdom101, p diên hồng, q10	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
178	#ADM-124830	131	\N	\N	1030000	0	0	1030000	transfer	completed	Ig DN	2026-02-07 18:32:04.939013+00	Ig DN 	0931231295	số nhà 24d3 ngõ 689 lạc long quân, phường tây hồ, hà nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
177	#ADM-075010	130	\N	\N	250000	0	0	250000	transfer	completed	Ig như quỳnh	2026-02-07 18:31:15.102462+00	Ig như quỳnh	0901567568	K408/H29/18 Hoàng Diệu, Phường Hoà Cường, Tp Đà Nẵng	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
179	#ADM-167886	132	\N	\N	250000	0	0	250000	transfer	completed	ig kim mỹ hà	2026-02-07 18:32:47.978098+00	ig kim mỹ hà 	0901115018	104/11 huỳnh mẫn đạt p2 q5 tphcm ( sát nhập 104/11 huỳnh mẫn đạt p chợ quán tphcm )	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
180	#ADM-224726	133	\N	\N	980000	0	0	980000	transfer	completed	Kol tuyền	2026-02-07 18:33:44.821545+00	Kol tuyền 	0966946346 	778 xô viết nghệ tĩnh phường thạnh mỹ tây quận bình thạnh \n\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
182	#ADM-472520	135	\N	\N	2510000	0	0	2510000	transfer	completed	Ig tamikanguyen	2026-02-08 04:21:12.630345+00	Ig tamikanguyen	0901104935	501/19 Phạm văn Chiêu phường 13.Quận Gò vấp\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
184	#ADM-406622	137	\N	\N	320000	0	0	320000	transfer	completed	Ig meehgoxcutie_	2026-02-08 05:26:46.718724+00	Ig meehgoxcutie_	0979768986	CityHouse - CD Apartment\n339/24B Đ. Lê Văn Sỹ, Phường 12, Quận 3, Hồ Chí Minh 700000, Vietnam 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
183	#ADM-350499	136	\N	\N	250000	0	0	250000	transfer	completed	Ig quỳnh anh	2026-02-08 05:25:50.598883+00	Ig quỳnh anh	0336823079	Số 39 , ql 13, Lộc Thái , Lộc Ninh, Bình Phước	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
185	#ADM-471396	47	\N	\N	700000	0	0	700000	transfer	completed	Thiện Thảo	2026-02-08 05:27:51.514789+00	Thiện Thảo	0898681865	126 đường 38 Bình Trưng Tây - Thủ Đức	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
186	ORD-79171770535486	138	\N	\N	850000	0	20000	870000	banking	completed	\N	2026-02-08 07:24:46.258204+00	Vũ Khánh Huyền 	0382829311	Ngõ 57 K40 khu 2 phường quảng yên, Thị xã Quảng Yên, Quảng Ninh		\N	\N	unpaid	\N	2066	171108	\N	\N	\N
187	#ADM-581023	139	\N	\N	600000	0	0	600000	transfer	completed	Ig vie	2026-02-08 09:06:21.152468+00	Ig vie	0779078617	152 Lê Quang Định, Bình Thạnh\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
188	#ADM-614686	140	\N	\N	280000	0	0	280000	transfer	completed	Ig nnphiephe	2026-02-08 09:06:54.786005+00	Ig nnphiephe 	0335856599 	Chung cư CT9 Vĩnh Điềm Trung , Phường Vĩnh Hiệp tp Nha Trang \n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
189	#ADM-653746	141	\N	\N	680000	0	0	680000	transfer	completed	Ig jeff	2026-02-08 09:07:33.848518+00	Ig jeff	0938780757	Linh Cung \nEco Green Block H, 39B Nguyễn Văn Linh, Tân Thuận Tây, Quận 7\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
166	#ADM-402459	119	\N	\N	530000	0	0	530000	transfer	returned	Ig kim chi	2026-02-07 11:23:22.571748+00	Ig kim chi 	0914019900	19 bàu cát4-ph tân bình -tân binh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
201	ORD-17111770579827	152	\N	\N	320000	0	20000	340000	banking	completed	\N	2026-02-08 19:43:47.118528+00	Nguyễn Ngọc Minh Thư	0918441864	21B.Nguyễn Thị Thập,Quận 7,phường Tân Phú,TPHCM, Quận 7, Hồ Chí Minh	minhthu010720@gmail.com	\N	\N	unpaid	\N	1449	20707	\N	\N	\N
200	ORD-65901770572633	151	\N	\N	280000	0	20000	300000	banking	completed	\N	2026-02-08 17:43:53.407474+00	Linh Trang	0823236968	81 Thạch Thị Thanh, Quận 1, Hồ Chí Minh	abc@gmail.com	\N	\N	unpaid	\N	1442	20110	\N	\N	\N
220	#ADM-099424	163	\N	\N	250000	0	0	250000	transfer	completed	Ig nguyen bich ngoc [ĐÃ THANH TOÁN]	2026-02-09 09:58:19.535975+00	Ig nguyen bich ngoc	0392951733	15 đường 37, phường hiệp bình phước , khu đô thị vạn phúc ,\n\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
191	#ADM-480836	143	\N	\N	250000	0	0	250000	transfer	completed	Ig NGỌC MAI	2026-02-08 09:21:20.940197+00	Ig NGỌC MAI	0835772142	ố 33, lô D, TTTM BÌNH MINH - K1, P cái vồn, TX Bình minh, Vĩnh Long 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
192	#ADM-525772	58	\N	\N	250000	0	0	250000	transfer	completed	ig	2026-02-08 09:22:05.897243+00	Giang TKTQ	0918974705	tân kỳ tân quý	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
193	ORD-21721770561671	144	\N	\N	600000	0	20000	620000	banking	completed	\N	2026-02-08 14:41:11.2406+00	Ngọc trâm	0342617409	94/3 ấp 3, Huyện Bình Đại, Bến Tre		\N	\N	unpaid	\N	1895	560602	\N	\N	\N
194	#ADM-306293	145	\N	\N	1270000	0	0	1270000	transfer	completed	Ig bow bangkok	2026-02-08 15:08:26.400932+00	Ig bow bangkok	0369166.222 	163 Trương Thị Hoa, phường Tân Thới Hiệp, Quận 12, thành phố Hồ Chí Minh\n ( Người Nhận BN2705)	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
195	#ADM-344122	146	\N	\N	530000	0	0	530000	transfer	completed	Ig an thuỳ	2026-02-08 15:09:04.224343+00	 Ig an thuỳ 	0946698781	Ngân Hàng Vib Dĩ An, \nSố 2 Đường M, Khu Trung Tâm Hành Chính, Phường Dĩ An, Thành Phố Dĩ An, Bình Dương\n\nTrần Thuỳ An	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
196	#ADM-409078	147	\N	\N	270000	0	0	270000	transfer	completed	Ig quynh anh maria	2026-02-08 15:10:09.191844+00	Ig quynh anh maria	0369514710	Xóm Miếu, cụm 7, Vĩnh ninh , đại Thanh, Hà Nội\nTên: Nguyễn Thị Thu Trang	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
197	#ADM-448036	148	\N	\N	250000	0	0	250000	transfer	completed	Ig thu thuỷ	2026-02-08 15:10:48.141107+00	Ig thu thuỷ 	0334947873	\nDc sn 5c hẻm 43/99/7 trung kính, trung hoà, cầu giấy Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
198	#ADM-494871	149	\N	\N	600000	0	0	600000	transfer	completed	Ig immatcha_cha	2026-02-08 15:11:34.973831+00	Ig immatcha_cha	0343178558	451 Xuân Đỉnh , Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
199	#ADM-171555	150	\N	\N	280000	0	0	280000	transfer	completed	Ig KHIMY	2026-02-08 15:39:31.976044+00	Ig KHIMY 	0908444086	Lô D cc ecogreen ,nguyễn văn linh ,q7\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
204	#ADM-289408	5	\N	\N	280000	0	0	280000	transfer	cancelled	[ĐÃ THANH TOÁN]	2026-02-09 02:31:30.063323+00	Test	0979911670	15 NXK	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
203	#ADM-246216	153	\N	\N	280000	0	0	280000	transfer	cancelled	[ĐÃ THANH TOÁN]	2026-02-09 02:30:46.731155+00	Test 	0979116700	15 NXK	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
202	ORD-21671770604194	5	\N	\N	280000	0	20000	300000	banking	returned	\N	2026-02-09 02:29:54.346636+00	Test 	0979911670	15 NXK, Quận Tân Phú, Hồ Chí Minh	thiemd779@gmail.com	\N	\N	unpaid	\N	1456	21509	\N	\N	\N
205	#ADM-141679	71	\N	\N	250000	0	0	250000	transfer	completed	ien.00 [ĐÃ THANH TOÁN]	2026-02-09 03:35:41.804035+00	ien.00	789515460	15 NXK khách ghé lấy	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
206	#ADM-185130	154	\N	\N	630000	0	0	630000	transfer	completed	Ig jessi.cameronj [ĐÃ THANH TOÁN]	2026-02-09 03:36:25.235536+00	Ig jessi.cameronj	0702624572	102/2 võ trứ nha trang , khánh hoà 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
207	#ADM-255802	155	\N	\N	750000	0	0	750000	transfer	completed	Honeyfai_ [ĐÃ THANH TOÁN]	2026-02-09 03:37:35.920963+00	Honeyfai_	0818999538   	M Village Ho Bieu Chanh 7 Hồ Biểu Chánh, Phường 12, Phú Nhuận, Thành phố Hồ Chí Minh, Vietnam  	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
212	ORD-85311770615659	5	\N	\N	250000	0	20000	270000	banking	cancelled	\N	2026-02-09 05:40:58.706937+00	Đởm Triết	0979911670	15 NXK, Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	1456	21508	\N	\N	\N
208	#ADM-290522	156	\N	\N	280000	0	0	280000	transfer	completed	Ig phạm ngọc tuyền [ĐÃ THANH TOÁN]	2026-02-09 03:38:10.627367+00	Ig phạm ngọc tuyền	0358137039	Nhà 8a hẻm 35 đường cmt8 kp1 phường 3 tây ninh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
210	#ADM-592064	71	\N	\N	750000	0	0	750000	transfer	completed	Ig wie [ĐÃ THANH TOÁN]	2026-02-09 05:06:32.199223+00	Ig wie	789515460	17 hoà hưng phường 12 quận 10	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
211	#ADM-715344	71	\N	\N	850000	0	0	850000	transfer	completed	Ig zina  [ĐÃ THANH TOÁN]	2026-02-09 05:08:35.455899+00	Ig zina 	789515460	Quận 7. Lê văn lương	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
213	#ADM-755605	71	\N	\N	350000	0	0	350000	transfer	completed	Ig wie  [ĐÃ THANH TOÁN]	2026-02-09 06:15:55.763292+00	Ig wie 	789515460	15NXK KHÁCH GHÉ LẤY	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
214	#ADM-789222	158	\N	\N	250000	0	0	250000	transfer	completed	Ig zoe  [ĐÃ THANH TOÁN]	2026-02-09 06:16:29.325734+00	Ig zoe 	0932086042	\n908/3 đoàn văn bơ p18 q4	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
218	#ADM-058834	161	\N	\N	280000	0	0	280000	transfer	completed	ig  [ĐÃ THANH TOÁN]	2026-02-09 09:57:38.951196+00	Mi Mi	0796287600	13 bình thới p11 quận 11 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
217	#ADM-021568	103	\N	\N	600000	0	0	600000	transfer	completed	Ig tiên tiên  [ĐÃ THANH TOÁN]	2026-02-09 09:57:01.695754+00	Ig tiên tiên 	0985037507	88/4 Đoàn Thị Điểm - xã Lộc thanh - tp bảo Lộc	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
216	#ADM-022483	160	\N	\N	530000	0	0	530000	transfer	completed	Ig tran tran  [ĐÃ THANH TOÁN]	2026-02-09 07:43:42.597559+00	Ig tran tran 	0767629111	 105/2 Phạm Phú Thứ P Bình Tiên (p3 q6)	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
215	#ADM-632227	159	\N	\N	600000	0	0	600000	transfer	completed	Ig đặng quỳnh [ĐÃ THANH TOÁN]	2026-02-09 06:30:32.332419+00	Ig đặng quỳnh	0706772763	atino 73 nguyễn việt hồng , phường an phú , ninh kiều cần thơ\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
219	#ADM-099257	162	\N	\N	250000	0	0	250000	transfer	returned	Ig nguyen bich ngoc [ĐÃ THANH TOÁN]	2026-02-09 09:58:19.367887+00	Ig nguyen bich ngoc	0392951733	15 đường 37, phường hiệp bình phước , khu đô thị vạn phúc ,\n\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
157	#ADM-371376	111	\N	\N	560000	0	0	560000	transfer	completed	Ig y0310_	2026-02-07 04:09:31.47746+00	Ig y0310_	0899290899	Số nhà 03 (cạnh mẫu giáo xóm đồng), Phường Phong Hải, Thị Xã Quảng Yên, Quảng Ninh\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
154	#ADM-380783	108	\N	\N	530000	0	0	530000	transfer	completed	Ig PHUONG UYEN	2026-02-07 02:46:20.886975+00	Ig PHUONG UYEN	0948434814	214 ni sư huỳnh liên p10 quận tb	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
170	ORD-21601770473914	123	\N	\N	530000	0	20000	550000	banking	completed	\N	2026-02-07 14:18:34.253249+00	Thanh Ngân	0386946804	55/4b trương đình hội p16 q8, Quận 8, Hồ Chí Minh	bcee.stal63@gmail.com	\N	\N	unpaid	\N	1450	20816	\N	\N	\N
222	#ADM-407207	165	\N	\N	560000	0	0	560000	transfer	completed	Kol hannal [ĐÃ THANH TOÁN]	2026-02-09 13:56:47.34857+00	Kol hannal	0366986065	Masteri thảo điền, t3, q2	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
221	#ADM-357022	164	\N	\N	250000	0	0	250000	transfer	completed	ig Cam cam [ĐÃ THANH TOÁN]	2026-02-09 13:55:57.164651+00	ig Cam cam	070 3624481	hocmon	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
224	ORD-77001770646817	167	\N	\N	600000	0	20000	620000	banking	completed	\N	2026-02-09 14:20:16.867056+00	Đào Lý Thảo Vy	0705992224	52/12 đường số 17, Quận 7, Hồ Chí Minh	vydaolythao@gmail.com	\N	\N	unpaid	\N	1449	20710	\N	\N	\N
227	#ADM-860680	169	\N	\N	280000	0	0	280000	transfer	completed	Ig themtradau [ĐÃ THANH TOÁN]	2026-02-09 16:34:20.804593+00	Ig themtradau	0934142781	15NXK khách ghé lấy	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
223	#ADM-445109	166	\N	\N	350000	0	0	350000	transfer	completed	Ig võ thảo ngân  [ĐÃ THANH TOÁN]	2026-02-09 13:57:25.220578+00	Ig võ thảo ngân 	0795407876	khu dân cư ấp phú thuận xã phú thịnh huyện tam bình tỉnh vĩnh long\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
225	#ADM-863065	168	\N	\N	350000	0	0	350000	transfer	completed	Ig hathanhthuylinh [ĐÃ THANH TOÁN]	2026-02-09 15:27:43.210588+00	Ig hathanhthuylinh	0902904947	\n47/17a bùi công trừng nhị bình hóc môn	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
253	#ADM-948160	186	\N	\N	560000	0	0	560000	transfer	completed	ig hanna_owo2u [ĐÃ THANH TOÁN]	2026-02-11 08:52:28.293158+00	ig hanna_owo2u	0789989206	42/2L ap tien lan ba diem hocmon 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
228	#ADM-853617	170	\N	\N	280000	0	0	280000	transfer	completed	Ig ulsuove_ [ĐÃ THANH TOÁN]	2026-02-09 16:50:53.728799+00	Ig ulsuove_	0364789984 	212/3b phạm văn chiêu phường 9 gò vấp	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
229	#ADM-515535	161	\N	\N	630000	0	0	630000	transfer	completed	Ig sấm [ĐÃ THANH TOÁN]	2026-02-09 17:35:15.661936+00	Ig sấm	0796287600	13 bình thới quận 1	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
230	#ADM-350224	171	\N	\N	350000	0	0	350000	transfer	completed	Maika  [ĐÃ THANH TOÁN]	2026-02-10 03:15:50.333977+00	Maika 	0906777794	50 đường số 3. P an lạc A. \nQuận bình tân	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
231	#ADM-424641	71	\N	\N	250000	0	0	250000	transfer	completed	JANNIE [ĐÃ THANH TOÁN]	2026-02-10 03:17:04.795688+00	JANNIE	789515460	15 NXK 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
232	#ADM-356533	172	\N	\N	780000	0	0	780000	transfer	completed	Ig mita.lam [ĐÃ THANH TOÁN]	2026-02-10 03:49:16.647519+00	Ig mita.lam	0838081828	7A Hải Thượng Lãn Ông - phường Rạch Sỏi - TP Rạch Giá - Kiên Giang\nTrang 0838081828 ạ	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
233	#ADM-826405	173	\N	\N	500000	0	0	500000	transfer	completed	Ig lâm thị mỹ hảo [ĐÃ THANH TOÁN]	2026-02-10 06:27:06.54033+00	Ig lâm thị mỹ hảo	0384753595	29 trần quang diệu, phường 13, quận 3	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
234	#ADM-860218	71	\N	\N	280000	0	0	280000	transfer	completed	Ig LTB  [ĐÃ THANH TOÁN]	2026-02-10 06:27:40.336912+00	Ig LTB 	789515460	15 NXK\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
235	#ADM-894715	71	\N	\N	350000	0	0	350000	transfer	completed	Ig jackie  [ĐÃ THANH TOÁN]	2026-02-10 06:28:14.831126+00	Ig jackie 	789515460	\nHai bà trưng q3	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
236	#ADM-938647	174	\N	\N	750000	0	0	750000	transfer	completed	Ig hoàng lan  [ĐÃ THANH TOÁN]	2026-02-10 06:28:58.759184+00	Ig hoàng lan 	0931539768	30 Phạm Văn Đồng Khu Cầu Xéo xã long thành đồng nai \n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
237	#ADM-892447	175	\N	\N	390000	0	0	390000	transfer	completed	Ig thanh truc huynh  [ĐÃ THANH TOÁN]	2026-02-10 07:51:32.569104+00	Ig thanh truc huynh 	086 5767578 	T08-05 The Manhattan, Vinhome Grand Park, Phường Long Bình, TP Thủ Đức	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
238	#ADM-067304	176	\N	\N	350000	0	0	350000	transfer	completed	ig _princesshappiii [ĐÃ THANH TOÁN]	2026-02-10 08:44:27.406754+00	ig _princesshappiii	0786968512	112/114/9 nguyễn thị minh khai quận ninh kiều thành phố cần thơ	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
245	#ADM-651036	181	\N	\N	750000	0	0	750000	transfer	completed	ig Quỳnh Như [ĐÃ THANH TOÁN]	2026-02-10 17:47:31.135503+00	 Quỳnh Như	0978596565 	283 bến vân đồn q4 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
242	ORD-86671770730296	5	\N	\N	280000	0	20000	300000	banking	cancelled	\N	2026-02-10 13:31:35.722048+00	Test	0979911670	15 NXK, Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	1456	21509	\N	\N	\N
239	ORD-55501770719260	177	\N	\N	630000	0	20000	650000	banking	completed	\N	2026-02-10 10:27:40.277133+00	Ngọc Nữ	0933850356	27/29 Điện Biên Phủ, Quận Bình Thạnh, Hồ Chí Minh	glamwithnu@gmail.com	\N	\N	unpaid	\N	1462	21611	\N	\N	\N
241	#ADM-137147	178	\N	\N	530000	0	0	530000	transfer	completed	Ig hien le [ĐÃ THANH TOÁN]	2026-02-10 11:15:37.257805+00	Ig hien le	0969813416	26 Lý Tự Trọng, P. Bến Nghé, TP HCM\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
243	#ADM-814691	179	\N	\N	430000	0	0	430000	transfer	completed	Ig kiwi1989 [ĐÃ THANH TOÁN]	2026-02-10 15:03:34.784574+00	Ig kiwi1989	0366286418	63-65A11, Khu phố 11, Nguyễn Văn Tiên, Phường Tân Phong, Tp. Biên Hoà, Tỉnh Đồng Nai.	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
244	#ADM-919989	180	\N	\N	1200000	0	0	1200000	transfer	completed	Ig mochisyx [ĐÃ THANH TOÁN]	2026-02-10 15:05:20.082758+00	Ig mochisyx	0899903807	204b6/5/2 Nguyễn Văn Hưởng, Thảo Điền	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
240	#ADM-097303	71	\N	\N	530000	0	0	530000	transfer	returned	ig tudocuavii [ĐÃ THANH TOÁN]	2026-02-10 10:58:17.461822+00	ig tudocuavii	789515460	Trần Coa vân q3	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
247	#ADM-174168	71	\N	\N	530000	0	0	530000	transfer	completed	ig tr.trang1837 [ĐÃ THANH TOÁN]	2026-02-11 05:36:14.316582+00	ig tr.trang1837	789515460	107 Trần huy liệu p12 quận phú nhuận	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
246	#ADM-069882	182	\N	\N	250000	0	0	250000	transfer	completed	Ig kittmy.t [ĐÃ THANH TOÁN]	2026-02-11 04:27:49.981918+00	Ig kittmy.t	890515460	50/29 nguyễn đình chiểu p4 quận phú nhuận 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
250	#ADM-234095	134	\N	\N	250000	0	0	250000	transfer	cancelled	Ig lê t.thu hường [ĐÃ THANH TOÁN]	2026-02-11 07:33:54.236652+00	Ig lê t.thu hường	0784649439	Ấp 5 miễu bà 8 long thọ nhơn trạch đồng nai	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
249	#ADM-326080	184	\N	\N	880000	0	0	880000	transfer	completed	Ig Hiền Phạm [ĐÃ THANH TOÁN]	2026-02-11 07:18:46.174007+00	Ig Hiền Phạm	0977415509	431 lê văn sỹ quận 3	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
252	#ADM-782933	185	\N	\N	350000	0	0	350000	transfer	completed	ig vivannnguyen90 [ĐÃ THANH TOÁN]	2026-02-11 08:49:43.048072+00	ig vivannnguyen90	0933182823	1065 lò góm p7 quận 6	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
251	#ADM-234408	134	\N	\N	250000	0	0	250000	transfer	completed	Ig lê t.thu hường [ĐÃ THANH TOÁN]	2026-02-11 07:33:54.499761+00	Ig lê t.thu hường	0784649439	Ấp 5 miễu bà 8 long thọ nhơn trạch đồng nai	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
226	#ADM-258187	129	\N	\N	400000	0	0	400000	transfer	completed	Ig bùi yến vy [ĐÃ THANH TOÁN]	2026-02-09 15:50:58.318214+00	Ig bùi yến vy	0909923466	BlockA, cc Kingdom101, p diên hồng, q10\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
248	#ADM-257239	183	\N	\N	350000	0	0	350000	transfer	completed	ig honeyfai_ [ĐÃ THANH TOÁN]	2026-02-11 05:37:37.353863+00	ig honeyfai_	0818999538	M village 7 Hồ Biểu Chánh p12 Phú Nhuận	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
254	#ADM-697052	187	\N	\N	600000	0	0	600000	transfer	completed	ig nguyễn khánh hà [ĐÃ THANH TOÁN]	2026-02-11 12:41:37.190296+00	ig nguyễn khánh hà	0867470512	63 đường số 79 tân quy quận 7	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
255	#ADM-798737	188	\N	\N	600000	0	0	600000	transfer	completed	ig mai le [ĐÃ THANH TOÁN]	2026-02-11 12:43:18.8697+00	ig mai le	0901360708	chung cư rivegate quận 4	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
256	#ADM-151652	189	\N	\N	940000	0	0	940000	transfer	completed	ig Kim [ĐÃ THANH TOÁN]	2026-02-11 12:49:11.803553+00	ig Kim	0389012992	2 tôn đức thắng vinhome golden river aqua 3, bến nghé	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
257	#ADM-495437	190	\N	\N	2190000	0	0	2190000	transfer	completed	ig Na Phea [ĐÃ THANH TOÁN]	2026-02-11 13:28:15.55213+00	ig Na Phea	093282796	Phnom penh city,  Cambodia	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
258	#ADM-141755	71	\N	\N	600000	0	0	600000	transfer	completed	ig em quỳnh [ĐÃ THANH TOÁN]	2026-02-11 15:52:21.882832+00	ig em quỳnh	789515460	96C võ thị sau phường tân định quận 1	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
260	#ADM-727874	192	\N	\N	630000	0	0	630000	transfer	cancelled	ig dương vi [ĐÃ THANH TOÁN]	2026-02-11 17:08:47.979832+00	ig dương vi	0939688638	75 đường số 26a quận 6	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
262	#ADM-430423	193	\N	\N	350000	0	0	350000	transfer	completed	ig hằng [ĐÃ THANH TOÁN]	2026-02-11 17:20:30.538106+00	ig hằng	0987030742	Tiệm My nail, só 3 tân thới nhất 1 phường đông hưng thuận bà điểm hocmon	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
261	#ADM-348290	192	\N	\N	780000	0	0	780000	transfer	completed	ig dương vi [ĐÃ THANH TOÁN]	2026-02-11 17:19:08.431698+00	ig dương vi	0939688638	75 đường số 26a quận 6	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
259	#ADM-264068	191	\N	\N	250000	0	0	250000	transfer	completed	ig nhu nguyen [ĐÃ THANH TOÁN]	2026-02-11 15:54:24.201995+00	ig nhu nguyen	0865673495	44 đường sô 7 khu đô thị an phú an khánh phường an phú tp thủ đức	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
263	#ADM-067528	71	\N	\N	280000	0	0	280000	transfer	completed	ig ellie [ĐÃ THANH TOÁN]	2026-02-11 17:31:08.024593+00	ig ellie	789515460	emilyy Spa Thủ Đức	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
264	#ADM-553281	71	\N	\N	250000	0	0	250000	transfer	completed	ig mỹ phương [ĐÃ THANH TOÁN]	2026-02-11 17:39:13.740667+00	ig mỹ phương	789515460	27N đường 32A p10 quận 6	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
265	#ADM-830562	71	\N	\N	280000	0	0	280000	transfer	completed	Ig Meii [ĐÃ THANH TOÁN]	2026-02-12 14:00:31.013426+00	Ig Meii	789515460	Độc Lập	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
266	#ADM-963078	3	\N	\N	350000	0	0	350000	transfer	completed	ig kiki [ĐÃ THANH TOÁN]	2026-02-12 16:32:43.517636+00	ig kiki	0708083054	214/C45 nguễn trãi phường nguyễn cư trinh quận 1	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
267	#ADM-291718	194	\N	\N	750000	0	0	750000	transfer	completed	Ig thu diễm [ĐÃ THANH TOÁN]	2026-02-12 17:44:51.809611+00	Ig thu diễm	0934511930	17-bt7 khu đô thị Văn Phú, Phú La, Hà Đông, HN	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
273	ORD-60441771913750	199	\N	\N	350000	0	20000	370000	banking	completed	\N	2026-02-24 06:15:49.702454+00	Trần M Phương	0786797999	226 Lê Quang Định, Quận Bình Thạnh, Hồ Chí Minh	mingphuong.29@gmail.com	\N	\N	unpaid	\N	1462	21610	\N	\N	\N
269	ORD-16151771633927	195	\N	\N	250000	0	20000	270000	banking	completed	\N	2026-02-21 00:32:07.49585+00	Minh nguyệt	0987569836	Số 79 ngõ 266 phố đội cấn, Quận Ba Đình, Hà Nội	meomun2001@gmail.com	\N	\N	unpaid	\N	1484	1A0101	\N	\N	\N
274	#ADM-456019	200	\N	\N	750000	0	0	750000	transfer	completed	Ig katp9re [ĐÃ THANH TOÁN]	2026-02-24 14:14:16.158624+00	Ig katp9re	0838925459	 Địa chỉ: 128/39, Đường Phạm Văn Hai, Phường 3, Quận Tân Bình, TP. Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
275	#ADM-589785	201	\N	\N	1400000	0	0	1400000	transfer	completed	Ig trish pham [ĐÃ THANH TOÁN]	2026-02-24 14:16:29.900779+00	Ig trish pham	0765551104 	399 Hai Ba Trưng quận 3	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
276	#ADM-798769	55	\N	\N	350000	0	0	350000	transfer	completed	Ig KANYARAT  [ĐÃ THANH TOÁN]	2026-02-24 14:19:58.885412+00	Ig KANYARAT 	0369166.222	163 Trương Thị Hoa, phường Tân Thới Hiệp, Quận 12, thành phố Hồ Chí Minh\n sdt : 0369166.222 ( Người Nhận BN2705)	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
272	ORD-14901771788091	198	\N	\N	280000	0	20000	300000	banking	completed	\N	2026-02-22 19:21:30.878964+00	Vy Vo	0399323601	315 Nguyễn Sơn, Quận Tân Phú, Hồ Chí Minh	xmberv@gmail.com	\N	\N	unpaid	\N	1456	21503	\N	\N	\N
268	#ADM-931961	71	\N	\N	220000	0	0	220000	transfer	completed	Ig mwyuht.ah  [ĐÃ THANH TOÁN]	2026-02-13 04:12:12.408863+00	Ig mwyuht.ah 	789515460	227/8 điện biên phủ bình thạnh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
271	ORD-74781771695530	197	\N	\N	440000	0	20000	460000	banking	completed	\N	2026-02-21 17:38:49.853472+00	Trần Triệu Mai Phương	0964618034	20, ngách 8, ngõ 1 Đình Thôn, Quận Nam Từ Liêm, Hà Nội	trantrieu1302@gmail.com	\N	\N	unpaid	\N	3440	13004	\N	\N	\N
1245	#ADM-986253	966	\N	\N	320000	0	0	320000	cod	shipping	Ig _byphung_	2026-04-14 15:03:06.433678+00	Ig _byphung_	0396825329	số nhà 26 ngõ 280, đường Trần Nguyên Hãn, Lê Chân, Hải Phòng	\N	\N	\N	unpaid	\N	\N	\N	2026-04-14 15:32:14.742+00	\N	\N
278	#ADM-077964	203	\N	\N	350000	0	0	350000	transfer	completed	Ig bí nhe  [ĐÃ THANH TOÁN]	2026-02-24 14:24:38.095322+00	Ig bí nhe 	0944294068	202/51 phạm văn hai p5 qtan bình \n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
280	#ADM-033994	205	\N	\N	280000	0	0	280000	transfer	completed	Ig cẩm nhung  [ĐÃ THANH TOÁN]	2026-02-25 04:50:34.08299+00	Ig cẩm nhung 	0775815411	 45 đào duy anh, phường quang trung, tp quy nhơn, tỉnh bình định	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
281	#ADM-080919	206	\N	\N	250000	0	0	250000	transfer	completed	Ig vyctorilane [ĐÃ THANH TOÁN]	2026-02-25 04:51:21.002159+00	Ig vyctorilane	0962409277 	91 Hàm Nghi, p.Ngô Mây, tp Quy Nhơn, Bình Định\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
282	#ADM-116184	207	\N	\N	250000	0	0	250000	transfer	completed	Ig thuy hang  [ĐÃ THANH TOÁN]	2026-02-25 04:51:56.310424+00	Ig thuy hang 	0975820878	3/70/Đồng Hòa/Kiến An/TP Hải Phòng	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
283	#ADM-157653	208	\N	\N	280000	0	0	280000	transfer	completed	Ig nunu [ĐÃ THANH TOÁN]	2026-02-25 04:52:37.777645+00	Ig nunu	0899326041	 453/70/52 đường Lê Văn Khương, Khu phố 5, phường Hiệp Thành, Quận 12, Thành phố Hồ Chí Minh, Việt Nam	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
284	#ADM-204903	209	\N	\N	400000	0	0	400000	transfer	completed	Ig joiee_devivre [ĐÃ THANH TOÁN]	2026-02-25 04:53:24.988609+00	Ig joiee_devivre	0818887574	Số 16 Ngõ 674 đg Nguyễn Văn Cừ Long biên Hà Nội (sau sát nhập: đg Ng Văn Cừ, phường Bồ Đề Hà Nội)	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
270	ORD-77981771660933	196	\N	\N	280000	0	20000	300000	banking	completed	\N	2026-02-21 08:02:13.363686+00	Thuý An 	0868107862	13/20b tạ quang bửu , Quận 8, Hồ Chí Minh	nguyenthithuyan923@gmail.con	\N	\N	unpaid	\N	1450	20804	\N	\N	\N
285	#ADM-248393	210	\N	\N	250000	0	0	250000	transfer	completed	Ig chau minh  [ĐÃ THANH TOÁN]	2026-02-25 04:54:08.480194+00	Ig chau minh 	0936083509 	c1 tôn thất thiệp, điện biên, ba đình, hà nội ak\nMinh Châu	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
310	#ADM-785375	232	\N	\N	250000	0	0	250000	transfer	completed	ig Bé thảo [ĐÃ THANH TOÁN]	2026-02-26 03:33:05.491054+00	Bé thảo ig	0981651629	Phường 10, gò vấp (địa chỉ cũ)\nPhường gò vấp (địa chỉ mới) 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
286	#ADM-303932	211	\N	\N	600000	0	0	600000	transfer	completed	Ig uyên [ĐÃ THANH TOÁN]	2026-02-25 04:55:04.024645+00	Ig uyên	0981852828	47 đuong 47, p. thao dien q2	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
287	#ADM-346355	212	\N	\N	720000	0	0	720000	transfer	completed	Ig nguyen tran khanh dat [ĐÃ THANH TOÁN]	2026-02-25 04:55:46.443665+00	Ig nguyen tran khanh dat	0963877579	89/1/84 đường số 8, p Tăng Nhơn Phú B, quận 9\nKhánh Đạt 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
288	#ADM-396894	213	\N	\N	520000	0	0	520000	transfer	completed	Ig linh tran [ĐÃ THANH TOÁN]	2026-02-25 04:56:36.981708+00	Ig linh tran	0868424123	23 Nguyễn An Ninh, Đống Đa, Phường Đống Đa, Thành Phố Vĩnh Yên, Vĩnh Phúc	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
289	#ADM-439709	214	\N	\N	280000	0	0	280000	transfer	completed	Ig nguoilanhungquen [ĐÃ THANH TOÁN]	2026-02-25 04:57:19.816456+00	Ig nguoilanhungquen	0918441864 	21B.Nguyễn Thị Thập,Quận 7,TPHCM (phòng 307)\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
314	#ADM-586001	236	\N	\N	630000	0	0	630000	transfer	completed	Ig michelle  [ĐÃ THANH TOÁN]	2026-02-26 05:26:26.128679+00	Ig michelle 	0942300185	30/14 Lê Anh Xuân, p. Thới Bình, q. Ninh Kiều, TP. Cần Thơ\n(KOL TẶNG ĐỒ) 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
291	#ADM-581416	216	\N	\N	250000	0	0	250000	transfer	completed	Ig thoai.tienn [ĐÃ THANH TOÁN]	2026-02-25 04:59:41.509075+00	Ig thoai.tienn	0937800100	333/23 Lê Văn Sỹ, P1, Tân bình	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
292	#ADM-628036	217	\N	\N	280000	0	0	280000	transfer	completed	Ig Doan thu trang [ĐÃ THANH TOÁN]	2026-02-25 05:00:28.130179+00	Ig Doan thu trang	0586338476 	335 Chu Văn An phường 12 Bình Thạnh TPHCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
293	#ADM-675083	218	\N	\N	280000	0	0	280000	transfer	completed	Ig ngốk [ĐÃ THANH TOÁN]	2026-02-25 05:01:15.169667+00	Ig ngốk	0329123422	730/15/8 lạc long qân p9 tbinh tphcm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
294	#ADM-741013	103	\N	\N	540000	0	0	540000	transfer	completed	Ig tiên tiên [ĐÃ THANH TOÁN]	2026-02-25 05:02:21.115804+00	Ig tiên tiên	0985037507	02 Nguyễn Lương Bằng - xã Lộc thanh - tp bảo Lộc - lâm đồng 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
295	#ADM-819422	127	\N	\N	250000	0	0	250000	transfer	completed	Ig ngocbaongan.  [ĐÃ THANH TOÁN]	2026-02-25 05:03:39.602455+00	Ig ngocbaongan. 	0838812881	37/6/29 hồ văn nhánh kp8 p5 mỹ tho tiền giang	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
296	#ADM-950334	219	\N	\N	350000	0	0	350000	transfer	completed	ig mimi [ĐÃ THANH TOÁN]	2026-02-25 05:05:50.420019+00	ig mimi	0937896863	89/28 Nghĩa Hưng, Phường 6, Tân Bình, Tp.HCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
297	#ADM-008193	220	\N	\N	190000	0	0	190000	transfer	completed	Ig minhtamtr [ĐÃ THANH TOÁN]	2026-02-25 05:06:48.283455+00	Ig minhtamtr	0989666805	37C1 ngõ 20 Hồ Tùng Mậu, Cầu Giấy , HN  	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
298	#ADM-055983	221	\N	\N	280000	0	0	280000	transfer	completed	Ig gnaschee_05  [ĐÃ THANH TOÁN]	2026-02-25 05:07:36.073533+00	Ig gnaschee_05 	0964951368	131/24 tô hiến thành p13 quận 10	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
299	#ADM-117860	100	\N	\N	630000	0	0	630000	transfer	completed	Ig ohvielleicht [ĐÃ THANH TOÁN]	2026-02-25 05:08:37.970759+00	Ig ohvielleicht	+84 79 6256618	Adress: 428 Võ Nguyên Giáp, Khuê Mỹ, Ngũ Hành Sơn, Đà Nẵng 550000	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
300	#ADM-178070	222	\N	\N	280000	0	0	280000	transfer	completed	Ig dâu  [ĐÃ THANH TOÁN]	2026-02-25 05:09:38.180086+00	Ig dâu 	0866720360	Đối Diện Quán Karaoke Thu Trang 1\nXã Trưng Trắc, Huyện Văn Lâm, Hưng Yên	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
301	#ADM-225562	223	\N	\N	250000	0	0	250000	transfer	completed	Ig kim my [ĐÃ THANH TOÁN]	2026-02-25 05:10:25.653239+00	Ig kim my	0564077912	754 phan văn hớn xã xuân thới thượng, hóc môn tphcm ( VUS phan văn hớn )	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
302	#ADM-296195	224	\N	\N	1880000	0	0	1880000	transfer	completed	Ig bee zzz [ĐÃ THANH TOÁN]	2026-02-25 05:11:36.286628+00	Ig bee zzz	0898395188	34 Trần đình xu Quan 1	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
303	#ADM-391871	225	\N	\N	250000	0	0	250000	transfer	completed	Ig alena mishkova [ĐÃ THANH TOÁN]	2026-02-25 05:13:11.981307+00	Ig alena mishkova	0867 743 532	124 Lý Thái Tổ, Đường Đệ, Nha Trang, Khánh Hòa	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
307	#ADM-571844	229	\N	\N	630000	0	0	630000	transfer	completed	Ig cún [ĐÃ THANH TOÁN]	2026-02-25 10:49:31.933409+00	Ig cún	0972221913	80/15 Dương Quảng Hàm, phường 5, Gò Vấp, Tphcm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
304	ORD-16881772015017	226	\N	\N	700000	0	20000	720000	banking	completed	\N	2026-02-25 10:23:37.449768+00	Mr. Kuo Đài Loan(Gửi phòng bảo vệ)	0937670759	Đường 7C, KCN Nhơn Trạch 2, Nhơn Trạch, Đồng Nai, Huyện Nhơn Trạch, Đồng Nai	qazxcv74123@gmailc.com	\N	\N	unpaid	\N	1708	480906	\N	\N	\N
305	#ADM-489083	227	\N	\N	350000	0	0	350000	transfer	completed	Ig phi yến  [ĐÃ THANH TOÁN]	2026-02-25 10:48:09.172061+00	Ig phi yến 	0932087209	119-121 lê lợi Q1	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
306	#ADM-525991	228	\N	\N	190000	0	0	190000	transfer	completed	Ig hà mỹ [ĐÃ THANH TOÁN]	2026-02-25 10:48:46.117894+00	Ig hà mỹ	0379207027	Thôn 5, xã quãng tân, huyện Tuy Đức, tỉnh Đăk Nông	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
308	#ADM-433085	230	\N	\N	400000	0	0	400000	transfer	completed	Ig mai le [ĐÃ THANH TOÁN]	2026-02-25 11:03:53.210823+00	Ig mai le	0974274411	mai le\n86 dường số 17 ấp tân tiến xã tân thông hội huyện củ chi\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
309	#ADM-743803	231	\N	\N	280000	0	0	280000	transfer	completed	Ig thu phuong pham [ĐÃ THANH TOÁN]	2026-02-26 03:32:23.901277+00	Ig thu phuong pham	0888068969	Số nhà 24 ngõ 38 đường Tô Hiệu Cẩm Trung Cẩm Phả Quảng Ninh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
346	#ADM-237087	263	\N	\N	250000	0	0	250000	transfer	completed	Ig minthu [ĐÃ THANH TOÁN]	2026-02-27 15:13:57.227108+00	Ig minthu	0374263243	Apc Corporation, 30/7, Trương Văn , Khu Phố Tân Hiệp, Phường Tân Bình, Thành Phố Dĩ An, Bình Dương	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
311	#ADM-865149	233	\N	\N	250000	0	0	250000	transfer	completed	Ig t.mit.ti [ĐÃ THANH TOÁN]	2026-02-26 03:34:25.265344+00	Ig t.mit.ti	0344846390	49 tân thới nhất 1b p. Đông hưng thuận	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
312	ORD-56921772082368	234	\N	\N	950000	0	20000	970000	banking	completed	\N	2026-02-26 05:06:08.072324+00	Thân Thị Ánh 	0393350981	Nhà số 41, Huyện Việt Yên, Bắc Giang	anhthithan383@gmail.com	\N	\N	unpaid	\N	1763	180918	\N	\N	\N
313	#ADM-530865	235	\N	\N	350000	0	0	350000	transfer	completed	Ig uhuyenday [ĐÃ THANH TOÁN]	2026-02-26 05:25:31.003173+00	Ig uhuyenday	0379110562	Park 4, 208 Đ. Nguyễn Hữu Cảnh, Vinhomes Tân Cảng, Bình Thạnh, Hồ Chí Minh\n\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
290	#ADM-534274	215	\N	\N	350000	0	0	350000	transfer	completed	Ig kate lin  [ĐÃ THANH TOÁN]	2026-02-25 04:58:54.389302+00	Ig kate lin 	+84938203196	saigon royal 09 nguyễn trường tộ p13 quận 4	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
315	#ADM-631339	237	\N	\N	600000	0	0	600000	transfer	completed	Ig vo hieu thao [ĐÃ THANH TOÁN]	2026-02-26 05:27:11.423275+00	Ig vo hieu thao	0387054842	(Phòng trọ Út Minh) 563/63/32/2A Lê Văn Khương, khu phố 73, phường Tân Thới Hiệp, Tp.Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
316	#ADM-831692	238	\N	\N	280000	0	0	280000	transfer	completed	zalo ngô thị an [ĐÃ THANH TOÁN]	2026-02-26 05:30:31.818201+00	zalo ngô thị an	092.379.3678	Mặt sau số 168 Trần Thủ Độ, Pháp Vân, Hoàng Liệt, Hoàng Mai, Hà Nội\n(ค้นหา 🔍 sân bóng Đại An)\n☎️ 092.379.3678	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
317	#ADM-295964	42	\N	\N	350000	0	0	350000	transfer	completed	Ig phuc hanh pham [ĐÃ THANH TOÁN]	2026-02-26 06:28:16.443968+00	Ig phuc hanh pham	0855877511	Địa chỉ:264 nam kì khởi nghĩa, p. Xuân hoà, hcm 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
318	#ADM-707752	239	\N	\N	650000	0	0	650000	transfer	completed	Ig rosé rosalie  [ĐÃ THANH TOÁN]	2026-02-26 06:35:07.892136+00	Ig rosé rosalie 	0888007659 / 0355180235	Name : Rose Rosalie ( MS0148 )\nContact Numbers:\n0888007659 / 0355180235\nAdd: 131c, phố Thanh Am, phường Thượng Thanh, quận Long Biên, Hà Nội.\nNhớ ghi mã lên kiện hàng :\nMS0148	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
319	ORD-30741772102757	240	\N	\N	280000	0	20000	300000	banking	completed	\N	2026-02-26 10:45:57.332724+00	Nguyễn Hiếu	0927006907	Đường 19/5 chung cư ct2 vĩnh điềm trung, Thành phố Nha Trang, Khánh Hòa	hieuhappy2201@gmail.com	\N	\N	unpaid	\N	1548	410121	\N	\N	\N
320	#ADM-726639	241	\N	\N	280000	0	0	280000	transfer	completed	Ig ngoc phuc [ĐÃ THANH TOÁN]	2026-02-26 14:38:46.771442+00	Ig ngoc phuc	0703929339	Chung cư Sky89- đường lê thị chợ- phường phú thuận- quận 7	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
321	#ADM-770743	242	\N	\N	280000	0	0	280000	transfer	completed	Ig bống  [ĐÃ THANH TOÁN]	2026-02-26 14:39:30.856289+00	Ig bống 	0965641518	8bt13 foresa 1 khu đô thị xuân phương nam từ liêm Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
322	#ADM-914327	243	\N	\N	250000	0	0	250000	transfer	completed	Ig mifam.store [ĐÃ THANH TOÁN]	2026-02-26 14:41:54.421621+00	Ig mifam.store	0839867277	268 đường 3/2 quận 10	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
323	#ADM-035857	244	\N	\N	630000	0	0	630000	transfer	completed	Ig hí [ĐÃ THANH TOÁN]	2026-02-26 14:43:55.984857+00	Ig hí	0989190214	22A2 Khu Dân Cư Phú Nhuận Phước Long B Quận 9	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
324	#ADM-117261	245	\N	\N	530000	0	0	530000	transfer	completed	Ig Dương Kim Yên [ĐÃ THANH TOÁN]	2026-02-27 04:38:37.355492+00	Ig Dương Kim Yên	082.77.888.55	Số 15 đường 27, KDC An Khánh, An Khánh, Ninh Kiều, Cần Thơ	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
325	#ADM-159387	246	\N	\N	280000	0	0	280000	transfer	completed	Ig ahihi1632 [ĐÃ THANH TOÁN]	2026-02-27 04:39:19.511972+00	Ig ahihi1632	0937926358	 1243 ql20, xã đại lào ,bảo lộc -Lâm đồng( cơm niêu thuận kiều)	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
326	#ADM-356461	229	\N	\N	250000	0	0	250000	transfer	completed	Ig cún [ĐÃ THANH TOÁN]	2026-02-27 12:12:36.614866+00	Ig cún	0972221913	80/15 Dương Quảng Hàm, phường 5, Gò Vấp, Tphcm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
327	#ADM-386823	247	\N	\N	280000	0	0	280000	transfer	completed	Ig vy vy [ĐÃ THANH TOÁN]	2026-02-27 12:13:06.957134+00	Ig vy vy	0865911606 	33 hoa mai , phú nhuận	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
328	#ADM-430314	248	\N	\N	630000	0	0	630000	transfer	completed	Ig bao t truong [ĐÃ THANH TOÁN]	2026-02-27 12:13:50.422835+00	Ig bao t truong	0367055470	B161C khu phố 3, phường đông hưng thuận,quận 12, hcm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
329	#ADM-480592	249	\N	\N	250000	0	0	250000	transfer	completed	Ig loan sansa [ĐÃ THANH TOÁN]	2026-02-27 12:14:40.713528+00	Ig loan sansa	0979537084	Số 6 ngõ 444 thuỵ khuê, tây hồ, hà nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
331	#ADM-523285	250	\N	\N	630000	0	0	630000	transfer	completed	Ig em my [ĐÃ THANH TOÁN]	2026-02-27 12:15:23.384149+00	Ig em my	 0377211144	Đc ấp mỹ lộ phường mỹ Đức tp Hà tiên tỉnh kiên Giang	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
332	#ADM-556636	205	\N	\N	280000	0	0	280000	transfer	completed	Ig cẩm nhung  [ĐÃ THANH TOÁN]	2026-02-27 12:15:56.74752+00	Ig cẩm nhung 	0775815411	 45 đào duy anh, phường quang trung, tp quy nhơn, tỉnh bình định	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
333	#ADM-557037	205	\N	\N	280000	0	0	280000	transfer	completed	Ig cẩm nhung  [ĐÃ THANH TOÁN]	2026-02-27 12:15:57.147447+00	Ig cẩm nhung 	0775815411	 45 đào duy anh, phường quang trung, tp quy nhơn, tỉnh bình định	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
334	#ADM-601357	251	\N	\N	530000	0	0	530000	transfer	completed	Ig imkkiil ( 🧚‍♀️) [ĐÃ THANH TOÁN]	2026-02-27 12:16:41.453238+00	Ig imkkiil ( 🧚‍♀️)	0889993313	Nhà văn hoá khu 5- Hải Yên-Móng Cái-Quảng Ninh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
335	#ADM-648028	252	\N	\N	280000	0	0	280000	transfer	completed	Ig lưu hồng duyên [ĐÃ THANH TOÁN]	2026-02-27 12:17:28.117139+00	Ig lưu hồng duyên	 0919732358	Đc: 191 Tô Hiến Thành p5 Cà Mau 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
336	#ADM-703711	253	\N	\N	530000	0	0	530000	transfer	completed	Ig jan miki  [ĐÃ THANH TOÁN]	2026-02-27 12:18:23.823949+00	Ig jan miki 	 0325267896	375 tân thới hiệp 21 , Tổ 3 ,Kp3 ,quận 12 ( nhớ gõ đủ)\nSố kho : 0325267896  ( nhớ ghi mã khách hàng ) \n\nNhớ ghi mã lên kiện hàng : W24130 Miki brown	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
337	#ADM-764819	254	\N	\N	1030000	0	0	1030000	transfer	completed	ig Van [ĐÃ THANH TOÁN]	2026-02-27 12:19:24.911326+00	ig Van	0964432596 	26A phạm thế hiển p thắng tam tpvt\nVân anh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
338	#ADM-880583	255	\N	\N	2900000	0	0	2900000	transfer	completed	Ig nguyễn phương thảo [ĐÃ THANH TOÁN]	2026-02-27 12:21:20.674739+00	Ig nguyễn phương thảo	0902933723	5/13，đường Nguyễn văn Vĩnh ,P4,Q Tân bình	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
339	#ADM-949075	256	\N	\N	880000	0	0	880000	transfer	completed	Ig dogsea [ĐÃ THANH TOÁN]	2026-02-27 12:22:29.166182+00	Ig dogsea	0923789902 	54/3 Đào Duy Anh p9 Phú Nhuận - ( Phương Thảo )	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
340	#ADM-483805	257	\N	\N	530000	0	0	530000	transfer	completed	phamthanhtra_ [ĐÃ THANH TOÁN]	2026-02-27 12:48:03.90525+00	phamthanhtra_	 0372328696	•  Địa chỉ: 158A Bùi Thị Xuân, Phường Phạm Ngũ Lão, Quận 1	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
342	#ADM-693267	259	\N	\N	750000	0	0	750000	transfer	completed	Ig huỳnh vyvy [ĐÃ THANH TOÁN]	2026-02-27 13:41:33.383228+00	Ig huỳnh vyvy	0909961295	441/59c p25 điện biên phủ bình thanh 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
343	#ADM-967510	260	\N	\N	530000	0	0	530000	transfer	completed	Ig ngọc anh  [ĐÃ THANH TOÁN]	2026-02-27 13:46:07.604966+00	Ig ngọc anh 	0822691939	Khóm 1 thị trấn mỹ an huyện tháp mười tỉnh đồng tháp\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
330	#ADM-480627	249	\N	\N	250000	0	0	250000	transfer	completed	Ig loan sansa [ĐÃ THANH TOÁN]	2026-02-27 12:14:40.914673+00	Ig loan sansa	0979537084	Số 6 ngõ 444 thuỵ khuê, tây hồ, hà nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
344	#ADM-109180	261	\N	\N	250000	0	0	250000	transfer	completed	Ig sbabie_ [ĐÃ THANH TOÁN]	2026-02-27 13:48:29.267381+00	Ig sbabie_	0826350862	địa chỉ ấp minh Tân xã minh hoà huyện châu thành tỉnh kiên Giang	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
589	#ADM-762874	71	\N	\N	350000	0	0	350000	transfer	shipping	About.meooo [ĐÃ THANH TOÁN]	2026-03-13 11:52:42.975174+00	About.meooo	789515460	hoả tốc	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
348	ORD-45321772246672	5	\N	\N	350000	0	500000	850000	banking	cancelled	\N	2026-02-28 02:44:32.240329+00	Test Email	0979911670	15 Test Street, Los Angeles, California	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
349	ORD-59261772247801	265	\N	\N	250000	0	500000	750000	banking	cancelled	\N	2026-02-28 03:03:20.85499+00	Test Email	+14155550198	15 Test Street, Los Angeles, California	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
347	ORD-31141772219154	264	\N	\N	280000	0	20000	300000	banking	cancelled	\N	2026-02-27 19:05:53.962369+00	Nguyễn Quỳnh Chi	0968006054	40 ngách 175 Thịnh Quang, Quận Đống Đa, Hà Nội	nguyenquynhchi297@gmail.com	\N	\N	unpaid	\N	1486	1A0415	\N	\N	\N
350	ORD-93611772250615	5	\N	\N	250000	0	30000	280000	banking	cancelled	\N	2026-02-28 03:50:15.177757+00	Test	0979911670	15 Nguyễn Xuân Khoát, Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	1456	21509	\N	\N	\N
351	ORD-89391772250892	5	\N	\N	250000	0	30000	280000	banking	cancelled	\N	2026-02-28 03:54:51.954722+00	Test	0979911670	15 Nguyễn Xuân Khoát, Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	1456	21509	\N	\N	\N
352	ORD-36291772250961	266	\N	\N	250000	0	500000	750000	banking	cancelled	\N	2026-02-28 03:56:01.317315+00	Test 2	+1 415 555 0198	15 Street, Los Angeles, California	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
354	ORD-11011772251157	266	\N	\N	350000	0	500000	850000	banking	cancelled	\N	2026-02-28 03:59:16.675962+00	Test  2	+1 415 555 0198	15 Street , Los Angeles, California	thiemd779@gmail.com	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
353	ORD-63301772251107	5	\N	\N	250000	0	30000	280000	banking	cancelled	\N	2026-02-28 03:58:27.139288+00	Test 	0979911670	15 Nguyễn Xuân Khoát, Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	1456	21509	\N	\N	\N
373	#ADM-750755	283	\N	\N	250000	0	0	250000	transfer	completed	Ig Lê Nguyễn Minh Thư [ĐÃ THANH TOÁN]	2026-03-01 09:02:31.06869+00	Ig Lê Nguyễn Minh Thư	0828464976	145 ấp Mỹ Thạnh, phường Mỹ Phong tỉnh Đồng Tháp	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
372	#ADM-688868	282	\N	\N	560000	0	0	560000	transfer	completed	ig Feng [ĐÃ THANH TOÁN]	2026-03-01 09:01:28.987756+00	ig Feng	0966811696	96/4 Võ Thành Trang, Phường 11, Tân Bình \n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
371	#ADM-641138	281	\N	\N	280000	0	0	280000	transfer	completed	Ig phương uyên nè [ĐÃ THANH TOÁN]	2026-03-01 09:00:41.264836+00	Ig phương uyên nè	0899478507 	10/4 đường 68 phường hiệp Phú thủ Đức	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
370	#ADM-481486	280	\N	\N	500000	0	0	500000	transfer	completed	Ig tô yến [ĐÃ THANH TOÁN]	2026-02-28 17:24:41.622718+00	Ig tô yến	0986238325	10 Kha Vạn Cân p An Bình, Dĩ An, Bình Dương (chung cư Opal Boulevard)	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
369	#ADM-417481	97	\N	\N	700000	0	0	700000	transfer	completed	Ig nnguyn [ĐÃ THANH TOÁN]	2026-02-28 17:23:37.688952+00	Ig nnguyn	0938223711	173/45/36 Khuông Việt, Phú Trung, Tân Phú 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
368	#ADM-321470	279	\N	\N	280000	0	0	280000	transfer	completed	Ig phương anh [ĐÃ THANH TOÁN]	2026-02-28 17:22:01.575751+00	Ig phương anh	0888066234	ngõ 76 nhà số 2 , đường nguyễn công hoan , phường bắc lý , tp đồng hới tỉnh quảng bình, Phường Bắc Lý, Thành phố Đồng Hới, Quảng Bình 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
367	#ADM-726771	278	\N	\N	400000	0	0	400000	transfer	completed	Ig nm.nguye7723 [ĐÃ THANH TOÁN]	2026-02-28 16:22:06.866946+00	Ig nm.nguye7723	0908561539	126/1d tôn thất đạm f bến nghé q1\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
366	#ADM-609667	277	\N	\N	280000	0	0	280000	transfer	completed	Ig lucy  [ĐÃ THANH TOÁN]	2026-02-28 12:10:09.786649+00	Ig lucy 	0788221551	chung cư miếu nổi, 54 vũ huy tấn 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
365	#ADM-579626	276	\N	\N	280000	0	0	280000	transfer	completed	Ig jade nguyen  [ĐÃ THANH TOÁN]	2026-02-28 12:09:39.747322+00	Ig jade nguyen 	0765009732 	114A Trịnh Phong, Phường, Nha Trang, Khánh Hòa	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
364	#ADM-395363	275	\N	\N	910000	0	0	910000	transfer	completed	Ig anbeoo [ĐÃ THANH TOÁN]	2026-02-28 12:06:35.501406+00	Ig anbeoo	0906969933	nhà số 9, đường số 8, kdc ven sông, tân phong q7	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
363	#ADM-227332	274	\N	\N	630000	0	0	630000	transfer	completed	Ig hien huynh [ĐÃ THANH TOÁN]	2026-02-28 12:03:47.465993+00	Ig hien huynh	0919170394	10a Huyền trân công chúa p4 thành phố Đà Lạt	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
362	#ADM-161578	273	\N	\N	1120000	0	0	1120000	transfer	completed	Ig qingyi8802 [ĐÃ THANH TOÁN]	2026-02-28 12:02:41.750089+00	Ig qingyi8802	0396504228	Số 51, ngõ 31, B6 Khu nhà ở Mai Dịch, đường Nguyễn Khả Trạc, Phường Phú Diễn, Thành phố Hà Nội, Việt Nam (phường Mai Dịch, Cầu Giấy cũ)	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
361	#ADM-057779	272	\N	\N	440000	0	0	440000	transfer	completed	Ig hồng hân  [ĐÃ THANH TOÁN]	2026-02-28 12:00:57.876869+00	Ig hồng hân 	0939553828	19 Đường Nguyễn Công Trứ , Phường Long Hưng , Thị Xã Tân Châu , An Giang	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
360	#ADM-982853	174	\N	\N	530000	0	0	530000	transfer	completed	Ig hoàng lan  [ĐÃ THANH TOÁN]	2026-02-28 11:59:43.000904+00	Ig hoàng lan 	0931539768	30 Phạm Văn Đồng Khu Cầu Xéo thị trấn long thành tỉnh đồng nai 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
359	#ADM-933262	271	\N	\N	250000	0	0	250000	transfer	completed	Ig wyn [ĐÃ THANH TOÁN]	2026-02-28 11:58:53.390238+00	Ig wyn	0364309690 	710 Nguyễn Thị Minh khai khu phố đông Thành phường Tân Đông Hiệp dĩ an Bình Dương	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
357	#ADM-358957	269	\N	\N	650000	0	0	650000	transfer	completed	Ig trần yến oanh  [ĐÃ THANH TOÁN]	2026-02-28 11:49:19.051412+00	Ig trần yến oanh 	0939 741 868	Vincom My Tho, số 1A đường Hùng Vương, p1, Mỹ Tho, Tiền Giang ( căn PG02-33) 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
356	#ADM-277493	268	\N	\N	500000	0	0	500000	transfer	completed	Ig bé ý [ĐÃ THANH TOÁN]	2026-02-28 11:47:57.587997+00	Ig bé ý	0902650169	72 lên thánh tôn q1 ạ\n\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
355	#ADM-206995	267	\N	\N	600000	0	0	600000	transfer	completed	Ig donfetch  [ĐÃ THANH TOÁN]	2026-02-28 11:46:47.105124+00	Ig donfetch 	+84357012453	Ibis Saigon Airport Hotel, Room 931\n2 Hồng Hà, Phường 2, Tân Bình, Thành phố Hồ Chí Minh 700000, Vietnam\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
345	#ADM-233613	262	\N	\N	250000	0	0	250000	transfer	completed	Ig phi nguyen [ĐÃ THANH TOÁN]	2026-02-27 13:50:33.698798+00	Ig phi nguyen	0934100243	124/7 mễ cốc p15 q8\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
358	#ADM-895745	270	\N	\N	600000	0	0	600000	transfer	completed	Ig tuyên du [ĐÃ THANH TOÁN]	2026-02-28 11:58:15.899966+00	Ig tuyên du	0845352059	9A Đường Thạnh Xuân 13, Thạnh Xuân, Quận 12, Thành phố Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
341	ORD-84741772196778	258	\N	\N	880000	0	20000	900000	banking	completed	\N	2026-02-27 12:52:57.815906+00	phạm ngọc trang	0986667499	Royal City (sảnh R5), 72 Nguyễn Trãi , Quận Thanh Xuân, Hà Nội	trangmits.99@gmail.com	\N	\N	unpaid	\N	1493	1A0711	\N	\N	\N
374	#ADM-568694	284	\N	\N	700000	0	0	700000	transfer	completed	Ig daanauuuu [ĐÃ THANH TOÁN]	2026-03-01 10:22:48.857267+00	Ig daanauuuu	0799079940	 36/36 Nguyễn Triệu Luật, Tân Tạo, Bình Tân - Sđt: 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
377	ORD-83711772361246	286	\N	\N	250000	0	500000	750000	done	cancelled	\N	2026-03-01 10:34:06.074361+00	Test	+1 854 098 09	15 Street, Los Angeles, California	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
378	ORD-98131772364179	5	\N	\N	25400	0	0	25400	done	cancelled	\N	2026-03-01 11:22:58.510603+00	ĐỞM QUANG MINH TRIẾT	0979911670	15 Street, LA, Cali	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
379	ORD-34871772380773	287	\N	\N	560000	0	0	560000	done	cancelled	\N	2026-03-01 15:59:32.527326+00	Yuyi Liu	3024202474	46 Albe dr  Ste 1 HW1211360, Delaware, Newark	yui89jp@icloud.com	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
396	ORD-18671772461662	302	\N	\N	530000	0	0	530000	banking	shipping	\N	2026-03-02 14:27:41.593158+00	Phạm Yến Vy	0796689118	132 Bến Vân Đồn Phường 6 Quận 4 TPHCM, Quận 4, Hồ Chí Minh	vyphamyen0311@gmail.com	\N	\N	unpaid	\N	1446	20406	\N	\N	\N
395	#ADM-867373	301	\N	\N	280000	0	0	280000	transfer	shipping	Ig vy  [ĐÃ THANH TOÁN]	2026-03-02 10:37:47.476252+00	Ig vy 	 0777055049	10/76/31 hoàng hoa thám p7 bình thạnh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
394	#ADM-730598	300	\N	\N	280000	0	0	280000	transfer	shipping	Ig shizukeoo [ĐÃ THANH TOÁN]	2026-03-02 10:35:30.730429+00	Ig shizukeoo	0787612039	 182 Ngô Huy Diễn, p. Hoà Xuân, q.Cẩm Lệ. Tp Đà Nẵng\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
393	#ADM-591536	299	\N	\N	280000	0	0	280000	transfer	shipping	Ig cammuy  [ĐÃ THANH TOÁN]	2026-03-02 10:33:11.655045+00	Ig cammuy 	0977790977	478/a hai bà trưng phường tân định quận 1	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
392	#ADM-405242	298	\N	\N	280000	0	0	280000	transfer	shipping	Ig iemboee [ĐÃ THANH TOÁN]	2026-03-02 10:30:05.343822+00	Ig iemboee	0946757175	153 đường số 4 , p16 gò vấp tphcm\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
391	#ADM-267548	297	\N	\N	560000	0	0	560000	transfer	shipping	ig Be han [ĐÃ THANH TOÁN]	2026-03-02 10:27:47.67072+00	ig Be han	0933888347 	203 cao văn lầu p2 q6 cũ\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
390	#ADM-167602	296	\N	\N	350000	0	0	350000	transfer	shipping	ig Phors [ĐÃ THANH TOÁN]	2026-03-02 10:26:07.723478+00	ig Phors	 0346086663	301 Phạm Ngũ Lão, Phường Phạm Ngũ Lão, Quận 1, Hồ Chí Minh, District 1, 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
389	#ADM-910204	295	\N	\N	500000	0	0	500000	transfer	shipping	Ig mai mai  [ĐÃ THANH TOÁN]	2026-03-02 10:21:50.316654+00	Ig mai mai 	0972270801	275 Lê Lợi, Ngô Quyền Hải Phòng 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
388	#ADM-724120	294	\N	\N	630000	0	0	630000	transfer	shipping	Ig celineharu  [ĐÃ THANH TOÁN]	2026-03-02 10:18:44.236989+00	Ig celineharu 	0335587187	ố 15 ngách 82/122 ngõ 166 kim mã, ba đình, hn	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
387	#ADM-662548	268	\N	\N	630000	0	0	630000	transfer	shipping	Ig bé ý  [ĐÃ THANH TOÁN]	2026-03-02 10:17:42.679463+00	Ig bé ý 	0902650169	72 lên thánh tôn q1 ạ	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
386	#ADM-511825	293	\N	\N	500000	0	0	500000	transfer	shipping	Ig kieuan_7  [ĐÃ THANH TOÁN]	2026-03-02 10:15:11.958781+00	Ig kieuan_7 	0329873525	Hestia Bakery & Coffee, Số 73, Lê Văn Thọ , Phường 8 , Quận Gò Vấp\n\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
385	#ADM-325806	292	\N	\N	930000	0	0	930000	transfer	shipping	Ig THU TRANG TRAN [ĐÃ THANH TOÁN]	2026-03-02 10:12:05.930182+00	Ig THU TRANG TRAN	0934331193 	Chung cư New City -  toà Hawai 1 - p2101 số 17 Mai Chí Thọ - p An Khánh - tp Thủ Đức - HCM 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
384	#ADM-147222	233	\N	\N	280000	0	0	280000	transfer	shipping	Ig t.mit.ti [ĐÃ THANH TOÁN]	2026-03-02 10:09:07.391264+00	Ig t.mit.ti	0344846390	49 tân thới nhất 1b p. Đông hưng thuận	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
383	#ADM-931965	291	\N	\N	650000	0	0	650000	transfer	shipping	Ig mô [ĐÃ THANH TOÁN]	2026-03-02 10:05:32.071212+00	Ig mô	0334232268	112 Yên Phụ nhỏ, phường Yên Phụ, quận Tây Hồ, TP Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
382	#ADM-889683	290	\N	\N	280000	0	0	280000	transfer	shipping	Ig iimvananh [ĐÃ THANH TOÁN]	2026-03-02 10:04:49.771229+00	Ig iimvananh	0938547603 	c2/26 phạm hùng xã bình hưng huyện bình chánh tphcm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
380	#ADM-044299	288	\N	\N	280000	0	0	280000	transfer	completed	Ig cao song nghi  [ĐÃ THANH TOÁN]	2026-03-02 09:34:04.403358+00	Ig cao song nghi 	0868795525	11 đường số 10, khu phố 4, hiệp bình chánh, thủ đức	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
376	#ADM-633045	118	\N	\N	350000	0	0	350000	transfer	completed	Ig nguyễn ngọc thiên kiều [ĐÃ THANH TOÁN]	2026-03-01 10:23:53.180038+00	Ig nguyễn ngọc thiên kiều	0988949801	96/3 đường s19, p8, gvap\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
375	#ADM-602890	285	\N	\N	280000	0	0	280000	transfer	completed	Ig huỳnh thư [ĐÃ THANH TOÁN]	2026-03-01 10:23:23.001472+00	Ig huỳnh thư	0373290600	107 Nguyễn Văn Linh, P.Tân thuận tây, quận 7  ecogen lock H	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
401	#ADM-790490	307	\N	\N	270000	0	0	270000	transfer	cancelled	vsv [ĐÃ THANH TOÁN]	2026-03-02 15:03:10.584053+00	vsv	cdv	27136bkjb	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
403	#ADM-296974	309	\N	\N	280000	0	0	280000	transfer	cancelled	test [ĐÃ THANH TOÁN]	2026-03-02 16:34:56.294585+00	TEst	0978919874	test	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
404	#ADM-874154	310	\N	\N	280000	0	20000	300000	cod	cancelled	ádf [ĐÃ THANH TOÁN]	2026-03-02 16:44:33.465507+00	test	ád	ádf	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
406	ORD-87131772470042	5	\N	\N	530000	0	20000	550000	banking	cancelled	\N	2026-03-02 16:47:21.650596+00	test	0979911670	15 Street, Quận Tân Phú, Hồ Chí Minh		\N	\N	unpaid	\N	1456	21509	\N	\N	\N
405	ORD-72401772469939	5	\N	\N	280000	0	20000	300000	banking	cancelled	\N	2026-03-02 16:45:38.794295+00	test	0979911670	15 test, Huyện Hoa Lư, Ninh Bình		\N	\N	unpaid	\N	1944	91437	\N	\N	\N
407	ORD-85031772498794	313	\N	\N	600000	0	20000	620000	banking	shipping	\N	2026-03-03 00:46:33.777725+00	Vy Truong	0938656758	48/8 nguyễn thanh tuyền, Quận Tân Bình, Hồ Chí Minh		\N	\N	unpaid	\N	1455	21402	\N	\N	\N
397	#ADM-584764	303	\N	\N	600000	0	0	600000	transfer	shipping	Ig an nhi [ĐÃ THANH TOÁN]	2026-03-02 14:59:44.870203+00	Ig an nhi	0824100205	10/4 Kỳ Đồng, phường 9, Quận 3. TP HCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
398	#ADM-622274	304	\N	\N	350000	0	0	350000	transfer	shipping	Ig emy  [ĐÃ THANH TOÁN]	2026-03-02 15:00:22.387328+00	Ig emy 	0779937230	Số 2 lô o cư xá vĩnh hội đường nguyễn hữu hào P9 Q4	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
399	#ADM-657623	305	\N	\N	530000	0	0	530000	transfer	shipping	Ig yennyenyn  [ĐÃ THANH TOÁN]	2026-03-02 15:00:57.754169+00	Ig yennyenyn 	0987659810	6 Nguyễn thiện thuật đồng xuân hoàn kiếm hà nội 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
400	#ADM-758598	306	\N	\N	880000	0	0	880000	transfer	shipping	Ig nm.le  [ĐÃ THANH TOÁN]	2026-03-02 15:02:38.73428+00	Ig nm.le 	0936135601	số nhà 11, ngách 1/1 đường An Dương Vương, Phú Thượng, Tây Hồ, Hà Nội 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
402	#ADM-464294	308	\N	\N	280000	0	0	280000	transfer	shipping	Ig chu thị thuỷ tiên [ĐÃ THANH TOÁN]	2026-03-02 15:14:24.383919+00	Ig chu thị thuỷ tiên	0393222393	17 mai chí thọ an khánh q2, newcity bali\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
381	#ADM-469711	289	\N	\N	530000	0	0	530000	transfer	completed	Ig thuan.ng87  [ĐÃ THANH TOÁN]	2026-03-02 09:41:09.833042+00	Ig thuan.ng87 	0938801987 	27 Nguyễn Hữu Thọ,tháp X2 Sunrise City North, Tân Hưng, q7	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
423	#ADM-876737	326	\N	\N	350000	0	0	350000	transfer	shipping	Ig nguyễn phương thảo [ĐÃ THANH TOÁN]	2026-03-03 13:17:56.857226+00	Ig nguyễn phương thảo	0962821709	BS8 The Berverly Solari, Vinhomes Grand Park, phường Long Bình, q9, Thủ Đức, HCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
422	#ADM-815035	197	\N	\N	440000	0	0	440000	transfer	shipping	Ig ghnopu.07 [ĐÃ THANH TOÁN]	2026-03-03 13:16:55.221046+00	Ig ghnopu.07	0964618034	Toà West A- Masteri west heights- Vinhome smart city- P. Tây Mỗ- quận Nam Từ Liêm- Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
421	#ADM-034363	325	\N	\N	600000	0	0	600000	transfer	shipping	Ig hong tham ngo [ĐÃ THANH TOÁN]	2026-03-03 10:17:14.482225+00	Ig hong tham ngo	0933333373	số 8 đường 47 phường 4 quận 4 ( sài gòn ) 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
420	#ADM-957722	324	\N	\N	280000	0	0	280000	transfer	shipping	Ig tam_dhin  [ĐÃ THANH TOÁN]	2026-03-03 10:15:57.814253+00	Ig tam_dhin 	0961068025	Số 20, Ngõ 394 Đường Mỹ Đình, Phường Mỹ Đình 1, Quận Nam Từ Liêm, Hà Nội\nSdt: 0961068025\nNgười nhận: Đinh Thị Tâm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
419	#ADM-924566	323	\N	\N	1420000	0	0	1420000	transfer	shipping	Ig jennie [ĐÃ THANH TOÁN]	2026-03-03 10:15:25.058178+00	Ig jennie	0905579126	29 Lê Huân, Thuận Hoà, Huế, Thành phố Huế, Vietnam	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
418	#ADM-820312	322	\N	\N	350000	0	0	350000	transfer	shipping	Ig nguyễn hương [ĐÃ THANH TOÁN]	2026-03-03 10:13:40.442318+00	Ig nguyễn hương	397 507 979	39 Thôn Nam Trang\nXã Đinh Trang Hòa, Huyện Di Linh, Lâm Đồng	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
417	#ADM-589103	321	\N	\N	280000	0	20000	300000	transfer	shipping	Ig my hoang huyen [ĐÃ THANH TOÁN]	2026-03-03 10:09:49.205522+00	Ig my hoang huyen	096-792-1229 	số 16-18 galaxy 1, khu đô thị ngân hà, hà đông, hà nội 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
415	#ADM-563501	319	\N	\N	280000	0	20000	300000	transfer	shipping	Ig kiwi1989 [ĐÃ THANH TOÁN]	2026-03-03 09:52:43.604543+00	Ig kiwi1989	0908709018	63-65A11, Khu phố 11, Nguyễn Văn Tiên, Phường Tân Phong, Tp. Biên Hoà, Tỉnh Đồng Nai	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
414	#ADM-530759	318	\N	\N	280000	0	20000	300000	transfer	shipping	Ig .ariel  [ĐÃ THANH TOÁN]	2026-03-03 09:52:10.864141+00	Ig .ariel 	0702601138	 33 nguyễn chí thanh,thạch thang,hải châu,tp đà nẵng	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
413	#ADM-487236	317	\N	\N	280000	0	0	280000	transfer	shipping	Ig hoàng thu trang  [ĐÃ THANH TOÁN]	2026-03-03 09:51:27.662222+00	Ig hoàng thu trang 	0941388237	Toà F, chung cư Feliz Home, 293 Hoàng Mai, phường Hoàng Văn Thụ, quận Hai Bà Trưng, Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
412	#ADM-458722	316	\N	\N	280000	0	0	280000	transfer	shipping	Ig huyền trang  [ĐÃ THANH TOÁN]	2026-03-03 09:50:58.826366+00	Ig huyền trang 	0399522524	45 Nguyễn Sơn, Ngọc Lâm, Long Biên	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
416	#ADM-554896	320	\N	\N	280000	0	0	280000	transfer	returned	Ig thanhthubeauty2310 [ĐÃ THANH TOÁN]	2026-03-03 10:09:15.003364+00	Ig thanhthubeauty2310	0963873132	Tháp 2 Toà Time tower 35 lê văn lương, nhân chính, thanh xuân hn\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
409	#ADM-841815	311	\N	\N	280000	0	0	280000	transfer	shipping	Ig tra my [ĐÃ THANH TOÁN]	2026-03-03 09:40:41.953968+00	Ig tra my	0868808283	202/10 tổ 1 kp1 tân chánh hiệp, q12, tphcm 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
408	#ADM-787392	315	\N	\N	350000	0	0	350000	transfer	shipping	Ig afterfive.offcial   [ĐÃ THANH TOÁN]	2026-03-03 09:39:47.496733+00	Ig afterfive.offcial  	09 0268 4984	100/82 thích quảng đức, p5, quận Phú nhuận\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
410	#ADM-145722	71	\N	\N	190000	0	0	190000	transfer	returned	Closeup.beng [ĐÃ THANH TOÁN]	2026-03-03 09:45:45.870787+00	Closeup.beng	789515460	15 nguyễn xuân khoát	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
437	#ADM-048194	335	\N	\N	680000	0	0	680000	transfer	shipping	Ig venus_saohom  [ĐÃ THANH TOÁN]	2026-03-04 12:40:48.290916+00	Ig venus_saohom 	0908088988	206 ng van huong,quan 2 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
436	#ADM-005414	176	\N	\N	280000	0	0	280000	transfer	shipping	Ig _princesshappiii [ĐÃ THANH TOÁN]	2026-03-04 12:40:05.533155+00	Ig _princesshappiii	0786968512	112/114/9 nguyễn thị minh khai quận ninh kiều thành phố cần thơ	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
434	#ADM-892392	334	\N	\N	950000	0	0	950000	transfer	shipping	Diễm My [ĐÃ THANH TOÁN]	2026-03-04 12:38:12.484537+00	 Diễm My	0377746617	126/1d Tôn Thất Đạm phường Bến Nghé quận 1	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
433	#ADM-844147	333	\N	\N	570000	0	0	570000	transfer	shipping	Ig tu tu  [ĐÃ THANH TOÁN]	2026-03-04 12:37:24.251109+00	Ig tu tu 	0972060321	96 hữu lê- hữu hoà- thanh trì- hà nội\nCẩm tú	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
432	#ADM-098541	238	\N	\N	640000	0	0	640000	transfer	shipping	Ig jenny  [ĐÃ THANH TOÁN]	2026-03-04 12:24:58.687134+00	Ig jenny 	092.379.3678	Mặt sau số 168 Trần thủ độ, Pháp vân , Hoàng liệt , Hoàng mai , Hà nội.\n( gõ tìm kiếm 🔍 sân bóng đại an ) 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
431	#ADM-058342	332	\N	\N	600000	0	0	600000	transfer	shipping	Ig KANYARAT  [ĐÃ THANH TOÁN]	2026-03-04 12:24:18.452349+00	Ig KANYARAT 	 0369166.222	( BN2705)\n163 Trương Thị Hoa, phường Tân Thới Hiệp, Quận 12, thành phố Hồ Chí Minh\n sdt : 0369166.222 ( Người Nhận BN2705)\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
430	#ADM-018816	71	\N	\N	440000	0	0	440000	transfer	shipping	Ig Mi  [ĐÃ THANH TOÁN]	2026-03-04 12:23:39.042208+00	Ig Mi 	789515460	13 bình thới p11 quận 11	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
429	#ADM-971775	331	\N	\N	280000	0	250000	530000	transfer	shipping	Ig ocethuw  [ĐÃ THANH TOÁN]	2026-03-04 12:22:51.949219+00	Ig ocethuw 	038 2043805	Chợ mỹ hiệp, xã mỹ hiệp, huyện cao lãnh, tỉnh đồng tháp\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
428	#ADM-916289	330	\N	\N	320000	0	0	320000	transfer	shipping	Ig kiko  [ĐÃ THANH TOÁN]	2026-03-04 12:21:56.377574+00	Ig kiko 	0359864888	Toà D 6th element Xuân La Tây hồ HN	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
427	#ADM-876780	329	\N	\N	320000	0	0	320000	transfer	shipping	Ig hương nguyễn [ĐÃ THANH TOÁN]	2026-03-04 12:21:16.8872+00	Ig hương nguyễn	0931602299	S10.03 vinhomes grand park, nguyễn xiễn, long bình, quận 9, tphcm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
426	#ADM-844912	328	\N	\N	320000	0	0	320000	transfer	shipping	Ig vũ thị luyến [ĐÃ THANH TOÁN]	2026-03-04 12:20:45.023761+00	Ig vũ thị luyến	0352692759	Số 8 kinh dương vương suối hoa tp bn cũ ạ g la phường kinh bắc 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
425	#ADM-762252	137	\N	\N	350000	0	0	350000	transfer	shipping	Ig meehgoxcutie_ [ĐÃ THANH TOÁN]	2026-03-04 12:19:22.677531+00	Ig meehgoxcutie_	0979768986	CityHouse - CD Apartment\n339/24B Đ. Lê Văn Sỹ, Phường 12, Quận 3, Hồ Chí Minh 700000, Vietnam	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
424	#ADM-720264	327	\N	\N	320000	0	0	320000	transfer	shipping	Ig hmtbhappi  [ĐÃ THANH TOÁN]	2026-03-04 12:18:40.360713+00	Ig hmtbhappi 	(+84) 859 828 504	Phòng 201, 57B Ngõ 98 Thái Hà, Phường Trung Liệt, Quận Đống Đa, Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
411	#ADM-432186	230	\N	\N	250000	0	0	250000	transfer	returned	Ig mai le [ĐÃ THANH TOÁN]	2026-03-03 09:50:32.297119+00	Ig mai le	0974274411	86 dường số 17 ấp tân tiến xã tân thông hội huyện củ chi	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
444	#ADM-377617	230	\N	\N	250000	0	0	250000	transfer	shipping	Ig mai le [ĐÃ THANH TOÁN]	2026-03-04 12:46:17.723644+00	Ig mai le	0974274411	86 dường số 17 ấp tân tiến xã tân thông hội huyện củ chi\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
443	#ADM-341576	340	\N	\N	250000	0	0	250000	transfer	shipping	Ig vvmman [ĐÃ THANH TOÁN]	2026-03-04 12:45:41.677948+00	Ig vvmman	0936311118	kiôt 220 chợ Phạm Thế Hiển ( đối diện hàng gạo ) tạp hoá Kim Phương\nphường chánh hưng tphcm ( p4 q8 cũ )\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
442	#ADM-286741	339	\N	\N	250000	0	0	250000	transfer	shipping	Ig thu hồng  [ĐÃ THANH TOÁN]	2026-03-04 12:44:46.845222+00	Ig thu hồng 	0981676578	Địa chỉ cũ Công ty THNN Tung Yang xã cẩm phúc huyện cẩm giàng tỉnh Hải Dương	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
441	#ADM-244070	338	\N	\N	280000	0	0	280000	transfer	shipping	Ig tracy  [ĐÃ THANH TOÁN]	2026-03-04 12:44:04.17164+00	Ig tracy 	0354053241	82/2C1 đường 494, phường tăng nhơn phú a, thủ đức\nBích Trâm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
440	#ADM-212327	55	\N	\N	1900000	0	0	1900000	transfer	shipping	Ig meen [ĐÃ THANH TOÁN]	2026-03-04 12:43:32.438044+00	Ig meen	0369166.222	163 Trương Thị Hoa, phường Tân Thới Hiệp, Quận 12, thành phố Hồ Chí Minh\n ( Người Nhận BN2705)\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
439	#ADM-138574	337	\N	\N	530000	0	0	530000	transfer	shipping	Ig dương thị kim ngân [ĐÃ THANH TOÁN]	2026-03-04 12:42:18.674867+00	Ig dương thị kim ngân	0706109051	33 nguyễn bỉnh khiêm, da kao, q1	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
438	#ADM-104163	336	\N	\N	1610000	0	0	1610000	transfer	shipping	Ig gg [ĐÃ THANH TOÁN]	2026-03-04 12:41:44.304209+00	Ig gg	 0779117207 	263/8 Điện Biên Phủ.  F15.  Quận Bình Thạnh.  \nPhone 0779117207 Bác Liễu	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
435	#ADM-935233	272	\N	\N	350000	0	0	350000	transfer	shipping	Ig hồng hân [ĐÃ THANH TOÁN]	2026-03-04 12:38:55.389038+00	Ig hồng hân	0939553828	19 Đường Nguyễn Công Trứ , Phường Long Hưng , Thị Xã Tân Châu , An Giang	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
445	#ADM-820742	341	\N	\N	500000	0	0	500000	transfer	shipping	Ig bich tuyn  [ĐÃ THANH TOÁN]	2026-03-04 14:33:40.955198+00	Ig bich tuyn 	0373912352	712/ tỉnh lộ 10\nBình trị đông \nBình tân\nHcm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
446	#ADM-859833	342	\N	\N	280000	0	0	280000	transfer	shipping	Ig dan thanh  [ĐÃ THANH TOÁN]	2026-03-04 14:34:19.980244+00	Ig dan thanh 	0383445592 	13, đường số 17, khu phố 2,phường bình chiểu , Tp Thủ Đức	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
447	#ADM-198994	343	\N	\N	320000	0	0	320000	transfer	shipping	Ig nguyen quynh traang  [ĐÃ THANH TOÁN]	2026-03-04 16:03:19.122537+00	Ig nguyen quynh traang 	0866716280	cuối ngõ 14 phố Lụa, Vạn Phúc, Hà Đông, HN\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
449	#ADM-468108	345	\N	\N	320000	0	0	320000	transfer	shipping	IG Ngân [ĐÃ THANH TOÁN]	2026-03-04 16:24:28.254095+00	IG Ngân	0356848574	14 đường số 6 khu phố 4 hiệp bình chánh thủ đức\nĐịa chỉ mới 14 đường số 6 kp56 hiệp bình	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
450	#ADM-680831	346	\N	\N	730000	0	0	730000	transfer	shipping	Ig hoàng nguyên trương  [ĐÃ THANH TOÁN]	2026-03-04 16:44:40.935916+00	Ig hoàng nguyên trương 	0973 820 020	Đường nhựa bên trái dưới chân cầu đối diện chợ Thạnh Hoà Sơn, ấp Cầu Vĩ, xã Thạnh Hoà Sơn, huyện Cầu Ngang, tỉnh Trà Vinh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
448	#ADM-863934	344	\N	\N	1350000	0	0	1350000	transfer	completed	pass đồ  [ĐÃ THANH TOÁN]	2026-03-04 16:14:24.111333+00	pass đồ 	0902173763	15 Nguyễn xuân Khoát	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
456	#ADM-713466	353	\N	\N	1000000	0	0	1000000	transfer	cancelled	Ig kristina [ĐÃ THANH TOÁN]	2026-03-05 11:38:33.564237+00	Ig kristina	0938059936	202/18 võ văn tần p5 q3	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
466	#ADM-792045	71	\N	\N	250000	0	0	250000	transfer	shipping	ig Đan thanh  [ĐÃ THANH TOÁN]	2026-03-05 13:03:12.603962+00	ig Đan thanh 	789515460	Q1	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
465	ORD-55001772711922	360	\N	\N	750000	0	20000	770000	banking	shipping	\N	2026-03-05 11:58:41.804201+00	bùi trân	0905790628	340/29 phan châu trinh, Quận Hải Châu, Đà Nẵng	buihoangbaotran785@gmail.com	\N	\N	unpaid	\N	1526	40102	\N	\N	\N
464	#ADM-937741	359	\N	\N	350000	0	0	350000	transfer	shipping	Ig ngoc phong  [ĐÃ THANH TOÁN]	2026-03-05 11:42:17.839409+00	Ig ngoc phong 	0772184758	Toà C , Central Garden, 328 Võ Văn Kiệt, phường Cô Giang, q1 \nTên: Ngọc Phong	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
463	#ADM-891795	71	\N	\N	630000	0	0	630000	transfer	shipping	Ig mi [ĐÃ THANH TOÁN]	2026-03-05 11:41:31.919453+00	Ig mi	789515460	13 bình thới p11 quận 11	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
462	#ADM-860615	358	\N	\N	280000	0	0	280000	transfer	shipping	Ig greenfast_ [ĐÃ THANH TOÁN]	2026-03-05 11:41:00.721306+00	Ig greenfast_	0792516411	39b ng văn linh q7\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
461	#ADM-838691	357	\N	\N	600000	0	0	600000	transfer	shipping	Ig lily  [ĐÃ THANH TOÁN]	2026-03-05 11:40:38.788611+00	Ig lily 	0929610964	46/33 bạch đằng f24 quận Bình Thạnh\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
460	#ADM-802603	356	\N	\N	280000	0	0	280000	transfer	shipping	Ig embotocvanghoe [ĐÃ THANH TOÁN]	2026-03-05 11:40:02.704571+00	Ig embotocvanghoe	0979200903	lô d2 chung cư mỹ đức phường 19 bình thạnh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
459	#ADM-778095	355	\N	\N	280000	0	0	280000	transfer	shipping	Ig kelly  [ĐÃ THANH TOÁN]	2026-03-05 11:39:38.200147+00	Ig kelly 	0977661777	La Rosa Apartment\n25 đường số 61, Thảo Điền, Q2 cũ, TP.HCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
458	#ADM-754894	354	\N	\N	280000	0	0	280000	transfer	shipping	Ig nguyễn thanh trúc  [ĐÃ THANH TOÁN]	2026-03-05 11:39:14.997716+00	Ig nguyễn thanh trúc 	0981798729	88 Ngọc Lâm - Long Biên - Hà Nội\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
457	#ADM-713536	353	\N	\N	1000000	0	0	1000000	transfer	shipping	Ig kristina [ĐÃ THANH TOÁN]	2026-03-05 11:38:33.647219+00	Ig kristina	0938059936	202/18 võ văn tần p5 q3	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
455	#ADM-666243	352	\N	\N	910000	0	0	910000	transfer	shipping	Ig kimchi_boo [ĐÃ THANH TOÁN]	2026-03-05 11:37:46.34338+00	Ig kimchi_boo	+84896749101 	185a liêu bình hương, tân thông hội, củ chi	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
454	#ADM-610173	351	\N	\N	750000	0	0	750000	transfer	shipping	Ig vani [ĐÃ THANH TOÁN]	2026-03-05 11:36:50.298081+00	Ig vani	(+84) 797026555	Zalo Ntram\nTPHCM Q TÂN BÌNH P1\n\n281/36, Lê Văn Sĩ	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
453	ORD-96881772699846	350	\N	\N	280000	0	20000	300000	banking	shipping	\N	2026-03-05 08:37:25.591193+00	My Nguyễn	0906502085	535/47 Thống Nhất, Quận Gò Vấp, Hồ Chí Minh	nngthmy@gmail.com	\N	\N	unpaid	\N	1461	21312	\N	\N	\N
452	ORD-32391772691942	349	\N	\N	250000	0	20000	270000	banking	shipping	\N	2026-03-05 06:25:42.232645+00	Cao Hồng Nhung	0855255253	4A Lê Thánh Tông, Quận Hoàn Kiếm, Hà Nội	chnhung0200@gmail.com	\N	\N	unpaid	\N	1489	1A0203	\N	\N	\N
451	ORD-63651772679267	348	\N	\N	600000	0	20000	620000	banking	shipping	\N	2026-03-05 02:54:26.750842+00	Lý Trần Bích Thuỷ	0967817921	197 Trần Nhật Duật, Thành phố Kon Tum, Kon Tum	lythuy16081999@gmail.com	\N	\N	unpaid	\N	1660	360101	\N	\N	\N
467	#ADM-775397	361	\N	\N	950000	0	0	950000	transfer	shipping	Ig lâm thuý an [ĐÃ THANH TOÁN]	2026-03-05 14:09:35.535823+00	Ig lâm thuý an	0366949072	57 Nguyễn Trọng Lội, Q. Tân Bình	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
470	ORD-46241772721122	1	\N	\N	600000	0	20000	620000	banking	cancelled	\N	2026-03-05 14:32:01.736555+00	Admin Brown	0900000000	15 NXK , Huyện Nậm Nhùn, Lai Châu	brownvn25@gmail.com	\N	\N	unpaid	\N	1984	70806	\N	\N	\N
469	ORD-68721772721087	1	\N	\N	250000	0	20000	270000	banking	cancelled	\N	2026-03-05 14:31:26.537116+00	Admin Brown	0900000000	15 NXK, Huyện Hàm Thuận Nam, Bình Thuận	brownvn25@gmail.com	\N	\N	unpaid	\N	1776	470509	\N	\N	\N
468	ORD-14521772721060	1	\N	\N	980000	0	20000	1000000	banking	cancelled	\N	2026-03-05 14:30:59.89215+00	Admin Brown	0900000000	15 NXK, Quận Tân Bình, Hồ Chí Minh	brownvn25@gmail.com	\N	\N	unpaid	\N	1455	21406	\N	\N	\N
471	#ADM-235104	362	\N	\N	600000	0	0	600000	transfer	shipping	Ig vivs [ĐÃ THANH TOÁN]	2026-03-05 15:40:35.276968+00	Ig vivs	0797131533	860/67 xo viet nghe tinh phuong 25  quan binh thanh thanh pho ho chi minh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
472	#ADM-495711	363	\N	\N	300000	0	-50000	250000	transfer	shipping	Ig meskmuse_ [ĐÃ THANH TOÁN]	2026-03-05 16:18:15.846254+00	Ig meskmuse_	0908799311  	252/11 lý chính thắng p9 q3 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
41	#ADM-114962	24	\N	\N	350000	0	0	350000	transfer	completed	Ig pông pính	2026-02-01 13:38:35.066308+00	Phạm Yến	0907673591	B10.09, chung cư The Golden Star, 58B Nguyễn Thị Thập, phường Bình Thuận, quận 7, tp. HCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
94	#ADM-659081	57	\N	\N	500000	0	0	500000	transfer	completed	Ig baconmeocon	2026-02-03 16:20:59.195182+00	Ig baconmeocon	0938080124	16 đường số 4, kdc Nam Hùng vương, p an lạc, kp3 quận bình tân, Phường An Lạc, Quận Bình Tân, TP Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
209	#ADM-500720	157	\N	\N	250000	0	0	250000	transfer	completed	ig Vi Nguyễn [ĐÃ THANH TOÁN]	2026-02-09 05:05:00.86792+00	ig Vi Nguyễn	0969999346 	Chung Cư CT6 Vĩnh Điềm Trung Nha Trang, Tòa Nhà CT6, Đường B3,\nPhường Tây Nha Trang, Khánh Hòa	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
279	#ADM-994882	204	\N	\N	250000	0	0	250000	transfer	completed	Ig cry baby [ĐÃ THANH TOÁN]	2026-02-25 04:49:54.98178+00	Ig cry baby	0773105709	Địa chỉ: Chung cư Diamond Riverside, Block D, phòng 26.01, số 1646A, Võ Văn Kiệt, phường Phú Định, quận 8	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
277	#ADM-961183	202	\N	\N	400000	0	0	400000	transfer	completed	Ig donfetch  [ĐÃ THANH TOÁN]	2026-02-24 14:22:41.295115+00	Ig donfetch 	+84 779 805443	\nAddress : Indochine Ben Than Hotel and Apartments , 30 Lưu Văn Lang, Phường Bến Thành, Quận 1, Thành phố Hồ Chí Minh 700000, Vietnam\n\nNo.hp: +84 779 805443\n(can zalo)\n\nNotes: Xin vui lòng gửi ở lễ tân khách sạn	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
480	#ADM-702515	371	\N	\N	300000	0	0	300000	transfer	shipping	Ig thuy linh truong  [ĐÃ THANH TOÁN]	2026-03-06 14:18:22.616987+00	Ig thuy linh truong 	0949866289	số nhà 39 ngách 53/22 ngõ 68 cầu giấy\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
479	#ADM-659163	71	\N	\N	700000	0	0	700000	transfer	shipping	Ig phan mỹ diệu [ĐÃ THANH TOÁN]	2026-03-06 14:17:39.298224+00	Ig phan mỹ diệu	789515460	205/15/9 trần văn đang phường 11 quận 3 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
478	#ADM-579299	370	\N	\N	300000	0	0	300000	transfer	shipping	Ig thiên thương [ĐÃ THANH TOÁN]	2026-03-06 14:16:19.400956+00	Ig thiên thương	0919288118	Toà B chung cư n04 Hoàng Đạo Thuý quận cầu giấy Hn \t\t	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
477	ORD-32301772786388	369	\N	\N	350000	0	20000	370000	banking	shipping	\N	2026-03-06 08:39:47.877173+00	Lâm Thanh Kiều Tiên	0346009498	208 Thống Nhất Mới, Thành phố Vũng Tàu, Bà Rịa - Vũng Tàu	kieutien98er@gmail.com	\N	\N	unpaid	\N	1544	520110	\N	\N	\N
476	#ADM-743996	368	\N	\N	300000	0	0	300000	transfer	shipping	Ig anhh.tn [ĐÃ THANH TOÁN]	2026-03-06 04:19:04.107703+00	Ig anhh.tn	0983690744	Số 6 ngõ 54/1 thượng thuỵ đức thượng hoài đức hà nội 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
474	#ADM-605062	366	\N	\N	650000	0	0	650000	transfer	shipping	Ig uyên nhật [ĐÃ THANH TOÁN]	2026-03-06 04:16:45.181094+00	Ig uyên nhật	0822101634	Chợ bình triệu, tiệm vàng ngon nhân trong chợ, phường hiệp bình chánh, thủ đức\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
475	#ADM-652314	367	\N	\N	320000	0	0	320000	transfer	shipping	Ig mya_nh54  [ĐÃ THANH TOÁN]	2026-03-06 04:17:32.421079+00	Ig mya_nh54 	0354395608 	30 tùng thiện vương phường Phú định Q8 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
473	ORD-24731772765829	365	\N	\N	320000	0	20000	340000	banking	shipping	\N	2026-03-06 02:57:09.150124+00	Nguyễn nga	0862166028	Số 2 hẻm 2 ngách 53 ngõ 165 cầu giấy, Quận Cầu Giấy, Hà Nội	nga433080@gmail.com	\N	\N	unpaid	\N	1485	1A0608	\N	\N	\N
482	#ADM-674464	373	\N	\N	650000	0	0	650000	transfer	cancelled	Ig luong ngoc diep  [ĐÃ THANH TOÁN]	2026-03-07 06:24:34.592079+00	Ig luong ngoc diep 	0842509333 	5b/46 nhân hoà, thanh xuân, hà nội 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
487	#ADM-679332	376	\N	\N	300000	0	0	300000	transfer	cancelled	Ig th.d82 [ĐÃ THANH TOÁN]	2026-03-08 07:41:19.463851+00	Ig th.d82	0982080802	Park 8, Times City, phường Vĩnh Tuy, thành phố Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
481	#ADM-647614	372	\N	\N	320000	0	0	320000	transfer	shipping	Ig fenndinhh [ĐÃ THANH TOÁN]	2026-03-07 06:24:07.728015+00	Ig fenndinhh	0935415274 	97 Ngô Quyền, Thành phố Quảng Ngãi	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
483	#ADM-719507	373	\N	\N	650000	0	-50000	600000	transfer	shipping	Ig luong ngoc diep  [ĐÃ THANH TOÁN]	2026-03-07 06:25:19.631986+00	Ig luong ngoc diep 	0842509333 	5b/46 nhân hoà, thanh xuân, hà nội 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
484	#ADM-782237	292	\N	\N	300000	0	0	300000	transfer	shipping	Ig thu trang tran  [ĐÃ THANH TOÁN]	2026-03-07 06:26:22.379237+00	Ig thu trang tran 	0934331193 	Chung cư New City -  toà Hawai 1 - p2101 số 17 Mai Chí Thọ - p An Khánh - tp Thủ Đức - HCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
485	ORD-38821772864902	374	\N	\N	600000	0	20000	620000	banking	shipping	\N	2026-03-07 06:28:21.686756+00	Nguyễn Lan Anh	0981589630	48 Trần Quốc Toản, Quận Hoàn Kiếm, Hà Nội	lananhng185@gmail.com	\N	\N	unpaid	\N	1489	1A0217	\N	\N	\N
486	#ADM-519164	375	\N	\N	300000	0	0	300000	transfer	shipping	Ig pass đồ - tly [ĐÃ THANH TOÁN]	2026-03-08 07:38:39.291922+00	Ig pass đồ - tly	0392378870	373/1/4 lý thường kiệt, p9 quận Tân Bình tpHCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
488	#ADM-679342	377	\N	\N	300000	0	0	300000	transfer	shipping	Ig th.d82 [ĐÃ THANH TOÁN]	2026-03-08 07:41:19.537316+00	Ig th.d82	0982080802	Park 8, Times City, phường Vĩnh Tuy, thành phố Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
490	#ADM-791720	379	\N	\N	350000	0	0	350000	transfer	shipping	Ig trần phú quý  Quý  [ĐÃ THANH TOÁN]	2026-03-08 07:43:11.845351+00	Ig trần phú quý  Quý 	0968288637	652/55 cộng hoà	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
489	#ADM-752591	378	\N	\N	350000	0	0	350000	transfer	shipping	Ig y băng ng  [ĐÃ THANH TOÁN]	2026-03-08 07:42:32.779443+00	Ig y băng ng 	0965304907	Đường số 11, hẻm 11C, phước tân 2, xã Tân Hưng, tp Bà rịa	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
491	#ADM-292262	312	\N	\N	700000	0	-70000	630000	transfer	shipping	Ig wolfdababy. [ĐÃ THANH TOÁN]	2026-03-08 08:08:12.417786+00	Ig wolfdababy.	0911862338	3 Nguyễn Viết Xuân, Khương Mai, Thanh Xuân, Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
500	#ADM-599768	386	\N	\N	350000	0	-70000	280000	transfer	shipping	Ig nguyễn huỳnh lâm ngọc [ĐÃ THANH TOÁN]	2026-03-08 08:29:59.860084+00	Ig nguyễn huỳnh lâm ngọc	0981 771 340	320/16a Nguyễn Văn Linh, phường Bình Thuận  quận 7, hcm\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
499	#ADM-040093	385	\N	\N	350000	0	-70000	280000	transfer	shipping	Ig jehegwjsbv  [ĐÃ THANH TOÁN]	2026-03-08 08:20:40.189651+00	Ig jehegwjsbv 	087 633 7187	Etipol Express \nVận tải Campuchia \nThông Tin Gửi Hàng \n* ETV So Ct (EV23837)\n· Địa Chỉ: 315/18/6 Nhuyễn Thị Tú, Phường Bình Hưng Hòa B, Quận Bình Tân, Hồ Chí Minh 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
498	#ADM-983760	384	\N	\N	650000	0	-50000	600000	transfer	shipping	Ig thhuyanh [ĐÃ THANH TOÁN]	2026-03-08 08:19:43.895727+00	Ig thhuyanh	0916549550	35/12 Ấp 4 Hoà An Phụng Hiệp Hậu Giang	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
497	#ADM-942622	366	\N	\N	700000	0	-70000	630000	transfer	shipping	Ig uyên nhật  [ĐÃ THANH TOÁN]	2026-03-08 08:19:02.71864+00	Ig uyên nhật 	0822101634	Chợ bình triệu, tiệm vàng ngon nhân trong chợ, phường hiệp bình chánh, thủ đức	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
496	#ADM-893705	383	\N	\N	650000	0	-120000	530000	transfer	shipping	Ig sarahlnaa [ĐÃ THANH TOÁN]	2026-03-08 08:18:13.830734+00	Ig sarahlnaa	0379.907.234	42a Nguyễn du - hồ xá - Vĩnh linh - quảng trị	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
495	#ADM-460090	326	\N	\N	1000000	0	-190000	810000	transfer	shipping	Ig nguyễn phương thảo [ĐÃ THANH TOÁN]	2026-03-08 08:11:00.196673+00	Ig nguyễn phương thảo	0962821709	BS8 The Berverly Solari, Vinhomes Grand Park, phường Long Bình, q9, Thủ Đức, HCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
494	#ADM-397493	382	\N	\N	350000	0	-70000	280000	transfer	shipping	Ig chloe nguyễn  [ĐÃ THANH TOÁN]	2026-03-08 08:09:57.589458+00	Ig chloe nguyễn 	0963091319	Bali 1 cc new city thủ thiên an khánh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
493	#ADM-368042	381	\N	\N	350000	0	-70000	280000	transfer	shipping	Ig caleb.gurl  [ĐÃ THANH TOÁN]	2026-03-08 08:09:28.13558+00	Ig caleb.gurl 	0383456677	chung cư Galaxy 9, số 9 Nguyễn Khoái, quận 4\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
492	#ADM-337217	380	\N	\N	700000	0	-70000	630000	transfer	shipping	Ig van pham [ĐÃ THANH TOÁN]	2026-03-08 08:08:57.304281+00	Ig van pham	 0379733739	Chung cư EcoGreen - block G, 39B Nguyễn Văn Linh, phường Tân Thuận Tây, quận 7	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
516	#ADM-398074	335	\N	\N	350000	0	0	350000	transfer	cancelled	Ig venus_saohom [ĐÃ THANH TOÁN]	2026-03-09 11:06:38.220227+00	Ig venus_saohom	0908088988	9/11 đường số 64 quận 2 phường Thảo Điền	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
504	#ADM-177097	390	\N	\N	350000	0	0	350000	transfer	cancelled	Ig lac ngoc nhi [ĐÃ THANH TOÁN]	2026-03-08 15:52:57.223296+00	Ig lac ngoc nhi	0796117375	12/17 nguyễn lâm p6 q10	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
521	#ADM-530752	402	\N	\N	650000	0	-120000	530000	transfer	shipping	Ig iloveapricot [ĐÃ THANH TOÁN]	2026-03-09 11:58:50.850662+00	Ig iloveapricot	0836588889	411/32 Nguyễn đình chiểu, p5, q3	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
518	#ADM-065032	390	\N	\N	350000	0	0	350000	transfer	shipping	Ig lac ngoc nhi [ĐÃ THANH TOÁN]	2026-03-09 11:34:25.198381+00	Ig lac ngoc nhi	0796117375	Địa chỉ giao hàng\n12/17 nguyễn lâm p6 q10	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
517	#ADM-843324	398	\N	\N	400000	0	0	400000	transfer	shipping	ig nguyễn thị mai linh [ĐÃ THANH TOÁN]	2026-03-09 11:14:03.478724+00	ig nguyễn thị mai linh	0367160843	Địa chỉ giao hàng\nVăn Môn-Yên Phong-Bắc Ninh\n\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
515	#ADM-277882	399	\N	\N	300000	0	0	300000	transfer	shipping	ig Mai jun  [ĐÃ THANH TOÁN]	2026-03-09 11:04:37.984962+00	ig Mai jun 	 0935146101	Khu phố phước thịnh thị trấn Phú thứ tây hòa phú yên\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
514	#ADM-233496	398	\N	\N	300000	0	0	300000	transfer	shipping	Ig nguyễn thị mai linh  [ĐÃ THANH TOÁN]	2026-03-09 11:03:53.602885+00	Ig nguyễn thị mai linh 	0367160843	Văn Môn-Yên Phong-Bắc Ninh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
513	#ADM-201943	397	\N	\N	350000	0	-70000	280000	transfer	shipping	Tiktok bông nè  [ĐÃ THANH TOÁN]	2026-03-09 11:03:22.12006+00	Tiktok bông nè 	0902696551	149/53/15 trịnh đình trọng tân phú	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
512	#ADM-161434	326	\N	\N	350000	0	-70000	280000	transfer	shipping	Ig nguyễn phương thảo [ĐÃ THANH TOÁN]	2026-03-09 11:02:41.596919+00	Ig nguyễn phương thảo	0962821709	BS8 The Berverly Solari, Vinhomes Grand Park, phường Long Bình, q9, Thủ Đức, HCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
511	#ADM-126801	396	\N	\N	300000	0	0	300000	transfer	shipping	Ig ngoctho_0201  [ĐÃ THANH TOÁN]	2026-03-09 11:02:06.896682+00	Ig ngoctho_0201 	0987691425	58 Chu Văn An , phường Tân Thành, TPHCM\n\nQuỳnh Như	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
510	#ADM-090095	395	\N	\N	300000	0	0	300000	transfer	shipping	Ig ur honey  [ĐÃ THANH TOÁN]	2026-03-09 11:01:30.190483+00	Ig ur honey 	0908300521 	26 Lý Tự Trọng, Q1\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
509	#ADM-060389	137	\N	\N	750000	0	0	750000	transfer	shipping	Ig meehgoxcu [ĐÃ THANH TOÁN]	2026-03-09 11:01:00.553713+00	Ig meehgoxcu	0979768986	CityHouse - CD Apartment\n339/24B Đ. Lê Văn Sỹ, Phường 12, Quận 3, Hồ Chí Minh 700000, Vietnam (tel. 0979768986)\n(* ‘giao cho lễ tân báo hàng của Mimi. ’*không cần gọi điện, vui lòng để lại đồ tại quầy lễ tân)	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
508	#ADM-001563	394	\N	\N	1000000	0	0	1000000	transfer	shipping	Ig minhhtthanh [ĐÃ THANH TOÁN]	2026-03-09 11:00:01.678115+00	Ig minhhtthanh	0568685030	111 dương bá trạc phường 1 quận 8 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
507	#ADM-857952	393	\N	\N	300000	0	0	300000	transfer	shipping	Ig gbee_ [ĐÃ THANH TOÁN]	2026-03-09 10:57:38.078109+00	Ig gbee_	0367826546 	30/3 pasteur p4 Đà Lạt	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
506	#ADM-857814	392	\N	\N	300000	0	0	300000	transfer	shipping	Ig gbee_ [ĐÃ THANH TOÁN]	2026-03-09 10:57:37.944914+00	Ig gbee_	0367826546 	30/3 pasteur p4 Đà Lạt	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
505	ORD-47261773044829	391	\N	\N	750000	0	20000	770000	banking	shipping	\N	2026-03-09 08:27:09.407728+00	Uyển Nhi	0905045576	55 đường số 11, Quận 7, Hồ Chí Minh	uyennhi081106@gmail.com	\N	\N	unpaid	\N	1449	20705	\N	\N	\N
503	#ADM-976275	389	\N	\N	700000	0	-70000	630000	transfer	shipping	Ig kay  [ĐÃ THANH TOÁN]	2026-03-08 15:49:36.370833+00	Ig kay 	0907807661	21 Ký Hoà P11 Q5	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
502	#ADM-814583	388	\N	\N	300000	0	0	300000	transfer	shipping	Ig ulsuove_  [ĐÃ THANH TOÁN]	2026-03-08 15:46:54.678682+00	Ig ulsuove_ 	0364789984	212/3b phạm văn chiêu phường 9 gò vấp\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
501	#ADM-605326	387	\N	\N	320000	0	0	320000	transfer	shipping	Ig congchuaoriii [ĐÃ THANH TOÁN]	2026-03-08 15:43:25.459+00	Ig congchuaoriii	789515469	30/95 Đỗ Nhuận, Sơn Kì, Tân Phú	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
551	#ADM-980216	420	\N	\N	650000	0	0	650000	transfer	shipping	Ig phuong dung chu [ĐÃ THANH TOÁN]	2026-03-11 13:49:40.883041+00	Ig phuong dung chu	0368823044 	· Địa chỉ: Move Vietnam, 27E Võ Trường Toản, Thảo Điền, quận 2 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
520	#ADM-444878	401	\N	\N	650000	0	0	650000	transfer	returned	Ig hồng trâm  [ĐÃ THANH TOÁN]	2026-03-09 11:57:24.975725+00	Ig hồng trâm 	 (+84) 787 726 763	15/3, Trần Hưng Đạo\nPhường 6, Thành Phố Mỹ Tho, Tiền Giang	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
519	#ADM-477201	400	\N	\N	350000	0	0	350000	transfer	shipping	Ig hoàng nguyên trương [ĐÃ THANH TOÁN]	2026-03-09 11:41:17.314998+00	Ig hoàng nguyên trương	0973 820 020 	Đường nhựa bên trái dưới chân cầu đối diện chợ Thạnh Hoà Sơn, ấp Cầu Vĩ, xã Thạnh Hoà Sơn, huyện Cầu Ngang, tỉnh Trà Vinh\n\nGiờ là ấp Cầu Vĩ, xã Ngũ Lạc, tỉnh Vĩnh Long	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
523	#ADM-798114	326	\N	\N	350000	0	-70000	280000	transfer	shipping	Ig nguyễn phương thảo [ĐÃ THANH TOÁN]	2026-03-09 13:59:58.280747+00	Ig nguyễn phương thảo	0962821709	BS8 The Berverly Solari, Vinhomes Grand Park, phường Long Bình, q9, Thủ Đức, HCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
522	#ADM-572179	403	\N	\N	300000	0	0	300000	transfer	shipping	Ig kimnhi_2910 [ĐÃ THANH TOÁN]	2026-03-09 13:56:12.290845+00	Ig kimnhi_2910	0971351900	299/16/4L Lý Thường Kiệt, phường Phú Thọ, hcm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
524	#ADM-461689	71	\N	\N	1500000	0	0	1500000	transfer	shipping	Ig virgobaby [ĐÃ THANH TOÁN]	2026-03-09 16:07:41.879272+00	Ig virgobaby	789515460	Apec wander hotel	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
525	#ADM-510682	404	\N	\N	350000	0	0	350000	transfer	shipping	Ig yến  [ĐÃ THANH TOÁN]	2026-03-09 16:08:30.776563+00	Ig yến 	0867928063	139 nguyên suý, tân phú	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
526	ORD-12561773144141	405	\N	\N	650000	0	20000	670000	banking	shipping	\N	2026-03-10 12:02:20.764861+00	đỗ ly	0948370303	106 đường số 51 , Quận Gò Vấp, Hồ Chí Minh	camlydoabc@gmail.com	\N	\N	unpaid	\N	1461	21310	\N	\N	\N
527	#ADM-029028	406	\N	\N	620000	0	0	620000	transfer	shipping	Ig elma_hus  [ĐÃ THANH TOÁN]	2026-03-10 14:30:29.131038+00	Ig elma_hus 	Thuỵ Sỹ	Elma Husic \nChemin de Chantemerle 21 \n1350 Orbe \nSuisse \n078/791.24.97	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
528	#ADM-090375	407	\N	\N	650000	0	0	650000	transfer	shipping	Ig sắn  [ĐÃ THANH TOÁN]	2026-03-10 14:31:30.4779+00	Ig sắn 	0919386166	Toà c6, chung cư d'capital, yên hoà HN	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
529	#ADM-119897	55	\N	\N	600000	0	0	600000	transfer	shipping	Ig meen [ĐÃ THANH TOÁN]	2026-03-10 14:32:00.047139+00	Ig meen	0369166.222	163 Trương Thị Hoa, phường Tân Thới Hiệp, Quận 12, thành phố Hồ Chí Minh\n sdt : 0369166.222 ( Người Nhận BN2705)	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
531	#ADM-188234	71	\N	\N	320000	0	0	320000	transfer	shipping	Ig gigitr.forwork [ĐÃ THANH TOÁN]	2026-03-10 14:33:08.352249+00	Ig gigitr.forwork	789515460	Vườn Lài	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
530	#ADM-155413	408	\N	\N	350000	0	0	350000	transfer	shipping	Ig nguyễn nguyệt [ĐÃ THANH TOÁN]	2026-03-10 14:32:35.517537+00	Ig nguyễn nguyệt	0989366708	Đc:74/14, Phan Đăng Lưu, Phường 5, Quận Phú Nhuận, TP. Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
532	#ADM-240310	409	\N	\N	750000	0	0	750000	transfer	shipping	Ig lê salan  [ĐÃ THANH TOÁN]	2026-03-10 14:34:00.484126+00	Ig lê salan 	0784250794	90 nguyễn hữu cảnh p22 quận bình thạnh . \nSunwah Pearl Golden House 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
533	#ADM-284495	378	\N	\N	650000	0	0	650000	transfer	shipping	Ig y băng ng [ĐÃ THANH TOÁN]	2026-03-10 14:51:24.607667+00	Ig y băng ng	0965304907	Đường số 11, hẻm 11C, phước tân 2, xã Tân Hưng, tp Bà rịa	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
534	ORD-61051773207559	410	\N	\N	1750000	0	20000	1770000	banking	shipping	\N	2026-03-11 05:39:18.614417+00	Hùng anh	0888324293	27 Võ Trường Toản, Thành phố Vũng Tàu, Bà Rịa - Vũng Tàu	tothuhoai62@gmail.com	\N	SPXVN062631105683	unpaid	\N	1544	520111	\N	\N	\N
537	ORD-20101773227135	5	\N	\N	350000	0	20000	370000	banking	returned	\N	2026-03-11 11:05:35.474918+00	Test Email	0979911670	15 NXK, Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	1456	21509	\N	\N	\N
535	ORD-67161773222534	411	\N	\N	350000	0	20000	370000	banking	shipping	\N	2026-03-11 09:48:53.97281+00	Trần Thu Uyên	0344671610	Chung cư Sunrise City Central - Toà W2 - 25 Nguyễn Hữu Thọ, Quận 7, Hồ Chí Minh	thu.uyenn1610@gmail.com	\N	SPXVN060142951153	unpaid	\N	1449	20704	\N	\N	\N
538	ORD-63221773227575	5	\N	\N	350000	0	20000	370000	banking	returned	\N	2026-03-11 11:12:54.750937+00	Test Email	0979911670	15 NXK, Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	SPXVN063507884173	unpaid	\N	1456	21509	\N	\N	\N
536	ORD-46351773225458	412	\N	\N	300000	0	20000	320000	banking	shipping	\N	2026-03-11 10:37:37.7299+00	Dịu	0898075217	45- An Hạ 3- An Thượng- Hoài Đức- HN, Huyện Hoài Đức, Hà Nội	diun2506@gmail.com	\N	SPXVN068230978533	unpaid	\N	1805	1B2303	\N	\N	\N
539	ORD-54941773227787	5	\N	\N	350000	0	20000	370000	banking	returned	\N	2026-03-11 11:16:26.628962+00	Test Email	0979911670	15 NXK, Huyện Quản Bạ, Hà Giang	nguyenhaohung4@gmail.com	\N	SPXVN063507884173	unpaid	\N	1999	50508	\N	\N	\N
541	ORD-87551773229203	413	\N	\N	300000	0	20000	320000	banking	shipping	\N	2026-03-11 11:40:03.464122+00	Đàm Thị Ngọc Anh	0908284907	175 Võ Văn Ngân, phường Linh Chiểu ,tp Thủ Đức, Hồ Chí Minh, Thành Phố Thủ Đức, Hồ Chí Minh	dtnanh20092007@gmail.com	\N	SPXVN062083816163	unpaid	\N	3695	90742	\N	\N	\N
540	ORD-10271773228361	5	\N	\N	700000	0	20000	720000	banking	returned	\N	2026-03-11 11:26:00.923061+00	Test Email	0979911670	15 NXK, Huyện Mường Ảng, Điện Biên	domquangminhtriet17@gmail.com	\N	SPXVN063507884173	unpaid	\N	2170	620908	\N	\N	\N
550	#ADM-889527	419	\N	\N	700000	0	0	700000	transfer	shipping	Ig N [ĐÃ THANH TOÁN]	2026-03-11 13:48:09.667836+00	Ig N	0374671733	Căn hộ citizent - đường 9A - khu trung sơn - bình hưng - Bình Chánh 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
548	#ADM-678100	418	\N	\N	350000	0	0	350000	transfer	shipping	Ig thục đoan woong  [ĐÃ THANH TOÁN]	2026-03-11 13:44:38.198809+00	Ig thục đoan woong 	0784689885 	442/10 Lê Quang ĐỊnh, quận Bình Thạnh\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
547	#ADM-628265	194	\N	\N	300000	0	0	300000	transfer	shipping	Ig thu diễm  [ĐÃ THANH TOÁN]	2026-03-11 13:43:48.387284+00	Ig thu diễm 	0934511930	17-bt7 khu đô thị Văn Phú, Phú La, Hà Đông, HN 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
546	#ADM-599039	417	\N	\N	650000	0	0	650000	transfer	shipping	Ig mai hân hân  [ĐÃ THANH TOÁN]	2026-03-11 13:43:19.209637+00	Ig mai hân hân 	0934155514	331 bến vân đồn q4	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
545	#ADM-561616	416	\N	\N	350000	0	0	350000	transfer	shipping	Ig evey  [ĐÃ THANH TOÁN]	2026-03-11 13:42:41.814266+00	Ig evey 	0963189389	350, đ. Hoàng Liên, p. Lào Cai (p. Kim tân, tp. Lào Cai cũ), tỉnh Lào Cai	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
544	#ADM-514014	415	\N	\N	350000	0	0	350000	transfer	shipping	Ig tieu han tran  [ĐÃ THANH TOÁN]	2026-03-11 13:41:54.142816+00	Ig tieu han tran 	0839946946	203 mai thị hồng hạnh phường vĩnh lợi thành phố rạch giá kiên giang	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
543	#ADM-486921	351	\N	\N	350000	0	0	350000	transfer	shipping	Ig vani  [ĐÃ THANH TOÁN]	2026-03-11 13:41:27.06256+00	Ig vani 	(+84) 797026555	TPHCM Q TÂN BÌNH P1\n\n281/36, Lê Văn Sĩ	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
542	#ADM-447221	414	\N	\N	350000	0	0	350000	transfer	shipping	Ig đang nhập [ĐÃ THANH TOÁN]	2026-03-11 13:40:47.363234+00	Ig đang nhập	0947204452	144/1/3 bình lợi, p13, bình thạnh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
1237	#ADM-425595	957	\N	\N	650000	0	0	650000	cod	shipping	Ig lan dang	2026-04-14 06:17:05.687326+00	Ig lan dang	0336609654	137 kỳ đồng , phường thanh khê đông quận thanh khê tp đà nẵng	\N	\N	\N	unpaid	\N	\N	\N	2026-04-14 15:32:14.742+00	\N	\N
553	#ADM-084732	248	\N	\N	970000	0	0	970000	transfer	shipping	Ig bao t truong [ĐÃ THANH TOÁN]	2026-03-11 13:51:24.96666+00	Ig bao t truong	0367055470	B161C khu phố 3, phường đông hưng thuận,quận 12, hcm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
552	#ADM-027843	421	\N	\N	650000	0	0	650000	transfer	shipping	Ig jie71104 [ĐÃ THANH TOÁN]	2026-03-11 13:50:27.962981+00	Ig jie71104	0931393787 	07 Thai Dương-Phường Thuận An-Tp Huế-sđt 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
549	#ADM-775221	326	\N	\N	1500000	0	0	1500000	transfer	shipping	Ig nguyễn phương thảo [ĐÃ THANH TOÁN]	2026-03-11 13:46:15.3615+00	Ig nguyễn phương thảo	0962821709	BS8 The Berverly Solari, Vinhomes Grand Park, phường Long Bình, q9, Thủ Đức, HCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
555	#ADM-242259	423	\N	\N	1400000	0	0	1400000	transfer	shipping	Ig milynnguyen  [ĐÃ THANH TOÁN]	2026-03-11 16:40:42.399613+00	Ig milynnguyen 	0899960366	407 nguyễn văn khối,p8,gv hcm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
554	#ADM-174991	422	\N	\N	300000	0	0	300000	transfer	shipping	Ig tamnhu nguyen3 [ĐÃ THANH TOÁN]	2026-03-11 16:39:35.08979+00	Ig tamnhu nguyen3	0938227331	11 thuận kiều p4 q11	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
556	#ADM-408672	424	\N	\N	650000	0	0	650000	transfer	shipping	Ig baotran [ĐÃ THANH TOÁN]	2026-03-11 17:00:08.815493+00	Ig baotran	0362799723 	6/205D Bưng Ông Thoàn tăng nhơn phú B thủ đức tphcm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
558	#ADM-644586	425	\N	\N	750000	0	0	750000	transfer	shipping	Ig nu  [ĐÃ THANH TOÁN]	2026-03-12 03:04:04.684547+00	Ig nu 	0778988112	13.04 S6, The Sun Anenue, 28 Đ. Mai Chí Thọ, An Phú, Thành phố Thủ Đức	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
557	#ADM-582626	71	\N	\N	350000	0	0	350000	transfer	shipping	Ig phhmy_inr [ĐÃ THANH TOÁN]	2026-03-12 03:03:02.804246+00	Ig phhmy_inr	789515460	khách tự đặt xe	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
561	#ADM-335681	428	\N	\N	700000	0	0	700000	transfer	cancelled	Ig kiraikini [ĐÃ THANH TOÁN]	2026-03-12 15:28:55.768339+00	Ig kiraikini	0966655088	số 9 bế văn cấm quận 7 nha\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
559	#ADM-249294	426	\N	\N	3900000	0	0	3900000	transfer	shipping	Lan Dang ig [ĐÃ THANH TOÁN]	2026-03-12 15:27:29.395204+00	 Lan Dang ig	(786) 502 0870	16714 sw 39th st Miramar FL,33027\n(786) 502 0870	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
560	#ADM-299620	427	\N	\N	400000	0	0	400000	transfer	shipping	Ig imi [ĐÃ THANH TOÁN]	2026-03-12 15:28:19.736313+00	Ig imi	0976441633 	Cc hoàng anh thanh bình\nĐường d4 phường tân hưng quận 7 \nNhư	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
562	#ADM-422756	428	\N	\N	700000	0	-70000	630000	transfer	shipping	Ig kiraikini [ĐÃ THANH TOÁN]	2026-03-12 15:30:22.966967+00	Ig kiraikini	0966655088	số 9 bế văn cấm quận 7 nha	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
563	#ADM-466213	378	\N	\N	650000	0	0	650000	transfer	shipping	Ig y băng ng  [ĐÃ THANH TOÁN]	2026-03-12 15:31:06.352777+00	Ig y băng ng 	0965304907	Đường số 11, hẻm 11C, phước tân 2, xã Tân Hưng, tp Bà rịa	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
564	#ADM-501769	429	\N	\N	1350000	0	0	1350000	transfer	shipping	Ig anni  [ĐÃ THANH TOÁN]	2026-03-12 15:31:41.865673+00	Ig anni 	0909318058 	7/7 Nguyen Trai Ben Thanh .aspire Sai Gon	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
565	#ADM-537292	430	\N	\N	350000	0	0	350000	transfer	shipping	Ig hanjin_wb [ĐÃ THANH TOÁN]	2026-03-12 15:32:17.381436+00	Ig hanjin_wb	0909078752 	192 nguyễn công trứ phường Bến Thành	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
566	#ADM-566197	431	\N	\N	300000	0	0	300000	transfer	shipping	Ig haaaviii [ĐÃ THANH TOÁN]	2026-03-12 15:32:46.334345+00	Ig haaaviii	0965203289	50 Tạ Quang Bửu, Hai Bà Trưng, Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
567	#ADM-635659	432	\N	\N	2300000	0	0	2300000	transfer	shipping	Ig thuý hằng [ĐÃ THANH TOÁN]	2026-03-12 15:33:55.804959+00	Ig thuý hằng	0374714319	Sảnh cư dân landmark 81	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
568	#ADM-680919	433	\N	\N	750000	0	0	750000	transfer	shipping	Ig bí nhe [ĐÃ THANH TOÁN]	2026-03-12 15:34:41.016361+00	Ig bí nhe	0944294068 	202/51 phạm văn hai p5 qtan bình 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
569	#ADM-718158	434	\N	\N	650000	0	0	650000	transfer	shipping	Ig quỳnh như [ĐÃ THANH TOÁN]	2026-03-12 15:35:18.271236+00	Ig quỳnh như	0374801159 	45a đươnhf 3/2 p11 quận 10 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
570	#ADM-776840	435	\N	\N	300000	0	0	300000	transfer	shipping	Ig an huệ [ĐÃ THANH TOÁN]	2026-03-12 15:36:16.957202+00	Ig an huệ	0902116728	Chung cư Decapella, 116 Lương Định Của, Phường An Khánh TP Thủ đức	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
571	#ADM-864498	71	\N	\N	970000	0	0	970000	transfer	shipping	For Yuliua krupnova  [ĐÃ THANH TOÁN]	2026-03-12 15:37:44.602766+00	For Yuliua krupnova 	789515460	For Yuliua krupnova tên\nHome hotel\n158 ng đình chính. Phú nhuận	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
572	#ADM-930281	436	\N	\N	650000	0	0	650000	transfer	shipping	Ig tram anh [ĐÃ THANH TOÁN]	2026-03-12 15:38:50.389412+00	Ig tram anh	0976132961	163 võ thành trang, p bảy hiền ( p11 cũ ) quận tân bình	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
573	#ADM-981587	437	\N	\N	600000	0	0	600000	transfer	shipping	Ig nauy [ĐÃ THANH TOÁN]	2026-03-12 15:39:41.690465+00	Ig nauy	0787074452	07 hoàng sĩ khải đà nẵng	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
574	ORD-64691773368265	302	\N	\N	700000	0	20000	720000	banking	shipping	\N	2026-03-13 02:17:44.602247+00	Phạm Yến Vy	0796689118	843/16/6 Nguyễn Kiệm Phường 3 Gò Vấp, Quận Gò Vấp, Hồ Chí Minh	vyphamyen0311@gmail.com	\N	SPXVN065070848953	unpaid	\N	1461	21302	\N	\N	\N
575	ORD-45621773381813	438	\N	\N	350000	0	20000	370000	banking	shipping	\N	2026-03-13 06:03:33.065085+00	Phạm Nguyễn Bảo Quyên	0707121103	463/15b Kha Vạn Cân, Quận Thủ Đức, Hồ Chí Minh	p.n.b.quyen12.11@gmail.com	\N	SPXVN064510689853	unpaid	\N	1463	21806	\N	\N	\N
576	ORD-54751773394095	439	\N	\N	1650000	0	20000	1670000	banking	shipping	\N	2026-03-13 09:28:15.036097+00	VIKTORIIA konik	+84 39 2340891	Hiyori Garden Tower 611, Quận Sơn Trà, Đà Nẵng	vikakotatko@gmail.com	\N	SPXVN063434944163	unpaid	\N	1528	40303	\N	\N	\N
577	#ADM-175253	440	\N	\N	1050000	0	0	1050000	transfer	cancelled	Ig gagayeong [ĐÃ THANH TOÁN]	2026-03-13 11:42:55.346849+00	Ig gagayeong	 82 10 2076 1821	 Gayeong kim\nPhone : 82 10 2076 1821\nEmail : rkdud1821@naver.com\nShipping address : \n\n601 ho, 312, Bongeunsa-ro, Gangnam-gu, Seoul, Republic of Korea	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
581	#ADM-486091	443	\N	\N	750000	0	0	750000	transfer	shipping	Ig vũ tường vi [ĐÃ THANH TOÁN]	2026-03-13 11:48:06.186291+00	Ig vũ tường vi	0981078612	57 Phó Đức Chính- P. Nguyễn Thái Bình- Q1	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
579	#ADM-380721	442	\N	\N	300000	0	0	300000	transfer	shipping	Ig minh ngọc [ĐÃ THANH TOÁN]	2026-03-13 11:46:20.817798+00	Ig minh ngọc	+84 38 4045461‬‬	Ấp tân hiệp A, thị trấn Óc Eo, huyện Thoại Sơn, tỉnh An Giang	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
578	#ADM-349024	441	\N	\N	2300000	0	0	2300000	transfer	shipping	Ig gagayeong [ĐÃ THANH TOÁN]	2026-03-13 11:45:49.114419+00	Ig gagayeong	82 10 2076 1821	Name : Gayeong kim\nPhone : 82 10 2076 1821\nEmail : rkdud1821@naver.com\nShipping address : \n\n601 ho, 312, Bongeunsa-ro, Gangnam-gu, Seoul, Republic of Korea	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
1240	#ADM-710104	960	\N	\N	1940000	0	0	1940000	cod	shipping	Ig katherine tran	2026-04-14 06:21:50.235641+00	Ig katherine tran	+84 93 8921937	Empire city- tòa linden - T1A -15.01	\N	\N	\N	unpaid	\N	\N	\N	2026-04-14 15:32:14.742+00	\N	\N
586	#ADM-632389	445	\N	\N	400000	0	0	400000	transfer	cancelled	Ig petit amour [ĐÃ THANH TOÁN]	2026-03-13 11:50:32.809687+00	Ig petit amour	0909967633	18L Điện Biên Phủ quận 1	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
588	#ADM-721817	447	\N	\N	700000	0	0	700000	transfer	shipping	Ig nhi pham [ĐÃ THANH TOÁN]	2026-03-13 11:52:01.912551+00	Ig nhi pham	0399433526	843/16/6 Nguyễn Kiệm, p Hạnh Thông (p3 cũ), Gò Vấp, TP HCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
587	#ADM-692438	446	\N	\N	1400000	0	0	1400000	transfer	shipping	Ig __strawbeerry [ĐÃ THANH TOÁN]	2026-03-13 11:51:32.529553+00	Ig __strawbeerry	0946335555	số 2 thác mạ 5 phường đông kinh tp lạng sơn	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
585	#ADM-632156	445	\N	\N	400000	0	0	400000	transfer	shipping	Ig petit amour [ĐÃ THANH TOÁN]	2026-03-13 11:50:32.244533+00	Ig petit amour	0909967633	18L Điện Biên Phủ quận 1	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
583	#ADM-538132	55	\N	\N	300000	0	0	300000	transfer	shipping	Ig kanyarat [ĐÃ THANH TOÁN]	2026-03-13 11:48:58.228445+00	Ig kanyarat	0369166.222	163 Trương Thị Hoa, phường Tân Thới Hiệp, Quận 12, thành phố Hồ Chí Minh\n sdt : 0369166.222 ( Người Nhận BN2705)	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
582	#ADM-514799	444	\N	\N	650000	0	0	650000	transfer	shipping	Ig nguyễn bảo uyên [ĐÃ THANH TOÁN]	2026-03-13 11:48:34.888956+00	Ig nguyễn bảo uyên	 0901848308	259 Phan Đình Phùng p15 qPN	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
580	#ADM-411353	50	\N	\N	320000	0	0	320000	transfer	shipping	Ig ngô thị an [ĐÃ THANH TOÁN]	2026-03-13 11:46:51.462425+00	Ig ngô thị an	0325267896	Người nhận: wind xpress- W 2807( tangmo) ghi lên kiện\nSđt: 0325267896\nĐc: 375 . đường Tân thới hiệp 21 - tổ 3 - kp3- Quận 12 . Tphcm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
592	#ADM-029488	449	\N	\N	350000	0	0	350000	transfer	shipping	Ig my.freaky. [ĐÃ THANH TOÁN]	2026-03-13 14:27:09.61695+00	Ig my.freaky.	0779800109	36a Út tịch, tân bình	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
591	#ADM-019938	291	\N	\N	350000	0	0	350000	transfer	shipping	Ig mô [ĐÃ THANH TOÁN]	2026-03-13 13:53:40.405018+00	Ig mô	0334232268	112 Yên Phụ nhỏ, phường Yên Phụ, quận Tây Hồ, TP Hà Nội\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
590	#ADM-066378	448	\N	\N	1100000	0	0	1100000	transfer	shipping	Lê salan  [ĐÃ THANH TOÁN]	2026-03-13 12:14:26.578499+00	Lê salan 	0784250794.	90 nguyễn hữu cảnh p22 quận bình thạnh . \nSunwah Pearl Golden House .	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
596	ORD-73061773468324	452	\N	\N	300000	0	20000	320000	banking	cancelled	\N	2026-03-14 06:05:23.718213+00	Lelinh	0977463201	133 huỳnh thúc kháng, Quận Đống Đa, Hà Nội	lehoangphuonglinh16091995@gmai.com	\N	\N	unpaid	\N	1486	1A0406	\N	\N	\N
597	ORD-52731773472649	453	\N	\N	550000	0	20000	570000	banking	shipping	\N	2026-03-14 07:17:29.407412+00	Byun Seyoung	0789841731	34 Lê Duẩn Diamond Plaza (The Office Lobby ground floor), Quận 1, Hồ Chí Minh	seyoung.byun0531@gmail.com	\N	https://spx.vn/track?SPXVN065957422473	unpaid	\N	1442	20101	\N	\N	\N
603	ORD-17981773492476	457	\N	\N	700000	0	20000	720000	banking	shipping	\N	2026-03-14 12:47:55.894127+00	Azjargal Amar	038 5846270	38/29 Nguyen Cong Hoan, Quận Phú Nhuận, Hồ Chí Minh	azjargla0125@gmail.com	\N	https://spx.vn/track?SPXVN065764309023	unpaid	\N	1457	21706	\N	\N	\N
605	#ADM-530746	459	\N	\N	320000	0	0	320000	transfer	shipping	Ig douneo_123 [ĐÃ THANH TOÁN]	2026-03-14 12:48:50.851525+00	Ig douneo_123	0949855883	74 cử trị châu đốc an giang	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
604	#ADM-511711	458	\N	\N	750000	0	0	750000	transfer	shipping	Ig thu yoga & qigong [ĐÃ THANH TOÁN]	2026-03-14 12:48:31.81652+00	Ig thu yoga & qigong	0962482428	6/5/10 chế lan viên, ngũ hành sơn, đà nẵng	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
602	#ADM-422934	456	\N	\N	350000	0	0	350000	transfer	shipping	Ig chenniii [ĐÃ THANH TOÁN]	2026-03-14 12:47:03.041404+00	Ig chenniii	0902847090 	46 Hoa Đào P2 Phú Nhuận	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
601	#ADM-394624	455	\N	\N	300000	0	0	300000	transfer	shipping	Ig minh anh [ĐÃ THANH TOÁN]	2026-03-14 12:46:34.723252+00	Ig minh anh	0788655755	04 phan chu trinh, p bình thạnh tp hcm\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
600	#ADM-364537	454	\N	\N	800000	0	0	800000	transfer	shipping	Ig yanie.th [ĐÃ THANH TOÁN]	2026-03-14 12:46:04.637331+00	Ig yanie.th	0384643228	Tổ 1, Khu Phố Tiến Hưng 3, Phước, Tỉnh Đồng Nai (Hẻm 167 Số Nhà 47), Xã Tiến Hưng, Thành Phố Đồng Xoài, Bình Phước	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
598	#ADM-309337	71	\N	\N	750000	0	0	750000	transfer	shipping	Ig huynh nhu hao [ĐÃ THANH TOÁN]	2026-03-14 12:45:09.506263+00	Ig huynh nhu hao	789515460	Hoả tốc khách tự đặt ship	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
599	#ADM-345440	452	\N	\N	300000	0	0	300000	transfer	shipping	Ig lilhp [ĐÃ THANH TOÁN]	2026-03-14 12:45:45.577847+00	Ig lilhp	0977463201	133 huỳnh thúc kháng- phường láng hạ-quận đống đa-HN	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
595	#ADM-601929	451	\N	\N	550000	0	0	550000	transfer	shipping	Ig an [ĐÃ THANH TOÁN]	2026-03-14 03:40:02.040312+00	Ig an	0909056816	Số Nhà 26 Lô U, Đường Cư Xá Phú Lâm D, Phường 10, Quận 6, TP. Hồ Chí Minh\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
593	#ADM-526759	450	\N	\N	650000	0	0	650000	transfer	shipping	Ig haânbala333 [ĐÃ THANH TOÁN]	2026-03-14 03:38:46.874042+00	Ig haânbala333	0983703307	35 Nguyễn Văn Bá, Bình Thọ, Thủ Đức\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
594	#ADM-554128	71	\N	\N	600000	0	0	600000	transfer	shipping	Ig aren_pre [ĐÃ THANH TOÁN]	2026-03-14 03:39:14.227951+00	Ig aren_pre	789515460	Hoả tốc	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
606	#ADM-789877	460	\N	\N	650000	0	0	650000	transfer	shipping	Ig ngọc hà [ĐÃ THANH TOÁN]	2026-03-14 13:26:30.006065+00	Ig ngọc hà	0937408700	Block B Chung cư Eco Green, Nguyễn Văn Linh, Phường tân thuận tây, Quận 7	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
607	#ADM-990533	461	\N	\N	300000	0	0	300000	transfer	cancelled	Ig cam [ĐÃ THANH TOÁN]	2026-03-14 13:29:50.664413+00	Ig cam	0786594301	496/93/7 dương quãng hàm p6 gv	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
610	#ADM-766130	463	\N	\N	700000	0	0	700000	transfer	shipping	Ig amber  [ĐÃ THANH TOÁN]	2026-03-14 16:29:26.22716+00	Ig amber 	0969998916	lâm viên complex 107a nguyễn phong sắc cầu giấy hn\nphòng 20-01	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
609	#ADM-726888	462	\N	\N	650000	0	0	650000	transfer	shipping	Ig jasmine [ĐÃ THANH TOÁN]	2026-03-14 16:28:47.137234+00	Ig jasmine	0934040535	100/15 dương bá trạc p2 q8	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
608	#ADM-049854	461	\N	\N	300000	0	0	300000	transfer	shipping	Ig cam [ĐÃ THANH TOÁN]	2026-03-14 13:30:49.986098+00	Ig cam	0786594301	496/93/7 dương quãng hàm p6 gv	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
611	ORD-69191773539469	464	\N	\N	1250000	0	20000	1270000	banking	shipping	\N	2026-03-15 01:51:09.040088+00	Nguyễn Thị Thuỷ Tiên	0374354658	Thôn 7, xã Lý Trạch, huyện Bố Trạch, tỉnh Quảng Bình, Huyện Bố Trạch, Quảng Bình	ntun.cen16@gmail.com	\N	https://spx.vn/track?SPXVN065989143183	unpaid	\N	1858	310515	\N	\N	\N
584	#ADM-593266	71	\N	\N	700000	0	0	700000	transfer	completed	Ig pee pov [ĐÃ THANH TOÁN]	2026-03-13 11:49:53.411658+00	Ig pee pov	789515460	Gói sẵn\nKhach có địa chỉ nhắn liền	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
613	#ADM-952489	466	\N	\N	300000	0	0	300000	transfer	shipping	Ig tô như huỳnh [ĐÃ THANH TOÁN]	2026-03-15 16:42:32.583085+00	Ig tô như huỳnh	 0862087248	006/AL Kp An lợi TT Tiệm Tôm Ba Tri Bến Tre 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
612	ORD-25441773587564	465	\N	\N	670000	0	20000	690000	banking	shipping	\N	2026-03-15 15:12:44.419276+00	Nhi	0938855752	282 nguyễn thị định, Quận 2, Hồ Chí Minh	voyennhi8396@gmail.com	\N	https://spx.vn/track?SPXVN061319245763	unpaid	\N	1443	20207	\N	\N	\N
614	#ADM-006720	467	\N	\N	1870000	0	0	1870000	transfer	shipping	Ig rosa nguyen [ĐÃ THANH TOÁN]	2026-03-15 16:43:26.83936+00	Ig rosa nguyen	+16083819852	274 Calle Canals apt 1001, San Juan PR 00907 \nRnguyen12919@gmail.com	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
615	#ADM-131861	468	\N	\N	350000	0	0	350000	transfer	shipping	Ig minh anh [ĐÃ THANH TOÁN]	2026-03-15 16:45:31.991664+00	Ig minh anh	0846970367	 116/36, bình lợi, bình thạnh 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
616	#ADM-171353	469	\N	\N	650000	0	0	650000	transfer	shipping	Ig võ quỳnh nhi  [ĐÃ THANH TOÁN]	2026-03-15 16:46:11.446208+00	Ig võ quỳnh nhi 	0945796060	Chung cư rivana phường vĩnh phú thuận an bình dương	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
617	#ADM-203591	470	\N	\N	320000	0	0	320000	transfer	shipping	Ig phan gia ân [ĐÃ THANH TOÁN]	2026-03-15 16:46:43.686621+00	Ig phan gia ân	đặng thúc vịnh  0938489922 	211 ấp 7 xã đông thạnh hóc môn đường \nGiao ở áo cưới nhất linh (note) 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
618	#ADM-231822	471	\N	\N	350000	0	0	350000	transfer	shipping	Ig nguyet thao nguyen [ĐÃ THANH TOÁN]	2026-03-15 16:47:12.397441+00	Ig nguyet thao nguyen	0769844844	215 Nam Kỳ Khởi Nghĩa quận 3	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
619	#ADM-288172	472	\N	\N	350000	0	0	350000	transfer	shipping	Ig phuong uyen [ĐÃ THANH TOÁN]	2026-03-15 16:48:08.262471+00	Ig phuong uyen	0378020197	Căn số 40 khu biệt thự Ngân Long, Phước Kiển, Nhà Bè, TPHCM\nPhương Uyên	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
620	#ADM-318913	361	\N	\N	320000	0	0	320000	transfer	shipping	Ig lâm thuý an [ĐÃ THANH TOÁN]	2026-03-15 16:48:39.014099+00	Ig lâm thuý an	0366949072	57 Nguyễn Trọng Lội, Q. Tân Bình	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
621	#ADM-353563	473	\N	\N	300000	0	0	300000	transfer	shipping	Ig yeubonthui [ĐÃ THANH TOÁN]	2026-03-15 16:49:13.674843+00	Ig yeubonthui	+84 87 9832607	toà nhà BRG, 198 Trần Quang Khải, Lý Thái Tổ, Hoàn Kiếm, Hà Nội 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
622	#ADM-384769	474	\N	\N	350000	0	0	350000	transfer	shipping	Ig lihn [ĐÃ THANH TOÁN]	2026-03-15 16:49:44.857444+00	Ig lihn	0963894934 	Tổ dân phố tuân cáo, phường nam hoa lư \n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
623	#ADM-421336	475	\N	\N	700000	0	0	700000	transfer	shipping	Ig pheoo  [ĐÃ THANH TOÁN]	2026-03-15 16:50:21.438904+00	Ig pheoo 	0963617696	Số 21, khu C ngách 1194/61/3A, Láng Thượng, Đống Đa, HN	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
624	#ADM-509543	461	\N	\N	350000	0	0	350000	transfer	shipping	ig Cam Cam [ĐÃ THANH TOÁN]	2026-03-15 16:51:49.648044+00	ig Cam Cam	0786594301	496/93/7 dương quãng hàm p6 gv	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
625	#ADM-225811	476	\N	\N	600000	0	0	600000	transfer	shipping	Ig insightofan [ĐÃ THANH TOÁN]	2026-03-15 17:20:25.953998+00	Ig insightofan	 0908931940	địa chỉ: 884/85 Lê Đức Thọ phường 15 quận Gò Vấp TP.HCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
626	ORD-50381773630131	477	\N	\N	1420000	0	20000	1440000	banking	shipping	\N	2026-03-16 03:02:10.616785+00	SHUNFEI （#43301）	0383163470	Số 160/46 Phan huy ích ，Phường 12 ，quận Gò Vấp TP Hồ Chí Minh, Quận Gò Vấp, Hồ Chí Minh	jamiefong0213@gmail.com	\N	https://spx.vn/track?SPXVN060082834433	unpaid	\N	1461	21308	\N	\N	\N
636	ORD-99001773653877	485	\N	\N	600000	0	20000	620000	banking	shipping	\N	2026-03-16 09:37:57.032514+00	Nguyễn Thị Phương Thảo	0365 081621	38 Ngõ 213, Quận Lê Chân, Hải Phòng	ducpham1219@gmail.com	\N	https://spx.vn/track?SPXVN064355863533	unpaid	\N	1588	30212	\N	\N	\N
637	#ADM-264760	486	\N	\N	700000	0	0	700000	transfer	shipping	Ig nina [ĐÃ THANH TOÁN]	2026-03-16 09:44:24.897215+00	Ig nina	0906852624 	633 ấp 1 Nguyễn Văn Tạo Hiệp Phước Nhà Bè HCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
635	#ADM-494064	448	\N	\N	650000	0	0	650000	transfer	shipping	Lê salan  [ĐÃ THANH TOÁN]	2026-03-16 07:51:34.561562+00	Lê salan 	0784250794.	90 nguyễn hữu cảnh p22 quận bình thạnh . \nSunwah Pearl Golden House .	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
634	#ADM-890895	484	\N	\N	300000	0	0	300000	transfer	shipping	Ig audet elisabeth [ĐÃ THANH TOÁN]	2026-03-16 07:24:50.993338+00	Ig audet elisabeth	0933782889	 Tòa Nhà Sky 89, Số 39, Đường Lê Thị Chợ Căn 20-01, Phường Phú Mỹ, Quận 7, TP. Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
633	#ADM-913316	483	\N	\N	1750000	0	0	1750000	transfer	shipping	Ig acidcxc [ĐÃ THANH TOÁN]	2026-03-16 07:08:33.413278+00	Ig acidcxc	0949.006083	153, Luong Nhu Hoc, phường chợ lớn, tphcm \nPIC: Nguyen (Becky)	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
632	#ADM-816225	482	\N	\N	350000	0	0	350000	transfer	shipping	Ig phphuongg [ĐÃ THANH TOÁN]	2026-03-16 07:06:56.321123+00	Ig phphuongg	0907469268	2/42 cao thắng p5q3	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
631	#ADM-772095	481	\N	\N	320000	0	0	320000	transfer	shipping	Ig jenny [ĐÃ THANH TOÁN]	2026-03-16 07:06:12.204339+00	Ig jenny	092.379.3678  	Mã khách hàng :  K258\nĐịa chỉ: Mặt sau số 168 Trần thủ độ, Pháp vân , Hoàng liệt , Hoàng mai , Hà nội.\n( gõ tìm kiếm 🔍 sân bóng đại an ) \n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
630	#ADM-714764	480	\N	\N	650000	0	0	650000	transfer	shipping	Ig yen anh [ĐÃ THANH TOÁN]	2026-03-16 07:05:14.873652+00	Ig yen anh	0376554218	232 Võ Thị Sáu, Phường Xuân Hoà, TPHCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
629	#ADM-675991	479	\N	\N	1450000	0	0	1450000	transfer	shipping	Ig duality [ĐÃ THANH TOÁN]	2026-03-16 07:04:36.125136+00	Ig duality	0909938897	•  Địa chỉ: 6.08 Toà Sapphire 1, Saigon Pearl, 92 Nguyen Hữu Cảnh, Bình Thạnh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
628	#ADM-626970	71	\N	\N	320000	0	0	320000	transfer	shipping	Ig elsa hellokitty  [ĐÃ THANH TOÁN]	2026-03-16 07:03:47.094048+00	Ig elsa hellokitty 	789515460	288c5 phường võ thị sáu quận 3 tphcm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
627	#ADM-527122	478	\N	\N	1000000	0	0	1000000	transfer	shipping	Ig qiennnn_ [ĐÃ THANH TOÁN]	2026-03-16 07:02:07.230111+00	Ig qiennnn_	0934007053	405/8A Thống Nhất, phường Thông Tây Hội\nTp Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
638	ORD-56461773658167	487	\N	\N	750000	0	20000	770000	banking	shipping	\N	2026-03-16 10:49:27.223938+00	Lưu Điệp	0965256838	247 nguyễn thị lắng, Huyện Củ Chi, Hồ Chí Minh	lisaluu2001@icloud.com	\N	https://spx.vn/track?SPXVN060159124003	unpaid	\N	1460	22114	\N	\N	\N
639	ORD-72341773668119	488	\N	\N	1100000	0	20000	1120000	banking	shipping	\N	2026-03-16 13:35:18.680156+00	nhật hà	0866833245	Số nhà 53 ngõ 766 La Thành, Giảng Võ, Quận Ba Đình, Hà Nội	hanhatlebui2001@gmail.com	\N	https://spx.vn/track?SPXVN068277058123	unpaid	\N	1484	1A0104	\N	\N	\N
640	#ADM-004384	489	\N	\N	350000	0	0	350000	transfer	shipping	Ig thuý nga [ĐÃ THANH TOÁN]	2026-03-16 14:56:44.512888+00	Ig thuý nga	0931822004	53 đg só 19 kp 19 phường bhh 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
641	#ADM-235127	71	\N	\N	400000	0	0	400000	transfer	shipping	Ig Yến Bắp [ĐÃ THANH TOÁN]	2026-03-16 16:07:15.291355+00	Ig Yến Bắp	789515460	Nguyễn đình chiểu, bàn cờ	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
642	#ADM-050156	490	\N	\N	650000	0	0	650000	transfer	shipping	Ig Đào Kha Anh Thuyên [ĐÃ THANH TOÁN]	2026-03-16 17:10:50.302278+00	Ig Đào Kha Anh Thuyên	0939839866	110 Bà Hạt quận 10	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
643	ORD-46051773724934	491	\N	\N	650000	0	20000	670000	banking	shipping	\N	2026-03-17 05:22:13.555531+00	Quốc Đại Minh Châu	0975865887	262/26/3 Lũy Bán Bích, phường Hòa Thạnh, Quận Tân Phú, tp HCM, Quận Tân Phú, Hồ Chí Minh		\N	SPXVN067112845333	unpaid	\N	1456	21502	\N	\N	\N
644	#ADM-936080	492	\N	\N	1270000	0	0	1270000	transfer	shipping	Ig ytwying  [ĐÃ THANH TOÁN]	2026-03-17 12:52:16.291762+00	Ig ytwying 	0915559528	Crowne Plaza Danang City Centre\n17 Quang Trung Street\nHai Chau I Ward, Hai Chau District\nDa Nang 550000\nVietnam	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
645	#ADM-077085	493	\N	\N	600000	0	0	600000	transfer	shipping	Ig v.aa.n [ĐÃ THANH TOÁN]	2026-03-17 12:54:37.227855+00	Ig v.aa.n	0889384808	19 đường 11, KĐT Vạn Phúc, Phường Hiệp Bình Phước, TP Thủ Đức, TP.HCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
646	#ADM-180291	494	\N	\N	250000	0	0	250000	transfer	shipping	Ig phors [ĐÃ THANH TOÁN]	2026-03-17 12:56:20.404526+00	Ig phors	 098439373	📍 301 Phạm Ngũ Lão, Phường Phạm Ngũ Lão, Quận 1, Hồ Chí Minh, District 1	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
647	#ADM-213826	495	\N	\N	320000	0	0	320000	transfer	shipping	Ig nguyễn nam phương  [ĐÃ THANH TOÁN]	2026-03-17 12:56:53.950135+00	Ig nguyễn nam phương 	0788089773	Số 4- khu tập thế 5 tầng- ngõ 92 cửa bắc- quán thánh- ba đình - hanoi( k liên lạc dc thì gọi Zalo nh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
648	#ADM-244461	496	\N	\N	250000	0	0	250000	transfer	shipping	Ig pho lâu tùm lum [ĐÃ THANH TOÁN]	2026-03-17 12:57:24.664402+00	Ig pho lâu tùm lum	0971883190	232/12 Nguyễn Thượng Hiền, phường 5, Phú Nhuận, Tp HCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
649	#ADM-326878	497	\N	\N	320000	0	0	320000	transfer	shipping	Ig V [ĐÃ THANH TOÁN]	2026-03-17 12:58:47.027212+00	Ig V	0938886869 	58/14/77 đường số 4 phường bình hưng hoà A quận bình tân	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
650	#ADM-350000	498	\N	\N	350000	0	0	350000	transfer	shipping	Ig an an [ĐÃ THANH TOÁN]	2026-03-17 12:59:10.106681+00	Ig an an	0789440224	68 phạm thị liên , phường kim long , huế	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
651	#ADM-405306	499	\N	\N	300000	0	0	300000	transfer	shipping	Ig nhu quynh [ĐÃ THANH TOÁN]	2026-03-17 13:00:05.423943+00	Ig nhu quynh	0349355535	38 Mai Anh Đào, phường 8, Đà Lạt	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
652	#ADM-433746	500	\N	\N	350000	0	0	350000	transfer	shipping	Ig glo [ĐÃ THANH TOÁN]	2026-03-17 13:00:33.861492+00	Ig glo	0703685858	14 đường 6 p.Bình Trưng (Bình Trưng Đông cũ) TpHCM 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
653	#ADM-576696	501	\N	\N	350000	0	0	350000	transfer	shipping	IG YẾN BẮP [ĐÃ THANH TOÁN]	2026-03-17 13:02:56.855111+00	IG YẾN BẮP	0384388532	399/7 nguyễn đình chiểu khu phố 26, phường bàn cờ 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
654	#ADM-625698	326	\N	\N	650000	0	0	650000	transfer	shipping	Ig nguyễn phương thảo [ĐÃ THANH TOÁN]	2026-03-17 13:03:45.954668+00	Ig nguyễn phương thảo	0962821709	BS8 The Berverly Solari, Vinhomes Grand Park, phường Long Bình, q9, Thủ Đức, HCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
655	#ADM-668410	502	\N	\N	300000	0	0	300000	transfer	shipping	Ig ddanthnhahh [ĐÃ THANH TOÁN]	2026-03-17 13:04:28.54085+00	Ig ddanthnhahh	0932989120	90 đường 77 Tân Quy Quận 7 nha	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
656	ORD-50071773759003	503	\N	\N	300000	0	20000	320000	banking	shipping	\N	2026-03-17 14:50:02.617336+00	Quỳnh Giao	0946942767	Sarina Block C, Đường B2, Thành Phố Thủ Đức, Hồ Chí Minh	hqunhgiao.18@gmail.com	\N	SPXVN066852365233	unpaid	\N	3695	90768	\N	\N	\N
657	#ADM-714081	504	\N	\N	750000	0	0	750000	transfer	shipping	Ig võ oanh vũ [ĐÃ THANH TOÁN]	2026-03-17 15:35:14.551312+00	Ig võ oanh vũ	0935096199	Tòa T3, chung cư masteri thảo điền	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
658	ORD-75581773768295	505	\N	\N	1050000	0	20000	1070000	banking	shipping	\N	2026-03-17 17:24:55.434001+00	Trang Tran	096 4155465	6 Nguyen Khac Hieu, Quận Ba Đình, Hà Nội	thithutrang11@gmail.com	\N	SPXVN068572975913	unpaid	\N	1484	1A0113	\N	\N	\N
659	ORD-60091773802084	506	\N	\N	350000	0	20000	370000	banking	shipping	\N	2026-03-18 02:48:03.56678+00	Minh Thơ	0906870356	1 Lê Hiến Mai, Phường Thạnh Mỹ Lợi, Thủ Đức, Thành phố Hồ Chí Minh, Thành Phố Thủ Đức, Hồ Chí Minh	ngthminhtho253@gmail.com	\N	SPXVN062388455763	unpaid	\N	3695	90748	\N	\N	\N
663	#ADM-529897	510	\N	\N	320000	0	0	320000	transfer	cancelled	Ig qingyi8802 [ĐÃ THANH TOÁN]	2026-03-18 03:12:09.988096+00	Ig qingyi8802	0962875123 	85 Hàng Bạc Hoàn Kiếm Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
667	#ADM-853938	514	\N	\N	350000	0	0	350000	transfer	shipping	Ig katie nguyen  [ĐÃ THANH TOÁN]	2026-03-18 13:00:54.09777+00	Ig katie nguyen 	0915043806	321/1 Quốc lộ 1 phường 4, TP Tân An, Long An	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
661	#ADM-466286	508	\N	\N	400000	0	0	400000	transfer	shipping	Ig minieeeee [ĐÃ THANH TOÁN]	2026-03-18 03:11:06.43862+00	Ig minieeeee	0904177271	C13/26 tôn đản phường 13 quận 4	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
662	#ADM-501862	509	\N	\N	350000	0	0	350000	transfer	shipping	Ig qingyi8802 [ĐÃ THANH TOÁN]	2026-03-18 03:11:41.98102+00	Ig qingyi8802	0396504228 	Số 51, ngõ 31, B6 Khu nhà ở Mai Dịch, đường Nguyễn Khả Trạc, Phường Phú Diễn, Thành phố Hà Nội, Việt Nam (phường Mai Dịch, Cầu Giấy cũ)\nNgười nhận: JM TQ\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
664	#ADM-696755	511	\N	\N	320000	0	0	320000	transfer	shipping	ig miuiuuuuu_00 [ĐÃ THANH TOÁN]	2026-03-18 03:14:56.840767+00	ig miuiuuuuu_00	0962875123	Địa chỉ giao hàng\n85 Hàng Bạc Hoàn Kiếm Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
665	#ADM-754587	512	\N	\N	1550000	0	0	1550000	transfer	shipping	Ig trang lê [ĐÃ THANH TOÁN]	2026-03-18 04:05:54.680962+00	Ig trang lê	0932506553	No 99/18-18A , Nguyen Thai Binh Street, Ward 4, District Tan Binh, TP. Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
666	ORD-52721773827973	513	\N	\N	300000	0	20000	320000	banking	shipping	\N	2026-03-18 09:59:32.826678+00	Thuy Dat	0862728912	P2 Pavilion Vinhomes Ocean Park, Huyện Gia Lâm, Hà Nội	freakkymelly@gmail.com	\N	SPXVN066957015543	unpaid	\N	1703	1A1201	\N	\N	\N
669	#ADM-916232	516	\N	\N	350000	0	0	350000	transfer	shipping	Ig hoàng lê kim [ĐÃ THANH TOÁN]	2026-03-18 13:01:56.360591+00	Ig hoàng lê kim	0934034199 	37 hoa sứ phường cầu kiệu tphcm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
670	#ADM-957914	517	\N	\N	350000	0	0	350000	transfer	shipping	Ig chib.bong [ĐÃ THANH TOÁN]	2026-03-18 13:02:38.014324+00	Ig chib.bong	0794999769	21b bùi thị xuân phường bến thành quận 1	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
671	#ADM-042231	518	\N	\N	700000	0	0	700000	transfer	shipping	Ig chang chang [ĐÃ THANH TOÁN]	2026-03-18 13:04:02.334874+00	Ig chang chang	0904467252	Địa chỉ: 220/85/2 Hoàng Hoa Thám, Phường 5, quận Bình Thạnh, TP.HCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
1246	#ADM-139768	71	\N	\N	660000	0	0	660000	transfer	shipping	Ig beeingbeefr [ĐÃ THANH TOÁN]	2026-04-14 15:05:39.940993+00	Ig beeingbeefr	789515460	khách hoả tốc	\N	\N	\N	unpaid	\N	\N	\N	2026-04-14 15:32:14.742+00	\N	\N
1244	#ADM-927373	965	\N	\N	1870000	0	0	1870000	cod	shipping	Ig amy	2026-04-14 15:02:07.486621+00	Ig amy 	+61 493 016 563	1204/10 Vista St, Surfers Paradise, Gold Coast, 4217, Australia	\N	\N	\N	unpaid	\N	\N	\N	2026-04-14 15:32:14.742+00	\N	\N
660	#ADM-440909	507	\N	\N	300000	0	0	300000	transfer	returned	Ig ngocnhii_zt [ĐÃ THANH TOÁN]	2026-03-18 03:10:41.022352+00	Ig ngocnhii_zt	(+84) 818 613 364	D-72 Tái Định Cư Kp10 Phú Quốc Phường Dương Đông, Thành Phố Phú Quốc, Kiên Giang	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
668	#ADM-887847	515	\N	\N	400000	0	0	400000	transfer	shipping	Ig thriftwith [ĐÃ THANH TOÁN]	2026-03-18 13:01:28.324665+00	Ig thriftwith	0765488828	ទីតាំងឃ្លាំងទទួលទំនិញនៅវៀតណាម \n\nលេខឃ្លាំង៖ \n154 tuệ tĩnh p12 q11 tphcm VTV To Cambodian Monyrothna Leng TKK 067234568   Postal code  : 72600	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
672	#ADM-681939	519	\N	\N	320000	0	0	320000	transfer	shipping	Ig N [ĐÃ THANH TOÁN]	2026-03-18 13:31:22.062531+00	Ig N	0818891141	12 Đặng Như Mai, phường Phước Mỹ, tp. Phan Rang-Tháp Chàm, tỉnh Ninh Thuận	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
673	#ADM-711955	520	\N	\N	350000	0	0	350000	transfer	shipping	Ig nina [ĐÃ THANH TOÁN]	2026-03-18 13:31:52.094406+00	Ig nina	0906852624	633 ấp 1 Nguyễn Văn Tạo Hiệp Phước Nhà Bè HCM\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
674	#ADM-984052	521	\N	\N	300000	0	0	300000	transfer	shipping	Ig liêu thị thanh ngân [ĐÃ THANH TOÁN]	2026-03-18 13:36:24.167841+00	Ig liêu thị thanh ngân	0819717639 	53 thủ khoa huân p1 mỹ tho	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
675	ORD-41621773845125	522	\N	\N	700000	0	20000	720000	banking	shipping	\N	2026-03-18 14:45:25.196853+00	Lin Shihhan 	0903665872	D12A-07 Midtown M7, Quận 7, Hồ Chí Minh		\N	SPXVN064371970103	unpaid	\N	1449	20707	\N	\N	\N
676	#ADM-320530	523	\N	\N	650000	0	0	650000	transfer	shipping	Ig hồng trâm [ĐÃ THANH TOÁN]	2026-03-18 16:45:20.667956+00	Ig hồng trâm	(+84) 787 726 763	15/3, Trần Hưng Đạo\nPhường 6, Thành Phố Mỹ Tho, Tiền Giang	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
677	#ADM-353847	524	\N	\N	350000	0	0	350000	transfer	shipping	Ig hellokittybby_x [ĐÃ THANH TOÁN]	2026-03-18 16:45:54.012623+00	Ig hellokittybby_x	0936058181	243 Vành đai trong, P. Bình trị đông B, bình tân	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
678	#ADM-614648	525	\N	\N	650000	0	0	650000	transfer	shipping	Ig nhung hi [ĐÃ THANH TOÁN]	2026-03-18 16:50:14.766043+00	Ig nhung hi	0337126660	Ấp 2 phước bình long thành đồng nai	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
679	#ADM-594146	526	\N	\N	350000	0	0	350000	transfer	shipping	Ig onlykitty.ty [ĐÃ THANH TOÁN]	2026-03-19 03:39:54.235958+00	Ig onlykitty.ty	0778683355	A4.23 kdc cotec phú xuân nhà bè	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
680	#ADM-621864	527	\N	\N	300000	0	0	300000	transfer	shipping	Ig dpt_232  [ĐÃ THANH TOÁN]	2026-03-19 03:40:21.957568+00	Ig dpt_232 	0364565231 	35 trục chính tam hiệp - phúc thọ - HN	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
681	#ADM-911177	528	\N	\N	750000	0	0	750000	transfer	shipping	Ig thuỳ trang  [ĐÃ THANH TOÁN]	2026-03-19 03:45:11.304774+00	Ig thuỳ trang 	0912287577 	39 dương văn đồng hới quảng trị	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
682	#ADM-953608	71	\N	\N	350000	0	0	350000	transfer	shipping	Ig yến nhi trần [ĐÃ THANH TOÁN]	2026-03-19 03:45:53.767785+00	Ig yến nhi trần	789515460	63 ỷ lan, tân phú dum minh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
683	ORD-11241773907217	529	\N	\N	350000	0	20000	370000	banking	shipping	\N	2026-03-19 08:00:17.050993+00	Trân	0853273175	421 Trần Xuân Soạn phường Tân Kiểng quận 7, Quận 7, Hồ Chí Minh	Vohoangbaotran971@gmail.com	\N	SPXVN067405204323	unpaid	\N	1449	20705	\N	\N	\N
686	#ADM-005406	532	\N	\N	1800000	0	0	1800000	transfer	shipping	Ig rlrde9 [ĐÃ THANH TOÁN]	2026-03-19 10:43:25.53918+00	Ig rlrde9	0363485698	30 Đường Nguyễn Hữu Cảnh, Bình Thạnh, Thành phố Hồ Chí Minh 700000	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
685	#ADM-937390	531	\N	\N	350000	0	0	350000	transfer	shipping	Ig chakriya meun [ĐÃ THANH TOÁN]	2026-03-19 10:42:17.480408+00	Ig chakriya meun	0708163707	Street:  177c, Đường Số 1, P Bình Hưng Hòa B, Q Bình Tân, Hồ Chí Minh\nKHE1600108	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
684	#ADM-911830	530	\N	\N	350000	0	0	350000	transfer	shipping	Ig fairy [ĐÃ THANH TOÁN]	2026-03-19 10:41:51.944088+00	Ig fairy	 0906082741	Địa chỉ số 7 đường 46 phường 2 quận 4	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
687	#ADM-576297	508	\N	\N	970000	0	0	970000	transfer	shipping	Ig minieeeeeee [ĐÃ THANH TOÁN]	2026-03-19 15:52:56.793539+00	Ig minieeeeeee	0904177271	C13/26 tôn đản phường 13 quận 4	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
689	#ADM-706820	534	\N	\N	300000	0	0	300000	transfer	shipping	Ig thanh [ĐÃ THANH TOÁN]	2026-03-19 15:55:06.918027+00	Ig thanh	0357361236	đchi: 5/73e nguyễn hữu cảnh, phường an tây , huế\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
690	#ADM-581358	535	\N	\N	900000	0	0	900000	transfer	shipping	Ig nn.ricci [ĐÃ THANH TOÁN]	2026-03-19 16:59:41.526921+00	Ig nn.ricci	0985561610 	46-46Bis Thủ Khoa Huân, Street, Quận 1 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
692	ORD-24721773977640	5	\N	\N	600000	0	20000	620000	banking	cancelled	\N	2026-03-20 03:33:59.618204+00	test	0979911670	25 Hồ Thành Biên , Quận 8, Hồ Chí Minh		\N	\N	unpaid	\N	1450	20804	\N	\N	\N
694	ORD-47671773992147	5	\N	\N	350000	0	20000	370000	banking	cancelled	\N	2026-03-20 07:35:46.811656+00	test	0979911670	15 NXK , Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	1456	21509	\N	\N	\N
695	ORD-66831773994004	5	\N	\N	300000	0	20000	320000	banking	cancelled		2026-03-20 08:06:44.224346+00	test	0979911679	18 NXK, Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	1456	21509	\N	\N	\N
691	ORD-82351773977132	536	\N	\N	600000	0	0	600000	banking	shipping	\N	2026-03-20 03:25:31.993287+00	Châu Ngọc Thảo Uyên	0902574509	25 hồ thành biên, Quận 8, Hồ Chí Minh	uyenthxo209@gmail.com	\N	SPXVN068161120123	unpaid	\N	1450	20804	\N	\N	\N
698	#ADM-734404	540	\N	\N	350000	0	0	350000	transfer	cancelled	Ig pee pov  [ĐÃ THANH TOÁN]	2026-03-20 12:28:54.526929+00	Ig pee pov 	0935906826	Hẻm 114 năm châu phường 12 quận tân bình tp hcm\nThuỷ Tiên	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
696	#ADM-622088	538	\N	\N	350000	0	0	350000	transfer	shipping	Ig gonnyne [ĐÃ THANH TOÁN]	2026-03-20 12:27:02.221202+00	Ig gonnyne	0912562355	19/22 nam kỳ khởi nghĩa , p1 , đà lạt ( nhà số 68 đối diện ) 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
697	#ADM-657198	539	\N	\N	650000	0	0	650000	transfer	shipping	Ig mỹ linh [ĐÃ THANH TOÁN]	2026-03-20 12:27:37.287903+00	Ig mỹ linh	0343389986	397 lê lợi, ngô quyền, hp\nNg nhận: mỹ linh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
699	#ADM-777071	541	\N	\N	650000	0	0	650000	transfer	shipping	Ig linh chu [ĐÃ THANH TOÁN]	2026-03-20 12:29:37.205164+00	Ig linh chu	0347070305	Tổ 19 KDL thác Prenn phường 03 Đà Lạt	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
700	#ADM-869638	542	\N	\N	1500000	0	0	1500000	transfer	shipping	Ig quin [ĐÃ THANH TOÁN]	2026-03-20 12:31:09.749472+00	Ig quin	0935185706	Lô C2 chung cư Nguyễn đinh chiểu, Dakao \nSđt: 0935185706 ( Ngân)	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
701	#ADM-042152	540	\N	\N	1050000	0	0	1050000	transfer	shipping	Ig pee pov [ĐÃ THANH TOÁN]	2026-03-20 12:34:02.717158+00	Ig pee pov	0935906826	Hẻm 114 năm châu phường 12 quận tân bình tp hcm Thuỷ Tiên	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
688	#ADM-676264	533	\N	\N	400000	0	0	400000	transfer	returned	Ig jie71104 [ĐÃ THANH TOÁN]	2026-03-19 15:54:36.385946+00	Ig jie71104	0931393787	07 Thai Dương-Phường Thuận An-Tp Huế	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
693	#ADM-067046	537	\N	\N	650000	0	0	650000	transfer	shipping	Ig tú hoàng [ĐÃ THANH TOÁN]	2026-03-20 03:41:07.175165+00	Ig tú hoàng	0933474541	Nguyen huu hao p9 q4	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
702	#ADM-109864	543	\N	\N	700000	0	0	700000	transfer	shipping	Ig hoàng anh pmha [ĐÃ THANH TOÁN]	2026-03-20 12:35:09.996944+00	Ig hoàng anh pmha	0916168968	09 Nguyễn Hữu Huân\nPhường Nha Trang\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
703	#ADM-163706	238	\N	\N	300000	0	0	300000	transfer	shipping	Ig ngô thị an  [ĐÃ THANH TOÁN]	2026-03-20 12:36:03.845556+00	Ig ngô thị an 	092.379.3678	Địa chỉ mới:\nMặt sau số 168 Trần Thủ Độ, Pháp Vân, Hoàng Liệt, Hoàng Mai, Hà Nội\n(ค้นหา 🔍 sân bóng Đại An)	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
704	#ADM-235823	544	\N	\N	650000	0	0	650000	transfer	shipping	Ig shanwydd [ĐÃ THANH TOÁN]	2026-03-20 12:37:15.938903+00	Ig shanwydd	65 88763319 	107 /16 Trương Định, Phường 6, Quận 3, Hồ Chí Minh, Vietnam\nRoom 113, under Arno Anton	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
705	#ADM-914118	540	\N	\N	350000	0	0	350000	transfer	shipping	Ig pee pov  [ĐÃ THANH TOÁN]	2026-03-20 12:48:34.25717+00	Ig pee pov 	0935906826	Hẻm 114 năm châu phường 12 quận tân bình tp hcm\nThuỷ Tiên 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
706	#ADM-045796	545	\N	\N	320000	0	0	320000	transfer	shipping	Ig beiu_pass [ĐÃ THANH TOÁN]	2026-03-21 04:40:45.928695+00	Ig beiu_pass	0373678242	150 đội cấn, ba đình, hà nội\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
707	#ADM-086181	546	\N	\N	1300000	0	0	1300000	transfer	shipping	Ig trần hồng ân [ĐÃ THANH TOÁN]	2026-03-21 04:41:26.306634+00	Ig trần hồng ân	 0932393943	Địa chỉ: 346/7/34/2 Khu phố 1,    Phường Tân Hoà, Tp. Biên Hoà, Đồng Nai	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
708	#ADM-116159	547	\N	\N	350000	0	0	350000	transfer	shipping	Ig b.thehappyyou  [ĐÃ THANH TOÁN]	2026-03-21 04:41:56.256067+00	Ig b.thehappyyou 	0909966195 	Sunshine diamond river\n422 đào trí phú thuận quận 7	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
712	ORD-42881774098019	552	\N	\N	100000	0	20000	120000	banking	cancelled	\N	2026-03-21 13:00:18.859847+00	test preorder 2	0978564302	15 NXK, Xã Tủa Thàng, Huyện Tủa Chùa, Điện Biên		\N	\N	unpaid	\N	2021	620611	\N	\N	\N
711	ORD-33961774097957	551	\N	\N	100000	0	20000	120000	banking	cancelled	\N	2026-03-21 12:59:17.165139+00	test preorder	0979911679	15 NXK, Xã Khánh Thạnh Tân, Huyện Mỏ Cày Bắc, Bến Tre	thiemd779@gmail.com	\N	\N	unpaid	\N	1974	560403	\N	\N	\N
714	ORD-19781774098785	554	\N	\N	100000	0	20000	120000	banking	cancelled	\N	2026-03-21 13:13:04.899889+00	test preorder	0978563489	15 NXK, Xã Thượng Tiến, Huyện Kim Bôi, Hòa Bình	thiemd779@gmail.com	\N	\N	unpaid	\N	2146	230824	\N	\N	\N
709	ORD-89651774071184	548	\N	\N	300000	0	20000	320000	banking	shipping	\N	2026-03-21 05:33:03.563447+00	Thy Thy	0933945837	35/6 đường TMT9, Quận 12, Hồ Chí Minh		\N	SPXVN060601144103	unpaid	\N	1454	21211	\N	\N	\N
710	ORD-11591774092841	550	\N	\N	350000	0	20000	370000	banking	shipping	\N	2026-03-21 11:34:01.227899+00	Ngân	0915249585	2/27a cao thắng, Quận 3, Hồ Chí Minh	ngocngan25899@gmail.com	\N	SPXVN065806877913	unpaid	\N	1444	20305	\N	\N	\N
713	ORD-31381774098746	553	\N	\N	300000	0	20000	320000	banking	shipping	\N	2026-03-21 13:12:25.563901+00	Lương Huyền Trâm	0778063851	566/99 nguyễn thái sơn p6 gò vấp, Quận Gò Vấp, Hồ Chí Minh		\N	SPXVN062222244963	unpaid	\N	1461	21314	\N	\N	\N
715	ORD-12861774099685	555	\N	\N	300000	0	20000	320000	banking	shipping	\N	2026-03-21 13:28:05.0992+00	Nguyễn Trần Lan Anh 	0919799472	123 Nguyễn Chích, Phường Trần Phú, Thành phố Quy Nhơn, Bình Định	anh.lannt153@gmail.com	\N	SPXVN062636199903	unpaid	\N	1662	370115	\N	\N	\N
716	#ADM-039402	556	\N	\N	4900000	0	0	4900000	transfer	shipping	Ig Lauren Brown  [ĐÃ THANH TOÁN]	2026-03-21 13:50:39.865231+00	Ig Lauren Brown 	+1 2897833327	4814 King St, Beamsville, ON L3J 0N5\nEmail: lauren.brown14@live.co.uk	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
717	#ADM-689138	557	\N	\N	400000	0	0	400000	transfer	shipping	Ig sandie  [ĐÃ THANH TOÁN]	2026-03-21 14:01:29.313793+00	Ig sandie 	0368606295	67 nguyễn thị minh khai, bến thành\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
718	#ADM-743693	351	\N	\N	900000	0	0	900000	transfer	shipping	Ig vani [ĐÃ THANH TOÁN]	2026-03-21 14:02:23.827626+00	Ig vani	(+84) 797026555	TPHCM Q TÂN BÌNH P1\n281/36, Lê Văn Sĩ	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
719	#ADM-777410	558	\N	\N	700000	0	0	700000	transfer	shipping	Ig jenny [ĐÃ THANH TOÁN]	2026-03-21 14:02:57.510106+00	Ig jenny	0586898742	283 bến vân đồn q4	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
720	ORD-33271774111656	559	\N	\N	350000	0	20000	370000	banking	shipping	\N	2026-03-21 16:47:35.983433+00	Đặng Phương Thảo	0373334772	Số 1 ngách 42/3 đường Nguyễn Đổng Chi, Nam Từ Liêm, Hà Nội, Phường Cầu Diễn, Quận Nam Từ Liêm, Hà Nội	anna.wilson1177@gmail.com	\N	SPXVN063335672403	unpaid	\N	3440	13001	\N	\N	\N
721	ORD-71621774173028	560	\N	\N	650000	0	20000	670000	banking	shipping	\N	2026-03-22 09:50:28.148611+00	Trương Tuyết Vy	0941659865	174/6 Lê Lai, Phường Bến Thành, Quận 1, Hồ Chí Minh	tuyetvya3pcd@gmail.com	\N	SPXVN061836194663	unpaid	\N	1442	20102	\N	\N	\N
722	ORD-46421774190015	561	\N	\N	3400000	0	20000	3420000	banking	shipping	\N	2026-03-22 14:33:34.779643+00	Don THi Thuy Tien	0389580786	Lô B46 ô số 18 tại khu B, khu đô thị mới Lê Trọng Tấn – Geleximco, Phường Dương Nội, Quận Hà Đông, Hà Nội	linhtinhcuatien@gmail.com	\N	SPXVN064575697513	unpaid	\N	1542	1B1503	\N	\N	\N
723	ORD-92971774192107	562	\N	\N	350000	0	20000	370000	banking	shipping	\N	2026-03-22 15:08:26.94213+00	Khánh Băng	0327161600	29A Lương Minh Nguyệt, Phường Tân Thới Hòa, Quận Tân Phú, Hồ Chí Minh	ngantran224310410.dlsg@gmail.com	\N	SPXVN063615139383	unpaid	\N	1456	21510	\N	\N	\N
724	ORD-97721774192350	563	\N	\N	350000	0	20000	370000	banking	shipping	\N	2026-03-22 15:12:30.344452+00	Hồng Cẩm	0948290496	49 Trường Sơn, Phường 2, Quận Tân Bình, Hồ Chí Minh	camdh96@gmail.com	\N	SPXVN069953270853	unpaid	\N	1455	21402	\N	\N	\N
726	#ADM-061437	137	\N	\N	320000	0	0	320000	transfer	shipping	ig meehgoxcutie  [ĐÃ THANH TOÁN]	2026-03-22 16:14:21.564716+00	ig meehgoxcutie 	0979768986	CityHouse - CD Apartment\n339/24B Đ. Lê Văn Sỹ, Phường 12, Quận 3, Hồ Chí Minh 700000, Vietnam 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
727	#ADM-100867	71	\N	\N	700000	0	0	700000	transfer	shipping	Ig shanwydd [ĐÃ THANH TOÁN]	2026-03-22 16:15:00.989293+00	Ig shanwydd	789515460	Khách ship hoả tốc	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
728	#ADM-204755	565	\N	\N	350000	0	0	350000	transfer	shipping	Ig maize [ĐÃ THANH TOÁN]	2026-03-22 16:16:44.882018+00	Ig maize	+84) 979 528 244	Bcons Green Topaz Đường Tôn Thất Tùng, Phường Đông Hòa, Thành Phố Dĩ An, Bình Dương	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
729	#ADM-230726	566	\N	\N	300000	0	0	300000	transfer	shipping	Ig yen.nhune [ĐÃ THANH TOÁN]	2026-03-22 16:17:10.833633+00	Ig yen.nhune	0779676550	63a điện biên phủ, phường 2, quận bình thạnh ( chung cư ngân hàng ACB ) 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
730	#ADM-254762	567	\N	\N	300000	0	0	300000	transfer	shipping	Ig irene [ĐÃ THANH TOÁN]	2026-03-22 16:17:34.888834+00	Ig irene	0967117904	Địa chỉ: số 297, ấp 4, Phước Lợi, Bến Lức, Long An ( Tây Ninh mới)	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
725	#ADM-029700	564	\N	\N	300000	0	0	300000	transfer	shipping	Ig lăng quỳnh  [ĐÃ THANH TOÁN]	2026-03-22 16:13:49.830728+00	Ig lăng quỳnh 	0393349698	Địa: 122 Trung Hòa, phường Yên Hòa, thành phố Hà Nội, Việt Nam\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
731	#ADM-416475	568	\N	\N	1250000	0	0	1250000	transfer	shipping	Ig ái nhung [ĐÃ THANH TOÁN]	2026-03-22 16:20:16.607746+00	Ig ái nhung	(+84) 777512322	Quan Tan Binh\nPhường 2\n25/21, Đường Cửu Long	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
732	#ADM-546727	569	\N	\N	400000	0	0	400000	transfer	shipping	Ig vani  [ĐÃ THANH TOÁN]	2026-03-22 16:22:26.832451+00	Ig vani 	+0328504510	tổ 29-kp.gia huỳnh -p trảng bàng -tây ninh, Phường Trảng Bàng, Thị Xã Trảng Bàng, Tây Ninh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
734	ORD-59461774236901	571	\N	\N	1000000	0	20000	1020000	banking	shipping	\N	2026-03-23 03:35:00.736617+00	LANGLANG 	0987409832	11/543 Nguyen Trai St. • 11( cạnh 15A)  Ngõ 543 Nguyễn Trãi, P.Thanh Xuân Nam, Phường Thanh Xuân Nam, Quận Thanh Xuân, Hà Nội	ylingyidan@gmail.com	\N	SPXVN064954967933	unpaid	\N	1493	1A0709	\N	\N	\N
745	#ADM-628086	579	\N	\N	300000	0	0	300000	transfer	shipping	Ig bailey  [ĐÃ THANH TOÁN]	2026-03-23 16:17:08.199203+00	Ig bailey 	0357118521	298/28 nơ trang long, p.12, q. Bthanh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
744	#ADM-593967	578	\N	\N	700000	0	0	700000	transfer	shipping	Ig gem gem [ĐÃ THANH TOÁN]	2026-03-23 16:16:34.104971+00	Ig gem gem	 0971994048	Chung cư carillon 7 - số 33 lương minh nguyệt , phường tân thới hoà , quận tân phú	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
743	#ADM-554384	577	\N	\N	350000	0	0	350000	transfer	shipping	Ig ng ot [ĐÃ THANH TOÁN]	2026-03-23 16:15:54.50089+00	Ig ng ot	0794700757 	1468 ấp 1 xã đạo Thạnh thành phố Mỹ tho tỉnh tiền Giang 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
742	#ADM-532841	326	\N	\N	300000	0	0	300000	transfer	shipping	Ig nguyễn phương thảo [ĐÃ THANH TOÁN]	2026-03-23 16:15:32.947478+00	Ig nguyễn phương thảo	0962821709	BS8 The Berverly Solari, Vinhomes Grand Park, phường Long Bình, q9, Thủ Đức, HCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
741	#ADM-500233	251	\N	\N	2200000	0	0	2200000	transfer	shipping	Ig ivywongkaki [ĐÃ THANH TOÁN]	2026-03-23 16:15:00.349149+00	Ig ivywongkaki	0889993313	Nhà văn hoá khu 5- Hải Yên-Móng Cái-Quảng Ninh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
739	#ADM-407066	575	\N	\N	320000	0	0	320000	transfer	shipping	Ig KVK  [ĐÃ THANH TOÁN]	2026-03-23 16:13:27.199358+00	Ig KVK 	0786442110	151/5E hàn hải nguyên p.2 q11\nNg nhận: Thịnh Trương	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
740	#ADM-425282	576	\N	\N	600000	0	0	600000	transfer	shipping	Ig zina [ĐÃ THANH TOÁN]	2026-03-23 16:13:45.4092+00	Ig zina	0949935669	Số 7 năm châu tân bình hcm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
738	#ADM-381422	574	\N	\N	300000	0	0	300000	transfer	shipping	Ig thanh ngan  [ĐÃ THANH TOÁN]	2026-03-23 16:13:01.5935+00	Ig thanh ngan 	0909205514	17/1 phan đình thông phường an lạc, bình tân	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
737	#ADM-631255	573	\N	\N	1450000	0	0	1450000	transfer	shipping	Ig t.laneflow [ĐÃ THANH TOÁN]	2026-03-23 16:00:31.348941+00	Ig t.laneflow	0368086824	Tecco, 6-8 Nguyễn Thiện Thuật, phường Bình Thạnh, Tp HCM\nRoom : 203	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
736	#ADM-543568	540	\N	\N	650000	0	0	650000	transfer	shipping	Ig pee pov  [ĐÃ THANH TOÁN]	2026-03-23 15:59:03.71163+00	Ig pee pov 	0935906826	Hẻm 114 năm châu phường 12 quận tân bình tp hcm\nThuỷ Tiên	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
735	#ADM-439331	572	\N	\N	350000	0	0	350000	transfer	shipping	ig Jeongbeen Seo [ĐÃ THANH TOÁN]	2026-03-23 15:57:19.467402+00	Jeongbeen Seo	+82 1087573181	jbeen030@naver.com\n\nAddress\n-State/Province: Seoul\n-City: Songpa-gu\n-House number / Street name: Room 318, 3F, Sangsang Class Jamsil Branch, 18-23, Olympic-ro 32-gil\n-Zip code:05548	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
733	ORD-45591774230182	570	\N	\N	350000	0	20000	370000	banking	shipping	\N	2026-03-23 01:43:01.928115+00	Kiều Chinh	0971325517	Cc Đông Hải, Phường Tân Chánh Hiệp, Quận 12, Hồ Chí Minh	kieuchinh1604@gmail.com	\N	\N	unpaid	\N	1454	21204	\N	\N	\N
750	ORD-85471774355256	584	\N	\N	300000	0	20000	320000	banking	completed	\N	2026-03-24 12:27:35.825509+00	Thuỳ anh	0968953341	25/27 Trương Văn Thành, Phường Hiệp Phú, Thành phố Thủ Đức, Thành phố Hồ Chí Minh, Phường Hiệp Phú, Thành Phố Thủ Đức, Hồ Chí Minh	thuyanhphanq123@gmail.com	\N	SPXVN063020227263	unpaid	\N	3695	90754	\N	\N	\N
749	#ADM-979421	583	\N	\N	620000	0	0	620000	transfer	shipping	Ig tiên tiên [ĐÃ THANH TOÁN]	2026-03-24 05:26:19.522325+00	Ig tiên tiên	0948627026	Block B2, Chung cư Boulevard, đường Nguyễn Lương Bằng, Phường Phú Mỹ, Quận 7, Thành phố Hồ Chí Minh.	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
751	#ADM-310973	585	\N	\N	700000	0	0	700000	transfer	shipping	Ig huỳnh ngọc bảo ngân [ĐÃ THANH TOÁN]	2026-03-24 13:18:31.069439+00	Ig huỳnh ngọc bảo ngân	0909676790	87/2E Trung Mỹ Tây, Trung Chánh, Hóc Môn, Tp.HCM\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
752	#ADM-364429	586	\N	\N	1000000	0	0	1000000	transfer	shipping	Ig n zy [ĐÃ THANH TOÁN]	2026-03-24 13:19:24.532353+00	Ig n zy	0363760545	44 nguyễn trọng trí, phường an lạc a, quận bình Tân	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
753	#ADM-412044	71	\N	\N	600000	0	0	600000	transfer	shipping	Ig rlrde9 [ĐÃ THANH TOÁN]	2026-03-24 13:20:12.151537+00	Ig rlrde9	789515460	khách đặt ship hoả tốc 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
754	#ADM-445667	238	\N	\N	300000	0	0	300000	transfer	shipping	Ig ngô thị an [ĐÃ THANH TOÁN]	2026-03-24 13:20:45.789417+00	Ig ngô thị an	092.379.3678	Mặt sau số 168 Trần Thủ Độ, Pháp Vân, Hoàng Liệt, Hoàng Mai, Hà Nội\n(ค้นหา 🔍 sân bóng Đại An)	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
755	#ADM-486909	587	\N	\N	1050000	0	0	1050000	transfer	shipping	Ig van le [ĐÃ THANH TOÁN]	2026-03-24 13:21:27.110121+00	Ig van le	0919880890	S6 office 02-14 The sun avenue, \n28 mai chí thọ, an phú, thủ Đức	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
747	#ADM-919458	581	\N	\N	320000	0	0	320000	transfer	shipping	Jialina.sb [ĐÃ THANH TOÁN]	2026-03-24 05:25:19.597559+00	Jialina.sb	(+84) 866 641 535	Nhà Nghỉ Thanh Trà 2, Ngách 20/105 Doãn Kế Thiện Phường Mai Dịch, Quận Cầu Giấy, Hà Nội\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
748	#ADM-950234	582	\N	\N	350000	0	0	350000	transfer	shipping	Ig followdao2222 [ĐÃ THANH TOÁN]	2026-03-24 05:25:50.335928+00	Ig followdao2222	 0399749576	Đchi: 29 trần nguyên hãn, phường đông thọ, thành phố thanh hoá	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
756	#ADM-903282	588	\N	\N	950000	0	0	950000	transfer	shipping	Ig aiden.C  [ĐÃ THANH TOÁN]	2026-03-24 13:45:03.50135+00	Ig aiden.C 	0965592198	19 hồ tùng mậu, mai dịch, cầu giấy hn\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
758	ORD-37891774407082	477	\N	\N	1290000	0	20000	1310000	banking	shipping	\N	2026-03-25 02:51:22.344138+00	SHUNFEI （#43301）	0383163470	 Số 160/46 Phan huy ích ，Phường 12 ，quận Gò Vấp TP Hồ Chí Minh, Phường 12, Quận Gò Vấp, Hồ Chí Minh	jamiefong0213@gmail.com	\N	SPXVN062565155543	unpaid	\N	1461	21308	\N	\N	\N
746	ORD-72331774288550	580	\N	\N	350000	0	20000	370000	banking	completed	\N	2026-03-23 17:55:50.435517+00	Triệu Minh	0905237120	148 Nguyễn Thị Minh Khai, Phường Tân Tiến, Thành phố Nha Trang, Khánh Hòa	trieuminh13199@gmail.com	\N	SPXVN069225768643	unpaid	\N	1548	91590	\N	\N	\N
757	ORD-99491774369594	589	\N	\N	250000	0	20000	270000	banking	shipping	\N	2026-03-24 16:26:34.323537+00	Mai Hương	0898215310	222 Pasteur, Phường Võ Thị Sáu, Quận 3, Hồ Chí Minh	huongtee39@gmail.com	\N	SPXVN067182462683	unpaid	\N	1444	90795	\N	\N	\N
759	ORD-93741774417460	590	\N	\N	750000	0	20000	770000	banking	shipping	\N	2026-03-25 05:44:20.190497+00	Nguyễn Ngọc Bảo Trân 	0393788221	165-167 Phan Đình Phùng , Phường 2, Thành phố Đà Lạt, Lâm Đồng	baotran.joellenguyen12@gmail.com	\N	SPXVN063682783183	unpaid	\N	1550	420105	\N	\N	\N
765	#ADM-469239	595	\N	\N	750000	0	0	750000	transfer	cancelled	Ig yeeling18_  [ĐÃ THANH TOÁN]	2026-03-25 12:57:49.331613+00	Ig yeeling18_ 	 0178763508	15 Jalan Batu Nilam 26 Bandar Bukit Tinggi 2 Klang Selangor Malaysia 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
760	#ADM-266310	55	\N	\N	320000	0	0	320000	transfer	shipping	Ig bowbkk.staff [ĐÃ THANH TOÁN]	2026-03-25 12:54:26.457286+00	Ig bowbkk.staff	0369166.222	163 Trương Thị Hoa, phường Tân Thới Hiệp, Quận 12, thành phố Hồ Chí Minh\n  ( Người Nhận BN2705)	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
761	#ADM-305647	591	\N	\N	300000	0	0	300000	transfer	shipping	Ig phirun [ĐÃ THANH TOÁN]	2026-03-25 12:55:05.750827+00	Ig phirun	0906.984.493	275/14B1 Đặng Nguyên Cẩn, Phường Phú Lâm, TP. Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
762	#ADM-343492	592	\N	\N	300000	0	0	300000	transfer	shipping	Ig tran thi my tuyen [ĐÃ THANH TOÁN]	2026-03-25 12:55:43.583221+00	Ig tran thi my tuyen	0938603662	Chung cư The Grande M5 Midtown\nĐường số 16, P Tân Phú, Q7 tphcm (Block A, Căn A18.11) (Đc cũ)	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
763	#ADM-363808	593	\N	\N	400000	0	0	400000	transfer	shipping	Ig tracy vo [ĐÃ THANH TOÁN]	2026-03-25 12:56:03.899569+00	Ig tracy vo	0766865000	Tổ dân phố yên trung ,phường yên sơn ninh bình	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
764	#ADM-414579	594	\N	\N	620000	0	-620000	0	transfer	shipping	Ig kim anh tran  [ĐÃ THANH TOÁN]	2026-03-25 12:56:54.676317+00	Ig kim anh tran 	0336585212	98 Cồn Dầu 19, phường Hoà Xuân, TP Đà Nẵng\nKOL TẶNG ĐỒ	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
766	#ADM-532341	596	\N	\N	750000	0	0	750000	transfer	shipping	Ig yeeling18_  [ĐÃ THANH TOÁN]	2026-03-25 12:58:52.434982+00	Ig yeeling18_ 	0178763508	15 Jalan Batu Nilam 26 Bandar Bukit Tinggi 2 Klang Selangor Malaysia 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
767	#ADM-575528	597	\N	\N	1450000	0	0	1450000	transfer	shipping	Ig im4iden [ĐÃ THANH TOÁN]	2026-03-25 12:59:35.624667+00	Ig im4iden	0397317719	104 lê trọng tấn , tây thạnh , tân phú \n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
768	#ADM-607610	598	\N	\N	700000	0	0	700000	transfer	shipping	Ig grace thường [ĐÃ THANH TOÁN]	2026-03-25 13:00:07.697531+00	Ig grace thường	0586670080	58 Quốc Hương, B08.06, Thao Dien	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
769	#ADM-631843	599	\N	\N	300000	0	0	300000	transfer	shipping	Ig yogingngoc_1908 [ĐÃ THANH TOÁN]	2026-03-25 13:00:31.929081+00	Ig yogingngoc_1908	0975557678	34/4/1 nguyễn thị huê đông lân bà điểm hóc môn	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
770	#ADM-679861	591	\N	\N	650000	0	0	650000	transfer	shipping	Ig phirun [ĐÃ THANH TOÁN]	2026-03-25 13:01:20.523513+00	Ig phirun	0906.984.493	275/14B1 Đặng Nguyên Cẩn, Phường Phú Lâm, TP. Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
771	#ADM-106015	71	\N	\N	950000	0	0	950000	transfer	shipping	Ig xue ting tan [ĐÃ THANH TOÁN]	2026-03-25 13:08:26.160186+00	Ig xue ting tan	789515460	7 Ngo Van Nam Street, Ben Nghe Ward, District 1, Ho Chi Minh City, Vietnam	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
785	#ADM-301558	5	\N	\N	400000	0	0	400000	transfer	returned	[ĐÃ THANH TOÁN]	2026-03-26 12:48:21.0043+00	test	0979911670	Tại quầy	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
772	#ADM-876926	600	\N	\N	400000	0	0	400000	transfer	shipping	Ig khả dinh  [ĐÃ THANH TOÁN]	2026-03-26 12:07:57.050377+00	Ig khả dinh 	0838121036 	Công ty Phú Thành, Xã Vĩnh Hải, Tp Sóc Trăng	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
773	#ADM-913996	601	\N	\N	650000	0	0	650000	transfer	shipping	Ig huonghtnt [ĐÃ THANH TOÁN]	2026-03-26 12:08:34.092343+00	Ig huonghtnt	0389069723	TDP Hải Thế, Phường Phong Quảng, Thành Phố Huế	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
774	#ADM-010011	573	\N	\N	620000	0	0	620000	transfer	shipping	Ig t.laneflow  [ĐÃ THANH TOÁN]	2026-03-26 12:10:10.130744+00	Ig t.laneflow 	0368086824	Tecco, 6-8 Nguyễn Thiện Thuật, phường Bình Thạnh, Tp HCM\nRoom : 203	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
775	#ADM-125619	241	\N	\N	620000	0	0	620000	transfer	shipping	Ig ngoc phuc [ĐÃ THANH TOÁN]	2026-03-26 12:12:05.737736+00	Ig ngoc phuc	0703929339	Chung cư Sky89- đường lê thị chợ- phường phú thuận- quận 7	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
776	#ADM-373160	602	\N	\N	1500000	0	0	1500000	transfer	shipping	ig Amy Lupercio  [ĐÃ THANH TOÁN]	2026-03-26 12:16:13.304557+00	ig Amy Lupercio 	(425)263-7069	\n1235 E 43rd St Los Angeles, CA \n90011\nsuppamyyy@gmail.com	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
777	#ADM-446520	603	\N	\N	650000	0	0	650000	transfer	shipping	Ig _beebowwbeww_ [ĐÃ THANH TOÁN]	2026-03-26 12:17:26.636668+00	Ig _beebowwbeww_	0388874407	18 Nguyễn văn trỗi, phường Tân An, thị xã La Gi, Tỉnh Bình Thuận	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
778	#ADM-469892	54	\N	\N	300000	0	0	300000	transfer	shipping	Ig nhee nhee [ĐÃ THANH TOÁN]	2026-03-26 12:17:50.016431+00	Ig nhee nhee	0396994800	Số 38 đường D4, phường chánh nghĩa, thành phố thủ dầu một, bình dương	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
779	#ADM-497477	604	\N	\N	750000	0	0	750000	transfer	shipping	Ig trần ngọc quyên [ĐÃ THANH TOÁN]	2026-03-26 12:18:17.581584+00	Ig trần ngọc quyên	0924686789	245/30F Bình Lợi p13, bình thạnh.	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
780	#ADM-523234	462	\N	\N	350000	0	0	350000	transfer	shipping	Ig jasmine [ĐÃ THANH TOÁN]	2026-03-26 12:18:43.349964+00	Ig jasmine	0934040535	100/15 dương bá trạc p2 q8	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
781	#ADM-546832	605	\N	\N	300000	0	0	300000	transfer	shipping	Ig do thi thuy trang [ĐÃ THANH TOÁN]	2026-03-26 12:19:06.947505+00	Ig do thi thuy trang	0987838370	263/11 lê văn việt phường hiệp phú quận 9 ( phường mới tăng nhơn phú )	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
782	#ADM-573454	606	\N	\N	350000	0	0	350000	transfer	shipping	Tran phuong sol [ĐÃ THANH TOÁN]	2026-03-26 12:19:33.591226+00	Tran phuong sol	0363331143	87 Nguyễn Cơ Thạch , kdt Sala, p An Khánh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
783	#ADM-617083	607	\N	\N	300000	0	0	300000	transfer	shipping	Ig lynn [ĐÃ THANH TOÁN]	2026-03-26 12:20:17.186862+00	Ig lynn	0947704089	41F/25, Đ. Đặng Thuỳ Trâm, Phường 13, Bình Lợi Trung, Hồ Chí Minh 700000	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
784	#ADM-640527	608	\N	\N	300000	0	0	300000	transfer	shipping	Ig 9pass99 [ĐÃ THANH TOÁN]	2026-03-26 12:20:40.63169+00	Ig 9pass99	038869989	Chung cư Grand Riverside , 283 Bến Vân đồn , Phường 2 , Q4, HCM 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
786	#ADM-544759	609	\N	\N	300000	0	0	300000	transfer	shipping	Ig pham hong phuong [ĐÃ THANH TOÁN]	2026-03-26 13:09:04.864769+00	Ig pham hong phuong	0942388188	572/12/4 âu cơ p10 tân bình hcm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
787	#ADM-596121	610	\N	\N	300000	0	0	300000	transfer	shipping	Ig đàm trang [ĐÃ THANH TOÁN]	2026-03-26 14:33:16.247932+00	Ig đàm trang	0355094855	B1104, Toà B Udic Complex Hoàng Đạo Thuý, Trung Hoà, Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
788	#ADM-939576	611	\N	\N	620000	0	0	620000	transfer	shipping	Ig duong [ĐÃ THANH TOÁN]	2026-03-26 16:35:39.719762+00	Ig duong	0962522440	290/34/12 đường hiệp thành 13 quận 12 , phường tân thới hiệp	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
789	#ADM-017404	612	\N	\N	600000	0	0	600000	transfer	shipping	Ig ngoc anh [ĐÃ THANH TOÁN]	2026-03-26 16:36:57.506297+00	Ig ngoc anh	0964989250	275 Nguyễn Trãi- Thanh Xuân - Hn 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
790	#ADM-141071	612	\N	\N	350000	0	0	350000	transfer	shipping	Ig ngoc anh [ĐÃ THANH TOÁN]	2026-03-26 16:39:01.210234+00	Ig ngoc anh	0964989250	275 Nguyễn Trãi- Thanh Xuân - Hn	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
793	#ADM-440239	594	\N	\N	300000	0	-300000	0	transfer	shipping	Ig kim anh tran  [ĐÃ THANH TOÁN]	2026-03-27 12:10:40.401208+00	Ig kim anh tran 	0336585212	98 Cồn Dầu 19, phường Hoà Xuân, TP Đà Nẵng\nKOL TẶNG ĐỒ	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
794	#ADM-477251	511	\N	\N	300000	0	0	300000	transfer	shipping	Ig miuiuuuuu [ĐÃ THANH TOÁN]	2026-03-27 12:11:17.499857+00	Ig miuiuuuuu	0962875123	85 Hàng Bạc Hoàn Kiếm Hà Nội\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
795	#ADM-551411	615	\N	\N	1400000	0	0	1400000	transfer	shipping	Ig p.khmyy [ĐÃ THANH TOÁN]	2026-03-27 12:12:31.539904+00	Ig p.khmyy	0988668664	19 hùng duệ vương , hồng bàng hải phòng 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
796	#ADM-614011	616	\N	\N	650000	0	0	650000	transfer	shipping	Ig Lquinn [ĐÃ THANH TOÁN]	2026-03-27 12:13:34.143599+00	Ig Lquinn	0369236444	203/19/2 hẻm hàm nghi phường duy tân tp kontum 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
797	#ADM-644954	238	\N	\N	320000	0	0	320000	transfer	shipping	Ig jenny  [ĐÃ THANH TOÁN]	2026-03-27 12:14:05.094061+00	Ig jenny 	092.379.3678	 Mặt sau số 168 Trần thủ độ, Pháp vân , Hoàng liệt , Hoàng mai , Hà nội.	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
798	#ADM-678462	617	\N	\N	650000	0	0	650000	transfer	shipping	Ig dieuryu76 [ĐÃ THANH TOÁN]	2026-03-27 12:14:38.570612+00	 Ig dieuryu76	0943071567	Xóm 4, xã xuân tiến, huyện Xuân trường, tp Nam định	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
1251	ORD-36201776179468	971	\N	\N	300000	0	0	300000	banking	shipping	\N	2026-04-14 15:11:08.481826+00	Lương Thị Bích Phượng	0707707878	305 Võ Thành Trang, Phường 11, Quận Tân Bình, Hồ Chí Minh	luongphuong3444@gmail.com	\N	SPXVN061885654724	unpaid	\N	1455	21411	2026-04-14 15:32:14.742+00	\N	\N
800	#ADM-742823	273	\N	\N	650000	0	0	650000	transfer	shipping	Ig qingyi [ĐÃ THANH TOÁN]	2026-03-27 12:15:43.031221+00	Ig qingyi	0396504228	Số 51, ngõ 31, B6 Khu nhà ở Mai Dịch, đường Nguyễn Khả Trạc, Phường Phú Diễn, Thành phố Hà Nội, Việt Nam (phường Mai Dịch, Cầu Giấy cũ)	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
801	#ADM-802138	619	\N	\N	1600000	0	0	1600000	transfer	shipping	0969178898 [ĐÃ THANH TOÁN]	2026-03-27 12:16:42.260476+00	0969178898	Ig trang vy	P503, số 6 Nguyễn Công Hoan, Ngọc Khánh, Ba Đình, Hà Nội (Chung cư Platinum)	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
802	#ADM-831363	620	\N	\N	300000	0	0	300000	transfer	shipping	Ig thục yến [ĐÃ THANH TOÁN]	2026-03-27 12:17:11.476346+00	Ig thục yến	0938859589	85B bà hom p13 q6	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
803	#ADM-866204	621	\N	\N	650000	0	0	650000	transfer	shipping	0764506174 [ĐÃ THANH TOÁN]	2026-03-27 12:17:46.309264+00	0764506174	Ig win	50 lê thiện trị , hoà hải , ngũ hành sơn đà nẵng	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
804	#ADM-894583	622	\N	\N	650000	0	0	650000	transfer	shipping	Ig kim anh [ĐÃ THANH TOÁN]	2026-03-27 12:18:14.701287+00	Ig kim anh	0775036405	290/51/36a Nơ Trang Long p12 quận Bình Thạnh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
805	#ADM-916821	623	\N	\N	300000	0	0	300000	transfer	shipping	Ig khánh linh [ĐÃ THANH TOÁN]	2026-03-27 12:18:36.929137+00	Ig khánh linh	0824097890	56A Ng. 619 Vũ Tông Phan Khương Đình Thanh Xuân Hà Nội 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
806	#ADM-935142	545	\N	\N	300000	0	0	300000	transfer	shipping	Ig beiu_pass [ĐÃ THANH TOÁN]	2026-03-27 12:18:55.259102+00	Ig beiu_pass	0373678242	150 đội cấn, ba đình, hà nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
807	#ADM-959155	624	\N	\N	300000	0	0	300000	transfer	shipping	Ig MJ [ĐÃ THANH TOÁN]	2026-03-27 12:19:19.278731+00	Ig MJ	0886493061	278a nguyễn đình chiểu, q3 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
808	#ADM-982508	625	\N	\N	320000	0	0	320000	transfer	shipping	Bảo bối [ĐÃ THANH TOÁN]	2026-03-27 12:19:42.631298+00	Bảo bối	0828392000	17 ngõ 31/21 nguyễn cao hbt hn	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
792	ORD-45131774585598	614	\N	\N	600000	0	20000	620000	banking	shipping	\N	2026-03-27 04:26:37.642912+00	Nguyễn Kim Hoàng Hà 	0965584096 	Số 14 ngõ 217, định công thượng, hoàng mai, hà nội, Phường Định Công, Quận Hoàng Mai, Hà Nội	ilovebanhmino.1@gmail.com	\N	SPXVN068141384053	unpaid	\N	1490	1A0802	\N	\N	\N
810	#ADM-862470	627	\N	\N	850000	0	0	850000	transfer	shipping	Rose Rosalie [ĐÃ THANH TOÁN]	2026-03-27 13:57:42.643498+00	Rose Rosalie	 0898650608	Hotel: CityHouse - Nest DC\n361/12 Nguyễn Đình Chiểu,\nPhường 5, Bàn Cờ, Hồ Chí Minh\n700000\nRoom:101 \nName: Rose Rosalie	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
809	ORD-19041774617297	626	\N	\N	650000	0	20000	670000	banking	shipping	\N	2026-03-27 13:14:57.462626+00	Nguyễn Anh Thư	0913969687	78/22/35 Tôn Thất Thuyết, Phường 16, Quận 4, Hồ Chí Minh	anhthung2011@gmail.com	\N	SPXVN062230326033	unpaid	\N	1446	20414	\N	\N	\N
811	#ADM-587380	628	\N	\N	950000	0	0	950000	transfer	shipping	Ig rose [ĐÃ THANH TOÁN]	2026-03-27 14:43:07.50841+00	Ig rose	(+84) 902 456 158	Tháp Hawaii - Đảo Kim Cương (H0507), Phường Bình Trưng Tây, Thành Phố Thủ Đức, TP. Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
812	ORD-65971774634455	629	\N	\N	300000	0	20000	320000	banking	shipping	\N	2026-03-27 18:00:55.456997+00	Hoàng Oanh	0866063740	1163/16 Lê Đức Thọ phường 13 quận Gò Vấp, Phường 13, Quận Gò Vấp, Hồ Chí Minh	oanhnvh0311@gmail.com	\N	SPXVN069801424013	unpaid	\N	1461	21309	\N	\N	\N
813	#ADM-225442	630	\N	\N	650000	0	0	650000	transfer	shipping	Ig my võ  [ĐÃ THANH TOÁN]	2026-03-28 04:13:45.59261+00	Ig my võ 	 0939806696	696 Trần Hưng Đạo, p.2, Q.5, tp.hcm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
815	#ADM-491483	632	\N	\N	320000	0	0	320000	transfer	shipping	Ig thi [ĐÃ THANH TOÁN]	2026-03-28 04:51:32.082043+00	Ig thi	 0334407364	261/40/2, Chu Văn An, Phường 12, Quận Bình Thạnh, TP. Hồ Chí Minh\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
814	ORD-21671774673016	631	\N	\N	1650000	0	20000	1670000	banking	shipping	\N	2026-03-28 04:43:35.851222+00	Fifi Kuan	‪+84 90 622 92 35‬ ‬	63a Đ. Nguyễn Cừ, Phường An Khánh, Quận 2, Hồ Chí Minh	fifikuan0427@gmail.com	\N	SPXVN068908486143	unpaid	\N	1443	20201	\N	\N	\N
816	#ADM-131766	633	\N	\N	650000	0	0	650000	transfer	shipping	Ig camii.ng  [ĐÃ THANH TOÁN]	2026-03-28 05:18:52.245713+00	Ig camii.ng 	0374440182	64 Trung tả ,văn miếu quốc tử giám hà nội \nSđt : 0374440182\nTên : Thảo vân	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
818	#ADM-180456	251	\N	\N	620000	0	0	620000	transfer	shipping	Ig 🧚‍♀️ [ĐÃ THANH TOÁN]	2026-03-28 09:29:40.642532+00	Ig 🧚‍♀️`	0889993313	Nhà văn hoá khu 5- Hải Yên-Móng Cái-Quảng Ninh .   Tabg tang	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
791	ORD-50901774551629	613	\N	\N	620000	0	20000	640000	banking	shipping	\N	2026-03-26 19:00:28.94246+00	Hoàng Thư	0918158185	87B/17 Kp1, Phường Tam Hòa, Thành phố Biên Hòa, Đồng Nai	thuhoag12345678@gmail.com	\N	SPXVN061728393713	unpaid	\N	1536	480112	\N	\N	\N
799	#ADM-713755	618	\N	\N	300000	0	0	300000	transfer	returned	Ig hari lăng quăng [ĐÃ THANH TOÁN]	2026-03-27 12:15:13.935509+00	Ig hari lăng quăng	0982650780	chợ quảng sơn , ninh sơn ninh thuận	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
817	ORD-66701774681551	634	\N	\N	350000	0	20000	370000	banking	shipping	\N	2026-03-28 07:05:50.900832+00	Vân Anh	0964102004	161/31/28 đường Đông Hưng Thuận 02, khu phố 62, Phường Đông Hưng Thuận, Quận 12, Hồ Chí Minh	blva0410@gmail.com	\N	SPXVN061012289683	unpaid	\N	1454	21202	\N	\N	\N
819	#ADM-290832	581	\N	\N	300000	0	0	300000	transfer	shipping	Ig jialina.sb [ĐÃ THANH TOÁN]	2026-03-28 09:31:31.007324+00	Ig jialina.sb	(+84) 866 641 535	Nhà Nghỉ Thanh Trà 2, Ngách 20/105 Doãn Kế Thiện Phường Mai Dịch, Quận Cầu Giấy, Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
820	#ADM-327469	636	\N	\N	320000	0	0	320000	transfer	shipping	Ig _neverchaseabitch_00 [ĐÃ THANH TOÁN]	2026-03-28 09:32:07.611627+00	Ig _neverchaseabitch_00	0827405569	 ccmn 1092 nguyễn khoái, thanh trì, hoàng mai, hà nội ạ\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
821	#ADM-358231	637	\N	\N	300000	0	0	300000	transfer	shipping	Ig như thảo [ĐÃ THANH TOÁN]	2026-03-28 09:32:38.589029+00	Ig như thảo	0392178841 	461/16 Hải Phòng, P. Chính Gián, Q.Thanh Khê, TP Đà Nẵng	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
822	#ADM-395253	638	\N	\N	300000	0	0	300000	transfer	shipping	ig J. [ĐÃ THANH TOÁN]	2026-03-28 09:33:15.39328+00	ig J.	 0907867994 	Block B eco green q7 nha ạ	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
823	#ADM-451668	639	\N	\N	950000	0	0	950000	transfer	shipping	Ig tú an / sapo [ĐÃ THANH TOÁN]	2026-03-28 09:34:11.793104+00	Ig tú an / sapo	0348893881	33 lê minh xuân p7 tân bình	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
824	#ADM-504390	640	\N	\N	300000	0	0	300000	transfer	shipping	ig Lê hồng bảo trân / sapo [ĐÃ THANH TOÁN]	2026-03-28 09:35:04.4969+00	ig Lê hồng bảo trân / sapo	0844488829	277 Võ Nguyên Giáp, An Phú, An Khánh, Hồ Chí Minh 70000\neast tower 2907\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
825	#ADM-458586	641	\N	\N	650000	0	0	650000	transfer	shipping	Ig anh.trn / sapo [ĐÃ THANH TOÁN]	2026-03-28 11:30:58.770156+00	Ig anh.trn / sapo	0348284747	525/15 Quang Trung, P10 Gò Vấp\nNgọc Anh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
826	#ADM-522173	642	\N	\N	320000	0	0	320000	transfer	shipping	Ig tuyết linh / sapo [ĐÃ THANH TOÁN]	2026-03-28 11:32:02.311787+00	Ig tuyết linh / sapo	 0358476051	217/70/35 bùi đình tuý,p24, bình thạnh, HCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
847	#ADM-327129	660	\N	\N	300000	0	0	300000	transfer	shipping	Ig mai thanh [ĐÃ THANH TOÁN]	2026-03-29 13:02:07.251566+00	Ig mai thanh	0528593977 	Đường 27 giữa ngã tư số 8 và 10. Nhà tuyền đồ mỹ Xã Nghĩa Thành, Huyện Châu Đức, Bà Rịa Vũng Tàu	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
845	#ADM-000748	658	\N	\N	600000	0	0	600000	transfer	shipping	Ig doanvananhh [ĐÃ THANH TOÁN]	2026-03-29 12:56:40.856522+00	Ig doanvananhh	0967 771 771  	50/6 khu phố 2, đường Bà Triệu, Hóc Môn ( hẻm đối diện HD bank) \nSdt 0967 771 771  (Huy)\n50/6 khu phố 2, đường Bà Triệu, Hóc Môn ( hẻm đối diện HD bank) \n\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
827	#ADM-041905	643	\N	\N	320000	0	0	320000	transfer	shipping	Ig NT phương thảo [ĐÃ THANH TOÁN]	2026-03-29 11:50:42.06501+00	Ig NT phương thảo	0916240805	Xóm 13 vĩnh trà nam\nTrung tiền hải thái bình	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
828	#ADM-295669	644	\N	\N	920000	0	0	920000	transfer	shipping	Ig huy lâm [ĐÃ THANH TOÁN]	2026-03-29 11:54:55.821513+00	Ig huy lâm	0938144013	73/18 huynh van banh\nP17 phu nhuan	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
846	#ADM-042491	659	\N	\N	750000	0	0	750000	transfer	shipping	Ig nguyễn kim huệ [ĐÃ THANH TOÁN]	2026-03-29 12:57:22.602776+00	Ig nguyễn kim huệ /Sapo	0903029673	số 71 đường số 3 phường an khánh tp thủ đức ( quận 2 )\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
844	#ADM-965386	657	\N	\N	600000	0	0	600000	transfer	shipping	Ig yeolan [ĐÃ THANH TOÁN]	2026-03-29 12:56:05.517062+00	Ig yeolan	0974250498 	Chung cư Pegasuite 2, 1079 tạ quang bửu, p6, q8, HCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
843	#ADM-819255	55	\N	\N	600000	0	0	600000	transfer	shipping	Ig bowbkk.staff / sapo [ĐÃ THANH TOÁN]	2026-03-29 12:53:39.425557+00	Ig bowbkk.staff / sapo	0369166.222	( BN2705)\n163 Trương Thị Hoa, phường Tân Thới Hiệp, Quận 12, thành phố Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
842	#ADM-652664	656	\N	\N	350000	0	0	350000	transfer	shipping	Ig yến nhi [ĐÃ THANH TOÁN]	2026-03-29 12:50:52.79916+00	Ig yến nhi	0386683498	17/9 đường 59 phường thảo điền quan 2\nIg yến nhi\n17/9 đường 59 phường thảo điền quan 2\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
841	#ADM-622136	655	\N	\N	600000	0	0	600000	transfer	shipping	Ig vũ thị kiều trinh / Sapo [ĐÃ THANH TOÁN]	2026-03-29 12:50:22.252357+00	Ig vũ thị kiều trinh / Sapo	0835116169	39 Bến Vân Đồn, Phường 13, Quận 4, Hồ Chí Minh\nChung cư The Tresor \nSảnh Ap1 2806	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
840	#ADM-549773	558	\N	\N	600000	0	0	600000	transfer	shipping	Ig jenny q4 / Sapo [ĐÃ THANH TOÁN]	2026-03-29 12:49:09.912125+00	Ig jenny q4 / Sapo	0586898742	283 bến vân đồn q4\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
839	#ADM-115927	654	\N	\N	300000	0	0	300000	transfer	shipping	Ig uyenahh [ĐÃ THANH TOÁN]	2026-03-29 12:41:56.055769+00	Ig uyenahh	0979879425	204/3B Cao Đạt F1 Q5 HCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
838	#ADM-063904	71	\N	\N	300000	0	0	300000	transfer	shipping	Ig 2ndhnngan / Sapo [ĐÃ THANH TOÁN]	2026-03-29 12:41:04.073555+00	Ig 2ndhnngan / Sapo	789515460	Khách ghé lấy	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
837	#ADM-004870	653	\N	\N	650000	0	0	650000	transfer	shipping	Ig myoiw [ĐÃ THANH TOÁN]	2026-03-29 12:40:05.001105+00	Ig myoiw	0336323793	41/1 trần hưng đạo, p6 , thành phố mỹ tho\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
836	#ADM-977760	652	\N	\N	320000	0	0	320000	transfer	shipping	Ig prv.sushiwasabi [ĐÃ THANH TOÁN]	2026-03-29 12:39:37.880891+00	Ig prv.sushiwasabi	0919686592	•Chung cư Tây Đô plaza , Xã Tân Phú Thạnh, Huyện Châu Thành A, Hậu Giang	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
835	#ADM-941483	651	\N	\N	300000	0	0	300000	transfer	shipping	Ig cao nguyen dang khoa/ sapo [ĐÃ THANH TOÁN]	2026-03-29 12:39:01.602405+00	Ig cao nguyen dang khoa/ sapo	0942879351	429 Hoàng Hữu Nam Long Bình TP. Thủ Đức	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
834	#ADM-896432	650	\N	\N	300000	0	0	300000	transfer	shipping	Ig trâm lê [ĐÃ THANH TOÁN]	2026-03-29 12:38:16.564826+00	Ig trâm lê	0389717351	80/3 phan đình phùng pleiku gia lai \n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
833	#ADM-874995	649	\N	\N	1520000	0	0	1520000	transfer	shipping	Ig _klhm [ĐÃ THANH TOÁN]	2026-03-29 12:37:55.129607+00	Ig _klhm	+886 928273350	9-23 Lam Son Square, Bến Nghé, Sài Gòn, Hồ Chí Minh, Vietnam	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
832	#ADM-777532	648	\N	\N	300000	0	0	300000	transfer	shipping	Ig hoàng lan anh [ĐÃ THANH TOÁN]	2026-03-29 12:36:17.647129+00	Ig hoàng lan anh	0966079275	Số 35 ngách 123/41 Xuân Phương, Phương Canh, Nam Từ Liêm, Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
831	#ADM-639116	647	\N	\N	300000	0	0	300000	transfer	shipping	Ig minh ngọc [ĐÃ THANH TOÁN]	2026-03-29 12:00:39.302952+00	Ig minh ngọc	‭‭+84 38 4045461‬‬	Ấp tân hiệp A, thị trấn Óc Eo, huyện Thoại Sơn, tỉnh An Giang	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
830	#ADM-569648	646	\N	\N	3370000	0	0	3370000	transfer	shipping	Ig nancy do [ĐÃ THANH TOÁN]	2026-03-29 11:59:29.768198+00	Ig nancy do	0397135528	 67B đường T5, phường Tây Thạnh, quận Tân Phú	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
912	#ADM-891550	705	\N	\N	1320000	0	0	1320000	transfer	shipping	Ig nhittlam [ĐÃ THANH TOÁN]	2026-03-31 14:38:11.646919+00	Ig nhittlam	0968081005	94A phạm đình hổ p2 q6	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
829	#ADM-387210	645	\N	\N	1150000	0	0	1150000	transfer	shipping	Ig kimberly nguyễn [ĐÃ THANH TOÁN]	2026-03-29 11:56:27.331283+00	Ig kimberly nguyễn / Sapo	0939968676	422 võ văn kiệt, phường cầu ông lãnh q1.	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
848	#ADM-373711	661	\N	\N	600000	0	0	600000	transfer	shipping	Ig kim hạnh [ĐÃ THANH TOÁN]	2026-03-29 13:02:53.833821+00	Ig kim hạnh	0339418412	300/23/21 Đường Nguyễn Văn Linh, Bình Thuận, Quận 7, Thành phố Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
851	ORD-24741774792152	663	\N	\N	300000	0	20000	320000	banking	shipping	\N	2026-03-29 13:49:12.031679+00	Như Quỳnh	0979929540	55/4 Phan Đình Phùng, Phường 17, Quận Phú Nhuận, Hồ Chí Minh	quynhquynhcutie@gmail.com	\N	SPXVN063247349883	unpaid	\N	1457	21715	\N	\N	\N
850	#ADM-356254	662	\N	\N	300000	0	0	300000	transfer	shipping	Ig lee's house  [ĐÃ THANH TOÁN]	2026-03-29 13:19:16.340801+00	Ig lee's house 	0904002200	 Đường 21, thôn Vinh Sơn xã Nghĩa Thành huyện Châu Đức tỉnh Bà Rịa Vũng Tàu	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
852	ORD-70411774802685	5	\N	\N	300000	0	0	300000	banking	cancelled	\N	2026-03-29 16:44:44.713747+00	TEst	0979911670	15 NXK, Phường Tân Thành, Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	1456	21509	\N	\N	\N
854	#ADM-958786	5	\N	\N	300000	0	0	300000	cod	cancelled	Test	2026-03-30 10:35:59.131943+00	TEst	0979911670	15 NXK	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
858	ORD-23891774867941	665	\N	\N	300000	0	0	300000	banking	cancelled	\N	2026-03-30 10:52:21.357374+00	test	097991170	15 nxk, Xã Tả Sìn Thàng, Huyện Tủa Chùa, Điện Biên		\N	\N	unpaid	\N	2021	620609	\N	\N	\N
857	#ADM-805514	5	\N	\N	300000	0	0	300000	cod	cancelled	Test	2026-03-30 10:50:05.68848+00	TEst	0979911670	15 NXK	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
856	#ADM-758509	5	\N	\N	300000	0	0	300000	cod	cancelled	Test	2026-03-30 10:49:18.659094+00	Test	0979911670	15 NXK	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
855	#ADM-758225	5	\N	\N	300000	0	0	300000	transfer	cancelled	Test	2026-03-30 10:49:18.391104+00	Test	0979911670	15 NXK	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
859	#ADM-817728	5	\N	\N	300000	0	0	300000	cod	cancelled	Test	2026-03-30 11:40:18.240317+00	TEst	0979911670	15 NXK	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
871	#ADM-224068	674	\N	\N	620000	0	0	620000	cod	shipping	Ig minh anh pham thi	2026-03-30 14:17:04.167268+00	Ig minh anh pham thi	0393603214	số 4 ngách 36 ngõ 12 nguyễn văn trỗi, phương liệt, thanh xuân, hà nội 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
873	ORD-62431774880510	5	\N	\N	300000	0	0	300000	banking	cancelled	\N	2026-03-30 14:21:49.629131+00	TEST EMAIL	0979911670	15 NXK, Phường Tân Thành, Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	1456	21509	\N	\N	\N
879	#ADM-122752	680	\N	\N	1570000	0	15000	1585000	transfer	shipping	Ig oink_pg [ĐÃ THANH TOÁN]	2026-03-30 14:32:02.994712+00	Ig oink_pg	84 23538-89999	Amina Lantana Hoi An Hotel & Spa	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
877	#ADM-896506	678	\N	\N	920000	0	15000	935000	transfer	shipping	Ig irina / Sapo [ĐÃ THANH TOÁN]	2026-03-30 14:28:16.668918+00	Ig irina / Sapo	076 9468394	6 Khuê Mỹ Đông 7, Khuê Mỹ, Ngũ Hành Sơn, Đà Nẵng 550000\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
876	#ADM-761394	677	\N	\N	620000	0	0	620000	cod	shipping	Ig nguyễn thuỳ linh	2026-03-30 14:26:01.494428+00	Ig nguyễn thuỳ linh 	0911949101	13B phạm minh Đức ngô quyền Hải phòng	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
875	#ADM-634708	676	\N	\N	300000	0	0	300000	transfer	shipping	Ig aaliyahanhkieu / sapo [ĐÃ THANH TOÁN]	2026-03-30 14:23:54.807673+00	Ig aaliyahanhkieu / sapo	0704471334 	12/1/25 đặng minh trứ, tân bình	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
874	#ADM-587721	675	\N	\N	670000	0	-670000	0	cod	shipping	Ig mei mei Kol tặng đồ	2026-03-30 14:23:07.839004+00	Ig mei mei Kol tặng đồ	0984729933	Toà Landmark Plus ,Vinhomes Central Park, 720A Điện Biên Phủ, phường Thạnh Mỹ Tây, thành phố Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
872	#ADM-428807	139	\N	\N	700000	0	0	700000	transfer	shipping	Ig vie  [ĐÃ THANH TOÁN Tiền mặt)	2026-03-30 14:20:28.988025+00	Ig vie / sapo	0779078617	Feliz En Vista (cổng 4) phường cát lái, thủ đức	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
870	#ADM-110865	55	\N	\N	1250000	0	0	1250000	transfer	shipping	Ig charii [ĐÃ THANH TOÁN]	2026-03-30 14:15:11.118294+00	Ig charii	0369166.222	Shop ghi lên kiện hàng ( BN2441)\n163 Trương Thị Hoa, phường Tân Thới Hiệp, Quận 12, thành phố Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
869	#ADM-021429	673	\N	\N	650000	0	0	650000	cod	shipping	Ig hoàng long	2026-03-30 14:13:41.536461+00	Ig hoàng long	0913733636	305A Lý Thường Kiệt P15 Q11	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
868	#ADM-982814	672	\N	\N	300000	0	0	300000	transfer	shipping	Ig mai my anh  [ĐÃ THANH TOÁN]	2026-03-30 14:13:02.905248+00	Ig mai my anh / Sapo	0938469019	44 Trần Văn Danh p13 Quận Tân Bình TPHCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
867	#ADM-901867	437	\N	\N	400000	0	0	400000	cod	shipping	Ig nauy	2026-03-30 14:11:41.975984+00	Ig nauy	0787074452	 107 hoàng sĩ khải đà nẵng\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
866	#ADM-876143	671	\N	\N	350000	0	0	350000	cod	shipping	Ig mliinhh	2026-03-30 14:11:16.280262+00	Ig mliinhh	0943870098	Địa chỉ: 56a Ngõ Yết Kiêu, Cửa Nam, Hoàn Kiếm, Hà Nội 11000	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
861	#ADM-611716	241	\N	\N	350000	0	0	350000	cod	shipping	Ig ngoc phuc	2026-03-30 14:06:51.867466+00	Ig ngoc phuc	0703929339	Chung cư Sky89- đường lê thị chợ- phường phú thuận- quận 7	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
862	#ADM-672478	667	\N	\N	650000	0	0	650000	cod	shipping	Ig mai thanh	2026-03-30 14:07:52.607522+00	Ig mai thanh	0528593977	Đường 27 giữa ngã tư số 8 và 10. Nhà tuyền đồ mỹ Xã Nghĩa Thành, Huyện Châu Đức, Bà Rịa Vũng Tàu	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
863	#ADM-735996	668	\N	\N	300000	0	0	300000	cod	shipping	Ig foundnotfound101	2026-03-30 14:08:56.144077+00	Ig foundnotfound101	0394999300	Toà West - Lumiere Riverside, Số 2, Võ Trường Toản, Phường An Phú, Thành Phố Thủ Đức, TP. Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
864	#ADM-803353	669	\N	\N	600000	0	0	600000	transfer	shipping	Ig thảo vy [ĐÃ THANH TOÁN]	2026-03-30 14:10:03.491481+00	Ig thảo vy / Sapo	0975921045 	363/46 Đinh Bộ Lĩnh p26 Bình thạnh\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
865	#ADM-846212	670	\N	\N	350000	0	0	350000	cod	shipping	Ig minh thư	2026-03-30 14:10:46.388601+00	Ig minh thư	0902905362	114 đồng văn cống, phường cát lái, hcm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
853	ORD-51551774803971	664	\N	\N	950000	0	0	950000	banking	shipping	\N	2026-03-29 17:06:10.737551+00	Huỳnh Ngọc Mai Lâm	0764466036	144/11A đường số 9, Phường Linh Tây, Quận Thủ Đức, Hồ Chí Minh	huynhngocmailam@gmail.com	\N	SPXVN060571563563	unpaid	\N	1463	21807	\N	\N	\N
849	#ADM-435978	569	\N	\N	850000	0	0	850000	transfer	returned	Ig vani [ĐÃ THANH TOÁN]	2026-03-29 13:03:56.134466+00	Ig vani	+0328504510	Gia Huỳnh - tổ 29-kp.gia huỳnh -p trảng bàng -tây ninh, Phường Trảng Bàng, Thị Xã Trảng Bàng, Tây Ninh\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
860	ORD-53731774875525	666	\N	\N	300000	0	0	300000	banking	returned	\N	2026-03-30 12:58:44.927822+00	Nguyễn Ngọc Mai	0385418958	Cổng làng đình cả , Xã Nội Duệ, Huyện Tiên Du, Bắc Ninh	nnm2109001@gmail.com	\N	SPXVN066911042293	unpaid	\N	1729	190409	\N	\N	\N
885	#ADM-351645	685	\N	\N	750000	0	0	750000	transfer	cancelled	Ig bmqin [ĐÃ THANH TOÁN]	2026-03-30 14:35:51.757244+00	Ig bmqin	0977586904	Vinhomes Grand Park, The Origami - S9.01 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
887	#ADM-445705	686	\N	\N	600000	0	0	600000	cod	shipping	Ig khahchin_	2026-03-30 14:37:25.865271+00	Ig khahchin_	094 2676286	ct3 yên hoà parkview, 3 Vũ Phạm Hàm, Yên Hoà, Cầu Giấy, Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
886	#ADM-398137	685	\N	\N	750000	0	0	750000	cod	shipping	Ig bmqin	2026-03-30 14:36:38.265868+00	Ig bmqin	0977586904	Vinhomes Grand Park, The Origami - S9.01 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
884	#ADM-324439	684	\N	\N	320000	0	0	320000	transfer	shipping	Ig trần thanh thuý [ĐÃ THANH TOÁN]	2026-03-30 14:35:24.547061+00	Ig trần thanh thuý / sapo	0976781461	Vinhome Grand Park phường Long Bình tp Thủ Đức HCM ( toà BS12)	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
883	#ADM-291647	103	\N	\N	650000	0	0	650000	cod	shipping	Ig ttien.bui	2026-03-30 14:34:51.772328+00	Ig ttien.bui	0985037507	02 Nguyễn Lương Bằng - xã Lộc thanh - tp bảo Lộc - lâm đồng 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
882	#ADM-253136	683	\N	\N	320000	0	-320000	0	cod	shipping	Kol sym	2026-03-30 14:34:13.269744+00	Kol sym	0879572999	Toà Parkview Residence, 152 điện biên phủ, phường 25, q.Bình Thạnh, Tp Hcm\nCăn 12A-03\n0879572999\nToà Parkview Residence, 152 điện biên phủ, phường 25, q.Bình Thạnh, Tp Hcm\nCăn 12A-03	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
881	#ADM-203576	682	\N	\N	350000	0	0	350000	transfer	shipping	Ig ly ha ai tran [ĐÃ THANH TOÁN]	2026-03-30 14:33:23.669728+00	Ig ly ha ai tran	 0939092540	48/12 hẻm 1 mậu thân, phường xuân khánh, quận ninh kiều, cần thơ	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
880	#ADM-180200	681	\N	\N	620000	0	0	620000	cod	shipping	Ig katty nguyen	2026-03-30 14:33:00.318348+00	Ig katty nguyen	0388372768	770 lý thái tổ, phường hoà phú, tp thủ dầu một, bình dương	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
878	#ADM-936082	679	\N	\N	320000	0	0	320000	cod	shipping	Ig phuong anh	2026-03-30 14:28:56.18028+00	Ig phuong anh	0859926708	35 tổ 2 ấp 3 xã an thái trung, huyện cái bè ,tỉnh tiền giang \n 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
888	#ADM-251245	687	\N	\N	970000	0	0	970000	transfer	shipping	Ig đăng vi [ĐÃ THANH TOÁN]	2026-03-30 15:40:51.372118+00	Ig đăng vi	 0984108804	39b Nguyễn Văn Linh , phường Tân Thuận Tây , quận 7 . Chung cư Eco Green block C	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
890	#ADM-368016	688	\N	\N	320000	0	0	320000	cod	shipping	Ig tiffanywong3042	2026-03-30 15:42:48.112101+00	Ig tiffanywong3042	0839100901	 5 Lương Ngọc Quyến, quận Hải Châu, Đà Nẵng	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
889	#ADM-320527	674	\N	\N	700000	0	0	700000	transfer	returned	Ig minh anh pham thi [ĐÃ THANH TOÁN]	2026-03-30 15:42:00.630986+00	Ig minh anh pham thi	0393603214	số 4 ngách 36 ngõ 12 nguyễn văn trỗi, phương liệt, thanh xuân, hà nội 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
891	#ADM-366922	674	\N	\N	700000	0	0	700000	cod	shipping	Ig minh anh pham thi	2026-03-30 16:49:27.061792+00	Ig minh anh pham thi	0393603214	số 4 ngách 36 ngõ 12 nguyễn văn trỗi, phương liệt, thanh xuân, hà nội\n\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
899	#ADM-188342	695	\N	\N	300000	0	0	300000	transfer	shipping	Ig như xinh lắm [ĐÃ THANH TOÁN]	2026-03-31 14:26:28.437113+00	Ig như xinh lắm	0797908294 	9h8 đường dd12, tân hưng thuận q.12	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
898	#ADM-158430	694	\N	\N	1290000	0	20000	1310000	transfer	shipping	Ig plchmsva [ĐÃ THANH TOÁN]	2026-03-31 14:25:58.566046+00	Ig plchmsva	0368308053	Nam Nha Trang, Khánh Hòa, room 507	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
897	#ADM-017241	693	\N	\N	300000	0	0	300000	cod	shipping	Ig đinh nguyễn nhi	2026-03-31 14:23:37.354075+00	Ig đinh nguyễn nhi	0779631653	Dc 1/2 tân hoà 2, phường hiệp phú, quận 9 cũ Thủ Đức	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
896	#ADM-975432	661	\N	\N	350000	0	0	350000	cod	shipping	Ig kim hạnh	2026-03-31 14:22:55.543169+00	Ig kim hạnh 	0339418412	300/23/21 Đường Nguyễn Văn Linh, Bình Thuận, Quận 7, Thành phố Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
894	#ADM-880249	691	\N	\N	350000	0	0	350000	cod	shipping	Ig mai thanh	2026-03-31 14:21:20.407846+00	Ig mai thanh	035 446 8559	shillamonogram đà nẵng	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
893	#ADM-647422	690	\N	\N	300000	0	0	300000	cod	shipping	Ig piedi.ary29	2026-03-31 14:17:27.594841+00	Ig piedi.ary29	0947252705	2 ngõ Hàng Chỉ, Hoàn Kiếm, Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
911	#ADM-781110	704	\N	\N	600000	0	0	600000	transfer	shipping	Ig phạm hoàng yến [ĐÃ THANH TOÁN]	2026-03-31 14:36:21.205536+00	Ig phạm hoàng yến	0702639591	43/4b  đường số 7,kp5, linh tây thủ đức	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
910	#ADM-721621	703	\N	\N	1250000	0	25000	1275000	transfer	shipping	Ig donfetch [ĐÃ THANH TOÁN]	2026-03-31 14:35:21.749821+00	Ig donfetch	0876868440	: 60 Đường số 46, Bình Trưng Đông, Thủ Đức, Thành phố Hồ Chí Minh, Vietnam	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
909	#ADM-605235	702	\N	\N	950000	0	0	950000	cod	shipping	Ig phanyen.b	2026-03-31 14:33:25.335405+00	Ig phanyen.b	0938946935	822/125 hương lộ 2, bình trị đông , bình tân 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
908	#ADM-566088	71	\N	\N	320000	0	0	320000	transfer	shipping	Ig npyn [ĐÃ THANH TOÁN]	2026-03-31 14:32:46.187508+00	Ig npyn	789515460	khách tự đặt xe	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
907	#ADM-539206	701	\N	\N	320000	0	0	320000	cod	shipping	Ig mãi hận math bio chem	2026-03-31 14:32:19.293657+00	Ig mãi hận math bio chem	0934140424	cosmo city 99 nguyễn thị thập phường tân phú quận 7 tphcm\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
906	#ADM-505854	251	\N	\N	620000	0	15000	635000	transfer	shipping	Ig imkkiil [ĐÃ THANH TOÁN]	2026-03-31 14:31:45.957111+00	Ig imkkiil	0889993313	Nhà văn hoá khu 5- Hải Yên-Móng Cái-Quảng Ninh 0889993313.   Tabg tang	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
905	#ADM-420880	700	\N	\N	300000	0	0	300000	cod	shipping	Ig k.nguyene	2026-03-31 14:30:20.970927+00	Ig k.nguyene	0935167396	5 Quốc sử quán, phường Đông Ba, Tp Huế	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
904	#ADM-387088	699	\N	\N	300000	0	0	300000	cod	shipping	Ig krystal	2026-03-31 14:29:47.18376+00	Ig krystal	0909529474	Thu Tuyền 17/21a Tân Thuận Tây p Bình Thuận q7	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
903	#ADM-349214	698	\N	\N	300000	0	0	300000	cod	shipping	Ig hai yen	2026-03-31 14:29:09.307549+00	Ig hai yen	0329371321	Bệnh viện Sản - Nhi Bắc Ninh số 2\nĐường Huyền Quang, phường Võ Cường, Tỉnh Bắc Ninh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
902	#ADM-305142	697	\N	\N	700000	0	0	700000	transfer	shipping	Ig hoonxxd [ĐÃ THANH TOÁN]	2026-03-31 14:28:25.238011+00	Ig hoonxxd	0902906841	Vinhome central 3 , nguyễn hữu cảnh 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
901	#ADM-275674	696	\N	\N	600000	0	35000	635000	transfer	shipping	Ig jan miki [ĐÃ THANH TOÁN]	2026-03-31 14:27:55.768571+00	Ig jan miki	0369166222	163 Đường Trương Thị Hoa, phường Tân Thới Hiệp quận 12 ,tphcm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
900	#ADM-223332	71	\N	\N	350000	0	0	350000	transfer	shipping	Ig thỏ con [ĐÃ THANH TOÁN]	2026-03-31 14:27:03.434426+00	Ig thỏ con	789515460	Khách ghé lấy	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
892	ORD-33691774962617	689	\N	\N	350000	0	0	350000	banking	shipping	\N	2026-03-31 13:10:17.407704+00	Như Ý	0367761313	622/10 đường cộng hoà, Phường 15, Quận Tân Bình, Hồ Chí Minh	nguyendonhuy301106@gmail.com	\N	SPXVN064242269064	unpaid	\N	1455	21415	\N	\N	\N
895	#ADM-948379	692	\N	\N	620000	0	0	620000	cod	cancelled	Ig ngọc nhân	2026-03-31 14:22:28.473849+00	Ig ngọc nhân	0842421488	số nhà 308 nguyễn văn thoại tiệm tóc rùa barber châu phú A châu đốc an giang	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
919	#ADM-992860	692	\N	\N	320000	0	0	320000	cod	shipping	Ig ngọc nhân	2026-03-31 14:56:33.031819+00	Ig ngọc nhân	0842421488	số nhà 308 nguyễn văn thoại tiệm tóc rùa barber châu phú A châu đốc an giang	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
918	#ADM-498612	420	\N	\N	750000	0	0	750000	cod	shipping	Ig phuong dung chu	2026-03-31 14:48:18.74246+00	Ig phuong dung chu	0368823044 	· Địa chỉ: Move Vietnam, 27E Võ Trường Toản, Thảo Điền, quận 2 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
917	#ADM-448976	649	\N	\N	300000	0	0	300000	cod	shipping	Ig _klhm	2026-03-31 14:47:29.172672+00	Ig _klhm / sapo thu cod	+886 928273350	:19-23 Lam Son Square, Bến Nghé, Sài Gòn, Hồ Chí Minh, Vietnam\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
916	#ADM-169579	71	\N	\N	670000	0	0	670000	transfer	shipping	Ig lilly [ĐÃ THANH TOÁN]	2026-03-31 14:42:49.69231+00	Ig lilly	789515460	Khách hoả tốc	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
913	#ADM-937349	706	\N	\N	350000	0	0	350000	cod	returned	Ig _emthuyy	2026-03-31 14:38:57.441232+00	Ig _emthuyy	0354468559	shillamonogram đà nẵng	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
914	#ADM-027813	707	\N	\N	1170000	0	15000	1185000	transfer	shipping	Ig succub.kyuubi [ĐÃ THANH TOÁN]	2026-03-31 14:40:27.907558+00	Ig succub.kyuubi	0338 796036	saigon, diamond island, maldives tower, post office box number 14.09	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
920	#ADM-392338	709	\N	\N	300000	0	0	300000	cod	shipping	Ig võ hoàng an	2026-03-31 15:03:12.521198+00	Ig võ hoàng an	0399955343	39 đường số 2, phường Tam Phú, Tp. thủ đức\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
921	#ADM-483479	696	\N	\N	350000	0	0	350000	transfer	shipping	Ig cira.studio [ĐÃ THANH TOÁN]	2026-03-31 15:04:43.637722+00	Ig cira.studio	0369166222	Người Nhận BN1356\n\n163 Đường Trương Thị Hoa, phường Tân Thới Hiệp quận 12 ,tphcm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
922	#ADM-704149	710	\N	\N	320000	0	0	320000	cod	shipping	Ig duyen	2026-03-31 15:08:24.284494+00	Ig duyen	0867 324 906	6 nguyễn bỉnh khiêm xã liên nghĩa tỉnh đức trọng huyện lâm đồng	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
923	#ADM-643982	711	\N	\N	1590000	0	15000	1605000	transfer	shipping	Ig fern [ĐÃ THANH TOÁN]	2026-03-31 16:30:44.094105+00	Ig fern	035 467 7196	 Toà nhà Vinaconax 7\n61 Nguyễn Văn Giap , Phường Cầu Diễn \nQuận Nam Từ Liêm , Hà nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
924	#ADM-686328	712	\N	\N	620000	0	0	620000	cod	shipping	Ig chemical romance	2026-03-31 16:31:26.42747+00	Ig chemical romance 	0912020515	The Ninety Complex, 90 Đ. Láng, Ngã Tư Sở, Đống Đa, Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
925	#ADM-402945	666	\N	\N	300000	0	0	300000	cod	shipping	Nguyễn Ngọc Mai ord	2026-03-31 16:43:23.095972+00	Nguyễn Ngọc Mai ord	0385418958	nnm2109001@gmail.com\n\nCổng làng đình cả , Xã Nội Duệ, Huyện Tiên Du, Bắc Ninh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
930	ORD-96751775019204	716	\N	\N	320000	0	0	320000	banking	shipping	\N	2026-04-01 04:53:23.701024+00	Dương Thị Hồng Mẫn	0772064405	29a, Phạm Ngũ Lão, Phường Phú Cường, Thành phố Thủ Dầu Một, Bình Dương	duongthihongman09@gmail.com	\N	SPXVN064161199864	unpaid	\N	1538	440107	\N	\N	\N
941	#ADM-454515	71	\N	\N	300000	0	0	300000	transfer	cancelled	Ig xíu  [ĐÃ THANH TOÁN]	2026-04-01 13:17:34.680605+00	Ig xíu 	789515460	Khách ghé lấy	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
1252	#ADM-552051	972	\N	\N	12700000	0	0	12700000	transfer	shipping	Ig avoe.official  [ĐÃ THANH TOÁN]	2026-04-14 15:29:12.495977+00	Ig avoe.official 	0365786150	o A10 KCN Minh Hưng-sikico, Xã Đồng Nơ, Huyện Hớn quản, Tỉnh Bình Phước \nCÔNG TY NGŨ KIM YOUDE	\N	\N	\N	unpaid	\N	\N	\N	2026-04-14 15:32:14.742+00	\N	\N
940	#ADM-970490	722	\N	\N	350000	0	0	350000	cod	shipping	Ig  Nguyễn ngọc	2026-04-01 12:52:50.604475+00	Ig  Nguyễn ngọc	0919176105	scsc building 30 phan thúc duyện, phường 4 , quận tân bình; thành phố Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
939	#ADM-883729	591	\N	\N	900000	0	30000	930000	transfer	shipping	Ig phirun [ĐÃ THANH TOÁN]	2026-04-01 12:51:23.85075+00	Ig phirun	0906.984.493	275/14B1 Đặng Nguyên Cẩn, Phường Phú Lâm, TP. Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
938	#ADM-696798	721	\N	\N	300000	0	0	300000	transfer	shipping	Ig thanhpham [ĐÃ THANH TOÁN]	2026-04-01 12:48:16.922219+00	Ig thanhpham	0902420680	 keangnam landmark72 đường phạm hùng, phường yên hoà hà nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
937	#ADM-572104	720	\N	\N	1350000	0	0	1350000	cod	shipping	Ig ashley nguyen	2026-04-01 12:46:12.225273+00	Ig ashley nguyen 	0906418882	Số 16 STH12A đường số 5 , khu đô thị Hà Quang 1 , phường Nam Nha Trang , Khánh Hoà 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
936	#ADM-460834	719	\N	\N	300000	0	0	300000	transfer	shipping	Ig Thao [ĐÃ THANH TOÁN]	2026-04-01 12:44:20.954018+00	Ig Thao	0977490522	21/20 Trường Sơn, P4, Tân Bình\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
935	#ADM-404097	696	\N	\N	700000	0	0	700000	transfer	shipping	Ig cira.studio [ĐÃ THANH TOÁN]	2026-04-01 12:43:24.2251+00	Ig cira.studio	0369166222	163 Đường Trương Thị Hoa, phường Tân Thới Hiệp quận 12 ,tphcm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
934	#ADM-243441	718	\N	\N	650000	0	0	650000	transfer	shipping	Ig jessica  [ĐÃ THANH TOÁN]	2026-04-01 12:40:43.547684+00	Ig jessica 	0827368345	NUE Noble Srinakarin Lasalle นิว โนเบิล ศรีนครินทร์ – ลาซาล\nSrinagarindra Rd, Samrong Nuea, Mueang Samut Prakan District, Samut Prakan 10270, Thailand	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
932	#ADM-101471	703	\N	\N	900000	0	0	900000	transfer	shipping	Ig donfetch [ĐÃ THANH TOÁN]	2026-04-01 12:38:21.598766+00	Ig donfetch	0876868440	\n\nAddress : 60 Đường số 46, Bình Trưng Đông, Thủ Đức, Thành phố Hồ Chí Minh, Vietnam\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
931	#ADM-031175	386	\N	\N	350000	0	0	350000	cod	shipping	Ig nguyễn huỳnh lâm ngọc	2026-04-01 12:37:11.348636+00	Ig nguyễn huỳnh lâm ngọc	0981 771 340	 320/16a Nguyễn Văn Linh, phường Bình Thuận  quận 7, hcm\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
929	#ADM-955899	425	\N	\N	1300000	0	0	1300000	cod	shipping	Ig im_chindi	2026-04-01 03:09:16.342951+00	Ig im_chindi	0778988112	13.04 S6, The Sun Anenue, 28 Đ. Mai Chí Thọ, An Phú, Thành phố Thủ Đức,	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
928	#ADM-868831	715	\N	\N	350000	0	0	350000	cod	shipping	Ig huong tran	2026-04-01 03:07:48.950199+00	Ig huong tran	0901669963	100 Lê Lợi, Lộc Thanh, Bảo Lộc - Lâm Đồng \n( địa chỉ xác nhập 100 Lê Lợi, Phường 1, Bảo Lộc - Lâm Đồng )	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
927	#ADM-842288	714	\N	\N	300000	0	0	300000	cod	shipping	Ig thien.nhi	2026-04-01 03:07:22.395499+00	Ig thien.nhi	0764747859	K18/15 Nguyễn Văn Thoại, Ngũ Hành Sơn, Đà Nẵng	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
926	#ADM-736534	713	\N	\N	1000000	0	0	1000000	cod	shipping	Ig kim ngânn	2026-04-01 03:05:36.654119+00	Ig kim ngânn	0972587185	23 cù chính lan tx hn	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
933	#ADM-193326	717	\N	\N	600000	0	-600000	0	cod	shipping	Ig maria kim  TẶNG ĐỒ KOL	2026-04-01 12:39:53.438893+00	Ig maria kim  TẶNG ĐỒ KOL	+84 32 5733980	51A Đ. Mê Linh, Tân Lập, Nha Trang, Khánh Hòa 650000\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
915	#ADM-126033	708	\N	\N	500000	0	0	500000	cod	returned	Ig mongthuong.15	2026-03-31 14:42:06.12638+00	Ig mongthuong.15 	0968816281	Hẻm 350/17C\nLê Văn Quới , Khu Phố 80, Bình Hưng Hoà. HCM\nSdt:0968816281Hẻm 350/17C\nLê Văn Quới , Khu Phố 80, Bình Hưng Hoà. HCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
942	#ADM-325469	50	\N	\N	4900000	0	0	4900000	transfer	shipping	Ig jang [ĐÃ THANH TOÁN]	2026-04-01 16:02:05.631035+00	Ig jang	0325267896	W2448\nĐịa chỉ: 375 tân thới hiệp 21 , Tổ 3 ,Kp3 ,quận 12 ( nhớ gõ đủ)\nSố kho :	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
943	ORD-90581775092306	723	\N	\N	600000	0	0	600000	banking	shipping	\N	2026-04-02 01:11:45.991669+00	vy	0945857868	228 khu bến xe, Phường Xuân Phú, Thị Xã Sông Cầu, Phú Yên	ngocvycampham@gmail.com	\N	SPXVN063511442994	unpaid	\N	1856	390302	\N	\N	\N
954	ORD-70181775124943	733	\N	\N	350000	0	0	350000	banking	shipping	\N	2026-04-02 10:15:43.43894+00	trần phương trang	0848616136	143 ngõ 2 tổ 3 đa sỹ kiến hưng hà đông, Phường Kiến Hưng, Quận Hà Đông, Hà Nội	tranphuongtrang.10032003@gmail.com	\N	SPXVN068577809644	unpaid	\N	1542	1B1505	\N	\N	\N
1250	#ADM-294900	970	\N	\N	550000	0	0	550000	cod	shipping	Ig đinh hồng anh	2026-04-14 15:08:15.012797+00	Ig đinh hồng anh	0934932239    	A-013 Chung cư GREEN RIVER, Phạm Thế Hiển, Phường 6, Quận 8, Sài Gòn 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-14 15:32:14.742+00	\N	\N
953	ORD-14121775104042	732	\N	\N	300000	0	0	300000	banking	returned	\N	2026-04-02 04:27:22.426414+00	Van tran	0933931727	Số 29 đường 54, Phường An Khánh, Quận 2, Hồ Chí Minh	vanbhm.789@gmail.com	\N	\N	unpaid	\N	1443	20201	\N	\N	\N
973	#ADM-455096	732	\N	\N	300000	0	0	300000	transfer	shipping	Van tran [ĐÃ THANH TOÁN]	2026-04-02 17:04:15.314897+00	Van tran	0933931727	vanbhm.789@gmail.com\n\nSố 29 đường 54, Phường An Khánh, Quận 2, Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
972	#ADM-412262	747	\N	\N	300000	0	0	300000	transfer	shipping	Ig kimdunkim [ĐÃ THANH TOÁN]	2026-04-02 17:03:32.392728+00	Ig kimdunkim	0914150196	La astoria 2, thủ đức	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
971	#ADM-371377	747	\N	\N	1000000	0	0	1000000	transfer	shipping	Ig kimdunkim [ĐÃ THANH TOÁN]	2026-04-02 17:02:51.482159+00	Ig kimdunkim	0914150196	La astoria 2, thủ đức	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
970	#ADM-325486	746	\N	\N	300000	0	0	300000	cod	shipping	Ig ANNA_0000	2026-04-02 17:02:05.583668+00	Ig ANNA_0000	0868340088	Đại lý thông diễm, ngã tư bsek, xã dlieyang, huyện eahleo, tỉnh đăk lăk	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
969	#ADM-266519	745	\N	\N	650000	0	0	650000	cod	shipping	Ig nhã phương	2026-04-02 17:01:06.624099+00	Ig nhã phương	0909070512	\nĐC: 31/2 Nguyễn Đình Khơi, P4, Q Tân Bình	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
968	#ADM-213845	744	\N	\N	2550000	0	-50000	2500000	transfer	shipping	Ig thy [ĐÃ THANH TOÁN]	2026-04-02 17:00:13.943806+00	Ig thy	0919500600	68/6 Thống Nhất, p10, gò vấp, hcm \n\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
967	#ADM-737240	743	\N	\N	320000	0	0	320000	transfer	shipping	Ig salty [ĐÃ THANH TOÁN]	2026-04-02 13:15:37.344305+00	Ig salty	0866879713	27/3 đường số 10, p.Bình Thuận, q7\nPhường Tân Thuận (mới)\n.Khanh 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
966	#ADM-686212	742	\N	\N	600000	0	0	600000	cod	shipping	Ig j	2026-04-02 13:14:46.308758+00	Ig j	089 9900934	6274749392	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
965	#ADM-639017	741	\N	\N	920000	0	0	920000	transfer	shipping	Ig trinh trinh nguyễn [ĐÃ THANH TOÁN]	2026-04-02 13:13:59.11404+00	Ig trinh trinh nguyễn	0966720842	41F/98 Đặng Thuỳ Trâm P13 Bình Thạnh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
964	#ADM-581915	326	\N	\N	300000	0	0	300000	transfer	shipping	Ig nguyễn phương thảo [ĐÃ THANH TOÁN]	2026-04-02 13:13:02.042867+00	Ig nguyễn phương thảo	0962821709	BS8 The Berverly Solari, Vinhomes Grand Park, phường Long Bình, q9, Thủ Đức, HCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
963	#ADM-544579	740	\N	\N	620000	0	0	620000	cod	shipping	Ig thu anh	2026-04-02 13:12:24.702434+00	Ig thu anh	0375033886	Sảnh T1, số 3 Lương Yên, HBT, Hà Nội\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
961	#ADM-491747	71	\N	\N	600000	0	0	600000	transfer	shipping	Ig wendy  [ĐÃ THANH TOÁN]	2026-04-02 13:11:31.84997+00	Ig wendy 	789515460	kháchhỏa tốc	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
960	#ADM-455893	739	\N	\N	400000	0	0	400000	cod	shipping	Ig nguyễn diễm hằng	2026-04-02 13:10:56.029726+00	Ig nguyễn diễm hằng	0983423895	52 Thành Thái phường 12 quận 10\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
959	#ADM-430114	738	\N	\N	300000	0	0	300000	cod	shipping	Ig tracy	2026-04-02 13:10:30.213689+00	Ig tracy	0933933871	  Địa chỉ: 159, đường Cách Mạng Tháng 8, khu phố 4, phường Phước Hiệp, TP. Bà Rịa, BRVT (địa chỉ cũ)\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
958	#ADM-402559	737	\N	\N	300000	0	0	300000	cod	shipping	Ig kim mì	2026-04-02 13:10:02.671362+00	Ig kim mì	0338370618	76 chung cư Ngô Tất Tố, lô C, phường 19, quận Bình Thạnh (mới là phường Thạnh Mỹ Tây), tpHCM\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
957	#ADM-331012	736	\N	\N	350000	0	0	350000	cod	shipping	Ig mika	2026-04-02 13:08:51.144306+00	Ig mika 	0933519007	25/2 huỳnh văn gấm, tây thạnh, tân phú\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
956	#ADM-281211	735	\N	\N	600000	0	0	600000	transfer	shipping	Ig mai huong [ĐÃ THANH TOÁN]	2026-04-02 13:08:01.30756+00	Ig mai huong	0823523265	Thao Dien Green, 192 Nguyễn Văn Hưởng, Thảo Điền, Thành phố Thủ Đức, Thành phố Hồ Chí Minh\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
955	ORD-33241775134451	734	\N	\N	750000	0	0	750000	banking	shipping	\N	2026-04-02 12:54:10.942787+00	Cao Hồng Yến	0987792504	Vinhomes Central Park toà C1, 208 Nguyễn Hữu Cảnh, Phường 22, Quận Bình Thạnh, Hồ Chí Minh	hongyen4422004@gmail.com	\N	\N	unpaid	\N	1462	21615	\N	\N	\N
952	#ADM-960991	731	\N	\N	600000	0	0	600000	cod	shipping	Ig luctramachiato	2026-04-02 03:19:21.098411+00	Ig luctramachiato	0835082727	C148 Lê Thị Riêng, phường Thới An, Quận 12, tphcm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
944	#ADM-519102	203	\N	\N	350000	0	0	350000	cod	shipping	Ig bí nhe	2026-04-02 03:11:59.268715+00	Ig bí nhe	0944294068	202/51 phạm văn hai p5 qtan bình ạ\n\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
945	#ADM-676853	724	\N	\N	1600000	0	0	1600000	cod	shipping	Ig trinh tú	2026-04-02 03:14:36.972808+00	Ig trinh tú	0819420586 	134/117/66,ph2 phường long bình đồng nai\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
946	#ADM-706007	725	\N	\N	300000	0	0	300000	transfer	shipping	Ig hân  [ĐÃ THANH TOÁN]	2026-04-02 03:15:06.112282+00	Ig hân 	0367913910	\nD6/1 đường 385, p.Tăng Nhơn Phú A	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
947	#ADM-729328	726	\N	\N	350000	0	0	350000	transfer	shipping	Ig _pycnngan_ [ĐÃ THANH TOÁN]	2026-04-02 03:15:29.778322+00	Ig _pycnngan_	0931830452	574/3/27d đường Kinh Dương Vương, P.An Lạc, Q.Bình Tân 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
948	#ADM-757290	727	\N	\N	300000	0	0	300000	transfer	shipping	Ig nhu pham [ĐÃ THANH TOÁN]	2026-04-02 03:15:57.395145+00	Ig nhu pham	 0905753333	Sunrise Riverside Block D Phước Kiển Nhà Bè 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
949	#ADM-796871	728	\N	\N	300000	0	0	300000	cod	shipping	Ig emma	2026-04-02 03:16:36.983356+00	Ig emma	0869042525	182 phố an dương, phường hồng hà hà nội	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
950	#ADM-859610	729	\N	\N	320000	0	0	320000	cod	shipping	Ig benhi123	2026-04-02 03:17:39.712429+00	Ig benhi123	0356210297	482/69A Lê Quang Định p11 Bình Thạnh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
951	#ADM-912824	730	\N	\N	300000	0	0	300000	cod	shipping	Ig trafbae	2026-04-02 03:18:32.921974+00	Ig trafbae	0938682503	số nhà 15b, ngõ 17, tổ 4, phường Phú Lương, quận Hà Đông, TP. Hà Nội 	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
974	#ADM-323188	748	\N	\N	21230000	0	0	21230000	transfer	shipping	ig avoé [ĐÃ THANH TOÁN]	2026-04-02 17:52:03.287108+00	ig avoé	0776657798	9A Tân thới nhất 8- phường Tân thới nhất-q12\n\nND logistics	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
975	ORD-31461775186606	749	\N	\N	300000	0	0	300000	banking	shipping	\N	2026-04-03 03:23:26.442596+00	Phạm thị Mỹ trinh 	0374909137	Số 34 Chu văn an long thành đồng nai, Thị trấn Long Thành, Huyện Long Thành, Đồng Nai	phamtrinh999@gmail.com	\N	SPXVN068209137044	unpaid	\N	1694	480801	\N	\N	\N
1249	#ADM-253479	969	\N	\N	600000	0	0	600000	transfer	shipping	Ig ha phung  [ĐÃ THANH TOÁN]	2026-04-14 15:07:33.582868+00	Ig ha phung 	0919220469	60 Huyền Trân Công Chúa, Hội An Đông, Đà Nẵng\nĐịa chỉ cũ: 60 Huyền Trân Công Chúa, p.Cẩm Châu, Hội An, Quảng Nam	\N	\N	\N	unpaid	\N	\N	\N	2026-04-14 15:32:14.742+00	\N	\N
993	#ADM-347953	145	\N	\N	300000	0	0	300000	transfer	cancelled	Ig bowbkk.staff [ĐÃ THANH TOÁN]	2026-04-03 14:25:48.061342+00	Ig bowbkk.staff	0369166.222 	Shop ghi lên kiện hàng ( BN2705)\n163 Trương Thị Hoa, phường Tân Thới Hiệp, Quận 12, thành phố Hồ Chí Minh\n sdt : 0369166.222 ( Người Nhận BN2705)	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
997	#ADM-519142	764	\N	\N	350000	0	0	350000	cod	shipping	Ig jane	2026-04-03 14:28:39.229901+00	Ig jane	 0792238801	Chung cu Infiniti Riviera Point \n2 Nguyễn Văn Tưởng, Tân Phú, Quận 7, Thành phố Hồ Chí Minh\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
996	#ADM-478519	763	\N	\N	700000	0	0	700000	cod	shipping	Ig trinh nguyễn	2026-04-03 14:27:58.607341+00	Ig trinh nguyễn	0903503415	34 cao thắng p5 q3 hcm\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
995	#ADM-435469	762	\N	\N	640000	0	0	640000	cod	shipping	Ig vy vo	2026-04-03 14:27:15.586476+00	Ig vy vo	0931737703	15 nguyễn cơ thạch phường An Khánh, tp hcm ạ	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
994	#ADM-395879	145	\N	\N	300000	0	25000	325000	transfer	shipping	[ĐÃ THANH TOÁN]	2026-04-03 14:26:35.982107+00	Ig bowbkk.staff	0369166.222 	Shop ghi lên kiện hàng ( BN2705)\n163 Trương Thị Hoa, phường Tân Thới Hiệp, Quận 12, thành phố Hồ Chí Minh\n sdt : 0369166.222 ( Người Nhận BN2705)\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
992	#ADM-308840	761	\N	\N	300000	0	0	300000	transfer	shipping	Ig kiemot2 [ĐÃ THANH TOÁN]	2026-04-03 14:25:08.93678+00	Ig kiemot2	0393794930	364/23/20a thoại ngọc hầu tân phú\n\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
991	#ADM-270471	760	\N	\N	620000	0	0	620000	cod	shipping	Ig myhanhhbae	2026-04-03 14:24:30.560779+00	Ig myhanhhbae	0773696382	598/58 dien bien phu p22 quan binh thanh\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
990	#ADM-222669	759	\N	\N	350000	0	0	350000	transfer	shipping	Ig peon!e [ĐÃ THANH TOÁN]	2026-04-03 14:23:42.797451+00	Ig peon!e`	0988930849	29/31 Hoàng Hoa Thám phường gia định\n\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
989	#ADM-183031	758	\N	\N	300000	0	0	300000	transfer	shipping	Ig phuong thao [ĐÃ THANH TOÁN]	2026-04-03 14:23:03.120817+00	Ig phuong thao	 0934001194	sav 3 the sun avenue, 28 mai chí thọ phường an phú quận 2	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
988	#ADM-142348	757	\N	\N	600000	0	0	600000	cod	shipping	Ig chang phạm	2026-04-03 14:22:22.478572+00	Ig chang phạm	0911607234 	S10.05 Vinhomes Grandpark\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
986	#ADM-060463	756	\N	\N	650000	0	30000	680000	transfer	shipping	Ig balm  [ĐÃ THANH TOÁN]	2026-04-03 14:21:00.553615+00	Ig balm 	0904473553	(SS2645 - Mr.skill)\nSS Cargo Shipping \n674 đường số 2, Phường 13, Quận 6. TPHCM 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-04 04:58:39.65+00	\N	\N
1001	ORD-41661775252928	768	\N	\N	300000	0	0	300000	banking	shipping	\N	2026-04-03 21:48:47.718022+00	bi võ	0966449908	Tổ 4 Ấp Thạnh Sơn 2A (nhà trọ văn minh), Xã Phước Tân, Huyện Xuyên Mộc, Bà Rịa - Vũng Tàu	bivo4969@gmail.com	\N	SPXVN067018150484	unpaid	\N	1699	520310	2026-04-04 13:51:21.01+00	\N	2026-04-04 12:54:07.069+00
985	#ADM-988214	71	\N	\N	600000	0	35000	635000	transfer	shipping	Ig kri.xy2022 [ĐÃ THANH TOÁN]	2026-04-03 14:19:48.380472+00	Ig kri.xy2022	789515460	Khách đặt hỏa tốc	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
984	#ADM-932035	755	\N	\N	350000	0	0	350000	transfer	shipping	Ig kiw.ainh [ĐÃ THANH TOÁN]	2026-04-03 14:18:52.124278+00	Ig kiw.ainh	0779976289	 ấp8 an phước long thành đồng nai ạ\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
983	#ADM-905484	754	\N	\N	300000	0	0	300000	cod	shipping	Ig phạm ý th	2026-04-03 14:18:25.585708+00	Ig phạm ý th	0944531150 	 \nVista Verde - 8 Nguyễn Thanh Sơn, pThạnh Mỹ Lợi, quận 2, HCM\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
982	#ADM-746261	753	\N	\N	320000	0	0	320000	cod	shipping	Ig my võ	2026-04-03 14:15:46.383441+00	Ig my võ	0939806696	696 Trần Hưng Đạo, p.2, Q.5, tp.hcm	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
981	#ADM-637882	752	\N	\N	1050000	0	0	1050000	cod	shipping	Ig phạm yến nhi	2026-04-03 14:13:58.002055+00	Ig phạm yến nhi	0986818823	AMZ pilates and yoga , Đối diện 357 Nguyễn Hoàng Tôn ,Xuân Tảo ,Hà Nội .	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
980	#ADM-378293	751	\N	\N	320000	0	0	320000	cod	shipping	Ig linh	2026-04-03 04:09:38.385447+00	Ig linh	0911710023	198 Nguyễn Thị Minh Khai, Q3, HCM (Tòa báo lao động)	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
979	#ADM-318034	326	\N	\N	300000	0	0	300000	transfer	shipping	Ig nguyễn phương thảo [ĐÃ THANH TOÁN]	2026-04-03 04:08:38.154768+00	Ig nguyễn phương thảo	0962821709	BS8 The Berverly Solari, Vinhomes Grand Park, phường Long Bình, q9, Thủ Đức, HCM	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
978	#ADM-214197	750	\N	\N	1970000	0	0	1970000	cod	shipping	Ig thục an	2026-04-03 03:50:14.29806+00	Ig thục an	0977354744	\n25/3C khu phố Long Thới, phường Lái Thiêu, Thuận An, Bình Dương\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
977	#ADM-126985	55	\N	\N	650000	0	25000	675000	transfer	shipping	Ig charii( BN2441) [ĐÃ THANH TOÁN]	2026-04-03 03:48:47.461789+00	Ig charii ( BN2441)	0369166.222	163 Trương Thị Hoa, phường Tân Thới Hiệp, Quận 12, thành phố Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
976	#ADM-764886	742	\N	\N	300000	0	0	300000	cod	shipping	Ig j6274749392	2026-04-03 03:42:44.990921+00	Ig j6274749392	089 9900934	\nChau Anh\nSảnh A	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
998	#ADM-275732	765	\N	\N	320000	0	0	320000	transfer	shipping	Ig ngoc linh  [ĐÃ THANH TOÁN]	2026-04-03 14:57:55.82171+00	Ig ngoc linh 	 0966454626	151/1/41 lạc long quân, p1, quận 11	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
999	#ADM-567138	766	\N	\N	350000	0	0	350000	transfer	shipping	ig minhanh [ĐÃ THANH TOÁN]	2026-04-03 15:02:47.269315+00	ig minhanh	0939479449	99 Nguyễn Thị Thập, phường tân phú, quận 7, Thành phố Hồ Chí Minh, chung cư Docklands	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
1005	#ADM-768745	771	\N	\N	650000	0	0	650000	cod	shipping	Ig insightofan	2026-04-04 04:09:28.844146+00	Ig insightofan	0908931940	 884/85 Lê Đức Thọ, phường 15, quận Gò Vấp, Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	2026-04-04 13:51:21.01+00	\N	2026-04-04 12:54:07.069+00
1049	#ADM-191530	809	\N	\N	600000	0	33000	633000	transfer	shipping	Ig gladysbay_ [ĐÃ THANH TOÁN]	2026-04-06 04:36:31.629556+00	Ig gladysbay_	 +84 96 696 11 31	OTIS APARTMENT AND HOTEL 33 Trần Kế Xương, Phường 1, Phú Nhuận, Hồ Chí Minh 700000, Việt Nam	\N	\N	\N	unpaid	\N	\N	\N	2026-04-06 14:56:34.495+00	\N	\N
1050	ORD-19731775482486	810	\N	\N	320000	0	0	320000	banking	shipping	\N	2026-04-06 13:34:46.32657+00	Hoàng Ngọc Ánh	0965122063	2C32/8 ấp 70 xã Tân vĩnh lộc, Xã Vĩnh Lộc B, Huyện Bình Chánh, Hồ Chí Minh	hna170803@gmail.com	\N	https://spx.vn/track?SPXVN068991421054	unpaid	\N	1533	22016	2026-04-06 14:56:34.495+00	\N	\N
1061	#ADM-259808	297	\N	\N	300000	0	0	300000	cod	shipping	Ig bên vợ	2026-04-06 14:54:19.975065+00	Ig bên vợ	0933888347 	203 cao văn lầu p2 q6 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-06 14:56:34.495+00	\N	\N
1048	#ADM-143598	696	\N	\N	350000	0	0	350000	transfer	returned	Ig jan miki [ĐÃ THANH TOÁN]	2026-04-06 04:35:43.728186+00	Ig jan miki	0369166222	163 Đường Trương Thị Hoa, phường Tân Thới Hiệp quận 12 ,tphcm\nBN182 miki	\N	\N	\N	unpaid	\N	\N	\N	2026-04-06 14:56:34.495+00	\N	\N
1015	#ADM-692711	780	\N	\N	300000	0	0	300000	transfer	shipping	Ig minh ngọcc [ĐÃ THANH TOÁN]	2026-04-04 13:34:52.839006+00	Ig minh ngọcc	0935814465	206/32 đường số 20 phường An Nhơn Gò Vấp TpHCM	\N	\N	\N	unpaid	\N	\N	\N	2026-04-04 13:51:21.01+00	\N	\N
1248	#ADM-214087	968	\N	\N	320000	0	0	320000	cod	shipping	Ig phạm mỹ	2026-04-14 15:06:54.195207+00	Ig phạm mỹ	0375868570	30A, đường số 2, Cát Lái, Thủ Đức, HCM	\N	\N	\N	unpaid	\N	\N	\N	2026-04-14 15:32:14.742+00	\N	\N
987	#ADM-100466	2	\N	\N	600000	0	0	600000	transfer	shipping	Ig baongoc08 [ĐÃ THANH TOÁN]	2026-04-03 14:21:40.571463+00	Ig baongoc08	0967515969	Midtown The Peak M8 block A đường 15 phường Tân Phú q7\n	\N	\N	\N	unpaid	\N	\N	\N	2026-04-04 04:58:39.65+00	\N	\N
1242	#ADM-174472	955	\N	\N	650000	0	0	650000	cod	shipping	Ig hạnh nguyên	2026-04-14 06:46:14.601462+00	Ig hạnh nguyên	0832204686	Đường số 1 khu dân cư Thạnh Mỹ phường Lê Bình quận Cái Răng Cần Thơ	\N	\N	\N	unpaid	\N	\N	\N	2026-04-14 15:32:14.742+00	\N	\N
1007	ORD-68071775282145	774	\N	\N	300000	0	0	300000	banking	shipping	\N	2026-04-04 05:55:44.744733+00	Phạm Thị Diễm My	0886327889	52/1 đường Đồng Tâm, Xã Bà Điểm, Huyện Hóc Môn, Hồ Chí Minh	tamdannguyen21121999@gmail.com	\N	SPXVN068902128644	unpaid	\N	1459	22202	2026-04-04 13:51:21.01+00	\N	\N
1010	ORD-57851775307425	775	\N	\N	300000	0	0	300000	banking	shipping	\N	2026-04-04 12:57:05.419509+00	Lương Gia Linh	0937303307	207c nguyễn xí ( chung cư richmond ), Phường 26, Quận Bình Thạnh, Hồ Chí Minh	linhlg190406@gmail.com	\N	SPXVN065840825124	unpaid	\N	1462	21618	2026-04-04 13:51:21.01+00	\N	\N
1014	#ADM-670713	779	\N	\N	320000	0	15000	335000	transfer	shipping	Ig D A S H A [ĐÃ THANH TOÁN]	2026-04-04 13:34:30.841405+00	Ig D A S H A	0867314648	Nha Trang Napoleon castle ￼25 Đ. Nguyễn Đình Chiểu, Bắc Nha Trang, Khánh Hòa 650000	\N	\N	\N	unpaid	\N	\N	\N	2026-04-04 13:51:21.01+00	\N	\N
1009	#ADM-221576	5	\N	\N	300000	0	0	300000	transfer	cancelled	test [ĐÃ THANH TOÁN]	2026-04-04 12:53:41.70454+00	TEst 2	0979911670	15 NXK, Phường Tân Thành, Quận Tân Phú, Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	2026-04-04 12:55:32.196+00
1008	#ADM-600693	5	\N	\N	300000	0	30000	330000	transfer	cancelled	Test [ĐÃ THANH TOÁN]	2026-04-04 12:43:21.195214+00	Test	0979911670	15 NXK, Xã Vàng Ma Chải, Huyện Phong Thổ, Lai Châu	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	2026-04-04 12:55:32.196+00
1013	#ADM-582383	778	\N	\N	650000	0	0	650000	cod	shipping	Ig iemvy31	2026-04-04 13:33:02.527157+00	Ig iemvy31	0905479510	02 hải hồ, phường thanh bình, quận hải châu, đà nẵng	\N	\N	\N	unpaid	\N	\N	\N	2026-04-04 13:51:21.01+00	\N	\N
1012	#ADM-527040	777	\N	\N	600000	0	0	600000	cod	shipping	Ig kimchi_boo	2026-04-04 13:32:07.187415+00	Ig kimchi_boo	085.373.9999	Ct2a ngõ 34 hoàng cầu, chợ dừa, đống đa\n.0794666888 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-04 13:51:21.01+00	\N	\N
1011	#ADM-428922	776	\N	\N	320000	0	0	320000	cod	shipping	Ig T	2026-04-04 13:13:49.023419+00	Thảo Trân	0989585837	Nhà Trọ Thầy Ngân, Số 2, Đường Nguyễn Thị Định, Khóm Đông Thịnh 8, Phường Mỹ Phước, Thành phố Long Xuyên, An Giang	\N	\N	\N	unpaid	\N	\N	\N	2026-04-04 13:51:21.01+00	\N	\N
1006	#ADM-820148	772	\N	\N	320000	0	0	320000	cod	shipping	Ig ginkeight	2026-04-04 04:10:20.24956+00	Ig ginkeight	0898503801	105 Nơ Trang Long, phường 11, quận Bình Thạnh, Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	2026-04-04 13:51:21.01+00	\N	\N
1000	ORD-29281775237243	767	\N	\N	300000	0	0	300000	banking	shipping	\N	2026-04-03 17:27:23.439303+00	Lý	0886357201	132 đường số 1 , Phường Tân Phú, Quận 7, Hồ Chí Minh	lyly112024@gmail.com	\N	SPXVN060738601094	unpaid	\N	1449	20707	2026-04-04 13:51:21.01+00	\N	\N
1004	#ADM-694927	770	\N	\N	350000	0	0	350000	cod	shipping	Loveututhemoon	2026-04-04 04:08:15.026689+00	Loveututhemoon	0867230909	22/20a1, đường số 26, phường Hiệp Bình Chánh, thành phố Thủ Đức, Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	2026-04-04 13:51:21.01+00	\N	\N
1003	#ADM-660509	703	\N	\N	300000	0	25000	325000	transfer	shipping	Ig donfetch  [ĐÃ THANH TOÁN]	2026-04-04 04:07:40.701354+00	Ig donfetch 	0876868440	 60 Đường số 46, phường Bình Trưng Đông, thành phố Thủ Đức, Thành phố Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	2026-04-04 13:51:21.01+00	\N	2026-04-04 12:54:07.069+00
1002	#ADM-610945	251	\N	\N	1260000	0	15000	1275000	transfer	shipping	Ig baobaoooo_ [ĐÃ THANH TOÁN]	2026-04-04 04:06:51.07053+00	Ig baobaoooo_	0889993313	Nhà văn hoá khu 5, phường Hải Yên, thành phố Móng Cái, tỉnh Quảng Ninh 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-04 13:51:21.01+00	\N	\N
1247	#ADM-178678	967	\N	\N	300000	0	0	300000	cod	shipping	Ig joetran23_11	2026-04-14 15:06:18.804526+00	Ig joetran23_11	0919118600	222 hà tôn quyền p6 q11 hcm \n	\N	\N	\N	unpaid	\N	\N	\N	2026-04-14 15:32:14.742+00	\N	\N
1243	ORD-72831776154171	963	\N	\N	320000	0	0	320000	banking	shipping	\N	2026-04-14 08:09:31.277154+00	sofia pham	0968461084	Cường Thịnh Homestay - Trọ Nhatrang, 158/12, Hương Lộ Ngọc Hiệp, Xóm Hộ, Phường Ngọc Hiệp, Thành Phố Nha Trang, Khánh Hòa, Phường Ngọc Hiệp, Thành phố Nha Trang, Khánh Hòa		\N	\N	unpaid	\N	1548	410102	2026-04-14 15:32:14.742+00	\N	\N
1019	#ADM-952936	783	\N	\N	300000	0	0	300000	cod	shipping	Ig T	2026-04-04 14:12:33.0426+00	Ig T	 0989585837. 	Nhà Trọ Thầy Ngân, Số 2, Đường Nguyễn Thị Định, Khóm Đông Thịnh 8, Phường Mỹ Phước, Thành Phố Long Xuyên, An Giang	\N	\N	\N	unpaid	\N	\N	\N	2026-04-04 14:12:44.15+00	\N	\N
1018	#ADM-843761	782	\N	\N	350000	0	0	350000	cod	shipping	Ig ngọc hoàng trịnh	2026-04-04 13:37:23.882252+00	Ig ngọc hoàng trịnh 	0901311298	8 hoàng văn thái PMH tower q7	\N	\N	\N	unpaid	\N	\N	\N	2026-04-04 13:51:21.01+00	\N	\N
1017	#ADM-807713	703	\N	\N	300000	0	25000	325000	transfer	shipping	Ig donfetch  [ĐÃ THANH TOÁN]	2026-04-04 13:36:47.824466+00	Ig donfetch 	0876868440	 60 Đường số 46, Bình Trưng Đông, Thủ Đức, Thành phố Hồ Chí Minh, Vietnam	\N	\N	\N	unpaid	\N	\N	\N	2026-04-04 13:51:21.01+00	\N	\N
1016	#ADM-763548	781	\N	\N	300000	0	0	300000	cod	shipping	Ig suhyn	2026-04-04 13:36:03.655057+00	Ig suhyn	0946340006	57, đường số 1 khu tái định cư phường Tương Bình Hiệp tp TDM Bình Dương	\N	\N	\N	unpaid	\N	\N	\N	2026-04-04 13:51:21.01+00	\N	\N
1241	#ADM-754673	961	\N	\N	700000	0	0	700000	cod	shipping	Ig cheetah.88539212	2026-04-14 06:22:34.763281+00	Ig cheetah.88539212	0904266855	Toà W3, Vinhomes westpoint Pham Hung, phường Mễ Trì, Nam Từ Liêm, Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	2026-04-14 15:32:14.742+00	\N	\N
1239	#ADM-571540	959	\N	\N	1290000	0	0	1290000	cod	shipping	Ig stunnarchives	2026-04-14 06:19:31.628839+00	Ig stunnarchives	6562098281	 30617 casewell pl Wesley chapel Fl, 33545	\N	\N	\N	unpaid	\N	\N	\N	2026-04-14 15:32:14.742+00	\N	\N
1024	ORD-69681775382257	787	\N	\N	300000	0	0	300000	banking	shipping	\N	2026-04-05 09:44:16.831792+00	Khánh Ngọc	0888077424	99/5A đường 30/4 phường Ninh Kiều, TPCT ( hẻm 99 kế Cỏ Mềm Homelab, chạy vào 5m bên tay trái có cổng rào màu đen ), Phường Xuân Khánh, Quận Ninh Kiều, Cần Thơ	Huynhtrankhanhngoc@gmail.com	\N	SPXVN067905248904	unpaid	\N	1572	550113	2026-04-05 12:42:13.717+00	\N	\N
1021	#ADM-966770	784	\N	\N	300000	0	0	300000	cod	shipping	Ig hong_._anh	2026-04-05 03:49:26.88654+00	Ig hong_._anh	0354417211	20/40/32, Tổ 3 xóm Trung Đằng Giang, Phường Đằng Giang, Quận Ngô Quyền, Hải Phòng	\N	\N	\N	unpaid	\N	\N	\N	2026-04-05 12:42:13.717+00	\N	\N
1022	#ADM-991469	785	\N	\N	350000	0	0	350000	cod	shipping	Ig zuilennha	2026-04-05 03:49:51.574265+00	Ig zuilennha	0797487077	38/48/7 Trần Khắc Chân, Tân Định, Q1, TP HCM 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-05 12:42:13.717+00	\N	\N
1023	#ADM-024024	786	\N	\N	300000	0	0	300000	transfer	shipping	ig Quỳnh Như [ĐÃ THANH TOÁN]	2026-04-05 03:50:24.134056+00	ig Quỳnh Như	0917134700	91/59B Phạm Văn Chiêu P14 Gò Vấp	\N	\N	\N	unpaid	\N	\N	\N	2026-04-05 12:42:13.717+00	\N	\N
1025	#ADM-247824	788	\N	\N	600000	0	0	600000	transfer	shipping	Ig mì [ĐÃ THANH TOÁN]	2026-04-05 12:30:48.006526+00	Ig mì	0868108834	5/16, Đường Nguyễn Văn Khối, Phường 11, Quận Gò Vấp, TP. Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	2026-04-05 12:42:13.717+00	\N	\N
1028	#ADM-364424	791	\N	\N	600000	0	0	600000	cod	shipping	Ig phan trần phương thảo	2026-04-05 12:32:44.504207+00	Ig phan trần phương thảo	0387468011	10 hẻm 25/119 ngõ Thổ Quan, Khâm Thiên, Đống Đa, Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	2026-04-05 12:42:13.717+00	\N	\N
1027	#ADM-337509	790	\N	\N	300000	0	0	300000	cod	shipping	Ig kim linh	2026-04-05 12:32:17.589932+00	Ig kim linh	0342544676	s111 ocean park 1 đa tốn gia lâm hn\n	\N	\N	\N	unpaid	\N	\N	\N	2026-04-05 12:42:13.717+00	\N	\N
1026	#ADM-302943	789	\N	\N	300000	0	0	300000	cod	shipping	Ig ánh hồng	2026-04-05 12:31:43.025055+00	Ig ánh hồng	0867731354	55/21 đường tây lân khu phố 44 phường Bình Tân HCM 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-05 12:42:13.717+00	\N	\N
1020	#ADM-049777	782	\N	\N	350000	0	0	350000	cod	returned	Ig ngọc hoàng trịnh	2026-04-04 14:14:09.945314+00	Ig ngọc hoàng trịnh 	0901311298	8 hoàng văn thái PMH tower q7	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
1042	#ADM-120561	492	\N	\N	1500000	0	15000	1515000	transfer	shipping	Ig ytwying [ĐÃ THANH TOÁN]	2026-04-05 15:48:40.704162+00	Ig ytwying	0915559528	voco Quang Binh Resort\nVo Nguyen Giap street, Dong Hoi City, Quang Binh	\N	\N	\N	unpaid	\N	\N	\N	2026-04-05 15:51:48.608+00	\N	\N
1039	#ADM-871664	799	\N	\N	650000	0	0	650000	transfer	shipping	Ig bunny.huynh [ĐÃ THANH TOÁN]	2026-04-05 12:41:11.855472+00	Ig bunny.huynh	0947777456	Xe điện thiện phát 3 ( nội thất đào 9be, đối diện trường thcs nguyễn quang sáng), Mỹ Luông, Chợ Mới, An Giang	\N	\N	\N	unpaid	\N	\N	\N	2026-04-05 12:42:13.717+00	\N	\N
1038	#ADM-788279	326	\N	\N	350000	0	0	350000	transfer	shipping	Ig nguyễn phương thảo [ĐÃ THANH TOÁN]	2026-04-05 12:39:48.377513+00	Ig nguyễn phương thảo	0962821709	BS8 The Berverly Solari, Vinhomes Grand Park, phường Long Bình, q9, Thủ Đức, HCM\n	\N	\N	\N	unpaid	\N	\N	\N	2026-04-05 12:42:13.717+00	\N	\N
1037	#ADM-761401	719	\N	\N	1000000	0	0	1000000	transfer	shipping	Phương Thảo [ĐÃ THANH TOÁN]	2026-04-05 12:39:21.514697+00	Phương Thảo	0977490522	21/20 Trường Sơn, P4, Tân Bình	\N	\N	\N	unpaid	\N	\N	\N	2026-04-05 12:42:13.717+00	\N	\N
1036	#ADM-687807	798	\N	\N	700000	0	33000	733000	transfer	shipping	Kim sonin [ĐÃ THANH TOÁN]	2026-04-05 12:38:07.88563+00	Ig NINNNK	0399.888.688	363 Hùng Vương, Phường An Đông, TP.HCM	\N	\N	\N	unpaid	\N	\N	\N	2026-04-05 12:42:13.717+00	\N	\N
1040	ORD-32291775403190	801	\N	\N	350000	0	0	350000	banking	shipping	\N	2026-04-05 15:33:09.938494+00	Trần Văn Thường - Trần Kim Ngân	0982164198	Nhà hàng Cơm Niêu Tài Lộc - Cẩm Khê - Tứ Minh - Hải Dương, Phường Tứ Minh, Thành phố Hải Dương, Hải Dương	vanthuongsbtc@gmail.com	\N	SPXVN060666599194	unpaid	\N	1598	210116	2026-04-05 15:51:48.608+00	\N	\N
1041	ORD-47181775403681	802	\N	\N	300000	0	0	300000	banking	shipping	\N	2026-04-05 15:41:20.945693+00	Thê Thê	0399750010	Toà B chung cư The Zei- Số 8 Lê Đức Thọ , Phường Mỹ Đình 1, Quận Nam Từ Liêm, Hà Nội	callthuongbaby@gmail.com	\N	SPXVN060510535714	unpaid	\N	3440	13004	2026-04-05 15:51:48.608+00	\N	\N
1045	#ADM-226917	805	\N	\N	600000	0	0	600000	cod	shipping	Ig thuhuyen tran	2026-04-05 15:50:27.003882+00	Ig thuhuyen tran	0388777937	162 trần bình trọng , lộc phát , bảo lộc , lâm đồng	\N	\N	\N	unpaid	\N	\N	\N	2026-04-05 15:51:48.608+00	\N	\N
1044	#ADM-176269	804	\N	\N	300000	0	0	300000	transfer	shipping	Ig tuyet bach [ĐÃ THANH TOÁN]	2026-04-05 15:49:36.360368+00	Ig tuyet bach	0384499397	Cây nhãn khu phố 2 thị trấn Bến Cầu huyện bến Cầu tỉnh Tây Ninh.	\N	\N	\N	unpaid	\N	\N	\N	2026-04-05 15:51:48.608+00	\N	\N
1043	#ADM-153598	803	\N	\N	300000	0	0	300000	cod	shipping	Ig concameokhongat_22	2026-04-05 15:49:13.694781+00	Ig concameokhongat_22	0943354366	Chung cư đất phương nam chu văn an p12 quận bình thạnh 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-05 15:51:48.608+00	\N	\N
1035	#ADM-588479	797	\N	\N	350000	0	0	350000	cod	shipping	Ig kelsey	2026-04-05 12:36:28.563499+00	Ig kelsey	0829408425	 nhà 14 ngõ 66/16/3 Ngọc Thuỵ, Long Biên, Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	2026-04-05 12:42:13.717+00	\N	\N
1034	#ADM-562266	487	\N	\N	350000	0	0	350000	cod	shipping	Ig lưu thị điệp	2026-04-05 12:36:02.370304+00	Ig lưu thị điệp	0965256838	211 lê lâm phú thạnh tân phú	\N	\N	\N	unpaid	\N	\N	\N	2026-04-05 12:42:13.717+00	\N	\N
1033	#ADM-537765	796	\N	\N	300000	0	0	300000	cod	shipping	Ig irisngn	2026-04-05 12:35:37.842629+00	Ig irisngn	0905859393	Nhà 48, hoa phượng 3, vinhomes riverside long biên, phúc lợi, hà nội	\N	\N	\N	unpaid	\N	\N	\N	2026-04-05 12:42:13.717+00	\N	\N
1032	#ADM-478363	795	\N	\N	300000	0	0	300000	transfer	shipping	Ig sbryieeee [ĐÃ THANH TOÁN]	2026-04-05 12:34:38.479162+00	Ig sbryieeee	0903305740	411 Kha Vạn Cân, phường Hiệp Bình Chánh, TP Thủ Đức, Hồ Chí Minh (Quán Cao Nguyên Xanh)	\N	\N	\N	unpaid	\N	\N	\N	2026-04-05 12:42:13.717+00	\N	\N
1031	#ADM-431816	794	\N	\N	600000	0	0	600000	cod	shipping	Ig winnie	2026-04-05 12:33:51.912442+00	Ig winnie	0901202196	45/38 Nguyễn đôn tiết, phường Bình trưng Đông, quận 2, hcm	\N	\N	\N	unpaid	\N	\N	\N	2026-04-05 12:42:13.717+00	\N	\N
1030	#ADM-413090	793	\N	\N	350000	0	0	350000	cod	shipping	Ig _phbento	2026-04-05 12:33:33.193038+00	Ig _phbento	0867388676 	178 Trần Phú, p.Diên Hồng, tp Pleiku, Gia Lai 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-05 12:42:13.717+00	\N	\N
1029	#ADM-385608	792	\N	\N	300000	0	0	300000	cod	shipping	Ig tthaomay	2026-04-05 12:33:05.686484+00	Ig tthaomay	0394280699	72 Trần Hưng Đạo, phường Trần Hưng Đạo, TP Hạ Long, tỉnh Quảng Ninh\n	\N	\N	\N	unpaid	\N	\N	\N	2026-04-05 12:42:13.717+00	\N	\N
1046	#ADM-771021	806	\N	\N	1250000	0	0	1250000	cod	shipping	Ig bet.chayyyy	2026-04-05 15:59:31.122369+00	Ig bet.chayyyy	4086306196	1782 Penwood St, San Jose, CA 95133	\N	\N	\N	unpaid	\N	\N	\N	2026-04-05 16:47:04.929+00	\N	\N
1253	ORD-14141776181286	962	\N	\N	300000	0	0	300000	banking	shipping	\N	2026-04-14 15:41:26.042724+00	Nguyễn Khánh Linh	0345992382	93C, ngách 99/110 Định Công Hạ, Phường Định Công, Quận Hoàng Mai, Hà Nội	daizuki8@gmail.com	\N	SPXVN066764885194	unpaid	\N	1490	1A0802	2026-04-14 15:44:57.438+00	\N	\N
1060	#ADM-234330	40	\N	\N	300000	0	0	300000	transfer	cancelled	Ig bên vợ [ĐÃ THANH TOÁN]	2026-04-06 14:53:54.532344+00	Ig bên vợ	0933888347	 203 cao văn lầu p2 q6	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
1254	ORD-65451776191083	973	\N	\N	1000000	0	0	1000000	banking	pending	\N	2026-04-14 18:24:43.065344+00	Lê Ngọc Anh	033 2708119	Số 5 ngõ 44 hào nam phường ô chợ dừa đống đa hà nội, Phường Ô Chợ Dừa, Quận Đống Đa, Hà Nội	duong.xu.98@gmail.com	\N	\N	unpaid	\N	1486	1A0410	\N	\N	\N
1062	#ADM-315259	817	\N	\N	320000	0	0	320000	transfer	shipping	Ig anothermythh [ĐÃ THANH TOÁN]	2026-04-06 14:55:15.361685+00	Ig anothermythh	0932633789	49 vũ trọng phụng, p.tân thành quận tân phú tphcm	\N	\N	\N	unpaid	\N	\N	\N	2026-04-07 12:23:11.899+00	\N	\N
1047	ORD-45031775446414	808	\N	\N	550000	0	0	550000	banking	shipping	\N	2026-04-06 03:33:34.088822+00	Nguyễn Thị Thu Hiền	0966788294	Số 11, ngõ 18 Lê Hồng Phong, Phường Hưng Bình, Thành phố Vinh, Nghệ An		\N	\N	unpaid	\N	1617	290107	2026-04-06 14:56:34.495+00	\N	\N
1059	#ADM-174539	385	\N	\N	600000	0	25000	625000	transfer	shipping	Ig chl.____ [ĐÃ THANH TOÁN]	2026-04-06 14:52:54.644815+00	Ig chl.____	087 633 7187	315/18/6 Nguyễn Thị Tú, Phường Bình Hưng Hòa B, Quận Bình Tân, Hồ Chí Minh 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-06 14:56:34.495+00	\N	\N
1058	#ADM-011376	816	\N	\N	700000	0	0	700000	cod	shipping	Ig sithanh	2026-04-06 14:50:11.499507+00	Ig sithanh	0938709011	11 , đường 34 , an phú , q2 , thủ đưc	\N	\N	\N	unpaid	\N	\N	\N	2026-04-06 14:56:34.495+00	\N	\N
1057	#ADM-943568	815	\N	\N	300000	0	0	300000	cod	shipping	Ig vân	2026-04-06 14:49:03.656925+00	Ig vân	0903516873	141 đô đốc tuýet, hoà xuân, đà nẵng\n	\N	\N	\N	unpaid	\N	\N	\N	2026-04-06 14:56:34.495+00	\N	\N
1056	#ADM-920697	814	\N	\N	300000	0	0	300000	transfer	shipping	Ig tit.princess [ĐÃ THANH TOÁN]	2026-04-06 14:48:40.78844+00	Ig tit.princess	0378404004 	132 nguyễn trãi bến thành q1	\N	\N	\N	unpaid	\N	\N	\N	2026-04-06 14:56:34.495+00	\N	\N
1055	#ADM-898805	813	\N	\N	320000	0	0	320000	transfer	shipping	Ig nhu y [ĐÃ THANH TOÁN]	2026-04-06 14:48:18.897227+00	Ig nhu y	0942092705	947 Quang Trung,p14, Gò Vấp	\N	\N	\N	unpaid	\N	\N	\N	2026-04-06 14:56:34.495+00	\N	\N
1054	#ADM-877892	812	\N	\N	300000	0	0	300000	cod	shipping	Ig jade	2026-04-06 14:47:57.983526+00	Ig jade	 0964677183	Sảnh A, toà River, Chung cư Eurowindow, Đông Hội, Đông Anh, Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	2026-04-06 14:56:34.495+00	\N	\N
1053	#ADM-827467	71	\N	\N	300000	0	0	300000	transfer	shipping	Ig thu lê [ĐÃ THANH TOÁN]	2026-04-06 14:47:07.595762+00	Ig thu lê	789515460	khách ghé lấy	\N	\N	\N	unpaid	\N	\N	\N	2026-04-06 14:56:34.495+00	\N	\N
1052	#ADM-733965	811	\N	\N	600000	0	0	600000	cod	shipping	Ig __mhangg_	2026-04-06 14:45:34.11304+00	Ig __mhangg_	0869669092	221 Hoàng Hoa Thám, Ba Đình, Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	2026-04-06 14:56:34.495+00	\N	\N
1051	#ADM-629863	515	\N	\N	750000	0	25000	775000	transfer	shipping	Ig thriftwith [ĐÃ THANH TOÁN]	2026-04-06 14:43:50.024491+00	Ig thriftwith	0765488828	154 tuệ tĩnh p12 q11 tphcm VTV To Cambodian Monyrothna Leng TKK 067234568	\N	\N	\N	unpaid	\N	\N	\N	2026-04-06 14:56:34.495+00	\N	\N
1063	#ADM-353393	818	\N	\N	300000	0	0	300000	cod	shipping	Ig mynart	2026-04-06 14:55:53.516056+00	Ig mynart	0528626051	253 hoàng văn thụ p2 tân bình	\N	\N	\N	unpaid	\N	\N	\N	2026-04-07 12:23:11.899+00	\N	\N
1064	ORD-28081775487851	819	\N	\N	320000	0	0	320000	banking	shipping	\N	2026-04-06 15:04:11.07655+00	Nâu	0968654470	33 mạc đỉnh chi, Phường Đa Kao, Quận 1, Hồ Chí Minh	duongdiepnhuhuynh@gmail.com	\N	SPXVN069047171514	unpaid	\N	1442	20106	2026-04-07 12:23:11.899+00	\N	\N
1065	#ADM-885385	345	\N	\N	320000	0	0	320000	cod	shipping	Ig ngân	2026-04-06 15:04:45.502014+00	Ig ngân	0356848574	đường số 6 khu phố 4 hịệp bình 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-07 12:23:11.899+00	\N	\N
1068	ORD-97271775496170	821	\N	\N	320000	0	0	320000	banking	shipping	\N	2026-04-06 17:22:50.211704+00	Quỳnh Anh	0961859543	The Marq - Căn hộ A20.10, 29B Nguyễn Đình Chiểu, Phường Đa Kao, Quận 1, Hồ Chí Minh	nghoangquynhanh@gmail.com	\N	SPXVN062514306944	unpaid	\N	1442	20106	2026-04-07 14:08:10.747+00	\N	\N
1069	ORD-49121775496171	822	\N	\N	350000	0	0	350000	banking	shipping	\N	2026-04-06 17:22:51.352344+00	Duy Ngọc	0779512164	148/7 Hoàng Diệu 2, Phường Linh Chiểu, Thành Phố Thủ Đức, Hồ Chí Minh	phanthiduyngoc@gmail.com	\N	SPXVN063169717984	unpaid	\N	3695	90742	2026-04-07 14:08:10.747+00	\N	\N
1070	ORD-11651775533961	823	\N	\N	300000	0	0	300000	banking	shipping	\N	2026-04-07 03:52:41.477806+00	Jun 	0966401556	Nhà số 7 ngõ 91 Đặng Tiến Đông, Phường Trung Liệt, Quận Đống Đa, Hà Nội		\N	SPXVN063756889484	unpaid	\N	1486	1A0417	2026-04-07 14:08:10.747+00	\N	\N
1083	#ADM-458967	830	\N	\N	300000	0	0	300000	cod	shipping	Ig amy	2026-04-07 14:00:59.057874+00	Ig amy	0939312605	Số 4 dương văn dương, phường sơn kỳ, quận tân phú, hcm	\N	\N	\N	unpaid	\N	\N	\N	2026-04-07 14:08:10.747+00	\N	\N
1082	#ADM-408350	829	\N	\N	700000	0	0	700000	cod	shipping	Ig tống gia yến	2026-04-07 14:00:08.44904+00	Ig tống gia yến	0868745716	41 Trần Quang diệu khu phố 2 thị trấn Đông Nam Phước Vĩnh huyện Phú Giáo tỉnh Bình dương	\N	\N	\N	unpaid	\N	\N	\N	2026-04-07 14:08:10.747+00	\N	\N
1087	#ADM-706041	834	\N	\N	350000	0	0	350000	transfer	shipping	Ig huỳnh nhi [ĐÃ THANH TOÁN]	2026-04-07 14:05:06.184617+00	Ig huỳnh nhi	0768024698	153/10b nguyễn Thông q3 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-07 14:08:10.747+00	\N	\N
1086	#ADM-665455	833	\N	\N	650000	0	15000	665000	transfer	shipping	Ig itduongnhieuda [ĐÃ THANH TOÁN]	2026-04-07 14:04:25.58325+00	Ig itduongnhieuda	(+84) 886 144 500	Kí Túc Xá Đh Mỹ Thuật, 27/15 Đường 27 Phường Hiệp Bình Chánh, Thành Phố Thủ Đức	\N	\N	\N	unpaid	\N	\N	\N	2026-04-07 14:08:10.747+00	\N	\N
1076	ORD-94921775568657	827	\N	\N	300000	0	0	300000	banking	shipping	\N	2026-04-07 13:30:56.715523+00	Tú Anh	0365699083	40 Phan Đăng Lưu, Kiến An, Phường Trần Thành Ngọ, Quận Kiến An, Hải Phòng	Anhltt201@gmail.com	\N	SPXVN062634266004	unpaid	\N	1590	30408	2026-04-07 14:08:10.747+00	\N	\N
1085	#ADM-512493	832	\N	\N	300000	0	0	300000	cod	shipping	Ig ningning	2026-04-07 14:01:52.588626+00	Ig ningning	0363423121	205 yên duyên yên sở hoàng mai hn	\N	\N	\N	unpaid	\N	\N	\N	2026-04-07 14:08:10.747+00	\N	\N
1090	#ADM-048051	837	\N	\N	600000	0	0	600000	cod	shipping	Ig ivy trúc phương	2026-04-07 14:44:08.232519+00	Ig ivy trúc phương	0345203628	577/8 , ấp Tân Đông , xã Mỹ Phú Đông , huyện Thoại Sơn , tỉnh An Giang	\N	\N	\N	unpaid	\N	\N	\N	2026-04-07 14:44:24.331+00	\N	\N
1089	#ADM-763020	836	\N	\N	300000	0	0	300000	cod	shipping	Ig haidiep	2026-04-07 14:06:03.11298+00	Ig haidiep	0339387192	55 Phố Tô Vĩnh Diện - Khương Đình - Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	2026-04-07 14:08:10.747+00	\N	\N
1088	#ADM-737667	835	\N	\N	600000	0	0	600000	cod	shipping	Ig phùng thuỳ dung	2026-04-07 14:05:37.757862+00	Ig phùng thuỳ dung	0383215995	S2.03 Ocean Park, Đa Tốn, Gia Lâm, HN	\N	\N	\N	unpaid	\N	\N	\N	2026-04-07 14:08:10.747+00	\N	\N
1084	#ADM-485150	831	\N	\N	350000	0	0	350000	transfer	shipping	Ig thu đông [ĐÃ THANH TOÁN]	2026-04-07 14:01:25.241812+00	Ig thu đông	0939872600	267/61b bùi đình tuý, bình thanh 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-07 14:08:10.747+00	\N	\N
1081	#ADM-380969	781	\N	\N	300000	0	0	300000	cod	shipping	Ig suhyn	2026-04-07 13:59:41.067318+00	Ig suhyn	0946340006	57, đường số 1 khu tái định cư phường Tương Bình Hiệp tp TDM Bình Dương	\N	\N	\N	unpaid	\N	\N	\N	2026-04-07 14:08:10.747+00	\N	\N
1080	#ADM-351694	238	\N	\N	320000	0	15000	335000	transfer	shipping	Ig ngô thị an [ĐÃ THANH TOÁN]	2026-04-07 13:59:11.794262+00	Ig ngô thị an	092.379.3678	Mặt sau số 168 Trần Thủ Độ, Pháp Vân, Hoàng Liệt, Hoàng Mai, Hà Nội\n(ค้นหา 🔍 sân bóng Đại An)	\N	\N	\N	unpaid	\N	\N	\N	2026-04-07 14:08:10.747+00	\N	\N
1079	#ADM-305701	55	\N	\N	600000	0	25000	625000	transfer	shipping	Ig bowbangkok.staff [ĐÃ THANH TOÁN]	2026-04-07 13:58:25.821718+00	Ig bowbangkok.staff	0369166.222	( BN2705)\n163 Trương Thị Hoa, phường Tân Thới Hiệp, Quận 12, thành phố Hồ Chí Minh\n	\N	\N	\N	unpaid	\N	\N	\N	2026-04-07 14:08:10.747+00	\N	\N
1078	#ADM-254795	71	\N	\N	350000	0	0	350000	transfer	shipping	Ig feiyin  [ĐÃ THANH TOÁN]	2026-04-07 13:57:34.924229+00	Ig feiyin 	789515460	khách ghé lấy	\N	\N	\N	unpaid	\N	\N	\N	2026-04-07 14:08:10.747+00	\N	\N
1077	#ADM-216139	828	\N	\N	300000	0	0	300000	cod	shipping	Ig phan ngọc thơ	2026-04-07 13:56:56.288506+00	Ig phan ngọc thơ	0389211072	chung cư rivergate 155 bến vân đồn quận 4	\N	\N	\N	unpaid	\N	\N	\N	2026-04-07 14:08:10.747+00	\N	\N
1075	#ADM-628385	826	\N	\N	620000	0	30000	650000	transfer	shipping	Ig prepretty [ĐÃ THANH TOÁN]	2026-04-07 04:20:28.489579+00	Ig prepretty	+84-818999538	7/1 Hồ Biểu Chánh, Phú Nhuận, TP. Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	2026-04-07 14:08:10.747+00	\N	\N
1074	#ADM-566933	825	\N	\N	300000	0	0	300000	cod	shipping	Ig 1808kg_	2026-04-07 04:19:27.048031+00	Ig 1808kg_	0708474923	144 Trần Phú khóm2 phường 1 Sa Đéc - Đồng Tháp	\N	\N	\N	unpaid	\N	\N	\N	2026-04-07 14:08:10.747+00	\N	\N
1073	#ADM-508187	824	\N	\N	600000	0	15000	615000	transfer	shipping	Ig lozova_hanna [ĐÃ THANH TOÁN]	2026-04-07 04:18:28.293117+00	Ig lozova_hanna	380990053866 	603 - 42/11 + 42/13 Da Tuong, Vinh Nguyen ward, Nha Trang city, Khanh Hoa province\n	\N	\N	\N	unpaid	\N	\N	\N	2026-04-07 14:08:10.747+00	\N	\N
1072	#ADM-429811	155	\N	\N	600000	0	35000	635000	transfer	shipping	Ig honeyfai [ĐÃ THANH TOÁN]	2026-04-07 04:17:09.930853+00	Ig honeyfai	0818999538   	M Village Ho Bieu Chanh 7 Hồ Biểu Chánh, Phường 12, Phú Nhuận, Thành phố Hồ Chí Minh, 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-07 14:08:10.747+00	\N	\N
1071	#ADM-327663	477	\N	\N	2600000	0	0	2600000	transfer	shipping	Ig jamie [ĐÃ THANH TOÁN]	2026-04-07 04:15:27.782715+00	Ig jamie	0383163470	SHUNFEI （#43301）\nSố 160/46 Phan huy ích ，Phường 12 ，quận Gò Vấp TP Hồ Chí Minh, Phường 12, Quận Gò Vấp, Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	2026-04-07 14:08:10.747+00	\N	\N
1067	#ADM-286749	820	\N	\N	300000	0	0	300000	cod	shipping	Ig nguyễn trần bảo linh	2026-04-06 16:01:26.844972+00	Ig nguyễn trần bảo linh	0368933154	201/65/14 Nguyễn Xí Bình Thạnh HCM	\N	\N	\N	unpaid	\N	\N	\N	2026-04-07 14:08:10.747+00	\N	\N
1066	#ADM-256049	86	\N	\N	300000	0	0	300000	cod	shipping	Ig thu vo	2026-04-06 16:00:56.48147+00	Ig thu vo	0932221092	7b/105/24 thành thái f14 q10	\N	\N	\N	unpaid	\N	\N	\N	2026-04-07 14:08:10.747+00	\N	\N
1092	#ADM-121237	839	\N	\N	600000	0	0	600000	cod	shipping	Ig thuỳvân nguyễn	2026-04-07 16:08:41.347467+00	Ig thuỳvân nguyễn	0938122996	tòa nhà cảng vụ hàng không miền nam, sân bay tân sơn nhất, đường trường sơn, p2, tân bình  	\N	\N	\N	unpaid	\N	\N	\N	2026-04-07 16:11:57.354+00	\N	\N
1091	ORD-34641775575542	838	\N	\N	600000	0	0	600000	banking	shipping	\N	2026-04-07 15:25:42.456258+00	Nguyễn Cẩm Nhung	0344325671	Khu tập thể in ngân hàng, phố Tôn Đức Thắng, Phường Hàng Bột, Quận Đống Đa, Hà Nội	nguyencamnhung152641@gmail.com	\N	SPXVN062158648084	unpaid	\N	1486	1A0402	2026-04-07 16:11:57.354+00	\N	\N
1094	#ADM-623450	5	\N	\N	420000	0	0	420000	transfer	cancelled	test [ĐÃ THANH TOÁN]	2026-04-08 10:03:43.597613+00	Test	0979911670	15 NXK	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
1093	#ADM-242983	840	\N	\N	650000	0	0	650000	transfer	shipping	Ig vy [ĐÃ THANH TOÁN]	2026-04-07 16:44:03.085544+00	Ig vy	0818924998 	121 cô giang, phường Cầu ông lãnh\n\n	\N	\N	\N	unpaid	\N	\N	\N	2026-04-08 15:24:49.283+00	\N	\N
1158	#ADM-945896	71	\N	\N	300000	0	0	300000	transfer	shipping	Ig vytrxn [ĐÃ THANH TOÁN]	2026-04-11 10:05:45.9959+00	Ig vytrxn	789515460	148 lê bình phuong 4. Tân binh	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1110	ORD-36561775661428	5	\N	\N	600000	0	0	600000	banking	cancelled	\N	2026-04-08 15:17:08.401999+00	Test	0979911670	15 NXK , Phường Tân Thành, Quận Tân Phú, Hồ Chí Minh	domquangminhtriet17@gmail.com	\N	\N	unpaid	\N	1456	21509	\N	\N	\N
1095	ORD-33461775645693	842	\N	\N	700000	0	0	700000	banking	shipping	\N	2026-04-08 10:54:53.206405+00	Nguyễn Tường Vi 	0918452222	Ấp 3 , Xã Khánh Hội, Huyện U Minh, Cà Mau		\N	SPXVN065148563224	unpaid	\N	2042	610304	2026-04-08 15:24:49.283+00	\N	\N
1096	#ADM-613271	273	\N	\N	365000	0	0	365000	transfer	shipping	Ig qingyi8802 [ĐÃ THANH TOÁN]	2026-04-08 14:46:53.379104+00	Ig qingyi8802	0396504228	Số 51, ngõ 31, B6 Khu nhà ở Mai Dịch, đường Nguyễn Khả Trạc, Phường Phú Diễn, Thành phố Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	2026-04-08 15:24:49.283+00	\N	\N
1097	#ADM-947459	843	\N	\N	350000	0	0	350000	cod	shipping	Ig noemie paris bảo nhi	2026-04-08 15:09:07.605803+00	Ig noemie paris bảo nhi	0903010865	citi alto cát lái block D 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-08 15:24:49.283+00	\N	\N
1105	#ADM-256886	71	\N	\N	650000	0	0	650000	transfer	shipping	Ig anh trat [ĐÃ THANH TOÁN]	2026-04-08 15:14:17.10313+00	Ig anh trat	789515460	Khách đặt hoả tốc	\N	\N	\N	unpaid	\N	\N	\N	2026-04-08 15:24:49.283+00	\N	\N
1104	#ADM-183938	850	\N	\N	300000	0	0	300000	transfer	shipping	Ig nguyen hoang yen nhi [ĐÃ THANH TOÁN]	2026-04-08 15:13:04.061719+00	Ig nguyen hoang yen nhi	0912516282	Căn C105, chung cư Hiệp Thành 3, đường số 8, phường Hiệp Thành, Thủ Dầu Một, Bình Dương	\N	\N	\N	unpaid	\N	\N	\N	2026-04-08 15:24:49.283+00	\N	\N
1103	#ADM-158183	849	\N	\N	350000	0	0	350000	cod	shipping	Ig hin	2026-04-08 15:12:38.29805+00	Ig hin	0787887362	Nhà trọ Minh Nhựt, 113, Đường 3/2, An Bình, Ninh Kiều, Cần Thơ	\N	\N	\N	unpaid	\N	\N	\N	2026-04-08 15:24:49.283+00	\N	\N
1102	#ADM-129850	848	\N	\N	300000	0	0	300000	transfer	shipping	Ig thy thy [ĐÃ THANH TOÁN]	2026-04-08 15:12:09.953774+00	Ig thy thy	0896562195	625 nguyễn đình chiểu phường bàn cờ quận 3	\N	\N	\N	unpaid	\N	\N	\N	2026-04-08 15:24:49.283+00	\N	\N
1101	#ADM-105963	847	\N	\N	1850000	0	0	1850000	cod	shipping	Ig _ntuynnn	2026-04-08 15:11:46.130638+00	Ig _ntuynnn	0923757531	số 10 hưng gia 3 phường tân phong quận 7\n	\N	\N	\N	unpaid	\N	\N	\N	2026-04-08 15:24:49.283+00	\N	\N
1100	#ADM-045537	846	\N	\N	300000	0	0	300000	cod	shipping	Ig bống	2026-04-08 15:10:45.647134+00	Ig bống	0367229158	Địa chỉ: 167 Cộng Hoà, p.12, Tân Bình	\N	\N	\N	unpaid	\N	\N	\N	2026-04-08 15:24:49.283+00	\N	\N
1099	#ADM-015078	845	\N	\N	320000	0	0	320000	cod	shipping	Ig thechxxu	2026-04-08 15:10:15.213991+00	Ig thechxxu	0865409688	72a nguyễn trãi thanh xuân thượng đình Hà Nội \nChung cư roayl city r4 thương mại\n	\N	\N	\N	unpaid	\N	\N	\N	2026-04-08 15:24:49.283+00	\N	\N
1098	#ADM-976335	844	\N	\N	350000	0	0	350000	cod	shipping	Ig ynhinn.16	2026-04-08 15:09:36.439213+00	Ig ynhinn.16	0344425259	đội 19, thôn câu lâu tây, duy phước, duy xuyên, quảng nam 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-08 15:24:49.283+00	\N	\N
1118	#ADM-992189	859	\N	\N	300000	0	0	300000	transfer	shipping	Ig linh nguyen [ĐÃ THANH TOÁN]	2026-04-08 15:26:32.317767+00	Ig linh nguyen	0938400603	1A16 Đông Tây 1, An Phú, quận 2 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-08 15:26:46.687+00	\N	\N
1117	#ADM-697478	858	\N	\N	970000	0	0	970000	transfer	shipping	Ig plchmsva [ĐÃ THANH TOÁN]	2026-04-08 15:21:37.566991+00	Ig plchmsva	84368308053	Sth32A.12 Đường Số 37, Hà Quang 1, Nha Trang, Phường Phước Hải, Thành Phố Nha Trang, Khánh Hòa	\N	\N	\N	unpaid	\N	\N	\N	2026-04-08 15:24:49.283+00	\N	\N
1116	#ADM-571115	857	\N	\N	300000	0	0	300000	cod	shipping	Ig bu	2026-04-08 15:19:31.210898+00	Ig bu	0984761299	64 trần thị liền phước kiển nhà bè	\N	\N	\N	unpaid	\N	\N	\N	2026-04-08 15:24:49.283+00	\N	\N
1115	#ADM-547450	856	\N	\N	300000	0	0	300000	transfer	shipping	Ig T/anne [ĐÃ THANH TOÁN]	2026-04-08 15:19:07.547294+00	Ig T/anne	0969598289	56B Bà Triệu, Phường Cửa Nam, Hà Nội 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-08 15:24:49.283+00	\N	\N
1114	#ADM-519563	855	\N	\N	350000	0	0	350000	cod	shipping	Ig tớ là chin	2026-04-08 15:18:39.654828+00	Ig tớ là chin	0929499652	48 đường số 31A, khu đô thị An Phú An Khánh, Phường An Phú, Thủ Đức	\N	\N	\N	unpaid	\N	\N	\N	2026-04-08 15:24:49.283+00	\N	\N
1113	#ADM-494579	854	\N	\N	300000	0	0	300000	cod	shipping	Ig poni	2026-04-08 15:18:14.734661+00	Ig poni	0376893928	· Đc: số nhà 26 ngách 48 ngõ 426 đường láng, đống đa, HN 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-08 15:24:49.283+00	\N	\N
1112	#ADM-458278	853	\N	\N	300000	0	0	300000	transfer	shipping	Ig trâm anh [ĐÃ THANH TOÁN]	2026-04-08 15:17:38.381565+00	Ig trâm anh	090 3879361	280/8 huỳnh văn bánh p11 phú nhuận	\N	\N	\N	unpaid	\N	\N	\N	2026-04-08 15:24:49.283+00	\N	\N
1111	#ADM-433195	540	\N	\N	650000	0	0	650000	transfer	shipping	Ig pee pov  [ĐÃ THANH TOÁN]	2026-04-08 15:17:13.309792+00	Ig pee pov 	0935906826	Hẻm 114/1 năm châu phường 12 quận tân bình tp hcm\n	\N	\N	\N	unpaid	\N	\N	\N	2026-04-08 15:24:49.283+00	\N	\N
1109	#ADM-371612	451	\N	\N	600000	0	0	600000	cod	shipping	Ig an	2026-04-08 15:16:11.729253+00	Ig an	0909056816	Số Nhà 26 Lô U, Đường Cư Xá Phú Lâm D, Phường 10, Quận 6, TP. Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	2026-04-08 15:24:49.283+00	\N	\N
1108	#ADM-342660	9	\N	\N	550000	0	0	550000	cod	shipping	Ig jenni	2026-04-08 15:15:42.783304+00	Ig jenni	0911066568	Sky89, 89 Lê Thị Chợ, quận 7 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-08 15:24:49.283+00	\N	\N
1107	#ADM-308811	852	\N	\N	300000	0	0	300000	cod	shipping	Ig bảo uyên	2026-04-08 15:15:08.91276+00	Ig bảo uyên	0938181222	18 trần hoành đà nẵng\nnguyễn bảo uyên\n	\N	\N	\N	unpaid	\N	\N	\N	2026-04-08 15:24:49.283+00	\N	\N
1106	#ADM-283814	851	\N	\N	250000	0	0	250000	transfer	shipping	Ig archivemehuh [ĐÃ THANH TOÁN]	2026-04-08 15:14:43.937928+00	Ig archivemehuh	0985835533	Địa chỉ 21 Trương Công Định,P14, Quận Tân Bình, HCM 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-08 15:24:49.283+00	\N	\N
1119	#ADM-708888	860	\N	\N	2300000	0	0	2300000	transfer	shipping	Ig jasmine [ĐÃ THANH TOÁN]	2026-04-08 16:28:29.036184+00	Ig jasmine	+852 9388 1755	66C Mount Davis Rd, Pok Fu Lam, Hong Kong\n	\N	\N	\N	unpaid	\N	\N	\N	2026-04-08 16:34:18.438+00	\N	\N
1120	#ADM-765095	861	\N	\N	600000	0	0	600000	cod	shipping	Ig vũ lâm oanh	2026-04-08 16:29:25.224274+00	Ig vũ lâm oanh	0866160699 	T3 times city, phường vĩnh tuy hn	\N	\N	\N	unpaid	\N	\N	\N	2026-04-08 16:34:18.438+00	\N	\N
1161	#ADM-673572	893	\N	\N	600000	0	0	600000	transfer	shipping	Ig nhật lệ [ĐÃ THANH TOÁN]	2026-04-11 10:17:53.669914+00	Ig nhật lệ	0384305303	132 bến vaan đồn cho mình 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1123	ORD-12781775744270	863	\N	\N	300000	0	0	300000	banking	shipping	\N	2026-04-09 14:17:50.471684+00	Như Thuỷ	0774455240	18 mỹ đa đông 3, Phường Mỹ An, Quận Ngũ Hành Sơn, Đà Nẵng	tp.ame284@gmail.com	\N	SPXVN068278235144	unpaid	\N	1529	40404	2026-04-09 15:05:57.173+00	\N	\N
1128	#ADM-784160	868	\N	\N	300000	0	0	300000	cod	shipping	Ig hhiihi.2409	2026-04-09 14:59:44.293429+00	Ig hhiihi.2409	(+84) 898 379 194	Uy ban nhân dân xã diên an, Xã Diên An, Huyện Diên Khánh, Khánh Hòa	\N	\N	\N	unpaid	\N	\N	\N	2026-04-09 15:05:57.173+00	\N	\N
1126	#ADM-380979	866	\N	\N	600000	0	0	600000	cod	shipping	Ig hoàng thạch	2026-04-09 14:53:01.086873+00	Ig hoàng thạch	0949877788	Block B, Căn B.23.10, chung cư Eco Green, 39B Nguyễn Văn Linh, Tân Thuận Tây, Quận 7, Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	2026-04-09 15:05:57.173+00	\N	\N
1125	#ADM-961937	865	\N	\N	300000	0	0	300000	transfer	shipping	Ig sylvie.lii [ĐÃ THANH TOÁN]	2026-04-09 14:46:02.0441+00	Ig sylvie.lii	0965892979	18/6 đường số 41 phường An Khánh Q2\n\n	\N	\N	\N	unpaid	\N	\N	\N	2026-04-09 15:05:57.173+00	\N	\N
1124	#ADM-921238	864	\N	\N	300000	0	0	300000	cod	shipping	Ig _._.kemne	2026-04-09 14:45:21.409333+00	Ig _._.kemne	0386181997	Chung cư paragon số 86 Duy Tân/ Dịch Vọng Hậu/ Cầu Giấy/ HN\n	\N	\N	\N	unpaid	\N	\N	\N	2026-04-09 15:05:57.173+00	\N	\N
1122	#ADM-721355	753	\N	\N	300000	0	0	300000	cod	shipping	Ig my võ	2026-04-09 02:45:21.500603+00	Ig my võ	0939806696	696 Trần Hưng Đạo, p.2, Q.5, tp.hcm	\N	\N	\N	unpaid	\N	\N	\N	2026-04-09 15:05:57.173+00	\N	\N
1121	#ADM-695292	71	\N	\N	350000	0	0	350000	transfer	shipping	Ig thanhthao_4  [ĐÃ THANH TOÁN]	2026-04-09 02:44:55.413645+00	Ig thanhthao_4 	789515460	Khách tự đặt ship	\N	\N	\N	unpaid	\N	\N	\N	2026-04-09 15:05:57.173+00	\N	\N
1168	#ADM-126628	898	\N	\N	320000	0	0	320000	transfer	shipping	Ig trangg_vht [ĐÃ THANH TOÁN]	2026-04-11 10:25:26.741672+00	Ig trangg_vht	 0328700916 	Số 96, Châu Văn Lồng, Phường Long Bình Tân, Thành Phố Biên Hòa, Đồng Nai	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1167	#ADM-998134	897	\N	\N	2200000	0	0	2200000	cod	shipping	Ig thena	2026-04-11 10:23:18.257222+00	Ig thena	530 360 8924	Tonicervantess@icloud.com\n3855 Archwood rd, cameron park CA 95682 USA	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1166	#ADM-852841	896	\N	\N	620000	0	0	620000	cod	shipping	Ig ngocquinh_	2026-04-11 10:20:52.936563+00	Ig ngocquinh_	0828020068	Nhà 2A Ngõ 322/95/29/30, Mỹ Đình 1 , Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1165	#ADM-824166	895	\N	\N	350000	0	0	350000	cod	shipping	Ig rítttt_hồ	2026-04-11 10:20:24.262088+00	Ig rítttt_hồ 	0909868757	Bãi Xe Container Thạnh Đức, Ấp 1, Xã Bình Đức, Tỉnh Tây Ninh (Long An cũ)	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1164	#ADM-792449	238	\N	\N	685000	0	0	685000	transfer	shipping	Ig ngô thị an ( K258)  [ĐÃ THANH TOÁN]	2026-04-11 10:19:52.554289+00	Ig ngô thị an ( K258) 	092.379.3678	Mặt sau số 168 Trần Thủ Độ, Pháp Vân, Hoàng Liệt, Hoàng Mai, Hà Nội\n(ค้นหา 🔍 sân bóng Đại A	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1162	#ADM-734634	894	\N	\N	300000	0	0	300000	transfer	shipping	Ig gn.archivesxx [ĐÃ THANH TOÁN]	2026-04-11 10:18:54.738597+00	Ig gn.archivesxx	‪+84 96 376 54 74‬ 	240/2A D. Le Thanh Ton Phuong Ben Thanh Quan 1 Thanh pho, Ben Thanh Hcm\n	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1160	#ADM-614344	892	\N	\N	350000	0	0	350000	transfer	shipping	Eden Comilang [ĐÃ THANH TOÁN]	2026-04-11 10:16:54.444135+00	Eden Comilang	0353896406	29 Huỳnh Văn Bánh, Phường 15, Phú Nhuận, Hồ Chí Minh 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1159	#ADM-180516	891	\N	\N	650000	0	0	650000	transfer	shipping	Ig aren_pre [ĐÃ THANH TOÁN]	2026-04-11 10:09:40.622195+00	Ig aren_pre	0879230235	793/10 trấn xuân soạn Q7, hcm	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1133	#ADM-079726	644	\N	\N	320000	0	0	320000	transfer	shipping	Ig huy lâm [ĐÃ THANH TOÁN]	2026-04-09 15:04:39.836858+00	Ig huy lâm	0938144013	73/18 huynh van banh\nP17 phu nhuan	\N	\N	\N	unpaid	\N	\N	\N	2026-04-09 15:05:57.173+00	\N	\N
1132	#ADM-046554	871	\N	\N	300000	0	0	300000	cod	shipping	Ig haahluu	2026-04-09 15:04:06.652074+00	Ig haahluu	0989273116	56 Lê Hồng Phong, phường Hà Cầu, quận Hà Đông, HN	\N	\N	\N	unpaid	\N	\N	\N	2026-04-09 15:05:57.173+00	\N	\N
1131	#ADM-021509	870	\N	\N	1000000	0	0	1000000	cod	shipping	Ig ngndd_	2026-04-09 15:03:41.614342+00	Ig ngndd_	0339653665	799/22/6 Nguyễn Kiệm, p3, Gò Vấp	\N	\N	\N	unpaid	\N	\N	\N	2026-04-09 15:05:57.173+00	\N	\N
1130	#ADM-988303	869	\N	\N	300000	0	0	300000	cod	shipping	Ig lê thảo	2026-04-09 15:03:08.402554+00	Ig lê thảo	  0795602420	235 gò xoài quận bình tân tp HCM 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-09 15:05:57.173+00	\N	\N
1129	#ADM-962656	55	\N	\N	1275000	0	0	1275000	transfer	shipping	Ig bowbkk.staff [ĐÃ THANH TOÁN]	2026-04-09 15:02:42.85025+00	Ig bowbkk.staff	0369166.222	( BN2705)\n163 Trương Thị Hoa, phường Tân Thới Hiệp, Quận 12, thành phố Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	2026-04-09 15:05:57.173+00	\N	\N
1127	#ADM-624589	867	\N	\N	3070000	0	0	3070000	transfer	shipping	Ig catherine phu [ĐÃ THANH TOÁN]	2026-04-09 14:57:04.753239+00	Ig catherine phu	(+84) 901 835 167	Building H, Midtown - The Peak M8, Unit 18.01, Đường số 16, Khu đô thị Phú Mỹ Hưng\nPhường Tân Phú, Quận 7, 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-09 15:05:57.173+00	\N	\N
1140	#ADM-432670	876	\N	\N	650000	0	0	650000	cod	cancelled	Ig trrngg	2026-04-10 03:07:13.082869+00	Ig trrngg	0765750384	428 Lê Hồng Phong, p1 q10\n	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
1139	ORD-57131775765180	875	\N	\N	350000	0	0	350000	banking	cancelled	\N	2026-04-09 20:06:20.360366+00	Đặng Ly	0888009921	Số nhà 9A, ngách 19 ngõ 127 Phùng Khoang, Phường Đại Mỗ, Quận Nam Từ Liêm, Hà Nội	imdangly@gmail.com	\N	\N	unpaid	\N	3440	13002	\N	\N	\N
1143	#ADM-101476	5	\N	\N	321000	0	0	321000	transfer	cancelled	tesst [ĐÃ THANH TOÁN]	2026-04-10 15:48:21.685747+00	Tesst	0979911670	15 NXK	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
1148	#ADM-580705	883	\N	\N	350000	0	0	350000	cod	cancelled	Ig quinn (quynh trang)	2026-04-11 09:59:40.804665+00	Ig quinn (quynh trang)	0909750265	216/1/1 Nguyễn Văn Hưởng thảo điền (phường an khánh mới)\nBi tím	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
1138	ORD-81141775765161	875	\N	\N	350000	0	0	350000	banking	shipping	\N	2026-04-09 20:06:01.06534+00	Đặng Ly	0888009921	Số nhà 9A, ngách 19 ngõ 127 Phùng Khoang, Phường Đại Mỗ, Quận Nam Từ Liêm, Hà Nội	imdangly@gmail.com	\N	SPXVN067139234114	unpaid	\N	3440	13002	2026-04-11 10:35:43.143+00	\N	\N
1141	ORD-64731775823863	877	\N	\N	950000	0	0	950000	banking	shipping	\N	2026-04-10 12:24:22.954628+00	Linh	0856111165	343/30 Trần Thủ Độ, Phường Phú Thạnh, Quận Tân Phú, Hồ Chí Minh		\N	SPXVN068215691964	unpaid	\N	1456	21503	2026-04-11 10:35:43.143+00	\N	\N
1142	ORD-96541775835102	878	\N	\N	300000	0	0	300000	banking	shipping	\N	2026-04-10 15:31:42.486968+00	Hồ Minh Mỹ Hảo	0902389940	74 Tô Hiệu, Phường Vĩnh Nguyên, Thành phố Nha Trang, Khánh Hòa	me.mm1505@gmail.com	\N	SPXVN064588582184	unpaid	\N	1548	410115	2026-04-11 10:35:43.143+00	\N	\N
1144	ORD-73661775869736	879	\N	\N	300000	0	0	300000	banking	shipping	\N	2026-04-11 01:08:55.79584+00	Khánh linh	0986579314	51 nguyên hồng - bích động - việt yên - bắc ninh ( bắc giang cũ ), Thị trấn Bích Động, Huyện Việt Yên, Bắc Giang	yen675663@gmail.com	\N	SPXVN065762659694	unpaid	\N	1763	180901	2026-04-11 10:35:43.143+00	\N	\N
1145	ORD-92341775880271	880	\N	\N	320000	0	0	320000	banking	shipping	\N	2026-04-11 04:04:31.054726+00	Hoàng Ái Vy	0833179044	43 ngõ 33 Chùa Láng, Phường Láng Thượng, Quận Đống Đa, Hà Nội	hoangaivy14012004@gmail.com	\N	SPXVN060015483414	unpaid	\N	1486	1A0407	2026-04-11 10:35:43.143+00	\N	\N
1146	ORD-21921775891400	881	\N	\N	350000	0	0	350000	banking	shipping	\N	2026-04-11 07:10:00.209298+00	Lê Giáng Mi	0902574526	2864/1b hẻm 99 đường an phú đông 10, Phường An Phú Đông, Quận 12, Hồ Chí Minh	gmi61127@gmail.com	\N	SPXVN062194385234	unpaid	\N	1454	21201	2026-04-11 10:35:43.143+00	\N	\N
1157	#ADM-911314	890	\N	\N	300000	0	0	300000	transfer	shipping	Ig milyn  [ĐÃ THANH TOÁN]	2026-04-11 10:05:11.414127+00	Ig milyn 	 0909333871	Bitexco, Ngô Đức Kế, P. Bến Nghé, Q1	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1156	#ADM-884002	889	\N	\N	350000	0	0	350000	cod	shipping	Ig nguyễn bảo trân	2026-04-11 10:04:44.110875+00	Ig nguyễn bảo trân	0903114446	135 phạm văn hai p5 tân bình	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1155	#ADM-862987	558	\N	\N	350000	0	0	350000	transfer	shipping	Ig JENNY [ĐÃ THANH TOÁN]	2026-04-11 10:04:23.113137+00	Ig JENNY	0586898742	khách đặt hoả tốc	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1154	#ADM-828420	888	\N	\N	600000	0	0	600000	transfer	shipping	Ig hongphuc1237 [ĐÃ THANH TOÁN]	2026-04-11 10:03:48.54375+00	Ig hongphuc1237	0963000866	35 tôn đức thắng p bến nghé quận 1 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1153	#ADM-789839	887	\N	\N	320000	0	0	320000	cod	shipping	Ig thỏ	2026-04-11 10:03:09.981663+00	Ig thỏ	0908223822	16/47/21 nguyễn thiện thuật q3	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1152	#ADM-746158	886	\N	\N	300000	0	0	300000	cod	shipping	Ig vũ lê	2026-04-11 10:02:26.33551+00	Ig vũ lê	0795600204	LôB 14-15 Nguyễn Đình Hoàn, P.Nại Hiên Đông, Q. Sơn Trà, TP. Đà Nẵng\n	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1151	#ADM-699927	885	\N	\N	670000	0	0	670000	transfer	shipping	Ig n.traang [ĐÃ THANH TOÁN]	2026-04-11 10:01:40.027221+00	Ig n.traang	0903208989	Biệt thự 25, khu đô thị Nghĩa Đô, ngõ 106 Hoàng Quốc Việt, p. Cổ Nhuế 1, Q. Bắc Từ Liêm, Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1150	#ADM-669432	883	\N	\N	350000	0	0	350000	transfer	shipping	Ig quinn (quynh trang) [ĐÃ THANH TOÁN]	2026-04-11 10:01:09.542639+00	Ig quinn (quynh trang)	0909750265	216/1/1 Nguyễn Văn Hưởng thảo điền (phường an khánh mới)\n\n	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1149	#ADM-612649	884	\N	\N	650000	0	0	650000	cod	shipping	Ig dydy_002	2026-04-11 10:00:13.165558+00	Ig dydy_002	0972632503 	17b nguyễn trãi , xuân hoà , long khánh 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1147	#ADM-443105	876	\N	\N	650000	0	0	650000	cod	shipping	Ig trrngg	2026-04-11 09:57:23.260053+00	Ig trrngg	0765750384	428 Lê Hồng Phong, p1 q10	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1137	#ADM-451615	854	\N	\N	350000	0	0	350000	cod	shipping	Ig poni	2026-04-09 17:24:11.780808+00	Ig poni	0376893928	 số nhà 26 ngách 48 ngõ 426 đường láng, đống đa, HN 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1136	#ADM-239405	874	\N	\N	350000	0	0	350000	transfer	shipping	Ig vy [ĐÃ THANH TOÁN]	2026-04-09 17:20:39.49327+00	Ig vy	0399136615 	V6-01 , Diamond brilliant , tân phú	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1135	#ADM-189844	873	\N	\N	1900000	0	0	1900000	cod	shipping	Ig cát tiên	2026-04-09 17:19:49.93419+00	Ig cát tiên	0901662195	16/2/4/10 đường 44 phường hiệp bình chánh, TP HCM	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1134	#ADM-982091	872	\N	\N	650000	0	0	650000	cod	shipping	Ig duyên đặng	2026-04-09 16:59:42.209964+00	Ig duyên đặng	0889632951	Số 48 ngõ 177 đường cầu diễn, nam từ liêm, hà nội	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1175	#ADM-678820	71	\N	\N	320000	0	0	320000	transfer	shipping	Ig lac ngoc nhi [ĐÃ THANH TOÁN]	2026-04-11 10:34:38.985993+00	Ig lac ngoc nhi	789515460	Khách đặt hoả tốc	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1174	#ADM-505659	904	\N	\N	1200000	0	0	1200000	transfer	shipping	Ig khailina  [ĐÃ THANH TOÁN]	2026-04-11 10:31:45.753336+00	Ig khailina 	0908315806	VietAviation Logistics Co., 6bis Thăng Long, Phường 4, Tân Bình, Ho Chi Minh, Vietnam  (Hồng -Truc Shanghai Hangzhou 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1173	#ADM-411955	903	\N	\N	300000	0	0	300000	transfer	shipping	Ig thiên thảo [ĐÃ THANH TOÁN]	2026-04-11 10:30:12.074427+00	Ig thiên thảo	0937501804	109/39 Nguyễn Thiện Thuật p2 q3 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1172	#ADM-377291	902	\N	\N	600000	0	0	600000	cod	shipping	Ig trâm anh	2026-04-11 10:29:37.385743+00	Ig trâm anh	0979251679	8/7 nguyễn đức cảnh, tp pleiku, gia lai 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1171	#ADM-336753	901	\N	\N	320000	0	0	320000	transfer	shipping	Ig soi215 [ĐÃ THANH TOÁN]	2026-04-11 10:28:56.86552+00	Ig soi215	032 7113054	15/7 Lương Thế Vinh, phường Xuân Hương, tp Đà Lạt\nPhương Thành	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1169	#ADM-197693	899	\N	\N	700000	0	0	700000	cod	shipping	Ig india ali	2026-04-11 10:26:37.812287+00	Ig india ali	9493242914	14271 jeffrey rd #194, irvine CA 92620	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1170	#ADM-307277	900	\N	\N	300000	0	0	300000	cod	returned	Ig ANNA_0000	2026-04-11 10:28:27.394811+00	Ig ANNA_0000	0585500046	400/35 nguyễn đức thiệu, dĩ an, dĩ an, bình dương	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 10:35:43.143+00	\N	\N
1202	#ADM-266334	829	\N	\N	300000	0	0	300000	cod	returned	Ig tống gia yến	2026-04-12 10:04:26.436564+00	Ig tống gia yến	0868745716	41 Trần Quang diệu khu phố 2 thị trấn Đông Nam Phước Vĩnh huyện Phú Giáo tỉnh Bình dương	\N	\N	\N	unpaid	\N	\N	\N	2026-04-12 15:27:10.472+00	\N	\N
1176	#ADM-872755	900	\N	\N	300000	0	0	300000	transfer	shipping	Ig ANNA_0000 [ĐÃ THANH TOÁN]	2026-04-11 11:44:32.919331+00	Ig ANNA_0000	0585500046	400/35 nguyễn đức thiệu, dĩ an, dĩ an, bình dương	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 11:59:16.196+00	\N	\N
1184	#ADM-540948	909	\N	\N	970000	0	0	970000	transfer	cancelled	Ig qazxcv74123 [ĐÃ THANH TOÁN]	2026-04-11 14:59:01.041139+00	Ig qazxcv74123	(+84) 343 621 271	Masa (Xưởng Số 6. Cty Sakura. Đối Diện INOX ASIA)Lô C3.1, Đường D 1, Khu Công Nghiệp Đồng An 2, Phường Hòa Phú, Thành Phố Thủ Dầu Một, Bình Dương	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
1187	#ADM-651056	911	\N	\N	320000	0	0	320000	transfer	shipping	Ig jauawjwh.171  [ĐÃ THANH TOÁN]	2026-04-11 15:00:51.173788+00	Ig jauawjwh.171 	0339876978	26 phan đình phùng-liên nghĩa-đức trọng-lâm đồng	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 15:04:09.887+00	\N	\N
1186	#ADM-626710	910	\N	\N	320000	0	0	320000	transfer	shipping	Ig emb3_raica [ĐÃ THANH TOÁN]	2026-04-11 15:00:26.798141+00	Ig emb3_raica	0914721224 	Uyên Khương\nOrange town 180A vườn lài, an phú đông, q12 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 15:04:09.887+00	\N	\N
1185	#ADM-606727	909	\N	\N	970000	0	0	970000	cod	shipping	Ig qazxcv74123	2026-04-11 15:00:06.832658+00	Ig qazxcv74123	(+84) 343 621 271	Masa (Xưởng Số 6. Cty Sakura. Đối Diện INOX ASIA)Lô C3.1, Đường D 1, Khu Công Nghiệp Đồng An 2, Phường Hòa Phú, Thành Phố Thủ Dầu Một, Bình Dương	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 15:04:09.887+00	\N	\N
1183	#ADM-498645	908	\N	\N	320000	0	0	320000	transfer	shipping	Ig yciiii_0.001 [ĐÃ THANH TOÁN]	2026-04-11 14:58:18.736907+00	Ig yciiii_0.001	0353271774	 35/3A ấp 7, Xã Xuân Thới Thượng, Hóc Môn, TPHCM 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 15:04:09.887+00	\N	\N
1182	#ADM-474197	907	\N	\N	320000	0	0	320000	cod	shipping	Ig nguyễn diễm quỳnh nga	2026-04-11 14:57:54.284046+00	Ig nguyễn diễm quỳnh nga	0334418259	Số nhà 68, ngõ 44 Trần Thái Tông,Dịch vọng hậu Cầu giấy\n	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 15:04:09.887+00	\N	\N
1181	#ADM-404074	906	\N	\N	300000	0	0	300000	cod	shipping	Ig quienphm	2026-04-11 14:56:44.161646+00	Ig quienphm	0706201066	 Lô 15 Ô CL 13 đường số 9 Hòn Rớ 2, xã Phước Đồng, Nha Trang\n	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 15:04:09.887+00	\N	\N
1180	#ADM-378262	905	\N	\N	320000	0	0	320000	cod	shipping	Ig ohsomeyeen	2026-04-11 14:56:18.379959+00	Ig ohsomeyeen	0849436685	87a hàm nghi, P Nguyễn Thái Bình, Q1	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 15:04:09.887+00	\N	\N
1179	#ADM-358260	71	\N	\N	320000	0	0	320000	transfer	shipping	Ig thanhhaaaa_2000 [ĐÃ THANH TOÁN]	2026-04-11 14:55:58.399709+00	Ig thanhhaaaa_2000	789515460	khách ghé lấy	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 15:04:09.887+00	\N	\N
1178	#ADM-701159	18	\N	\N	1050000	0	0	1050000	transfer	shipping	ig july nhật vy [ĐÃ THANH TOÁN]	2026-04-11 11:58:21.283998+00	ig july nhật vy	0789515460	khách ghé lấy	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 11:59:16.196+00	\N	\N
1177	#ADM-592526	215	\N	\N	320000	0	0	320000	transfer	shipping	0000ig kate lin [ĐÃ THANH TOÁN]	2026-04-11 11:56:32.742462+00	ig kate lin	+84938203196	saigon royal 09 nguyễn trường tộ phường cóm chiếu quận 5	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 11:59:16.196+00	\N	\N
1205	#ADM-414877	927	\N	\N	350000	0	0	350000	cod	shipping	Ig teddy	2026-04-12 10:06:54.981506+00	Ig teddy	0914649545	355/6 đường bùi quốc khánh phường chánh nghĩa thủ dầu một Bình Dương 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-12 15:27:10.472+00	\N	\N
1204	#ADM-387621	926	\N	\N	700000	0	0	700000	transfer	shipping	Ig bánh cờ rếp [ĐÃ THANH TOÁN]	2026-04-12 10:06:27.719129+00	Ig bánh cờ rếp	0375451108	656/19 cmt8 p11 q3	\N	\N	\N	unpaid	\N	\N	\N	2026-04-12 15:27:10.472+00	\N	\N
1203	#ADM-335253	925	\N	\N	965000	0	0	965000	transfer	shipping	Ig Presaigon.bkk [ĐÃ THANH TOÁN]	2026-04-12 10:05:35.347814+00	Ig Presaigon.bkk	0355180235	31c, phố Thanh Am, phường Thượng Thanh, quận Long Biên, Hà Nội.”	\N	\N	\N	unpaid	\N	\N	\N	2026-04-12 15:27:10.472+00	\N	\N
1201	#ADM-240870	924	\N	\N	350000	0	0	350000	cod	shipping	Ig lê ngọc mai	2026-04-12 10:04:00.970949+00	Ig lê ngọc mai	0916586373	98 chu văn an phường 26, bình thanh 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-12 15:27:10.472+00	\N	\N
1200	#ADM-206184	71	\N	\N	620000	0	0	620000	transfer	shipping	Ig pham pham [ĐÃ THANH TOÁN]	2026-04-12 10:03:26.433283+00	Ig pham pham	789515460	khách đặt hoả tốc	\N	\N	\N	unpaid	\N	\N	\N	2026-04-12 15:27:10.472+00	\N	\N
1199	#ADM-169575	923	\N	\N	1335000	0	0	1335000	cod	shipping	Ig anastasiia_kinder	2026-04-12 10:02:49.679263+00	 Ig anastasiia_kinder	+84342253533	Scenia Bay, Phường Vĩnh Hải, Nha Trang City, Khanh Hoa Province.	\N	\N	\N	unpaid	\N	\N	\N	2026-04-12 15:27:10.472+00	\N	\N
1198	#ADM-088051	922	\N	\N	350000	0	0	350000	cod	shipping	Ig hoàng hiếu	2026-04-12 10:01:28.152794+00	Ig hoàng hiếu 	0387825807	229/2D khu phố Thạnh bình phường an thạnh thành phố thuận an tỉnh bình dương	\N	\N	\N	unpaid	\N	\N	\N	2026-04-12 15:27:10.472+00	\N	\N
1197	#ADM-059510	921	\N	\N	350000	0	0	350000	cod	shipping	Ig mỹ uyên	2026-04-12 10:00:59.676025+00	Ig mỹ uyên	0353679949	10 nguyễn thị minh khai, phường phú nhuận, quận thuận hoá, thành phố huế	\N	\N	\N	unpaid	\N	\N	\N	2026-04-12 15:27:10.472+00	\N	\N
1196	#ADM-006171	920	\N	\N	900000	0	0	900000	cod	shipping	Ig lily	2026-04-12 10:00:06.292445+00	Ig lily	0908040593	2/8 đường số 31, P.An Khánh, Q.2	\N	\N	\N	unpaid	\N	\N	\N	2026-04-12 15:27:10.472+00	\N	\N
1206	#ADM-415061	928	\N	\N	350000	0	0	350000	cod	returned	Ig teddy	2026-04-12 10:06:55.163705+00	Ig teddy	0914649545	355/6 đường bùi quốc khánh phường chánh nghĩa thủ dầu một Bình Dương 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-12 15:27:10.472+00	\N	\N
1191	#ADM-785584	915	\N	\N	1590000	0	0	1590000	transfer	shipping	Ig ngọc nguyễn [ĐÃ THANH TOÁN]	2026-04-11 15:03:05.685716+00	Ig ngọc nguyễn	0369552337	Ấp 4 Xã Mỹ Tân thành phố Cao Lãnh tỉnh Đồng tháp( ngay chợ bình Trị)\n	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 15:04:09.887+00	\N	\N
1190	#ADM-755896	914	\N	\N	615000	0	0	615000	transfer	shipping	Ig kitty [ĐÃ THANH TOÁN]	2026-04-11 15:02:36.012526+00	Ig kitty	0926777966	Amamy JAHX73 Ngọc\n(Cửa hàng Amamy Post đối diện số nhà 56 ngách 93/20, ngõ 93 Hoàng Văn Thái, Khương Trung, Thanh Xuân, Hà Nội)	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 15:04:09.887+00	\N	\N
1189	#ADM-705816	913	\N	\N	650000	0	0	650000	transfer	shipping	Ig hoài danh [ĐÃ THANH TOÁN]	2026-04-11 15:01:45.927906+00	Ig hoài danh	0937720053	: 128/78C Lê Văn Duyệt, phường 1, quận Bình Thạnh, TP.HCM\n	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 15:04:09.887+00	\N	\N
1188	#ADM-680186	912	\N	\N	320000	0	0	320000	cod	shipping	Ig hathuylinh.eyelash	2026-04-11 15:01:20.32246+00	Ig hathuylinh.eyelash	0961571039	4 Long biên 2 long biên hn \n	\N	\N	\N	unpaid	\N	\N	\N	2026-04-11 15:04:09.887+00	\N	\N
1195	#ADM-961092	919	\N	\N	350000	0	0	350000	transfer	shipping	Ig Béeeeee Kemmm [ĐÃ THANH TOÁN]	2026-04-12 09:59:21.18856+00	Ig Béeeeee Kemmm	0356478016	87/29 đường số 27 p6 gò vấp	\N	\N	\N	unpaid	\N	\N	\N	2026-04-12 15:27:10.472+00	\N	\N
1194	#ADM-929666	918	\N	\N	320000	0	0	320000	cod	shipping	Ig bim	2026-04-12 09:58:49.799768+00	Ig bim	0934730483 	430 Võ Văn Đặng, Hoà Hải, Ngũ Hành Sơn, Đà Nẵng ( ANNA's HOME )	\N	\N	\N	unpaid	\N	\N	\N	2026-04-12 15:27:10.472+00	\N	\N
1192	ORD-26521775968455	916	\N	\N	300000	0	0	300000	banking	shipping	\N	2026-04-12 04:34:15.065717+00	Hà Ngọc Anh	0975451521	18 đường số 14 Khu Đô Thị Vạn Phúc, Phường Hiệp Bình Phước, Thành Phố Thủ Đức, Hồ Chí Minh	ngocanhha0104@gmail.com	\N	SPXVN067543015564	unpaid	\N	3695	90740	2026-04-12 15:27:10.472+00	\N	\N
1193	ORD-35881775971118	917	\N	\N	300000	0	0	300000	banking	shipping	\N	2026-04-12 05:18:38.433102+00	Nguyễn Trần Lan Anh 	0919799472 	578 Hoàng Văn Thụ, Phường Lê Hồng Phong, Thành phố Quy Nhơn, Bình Định	anh.lannt153@gmail.com	\N	SPXVN065951798354	unpaid	\N	1662	370105	2026-04-12 15:27:10.472+00	\N	\N
1215	#ADM-533077	936	\N	\N	300000	0	0	300000	transfer	shipping	Ig hiếu kiên [ĐÃ THANH TOÁN]	2026-04-12 15:25:33.15337+00	Ig hiếu kiên	0355505838	214/2e vạn kiếp, phường 3, quận Bình Thạnh 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-12 15:27:10.472+00	\N	\N
1214	#ADM-498318	935	\N	\N	970000	0	0	970000	transfer	shipping	Ig celine pham [ĐÃ THANH TOÁN]	2026-04-12 15:24:58.417585+00	Ig celine pham	0931595999	10/119 Miếu Hai Xã, phường Hồ Nam, quận Lê Chân, TP. Hải Phòng	\N	\N	\N	unpaid	\N	\N	\N	2026-04-12 15:27:10.472+00	\N	\N
1213	#ADM-448469	101	\N	\N	350000	0	0	350000	cod	shipping	Ig meii	2026-04-12 15:24:08.574665+00	Ig meii	0841444661	332/34 độc lậ phú thọ hoà tân phú\n	\N	\N	\N	unpaid	\N	\N	\N	2026-04-12 15:27:10.472+00	\N	\N
1212	#ADM-414205	934	\N	\N	2170000	0	0	2170000	cod	shipping	Ig 777	2026-04-12 15:23:34.299888+00	Ig 777	07562744259	9 Grove shaw Kingswood, Surrey, KT20 6QL, United Kingdom	\N	\N	\N	unpaid	\N	\N	\N	2026-04-12 15:27:10.472+00	\N	\N
1218	#ADM-093156	939	\N	\N	320000	0	0	320000	transfer	shipping	Ig phương nhi võ [ĐÃ THANH TOÁN]	2026-04-13 07:41:33.304865+00	Ig phương nhi võ	0915591550	6g25 Trần Não, phường An Khánh, Quận 2 ( đầu hẽm 151 Trần Não) 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-13 16:55:22.552+00	\N	\N
1207	#ADM-460988	929	\N	\N	320000	0	0	320000	transfer	shipping	Ig lâm ánh quỳnh [ĐÃ THANH TOÁN]	2026-04-12 10:07:41.093354+00	Ig lâm ánh quỳnh	0775773167	Chung cư Citiesto - Cát Lái - Block C - Căn hộ C19.10	\N	\N	\N	unpaid	\N	\N	\N	2026-04-12 15:27:10.472+00	\N	\N
1217	ORD-60331776055665	938	\N	\N	950000	0	0	950000	banking	shipping	\N	2026-04-13 04:47:45.477143+00	Anh Phương	0933006410	220/15/9c âu cơ, Phường 9, Quận Tân Bình, Hồ Chí Minh	anhphuong.280698@gmail.com	\N	SPXVN062072341864	unpaid	\N	1455	21409	\N	\N	\N
1208	#ADM-518479	930	\N	\N	350000	0	0	350000	cod	shipping	Ig hangtr__	2026-04-12 10:08:38.576967+00	Ig hangtr__	0347135579	285 Đội Cấn, Liễu Giai, Ba Đình, HN giúp m nhé\n	\N	\N	\N	unpaid	\N	\N	\N	2026-04-13 16:55:22.552+00	\N	\N
1209	#ADM-942096	931	\N	\N	320000	0	0	320000	cod	shipping	Ig đoàn phương uyên	2026-04-12 15:15:42.156863+00	Ig đoàn phương uyên	0783694723	202  Hoàng Diệu , phường thanh sơn , phan rang ninh thuận 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-13 16:55:22.552+00	\N	\N
1210	#ADM-965793	932	\N	\N	300000	0	0	300000	cod	shipping	Ig thuỳ linh	2026-04-12 15:16:05.853238+00	Ig thuỳ linh	0345026058	152 hoa bằng,yên hoà,cầu giấy , hà nội	\N	\N	\N	unpaid	\N	\N	\N	2026-04-13 16:55:22.552+00	\N	\N
1211	#ADM-274778	933	\N	\N	350000	0	0	350000	cod	shipping	Ig mai thanh	2026-04-12 15:21:14.933692+00	Ig mai thanh 	+84) 528 593 977	Đường 27 giữa ngã tư số 8 số 10. Nhà tuyền đồ mỹ Xã Nghĩa Thành, Huyện Châu Đức, Bà Rịa - Vũng Tàu	\N	\N	\N	unpaid	\N	\N	\N	2026-04-13 16:55:22.552+00	\N	\N
1216	ORD-61511776010372	937	\N	\N	320000	0	0	320000	banking	shipping	\N	2026-04-12 16:12:52.157147+00	Minh Phương	0906140069	29 ngõ 19 Tố Hữu, Phường Trung Văn, Quận Nam Từ Liêm, Hà Nội	dominhphuong2911@gmail.com	\N	SPXVN060324710694	unpaid	\N	3440	13009	2026-04-13 16:55:22.552+00	\N	\N
1224	ORD-22821776081299	944	\N	\N	350000	0	0	350000	banking	shipping	\N	2026-04-13 11:54:59.112894+00	Bùi Ngọc Ánh	0359366756	Phòng M808, chung cư HDI, 158 Võ Chí Công, Phường Xuân La, Quận Tây Hồ, Hà Nội	anhbuingoc1999@gmail.com	\N	SPXVN069030643554	unpaid	\N	1492	1A0507	2026-04-13 16:55:22.552+00	\N	\N
1225	ORD-85741776083549	945	\N	\N	300000	0	0	300000	banking	shipping	\N	2026-04-13 12:32:28.966686+00	Nguyễn Ngọc Quỳnh Chi	0978781586	Số 2 - ngách 464/1 - Âu Cơ, Phường Nhật Tân, Quận Tây Hồ, Hà Nội	nnqc11082005@gmail.com	\N	SPXVN066670465534	unpaid	\N	1492	1A0502	2026-04-13 16:55:22.552+00	\N	\N
1233	#ADM-900304	949	\N	\N	320000	0	0	320000	transfer	cancelled	Ig thuỳ linh [ĐÃ THANH TOÁN]	2026-04-14 06:08:20.75887+00	Ig thuỳ linh	 0867716136	 Máy Xông Tinh Dầu , Máy Khuếch Tán Tinh Dầu Thiên Nhiên Lorita, 602/39/20, Đường Điện Biên Phủ, p22, quận Bình Thạnh, tp HCM.	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
1226	#ADM-714971	946	\N	\N	300000	0	0	300000	cod	shipping	Ig hnil	2026-04-13 16:45:15.067778+00	Ig hnil 	0936526288	 số 502 Tôn Đức Thắng - phường An Đồng - quận An Dương - tp Hải Phòng	\N	\N	\N	unpaid	\N	\N	\N	2026-04-13 16:55:22.552+00	\N	\N
1227	#ADM-816802	947	\N	\N	925000	0	0	925000	transfer	shipping	Ig nanfeng.studio  [ĐÃ THANH TOÁN]	2026-04-13 16:46:56.913416+00	Ig nanfeng.studio 	0976387001	 20 Tân Thới Nhất 17, Phường Tân Thới Nhất, Quận 12, Thành phố Hồ Chí Minh	\N	\N	\N	unpaid	\N	\N	\N	2026-04-13 16:55:22.552+00	\N	\N
1228	#ADM-844943	948	\N	\N	300000	0	0	300000	cod	shipping	Ig baobeiii	2026-04-13 16:47:25.045623+00	Ig baobeiii	0976248195	463 An Dương Vương, Đông Ngạc, Bắc Từ Liêm, Hà Nội 	\N	\N	\N	unpaid	\N	\N	\N	2026-04-13 16:55:22.552+00	\N	\N
1229	#ADM-928522	949	\N	\N	320000	0	0	320000	transfer	shipping	Ig thuỳ linh [ĐÃ THANH TOÁN]	2026-04-13 17:05:28.613776+00	Ig thuỳ linh	 0867716136	 Máy Xông Tinh Dầu , Máy Khuếch Tán Tinh Dầu Thiên Nhiên Lorita, 602/39/20, Đường Điện Biên Phủ, p22, quận Bình Thạnh, tp HCM.	\N	\N	\N	unpaid	\N	\N	\N	2026-04-13 17:05:47.429+00	\N	\N
1231	#ADM-893218	951	\N	\N	978000	0	0	978000	transfer	shipping	Ig donfetch [ĐÃ THANH TOÁN]	2026-04-13 17:21:33.365489+00	Ig donfetch	0886508026	8C lam son , tan binh, HCMC\nRoom 203	\N	\N	\N	unpaid	\N	\N	\N	2026-04-13 17:22:21.612+00	\N	\N
1223	#ADM-272303	943	\N	\N	300000	0	0	300000	transfer	shipping	Ig camtien_ [ĐÃ THANH TOÁN]	2026-04-13 07:44:32.410818+00	Ig camtien_	0382679931	146 Nguyễn đình chiểu phường 6 (địa chỉ mới phường Xuân Hoà), quận 3, TPHCM\nToà nhà Endovina Tower	\N	\N	\N	unpaid	\N	\N	\N	2026-04-13 16:55:22.552+00	\N	\N
1222	#ADM-243359	942	\N	\N	680000	0	0	680000	transfer	shipping	Ig eint_chit3 [ĐÃ THANH TOÁN]	2026-04-13 07:44:03.499499+00	Ig eint_chit3	0798361288	341/17c lạc Long quân phường 5 quận 11 tp HCM	\N	\N	\N	unpaid	\N	\N	\N	2026-04-13 16:55:22.552+00	\N	\N
1221	#ADM-196227	27	\N	\N	600000	0	0	600000	cod	shipping	Ig inthezone.02.04	2026-04-13 07:43:16.344973+00	Ig inthezone.02.04	0962645716 	Thái Phụng 385F/39A-B, Đ. Trần Nam Phú, An Khánh, Ninh Kiều, Cần Thơ	\N	\N	\N	unpaid	\N	\N	\N	2026-04-13 16:55:22.552+00	\N	\N
1220	#ADM-167934	941	\N	\N	300000	0	0	300000	cod	shipping	Ig thảo nguyên	2026-04-13 07:42:48.036326+00	Ig thảo nguyên	0389525658	Tầng 5, tòa nhà 29T1, đường Hoàng Đạo Thúy, Phường Yên Hoà, Thành phố Hà Nội, Việt Nam	\N	\N	\N	unpaid	\N	\N	\N	2026-04-13 16:55:22.552+00	\N	\N
1219	#ADM-142940	940	\N	\N	1250000	0	0	1250000	cod	shipping	Ig ngọc anh nguyễn	2026-04-13 07:42:23.059044+00	Ig ngọc anh nguyễn 	0896025025	số nhà 76, đường 23, khu đô thị thành phố Giao Lưu, Cổ Nhuế 2, quan Bắc Từ Liêm, Hà Nội	\N	\N	\N	unpaid	\N	\N	\N	2026-04-13 16:55:22.552+00	\N	\N
1235	#ADM-335228	955	\N	\N	300000	0	0	300000	cod	cancelled	Ig hạnh nguyên	2026-04-14 06:15:35.366485+00	Ig hạnh nguyên	0832204686	Đường số 1 khu dân cư Thạnh Mỹ phường Lê Bình quận Cái Răng Cần Thơ	\N	\N	\N	unpaid	\N	\N	\N	\N	\N	\N
1230	ORD-51471776100299	950	\N	\N	300000	0	0	300000	banking	shipping	\N	2026-04-13 17:11:39.230083+00	Nguyễn Ngọc Bảo Trân	0337085521	461 Trần Phú (Cửa Hàng Phụ Kiện Điện Thoại Hoàng Kim), Phường 7, Quận 5, Hồ Chí Minh	baotran12022019@gmail.com	\N	SPXVN060997758734	unpaid	\N	1447	20507	2026-04-13 17:22:21.612+00	\N	\N
1232	ORD-71251776107153	952	\N	\N	350000	0	0	350000	banking	shipping	\N	2026-04-13 19:05:53.042815+00	Trúc 	+84 90 6964204	Sunrise city north toà x2 căn 2405, Phường Tân Hưng, Quận 7, Hồ Chí Minh	thanhtructruong2014@gmail.com	\N	SPXVN065265699204	unpaid	\N	1449	20704	2026-04-14 15:32:14.742+00	\N	\N
1236	#ADM-360196	956	\N	\N	300000	0	0	300000	cod	shipping	Ig i am autumn	2026-04-14 06:16:00.316663+00	Ig i am autumn	0866841318	số 14 ngõ 252 ngõ chợ khâm thiên, phường trung phụng, quận đống đa, hà nội	\N	\N	\N	unpaid	\N	\N	\N	2026-04-14 15:32:14.742+00	\N	\N
1234	#ADM-003956	954	\N	\N	250000	0	0	250000	cod	shipping	Ig Kl Lil Như	2026-04-14 06:10:04.102729+00	Ig Kl Lil Như	0777783293	B2810 Sun Cosmo, Trần Thị Lý,Ngũ Hành Sơn, Đà Nẵng\n	\N	\N	\N	unpaid	\N	\N	\N	2026-04-14 15:32:14.742+00	\N	\N
\.


--
-- TOC entry 4086 (class 0 OID 23128)
-- Dependencies: 426
-- Data for Name: product_collections; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.product_collections (product_id, category_id) FROM stdin;
10	1
13	1
12	2
\.


--
-- TOC entry 4058 (class 0 OID 17522)
-- Dependencies: 398
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.products (id, name, slug, description, base_price, images, is_active, created_at, category_id, size_chart_url, name_en, description_en, is_preorder, preorder_note) FROM stdin;
32	LILAC BIKINI	lilac-bikini	Chất liệu : Thun \nThành phần : 75% Nylon 25% Elastane\nCó đệm mút ngực \nCả quần và áo đều được may 2lớp.	350000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369968/brown_products/tqfs1rumv93uqa2y35hl.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774371119/brown_products/v8bbodcenhxnlfa004vt.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774371121/brown_products/c0w0d1jo3xtbffqhgp0c.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774371122/brown_products/tbriqqcin6h2j4rnyiqr.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774371124/brown_products/bjrljt2beswmuwv57ba9.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774371126/brown_products/xspwhmqasq9rfaefn4mx.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774371128/brown_products/xrdkse6krhutns3h2vs1.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774371131/brown_products/ftxjc04u7rnd8seahbjh.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774371133/brown_products/wyn8waeattc1tgpqjqgd.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774371134/brown_products/hwi6ov8tb4t46mjip8yi.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774371136/brown_products/fu6aefujzacmwezhzi1f.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774422418/brown_products/xhozsybfdcnxkhcck5qi.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774422420/brown_products/rbdoq9juyhylxhdu8t7b.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774422421/brown_products/kqnmo740pr2s4m3w0ubt.webp}	t	2026-03-24 16:33:36.811244+00	3	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369979/brown_products/pngu0nmathcroweihnao.webp	LILAC BIKINI	Material: Elastic\nIngredients: 75% Nylon 25% Elastane\nHas breast padding\nBoth pants and shirt are sewn in 2 layers.	f	2 tháng 4 giao hàng
18	IVORY BIKINI	ivory-bikini-1769507588435	Chất liệu : Thun \nThành phần : 75% Nylon 25% Elastane\nCó đệm mút ngực \nCả quần và áo đều được may 2lớp.\n	300000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769238/brown_migration/h7vio5lvckeyedu6aklx.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369872/brown_products/qtnbszxwy74zhkqgsg64.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369874/brown_products/zhzisajglapy190hz9pd.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369875/brown_products/l7mvxymu3wa3rjhyyrhp.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369877/brown_products/bbiagzcnow2z55qonu9r.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369880/brown_products/dc6ah7sr7mfawk74ew7m.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369882/brown_products/apoxqtvzznyjgysyioxa.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369883/brown_products/vjsdcubndy5n28ziland.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369885/brown_products/kpn88qp2hf1smhtq1s5t.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369887/brown_products/l4gaod3uvddloqyruazv.jpg,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369889/brown_products/xerjjf8nrqcww0mm1nqw.jpg,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774422735/brown_products/s6j2thern2wagxiqmoll.webp}	t	2026-01-27 09:53:08.685456+00	3	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770116/brown_migration/cydhbuknueywtpxpmgme.webp	IVORY BIKINI	Material: Elastic\nIngredients: 75% Nylon 25% Elastane\nHas breast padding\nBoth pants and shirt are sewn in 2 layers.	f	\N
15	BLOOM SKIRT 	bloom-skirt--1769506794547	Chất liệu quần: Thun \nThành phần váy : 100% Poly\nSet chân váy bí kèm quần KHÔNG TÁCH LẺ - váy không may liền quần nên khách có thể tự điều chỉnh độ dài ngắn hoặc độ phồng ít nhiều tùy theo sở thích.\nTất cả các phép đo kích thước đều được tính bằng cm.	300000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769684/brown_migration/rafbqsj4b8suk9fqhjcd.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769687/brown_migration/qmupauvcpv7vwwpsykxp.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769691/brown_migration/r62o8dcebwdym6vysi62.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769698/brown_migration/h3exsna0pgueo8sacs7z.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769705/brown_migration/qdnx2mtw7vokussfmx5x.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769711/brown_migration/eesrfr1wujqod7jcoxwh.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769717/brown_migration/ctsr31wjcy2onboopmlo.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769724/brown_migration/yf5abmoi50sb9xnky7jh.webp}	f	2026-01-27 09:39:54.787998+00	2	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770152/brown_migration/ebix2ukd6tktryu58gex.webp	BLOOM SKIRT	Pants material: Elastic\nSkirt composition: 100% Poly\nThe skirt and pants set is NOT SEPARATE - the skirt is not sewn together so customers can adjust the length or bulge more or less depending on their preferences.\nAll size measurements are in cm.	f	\N
6	POLO BABY MILK	polo-baby-milk-1769440246795	Chất liệu : Thun\nThành phần : 75% Nylon 25% Elastane\nÁo polo có dây kéo chiết eo form ôm\nTất cả các phép đo kích thước đều được tính bằng cm.\n	270000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769305/brown_migration/eqrrbcn5tekteu2whp4q.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769307/brown_migration/mhpgqrliufhay6qqacoy.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769310/brown_migration/xjgjpalel3djkdjni1le.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769313/brown_migration/mjft8wv3gcoenricxjvw.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769315/brown_migration/tm94a27ikqbarhmbudlc.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769317/brown_migration/jjb8gl2ckpt0xc3shfjv.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769319/brown_migration/d0x6rp1fpdniv0sy96t9.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769321/brown_migration/igpmpzhywm04gswnsf41.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769322/brown_migration/ij50plqnqaw1s3rltuqw.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769324/brown_migration/tqma4mec48smtnt4pefl.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769325/brown_migration/vlwg32erow1iz19vjtkt.webp}	f	2026-01-26 15:10:46.901889+00	1	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770129/brown_migration/niwshy0nr9wlq5j21pa1.webp	POLO BABY MILK	Material: Elastic\nIngredients: 75% Nylon 25% Elastane\nPolo shirt with zipper and slim waist\nAll size measurements are in cm.	f	\N
9	BROWN JEANS 	brown-jeans--1769504400203	Chất liệu : Jeans\nQuần jean cạp thấp ống suông loe.\nTất cả các phép đo kích thước đều được tính bằng cm.	350000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769383/brown_migration/hos5bhzhdhq8cs4oizwz.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769386/brown_migration/mfymgbvnidrtvdskytk0.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769390/brown_migration/eo8liycalufpjx2hvpa5.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769395/brown_migration/aancpavcvwjziasdjsln.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769399/brown_migration/iprgujtdc4rlkzxu84xp.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769404/brown_migration/prtlkn0xhfmzslrlltai.webp}	f	2026-01-27 09:00:00.443461+00	2	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770127/brown_migration/png214owqgqrhfqfvbdi.webp	BROWN JEANS	Material: Jeans\nLow-waisted, flared jeans.\nAll size measurements are in cm.	f	\N
10	BOWTIE BRA	bowtie-bra-1769504853531	Chất liệu : Thun gân \nThành phần : 100% cotton\nCó Mút (phía sau cột dây).\nTất cả các phép đo kích thước đều được tính bằng cm.	140000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769346/brown_migration/qbgq7yey2o015msj8jak.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769350/brown_migration/a2exvpvjlqoio3cludwh.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769354/brown_migration/lbmeneigyo1mell84k31.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769357/brown_migration/rzsbxreysks3iuxlso8j.webp}	f	2026-01-27 09:07:33.657681+00	1	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770133/brown_migration/sa811cg0qn5fg53lzwwm.webp	BOWTIE BRA	Material: Ribbed elastic\nIngredients: 100% cotton\nThere is foam (behind the string).\nAll size measurements are in cm.	f	\N
12	JOLIE SHORT	jolie-short-1769505269364	Chất liệu : Thun \nThành phần : 75% Nylon 25% Elastane\nQuần ngắn lưng thấp cạp xéo gập viền) phần lưng gập không may cố định, khách có thể tuỳ ý gập độ cao thấp theo ý muốn.\nTất cả các phép đo kích thước đều được tính bằng cm.\n	250000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769406/brown_migration/jybin2sh2xzbfsivx9r8.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769409/brown_migration/y5asx9s7fdb053fjlzi4.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772731374/brown_products/otkcyterfli39yuymo0s.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772731376/brown_products/jnxzvkiyjoo4hxkug2u8.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772731379/brown_products/wenxwjq4xaldapbwbbzm.jpg,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772731382/brown_products/toaqaqpasjem4en3zp1m.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772731385/brown_products/sj5pmleflrsk7qft9urr.jpg,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772731389/brown_products/s31vdxssjbcklbwubwqj.jpg,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772731450/brown_products/drreshwbsfksn9vxcea3.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772731452/brown_products/qcdw5vroqxd9w2m8aq1o.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774370505/brown_products/qikj0pd5sd4lnyxx5mwc.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423151/brown_products/alwro2jsrdtr8krggnob.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423154/brown_products/ill4lh8qvs5oprsctdfz.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423155/brown_products/jd37qeqmowi4wlukqnjz.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423157/brown_products/ghtkw69rmxinqdyurlle.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423158/brown_products/gxdkprmfbu7ncsrpd2yf.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423159/brown_products/xetbn0za3z9exjfcq9ch.webp}	t	2026-01-27 09:14:29.521543+00	2	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770140/brown_migration/kvcdlkewxs5p5gil9j3e.webp	JOLIE SHORT	Material: Elastic\nIngredients: 75% Nylon 25% Elastane\nLow-waisted short pants with folded hems) The folded back is not fixed, customers can freely fold it to the desired height.\nAll size measurements are in cm.	f	\N
34	Phụ kiện BrownVN	phu-kien-brownvn		0	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1775641375/brown_products/xztxp9cyl4n9mxuyjaqe.webp}	f	2026-04-08 09:46:12.478188+00	6	\N	BrownVN accessories		f	\N
14	MUSE TOP	muse-top-1769506615428	Chất liệu : Thun \nThành phần : 75% Nylon 25% Elastane\nÁo cổ tim cột cổ - phần ngực được may 2 lớp \nKhoét sâu gom tạo nâng v1.\nTất cả các phép đo kích thước đều được tính bằng cm.	350000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769530/brown_migration/ck5be2swlyecywfndtte.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769532/brown_migration/cpdhakri54g7leblzuuv.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769535/brown_migration/r7de4sncipfqlamnmyka.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769538/brown_migration/o0c8mahl4haswxzpmbl3.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769541/brown_migration/er2i6b39saecyeizlcu5.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769545/brown_migration/uvkyq6b3tfa8blmngytw.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772776953/brown_products/vhnb7heo05bp9xd9ggob.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772776957/brown_products/zowuldo76mdgbiwzxf77.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772776960/brown_products/mb1lhsaf7feloe0aoqlp.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772776962/brown_products/afnesozlkl11gehoeppt.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772776965/brown_products/a47hjnkirawmp2nfm0vg.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772776968/brown_products/u6yoly5ucvqxld7ecrfp.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772776972/brown_products/kedaflkg3mkt73doipzl.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772776975/brown_products/ioiyoetxwwzhjrzjmhzx.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772776978/brown_products/ukrdjn6x15ofctww8fnx.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772776981/brown_products/sozspzussyih2n9tmbts.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772776984/brown_products/y3u5jhszn93txvqyn4vi.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423019/brown_products/xhn7kivvbb0qfmedwqoc.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423021/brown_products/bdgeek4ajk1mirv9on1u.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423023/brown_products/c37ldyzj344rchi591mr.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423024/brown_products/qi4mfnwna4edkkezd6ck.webp}	t	2026-01-27 09:36:55.718592+00	1	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770147/brown_migration/opmiuh65xyrfelx7dg4f.webp	MUSE TOP	Material: Elastic\nIngredients: 75% Nylon 25% Elastane\nTurtleneck collared shirt - the chest is sewn in 2 layers\nDeep boring to create lift v1.\nAll size measurements are in cm.	f	\N
8	LAROSE CAMI	larose-cami-1769441181303	Chất liệu : Thun \nThành phần : 75% Nylon 25% Elastane\n Áo 2 dây cổ tim có chiết eo & may viền giúp nâng phần ngực\nTất cả các phép đo kích thước đều được tính bằng cm.	180000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769729/brown_migration/dfaaotoh2yto0fyrjt7z.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769731/brown_migration/tyga5pulcglsjro479cq.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769733/brown_migration/u60gui7osk7rbwqobjdd.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769734/brown_migration/d0hawe3icq8kga62pvse.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769736/brown_migration/cmrrb2oapi8iuusc0vsw.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769738/brown_migration/rgfgb4jocgvy3scl79kv.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769740/brown_migration/c5rd7lc3salihqnqgdoa.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769742/brown_migration/knbsdq9wqqm9ebuuwyeq.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769744/brown_migration/p6qkrvzql6dnt5hzczfz.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769747/brown_migration/ad0zrcun2hqzbsk5voqm.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769749/brown_migration/bxnpvv51crgv7ebdghdb.webp}	f	2026-01-26 15:26:21.856187+00	1	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770162/brown_migration/kce1rbd3e2mso4kbxdiw.webp	LAROSE CAMI	Material: Elastic\nIngredients: 75% Nylon 25% Elastane\n2-strap turtleneck shirt with waistline and hemming to help lift the bust\nAll size measurements are in cm.	f	\N
13	GLOW HALTER	glow-halter-1769505948457	Chất liệu : Thun \nThành phần : 75% Nylon 25% Elastane\nÁo yếm may 2 lớp - có cài nút ở cổ - có tăng đơ điều chỉnh ở sau lưng - cột dây để thoải mái điều chỉnh theo số đo của mỗi người.\nTất cả các phép đo kích thước đều được tính bằng cm.	350000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769482/brown_migration/cidhikd6f1l2ug49f9an.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769483/brown_migration/toe9bcc2kjgjbwcyy2fr.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769486/brown_migration/vuvuqzebbdayvbuiikyz.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769489/brown_migration/ozmadjfwcwqnmrviqh7j.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769491/brown_migration/ok9to3b3vhxh3uj6f3sa.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772732175/brown_products/m6wvrilzpu4ce2elqupm.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772732272/brown_products/l8szzpxvdpigwq8lucyt.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772732274/brown_products/jigceutyzx6druuzyl6m.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772732277/brown_products/rrn1hlywvroowkauhlzo.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772732279/brown_products/nscdcphzjiguro6jl0ih.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772732282/brown_products/elmnugc2iv2gwkr25tn8.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772732285/brown_products/eku3mji0v44fmghfomhx.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774370312/brown_products/be36zmg5wz5u6xfgkqbf.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774370315/brown_products/mpqnepjij0upvbqgkfrd.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774370317/brown_products/zruwvofszklcjte7jzss.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774370319/brown_products/opqpnidskkwu5zfu2yvt.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423084/brown_products/gig5u6ioj9fgjz9sgisr.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423086/brown_products/z89ni2xfeqqenoxptfdh.webp}	t	2026-01-27 09:25:48.591654+00	1	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770160/brown_migration/ibqomgahjpwtnfzgeoin.webp	GLOW HALTER	Material: Elastic\nIngredients: 75% Nylon 25% Elastane\n2-layer camisole - buttoned at the neck - adjustable straps at the back - laced to comfortably adjust according to each person's measurements.\nAll size measurements are in cm.	f	\N
11	CHIC TEE	chic-tee-1769505018586	Chất liệu : Thun\nThành phần : 100% Cotton\nÁo trễ vai form rộng.\nTất cả các phép đo kích thước đều được tính bằng cm.\n	250000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769359/brown_migration/pxm1doryh6ed5rrbf9hq.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769363/brown_migration/vxazrgfyrgf7l9nr6jau.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769367/brown_migration/fiymjzfxadllihihwdq1.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769372/brown_migration/gyof4bu1aym7wjuylgi4.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769377/brown_migration/df9vil9dpvrga10wzn3a.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769381/brown_migration/ocnovzpndd1znwskbagj.webp}	f	2026-01-27 09:10:18.734267+00	1	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770137/brown_migration/jksoxzclunfwlg5mzxmt.webp	CHIC TEE	Material: Elastic\nIngredients: 100% Cotton\nWide form off-shoulder shirt.\nAll size measurements are in cm.	f	\N
3	SKIRT HONEY DRESS 	skirt-honey-dress--1769437468949	Chất liệu : Thun\nThành phần : 75% Nylon 25% Elastane \nChân váy dài lưng thấp cạp xéo, gập viền hoặc không tuỳ thích.\nTất cả các phép đo kích thước đều được tính bằng cm.	350000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769147/brown_migration/kyszl10ert2ngyvc6vij.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769151/brown_migration/apufsmwgkprd1rrwdl1n.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769156/brown_migration/po4bwi2i55biign1hr36.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772731847/brown_products/nynowxzjbqrajiwaoti0.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772731849/brown_products/gj3vsnxx3zjshllbgaed.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772731949/brown_products/cwpeidqijbcefstju3d2.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772731951/brown_products/mhl0sbvvrhqpxycwvngq.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772731960/brown_products/iiqtkbdszc41ixi0fg8g.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772732017/brown_products/prayn1b2saz0kgunnuvb.jpg,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772732022/brown_products/dqkyhrdp9vrf6udvxo4q.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772732029/brown_products/plni34pz86395jas9c6t.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423381/brown_products/nttt5sdgu5c1uma54lrt.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423382/brown_products/yylajwo3a3vaoysuasc2.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423384/brown_products/nzq9pdwppzsqg7i9r3ej.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423386/brown_products/wk0yzjbucob6zkp3rt5s.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423387/brown_products/yzdchl4lyh2qqfg7qnje.webp}	t	2026-01-26 14:24:29.537851+00	2	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770122/brown_migration/scokzjry0upfhbseds3a.webp	SKIRT HONEY DRESS	Material: Elastic\nIngredients: 75% Nylon 25% Elastane\nLow-waisted long skirt with slanted waist, folded hem or not as desired.\nAll size measurements are in cm.	f	\N
20	BRONZE BIKINI	bronze-bikini-1769507808808	Chất liệu : Thun \nThành phần : 75% Nylon 25% Elastane\nCó đệm mút ngực \nCả quần và áo đều được may 2lớp.	320000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769284/brown_migration/xys4exdoboqao5ze6jwm.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369494/brown_products/sh0n39sdwiwpezcrvgge.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369496/brown_products/xebjfacyyuwuvdx8gu54.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369499/brown_products/yrhoyxmkck45mg0o6zyh.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369500/brown_products/tpwscent5hm5tmo6lexz.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369502/brown_products/qamxc6eq0hjjcj1snpoi.jpg,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369504/brown_products/qfqigtd2ool5azmaeahg.jpg,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369506/brown_products/g00447wzu14gzmz6yjsz.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369508/brown_products/usml5tpchya6zmy2zest.webp}	t	2026-01-27 09:56:48.95231+00	3	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770124/brown_migration/pbnrq6mmjc3jlcio7eok.webp	BRONZE BIKINI	Material: Elastic\nIngredients: 75% Nylon 25% Elastane\nHas breast padding\nBoth pants and shirt are sewn in 2 layers.	f	\N
7	LILY TOP	lily-top-1769440684492	Chất liệu : Thun\nThành phần : 75% Nylon 25% Elastane\nTrễ vai xếp li có chiết eo.\nTất cả các phép đo kích thước đều được tính bằng cm.	220000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769327/brown_migration/vwjdcdmysqqgudsbau4l.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769328/brown_migration/jsmvqacu6twpsh3pc05s.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769330/brown_migration/scn5dhd2mtclpncvwbgr.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769333/brown_migration/reh6ctnyj9jg8fdcborq.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769335/brown_migration/a5hsjvv8zvbv6fo0kqae.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769338/brown_migration/cadubruecnlcf3mpdfsf.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769339/brown_migration/com4ydtvcp9ptbnhnquq.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769341/brown_migration/qsqsqgxh29yaltzncs2y.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769342/brown_migration/rkwli0mnyv2sop9bkmpi.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769344/brown_migration/c1m63jdfy2u19fbyynnm.webp}	f	2026-01-26 15:18:04.742783+00	1	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770130/brown_migration/klvg7rguwskb3zqtsvki.webp	LILY TOP	Material: Elastic\nIngredients: 75% Nylon 25% Elastane\nPleated off-shoulder with gathered waist.\nAll size measurements are in cm.	f	\N
17	CURVE TEE	curve-tee-1769507446512	Chất liệu : Thun \nThành phần : 75% Nylon 25% Elastane\nÁo thun ôm body thêu chữ - có dây kéo phía sau cổ cho các nàng dễ dàng mặc và cởi.\nTất cả các phép đo kích thước đều được tính bằng cm.	300000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769634/brown_migration/ri6ahfxobbvjlh8pzv8c.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769635/brown_migration/shzjw1zlmnumnxqctsce.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769638/brown_migration/ojmz13bky8o3rqlwtgqs.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769641/brown_migration/a1iaxp7g7djrwjpt5pfp.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769643/brown_migration/s0cnysy3qvcl5o116ykr.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769646/brown_migration/qejovny0wf6cpx6bigyv.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772732496/brown_products/d6xax2tk30rxrazc41o0.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772732498/brown_products/vvyd1rhuz4k01cxu7w2v.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772732501/brown_products/tj3aymbz3awkptxkb78n.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772732503/brown_products/lssdlhlwxiug8mgoz8ca.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772732506/brown_products/dmonze9izgtya5avtwjn.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772732508/brown_products/sxyvf7pql55o2ogw09j6.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772732511/brown_products/wpcuxquj4wvgzbgoaivx.jpg,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772732514/brown_products/nagcsqznb1d3uzfqmjw5.jpg,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774422815/brown_products/wcer6rqjcoaci1tkx03t.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774422817/brown_products/a0zm6d2ump4uuu69f3al.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774422819/brown_products/utdsn1kzjp2styvocqdw.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774422821/brown_products/gbawomgo7oa5drmjx1yw.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774422822/brown_products/lch9dq1u6w51nazw9f9o.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774422824/brown_products/re4qxgdsy8kpvamucru0.webp}	t	2026-01-27 09:50:46.761579+00	1	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770148/brown_migration/skyb2bekih1vwydauvsu.webp	CURVE TEE	Material: Elastic\nIngredients: 75% Nylon 25% Elastane\nEmbroidered body-hugging t-shirt - with zipper at the back of the neck for girls to easily put on and take off.\nAll size measurements are in cm.	f	\N
5	CAPRI AMOR	capri-amor-1769439895584	Chất liệu : Thun\nThành phần : 75% Nylon 25% Elastane\nQuần lửng lưng thấp cạp xéo có gập viền lưng & xẻ tà) - phần lưng gập không may cố định, khách có thể tuỳ ý gập độ cao thấp theo ý muốn.\nTất cả các phép đo kích thước đều được tính bằng cm.	300000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769441/brown_migration/m8oykrhpgdvs5n0v8she.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769445/brown_migration/zcgq1fmdtxzrkqhnibls.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769450/brown_migration/o3wnacphtsudq70qp43r.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769454/brown_migration/ecjru6bobh1qsd5fun32.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769471/brown_migration/ancvg43qsx0paxixnnmv.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769475/brown_migration/oyhtzskcsgucvkkidqtx.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769480/brown_migration/mwptz6t6zqteh4w7tlyo.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774370626/brown_products/g2q8xspafi5p236hr4l3.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774370628/brown_products/etip9fns38rvllvx8vrj.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423245/brown_products/wpfbyluotwjfneidhpro.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423247/brown_products/uheadqy5jrgcy5iegima.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423248/brown_products/gxvos6uk1azuh89l8rk9.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423251/brown_products/yho6pkxzpdprrbmb4pbg.webp}	t	2026-01-26 15:04:55.851048+00	2	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770144/brown_migration/f48da1b4l0hndpm2bwxj.webp	CAPRI AMOR	Material: Elastic\nIngredients: 75% Nylon 25% Elastane\nLow-waisted, slanted pants with folded back hem & slits - the folded back part is not fixed, customers can arbitrarily fold it to the desired height.\nAll size measurements are in cm.	f	\N
16	FLARE PANTS 	flare-pants--1769506994720	Chất liệu : Thun \nThành phần : 75% Nylon 25% Elastane\nQuần loe lưng thấp cạp xéo có gập viền - phần lưng gập không may cố định, khách có thể tuỳ ý gập độ cao thấp theo ý muốn - phần hông có nhún nhẹ hai bên để che phần bụng dưới.\nTất cả các phép đo kích thước đều được tính bằng cm.	400000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769586/brown_migration/xjzur47dba6slonhwjrr.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769588/brown_migration/xxpkcjbeizwzwq5nykrc.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772731577/brown_products/bw4kxx5fp3hy8ldytahh.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774422880/brown_products/e7sgsdb17ievwawoqla7.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774422881/brown_products/wifmdufkwsejp3ws0g3g.webp}	t	2026-01-27 09:43:15.154499+00	2	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770154/brown_migration/fz8hjwjeylh8klih8u9y.webp	FLARE PANTS	Material: Elastic\nIngredients: 75% Nylon 25% Elastane\nLow-waisted flared pants with a folded hem - the folded back is not sewn in place, customers can freely fold it to the desired height - the hips have slight ruffles on both sides to cover the lower abdomen.\nAll size measurements are in cm.	f	\N
27	TEST	test	TEST SAN PHAM	100000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774090297/brown_products/joo4mztgr173mhkelukb.webp}	f	2026-03-21 10:52:03.000137+00	5	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774090301/brown_products/rbi3lohnqaqjtr55oy6n.webp	TEST	TEST SAN PHAM	t	ORDER 15 NGAY
28	LAROSA CAMI 2	larosa-cami-2	Áo được may 2lớp. Phần dây có tăng đơ điều chỉnh được độ ngắn dài theo cơ thể của mỗi người. Thiết kế may 2 đường chiết eo tạo cảm giác v2 nhỏ gọn.	300000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774188630/brown_products/wtvzarsccieo9asmepxd.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774188558/brown_products/mnfkl7onz3whsosnb7fk.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774188560/brown_products/jk75psqwevn20ylupusi.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774188552/brown_products/v2pkfwdpod0yvjnbql8s.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774188547/brown_products/avjycigu6cbyblnjnvyz.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774188550/brown_products/m6hgdewd4wpsrsj72ue8.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774188554/brown_products/lxxvhyamachufuefanr2.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774188556/brown_products/t1dtheyrzlguzqznz9jd.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369123/brown_products/hvodzktwiruq4qe5leqm.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369125/brown_products/xf0fod8gasvucffjgsyu.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774422518/brown_products/ra58xwx329nxwg5a2zt6.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774422520/brown_products/tgv14uebcycs9wt2zjql.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774422521/brown_products/aq4f8uwz392lqtwxqavc.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774422523/brown_products/xliylko4xhjoyk3kat6b.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774422524/brown_products/jfomwbhbui5dekteiwqx.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774422526/brown_products/rdvxjioafiit635rsgzw.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774422529/brown_products/hpxuytbwrgxgwx6o0abt.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774422597/brown_products/tnc0dnokcezqtefg8m6h.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774422599/brown_products/kzlpsiqkc7s7xlq5dj2a.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774422601/brown_products/qeqoyeatoqzgkjeudqwg.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774422603/brown_products/dtthd9fpkdfpb3lsy3hk.webp}	t	2026-03-22 15:49:37.022997+00	1	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774188555/brown_products/ao6yhirqfj8zorad0oib.webp	LAROSA CAMI 2	The shirt is sewn in 2 layers.The strap has an adjustable length that can be shortened and lengthed according to each person's body.The 2-seam design creates a compact v2 feel.	f	\N
4	SKIRT HONEY 	skirt-honey--1769439364870	Chất liệu : Thun\nThành phần : 75% Nylon 25% Elastane \nChân váy ngắn lưng thấp có quần bảo hộ.\nTất cả các phép đo kích thước đều được tính bằng cm.	300000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774364387/brown_products/vhnecoanmh6nioylos3l.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774364298/brown_products/lxh9ggfjehzzzqtbwi0k.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774364300/brown_products/u1r4nffkk8nvbjcsk3sr.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769210/brown_migration/lfhxzfuj5frvapkbwum5.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769207/brown_migration/qyh1ijwnjbdw6c010jq6.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772731695/brown_products/orsvydcratuepv6eskqg.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772731699/brown_products/mj60ckl9acttghzcohno.jpg,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772731776/brown_products/x2yi1pysryv5rr99wdjp.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772731780/brown_products/irxantog7qbzugsiwp1b.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772731790/brown_products/ki0gaje08torjctpytcm.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1772731792/brown_products/gqj48xtoahshohhehevj.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423317/brown_products/ksloqjzw0bly4nsbm3nh.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423318/brown_products/d3grrzxbdnxtt8byi9bj.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423320/brown_products/rl3e9oncbtzibvpqyq4y.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423321/brown_products/ykct0hig6yakojmklvjc.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423323/brown_products/awkfx895i9iqg6xp7qhj.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423326/brown_products/k8w9ij36vua8gwqlulaw.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423327/brown_products/e5xccs7jysjb8dqimwwy.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423328/brown_products/fupzru5g6vnrmhf3xsky.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774423330/brown_products/wgz8e2qlcjlwbhqwpyp5.webp}	t	2026-01-26 14:56:05.130846+00	2	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770158/brown_migration/jdk3gedmqtocqabjsmsj.webp	SKIRT HONEY	Material: Elastic\nIngredients: 75% Nylon 25% Elastane\nLow-waisted short skirt with protective pants.\nAll size measurements are in cm.	f	\N
19	SOLÉ BIKINI	sole-bikini-1769507676713	Chất liệu : Thun \nThành phần : 75% Nylon 25% Elastane\nCó đệm mút ngực \nCả quần và áo đều được may 2lớp	300000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769265/brown_migration/fimz294eg3kkb8bmjctt.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369705/brown_products/do7i6d4zgopvxkegpzp8.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369708/brown_products/d81gzicwuavcughwqv6z.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369710/brown_products/uz2rwlfypyrmd78w0kil.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369712/brown_products/wk2v9byjhqydjnntjzju.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369713/brown_products/fyqhmjivoxtsiqk5v99g.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369715/brown_products/oyqnrdzvmzhxlbntqgdu.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369717/brown_products/xwwlw6y9nagzhnmwzaix.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369718/brown_products/clpmo38xvcgvmf2ymzlu.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369720/brown_products/zhjieubepgmkewrgnivv.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774422695/brown_products/f1ikhfedz9vfqeuyc4b9.webp}	t	2026-01-27 09:54:36.85854+00	3	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769770118/brown_migration/gfvwpyokghhjz1ktexit.webp	SOLÉ BIKINI	Material: Elastic\nIngredients: 75% Nylon 25% Elastane\nHas breast padding\nBoth pants and shirt are sewn in 2 layers	f	\N
33	SAVAGE BIKINI	savage-bikini	Chất liệu : Thun \nThành phần : 75% Nylon 25% Elastane\nKhông có đệm mút ngực \nCả quần và áo đều được may 2lớp.	320000	{https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774370221/brown_products/ycuadauz5in7ii6v1aom.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774370942/brown_products/d2lc3nlth5vlm7tfqlb8.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774370944/brown_products/ddiublm8demjbjnt3rmz.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774370946/brown_products/gwo9qwxnrhzxoyt8byxx.jpg,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774370948/brown_products/zurolmmouptlsgw6ngbd.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774370950/brown_products/ztwyyp8lr3uqrdmohofc.jpg,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774371187/brown_products/pid2lyzgfxdablr2qreb.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774371189/brown_products/plckjuxiv5szerdcccg7.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774371191/brown_products/t3hvyjuwmixtxyzcn8g5.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774371193/brown_products/dotlscpmqqfex8cldxf1.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774371195/brown_products/ib2ubggyilzn1boxmy66.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774422378/brown_products/waesgy4cficzqvvsptgg.webp,https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774422380/brown_products/fklzfmj5r98501fbf2tb.webp}	t	2026-03-24 16:38:02.923803+00	3	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774370231/brown_products/dkhabc8jamry2soa2wt8.webp	SAVAGE BIKINI	Material: Elastic\nIngredients: 75% Nylon 25% Elastane\nThere is no breast pad\nBoth pants and shirt are sewn in 2 layers.	f	2 tháng 4 bắt đầu giao hàng
\.


--
-- TOC entry 4070 (class 0 OID 17637)
-- Dependencies: 410
-- Data for Name: promotions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.promotions (id, code, description, discount_type, discount_value, min_order_value, start_date, end_date, requires_account, is_active, usage_limit, used_count, max_discount_amount) FROM stdin;
\.


--
-- TOC entry 4064 (class 0 OID 17585)
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
76	76	73	30	110000
77	77	75	20	110000
78	78	83	10	120000
79	79	102	10	140000
80	80	100	18	120000
81	81	78	5	120000
82	82	76	12	120000
83	83	96	5	120000
84	84	94	5	120000
85	85	96	16	120000
86	86	77	9	120000
87	87	78	5	120000
88	88	73	10	120000
89	89	83	5	120000
90	90	73	10	120000
91	91	77	1	120000
92	92	72	5	120000
93	93	79	8	120000
94	94	78	10	120000
95	95	81	19	120000
96	96	83	12	120000
97	97	74	9	120000
98	98	102	15	140000
99	99	95	12	120000
100	100	95	8	120000
101	101	97	20	120000
102	102	73	10	120000
103	103	75	5	120000
104	104	101	5	120000
105	105	72	6	120000
106	106	70	9	120000
107	107	101	3	120000
108	108	79	10	120000
109	109	75	7	120000
110	110	78	5	120000
111	111	48	10	120000
112	112	73	46	120000
113	113	76	12	120000
114	114	101	13	120000
115	115	143	9	120000
116	116	24	20	120000
117	117	142	36	120000
118	118	69	13	120000
119	119	71	6	120000
120	120	23	31	110000
121	121	162	10	120000
122	122	163	10	120000
123	122	158	10	120000
124	122	159	10	120000
125	122	160	10	120000
126	122	161	10	120000
127	123	160	20	120000
128	123	162	18	120000
129	123	159	19	120000
130	123	158	19	120000
131	123	163	19	120000
132	123	161	13	120000
133	124	83	8	120000
134	125	23	6	120000
135	125	101	6	120000
136	125	102	11	120000
137	126	101	7	110000
138	127	83	17	120000
139	128	23	1	120000
140	128	71	11	120000
141	128	69	9	120000
142	128	75	28	120000
143	129	165	12	120000
144	129	164	11	120000
145	129	83	16	120000
146	129	81	10	120000
147	130	143	28	120000
148	130	102	13	120000
149	130	78	13	120000
150	130	165	3	120000
151	131	77	9	120000
152	132	101	12	120000
153	132	164	12	120000
154	133	72	5	120000
155	133	74	5	120000
156	133	164	20	120000
157	133	165	6	120000
158	134	102	2	120000
159	134	79	22	120000
160	134	92	10	120000
161	134	73	10	120000
162	134	165	20	120000
163	135	100	8	120000
164	136	169	99999	1
165	137	100	9	120000
166	137	47	6	120000
167	137	71	20	120000
168	137	72	4	120000
169	137	74	4	120000
170	138	100	15	120000
171	139	101	29	120000
172	139	82	10	120000
173	139	81	11	120000
174	139	73	27	120000
175	139	78	16	120000
176	139	47	11	120000
177	139	92	14	120000
178	139	93	10	120000
179	139	76	22	120000
180	139	75	5	120000
181	139	23	32	120000
182	140	102	20	120000
183	141	143	72	120000
184	141	142	15	120000
185	141	79	10	120000
186	141	80	7	120000
187	141	92	3	120000
188	141	23	19	120000
189	141	24	10	120000
190	141	85	23	120000
191	141	86	10	120000
192	142	165	10	120000
193	142	100	47	120000
\.


--
-- TOC entry 4062 (class 0 OID 17565)
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
74	1	1	20000	\N	2026-03-01 11:03:41.172162+00	\N	\N
75	1	1	20000	\N	2026-03-01 11:21:48.99199+00	\N	\N
76	1	1	3300000	\N	2026-03-08 08:06:55.474324+00	\N	\N
77	1	1	2200000	\N	2026-03-08 08:07:19.530103+00	\N	\N
78	1	1	1200000	\N	2026-03-09 10:50:53.335139+00	\N	\N
79	1	1	1400000	\N	2026-03-10 14:26:23.534877+00	\N	\N
80	1	1	2160000	\N	2026-03-10 14:26:49.256304+00	\N	\N
81	1	1	600000	\N	2026-03-10 14:27:13.761676+00	\N	\N
82	1	1	1440000	\N	2026-03-11 11:10:11.958743+00	\N	\N
83	1	1	600000	\N	2026-03-11 11:10:34.313169+00	\N	\N
84	1	1	600000	\N	2026-03-11 11:10:49.065819+00	\N	\N
85	1	1	1920000	\N	2026-03-12 15:23:45.16469+00	\N	\N
86	1	1	1080000	\N	2026-03-12 15:24:03.748932+00	\N	\N
87	1	1	600000	\N	2026-03-12 15:24:17.309828+00	\N	\N
88	1	1	1200000	\N	2026-03-12 15:35:39.181684+00	\N	\N
89	1	1	600000	\N	2026-03-13 11:43:34.344355+00	\N	\N
90	1	1	1200000	\N	2026-03-13 11:43:51.410139+00	\N	\N
91	1	1	120000	\N	2026-03-13 11:44:06.266569+00	\N	\N
92	1	1	600000	\N	2026-03-13 11:44:22.869034+00	\N	\N
93	1	1	960000	\N	2026-03-14 13:05:14.428955+00	\N	\N
94	1	1	1200000	\N	2026-03-15 16:44:52.949128+00	\N	\N
95	1	1	2280000	\N	2026-03-16 06:57:46.447928+00	\N	\N
96	1	1	1440000	\N	2026-03-16 06:58:07.447051+00	\N	\N
97	1	1	1080000	\N	2026-03-16 06:58:35.192919+00	\N	\N
98	1	1	2100000	\N	2026-03-17 12:37:04.090671+00	\N	\N
99	1	1	1440000	\N	2026-03-17 12:37:32.177413+00	\N	\N
100	1	1	960000	\N	2026-03-18 12:53:03.667725+00	\N	\N
101	1	1	2400000	\N	2026-03-18 12:53:25.571899+00	\N	\N
102	1	1	1200000	\N	2026-03-18 12:53:43.352225+00	\N	\N
103	1	1	600000	\N	2026-03-18 12:54:11.176146+00	\N	\N
104	1	1	600000	\N	2026-03-18 13:36:04.711433+00	\N	\N
105	1	1	720000	\N	2026-03-19 11:40:35.031782+00	\N	\N
106	1	1	1080000	\N	2026-03-19 11:40:58.806522+00	\N	\N
107	1	1	360000	\N	2026-03-19 11:41:14.783346+00	\N	\N
108	1	1	1200000	\N	2026-03-20 12:02:41.45842+00	\N	\N
109	1	1	840000	\N	2026-03-20 12:02:57.834027+00	\N	\N
110	1	1	600000	\N	2026-03-20 12:03:17.518683+00	\N	\N
111	1	1	1200000	\N	2026-03-20 12:03:31.31605+00	\N	\N
112	1	1	5520000	\N	2026-03-20 12:03:48.715435+00	\N	\N
113	1	1	1440000	\N	2026-03-21 13:47:26.104347+00	\N	\N
114	1	1	1560000	\N	2026-03-23 16:12:10.977494+00	\N	\N
115	1	1	1080000	\N	2026-03-24 15:21:00.722248+00	\N	\N
116	1	1	2400000	\N	2026-03-24 15:21:17.335287+00	\N	\N
117	1	1	4320000	\N	2026-03-25 13:05:36.834793+00	\N	\N
118	1	1	1560000	\N	2026-03-25 13:06:00.533628+00	\N	\N
119	1	1	720000	\N	2026-03-25 13:06:12.537885+00	\N	\N
120	1	1	3410000	\N	2026-03-26 12:10:37.359098+00	\N	\N
121	1	1	1200000	\N	2026-03-26 12:23:13.17493+00	\N	\N
122	1	1	6000000	\N	2026-03-26 12:24:05.374702+00	\N	\N
123	1	1	12960000	\N	2026-03-27 12:07:20.839759+00	\N	\N
124	1	1	960000	\N	2026-03-27 12:07:55.24375+00	\N	\N
125	1	1	2760000	\N	2026-03-27 12:09:27.335866+00	\N	\N
126	1	1	770000	\N	2026-03-29 12:32:43.586522+00	\N	\N
127	1	1	2040000	\N	2026-03-29 12:33:32.105045+00	\N	\N
128	1	1	5880000	\N	2026-03-29 12:34:29.43274+00	\N	\N
129	1	1	5880000	\N	2026-03-30 14:02:11.568962+00	\N	\N
130	1	1	6840000	\N	2026-03-31 14:16:18.574473+00	\N	\N
131	1	1	1080000	\N	2026-04-03 14:29:16.111364+00	\N	\N
132	1	1	2880000	\N	2026-04-04 04:58:03.985646+00	\N	\N
133	1	1	4320000	\N	2026-04-04 13:05:47.555938+00	\N	\N
134	1	1	7680000	\N	2026-04-06 14:41:09.615274+00	\N	\N
135	1	1	960000	\N	2026-04-06 14:44:57.712009+00	\N	\N
136	2	1	99999	\N	2026-04-08 10:00:07.795917+00	\N	\N
137	2	1	5160000	\N	2026-04-08 15:07:41.269741+00	\N	\N
138	2	1	1800000	\N	2026-04-09 14:47:58.587621+00	\N	\N
139	2	1	22440000	\N	2026-04-09 16:13:50.1441+00	\N	\N
140	2	1	2400000	\N	2026-04-11 10:24:55.082456+00	\N	\N
141	1	1	20280000	\N	2026-04-11 15:47:46.743999+00	\N	\N
142	1	1	6840000	\N	2026-04-14 14:59:45.857741+00	\N	\N
\.


--
-- TOC entry 4052 (class 0 OID 17487)
-- Dependencies: 392
-- Data for Name: stores; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.stores (id, name, address, phone, is_active, created_at) FROM stdin;
1	15 Nguyễn Xuân Khoát	\N	\N	t	2026-01-26 14:30:34.21197+00
\.


--
-- TOC entry 4056 (class 0 OID 17513)
-- Dependencies: 396
-- Data for Name: suppliers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.suppliers (id, name, created_at, phone, address) FROM stdin;
1	Qlee	2026-01-26 14:30:15.248688+00	\N	\N
2	Phụ kiện Brown	2026-04-08 09:52:32.55665+00	\N	\N
\.


--
-- TOC entry 4060 (class 0 OID 17549)
-- Dependencies: 400
-- Data for Name: variants; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.variants (id, product_id, sku, size, color, current_price, image_url, created_at, weight, color_en) FROM stdin;
82	14	Áo Tim Đen M	M	Đen	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769771/brown_migration/wyqxuirvcahssmzli1nv.webp	2026-01-27 09:36:55.99799+00	500	Black
97	17	Áo Thun Xanh M	M	Xanh	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769813/brown_migration/j5pis9noptfjcwd5bxgl.webp	2026-01-27 09:50:46.963978+00	500	Blue
80	14	Áo Tim Xanh M	M	Xanh	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769765/brown_migration/gia1no6rg1qoldibsole.webp	2026-01-27 09:36:55.99799+00	500	Blue
94	17	Áo Thun Đen S	S	Đen	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769806/brown_migration/y0qz98n4zyy8mqbfottm.webp	2026-01-27 09:50:46.963978+00	500	Black
95	17	Áo Thun Đen M	M	Đen	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769808/brown_migration/avlkmlrgsilrcfi1qvdn.webp	2026-01-27 09:50:46.963978+00	500	Black
50	12	Quần Ngắn Đen M	M	Đen	\N	\N	2026-01-27 09:14:29.970962+00	500	Black
35	8	2S Vàng S	S	Vàng	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769731/brown_migration/tyga5pulcglsjro479cq.webp	2026-01-26 15:26:22.190999+00	500	Yellow
51	12	Quần Ngắn Nâu S	S	Nâu	\N	\N	2026-01-27 09:14:29.970962+00	500	Brown
52	12	Quần Ngắn Nâu M	M	Nâu	\N	\N	2026-01-27 09:14:29.970962+00	500	Brown
48	12	Quần Ngắn Trắng M	M	Trắng	\N	\N	2026-01-27 09:14:29.970962+00	500	White
70	5	Capri trắng M	M	Trắng	\N	\N	2026-01-27 09:15:51.449335+00	500	White
71	5	Capri Đen S	S	Đen	\N	\N	2026-01-27 09:15:51.449335+00	500	Black
93	17	Áo Thun Trắng M	M	Trắng	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769803/brown_migration/npp8gyl4vvaduzu96ecf.webp	2026-01-27 09:50:46.963978+00	500	White
72	5	Capri Đen M	M	Đen	\N	\N	2026-01-27 09:15:51.449335+00	500	Black
24	4	Váy Ngắn Đen	Free	Đen	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769207/brown_migration/qyh1ijwnjbdw6c010jq6.webp	2026-01-26 15:05:40.605075+00	500	Black
73	3	Váy Dài Trắng	Free	Trắng	\N	\N	2026-01-27 09:16:12.934687+00	500	White
88	16	Quần Loe Đen S	S	Đen	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769789/brown_migration/nuze6xytm19axcrfgtyn.webp	2026-01-27 09:43:15.43895+00	500	Black
89	16	Quần Loe Đen M	M	Đen	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769792/brown_migration/noakewjw5ntcruwnatug.webp	2026-01-27 09:43:15.43895+00	500	Black
76	13	Yếm Đen	Free	Đen	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769754/brown_migration/bopvf4amdptwfdfch7fe.webp	2026-01-27 09:25:49.000084+00	500	Black
79	14	Áo Tim Xanh S	S	Xanh	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769763/brown_migration/kpdiraemztfkexff5pch.webp	2026-01-27 09:36:55.99799+00	500	Blue
45	10	Bra Xám	Free	Xám	\N	\N	2026-01-27 09:07:34.070857+00	500	Grey
90	16	Quần Loe Trắng S	S	Trắng	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769795/brown_migration/npeqmmpkagruvnidxf0d.webp	2026-01-27 09:43:15.43895+00	500	White
37	8	2S Trắng S	S	Trắng	\N	\N	2026-01-26 15:26:22.190999+00	500	White
38	8	2S Trắng M	M	Trắng	\N	\N	2026-01-26 15:26:22.190999+00	500	White
39	8	2S Đen S	S	Đen	\N	\N	2026-01-26 15:26:22.190999+00	500	Black
40	8	2S Đen M	M	Đen	\N	\N	2026-01-26 15:26:22.190999+00	500	Black
41	8	2S Nâu S	S	Nâu 	\N	\N	2026-01-26 15:26:22.190999+00	500	Brown
42	8	2S Nâu M	M	Nâu	\N	\N	2026-01-26 15:26:22.190999+00	500	Brown
32	7	Trễ Vai Trắng M	M 	Trắng	\N	\N	2026-01-26 15:18:04.988012+00	500	White
33	7	Trễ Vai Đen S	S	Đen	\N	\N	2026-01-26 15:18:04.988012+00	500	Black
34	7	Trễ Vai Đen M	M	Đen	\N	\N	2026-01-26 15:18:04.988012+00	500	Black
92	17	Áo Thun Trắng S	S	Trắng	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769800/brown_migration/jib0srnxuzhoskxupd6n.webp	2026-01-27 09:50:46.963978+00	500	White
169	34	pk-brown	Free	No Color	\N	\N	2026-04-08 09:59:29.881379+00	500	No Color
47	12	Quần Ngắn Trắng S	S	Trắng	\N	\N	2026-01-27 09:14:29.970962+00	500	White
83	14	Áo Tim Trắng S	S	Trắng	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769773/brown_migration/k8jrfsplszhxwzk4gsfr.webp	2026-01-27 09:36:55.99799+00	500	White
81	14	Áo Tim Đen S	S	Đen	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769768/brown_migration/yh5apxjxznekjhngzqsg.webp	2026-01-27 09:36:55.99799+00	500	Black
69	5	Capri Trắng S	S	Trắng	\N	\N	2026-01-27 09:15:51.449335+00	500	White
91	16	Quần Loe Trắng M	M	Trắng	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769798/brown_migration/lfrisp4yqbtxdfhs1jxd.webp	2026-01-27 09:43:15.43895+00	500	White
84	14	Áo Tim Trắng M	M	Trắng	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769776/brown_migration/grq3y4vpgnsoi0ivrkff.webp	2026-01-27 09:36:55.99799+00	500	White
85	14	Áo Tim Xám S	S	Xám	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769778/brown_migration/d1wjkqitwkjglwtmhbd4.webp	2026-01-27 09:36:55.99799+00	500	Grey
86	14	Áo Tim Xám M	M	Xám	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769781/brown_migration/tiayaqkuoj4bg5j8dcyp.webp	2026-01-27 09:36:55.99799+00	500	Grey
77	13	Yếm Xám	Free	Xám	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769757/brown_migration/okvqkxoh7tvgugiipw9p.webp	2026-01-27 09:25:49.000084+00	500	Grey
96	17	Áo Thun Xanh S	S	Xanh	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769811/brown_migration/ofnl17sqvdgb7zawcc6q.webp	2026-01-27 09:50:46.963978+00	500	Blue
87	15	Váy Bí Trắng	Free	Trắng	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769786/brown_migration/xk1wdojb2bnpkhonrhru.webp	2026-01-27 09:39:54.994873+00	500	White
27	6	Polo Trắng S	S	Trắng	\N	\N	2026-01-26 15:10:47.11471+00	500	White
28	6	Polo Trắng M	M	Trắng	\N	\N	2026-01-26 15:10:47.11471+00	500	White
29	6	Polo Đen S	S	Đen	\N	\N	2026-01-26 15:10:47.11471+00	500	Black
30	6	Polo Đen M	M	Đen	\N	\N	2026-01-26 15:10:47.11471+00	500	Black
46	11	Tee trễ vai trắng	Free	Trắng	\N	\N	2026-01-27 09:10:18.943612+00	500	White
159	28	2s tím	Free size	Tím	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774188552/brown_products/v2pkfwdpod0yvjnbql8s.webp	2026-03-25 07:10:15.83284+00	500	Purple
160	28	2s trắng	Free size 	Trắng	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774188547/brown_products/avjycigu6cbyblnjnvyz.webp	2026-03-25 07:10:15.83284+00	500	White
161	28	2s đen	Free size	Đen	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774188550/brown_products/m6hgdewd4wpsrsj72ue8.webp	2026-03-25 07:10:15.83284+00	500	Black
164	33	Bikini Da Beo	Free	Be	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774370221/brown_products/ycuadauz5in7ii6v1aom.webp	2026-03-26 12:22:05.063198+00	500	Beige
165	32	Bikini Tím	Free	Tím	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774369968/brown_products/tqfs1rumv93uqa2y35hl.webp	2026-03-26 12:22:31.653733+00	500	Purple
110	9	Jeans S	S	Trắng	\N	\N	2026-01-27 10:18:26.343445+00	500	White
111	9	Jeans M	M	Trắng	\N	\N	2026-01-27 10:18:26.343445+00	500	White
112	9	Jeans L	L	Trắng	\N	\N	2026-01-27 10:18:26.343445+00	500	White
131	27	T-S-Đ	S	Đen	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774090297/brown_products/joo4mztgr173mhkelukb.webp	2026-03-21 12:57:38.036946+00	500	Black
36	8	2S Vàng M	M	Vàng	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769731/brown_migration/tyga5pulcglsjro479cq.webp	2026-01-26 15:26:22.190999+00	500	Yellow
31	7	Trễ Vai Trắng S	S	Trắng	\N	\N	2026-01-26 15:18:04.988012+00	500	White
102	20	Bikini Xám	Free	Xám	\N	\N	2026-01-27 09:56:49.155595+00	500	Grey
158	28	2s xanh	Free size	Xanh	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774188558/brown_products/mnfkl7onz3whsosnb7fk.webp	2026-03-25 07:10:15.83284+00	500	Blue
143	4	Váy ngắn Xanh	Free	Xanh	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774364298/brown_products/lxh9ggfjehzzzqtbwi0k.webp	2026-03-24 15:20:13.685273+00	500	Blue
100	18	Bikini Cherry Trắng	Free	Trắng	\N	\N	2026-01-27 09:53:08.914811+00	500	White
98	17	Áo Thun Xám S	S	Xám	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769816/brown_migration/egnb2jhvee4rkz3fkjg6.webp	2026-01-27 09:50:46.963978+00	500	Grey
99	17	Áo Thun Xám M	M	Xám	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769819/brown_migration/xawni7fqx1z55a5dqthv.webp	2026-01-27 09:50:46.963978+00	500	Grey
75	13	Yếm Trắng	Free	Trắng	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769751/brown_migration/aexlwla8a0z8ayi0md5v.webp	2026-01-27 09:25:49.000084+00	500	White
49	12	Quần Ngắn Đen S	S	Đen	\N	\N	2026-01-27 09:14:29.970962+00	500	Black
142	4	Váy Ngắn Xám	Free	Xám	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774364300/brown_products/u1r4nffkk8nvbjcsk3sr.webp	2026-03-24 15:16:16.827994+00	500	Grey
23	4	Váy Ngắn Trắng	Free	Trắng	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769210/brown_migration/lfhxzfuj5frvapkbwum5.webp	2026-01-26 15:05:40.605075+00	500	White
74	3	Váy Dài Đen	Free	Đen	\N	\N	2026-01-27 09:16:12.934687+00	500	Black
162	28	2s be	Free size	Be	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774188554/brown_products/lxxvhyamachufuefanr2.webp	2026-03-25 07:10:15.83284+00	500	Beige
163	28	2s xám	Free size	Xám	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1774188556/brown_products/t1dtheyrzlguzqznz9jd.webp	2026-03-25 07:10:15.83284+00	500	Grey
78	13	Yếm Xanh	Free	Xanh	\N	https://res.cloudinary.com/dqfkmrw8l/image/upload/v1769769760/brown_migration/fypcmzt3dv942lgijgvp.webp	2026-01-27 09:25:49.000084+00	500	Blue
101	19	Bikini Xanh	Free	Xanh	\N	\N	2026-01-27 09:54:37.063319+00	500	Blue
\.


--
-- TOC entry 4126 (class 0 OID 0)
-- Dependencies: 424
-- Name: banners_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.banners_id_seq', 1, false);


--
-- TOC entry 4127 (class 0 OID 0)
-- Dependencies: 412
-- Name: cart_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.cart_items_id_seq', 1, false);


--
-- TOC entry 4128 (class 0 OID 0)
-- Dependencies: 393
-- Name: categories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.categories_id_seq', 6, true);


--
-- TOC entry 4129 (class 0 OID 0)
-- Dependencies: 422
-- Name: content_banners_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.content_banners_id_seq', 4, true);


--
-- TOC entry 4130 (class 0 OID 0)
-- Dependencies: 407
-- Name: customers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.customers_id_seq', 974, true);


--
-- TOC entry 4131 (class 0 OID 0)
-- Dependencies: 418
-- Name: expense_categories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.expense_categories_id_seq', 23, true);


--
-- TOC entry 4132 (class 0 OID 0)
-- Dependencies: 420
-- Name: expenses_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.expenses_id_seq', 43, true);


--
-- TOC entry 4133 (class 0 OID 0)
-- Dependencies: 405
-- Name: inventory_batches_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.inventory_batches_id_seq', 407, true);


--
-- TOC entry 4134 (class 0 OID 0)
-- Dependencies: 416
-- Name: order_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.order_items_id_seq', 2141, true);


--
-- TOC entry 4135 (class 0 OID 0)
-- Dependencies: 414
-- Name: orders_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.orders_id_seq', 1254, true);


--
-- TOC entry 4136 (class 0 OID 0)
-- Dependencies: 397
-- Name: products_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.products_id_seq', 34, true);


--
-- TOC entry 4137 (class 0 OID 0)
-- Dependencies: 409
-- Name: promotions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.promotions_id_seq', 1, false);


--
-- TOC entry 4138 (class 0 OID 0)
-- Dependencies: 403
-- Name: purchase_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.purchase_items_id_seq', 193, true);


--
-- TOC entry 4139 (class 0 OID 0)
-- Dependencies: 401
-- Name: purchase_orders_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.purchase_orders_id_seq', 142, true);


--
-- TOC entry 4140 (class 0 OID 0)
-- Dependencies: 391
-- Name: stores_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.stores_id_seq', 1, true);


--
-- TOC entry 4141 (class 0 OID 0)
-- Dependencies: 395
-- Name: suppliers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.suppliers_id_seq', 2, true);


--
-- TOC entry 4142 (class 0 OID 0)
-- Dependencies: 399
-- Name: variants_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.variants_id_seq', 169, true);


--
-- TOC entry 3830 (class 2606 OID 21625)
-- Name: banners banners_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.banners
    ADD CONSTRAINT banners_pkey PRIMARY KEY (id);


--
-- TOC entry 3813 (class 2606 OID 17662)
-- Name: cart_items cart_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cart_items
    ADD CONSTRAINT cart_items_pkey PRIMARY KEY (id);


--
-- TOC entry 3811 (class 2606 OID 17655)
-- Name: carts carts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.carts
    ADD CONSTRAINT carts_pkey PRIMARY KEY (user_id);


--
-- TOC entry 3780 (class 2606 OID 17504)
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- TOC entry 3782 (class 2606 OID 17506)
-- Name: categories categories_slug_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_slug_key UNIQUE (slug);


--
-- TOC entry 3828 (class 2606 OID 20157)
-- Name: content_banners content_banners_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.content_banners
    ADD CONSTRAINT content_banners_pkey PRIMARY KEY (id);


--
-- TOC entry 3803 (class 2606 OID 17634)
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- TOC entry 3824 (class 2606 OID 17727)
-- Name: expense_categories expense_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.expense_categories
    ADD CONSTRAINT expense_categories_pkey PRIMARY KEY (id);


--
-- TOC entry 3826 (class 2606 OID 17737)
-- Name: expenses expenses_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_pkey PRIMARY KEY (id);


--
-- TOC entry 3801 (class 2606 OID 17608)
-- Name: inventory_batches inventory_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_pkey PRIMARY KEY (id);


--
-- TOC entry 3822 (class 2606 OID 17709)
-- Name: order_items order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (id);


--
-- TOC entry 3816 (class 2606 OID 17687)
-- Name: orders orders_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_code_key UNIQUE (code);


--
-- TOC entry 3818 (class 2606 OID 17685)
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- TOC entry 3832 (class 2606 OID 23132)
-- Name: product_collections product_collections_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_collections
    ADD CONSTRAINT product_collections_pkey PRIMARY KEY (product_id, category_id);


--
-- TOC entry 3786 (class 2606 OID 17530)
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- TOC entry 3788 (class 2606 OID 17532)
-- Name: products products_slug_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_slug_key UNIQUE (slug);


--
-- TOC entry 3807 (class 2606 OID 17649)
-- Name: promotions promotions_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promotions
    ADD CONSTRAINT promotions_code_key UNIQUE (code);


--
-- TOC entry 3809 (class 2606 OID 17647)
-- Name: promotions promotions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promotions
    ADD CONSTRAINT promotions_pkey PRIMARY KEY (id);


--
-- TOC entry 3798 (class 2606 OID 17590)
-- Name: purchase_items purchase_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_items
    ADD CONSTRAINT purchase_items_pkey PRIMARY KEY (id);


--
-- TOC entry 3794 (class 2606 OID 21610)
-- Name: purchase_orders purchase_orders_code_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_code_unique UNIQUE (code);


--
-- TOC entry 3796 (class 2606 OID 17573)
-- Name: purchase_orders purchase_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_pkey PRIMARY KEY (id);


--
-- TOC entry 3778 (class 2606 OID 17495)
-- Name: stores stores_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stores
    ADD CONSTRAINT stores_pkey PRIMARY KEY (id);


--
-- TOC entry 3784 (class 2606 OID 17520)
-- Name: suppliers suppliers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_pkey PRIMARY KEY (id);


--
-- TOC entry 3790 (class 2606 OID 17556)
-- Name: variants variants_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.variants
    ADD CONSTRAINT variants_pkey PRIMARY KEY (id);


--
-- TOC entry 3792 (class 2606 OID 17558)
-- Name: variants variants_sku_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.variants
    ADD CONSTRAINT variants_sku_key UNIQUE (sku);


--
-- TOC entry 3814 (class 1259 OID 22937)
-- Name: idx_cart_items_variant_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cart_items_variant_id ON public.cart_items USING btree (variant_id);


--
-- TOC entry 3804 (class 1259 OID 17635)
-- Name: idx_customer_phone; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_customer_phone ON public.customers USING btree (phone);


--
-- TOC entry 3805 (class 1259 OID 23174)
-- Name: idx_customers_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_customers_user_id ON public.customers USING btree (user_id);


--
-- TOC entry 3799 (class 1259 OID 17624)
-- Name: idx_inventory_fifo; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_inventory_fifo ON public.inventory_batches USING btree (store_id, variant_id, created_at);


--
-- TOC entry 3819 (class 1259 OID 22935)
-- Name: idx_order_items_order_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_order_items_order_id ON public.order_items USING btree (order_id);


--
-- TOC entry 3820 (class 1259 OID 22936)
-- Name: idx_order_items_variant_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_order_items_variant_id ON public.order_items USING btree (variant_id);


--
-- TOC entry 3855 (class 2620 OID 21696)
-- Name: orders trigger_restore_inventory; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_restore_inventory AFTER UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.restore_inventory_on_cancel();


--
-- TOC entry 3844 (class 2606 OID 17663)
-- Name: cart_items cart_items_cart_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cart_items
    ADD CONSTRAINT cart_items_cart_id_fkey FOREIGN KEY (cart_id) REFERENCES public.carts(user_id) ON DELETE CASCADE;


--
-- TOC entry 3845 (class 2606 OID 17668)
-- Name: cart_items cart_items_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cart_items
    ADD CONSTRAINT cart_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.variants(id);


--
-- TOC entry 3833 (class 2606 OID 17507)
-- Name: categories categories_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.categories(id) ON DELETE SET NULL;


--
-- TOC entry 3851 (class 2606 OID 17743)
-- Name: expenses expenses_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.expense_categories(id);


--
-- TOC entry 3852 (class 2606 OID 17738)
-- Name: expenses expenses_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id);


--
-- TOC entry 3834 (class 2606 OID 23169)
-- Name: products fk_products_main_category; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT fk_products_main_category FOREIGN KEY (category_id) REFERENCES public.categories(id);


--
-- TOC entry 3840 (class 2606 OID 17619)
-- Name: inventory_batches inventory_batches_purchase_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_purchase_item_id_fkey FOREIGN KEY (purchase_item_id) REFERENCES public.purchase_items(id);


--
-- TOC entry 3841 (class 2606 OID 17609)
-- Name: inventory_batches inventory_batches_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id);


--
-- TOC entry 3842 (class 2606 OID 17883)
-- Name: inventory_batches inventory_batches_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id);


--
-- TOC entry 3843 (class 2606 OID 17614)
-- Name: inventory_batches inventory_batches_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.variants(id);


--
-- TOC entry 3849 (class 2606 OID 17710)
-- Name: order_items order_items_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- TOC entry 3850 (class 2606 OID 17715)
-- Name: order_items order_items_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.variants(id);


--
-- TOC entry 3846 (class 2606 OID 17688)
-- Name: orders orders_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- TOC entry 3847 (class 2606 OID 17698)
-- Name: orders orders_promotion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_promotion_id_fkey FOREIGN KEY (promotion_id) REFERENCES public.promotions(id);


--
-- TOC entry 3848 (class 2606 OID 17693)
-- Name: orders orders_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id);


--
-- TOC entry 3853 (class 2606 OID 23138)
-- Name: product_collections product_collections_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_collections
    ADD CONSTRAINT product_collections_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id) ON DELETE CASCADE;


--
-- TOC entry 3854 (class 2606 OID 23133)
-- Name: product_collections product_collections_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_collections
    ADD CONSTRAINT product_collections_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- TOC entry 3838 (class 2606 OID 17591)
-- Name: purchase_items purchase_items_purchase_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_items
    ADD CONSTRAINT purchase_items_purchase_order_id_fkey FOREIGN KEY (purchase_order_id) REFERENCES public.purchase_orders(id) ON DELETE CASCADE;


--
-- TOC entry 3839 (class 2606 OID 17596)
-- Name: purchase_items purchase_items_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_items
    ADD CONSTRAINT purchase_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.variants(id);


--
-- TOC entry 3836 (class 2606 OID 17579)
-- Name: purchase_orders purchase_orders_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id);


--
-- TOC entry 3837 (class 2606 OID 17574)
-- Name: purchase_orders purchase_orders_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id);


--
-- TOC entry 3835 (class 2606 OID 17559)
-- Name: variants variants_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.variants
    ADD CONSTRAINT variants_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- TOC entry 4038 (class 3256 OID 22904)
-- Name: categories Admin All Categories; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Categories" ON public.categories USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4030 (class 3256 OID 22896)
-- Name: customers Admin All Customers; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Customers" ON public.customers USING ((EXISTS ( SELECT 1
   FROM public.customers customers_1
  WHERE ((customers_1.user_id = auth.uid()) AND (customers_1.role = 'admin'::text)))));


--
-- TOC entry 4032 (class 3256 OID 22898)
-- Name: expenses Admin All Expenses; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Expenses" ON public.expenses USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4033 (class 3256 OID 22899)
-- Name: inventory_batches Admin All Inventory; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Inventory" ON public.inventory_batches USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4041 (class 3256 OID 22928)
-- Name: order_items Admin All Order Items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Order Items" ON public.order_items USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4027 (class 3256 OID 22893)
-- Name: orders Admin All Orders; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Orders" ON public.orders USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4026 (class 3256 OID 22892)
-- Name: products Admin All Products; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Products" ON public.products USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4034 (class 3256 OID 22900)
-- Name: promotions Admin All Promotions; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Promotions" ON public.promotions USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4036 (class 3256 OID 22902)
-- Name: variants Admin All Variants; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin All Variants" ON public.variants USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4046 (class 3256 OID 22933)
-- Name: banners Admin Manage Banners; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin Manage Banners" ON public.banners USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4024 (class 3256 OID 20159)
-- Name: content_banners Admin Manage Banners; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin Manage Banners" ON public.content_banners USING ((auth.role() = 'authenticated'::text));


--
-- TOC entry 4047 (class 3256 OID 22934)
-- Name: content_banners Admin Manage Content Banners; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Admin Manage Content Banners" ON public.content_banners USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.user_id = auth.uid()) AND (customers.role = 'admin'::text)))));


--
-- TOC entry 4044 (class 3256 OID 22931)
-- Name: banners Public Read Banners; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Banners" ON public.banners FOR SELECT USING (true);


--
-- TOC entry 4023 (class 3256 OID 20158)
-- Name: content_banners Public Read Banners; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Banners" ON public.content_banners FOR SELECT USING (true);


--
-- TOC entry 4037 (class 3256 OID 22903)
-- Name: categories Public Read Categories; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Categories" ON public.categories FOR SELECT USING (true);


--
-- TOC entry 4045 (class 3256 OID 22932)
-- Name: content_banners Public Read Content Banners; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Content Banners" ON public.content_banners FOR SELECT USING (true);


--
-- TOC entry 4025 (class 3256 OID 22891)
-- Name: products Public Read Products; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Products" ON public.products FOR SELECT USING (true);


--
-- TOC entry 4035 (class 3256 OID 22901)
-- Name: variants Public Read Variants; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Public Read Variants" ON public.variants FOR SELECT USING (true);


--
-- TOC entry 4043 (class 3256 OID 22930)
-- Name: order_items User Create Order Items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User Create Order Items" ON public.order_items FOR INSERT WITH CHECK (true);


--
-- TOC entry 4029 (class 3256 OID 22895)
-- Name: orders User Create Orders; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User Create Orders" ON public.orders FOR INSERT WITH CHECK (true);


--
-- TOC entry 4031 (class 3256 OID 22897)
-- Name: customers User Manage Self; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User Manage Self" ON public.customers USING ((user_id = auth.uid()));


--
-- TOC entry 4040 (class 3256 OID 22927)
-- Name: carts User Own Cart; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User Own Cart" ON public.carts USING ((user_id = auth.uid()));


--
-- TOC entry 4039 (class 3256 OID 22926)
-- Name: cart_items User Own Cart Items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User Own Cart Items" ON public.cart_items USING (((EXISTS ( SELECT 1
   FROM public.carts
  WHERE ((carts.user_id = cart_items.cart_id) AND (carts.user_id = auth.uid())))) OR ((cart_id)::text = (auth.uid())::text)));


--
-- TOC entry 4042 (class 3256 OID 22929)
-- Name: order_items User View Own Order Items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User View Own Order Items" ON public.order_items FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.orders
  WHERE ((orders.id = order_items.order_id) AND (EXISTS ( SELECT 1
           FROM public.customers
          WHERE ((customers.id = orders.customer_id) AND (customers.user_id = auth.uid()))))))));


--
-- TOC entry 4028 (class 3256 OID 22894)
-- Name: orders User View Own Orders; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "User View Own Orders" ON public.orders FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.customers
  WHERE ((customers.id = orders.customer_id) AND (customers.user_id = auth.uid())))));


--
-- TOC entry 4021 (class 0 OID 21617)
-- Dependencies: 425
-- Name: banners; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.banners ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4015 (class 0 OID 17657)
-- Dependencies: 413
-- Name: cart_items; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4014 (class 0 OID 17650)
-- Dependencies: 411
-- Name: carts; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.carts ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4005 (class 0 OID 17497)
-- Dependencies: 394
-- Name: categories; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4020 (class 0 OID 20148)
-- Dependencies: 423
-- Name: content_banners; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.content_banners ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4012 (class 0 OID 17626)
-- Dependencies: 408
-- Name: customers; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4018 (class 0 OID 17721)
-- Dependencies: 419
-- Name: expense_categories; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.expense_categories ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4019 (class 0 OID 17729)
-- Dependencies: 421
-- Name: expenses; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4011 (class 0 OID 17602)
-- Dependencies: 406
-- Name: inventory_batches; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.inventory_batches ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4017 (class 0 OID 17704)
-- Dependencies: 417
-- Name: order_items; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4016 (class 0 OID 17674)
-- Dependencies: 415
-- Name: orders; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4022 (class 0 OID 23128)
-- Dependencies: 426
-- Name: product_collections; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.product_collections ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4007 (class 0 OID 17522)
-- Dependencies: 398
-- Name: products; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4013 (class 0 OID 17637)
-- Dependencies: 410
-- Name: promotions; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.promotions ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4010 (class 0 OID 17585)
-- Dependencies: 404
-- Name: purchase_items; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.purchase_items ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4009 (class 0 OID 17565)
-- Dependencies: 402
-- Name: purchase_orders; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4004 (class 0 OID 17487)
-- Dependencies: 392
-- Name: stores; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.stores ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4006 (class 0 OID 17513)
-- Dependencies: 396
-- Name: suppliers; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4008 (class 0 OID 17549)
-- Dependencies: 400
-- Name: variants; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.variants ENABLE ROW LEVEL SECURITY;

--
-- TOC entry 4092 (class 0 OID 0)
-- Dependencies: 50
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE USAGE ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO PUBLIC;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- TOC entry 4093 (class 0 OID 0)
-- Dependencies: 413
-- Name: TABLE cart_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.cart_items TO service_role;
GRANT SELECT ON TABLE public.cart_items TO anon;


--
-- TOC entry 4094 (class 0 OID 0)
-- Dependencies: 412
-- Name: SEQUENCE cart_items_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.cart_items_id_seq TO service_role;


--
-- TOC entry 4095 (class 0 OID 0)
-- Dependencies: 411
-- Name: TABLE carts; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.carts TO service_role;
GRANT SELECT ON TABLE public.carts TO anon;


--
-- TOC entry 4096 (class 0 OID 0)
-- Dependencies: 394
-- Name: TABLE categories; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.categories TO service_role;
GRANT SELECT ON TABLE public.categories TO anon;


--
-- TOC entry 4097 (class 0 OID 0)
-- Dependencies: 393
-- Name: SEQUENCE categories_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.categories_id_seq TO service_role;


--
-- TOC entry 4098 (class 0 OID 0)
-- Dependencies: 423
-- Name: TABLE content_banners; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.content_banners TO service_role;
GRANT SELECT ON TABLE public.content_banners TO anon;
GRANT SELECT ON TABLE public.content_banners TO authenticated;


--
-- TOC entry 4099 (class 0 OID 0)
-- Dependencies: 408
-- Name: TABLE customers; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.customers TO service_role;
GRANT SELECT ON TABLE public.customers TO anon;
GRANT SELECT,UPDATE ON TABLE public.customers TO authenticated;


--
-- TOC entry 4100 (class 0 OID 0)
-- Dependencies: 407
-- Name: SEQUENCE customers_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.customers_id_seq TO service_role;


--
-- TOC entry 4101 (class 0 OID 0)
-- Dependencies: 419
-- Name: TABLE expense_categories; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.expense_categories TO service_role;
GRANT SELECT ON TABLE public.expense_categories TO anon;


--
-- TOC entry 4102 (class 0 OID 0)
-- Dependencies: 418
-- Name: SEQUENCE expense_categories_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.expense_categories_id_seq TO service_role;


--
-- TOC entry 4103 (class 0 OID 0)
-- Dependencies: 421
-- Name: TABLE expenses; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.expenses TO service_role;
GRANT SELECT ON TABLE public.expenses TO anon;


--
-- TOC entry 4104 (class 0 OID 0)
-- Dependencies: 420
-- Name: SEQUENCE expenses_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.expenses_id_seq TO service_role;


--
-- TOC entry 4105 (class 0 OID 0)
-- Dependencies: 406
-- Name: TABLE inventory_batches; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.inventory_batches TO service_role;
GRANT SELECT ON TABLE public.inventory_batches TO anon;


--
-- TOC entry 4106 (class 0 OID 0)
-- Dependencies: 405
-- Name: SEQUENCE inventory_batches_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.inventory_batches_id_seq TO service_role;


--
-- TOC entry 4107 (class 0 OID 0)
-- Dependencies: 417
-- Name: TABLE order_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.order_items TO service_role;
GRANT SELECT ON TABLE public.order_items TO anon;


--
-- TOC entry 4108 (class 0 OID 0)
-- Dependencies: 416
-- Name: SEQUENCE order_items_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.order_items_id_seq TO service_role;


--
-- TOC entry 4109 (class 0 OID 0)
-- Dependencies: 415
-- Name: TABLE orders; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.orders TO service_role;
GRANT SELECT ON TABLE public.orders TO anon;


--
-- TOC entry 4110 (class 0 OID 0)
-- Dependencies: 414
-- Name: SEQUENCE orders_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.orders_id_seq TO service_role;


--
-- TOC entry 4111 (class 0 OID 0)
-- Dependencies: 426
-- Name: TABLE product_collections; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.product_collections TO service_role;
GRANT ALL ON TABLE public.product_collections TO anon;
GRANT ALL ON TABLE public.product_collections TO authenticated;


--
-- TOC entry 4112 (class 0 OID 0)
-- Dependencies: 398
-- Name: TABLE products; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.products TO service_role;
GRANT SELECT ON TABLE public.products TO anon;


--
-- TOC entry 4113 (class 0 OID 0)
-- Dependencies: 397
-- Name: SEQUENCE products_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.products_id_seq TO service_role;


--
-- TOC entry 4114 (class 0 OID 0)
-- Dependencies: 410
-- Name: TABLE promotions; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.promotions TO service_role;
GRANT SELECT ON TABLE public.promotions TO anon;


--
-- TOC entry 4115 (class 0 OID 0)
-- Dependencies: 409
-- Name: SEQUENCE promotions_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.promotions_id_seq TO service_role;


--
-- TOC entry 4116 (class 0 OID 0)
-- Dependencies: 404
-- Name: TABLE purchase_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.purchase_items TO service_role;
GRANT SELECT ON TABLE public.purchase_items TO anon;


--
-- TOC entry 4117 (class 0 OID 0)
-- Dependencies: 403
-- Name: SEQUENCE purchase_items_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.purchase_items_id_seq TO service_role;


--
-- TOC entry 4118 (class 0 OID 0)
-- Dependencies: 402
-- Name: TABLE purchase_orders; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.purchase_orders TO service_role;
GRANT SELECT ON TABLE public.purchase_orders TO anon;


--
-- TOC entry 4119 (class 0 OID 0)
-- Dependencies: 401
-- Name: SEQUENCE purchase_orders_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.purchase_orders_id_seq TO service_role;


--
-- TOC entry 4120 (class 0 OID 0)
-- Dependencies: 392
-- Name: TABLE stores; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.stores TO service_role;
GRANT SELECT ON TABLE public.stores TO anon;


--
-- TOC entry 4121 (class 0 OID 0)
-- Dependencies: 391
-- Name: SEQUENCE stores_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.stores_id_seq TO service_role;


--
-- TOC entry 4122 (class 0 OID 0)
-- Dependencies: 396
-- Name: TABLE suppliers; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.suppliers TO service_role;
GRANT SELECT ON TABLE public.suppliers TO anon;


--
-- TOC entry 4123 (class 0 OID 0)
-- Dependencies: 395
-- Name: SEQUENCE suppliers_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.suppliers_id_seq TO service_role;


--
-- TOC entry 4124 (class 0 OID 0)
-- Dependencies: 400
-- Name: TABLE variants; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.variants TO service_role;
GRANT SELECT ON TABLE public.variants TO anon;


--
-- TOC entry 4125 (class 0 OID 0)
-- Dependencies: 399
-- Name: SEQUENCE variants_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.variants_id_seq TO service_role;


-- Completed on 2026-04-15 09:25:50

--
-- PostgreSQL database dump complete
--

