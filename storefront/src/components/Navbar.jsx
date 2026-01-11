import { Link } from 'react-router-dom';
import { FaSearch, FaShoppingBag, FaUser } from 'react-icons/fa';
import { useCart } from '../context/CartContext'; // Import Context

const Navbar = () => {
  const { cartCount } = useCart(); // Lấy số lượng thực tế

  return (
    <nav className="sticky top-0 z-50 bg-white/80 backdrop-blur-md border-b border-stone-100">
      <div className="max-w-7xl mx-auto px-6 h-20 flex items-center justify-between">
        
        {/* 1. Logo */}
        <Link to="/" className="text-2xl font-bold tracking-[0.2em] text-stone-900">
          BROWN
        </Link>

        {/* 2. Menu chính */}
        <div className="hidden md:flex items-center gap-8 text-sm font-medium text-stone-500 uppercase tracking-wider">
          <Link to="/" className="hover:text-stone-900 transition-colors">Trang chủ</Link>
          <Link to="/collection" className="hover:text-stone-900 transition-colors">Sản phẩm</Link>
          <Link to="/about" className="hover:text-stone-900 transition-colors">Về chúng tôi</Link>
        </div>

        {/* 3. Icons bên phải */}
        <div className="flex items-center gap-6 text-stone-600">
          <FaSearch className="cursor-pointer hover:text-stone-900" />
          
          {/* --- GIỎ HÀNG (Chỉ 1 khối duy nhất ở đây) --- */}
          <Link to="/cart" className="relative group">
            <FaShoppingBag className="text-xl group-hover:text-stone-900" />
            {/* Logic hiện số lượng badge */}
            {cartCount > 0 && (
              <span className="absolute -top-2 -right-2 bg-stone-900 text-white text-[10px] w-4 h-4 rounded-full flex items-center justify-center">
                {cartCount}
              </span>
            )}
          </Link>
          {/* ------------------------------------------- */}

          <FaUser className="cursor-pointer hover:text-stone-900" />
        </div>
      </div>
    </nav>
  );
};

export default Navbar;