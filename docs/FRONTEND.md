# Cấu trúc Frontend

Ứng dụng React (`storefront/`) chứa **cả storefront cho khách lẫn admin dashboard** trong một codebase, phân tách bằng routing.

## 1. Công nghệ

- **React 19** + **Vite** (`rolldown-vite`)
- **React Router 7** (routing)
- **TailwindCSS 4** (styling, qua plugin `@tailwindcss/vite`)
- **Framer Motion** (animation)
- **Chart.js / Recharts** (biểu đồ báo cáo)
- **react-toastify** (thông báo), **xlsx** (xuất Excel), **@paypal/react-paypal-js** (thanh toán)

## 2. Cấu trúc thư mục `src/`

```
src/
├── App.jsx               # Định nghĩa toàn bộ route + layout
├── main.jsx              # Điểm khởi động, bọc các Provider
├── supabaseClient.js     # Khởi tạo Supabase client (anon key)
├── pages/
│   ├── Home.jsx, Collection.jsx, ProductDetail.jsx
│   ├── Cart.jsx, Checkout.jsx
│   ├── Login.jsx, Register.jsx, Profile.jsx
│   ├── policies/         # ReturnPolicy, ShippingPolicy, CareGuide
│   └── admin/            # Toàn bộ trang quản trị
├── components/           # Navbar, Sidebar, Header, ProductModal, SEO, AdminRoute
├── context/              # AuthContext, AdminAuthContext, CartContext, LanguageContext
├── hooks/                # useAsync, useRealtimeOrder
└── utils/                # translations.js, currencyHelper.js, geoDetection.js
```

## 3. Routing (`App.jsx`)

Hai khu vực chính:

### Storefront — prefix `/`
Bọc trong `StorefrontLayout` (Navbar + Footer):

| Route | Trang |
|-------|-------|
| `/` | Home |
| `/collection` | Danh sách sản phẩm |
| `/product/:slug` | Chi tiết sản phẩm |
| `/cart`, `/checkout` | Giỏ hàng, thanh toán |
| `/login`, `/register`, `/account` | Tài khoản |
| `/policy/return`, `/policy/shipping`, `/policy/care` | Trang chính sách |

### Admin — prefix `/admin`
Bảo vệ bởi `AdminRoute`, bọc trong `AdminLayoutWrapper` (Sidebar + Header, kèm `useRealtimeOrder`):

| Route | Trang |
|-------|-------|
| `/admin/login` | Đăng nhập admin |
| `/admin` | Dashboard |
| `/admin/products` | Quản lý sản phẩm |
| `/admin/orders`, `/admin/orders/create` | Đơn hàng, tạo đơn |
| `/admin/inventory`, `/admin/inventory/defective` | Kho hàng, hàng lỗi |
| `/admin/customers` | Khách hàng |
| `/admin/promotions` | Khuyến mãi |
| `/admin/expenses` | Chi phí |
| `/admin/reports` | Báo cáo |
| `/admin/appearance` | Giao diện (banner) |

## 4. Context (state toàn cục)

| Context | Vai trò |
|---------|---------|
| `AuthContext` | Phiên đăng nhập khách hàng (Supabase Auth) |
| `AdminAuthContext` | Phiên đăng nhập quản trị viên |
| `CartContext` | Giỏ hàng, số lượng, tổng tiền |
| `LanguageContext` | Ngôn ngữ hiện tại + hàm `t()` để dịch |

## 5. Đa ngôn ngữ (i18n)

- Toàn bộ chuỗi nằm trong `utils/translations.js`, chia 2 nhánh `vi` và `en` với cùng cấu trúc khóa lồng nhau (vd: `nav.home`, `policies.care_title`).
- Dùng qua hook: `const { t, lang, toggleLang } = useLanguage()` rồi `t('nav.home')`.
- Ngôn ngữ mặc định là `vi`, lưu lựa chọn của khách trong `localStorage` (`user_lang`).
- **Khi thêm text mới: luôn bổ sung khóa cho CẢ `vi` và `en`** để giữ song ngữ đầy đủ.

### Ví dụ thêm một trang chính sách mới
1. Tạo component trong `pages/policies/`, dùng `t('policies.xxx')`.
2. Thêm khóa dịch vào `policies` của cả `vi` và `en` trong `translations.js`.
3. Thêm `<Route>` trong `App.jsx`.
4. Thêm link trong `components/Navbar.jsx` (cả menu desktop và mobile), dùng `t('nav.xxx')`.

## 6. Tiền tệ

`utils/currencyHelper.js` xử lý hiển thị giá theo ngôn ngữ: VND cho `vi`, quy đổi USD cho `en` (cùng tỷ giá với backend trong `emailService.js`).

## 7. Realtime

`hooks/useRealtimeOrder.jsx` đăng ký kênh realtime của Supabase để cập nhật đơn hàng tức thì trong admin dashboard.

## 8. Gọi API

Frontend gọi backend qua `axios` với base URL từ `import.meta.env.VITE_API_URL`, ví dụ:

```js
const res = await axios.get(`${import.meta.env.VITE_API_URL}/api/products`);
```

Với thao tác cần xác thực, gắn token Supabase vào header `Authorization`.
