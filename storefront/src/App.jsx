
import { useState } from 'react';
import { BrowserRouter, Routes, Route, Outlet } from 'react-router-dom';

// ==============================
// 1. IMPORTS CHO STOREFRONT
// ==============================
import Navbar from './components/Navbar';
import Home from './pages/Home';
import ProductDetail from './pages/ProductDetail'; 
import Cart from './pages/Cart';
import Collection from './pages/Collection';
import Checkout from './pages/Checkout';
import StoreLogin from './pages/Login'; // Đổi tên để tránh trùng
import Register from './pages/Register';
import Profile from './pages/Profile';
import ReturnPolicy from './pages/policies/ReturnPolicy';
import ShippingPolicy from './pages/policies/ShippingPolicy';
import { useLanguage } from './context/LanguageContext';
//import About from './pages/About';

// ==============================
// 2. IMPORTS CHO ADMIN
// ==============================
// Lưu ý: Tôi giả định bạn đã chuyển các file Admin vào thư mục pages/admin/ hoặc đổi tên file
// Nếu chưa, hãy sửa đường dẫn bên dưới cho đúng file của bạn
import useRealtimeOrder from './hooks/useRealtimeOrder';
import Sidebar from './components/Sidebar';
import Header from './components/Header';
import AdminRoute from './components/AdminRoute';
import AdminLogin from './pages/admin/Login'; // Hoặc './pages/LoginAdmin'
import Dashboard from './pages/admin/Dashboard';
import Products from './pages/admin/Products';
import AdminOrders from './pages/admin/Orders'; // Đổi tên để tránh nhầm lẫn
import Inventory from './pages/admin/Inventory';
import Reports from './pages/admin/Reports';
import Expenses from './pages/admin/Expenses';
import AdminCustomers from './pages/admin/Customer';
import Appearance from './pages/admin/Appearance';
import Promotions from './pages/admin/Promotions';
import CreateOrder from './pages/admin/CreateOrder';

// --- Layout Wrapper cho Admin (Realtime & Sidebar) ---
const AdminLayoutWrapper = () => {
  useRealtimeOrder();
  const [isSidebarOpen, setIsSidebarOpen] = useState(false); // State quản lý menu

  return (
    <div className="flex min-h-screen bg-stone-50 text-stone-800 text-base font-sans">
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
  const { t } = useLanguage();
  return (
    <div className="flex flex-col min-h-screen font-sans text-stone-800">
      <Navbar />
      <main className="flex-grow">
        <Outlet /> {/* Nơi hiển thị các trang con của Storefront */}
      </main>
      
      {/* Footer */}
      <footer className="bg-[#573425] text-[#f5f5f4] py-12 border-t-4 border-stone-800">
          <div className="max-w-7xl mx-auto px-6 grid grid-cols-1 md:grid-cols-3 gap-8 text-sm">
             <div>
                <h3 className="font-serif text-lg font-bold mb-4 uppercase tracking-widest">{t('footer.about')}</h3>
                <p className="text-stone-400 leading-relaxed">{t('footer.desc')}</p>
             </div>
             <div>
                <h3 className="font-serif text-lg font-bold mb-4 uppercase tracking-widest">{t('footer.contact')}</h3>
                <p className="text-stone-400">Hotline: 090.695.4860</p>
                <p className="text-stone-400">Email: brownvn25@gmail.com</p>
                <p className="text-stone-400">Add: Ho Chi Minh City, Vietnam</p>
             </div>
             <div>
                <h3 className="font-serif text-lg font-bold mb-4 uppercase tracking-widest">{t('footer.follow')}</h3>
                <div className="flex gap-4">
                   <a href="https://instagram.com/brown.vn" target="_blank" rel="noopener noreferrer" className="text-stone-400 hover:text-white transition">Instagram</a>                   
                </div>
             </div>
          </div>
          <div className="text-center mt-12 text-[#f5f5f4] text-xs">
             © 2026 {t('footer.rights')}
          </div>
       </footer>
    </div>
  );
};

function App() {
  return (
    <BrowserRouter>
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
              <Route path="orders/create" element={<CreateOrder />} />
           </Route>
        </Route>


        {/* =========================================
            KHU VỰC STOREFRONT (Mặc định)
           ========================================= */}
        <Route path="/" element={<StorefrontLayout />}>
           <Route index element={<Home />} />
           <Route path="collection" element={<Collection />} />
           <Route path="product/:slug" element={<ProductDetail />} />
           <Route path="cart" element={<Cart />} /> 
           <Route path="checkout" element={<Checkout />} />
           <Route path="login" element={<StoreLogin />} />
           <Route path="register" element={<Register />} />
           <Route path="account" element={<Profile />} />
           <Route path="policy/return" element={<ReturnPolicy />} />
           <Route path="policy/shipping" element={<ShippingPolicy />} />
           {/* <Route path="/about" element={<About />} /> */}
           {/* Trang 404 cho Storefront (Tùy chọn) */}
           <Route path="*" element={<div className="p-20 text-center">404 - Page Not Found</div>} />
        </Route>

      </Routes>
    </BrowserRouter>
  );
}

export default App;