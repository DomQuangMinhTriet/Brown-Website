import { BrowserRouter, Routes, Route } from 'react-router-dom';
import Navbar from './components/Navbar';
import Home from './pages/Home';
import ProductDetail from './pages/ProductDetail'; 
import Cart from './pages/Cart';
import Collection from './pages/Collection';
import Checkout from './pages/Checkout';


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
        </Routes>
        
        {/* Footer đơn giản */}
        <footer className="bg-stone-900 text-stone-400 py-12 text-center text-sm">
          © 2026 BROWN FASHION. All rights reserved.
        </footer>
      </div>
    </BrowserRouter>
  );
}

export default App;