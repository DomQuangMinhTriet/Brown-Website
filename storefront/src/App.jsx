import { BrowserRouter, Routes, Route } from 'react-router-dom';
import Navbar from './components/Navbar';
import Home from './pages/Home';
import ProductDetail from './pages/ProductDetail'; 
import Cart from './pages/Cart';
import Collection from './pages/Collection';
import Checkout from './pages/Checkout';
// --- IMPORT CÁC TRANG TÀI KHOẢN ---
import Login from './pages/Login';
import Register from './pages/Register';
import Profile from './pages/Profile'; // Trang này chúng ta tạo ở bước trước

function App() {
  return (
    <BrowserRouter>
      <div className="font-sans text-stone-800">
        <Navbar />
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/collection" element={<Collection />} />
          <Route path="/product/:slug" element={<ProductDetail />} />
          <Route path="/cart" element={<Cart />} /> 
          <Route path="/checkout" element={<Checkout />} />
          
          {/* --- CÁC ROUTE MỚI --- */}
          <Route path="/login" element={<Login />} />
          <Route path="/register" element={<Register />} />
          <Route path="/account" element={<Profile />} />
        </Routes>
        
        <footer className="bg-stone-900 text-stone-400 py-12 text-center text-sm">
          © 2026 BROWN FASHION. All rights reserved.
        </footer>
      </div>
    </BrowserRouter>
  );
}

export default App;