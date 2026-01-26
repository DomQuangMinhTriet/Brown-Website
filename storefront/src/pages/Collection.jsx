import { useEffect, useState } from 'react';
import axios from 'axios';
import { Link, useSearchParams, useNavigate } from 'react-router-dom';
import { FaStore, FaShoppingCart } from 'react-icons/fa';
import { useCart } from '../context/CartContext'; 

const Collection = () => {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const { cartCount, cartTotal } = useCart(); 
  const navigate = useNavigate();
  
  // Lấy tham số URL
  const [searchParams] = useSearchParams();
  const searchQuery = searchParams.get('search');
  const isPosMode = searchParams.get('pos') === 'true'; 
  const categorySlug = searchParams.get('category'); 

  // [MỚI] 1. State lưu tiêu đề trang (để không phụ thuộc vào sản phẩm)
  const [pageTitle, setPageTitle] = useState('Tất cả sản phẩm');

  // [MỚI] 2. Effect riêng để lấy Tên Danh Mục đúng (Fix lỗi hiển thị sai tên)
  useEffect(() => {
    const fetchCategoryName = async () => {
        if (searchQuery) {
            setPageTitle(`Kết quả tìm kiếm: "${searchQuery}"`);
        } else if (categorySlug) {
            try {
                // Gọi API lấy danh sách danh mục để tìm tên đúng của Slug hiện tại
                const res = await axios.get(`${import.meta.env.VITE_API_URL}/api/categories`);
                if (res.data.success) {
                    const foundCat = res.data.data.find(c => c.slug === categorySlug);
                    // Nếu tìm thấy thì lấy tên, không thì lấy chính cái slug cho đỡ trống
                    setPageTitle(foundCat ? `${foundCat.name}` : `${categorySlug}`);
                }
            } catch (error) {
                console.error("Lỗi lấy tên danh mục:", error);
                setPageTitle('Sản phẩm');
            }
        } else {
            setPageTitle('Tất cả sản phẩm');
        }
    };

    fetchCategoryName();
  }, [categorySlug, searchQuery]); // Chạy lại khi URL thay đổi

  // 3. Effect lấy danh sách sản phẩm (Giữ nguyên logic lọc cũ của bạn)
  useEffect(() => {
    const fetchProducts = async () => {
      setLoading(true);
      try {
        let url = `${import.meta.env.VITE_API_URL}/api/products?`;
        
        const params = [];
        if (searchQuery) params.push(`search=${encodeURIComponent(searchQuery)}`);
        
        // Gửi slug lên Backend (Backend đã sửa để lọc cả danh mục phụ)
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
  }, [searchParams]); 

  return (
    <div className={isPosMode ? "bg-stone-100 min-h-screen pb-24" : ""}>
      
      {/* HEADER POS MODE */}
      {isPosMode && (
          <div className="bg-red-700 text-white p-4 shadow-md sticky top-20 z-40 flex justify-between items-center">
             <div className="font-bold text-lg flex items-center gap-2 uppercase">
                <FaStore/> Chọn sản phẩm (POS)
             </div>
             <button onClick={() => window.close()} className="text-xs underline opacity-80 hover:opacity-100">
                Thoát
             </button>
          </div>
      )}

      <div className="max-w-7xl mx-auto px-6 py-8">
        {/* [SỬA] Hiển thị PageTitle từ State mới */}
        <div className="text-center mb-10">
            <h2 className="text-3xl font-serif text-stone-900 mb-8 uppercase">
                {pageTitle}
            </h2>
        </div>

        {/* LIST SẢN PHẨM */}
        {loading ? (
            <div className="text-center py-20">Đang tải...</div>
        ) : (
            <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-x-4 gap-y-8">
            {products.map(product => (
                <Link 
                    to={`/product/${product.slug}${isPosMode ? '?pos=true' : ''}`} 
                    key={product.id} 
                    className="group block"
                >
                    <div className="aspect-[3/4] overflow-hidden rounded-lg mb-3 relative">
                        <img 
                            src={product.images?.[0]} 
                            alt={product.name} 
                            className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                        />
                        
                        {isPosMode && (
                            <div className="absolute inset-0 bg-black/10 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity">
                                <span className="bg-white text-stone-900 px-3 py-1 text-xs font-bold rounded shadow">CHỌN MUA</span>
                            </div>
                        )}
                    </div>

                    <h3 className="font-medium text-stone-900 text-sm truncate group-hover:text-stone-600 transition-colors">
                        {product.name}
                    </h3>
                    <p className="text-stone-500 font-bold mt-1 text-sm">
                        {new Intl.NumberFormat('vi-VN').format(product.base_price)} ₫
                    </p>
                </Link>
            ))}
            </div>
        )}
        
        {!loading && products.length === 0 && (
            <div className="text-center py-10 text-stone-500 italic">
                Không tìm thấy sản phẩm nào trong danh mục này.
            </div>
        )}
      </div>

      {/* THANH THANH TOÁN POS */}
      {isPosMode && (
        <div className="fixed bottom-0 left-0 w-full bg-white border-t border-stone-200 p-4 shadow-[0_-5px_10px_rgba(0,0,0,0.1)] z-50 flex justify-between items-center">
            <div className="flex items-center gap-4">
                <div className="bg-stone-900 text-white w-12 h-12 rounded-full flex items-center justify-center text-xl relative">
                    <FaShoppingCart />
                    {cartCount > 0 && <span className="absolute -top-1 -right-1 bg-red-600 text-white text-xs w-5 h-5 rounded-full flex items-center justify-center border border-white">{cartCount}</span>}
                </div>
                <div>
                    <p className="text-xs text-stone-500 uppercase">Tổng tiền tạm tính</p>
                    <p className="text-xl font-bold text-stone-900">{new Intl.NumberFormat('vi-VN').format(cartTotal)} ₫</p>
                </div>
            </div>
            
            <button 
                onClick={() => navigate('/checkout?pos=true')} 
                disabled={cartCount === 0}
                className="bg-red-600 hover:bg-red-700 text-white px-8 py-3 rounded font-bold uppercase tracking-widest disabled:bg-gray-300 transition-colors"
            >
                Thanh Toán Ngay
            </button>
        </div>
      )}
    </div>
  );
};

export default Collection;