import { useEffect, useState } from 'react';
import axios from 'axios';
import { Link } from 'react-router-dom';
import { FaArrowRight } from 'react-icons/fa';
import { formatPrice } from '../utils/currencyHelper';
import SEO from '../components/SEO';
import { useLanguage } from '../context/LanguageContext'; // Đa ngôn ngữ

const Home = () => {
  const { t, lang } = useLanguage();
  const [products, setProducts] = useState([]);
  const [banners, setBanners] = useState([]);
  const [loading, setLoading] = useState(true);
  const [currentBanner, setCurrentBanner] = useState(0);
  useEffect(() => {
    const fetchData = async () => {
      try {
        const [prodRes, banRes] = await Promise.all([
            axios.get(`${import.meta.env.VITE_API_URL}/api/products`),
            axios.get(`${import.meta.env.VITE_API_URL}/api/content/banners`)
        ]);
        if (prodRes.data.success) setProducts(prodRes.data.data);
        if (banRes.data.success) setBanners(banRes.data.data);
      } catch (err) { console.error(err); } 
      finally { setLoading(false); }
    };
    fetchData();
  }, []);
  // 4. useEffect MỚI (Thêm vào ngay bên dưới - Để tự động chuyển)
  useEffect(() => {
    if (banners.length <= 1) return; // Chỉ chạy nếu có nhiều hơn 1 banner

    const interval = setInterval(() => {
        setCurrentBanner(prev => (prev === banners.length - 1 ? 0 : prev + 1));
    }, 5000); // 5 giây đổi 1 lần

    return () => clearInterval(interval);
  }, [banners]); // Chạy lại mỗi khi danh sách banners thay đổi
  // Logic kiểm tra xem URL là ảnh hay video
  const isVideo = (url) => {
    return url.match(/\.(mp4|webm|ogg)$/i);
  };

  return (
    <>
      <SEO title={t('home.title')} />
      
      {/* 1. HERO BANNER - CLICKABLE & FIXED RATIO */}
        {/* aspect-[3/1]: Tỷ lệ chuẩn cho banner ngang (VD: 1920x640px) */}
        <div className="relative w-full aspect-[3/1] bg-stone-200 overflow-hidden group">
            
            {loading ? (
                <div className="absolute inset-0 flex items-center justify-center text-stone-400 animate-pulse">LOADING...</div>
            ) : banners.length > 0 ? (
                banners.map((banner, index) => (
                    <Link 
                        to={banner.link_to || "/collection"} 
                        key={banner.id}
                        // Thay thẻ div bằng Link để click được toàn bộ banner
                        className={`absolute inset-0 block w-full h-full transition-opacity duration-1000 ease-in-out
                            ${index === currentBanner ? 'opacity-100 z-10' : 'opacity-0 z-0'}
                        `}
                    >
                        {isVideo(banner.image_url) ? (
                            <video 
                                autoPlay loop muted playsInline 
                                className="w-full h-full object-cover" // object-cover giúp lấp đầy khung aspect-ratio
                            >
                                <source src={banner.image_url} type="video/mp4" />
                            </video>
                        ) : (
                            <img 
                                src={banner.image_url} 
                                alt={banner.title} 
                                className="w-full h-full object-cover" 
                            />
                        )}
                        
                        {/* Đã xóa phần Text Overlay và Button ở đây */}
                    </Link>
                ))
            ) : (
                <div className="w-full h-full bg-[#292524]"></div>
            )}

            {/* NÚT CHẤM TRÒN ĐIỀU HƯỚNG (Giữ lại để khách biết có nhiều banner) */}
            {!loading && banners.length > 1 && (
                <div className="absolute bottom-4 left-1/2 -translate-x-1/2 z-20 flex gap-2">
                    {banners.map((_, idx) => (
                        <button 
                            key={idx} 
                            onClick={(e) => {
                                e.preventDefault(); // Ngăn click nhầm vào Link banner
                                setCurrentBanner(idx);
                            }}
                            className={`h-1.5 rounded-full transition-all duration-500 shadow-sm
                                ${idx === currentBanner ? 'bg-white w-8' : 'bg-white/60 w-2 hover:bg-white'}
                            `}
                        />
                    ))}
                </div>
            )}


        {/* Overlay Text */}
        <div className="absolute inset-0 bg-black/20 flex flex-col items-center justify-center text-center p-4">
            <h2 className="text-white text-4xl md:text-6xl font-serif font-bold tracking-widest mb-6 drop-shadow-lg">
                {banners[0]?.title || 'BROWN'}
            </h2>
            <Link to={banners[0]?.link_to || "/collection"} 
                className="bg-white text-stone-900 px-8 py-3 uppercase font-bold tracking-[0.2em] hover:bg-stone-900 hover:text-white transition-all duration-300">
                {t('home.hero_btn')}
            </Link>
        </div>
      </div>

      {/* 2. SẢN PHẨM MỚI */}
      <section className="max-w-7xl mx-auto px-6 py-20">
         <div className="text-center mb-12">
            <h3 className="text-2xl md:text-3xl font-serif font-bold text-[#292524] mb-2">{t('home.new_arrival')}</h3>
            <div className="w-16 h-1 bg-stone-900 mx-auto"></div>
         </div>

        <div className="grid grid-cols-2 md:grid-cols-4 gap-x-6 gap-y-10">
            {products.slice(0, 8).map(product => (
                <Link 
                    key={product.id} 
                    to={`/product/${product.slug}`} 
                    className="group block text-center"
                >
                    <div className="relative overflow-hidden mb-4 bg-stone-100 aspect-[3/4]">
                        <img 
                            src={product.images?.[0]} 
                            alt={product.name} 
                            className="w-full h-full object-cover object-center transition-transform duration-700 group-hover:scale-105"
                            // [THÊM] Lazy load
                            loading="lazy"
                            decoding="async"
                        />
                    {/* Nút xem nhanh (Desktop only) */}
                    <div className="absolute bottom-0 left-0 w-full bg-white/90 text-center py-3 translate-y-full group-hover:translate-y-0 transition-transform duration-300 hidden md:block">
                        <span className="text-xs font-bold uppercase tracking-wider text-stone-900">{t('home.view_detail')}</span>
                    </div>
                  </div>
                  
                  {/* Tên sản phẩm */}
                    <h3 className="text-stone-900 font-medium text-sm group-hover:text-stone-600 transition-colors truncate px-1">
                        {lang === 'en' && product.name_en ? product.name_en : product.name}
                    </h3>
                    
                    {/* Giá tiền */}
                    <p className="text-stone-500 mt-1 font-bold text-sm px-1">
                        {formatPrice(product.base_price, lang === 'en' ? 'USD' : 'VND')}
                    </p>
                </Link>
            ))}
         </div>
         
         <div className="text-center mt-16">
            <Link to="/collection" className="inline-block border border-stone-900 px-10 py-3 text-stone-900 font-bold uppercase tracking-widest hover:bg-stone-900 hover:text-white transition-all text-sm">
                {t('home.view_all')}
            </Link>
         </div>
      </section>
    </>
  );
};

export default Home;