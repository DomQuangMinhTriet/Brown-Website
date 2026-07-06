-- ============================================================
-- GIẢM GIÁ TRỰC TIẾP THEO BIẾN THỂ (màu + size)
-- Thay thế hoàn toàn cơ chế giảm giá cấp sản phẩm (products.discount_amount /
-- products.is_discount_active) bằng cơ chế giảm giá cấp biến thể, để có thể
-- giảm giá riêng cho từng tổ hợp màu/size (VD: chỉ giảm màu Đen size M).
-- ============================================================

-- 1) Thêm 2 cột giảm giá vào variants (mirror cấu trúc cũ ở products)
ALTER TABLE public.variants ADD COLUMN IF NOT EXISTS discount_amount numeric(12,0) DEFAULT 0;
ALTER TABLE public.variants ADD COLUMN IF NOT EXISTS is_discount_active boolean DEFAULT false;

-- 2) Dọn cột giảm giá cấp sản phẩm nếu có (môi trường nào đã lỡ tạo trước đó).
--    IF EXISTS nên vô hại nếu 2 cột này chưa từng tồn tại.
ALTER TABLE public.products DROP COLUMN IF EXISTS discount_amount;
ALTER TABLE public.products DROP COLUMN IF EXISTS is_discount_active;
