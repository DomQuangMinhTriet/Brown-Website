-- =====================================================================
-- MIGRATION 2026 — Video sản phẩm + An toàn lưu trữ media
-- Chạy toàn bộ file này 1 lần trong Supabase → SQL Editor → Run.
-- Idempotent (chạy lại nhiều lần không lỗi).
--
-- LƯU Ý: Các phần "an toàn lưu trữ" khác (giới hạn dung lượng upload, tự
-- dọn file Cloudinary khi xóa/thay ảnh, audit file mồ côi) đều là thay đổi
-- ở CODE backend (server/), không cần chỉnh gì thêm ở database ngoài file
-- SQL này.
-- =====================================================================

-- ------------------------------------------------------------------
-- Video sản phẩm — nằm chung nhóm với hình ảnh, hiển thị nối sau ảnh trên
-- trang chi tiết sản phẩm. Mỗi video tối đa 10s / 15MB (kiểm tra ở backend).
-- ------------------------------------------------------------------
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS videos text[] DEFAULT '{}'::text[];

-- Buộc PostgREST nạp lại schema cache để nhận cột mới ngay
NOTIFY pgrst, 'reload schema';
