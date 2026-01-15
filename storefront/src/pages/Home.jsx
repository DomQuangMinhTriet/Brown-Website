import { useEffect, useState } from 'react';
import axios from 'axios';
import { Link } from 'react-router-dom';
<<<<<<< Updated upstream

const Home = () => {
  const [products, setProducts] = useState([]);

  useEffect(() => {
    // Gọi API lấy sản phẩm từ Backend
=======
import { FaArrowRight } from 'react-icons/fa';
import SEO from '../components/SEO';

const Home = () => {
  // 1. State cho Sản phẩm (Giữ nguyên logic cũ)
  const [products, setProducts] = useState([]);
  const [loadingProducts, setLoadingProducts] = useState(true);

  // 2. State cho Banner (Mới thêm)
  const [banners, setBanners] = useState([]);
  const [loadingBanner, setLoadingBanner] = useState(true);

  useEffect(() => {
    // Hàm lấy danh sách sản phẩm (Logic gốc)
>>>>>>> Stashed changes
    const fetchProducts = async () => {
      try {
        const res = await axios.get('http://localhost:5000/api/products');
        if (res.data.success) {
          setProducts(res.data.data);
        }
<<<<<<< Updated upstream
      } catch (error) {
        console.error("Lỗi lấy sản phẩm:", error);
      }
    };
    fetchProducts();
  }, []);

  return (
    <div className="min-h-screen bg-stone-50">
      {/* Banner */}
      <div className="h-[500px] bg-stone-200 flex items-center justify-center mb-10">
        <div className="text-center">
          <h2 className="text-4xl md:text-6xl font-light text-stone-800 mb-4 tracking-widest">NEW ARRIVALS</h2>
          <Link to="/collection" className="inline-block border-b border-stone-800 pb-1 uppercase text-sm tracking-widest hover:text-stone-600">Xem bộ sưu tập</Link>
        </div>
      </div>

      {/* Danh sách sản phẩm */}
      <div className="max-w-7xl mx-auto px-6 pb-20">
        <h3 className="text-2xl font-bold text-stone-800 mb-8 text-center font-serif">Sản Phẩm Mới Nhất</h3>
        
        <div className="grid grid-cols-2 md:grid-cols-4 gap-x-6 gap-y-10">
          {products.map((product) => (
            <Link to={`/product/${product.slug}`} key={product.id} className="group">
              {/* Ảnh sản phẩm */}
              <div className="aspect-[3/4] bg-stone-200 overflow-hidden rounded-sm mb-4 relative">
                {product.images?.[0] ? (
                  <img 
                    src={product.images[0]} 
                    alt={product.name} 
                    className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                  />
                ) : (
                  <div className="w-full h-full flex items-center justify-center text-stone-400">No Image</div>
                )}
                {/* Nút thêm nhanh (Hiện khi hover) */}
                <button className="absolute bottom-0 left-0 w-full bg-stone-900 text-white py-3 translate-y-full group-hover:translate-y-0 transition-transform duration-300 uppercase text-xs tracking-wider">
                  Xem chi tiết
                </button>
              </div>

              {/* Thông tin */}
              <div>
                <h4 className="font-medium text-stone-800 group-hover:text-stone-600 transition-colors">{product.name}</h4>
                <p className="text-stone-500 text-sm mt-1">
                  {new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(product.base_price)}
                </p>
              </div>
            </Link>
          ))}
        </div>
=======
      } catch (err) {
        console.error("Lỗi tải sản phẩm:", err);
      } finally {
        setLoadingProducts(false);
      }
    };

    // Hàm lấy Banner (Logic mới)
    const fetchBanners = async () => {
      try {
        const res = await axios.get('http://localhost:5000/api/content/banners');
        if (res.data.success) {
          setBanners(res.data.data);
        }
      } catch (err) {
        console.error("Lỗi tải banner:", err);
      } finally {
        setLoadingBanner(false);
      }
    };

    fetchProducts();
    fetchBanners();
  }, []);

  // Hàm render Banner Hero (Mới)
  const renderHeroSection = () => {
    if (loadingBanner) return <div className="h-[500px] bg-stone-100 animate-pulse"></div>;
    
    // Nếu không có banner nào -> Hiển thị mặc định
    if (banners.length === 0) {
      return (
        <div className="h-[500px] bg-stone-200 flex items-center justify-center text-center px-4">
          <div>
             <h1 className="text-4xl md:text-6xl font-bold text-stone-800 mb-4 tracking-widest">BROWN FASHION</h1>
             <p className="text-stone-500 text-lg">Thanh lịch & Tối giản</p>
          </div>
        </div>
      );
    }

    // Lấy banner đầu tiên làm Hero
    const mainBanner = banners[0];

    return (
      <div className="relative h-[60vh] md:h-[80vh] w-full overflow-hidden">
        <img 
          src={mainBanner.image_url} 
          alt={mainBanner.title} 
          className="w-full h-full object-cover object-center transition-transform duration-1000 hover:scale-105"
        />
        <div className="absolute inset-0 bg-black/30"></div>
        <div className="absolute inset-0 flex flex-col items-center justify-center text-center px-4">
          <h2 className="text-white text-4xl md:text-6xl font-bold mb-6 tracking-wide drop-shadow-lg uppercase">
            {mainBanner.title}
          </h2>
          {mainBanner.link_to && (
            <Link 
              to={mainBanner.link_to} 
              className="group bg-white text-black px-8 py-3 font-bold uppercase tracking-widest hover:bg-stone-900 hover:text-white transition-all duration-300 flex items-center gap-2"
            >
              Khám phá ngay <FaArrowRight className="group-hover:translate-x-1 transition-transform"/>
            </Link>
          )}
        </div>
      </div>
    );
  };

  return (
    <div className="min-h-screen bg-stone-50">
      {/* SEO */}
      <SEO title="Trang chủ" description="Thương hiệu thời trang tối giản Brown Fashion." />

      {/* 1. HERO SECTION (BANNER) */}
      {renderHeroSection()}

      {/* 2. DANH SÁCH SẢN PHẨM (GIỮ NGUYÊN LOGIC CŨ) */}
      <div className="max-w-7xl mx-auto px-4 py-16">
          <div className="text-center mb-12">
            <h3 className="text-2xl font-bold text-stone-800 uppercase tracking-widest mb-2">Hàng mới về</h3>
            <p className="text-stone-500 italic">Những thiết kế mới nhất cho mùa này</p>
          </div>

          {loadingProducts ? (
            <div className="text-center py-10">Đang tải sản phẩm...</div>
          ) : (
            <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-8">
              {products.map((product) => (
                <Link to={`/product/${product.slug}`} key={product.id} className="group">
                  <div className="relative overflow-hidden mb-4 bg-stone-200 aspect-[3/4]">
                    {/* Ảnh sản phẩm */}
                    <img 
                      src={product.images?.[0]} 
                      alt={product.name} 
                      className="w-full h-full object-cover object-center transition-transform duration-500 group-hover:scale-110"
                    />
                    {/* Badge Mới/Sale nếu cần */}
                    {/*<div className="absolute top-2 left-2 bg-stone-900 text-white text-xs px-2 py-1 uppercase tracking-wider">New</div>*/}
                  </div>
                  
                  {/* Thông tin sản phẩm */}
                  <h3 className="text-stone-900 font-medium group-hover:text-stone-600 transition-colors">{product.name}</h3>
                  <p className="text-stone-500 mt-1 font-bold">
                    {new Intl.NumberFormat('vi-VN').format(product.base_price)} ₫
                  </p>
                </Link>
              ))}
            </div>
          )}
          
          {/* Nút xem tất cả */}
          <div className="text-center mt-12">
             <Link to="/collection" className="inline-block border-b-2 border-stone-900 pb-1 text-stone-900 font-bold uppercase tracking-widest hover:text-stone-600 hover:border-stone-600 transition-all">
                Xem tất cả sản phẩm
             </Link>
          </div>
>>>>>>> Stashed changes
      </div>
    </div>
  );
};

export default Home;