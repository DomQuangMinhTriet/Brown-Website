# BROWN — Hệ thống Thương mại điện tử Thời trang

**BROWN** là nền tảng bán hàng thời trang full-stack, bao gồm một website bán hàng (storefront) song ngữ Việt – Anh và một trang quản trị (admin dashboard) đầy đủ tính năng quản lý bán hàng, kho hàng theo phương pháp **FIFO**, khách hàng, khuyến mãi, tài chính và báo cáo.

> Hộ Kinh Doanh BROWNVN — https://brownvn.com

---

## Mục lục

- [Tính năng chính](#tính-năng-chính)
- [Kiến trúc tổng quan](#kiến-trúc-tổng-quan)
- [Công nghệ sử dụng](#công-nghệ-sử-dụng)
- [Cấu trúc thư mục](#cấu-trúc-thư-mục)
- [Bắt đầu nhanh](#bắt-đầu-nhanh)
- [Tài liệu chi tiết](#tài-liệu-chi-tiết)

---

## Tính năng chính

### Storefront (Khách hàng)
- Trang chủ, danh mục sản phẩm, chi tiết sản phẩm (theo biến thể size/màu)
- Giỏ hàng & thanh toán (COD / Banking / PayPal), tính phí vận chuyển
- Tài khoản khách hàng, lịch sử đơn hàng, theo dõi đơn realtime
- Đa ngôn ngữ **Tiếng Việt / Tiếng Anh**, tự động đổi tiền tệ (VND/USD)
- Các trang chính sách: đổi hàng, vận chuyển, hướng dẫn bảo quản

### Admin (Quản trị)
- **Dashboard** & báo cáo tài chính (doanh thu, lợi nhuận, COGS theo FIFO)
- **Sản phẩm**: quản lý sản phẩm, biến thể (SKU), danh mục, hình ảnh (Cloudinary)
- **Đơn hàng**: tạo đơn tại quầy, cập nhật trạng thái, xuất file Sapo/Excel
- **Kho hàng**: nhập kho, điều chỉnh, hàng lỗi, tồn kho theo lô (FIFO)
- **Khách hàng**, **Khuyến mãi** (voucher), **Chi phí** (quản lý tài chính)
- **Giao diện**: quản lý banner trang chủ

---

## Kiến trúc tổng quan

```
┌──────────────────────────┐         ┌──────────────────────────┐
│      storefront/         │         │        server/           │
│  React SPA (Vite)        │  HTTP   │  Express REST API        │
│  - Storefront (khách)    │ ──────► │  - Controllers / Routes  │
│  - Admin (/admin/*)      │  axios  │  - Services (mail/ship)  │
└───────────┬──────────────┘         └────────────┬─────────────┘
            │                                      │
            │ Supabase JS (Auth + đọc dữ liệu)     │ Supabase (postgres)
            └──────────────────┬───────────────────┘
                               ▼
                  ┌──────────────────────────┐
                  │   Supabase / PostgreSQL  │
                  │ (brownvn_complete.sql)   │
                  └──────────────────────────┘

Dịch vụ ngoài: Cloudinary (ảnh) · Resend/SMTP (email) · GHN (vận chuyển) · PayPal
```

Chi tiết: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

---

## Công nghệ sử dụng

| Lớp | Công nghệ |
|-----|-----------|
| Frontend | React 19, Vite (rolldown-vite), React Router 7, TailwindCSS 4, Framer Motion |
| Biểu đồ / Xuất file | Chart.js, Recharts, xlsx |
| Backend | Node.js, Express 5, Zod (validation), Multer, node-cache |
| Database / Auth | Supabase (PostgreSQL + Auth) |
| Dịch vụ ngoài | Cloudinary, Resend / Nodemailer, GHN (Giao Hàng Nhanh), PayPal |

---

## Cấu trúc thư mục

```
Brown-Website/
├── storefront/        # Ứng dụng React (storefront + admin dashboard)
│   └── src/
│       ├── pages/         # Trang storefront + pages/admin/*
│       ├── components/     # Navbar, Sidebar, Header, ProductModal...
│       ├── context/        # Auth, Cart, Language, AdminAuth
│       └── utils/          # translations, currencyHelper, geoDetection
├── server/            # API Express
│   ├── controllers/        # Logic nghiệp vụ
│   ├── routes/             # Định nghĩa endpoint
│   ├── services/           # emailService, shippingService
│   ├── middleware/         # auth, cache, validate
│   └── validators/         # Zod schema
├── database/          # SQL khởi tạo cục bộ (bị Git ignore)
└── docs/              # Tài liệu dự án
```

---

## Bắt đầu nhanh

Yêu cầu: **Node.js 18+** và một project **Supabase**.

```bash
# 1. Backend
cd server
npm install
cp .env.example .env      # điền các biến môi trường (xem docs/SETUP.md)
npm run dev               # chạy tại http://localhost:5000

# 2. Frontend (mở terminal mới)
cd storefront
npm install
# tạo file .env với VITE_API_URL, VITE_SUPABASE_URL, VITE_SUPABASE_ANON_KEY
npm run dev               # chạy tại http://localhost:5173
```

Hướng dẫn cài đặt đầy đủ (biến môi trường, khởi tạo database): [docs/SETUP.md](docs/SETUP.md)

---

## Tài liệu chi tiết

| Tài liệu | Nội dung |
|----------|----------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Kiến trúc hệ thống, luồng dữ liệu, xác thực |
| [docs/SETUP.md](docs/SETUP.md) | Cài đặt môi trường, biến `.env`, khởi tạo DB |
| [docs/API.md](docs/API.md) | Tham chiếu toàn bộ REST API endpoint |
| [docs/DATABASE.md](docs/DATABASE.md) | Mô hình dữ liệu & cơ chế kho FIFO |
| [docs/FRONTEND.md](docs/FRONTEND.md) | Cấu trúc frontend, routing, đa ngôn ngữ |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Triển khai production |
| [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) | Quy ước code & quy trình đóng góp |

---

© 2026 BROWN. All rights reserved.
