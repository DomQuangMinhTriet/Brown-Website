# Quy ước & đóng góp

Hướng dẫn ngắn gọn về quy ước code và quy trình làm việc trong dự án BROWN.

## 1. Cấu trúc làm việc

- Frontend và backend nằm trong cùng repo nhưng cài dependencies **riêng** (`storefront/` và `server/`).
- Mỗi tính năng backend thường gồm bộ ba: `routes/` (định nghĩa endpoint) → `controllers/` (logic) → tùy chọn `services/`, `validators/`.

## 2. Quy ước code

- **Ngôn ngữ comment & UI:** Tiếng Việt là chính (giữ nhất quán với codebase hiện tại).
- **Frontend:** component React dạng function + hook. Style bằng class TailwindCSS, theo bảng màu `stone`/`brown` hiện có.
- **Đa ngôn ngữ:** mọi chuỗi hiển thị cho người dùng phải đi qua `t()` và có khóa ở **cả `vi` và `en`** trong `utils/translations.js`.
- **Backend:** dùng `async/await`, trả JSON dạng `{ success, data }` hoặc `{ success, message }`.
- **Validation:** ưu tiên dùng schema Zod trong `validators/` cho dữ liệu đầu vào quan trọng (vd: tạo đơn).

## 3. Kiểm tra trước khi commit

```bash
# Frontend
cd storefront
npm run lint
npm run build      # đảm bảo build không lỗi

# Backend
cd server
npm run dev        # chạy thử, kiểm tra không có lỗi khởi động
```

## 4. Biến môi trường & bảo mật

- **Không commit** file `.env` (đã nằm trong `.gitignore`).
- **Không** đặt `service_role_key` của Supabase ở frontend — chỉ dùng `anon` key.
- Không log/hard-code khóa API trong mã nguồn.

## 5. Quy ước commit

Theo lịch sử dự án, commit message ngắn gọn mô tả thay đổi (tiếng Việt hoặc Anh đều được), nên kèm phạm vi:

```
Update (email) (variants): điều chỉnh màu sắc tiếng Anh của biến thể
```

## 6. Thêm tính năng thường gặp

### Thêm một endpoint API
1. Viết handler trong `controllers/xxxController.js`.
2. Khai báo route trong `routes/xxxRoutes.js`.
3. Đăng ký route trong `server/server.js` nếu là nhóm route mới.
4. Cập nhật [docs/API.md](API.md).

### Thêm một trang storefront
Xem hướng dẫn từng bước trong [docs/FRONTEND.md](FRONTEND.md#ví-dụ-thêm-một-trang-chính-sách-mới).

## 7. Tài liệu liên quan

- [ARCHITECTURE.md](ARCHITECTURE.md) — kiến trúc tổng thể
- [SETUP.md](SETUP.md) — cài đặt môi trường
- [API.md](API.md) — tham chiếu API
- [DATABASE.md](DATABASE.md) — mô hình dữ liệu
- [FRONTEND.md](FRONTEND.md) — cấu trúc frontend
- [DEPLOYMENT.md](DEPLOYMENT.md) — triển khai
