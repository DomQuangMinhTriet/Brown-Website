# Kiến trúc hệ thống

Tài liệu mô tả kiến trúc tổng thể, các thành phần và luồng dữ liệu của hệ thống BROWN.

## 1. Tổng quan các thành phần

Hệ thống gồm 3 phần chính nằm trong cùng một repository (monorepo nhẹ, không dùng workspace tool):

| Thư mục | Vai trò | Công nghệ |
|---------|---------|-----------|
| `storefront/` | Ứng dụng web React (gộp cả storefront cho khách và admin dashboard) | React 19 + Vite |
| `server/` | REST API backend | Node.js + Express 5 |
| `database/` | Schema PostgreSQL và dữ liệu mẫu | Supabase / PostgreSQL |

> **Lưu ý:** Storefront và Admin **dùng chung một codebase React**. Phần admin được phân tách bằng route `/admin/*` và bảo vệ bởi `AdminRoute` (xem [FRONTEND.md](FRONTEND.md)).

## 2. Sơ đồ kiến trúc

```
                         Người dùng (Khách / Quản trị viên)
                                       │
                                       ▼
                    ┌──────────────────────────────────────┐
                    │            storefront/ (SPA)          │
                    │                                       │
                    │   Storefront  ──┐      ┌── Admin      │
                    │   (/, /product) │      │  (/admin/*)  │
                    └─────────┬───────┴──────┴──────┬───────┘
                              │                      │
              Supabase JS     │                      │  axios → REST
        (Auth + đọc dữ liệu)  │                      │
                              ▼                      ▼
              ┌───────────────────────┐   ┌────────────────────────┐
              │   Supabase Postgres   │◄──│      server/ (API)     │
              │   + Supabase Auth     │   │  Express + Controllers  │
              └───────────────────────┘   └───────────┬────────────┘
                                                       │
                          ┌────────────────────────────┼────────────────────┐
                          ▼                ▼            ▼          ▼          ▼
                     Cloudinary       Resend/SMTP      GHN      PayPal    node-cache
                       (ảnh)            (email)      (ship)   (thanh toán) (cache)
```

## 3. Luồng dữ liệu chính

### 3.1. Đọc dữ liệu công khai (sản phẩm, danh mục, banner)
Frontend gọi REST API (`server/`), backend dùng Supabase service key để truy vấn PostgreSQL. Một số nơi frontend dùng trực tiếp Supabase JS với khóa `anon` (chỉ quyền `SELECT`).

### 3.2. Xác thực (Authentication)
- Đăng nhập/đăng ký qua **Supabase Auth** (phía frontend, lưu token trong `localStorage`).
- Khi gọi API cần quyền, frontend gắn header `Authorization: Bearer <token>`.
- Backend xác minh token qua `middleware/authMiddleware.js` → `supabase.auth.getUser(token)`, gắn `req.user` rồi cho đi tiếp.

### 3.3. Đặt hàng (Checkout)
1. Khách chọn sản phẩm → giỏ hàng (`CartContext`).
2. Tính phí ship (`POST /api/orders/shipping-fee` hoặc `/api/shipping/calculate` → GHN).
3. Tạo đơn (`POST /api/orders`): backend ghi `orders` + `order_items`, trừ tồn kho theo **FIFO** và tính `cogs_total`.
4. Gửi email xác nhận cho khách + admin qua `services/emailService.js` (Resend).

### 3.4. Kho hàng FIFO
Mỗi lần nhập hàng tạo một **lô** (`inventory_batches`). Khi bán, hệ thống trừ dần từ lô **cũ nhất** (sort theo `created_at ASC`) để tính giá vốn (COGS) chính xác. Chi tiết: [DATABASE.md](DATABASE.md#kho-fifo).

## 4. Middleware backend

| Middleware | Chức năng |
|------------|-----------|
| `authMiddleware.js` | Xác minh token Supabase, bảo vệ route admin |
| `cacheMiddleware.js` | Cache phản hồi bằng `node-cache` (giảm tải DB) |
| `validateMiddleware.js` | Kiểm tra dữ liệu đầu vào bằng schema Zod (`validators/`) |

## 5. CORS & bảo mật

- Danh sách `allowedOrigins` được cấu hình trong `server/server.js` (localhost + domain production).
- Token Supabase được xác thực ở backend cho mọi thao tác ghi.
- Khóa `anon` của Supabase chỉ có quyền `SELECT` (cấu hình `GRANT` trong `full_schema_data.sql`).

## 6. Tích hợp dịch vụ ngoài

| Dịch vụ | Mục đích | Cấu hình (.env) |
|---------|----------|-----------------|
| Cloudinary | Lưu trữ & tối ưu ảnh sản phẩm | `CLOUDINARY_*` |
| Resend / SMTP | Gửi email đơn hàng | `RESEND_API_KEY`, `SMTP_*` |
| GHN | Tính phí & tạo đơn vận chuyển | `GHN_*` |
| PayPal | Thanh toán quốc tế | cấu hình phía frontend |
| Supabase | Database + Auth | `SUPABASE_URL`, `SUPABASE_KEY` |
