import { BrowserRouter, Routes, Route } from 'react-router-dom';
import Navbar from './components/Navbar';
import Home from './pages/Home';
import ProductDetail from './pages/ProductDetail'; 
import Cart from './pages/Cart';
import Collection from './pages/Collection';
import Checkout from './pages/Checkout';
import Login from './pages/Login';
import Register from './pages/Register';
import Profile from './pages/Profile';

// Import Context Ngôn ngữ
import { useLanguage } from './context/LanguageContext';

function AppContent() {
  const { t } = useLanguage();

  return (
    <BrowserRouter>
      {/* Wrapper chính: Flex Column để đẩy Footer */}
      <div className="flex flex-col min-h-screen font-sans text-stone-800">
        
        <Navbar />
        
        {/* Phần nội dung chính sẽ giãn ra (flex-grow) */}
        <main className="flex-grow">
          <Routes>
            <Route path="/" element={<Home />} />
            <Route path="/collection" element={<Collection />} />
            <Route path="/product/:slug" element={<ProductDetail />} />
            <Route path="/cart" element={<Cart />} /> 
            <Route path="/checkout" element={<Checkout />} />
            <Route path="/login" element={<Login />} />
            <Route path="/register" element={<Register />} />
            <Route path="/account" element={<Profile />} />
          </Routes>
        </main>
        
        {/* Footer luôn nằm đáy */}
        <footer className="bg-[#292524] text-[#f5f5f4] py-12 border-t-4 border-stone-800">
          <div className="max-w-7xl mx-auto px-6 grid grid-cols-1 md:grid-cols-3 gap-8 text-sm">
             <div>
                <h3 className="font-serif text-lg font-bold mb-4 uppercase tracking-widest">{t('footer.about')}</h3>
                <p className="text-stone-400 leading-relaxed">{t('footer.desc')}</p>
             </div>
             <div>
                <h3 className="font-serif text-lg font-bold mb-4 uppercase tracking-widest">{t('footer.contact')}</h3>
                <p className="text-stone-400">Hotline: 0902.173.763</p>
                <p className="text-stone-400">Email: brownvn25@gmail.com</p>
                <p className="text-stone-400">Add: Ho Chi Minh City, Vietnam</p>
             </div>
             <div>
                <h3 className="font-serif text-lg font-bold mb-4 uppercase tracking-widest">{t('footer.follow')}</h3>
                <div className="flex gap-4">
                   <a href="#" className="text-stone-400 hover:text-white transition">Facebook</a>
                   <a href="#" className="text-stone-400 hover:text-white transition">Instagram</a>
                   <a href="#" className="text-stone-400 hover:text-white transition">Tiktok</a>
                </div>
             </div>
          </div>
          <div className="text-center mt-12 text-stone-600 text-xs">
             © 2026 {t('footer.rights')}
          </div>
        </footer>
      </div>
    </BrowserRouter>
  );
}

// App Wrapper để bọc Context
export default AppContent;