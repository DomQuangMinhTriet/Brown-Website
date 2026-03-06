import { useEffect, useState } from 'react';
import axios from 'axios';
import { Link, useSearchParams, useNavigate } from 'react-router-dom';
import { FaStore, FaShoppingCart } from 'react-icons/fa';
import { useCart } from '../context/CartContext'; 
import { useLanguage } from '../context/LanguageContext';
import { formatPrice } from '../utils/currencyHelper';

// [CHỈNH SỬA] Thêm hàm nén ảnh chống tràn RAM
const getOptimizedImageUrl = (url, width = 400) => {
    if (!url || typeof url !== 'string' || !url.includes('cloudinary.com')) return url;
    const uploadIndex = url.indexOf('upload/') + 7;
    const transformations = `c_scale,w_${width},f_auto,q_auto/`;
    return url.substring(0, uploadIndex) + transformations + url.substring(uploadIndex);
};

const Collection = () => {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const { cartCount, cartTotal } = useCart(); 
  const { t, lang } = useLanguage();
  const navigate = useNavigate();
  
  const [searchParams] = useSearchParams();
  const searchQuery = searchParams.get('search');
  const isPosMode = searchParams.get('pos') === 'true'; 
  const categorySlug = searchParams.get('category'); 

  const [pageTitle, setPageTitle] = useState(t('collection.all_products'));

  // [CHỈNH SỬA] Thêm state giới hạn số lượng sản phẩm hiển thị lúc đầu
  const [visibleCount, setVisibleCount] = useState(12);

  useEffect(() => {
    const fetchCategoryName = async () => {
        if (searchQuery) {
            setPageTitle(`${t('collection.search_result')}: "${searchQuery}"`);
        } else if (categorySlug) {
            try {
                const res = await axios.get(`${import.meta.env.VITE_API_URL}/api/categories`);
                if (res.data.success) {
                    const foundCat = res.data.data.find(c => c.slug === categorySlug);
                    setPageTitle(foundCat ? `${foundCat.name}` : `${categorySlug}`);
                }
            } catch (error) {
                console.error("Lỗi lấy tên danh mục:", error);
                // [CHỈNH SỬA] Fix lỗi catData is not defined trong bản gốc của bạn
                setPageTitle(categorySlug); 
            }
        } else {
            setPageTitle(t('collection.all_products'));
        }
    };

    fetchCategoryName();
  }, [categorySlug, searchQuery]); 

  useEffect(() => {
    const fetchProducts = async () => {
      setLoading(true);
      try {
        let url = `${import.meta.env.VITE_API_URL}/api/products?`;
        
        const params = [];
        if (searchQuery) params.push(`search=${encodeURIComponent(searchQuery)}`);
        if (categorySlug) params.push(`category=${encodeURIComponent(categorySlug)}`); 
        
        const res = await axios.get(url + params.join('&'));
        
        if (res.data.success) {
            setProducts(res.data.data);
        }
      } catch (error) { 
          console.error(error); 
          setProducts([]);
      } 
      finally { setLoading(false); }
    };
    fetchProducts();
    // [CHỈNH SỬA] Đặt lại số lượng hiển thị khi đổi danh mục
    setVisibleCount(12);
  }, [searchParams]); 

  return (
    <div className={isPosMode ? "bg-stone-100 min-h-screen pb-24" : ""}>
      
      {isPosMode && (
          <div className="bg-red-700 text-white p-4 shadow-md sticky top-20 z-40 flex justify-between items-center">
             <div className="font-bold text-lg flex items-center gap-2 uppercase">
                <FaStore/> {t('collection.pos_mode')}
             </div>
             <button onClick={() => window.close()} className="text-xs underline opacity-80 hover:opacity-100">
                {t('collection.exit')}
             </button>
          </div>
      )}

      <div className="max-w-7xl mx-auto px-6 py-8">
        <div className="text-center mb-10">
            <h2 className="text-3xl font-bold text-[#573425] mb-8 uppercase">
                {pageTitle}
            </h2>
        </div>

        {loading ? (
            <div className="text-center py-20">{t('collection.loading')}</div>
        ) : (
            <>
                <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-x-4 gap-y-8">
                {/* [CHỈNH SỬA] Dùng slice để không render thừa thẻ DOM */}
                {products.slice(0, visibleCount).map(product => (
                    <Link 
                        to={`/product/${product.slug}${isPosMode ? '?pos=true' : ''}`} 
                        key={product.id} 
                        className="group block text-center"
                    >
                        <div className="aspect-[3/4] overflow-hidden rounded-lg mb-3 relative">
                            <img 
                                // [CHỈNH SỬA] Nén ảnh Thumbnail
                                src={getOptimizedImageUrl(product.images?.[0], 400)} 
                                alt={product.name} 
                                className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                                loading="lazy"
                                decoding="async"
                            />
                            
                            {isPosMode && (
                                <div className="absolute inset-0 bg-black/10 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity">
                                    <span className="bg-white text-stone-900 px-3 py-1 text-xs font-bold rounded shadow">{t('collection.select')}</span>
                                </div>
                            )}
                        </div>

                        <h3 className="font-medium text-stone-900 text-sm truncate group-hover:text-stone-600 transition-colors">
                            {lang === 'en' && product.name_en ? product.name_en : product.name}
                        </h3>
                        <p className="text-stone-500 font-bold mt-1 text-sm">
                            {formatPrice(product.base_price, lang === 'en' ? 'USD' : 'VND')}
                        </p>
                    </Link>
                ))}
                </div>

                {/* [CHỈNH SỬA] Nút Tải Thêm */}
                {visibleCount < products.length && (
                    <div className="mt-12 text-center">
                        <button 
                            onClick={() => setVisibleCount(prev => prev + 12)}
                            className="bg-stone-900 text-white px-8 py-3 rounded-full font-bold text-sm uppercase tracking-wider hover:bg-stone-800 transition-colors"
                        >
                            Xem thêm sản phẩm
                        </button>
                    </div>
                )}
            </>
        )}
        
        {!loading && products.length === 0 && (
            <div className="text-center py-10 text-stone-500 italic">
                {t('collection.no_products')}
            </div>
        )}
      </div>

      {isPosMode && (
        <div className="fixed bottom-0 left-0 w-full bg-white border-t border-stone-200 p-4 shadow-[0_-5px_10px_rgba(0,0,0,0.1)] z-50 flex justify-between items-center">
            <div className="flex items-center gap-4">
                <div className="bg-stone-900 text-white w-12 h-12 rounded-full flex items-center justify-center text-xl relative">
                    <FaShoppingCart />
                    {cartCount > 0 && <span className="absolute -top-1 -right-1 bg-red-600 text-white text-xs w-5 h-5 rounded-full flex items-center justify-center border border-white">{cartCount}</span>}
                </div>
                <div>
                    <p className="text-xs text-stone-500 uppercase">{t('collection.subtotal')}</p>
                    <p className="text-xl font-bold text-stone-900">{formatPrice(cartTotal, lang === 'en' ? 'USD' : 'VND')}</p>
                </div>
            </div>
            
            <button 
                onClick={() => navigate('/checkout?pos=true')} 
                disabled={cartCount === 0}
                className="bg-red-600 hover:bg-red-700 text-white px-8 py-3 rounded font-bold uppercase tracking-widest disabled:bg-gray-300 transition-colors"
            >
                {t('collection.checkout')}
            </button>
        </div>
      )}
    </div>
  );
};

export default Collection;