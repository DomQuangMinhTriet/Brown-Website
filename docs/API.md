# Tham chiếu REST API

Tài liệu các endpoint của backend (`server/`). Tất cả đều có tiền tố `/api`.

- **Base URL (dev):** `http://localhost:5000`
- **Định dạng:** JSON
- **Xác thực:** Các thao tác admin/ghi yêu cầu header `Authorization: Bearer <supabase_access_token>` (xem `middleware/authMiddleware.js`).
- **Validation:** Một số route dùng schema Zod (`validators/`) qua `validateMiddleware`.

> Định nghĩa chi tiết nằm trong `server/routes/*.js` và logic xử lý trong `server/controllers/*.js`.

---

## Products — `/api/products`

| Method | Endpoint | Mô tả |
|--------|----------|-------|
| GET | `/api/products` | Danh sách sản phẩm |
| GET | `/api/products/:slug` | Chi tiết sản phẩm theo slug |
| POST | `/api/products` | Tạo sản phẩm mới (nhận `discount_amount`, `is_discount_active`) |
| PUT | `/api/products/:id` | Cập nhật sản phẩm |
| PUT | `/api/products/:id/discount` | Bật/tắt & set **giảm giá trực tiếp** cho sản phẩm |
| DELETE | `/api/products/:id` | Xóa sản phẩm |
| GET | `/api/products/export/sapo` | Xuất danh sách sản phẩm định dạng Sapo |

## Categories — `/api/categories`

| Method | Endpoint | Mô tả |
|--------|----------|-------|
| GET | `/api/categories` | Danh sách danh mục |
| POST | `/api/categories` | Tạo danh mục |
| DELETE | `/api/categories/:id` | Xóa danh mục |
| PUT | `/api/categories/:id/visibility` | Bật/tắt hiển thị danh mục |

## Orders — `/api/orders`

| Method | Endpoint | Mô tả |
|--------|----------|-------|
| POST | `/api/orders/shipping-fee` | Tính phí vận chuyển cho đơn |
| POST | `/api/orders` | Tạo đơn hàng (khách online) |
| GET | `/api/orders` | Danh sách đơn hàng |
| PUT | `/api/orders/bulk-status` | Cập nhật trạng thái hàng loạt |
| PUT | `/api/orders/:id/details` | Cập nhật chi tiết đơn |
| PUT | `/api/orders/:id/status` | Cập nhật trạng thái một đơn |
| POST | `/api/orders/create-admin` | Tạo đơn tại quầy (admin) |
| GET | `/api/orders/export/sapo` | Xuất đơn hàng định dạng Sapo |
| GET | `/api/orders/accessory` | Lấy dữ liệu phụ trợ cho tạo đơn |

## Inventory — `/api/inventory`

| Method | Endpoint | Mô tả |
|--------|----------|-------|
| GET | `/api/inventory/suppliers` | Danh sách nhà cung cấp |
| POST | `/api/inventory/suppliers` | Thêm nhà cung cấp |
| GET | `/api/inventory/stores` | Danh sách kho/chi nhánh |
| POST | `/api/inventory/stores` | Thêm kho |
| GET | `/api/inventory/stock` | Tồn kho hiện tại |
| GET | `/api/inventory/history` | Lịch sử xuất/nhập kho |
| POST | `/api/inventory/inbound` | Nhập kho (tạo lô FIFO) |
| POST | `/api/inventory/adjust` | Điều chỉnh tồn kho |
| POST | `/api/inventory/defective` | Ghi nhận hàng lỗi |
| GET | `/api/inventory/defective` | Danh sách hàng lỗi |

## Master data — `/api/master`

| Method | Endpoint | Mô tả |
|--------|----------|-------|
| GET | `/api/master/stores` | Danh sách kho |
| POST | `/api/master/stores` | Thêm kho |
| GET | `/api/master/suppliers` | Danh sách nhà cung cấp |
| POST | `/api/master/suppliers` | Thêm nhà cung cấp |

## Customers — `/api/customers`

| Method | Endpoint | Mô tả |
|--------|----------|-------|
| GET | `/api/customers` | Danh sách khách hàng |
| GET | `/api/customers/:id` | Chi tiết khách hàng |
| GET | `/api/customers/:id/history` | Lịch sử mua hàng |
| GET | `/api/customers/me/profile` | Hồ sơ của khách đang đăng nhập |
| PUT | `/api/customers/me/profile` | Cập nhật hồ sơ |
| POST | `/api/customers/register` | Đăng ký khách hàng |

## Promotions — `/api/promotions`

| Method | Endpoint | Mô tả |
|--------|----------|-------|
| GET | `/api/promotions` | Danh sách khuyến mãi |
| POST | `/api/promotions` | Tạo voucher (nhận `applicable_product_ids`; `usage_limit`/`end_date` để trống = không giới hạn) |
| DELETE | `/api/promotions/:id` | Xóa voucher |
| POST | `/api/promotions/check` | Kiểm tra & áp mã. Body `{ code, items: [{product_id, quantity}] }` — server tự tính giảm **chỉ trên các SP được áp mã** và **loại SP đang giảm giá trực tiếp** |

## Expenses — `/api/expenses`

| Method | Endpoint | Mô tả |
|--------|----------|-------|
| GET | `/api/expenses` | Danh sách phiếu chi |
| POST | `/api/expenses` | Tạo phiếu chi |
| DELETE | `/api/expenses/:id` | Xóa phiếu chi |
| GET | `/api/expenses/categories` | Danh mục chi phí |
| POST | `/api/expenses/categories` | Thêm danh mục chi phí |

## Reports — `/api/reports`

| Method | Endpoint | Mô tả |
|--------|----------|-------|
| GET | `/api/reports/dashboard` | Số liệu tổng quan dashboard |
| GET | `/api/reports/financial` | Báo cáo tài chính (`?startDate=&endDate=`) |
| GET | `/api/reports/monthly` | Báo cáo theo tháng |

## Shipping — `/api/shipping`

| Method | Endpoint | Mô tả |
|--------|----------|-------|
| POST | `/api/shipping/calculate` | Tính phí ship qua GHN |

## Content — `/api/content`

| Method | Endpoint | Mô tả |
|--------|----------|-------|
| GET | `/api/content/banners` | Danh sách banner trang chủ |
| POST | `/api/content/banners` | Thêm banner |
| PUT | `/api/content/banners/:id` | Cập nhật banner |
| DELETE | `/api/content/banners/:id` | Xóa banner |
| GET | `/api/content/lookbook` | Danh sách nội dung Lookbook (cache 5 phút) |
| POST | `/api/content/lookbook` | Thêm mục Lookbook (`block_type`, `image_url`, `image_url_2`…) |
| PUT | `/api/content/lookbook/:id` | Cập nhật mục (sửa nội dung, thứ tự, ẩn/hiện) |
| DELETE | `/api/content/lookbook/:id` | Xóa mục Lookbook |

## Upload — `/api/upload`

| Method | Endpoint | Mô tả |
|--------|----------|-------|
| POST | `/api/upload` | Upload ảnh lên Cloudinary (multipart/form-data, dùng Multer) |

---

## Quy ước phản hồi

Phần lớn endpoint trả về JSON dạng:

```json
{ "success": true, "data": ... }
```

Khi lỗi:

```json
{ "success": false, "message": "Mô tả lỗi" }
```

Mã trạng thái thường gặp: `200` OK, `400` dữ liệu sai, `401` chưa xác thực, `500` lỗi server.
