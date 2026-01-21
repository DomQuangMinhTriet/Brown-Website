import { useEffect, useState } from 'react';
import axios from 'axios';
import { Link, useSearchParams, useNavigate } from 'react-router-dom';
import { FaSearch, FaStore, FaShoppingCart } from 'react-icons/fa';
import { useCart } from '../context/CartContext'; // Import Cart

const Collection = () => {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const { cartCount, cartTotal } = useCart(); // Lấy thông tin giỏ hàng
  const navigate = useNavigate();
  
  // Lấy tham số POS
  const [searchParams] = useSearchParams();
  const searchQuery = searchParams.get('search');
  const isPosMode = searchParams.get('pos') === 'true'; // Kiểm tra chế độ POS
  const categorySlug = searchParams.get('category'); // <--- LẤY SLUG DANH MỤC

  useEffect(() => {
    const fetchProducts = async () => {
      setLoading(true);
      try {
        // Lấy tham số từ URL trình duyệt
        // Ví dụ URL: /collection?category=ao-thun -> categorySlug = 'ao-thun'
        const categorySlug = searchParams.get('category'); 
        const searchQuery = searchParams.get('search');

        let url = 'http://localhost:5000/api/products?'; // Lưu ý dấu ? ở cuối
        
        const params = [];
        if (searchQuery) params.push(`search=${encodeURIComponent(searchQuery)}`);
        
        // Gửi slug lên với key là 'category' để khớp với req.query.category ở Backend
        if (categorySlug) params.push(`category=${encodeURIComponent(categorySlug)}`); 
        
        // Kết quả sẽ là: http://localhost:5000/api/products?category=ao-thun
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
  }, [searchParams]); // Dùng searchParams làm dependency là đủ

  return (
    <div className={isPosMode ? "bg-stone-100 min-h-screen pb-24" : ""}>
      
      {/* 1. HEADER POS MODE */}
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
        {/* Title & Search... (Giữ nguyên logic cũ) */}
        <div className="text-center mb-10">
            <h2 className="text-3xl font-serif text-stone-900 mb-8">
                {searchQuery 
                    ? `Kết quả tìm kiếm: "${searchQuery}"` 
                    : categorySlug 
                        ? `Danh mục: ${products[0]?.categories?.name || 'Sản phẩm'}` 
                        : "Tất cả sản phẩm"}
            </h2>
        </div>

        {/* LIST SẢN PHẨM */}
        {loading ? (
            <div className="text-center py-20">Đang tải...</div>
        ) : (
            <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-x-4 gap-y-8">
            {products.map(product => (
                <Link 
                    // QUAN TRỌNG: Nếu đang ở POS, khi bấm vào sản phẩm phải giữ nguyên ?pos=true
                    to={`/product/${product.slug}${isPosMode ? '?pos=true' : ''}`} 
                    key={product.id} 
                    // --- SỬA Ở ĐÂY: Xóa bg-white, p-3, shadow ---
                    className="group block"
                >
                    {/* Khung ảnh: Xóa bg-stone-200 để tránh hiện nền xám khi ảnh đang load */}
                    <div className="aspect-[3/4] overflow-hidden rounded-lg mb-3 relative">
                        <img 
                            src={product.images?.[0]} 
                            alt={product.name} 
                            className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                        />
                        
                        {/* Overlay nút chọn mua (chỉ hiện khi ở POS) */}
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
      </div>

      {/* 2. THANH THANH TOÁN (CHỈ HIỆN KHI Ở POS) */}
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
                onClick={() => navigate('/checkout?pos=true')} // Chuyển sang trang thanh toán POS
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