-- Apply once to the existing production database in Supabase SQL Editor.
-- It is idempotent and only changes the special manual accessory product.
BEGIN;

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS tracks_inventory boolean NOT NULL DEFAULT true;
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS is_revenue_adjustment boolean NOT NULL DEFAULT false;

UPDATE public.products
SET tracks_inventory = false,
    is_revenue_adjustment = true
WHERE name = 'Phụ kiện BrownVN';

-- Repair historical report rows. These were incorrectly charged with the
-- latest inventory-batch cost even though this product does not track stock.
UPDATE public.order_items oi
SET cogs_total = 0
FROM public.variants v
JOIN public.products p ON p.id = v.product_id
WHERE oi.variant_id = v.id
  AND p.name = 'Phụ kiện BrownVN'
  AND oi.cogs_total <> 0;

CREATE OR REPLACE FUNCTION public.create_order_transaction(
  p_customer_id bigint, p_customer_info jsonb, p_payment_method text,
  p_shipping_fee numeric, p_discount_amount numeric, p_voucher_code text, p_items jsonb
) RETURNS jsonb LANGUAGE plpgsql SET search_path TO public AS $$
DECLARE
  v_order_id bigint; v_order_code text; v_subtotal numeric := 0; v_total_amount numeric;
  v_item jsonb; v_variant_id bigint; v_buy_qty integer; v_real_price numeric;
  v_promotion_id bigint; v_needed_qty integer; v_batch record; v_take_qty integer; v_item_cogs numeric;
  v_tracks_inventory boolean;
BEGIN
  v_order_code := 'ORD-' || floor(random() * 8999 + 1000) || extract(epoch FROM now())::bigint;
  IF coalesce(p_voucher_code, '') <> '' THEN
    SELECT id INTO v_promotion_id FROM public.promotions WHERE code = p_voucher_code LIMIT 1;
  END IF;
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_buy_qty := (v_item->>'quantity')::integer; v_real_price := (v_item->>'unit_price')::numeric;
    IF v_buy_qty IS NULL OR v_buy_qty <= 0 OR v_real_price IS NULL THEN RAISE EXCEPTION 'Invalid order item'; END IF;
    v_subtotal := v_subtotal + v_buy_qty * v_real_price;
  END LOOP;
  v_total_amount := greatest(0, v_subtotal + coalesce(p_shipping_fee, 0) - coalesce(p_discount_amount, 0));
  INSERT INTO public.orders (code, customer_id, customer_name, customer_phone, customer_email,
    customer_address, customer_district_id, customer_ward_code, payment_method, status,
    payment_status, subtotal, discount_amount, shipping_fee, total_amount, promotion_id, shipping_tracking_code)
  VALUES (v_order_code, p_customer_id, p_customer_info->>'name', p_customer_info->>'phone',
    p_customer_info->>'email', p_customer_info->>'address', (p_customer_info->>'district_id')::integer,
    p_customer_info->>'ward_code', p_payment_method, 'pending', 'unpaid', v_subtotal,
    coalesce(p_discount_amount, 0), coalesce(p_shipping_fee, 0), v_total_amount, v_promotion_id, NULL)
  RETURNING id INTO v_order_id;
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_variant_id := (v_item->>'variant_id')::bigint; v_buy_qty := (v_item->>'quantity')::integer;
    v_real_price := (v_item->>'unit_price')::numeric; v_needed_qty := v_buy_qty; v_item_cogs := 0;
    SELECT p.tracks_inventory INTO v_tracks_inventory
      FROM public.variants v JOIN public.products p ON p.id = v.product_id
      WHERE v.id = v_variant_id;
    IF v_tracks_inventory IS NULL THEN RAISE EXCEPTION 'Invalid product variant'; END IF;
    IF v_tracks_inventory THEN
      FOR v_batch IN SELECT * FROM public.inventory_batches
        WHERE variant_id = v_variant_id AND quantity_remaining > 0 ORDER BY created_at ASC FOR UPDATE LOOP
        EXIT WHEN v_needed_qty <= 0; v_take_qty := least(v_batch.quantity_remaining, v_needed_qty);
        UPDATE public.inventory_batches SET quantity_remaining = quantity_remaining - v_take_qty WHERE id = v_batch.id;
        v_item_cogs := v_item_cogs + v_take_qty * v_batch.cost_price; v_needed_qty := v_needed_qty - v_take_qty;
      END LOOP;
    END IF;
    INSERT INTO public.order_items (order_id, variant_id, quantity, price_at_purchase, cogs_total)
    VALUES (v_order_id, v_variant_id, v_buy_qty, v_real_price, v_item_cogs);
  END LOOP;
  RETURN jsonb_build_object('success', true, 'order_id', v_order_id, 'order_code', v_order_code);
END;
$$;

CREATE OR REPLACE FUNCTION public.restore_inventory_on_cancel() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public AS $$
DECLARE v_item record; v_target_batch_id bigint;
BEGIN
  IF new.status = 'cancelled' AND old.status <> 'cancelled' THEN
    FOR v_item IN
      SELECT oi.variant_id, oi.quantity FROM public.order_items oi
      JOIN public.variants v ON v.id = oi.variant_id
      JOIN public.products p ON p.id = v.product_id
      WHERE oi.order_id = new.id AND p.tracks_inventory
    LOOP
      SELECT id INTO v_target_batch_id FROM public.inventory_batches
        WHERE variant_id = v_item.variant_id ORDER BY created_at DESC LIMIT 1;
      IF v_target_batch_id IS NOT NULL THEN
        UPDATE public.inventory_batches SET quantity_remaining = quantity_remaining + v_item.quantity
          WHERE id = v_target_batch_id;
      END IF;
    END LOOP;
  END IF;
  RETURN new;
END;
$$;

COMMIT;
