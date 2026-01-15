import { useState } from 'react'; // Thêm useState
import { Link, useNavigate } from 'react-router-dom'; // Thêm useNavigate
import { FaSearch, FaShoppingBag, FaUser, FaTimes } from 'react-icons/fa'; // Thêm FaTimes
import { useCart } from '../context/CartContext';
import { useAuth } from '../context/AuthContext';

const Navbar = () => {
  const { cartCount } = useCart();
  const { user } = useAuth();
  
  // State xử lý tìm kiếm
  const [showSearch, setShowSearch] = useState(false);
  const [keyword, setKeyword] = useState('');
  const navigate = useNavigate();

  const handleSearch = (e) => {
    e.preventDefault(); // Chặn reload trang
    if (keyword.trim()) {
      setShowSearch(false); // Đóng thanh search
      navigate(`/collection?search=${keyword.trim()}`); // Chuyển hướng
      setKeyword(''); // Reset ô nhập
    }
  };

  return (
    <>
      <nav className="sticky top-0 z-50 bg-white/80 backdrop-blur-md border-b border-stone-100">
        <div className="max-w-7xl mx-auto px-6 h-20 flex items-center justify-between">
          
          {/* 1. Logo */}
          <Link to="/" className="text-2xl font-bold tracking-[0.2em] text-stone-900 z-50">
            BROWN
          </Link>

          {/* 2. Menu chính (Ẩn khi bật search) */}
          {!showSearch && (
            <div className="hidden md:flex items-center gap-8 text-sm font-medium text-stone-500 uppercase tracking-wider">
              <Link to="/" className="hover:text-stone-900 transition-colors">Trang chủ</Link>
              <Link to="/collection" className="hover:text-stone-900 transition-colors">Sản phẩm</Link>
              <Link to="/about" className="hover:text-stone-900 transition-colors">Về chúng tôi</Link>
            </div>
          )}

          {/* 3. INPUT TÌM KIẾM (Hiện khi bấm icon) */}
          <div className={`absolute left-0 w-full px-6 transition-all duration-300 ${showSearch ? 'top-20 opacity-100 visible' : 'top-16 opacity-0 invisible pointer-events-none'} md:static md:w-auto md:visible md:opacity-100 md:pointer-events-auto`}>
             {/* Logic: Trên mobile thì hiện dưới navbar, trên Desktop thì hiện đè hoặc xử lý linh hoạt. 
                 Ở đây mình làm kiểu đơn giản: Khi bấm icon search thì hiện ô input đè lên menu giữa */}
             
             {showSearch && (
                 <form onSubmit={handleSearch} className="absolute inset-0 bg-white flex items-center justify-center px-20 h-20 top-0 left-0 w-full z-40">
                    <input 
                        autoFocus
                        type="text" 
                        placeholder="Tìm kiếm sản phẩm..." 
                        className="w-full max-w-2xl text-xl border-b-2 border-stone-200 py-2 outline-none text-stone-800 placeholder:text-stone-300"
                        value={keyword}
                        onChange={(e) => setKeyword(e.target.value)}
                    />
                    <button type="button" onClick={() => setShowSearch(false)} className="ml-4 text-stone-400 hover:text-stone-900">
                        <FaTimes size={24} />
                    </button>
                 </form>
             )}
          </div>

          {/* 4. Icons bên phải */}
          <div className="flex items-center gap-6 text-stone-600 z-50">
            {/* Nút Search Toggle */}
            <button onClick={() => setShowSearch(!showSearch)} className="hover:text-stone-900 focus:outline-none">
                <FaSearch className="text-lg" />
            </button>
            
            <Link to="/cart" className="relative group">
              <FaShoppingBag className="text-xl group-hover:text-stone-900" />
              {cartCount > 0 && (
                <span className="absolute -top-2 -right-2 bg-stone-900 text-white text-[10px] w-4 h-4 rounded-full flex items-center justify-center">
                  {cartCount}
                </span>
              )}
            </Link>

            <Link to={user ? "/account" : "/login"}>
              <FaUser className={`text-xl cursor-pointer hover:text-stone-900 ${user ? 'text-green-600' : ''}`} />
            </Link>
          </div>
        </div>
      </nav>
    </>
  );
};

export default Navbar;