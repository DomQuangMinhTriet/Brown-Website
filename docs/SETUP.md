# Hướng dẫn cài đặt & cấu hình

Hướng dẫn thiết lập môi trường phát triển cho hệ thống BROWN.

## 1. Yêu cầu hệ thống

- **Node.js** 18 trở lên
- **npm** (đi kèm Node.js)
- Một project **Supabase** (PostgreSQL + Auth)
- Tài khoản các dịch vụ ngoài (tùy chọn khi dev): Cloudinary, Resend, GHN

## 2. Cài đặt mã nguồn

```bash
git clone <repo-url>
cd Brown-Website
```

Dự án gồm 2 phần cần cài dependencies riêng: `server/` và `storefront/`.

## 3. Cấu hình Backend (`server/`)

```bash
cd server
npm install
```

Tạo file `server/.env` với các biến sau:

```env
# Server
PORT=5000

# Supabase (Project Settings > API)
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_KEY=<service_role_key>

# Email — SMTP (nếu dùng Gmail, tạo App Password)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your@gmail.com
SMTP_PASS=<app_password>

# Email — Resend (ưu tiên dùng cho email đơn hàng)
RESEND_API_KEY=<resend_api_key>
MY_EMAIL=admin@yourdomain.com

# Vận chuyển — GHN (Giao Hàng Nhanh)
GHN_API_TOKEN=<ghn_token>
GHN_SHOP_ID=<ghn_shop_id>
GHN_API_URL=https://online-gateway.ghn.vn/shiip/public-api

# Cloudinary (lưu trữ ảnh)
CLOUDINARY_CLOUD_NAME=<cloud_name>
CLOUDINARY_API_KEY=<api_key>
CLOUDINARY_API_SECRET=<api_secret>
```

Chạy backend:

```bash
npm run dev      # nodemon, tự reload (development)
npm start        # node server.js (production)
```

API mặc định chạy tại `http://localhost:5000`. Kiểm tra health check tại `GET /`.

## 4. Cấu hình Frontend (`storefront/`)

```bash
cd storefront
npm install
```

Tạo file `storefront/.env`:

```env
# URL của backend API
VITE_API_URL=http://localhost:5000

# Supabase (dùng anon key, KHÔNG dùng service key ở frontend)
VITE_SUPABASE_URL=https://xxxx.supabase.co
VITE_SUPABASE_ANON_KEY=<anon_public_key>
```

> ⚠️ Biến frontend bắt buộc có tiền tố `VITE_` để Vite expose ra client. **Không bao giờ** đặt `service_role_key` ở frontend.

Các lệnh:

```bash
npm run dev       # development tại http://localhost:5173
npm run build     # build production ra dist/
npm run preview   # xem thử bản build
npm run lint      # kiểm tra ESLint
```

## 5. Khởi tạo Database

1. Tạo project trên [Supabase](https://supabase.com).
2. Mở **SQL Editor**, chạy nội dung file tổng [`database/full_schema_data.sql`](../database/full_schema_data.sql).
   - Đây là bản `pg_dump` đầy đủ: tạo toàn bộ bảng, index, stored function, cấp quyền (`GRANT`) và nạp dữ liệu (dạng `COPY`).
3. Lấy `SUPABASE_URL`, `service_role_key` (cho backend) và `anon_key` (cho frontend) tại **Project Settings > API**.

> `database/prod-ca-2021.crt` là certificate SSL dùng khi cần kết nối trực tiếp tới Supabase qua chứng chỉ.

## 6. Bật xác thực Supabase Auth

Trong Supabase Dashboard → **Authentication**, bật Email provider để cho phép đăng ký/đăng nhập khách hàng và quản trị viên.

## 7. Kiểm tra kết nối

1. Backend chạy ở port 5000, truy cập `http://localhost:5000` thấy `API Server is running...`.
2. Frontend chạy ở port 5173, trang chủ load được danh sách sản phẩm (gọi `GET /api/products`).
3. Truy cập `/admin/login` để vào trang quản trị.

## 8. Sự cố thường gặp

| Lỗi | Nguyên nhân & cách xử lý |
|-----|--------------------------|
| Frontend không gọi được API | Kiểm tra `VITE_API_URL` và CORS `allowedOrigins` trong `server/server.js` |
| 401 Unauthorized | Token Supabase thiếu/hết hạn — đăng nhập lại |
| Ảnh không upload được | Thiếu/cấu hình sai biến `CLOUDINARY_*` |
| Không gửi được email | Kiểm tra `RESEND_API_KEY` hoặc cấu hình `SMTP_*` |
