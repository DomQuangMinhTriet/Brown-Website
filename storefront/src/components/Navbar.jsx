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
            if(res.data.success) {
                const allCats = res.data.data;
                const visibleCats = allCats.filter(cat => cat.is_visible_on_home !== false);
                setCategories(visibleCats);
            }
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

  const navLink =
    'relative py-2 text-ink/70 transition-colors hover:text-cocoa ' +
    "after:absolute after:bottom-0 after:left-0 after:h-px after:w-0 after:bg-cocoa after:transition-all after:duration-300 hover:after:w-full";

  return (
    <>
      <nav className="sticky top-0 z-50 border-b border-sand/70 bg-cream/85 backdrop-blur-md">
        <div className="max-w-7xl mx-auto px-5 sm:px-6 lg:px-8 h-20 grid grid-cols-[auto_1fr_auto] items-center gap-3">

          {/* CỘT 1: Mobile Menu Button + Logo (luôn render để giữ đúng cột lưới) */}
          <div className="flex items-center gap-3">
            <button className="md:hidden text-cocoa focus:outline-none" onClick={() => setIsMobileMenuOpen(true)} aria-label="Mở menu">
              <FaBars className="text-xl" />
            </button>

            <Link to="/" className="font-sugo text-2xl md:text-3xl uppercase tracking-[0.1em] text-cocoa shrink-0">
              BROWN
            </Link>
          </div>

          {/* CỘT 2: Desktop Menu — căn giữa, ổn định khi đổi ngôn ngữ (Logo/Icon không bị kéo lệch) */}
          <div className="flex items-center justify-center">
            <div className="hidden md:flex items-center gap-5 lg:gap-8 text-xs tracking-wide whitespace-nowrap">
            <Link to="/" className={navLink}>{t('nav.home')}</Link>

            {/* Dropdown Menu Sản Phẩm */}
            <div
                className="relative group py-2"
                onMouseEnter={() => setIsProductMenuOpen(true)}
                onMouseLeave={() => setIsProductMenuOpen(false)}
            >
                <div className="flex items-center gap-1.5 cursor-pointer text-ink/70 transition-colors hover:text-cocoa">
                    <Link to="/collection">{t('nav.products')}</Link>
                    <FaChevronDown size={9} className={`transition-transform duration-300 ${isProductMenuOpen ? 'rotate-180' : ''}`} />
                </div>

                {/* Dropdown Content */}
                <div className={`absolute top-full left-1/2 -translate-x-1/2 w-52 overflow-hidden rounded-2xl border border-sand bg-surface shadow-[0_18px_50px_-20px_rgba(63,36,24,0.35)] transition-all duration-300 ${isProductMenuOpen ? 'opacity-100 visible translate-y-0' : 'opacity-0 invisible -translate-y-2'}`}>
                    <div className="flex flex-col py-1">
                        <Link to="/collection" className="px-5 py-3 text-left text-ink/70 transition-colors hover:bg-parchment hover:text-cocoa">
                            {t('collection.all_products')}
                        </Link>
                        {categories.map(cat => (
                            <Link
                                key={cat.id}
                                to={`/collection?category=${cat.slug}`}
                                className="px-5 py-3 text-left text-ink/70 transition-colors hover:bg-parchment hover:text-cocoa"
                            >
                                {cat.name}
                            </Link>
                        ))}
                    </div>
                </div>
            </div>

            <Link to="/lookbook" className={navLink}>LOOKBOOK</Link>
            <Link to="/policy/return" className={navLink}>{t('nav.return_policy')}</Link>
            <Link to="/policy/shipping" className={navLink}>{t('nav.shipping_policy')}</Link>
            <Link to="/policy/care" className={navLink}>{t('nav.care_guide')}</Link>
            </div>
          </div>

          {/* CỘT 3: Icons */}
          <div className="flex items-center justify-end gap-5 text-cocoa">
            {/* Lang Switcher */}
            <button onClick={toggleLang} className="flex items-center gap-1 text-xs font-semibold uppercase transition-colors hover:text-clay" aria-label="Đổi ngôn ngữ">
                <FaGlobe /> {lang}
            </button>

            <button onClick={() => setShowSearch(!showSearch)} className="transition-colors hover:text-clay" aria-label="Tìm kiếm">
                <FaSearch className="text-lg" />
            </button>

            <Link to="/cart" className="relative transition-colors hover:text-clay" aria-label="Giỏ hàng">
              <FaShoppingBag className="text-xl" />
              {cartCount > 0 && (
                <span className="absolute -top-2 -right-2 flex h-4 w-4 items-center justify-center rounded-full bg-clay text-[10px] text-cream">
                  {cartCount}
                </span>
              )}
            </Link>

            <div className="hidden md:block">
                <Link to={user ? "/account" : "/login"} aria-label="Tài khoản">
                    <FaUser className={`text-xl transition-colors hover:text-clay ${user ? 'text-cocoa' : 'text-cocoa/60'}`} />
                </Link>
            </div>
          </div>
        </div>

        {/* Search Bar Overlay */}
        {showSearch && (
            <div className="absolute top-full left-0 w-full animate-fade-in border-b border-sand bg-cream p-4 shadow-[0_18px_40px_-24px_rgba(63,36,24,0.4)]">
                <form onSubmit={handleSearch} className="mx-auto flex max-w-3xl items-center border-b border-cocoa/30 pb-2">
                    <FaSearch className="mr-3 text-muted" />
                    <input
                        type="text"
                        placeholder={t('nav.search_placeholder')}
                        className="w-full bg-transparent py-2 font-heading text-lg text-espresso outline-none placeholder:text-muted/60"
                        value={keyword}
                        onChange={(e) => setKeyword(e.target.value)}
                        autoFocus
                    />
                    <button type="button" onClick={() => setShowSearch(false)} className="ml-4 text-muted transition-colors hover:text-cocoa">
                        <FaTimes size={24} />
                    </button>
                </form>
            </div>
        )}
      </nav>

      {/* MOBILE MENU */}
      {isMobileMenuOpen && (
        <div className="fixed inset-0 z-[60] flex">
            <div className="absolute inset-0 bg-espresso/60 backdrop-blur-sm" onClick={() => setIsMobileMenuOpen(false)}></div>

            <div className="relative flex h-full w-[85%] max-w-sm flex-col bg-cream shadow-2xl">
                {/* Header Mobile Menu */}
                <div className="flex items-center justify-between border-b border-sand p-6">
                    <span className="font-sugo text-2xl uppercase tracking-[0.1em] text-cocoa">BROWN</span>
                    <button onClick={() => setIsMobileMenuOpen(false)} className="text-muted transition-colors hover:text-clay" aria-label="Đóng menu">
                        <FaTimes size={24} />
                    </button>
                </div>

                <div className="flex flex-1 flex-col gap-1 overflow-y-auto p-6">
                    <Link to="/" onClick={() => setIsMobileMenuOpen(false)} className="border-b border-sand py-3 font-heading text-lg text-espresso">
                        {t('nav.home')}
                    </Link>

                    {/* Accordion cho Sản phẩm trên Mobile */}
                    <div className="border-b border-sand py-3">
                        <p className="mb-2 font-heading text-lg text-espresso">{t('nav.products')}</p>
                        <div className="flex flex-col gap-2 border-l border-cocoa/25 pl-4">
                             <Link to="/collection" onClick={() => setIsMobileMenuOpen(false)} className="py-1 text-ink/70">{t('collection.all_products')}</Link>
                             {categories.map(cat => (
                                <Link
                                    key={cat.id}
                                    to={`/collection?category=${cat.slug}`}
                                    onClick={() => setIsMobileMenuOpen(false)}
                                    className="py-1 text-ink/70"
                                >
                                    {cat.name}
                                </Link>
                             ))}
                        </div>
                    </div>

                    <Link to="/lookbook" onClick={() => setIsMobileMenuOpen(false)} className="border-b border-sand py-3 font-heading text-lg text-espresso">
                        Lookbook
                    </Link>
                    <Link to="/policy/return" onClick={() => setIsMobileMenuOpen(false)} className="border-b border-sand py-3 font-heading text-lg text-espresso">
                        {t('nav.return_policy')}
                    </Link>
                    <Link to="/policy/shipping" onClick={() => setIsMobileMenuOpen(false)} className="border-b border-sand py-3 font-heading text-lg text-espresso">
                        {t('nav.shipping_policy')}
                    </Link>
                    <Link to="/policy/care" onClick={() => setIsMobileMenuOpen(false)} className="border-b border-sand py-3 font-heading text-lg text-espresso">
                        {t('nav.care_guide')}
                    </Link>
                </div>

                {/* Footer Mobile Menu */}
                <div className="border-t border-sand p-6">
                    {user ? (
                        <div className="space-y-3">
                             <Link to="/account" onClick={() => setIsMobileMenuOpen(false)} className="flex items-center gap-3 font-medium text-espresso">
                                <FaUser /> {t('nav.account')}
                            </Link>
                            <button onClick={handleLogout} className="w-full text-left text-sm font-medium text-clay">
                                {t('nav.logout')}
                            </button>
                        </div>
                    ) : (
                        <Link to="/login" onClick={() => setIsMobileMenuOpen(false)} className="flex items-center gap-3 font-medium text-espresso">
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
