# Triển khai (Deployment)

Hướng dẫn đưa hệ thống BROWN lên môi trường production.

## 1. Tổng quan hạ tầng

| Thành phần | Gợi ý nền tảng |
|------------|----------------|
| Frontend (`storefront/`) | Vercel / Netlify (static SPA) |
| Backend (`server/`) | Render / Railway / VPS (Node.js) |
| Database + Auth | Supabase (managed) |
| Ảnh | Cloudinary |
| Email | Resend |

Domain production hiện tại: `https://brownvn.com` (và bản Vercel `https://brown-website-dcmd.vercel.app`).

## 2. Triển khai Frontend

1. Build:
   ```bash
   cd storefront
   npm install
   npm run build      # tạo thư mục dist/
   ```
2. Cấu hình biến môi trường trên nền tảng host:
   - `VITE_API_URL` → URL backend production
   - `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`
3. Deploy thư mục `dist/` (hoặc kết nối Git để auto-build).
4. **SPA routing:** cấu hình rewrite tất cả request về `index.html` để React Router hoạt động (Vercel/Netlify thường tự xử lý).

## 3. Triển khai Backend

1. Cài dependencies và chạy:
   ```bash
   cd server
   npm install
   npm start          # node server.js
   ```
2. Cấu hình **đầy đủ biến môi trường** (xem [SETUP.md](SETUP.md#3-cấu-hình-backend-server)).
3. Mở port theo biến `PORT` (mặc định 5000).

## 4. Cấu hình CORS

Sau khi có domain production, thêm domain vào `allowedOrigins` trong [`server/server.js`](../server/server.js):

```js
const allowedOrigins = [
  "http://localhost:5173",
  "https://brown-website-dcmd.vercel.app",
  "https://brownvn.com"
];
```

> Hiện cấu hình đang tạm cho phép mọi origin để dễ test — nên siết lại trong production bằng cách bật nhánh chặn CORS.

## 5. Checklist trước khi go-live

- [ ] Đã chạy bản `brownvn_complete.sql` đã được quản trị dự án cung cấp trên Supabase production (hoặc migration đã được phê duyệt)
- [ ] Phân quyền `anon` chỉ `SELECT` (đã có trong schema)
- [ ] Tất cả biến `.env` backend đã cấu hình (Supabase, Cloudinary, Resend, GHN)
- [ ] Biến `VITE_*` frontend trỏ đúng backend production
- [ ] `allowedOrigins` đã thêm domain thật
- [ ] Bật HTTPS cho cả frontend và backend
- [ ] Kiểm tra luồng: xem sản phẩm → đặt hàng → nhận email → cập nhật trạng thái admin

## 6. Quản lý phiên bản cache phía client

Trong `storefront/src/App.jsx` có cơ chế `APP_VERSION`: khi tăng số version, client sẽ tự dọn `localStorage` và reload để tránh lỗi cache cũ. Nhớ tăng `APP_VERSION` sau mỗi đợt fix lớn ảnh hưởng dữ liệu lưu ở client.
