
import { useState, useEffect, lazy, Suspense } from 'react';
import { BrowserRouter, Routes, Route, Outlet } from 'react-router-dom';

// ==============================
// 1. IMPORTS CHO STOREFRONT
// ==============================
import Navbar from './components/Navbar';
import Home from './pages/Home';
import Footer from './components/Footer';
import Preloader from './components/Preloader';
//import About from './pages/About';

// [Code-split] Trang chủ là điểm vào phổ biến nhất nên tải ngay (eager); các trang
// còn lại của storefront chỉ tải khi khách thực sự điều hướng tới, giảm dung lượng
// bundle chính mà mọi khách phải tải khi chỉ ghé trang chủ.
const ProductDetail = lazy(() => import('./pages/ProductDetail'));
const Cart = lazy(() => import('./pages/Cart'));
const Collection = lazy(() => import('./pages/Collection'));
const Checkout = lazy(() => import('./pages/Checkout'));
const StoreLogin = lazy(() => import('./pages/Login')); // Đổi tên để tránh trùng
const Register = lazy(() => import('./pages/Register'));
const Profile = lazy(() => import('./pages/Profile'));
const Lookbook = lazy(() => import('./pages/Lookbook'));
const ReturnPolicy = lazy(() => import('./pages/policies/ReturnPolicy'));
const ShippingPolicy = lazy(() => import('./pages/policies/ShippingPolicy'));
const CareGuide = lazy(() => import('./pages/policies/CareGuide'));

// ==============================
// 2. IMPORTS CHO ADMIN
// ==============================
// [Code-split] Khách hàng ở storefront không bao giờ cần tải code admin (charts, xlsx,...)
// nên toàn bộ trang admin được lazy-load — chỉ tải khi có người thực sự vào /admin/*.
import useRealtimeOrder from './hooks/useRealtimeOrder';
import AdminRoute from './components/AdminRoute';
import AdminLoadingOverlay from './components/AdminLoadingOverlay';
const Sidebar = lazy(() => import('./components/Sidebar'));
const Header = lazy(() => import('./components/Header'));
const AdminLogin = lazy(() => import('./pages/admin/Login'));
const Dashboard = lazy(() => import('./pages/admin/Dashboard'));
const Products = lazy(() => import('./pages/admin/Products'));
const AdminOrders = lazy(() => import('./pages/admin/Orders'));
const Inventory = lazy(() => import('./pages/admin/Inventory'));
const Reports = lazy(() => import('./pages/admin/Reports'));
const Expenses = lazy(() => import('./pages/admin/Expenses'));
const AdminCustomers = lazy(() => import('./pages/admin/Customer'));
const Appearance = lazy(() => import('./pages/admin/Appearance'));
const Promotions = lazy(() => import('./pages/admin/Promotions'));
const CreateOrder = lazy(() => import('./pages/admin/CreateOrder'));
const DefectiveItems = lazy(() => import('./pages/admin/DefectiveItems'));

// --- Layout Wrapper cho Admin (Realtime & Sidebar) ---
const AdminLayoutWrapper = () => {
  useRealtimeOrder();
  const [isSidebarOpen, setIsSidebarOpen] = useState(false); // State quản lý menu

  return (
    <div className="flex min-h-screen bg-stone-50 text-stone-800 text-base font-sans">
      <AdminLoadingOverlay />
      {/* 1. OVERLAY ĐEN (Chỉ hiện trên mobile khi mở menu) */}
      {isSidebarOpen && (
        <div 
          onClick={() => setIsSidebarOpen(false)}
          className="fixed inset-0 bg-black/50 z-40 md:hidden"
        ></div>
      )}

      {/* 2. SIDEBAR (Ẩn hiện trên mobile, Cố định trên desktop) */}
      <aside className={`
        fixed top-0 left-0 z-50 h-full w-64 bg-white shadow-xl transition-transform duration-300 ease-in-out
        ${isSidebarOpen ? 'translate-x-0' : '-translate-x-full'} 
        md:translate-x-0
      `}>
        {/* Truyền hàm đóng menu vào Sidebar */}
        <Sidebar onClose={() => setIsSidebarOpen(false)} />
      </aside>

      {/* 3. NỘI DUNG CHÍNH */}
      <div className="flex-1 flex flex-col min-w-0 md:ml-64 transition-all duration-300">
        {/* Header chứa nút 3 gạch */}
        <Header toggleSidebar={() => setIsSidebarOpen(!isSidebarOpen)} />
        
        <main className="flex-1 p-4 md:p-8 mt-16 overflow-x-hidden">
          <Outlet /> 
        </main>
      </div>
    </div>
  );
};

// --- Layout Wrapper cho Storefront (Navbar & Footer) ---
const StorefrontLayout = () => {
  return (
    <div className="flex flex-col min-h-screen font-sans text-ink">
      <Preloader />
      <Navbar />
      <main className="flex-grow">
        <Outlet /> {/* Nơi hiển thị các trang con của Storefront */}
      </main>
      <Footer />
    </div>
  );
};

function App() {
  // THÊM ĐOẠN NÀY VÀO TRÊN CÙNG TRONG APP.JSX
  useEffect(() => {
    // Đổi số này mỗi khi bạn có đợt fix lỗi lớn (VD: từ 1.0 lên 1.1)
    const APP_VERSION = "1.1"; 
    const localVersion = localStorage.getItem("brown_app_version");

    if (localVersion !== APP_VERSION) {
      console.log("Phát hiện version cũ, đang dọn dẹp hệ thống...");
      
      // Quét sạch rác cũ
      localStorage.clear();
      
      // Cập nhật version mới
      localStorage.setItem("brown_app_version", APP_VERSION);
      
      // Ép tải lại trang để sạch bộ nhớ
      window.location.reload();
    }
  }, []);

  return (
    <BrowserRouter>
      <Suspense fallback={<div className="flex min-h-screen items-center justify-center text-stone-400">Đang tải...</div>}>
      <Routes>

        {/* =========================================
            KHU VỰC ADMIN (Bắt đầu bằng /admin)
           ========================================= */}
        
        {/* Login Admin: /admin/login */}
        <Route path="/admin/login" element={<AdminLogin />} />

        {/* Protected Admin Routes */}
        <Route path="/admin" element={<AdminRoute />}>
           <Route element={<AdminLayoutWrapper />}>
              <Route index element={<Dashboard />} /> {/* /admin */}
              <Route path="products" element={<Products />} />
              <Route path="orders" element={<AdminOrders />} />
              <Route path="customers" element={<AdminCustomers />} />
              <Route path="inventory" element={<Inventory />} />
              <Route path="promotions" element={<Promotions />} />
              <Route path="appearance" element={<Appearance />} />
              <Route path="reports" element={<Reports />} />
              <Route path="expenses" element={<Expenses />} />
              <Route path="inventory/defective" element={<DefectiveItems />} />
              <Route path="orders/create" element={<CreateOrder />} />
           </Route>
        </Route>


        {/* =========================================
            KHU VỰC STOREFRONT (Mặc định)
           ========================================= */}
        <Route path="/" element={<StorefrontLayout />}>
           <Route index element={<Home />} />
           <Route path="collection" element={<Collection />} />
           <Route path="lookbook" element={<Lookbook />} />
           <Route path="product/:slug" element={<ProductDetail />} />
           <Route path="cart" element={<Cart />} /> 
           <Route path="checkout" element={<Checkout />} />
           <Route path="login" element={<StoreLogin />} />
           <Route path="register" element={<Register />} />
           <Route path="account" element={<Profile />} />
           <Route path="policy/return" element={<ReturnPolicy />} />
           <Route path="policy/shipping" element={<ShippingPolicy />} />
           <Route path="policy/care" element={<CareGuide />} />
           {/* <Route path="/about" element={<About />} /> */}
           {/* Trang 404 cho Storefront (Tùy chọn) */}
           <Route path="*" element={<div className="p-20 text-center">404 - Page Not Found</div>} />
        </Route>

      </Routes>
      </Suspense>
    </BrowserRouter>
  );
}

export default App;
