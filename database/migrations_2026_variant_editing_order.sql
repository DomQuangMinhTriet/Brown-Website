-- Cho phép lưu thứ tự hiển thị của biến thể trên trang sản phẩm.
ALTER TABLE public.variants
    ADD COLUMN IF NOT EXISTS display_order integer NOT NULL DEFAULT 0;

-- Giữ nguyên thứ tự hiện có của các biến thể cũ theo ngày tạo, rồi theo id.
WITH ranked_variants AS (
    SELECT
        id,
        ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY created_at ASC, id ASC) - 1 AS position
    FROM public.variants
)
UPDATE public.variants AS variants
SET display_order = ranked_variants.position
FROM ranked_variants
WHERE variants.id = ranked_variants.id;

CREATE INDEX IF NOT EXISTS variants_product_display_order_idx
    ON public.variants (product_id, display_order);
