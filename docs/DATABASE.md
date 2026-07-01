# Mô hình dữ liệu

Cơ sở dữ liệu PostgreSQL (Supabase). Toàn bộ schema, stored function và dữ liệu nằm trong file tổng [`database/full_schema_data.sql`](../database/full_schema_data.sql) — bản `pg_dump` đầy đủ và mới nhất.

## 1. Tổng quan các bảng

| Nhóm | Bảng | Vai trò |
|------|------|---------|
| Danh mục | `stores` | Chi nhánh / kho hàng |
| | `categories` | Danh mục sản phẩm (hỗ trợ cha–con qua `parent_id`) |
| | `suppliers` | Nhà cung cấp |
| Sản phẩm | `products` | Sản phẩm (thông tin chung, `base_price`, mảng `images`, **giảm giá trực tiếp** `discount_amount`/`is_discount_active`) |
| | `product_categories` | Bảng trung gian sản phẩm ↔ danh mục (n–n) |
| | `variants` | Biến thể/SKU (size, màu, giá, ảnh riêng) |
| Kho FIFO | `purchase_orders` | Phiếu nhập kho |
| | `purchase_items` | Chi tiết phiếu nhập (giá vốn lúc nhập) |
| | `inventory_batches` | **Lô tồn kho** — cốt lõi tính FIFO |
| Khách & KM | `customers` | Khách hàng (liên kết Supabase Auth qua `user_id`) |
| | `promotions` | Voucher giảm giá (áp cho SP cụ thể qua `applicable_product_ids`; `usage_limit`/`end_date` = NULL là không giới hạn) |
| | `carts` / `cart_items` | Giỏ hàng (khách đã đăng nhập) |
| Bán hàng | `orders` | Đơn hàng |
| | `order_items` | Chi tiết đơn (giá bán + `cogs_total` theo FIFO) |
| Tài chính | `expense_categories` | Danh mục chi phí |
| | `expenses` | Phiếu chi |
| Nội dung | `banners` / `content_banners` | Banner hiển thị trang chủ |
| | `content_lookbook` | Nội dung trang Lookbook editorial (`block_type`: full/compare/quote, `image_url_2` cho slider) |
| | `product_collections` | Bộ sưu tập / nhóm sản phẩm |

## 2. Sơ đồ quan hệ chính

```
categories ──┐
             ├─< product_categories >── products ──< variants ──┐
suppliers ───┤                                                  │
   │         │                                                  │
   ▼         ▼                                                  ▼
purchase_orders ──< purchase_items ──────────────► inventory_batches
                                                          │ (FIFO)
                                                          ▼
customers ──< orders ──< order_items >──────────────── variants
   │           │
   │           ├── promotions (promotion_id)
   │           └── stores (store_id)
   │
carts ──< cart_items >── variants

stores ──< expenses >── expense_categories
```

## 3. Kho FIFO

Đây là phần trọng tâm của hệ thống. Logic đặt hàng + trừ kho FIFO được đóng gói trong **stored function** `create_order_transaction(...)` (định nghĩa trong file dump), đảm bảo tạo đơn và trừ tồn kho diễn ra trong cùng một transaction.

### Cơ chế
1. **Nhập kho**: mỗi lần nhập tạo `purchase_orders` + `purchase_items`, đồng thời sinh các **lô** trong `inventory_batches` với `quantity_remaining = original_quantity` và `cost_price` (giá vốn lô đó).
2. **Bán hàng**: khi tạo `order_items`, hệ thống trừ dần `quantity_remaining` từ **lô cũ nhất** (sắp xếp theo `created_at ASC`) và cộng dồn vào `cogs_total` của dòng đơn → giá vốn chính xác theo nguyên tắc nhập trước–xuất trước.
3. **Index** `idx_inventory_fifo (store_id, variant_id, created_at ASC)` đảm bảo truy vấn lô theo thứ tự FIFO nhanh.

### Vì sao quan trọng
Cho phép tính **lợi nhuận thực** (doanh thu − COGS) chính xác ngay cả khi giá vốn thay đổi giữa các lần nhập — phục vụ báo cáo tài chính (`/api/reports/financial`).

## 4. Một số trường đáng chú ý

| Bảng.Cột | Ghi chú |
|----------|---------|
| `products.images` | Kiểu `TEXT[]` — mảng link ảnh (Cloudinary) |
| `variants.current_price` | Nếu `NULL` thì lấy `products.base_price` |
| `orders.status` | `pending`, `confirmed`, `shipping`, `completed`, `cancelled`, `returned` |
| `orders.payment_method` | `cod`, `banking` (và PayPal phía frontend) |
| `orders.customer_*` | Lưu thông tin người nhận cho **đơn khách vãng lai** |
| `order_items.cogs_total` | Giá vốn dòng hàng, tính bằng logic FIFO sau khi bán |
| `promotions.discount_type` | `percent` hoặc `fixed` |
| `promotions.applicable_product_ids` | `jsonb` mảng id SP được áp mã; `[]` = áp cho **mọi** SP. Voucher chỉ giảm trên tiền các SP này, và **không cộng dồn** với SP đang giảm giá trực tiếp |
| `products.discount_amount` / `is_discount_active` | Giảm giá trực tiếp theo **số tiền**; giá bán = `base_price − discount_amount` khi bật. Giá gốc vẫn lưu ở `base_price` |
| `content_lookbook.block_type` | `full` (ảnh/video tràn viền) · `compare` (slider 2 ảnh, cần `image_url_2`) · `quote` (câu trích dẫn, không cần ảnh) |
| `customers.user_id` | `UUID` liên kết Supabase Auth; `NULL` nếu khách vãng lai |

## 5. Stored functions

File dump bao gồm các function PL/pgSQL chạy trực tiếp trong database, đáng chú ý:
- `create_order_transaction(...)` — tạo đơn hàng và trừ tồn kho theo FIFO trong một transaction.

## 6. Phân quyền (GRANT)

- `service_role` & `postgres`: toàn quyền (dùng ở backend).
- `anon` (khóa public ở frontend): chỉ `SELECT` — chỉ đọc dữ liệu công khai.

## 7. File dữ liệu

`database/full_schema_data.sql` là **file tổng duy nhất**: bản `pg_dump` đầy đủ gồm schema, stored function, index, phân quyền và toàn bộ dữ liệu (dạng `COPY`). Dùng file này để khôi phục hoặc khởi tạo lại database. Certificate `database/prod-ca-2021.crt` dùng cho kết nối SSL tới Supabase.

`database/migrations_2026_promotions_lookbook.sql` là **file migration tăng dần** (idempotent) cho các nâng cấp 2026: bảng `content_lookbook`, giảm giá trực tiếp sản phẩm, và voucher theo sản phẩm. Chạy file này trong Supabase SQL Editor để cập nhật một database đang chạy mà không cần khôi phục toàn bộ.
