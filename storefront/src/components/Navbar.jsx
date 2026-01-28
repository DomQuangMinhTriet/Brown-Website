import { useState, useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { FaSearch, FaShoppingBag, FaUser, FaBars, FaTimes, FaGlobe, FaChevronDown } from 'react-icons/fa';
import { useCart } from '../context/CartContext';
import { useAuth } from '../context/AuthContext';
import { useLanguage } from '../context/LanguageContext';
import axios from 'axios';

const Navbar = () => {
  const { cartCount } = useCart();
  const { user, logout } = useAuth();
  const { t, lang, toggleLang } = useLanguage();
  
  const [showSearch, setShowSearch] = useState(false);
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);
  const [keyword, setKeyword] = useState('');
  const [categories, setCategories] = useState([]);
  
  // State cho dropdown Menu (Sản phẩm)
  const [isProductMenuOpen, setIsProductMenuOpen] = useState(false);

  const navigate = useNavigate();

  // Lấy danh mục từ API để hiển thị trên Menu
  useEffect(() => {
    const fetchCats = async () => {
        try {
            const res = await axios.get(`${import.meta.env.VITE_API_URL}/api/categories`);
            if(res.data.success) setCategories(res.data.data);
        } catch(e) { console.error(e); }
    };
    fetchCats();
  }, []);

  const handleSearch = (e) => {
    e.preventDefault();
    if (keyword.trim()) {
      setShowSearch(false);
      navigate(`/collection?search=${encodeURIComponent(keyword.trim())}`);
      setKeyword('');
    }
  };

  const handleLogout = async () => {
      await logout();
      setIsMobileMenuOpen(false);
      navigate('/');
  };

  return (
    <>
      <nav className="sticky top-0 z-50 bg-white/95 backdrop-blur-md border-b border-stone-100 shadow-sm transition-all duration-300">
        <div className="max-w-7xl mx-auto px-6 h-20 flex items-center justify-between">
          
          {/* Mobile Menu Button */}
          <button className="md:hidden text-stone-800 focus:outline-none" onClick={() => setIsMobileMenuOpen(true)}>
            <FaBars className="text-xl" />
          </button>

          {/* Logo */}
          <Link to="/" className="text-2xl md:text-3xl font-bold tracking-widest uppercase font-sugo text-[#573425]">
            BROWN
          </Link>

          {/* Desktop Menu */}
          <div className="hidden md:flex gap-10 text-sm font-medium tracking-wide text-stone-600">
            <Link to="/" className="hover:text-stone-900 transition-colors py-2 border-b-2 border-transparent hover:border-stone-900">
                {t('nav.home')}
            </Link>
            
            {/* Dropdown Menu Sản Phẩm */}
            <div 
                className="relative group py-2 cursor-pointer"
                onMouseEnter={() => setIsProductMenuOpen(true)}
                onMouseLeave={() => setIsProductMenuOpen(false)}
            >
                <div className="flex items-center gap-1 hover:text-stone-900 transition-colors border-b-2 border-transparent hover:border-stone-900">
                    <Link to="/collection">{t('nav.products')}</Link>
                    <FaChevronDown size={10} />
                </div>

                {/* Dropdown Content */}
                <div className={`absolute top-full left-1/2 -translate-x-1/2 w-48 bg-white shadow-xl rounded-b-lg overflow-hidden border-t-2 border-stone-900 transition-all duration-300 ${isProductMenuOpen ? 'opacity-100 visible translate-y-0' : 'opacity-0 invisible -translate-y-2'}`}>
                    <div className="flex flex-col">
                        <Link to="/collection" className="px-4 py-3 hover:bg-stone-50 text-stone-600 hover:text-stone-900 text-left border-b border-stone-100 last:border-0">
                            Tất cả sản phẩm
                        </Link>
                        {categories.map(cat => (
                            <Link 
                                key={cat.id} 
                                to={`/collection?category=${cat.slug}`} // Hoặc filter theo category_id
                                className="px-4 py-3 hover:bg-stone-50 text-stone-600 hover:text-stone-900 text-left border-b border-stone-100 last:border-0"
                            >
                                {cat.name}
                            </Link>
                        ))}
                    </div>
                </div>
            </div>

            <Link to="/policy/return" className="hover:text-stone-900 transition-colors py-2 border-b-2 border-transparent hover:border-stone-900">
                CHÍNH SÁCH ĐỔI TRẢ
            </Link>

            <Link to="/policy/shipping" className="hover:text-stone-900 transition-colors py-2 border-b-2 border-transparent hover:border-stone-900">
                CHÍNH SÁCH VẬN CHUYỂN
            </Link>

            {/* <Link to="/about" className="hover:text-stone-900 transition-colors py-2 border-b-2 border-transparent hover:border-stone-900">
                {t('nav.about')}
            </Link> */}
          </div>

          {/* Icons Right */}
          <div className="flex items-center gap-5 text-stone-600">
            {/* Lang Switcher */}
            <button onClick={toggleLang} className="flex items-center gap-1 text-xs font-bold hover:text-stone-900 uppercase">
                <FaGlobe /> {lang}
            </button>

            <button onClick={() => setShowSearch(!showSearch)} className="hover:text-stone-900">
                <FaSearch className="text-lg" />
            </button>
            
            <Link to="/cart" className="relative group hover:text-stone-900">
              <FaShoppingBag className="text-xl" />
              {cartCount > 0 && (
                <span className="absolute -top-2 -right-2 bg-[#292524] text-white text-[10px] w-4 h-4 rounded-full flex items-center justify-center">
                  {cartCount}
                </span>
              )}
            </Link>

            <div className="hidden md:block">
                <Link to={user ? "/account" : "/login"}>
                    <FaUser className={`text-xl hover:text-stone-900 ${user ? 'text-stone-900' : ''}`} />
                </Link>
            </div>
          </div>
        </div>

        {/* Search Bar Overlay */}
        {showSearch && (
            <div className="absolute top-full left-0 w-full bg-white border-b border-stone-100 p-4 animate-fade-in shadow-lg">
                <form onSubmit={handleSearch} className="max-w-3xl mx-auto flex items-center border-b border-stone-300 pb-2">
                    <FaSearch className="text-stone-400 mr-3" />
                    <input 
                        type="text" 
                        placeholder={t('nav.search_placeholder')}
                        className="w-full outline-none text-stone-800 placeholder:text-stone-300 py-2 text-lg font-serif"
                        value={keyword}
                        onChange={(e) => setKeyword(e.target.value)}
                        autoFocus
                    />
                    <button type="button" onClick={() => setShowSearch(false)} className="ml-4 text-stone-400 hover:text-stone-900">
                        <FaTimes size={24} />
                    </button>
                </form>
            </div>
        )}
      </nav>

      {/* MOBILE MENU (Nâng cấp) */}
      {isMobileMenuOpen && (
        <div className="fixed inset-0 z-[60] flex">
            <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" onClick={() => setIsMobileMenuOpen(false)}></div>
            
            <div className="relative bg-[#f5f5f4] w-[85%] max-w-sm h-full shadow-2xl flex flex-col transform transition-transform duration-300">
                {/* Header Mobile Menu */}
                <div className="p-6 flex justify-between items-center border-b border-stone-200 bg-white">
                    <span className="text-2xl font-serif font-bold text-[#292524]">BROWN</span>
                    <button onClick={() => setIsMobileMenuOpen(false)} className="text-stone-500 hover:text-red-500">
                        <FaTimes size={24} />
                    </button>
                </div>

                <div className="flex-1 overflow-y-auto p-6 flex flex-col gap-2">
                    <Link to="/" onClick={() => setIsMobileMenuOpen(false)} className="text-lg font-bold text-stone-800 py-2 border-b border-stone-200">
                        {t('nav.home')}
                    </Link>
                    
                    {/* Accordion cho Sản phẩm trên Mobile */}
                    <div className="py-2 border-b border-stone-200">
                        <p className="text-lg font-bold text-stone-800 mb-2">{t('nav.products')}</p>
                        <div className="pl-4 flex flex-col gap-2 border-l-2 border-stone-300">
                             <Link to="/collection" onClick={() => setIsMobileMenuOpen(false)} className="text-stone-600 py-1">Tất cả sản phẩm</Link>
                             {categories.map(cat => (
                                <Link 
                                    key={cat.id} 
                                    to={`/collection?search=${cat.slug}`}
                                    onClick={() => setIsMobileMenuOpen(false)} 
                                    className="text-stone-600 py-1"
                                >
                                    {cat.name}
                                </Link>
                             ))}
                        </div>
                    </div>

                    <Link to="/about" onClick={() => setIsMobileMenuOpen(false)} className="text-lg font-bold text-stone-800 py-2 border-b border-stone-200">
                        {t('nav.about')}
                    </Link>
                </div>

                {/* Footer Mobile Menu */}
                <div className="p-6 bg-white border-t border-stone-200">
                    {user ? (
                        <div className="space-y-3">
                             <Link to="/account" onClick={() => setIsMobileMenuOpen(false)} className="flex items-center gap-3 text-stone-800 font-bold">
                                <FaUser /> {t('nav.account')}
                            </Link>
                            <button onClick={handleLogout} className="text-red-600 text-sm font-medium w-full text-left">
                                {t('nav.logout')}
                            </button>
                        </div>
                    ) : (
                        <Link to="/login" onClick={() => setIsMobileMenuOpen(false)} className="flex items-center gap-3 text-stone-800 font-bold">
                            <FaUser /> {t('nav.login')}
                        </Link>
                    )}
                </div>
            </div>
        </div>
      )}
    </>
  );
};

export default Navbar;