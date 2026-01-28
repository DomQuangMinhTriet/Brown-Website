// client/src/pages/ProductDetail.jsx
import { useState, useEffect } from 'react';
import { useParams, Link } from 'react-router-dom';
import axios from 'axios';
import { useCart } from '../context/CartContext';
import { FaStar, FaCheck, FaHistory, FaBoxOpen } from 'react-icons/fa';
import SEO from '../components/SEO';

// --- COMPONENT CON: THẺ SẢN PHẨM ---
const ProductCard = ({ product }) => (
    <Link to={`/product/${product.slug}`} className="group block">
        <div className="aspect-[3/4] overflow-hidden rounded-lg mb-3 relative bg-stone-100">
            <img 
                src={product.images?.[0]} 
                alt={product.name} 
                className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                // [THÊM] Lazy load
                loading="lazy"
                decoding="async"
            />
        </div>
        <h3 className="font-medium text-stone-900 text-sm truncate group-hover:text-stone-600 transition-colors">
            {product.name}
        </h3>
        <p className="text-stone-500 font-bold mt-1 text-sm">
            {new Intl.NumberFormat('vi-VN').format(product.base_price)} ₫
        </p>
    </Link>
);

const ProductDetail = () => {
    const { slug } = useParams();
    const [product, setProduct] = useState(null);
    const [selectedVariant, setSelectedVariant] = useState(null);
    const { addToCart } = useCart();
    
    // State cho 2 mục mới
    const [relatedProducts, setRelatedProducts] = useState([]);
    const [viewedProducts, setViewedProducts] = useState([]);
    const [mainImage, setMainImage] = useState(null); // [MỚI] State ảnh chính

    // 1. Fetch sản phẩm chính + Sản phẩm liên quan + Xử lý đã xem
    useEffect(() => {
        const fetchProductData = async () => {
            try {
                // Lấy tất cả sản phẩm về để check
                const res = await axios.get(`${import.meta.env.VITE_API_URL}/api/products`); 
                if (res.data.success) {
                    const allProducts = res.data.data;
                    const found = allProducts.find(p => p.slug === slug);
                    
                    if (found) {
                        setProduct(found);
                        
                        // --- LOGIC SẢN PHẨM LIÊN QUAN ---
                        const related = allProducts.filter(p => 
                            p.category_id === found.category_id && p.id !== found.id
                        ).slice(0, 4);
                        setRelatedProducts(related);

                        // --- LOGIC LƯU & LỌC SẢN PHẨM ĐÃ XEM (QUAN TRỌNG) ---
                        // 1. Lưu sản phẩm hiện tại vào LocalStorage
                        saveToViewedHistory(found);

                        // 2. Đọc lại từ LocalStorage
                        const localHistory = JSON.parse(localStorage.getItem('viewed_products') || '[]');

                        // 3. [FIX LỖI] Kiểm tra xem sản phẩm trong LocalStorage có tồn tại trong Database thật (allProducts) không?
                        // Nếu sản phẩm đã bị xóa trong Admin, nó sẽ không tìm thấy trong allProducts -> Bị lọc bỏ.
                        const validHistory = localHistory
                            .map(localItem => allProducts.find(realItem => realItem.id === localItem.id)) // Map sang sản phẩm thật
                            .filter(item => item !== undefined); // Loại bỏ những cái undefined (đã bị xóa)

                        // 4. Cập nhật lại LocalStorage cho sạch sẽ (Xóa rác)
                        localStorage.setItem('viewed_products', JSON.stringify(validHistory));

                        // 5. Hiển thị ra màn hình (Trừ sản phẩm đang xem hiện tại)
                        setViewedProducts(validHistory.filter(p => p.id !== found.id).slice(0, 4));
                    }
                }
            } catch (error) {
                console.error("Lỗi tải sản phẩm:", error);
            }
        };

        fetchProductData();
        // Scroll lên đầu trang khi chuyển sản phẩm
        window.scrollTo(0, 0); 
    }, [slug]);

    // [MỚI] Effect để set ảnh mặc định khi sản phẩm thay đổi
    useEffect(() => {
        if (product?.images?.length > 0) {
            setMainImage(product.images[0]);
        }
    }, [product]);

    // 2. Hàm lưu lịch sử xem
    const saveToViewedHistory = (currentProduct) => {
        try {
            const history = JSON.parse(localStorage.getItem('viewed_products') || '[]');
            // Lọc bỏ sản phẩm trùng (nếu đã xem rồi thì xóa cũ để đẩy lên đầu)
            const newHistory = history.filter(item => item.id !== currentProduct.id);
            
            // Thêm sản phẩm hiện tại vào đầu danh sách
            newHistory.unshift({
                id: currentProduct.id,
                name: currentProduct.name,
                slug: currentProduct.slug,
                base_price: currentProduct.base_price,
                images: currentProduct.images
            });

            // Chỉ giữ lại 8 sản phẩm gần nhất
            const limitedHistory = newHistory.slice(0, 8);
            
            localStorage.setItem('viewed_products', JSON.stringify(limitedHistory));
        } catch (e) { console.error(e); }
    };

    // Helper: Lấy tồn kho
    const getStock = (variant) => variant ? variant.quantity_remaining : 0;

    if (!product) return <div className="min-h-screen flex justify-center items-center">Đang tải...</div>;

    return (
        <div className="min-h-screen pt-10 pb-20 px-4 bg-white">
             {/* SEO */}
             <SEO 
                title={product.name} 
                description={product.description?.substring(0, 150) + "..."} 
                image={product.images?.[0]} 
                url={`/product/${product.slug}`}
            />

            <div className="max-w-6xl mx-auto">
                {/* --- PHẦN 1: CHI TIẾT SẢN PHẨM CHÍNH --- */}
                <div className="grid grid-cols-1 md:grid-cols-2 gap-12 mb-20">
                    {/* Cột Trái: Ảnh */}
                    <div className="space-y-4">
                        <div className="rounded-xl overflow-hidden aspect-[3/4]">
                            {/* [ĐÃ SỬA] Hiển thị mainImage thay vì fix cứng ảnh đầu tiên */}
                            <img 
                                src={mainImage || product.images?.[0] || 'https://via.placeholder.com/500'} 
                                alt={product.name} 
                                className="w-full h-full object-cover transition-all duration-300"
                                // Ảnh chính nên tải ngay (priority), không dùng lazy ở đây để tránh nháy hình
                                fetchPriority="high"
                            />
                        </div>
                        {/* Ảnh nhỏ (Thumbnails) nếu có nhiều ảnh */}
                        {product.images?.length > 1 && (
                            <div className="grid grid-cols-4 gap-2">
                                {product.images.map((img, idx) => (
                                    <div 
                                        key={idx} 
                                        onClick={() => setMainImage(img)} // [MỚI] Click đổi ảnh
                                        className={`
                                            aspect-[3/4] rounded-lg overflow-hidden cursor-pointer hover:opacity-80 transition-all
                                            ${mainImage === img ? 'ring-2 ring-stone-900' : 'border border-transparent'}
                                        `}
                                    >
                                        <img src={img} className="w-full h-full object-cover" alt="" loading="lazy" decoding="async" />
                                    </div>
                                ))}
                            </div>
                        )}
                    </div>

                    {/* Cột Phải: Thông tin */}
                    <div className="flex flex-col h-full">
                        <div className="mb-auto">
                            <h1 className="text-3xl font-serif text-stone-900 mb-2">{product.name}</h1>
                            <div className="flex items-center gap-2 mb-6">
                            </div>

                            <p className="text-2xl font-bold text-stone-800 mb-8">
                                {new Intl.NumberFormat('vi-VN').format(product.base_price)} ₫
                            </p>

                            {/* Chọn Biến thể */}
                            <div className="mb-8">
                                <label className="text-xs font-bold uppercase text-stone-500 mb-3 block">Chọn Phân loại:</label>
                                <div className="flex flex-wrap gap-2">
                                    {product.variants?.map(variant => (
                                        <button
                                            key={variant.id}
                                            onClick={() => {
                                                setSelectedVariant(variant);
                                                // [MỚI] Nếu biến thể có ảnh riêng -> đổi ảnh chính
                                                if (variant.image_url) {
                                                    setMainImage(variant.image_url);
                                                }
                                            }}
                                            className={`
                                                min-w-[80px] px-4 py-2 border rounded-lg text-sm transition-all relative overflow-hidden
                                                ${selectedVariant?.id === variant.id 
                                                    ? 'border-stone-900 bg-stone-900 text-white' 
                                                    : 'border-stone-200 text-stone-600 hover:border-stone-900'}
                                                ${getStock(variant) <= 0 ? 'opacity-50 cursor-not-allowed bg-stone-100' : ''}
                                            `}
                                            disabled={getStock(variant) <= 0}
                                        >
                                            {variant.size} - {variant.color}
                                            {/* Hiển thị tồn kho nhỏ */}
                                            {getStock(variant) > 0 && getStock(variant) < 5 && (
                                                <span className="absolute top-0 right-0 w-2 h-2 bg-red-500 rounded-full"></span>
                                            )}
                                        </button>
                                    ))}
                                </div>
                                {selectedVariant && (
                                    <div className="mt-2 text-xs text-stone-500 font-medium">
                                        {getStock(selectedVariant) > 0 
                                            ? `Còn lại ${getStock(selectedVariant)} sản phẩm` 
                                            : <span className="text-red-500">Hết hàng</span>}
                                    </div>
                                )}
                            </div>

                            {/* Nút Mua */}
                            <button 
                                onClick={() => addToCart(product, selectedVariant, 1)}
                                disabled={!selectedVariant || getStock(selectedVariant) <= 0}
                                className={`
                                    w-full py-4 rounded-xl font-bold text-white uppercase tracking-wider shadow-lg transition-transform active:scale-95 mb-8
                                    ${(!selectedVariant || getStock(selectedVariant) <= 0)
                                        ? 'bg-stone-300 cursor-not-allowed shadow-none' 
                                        : 'bg-red-600 hover:bg-red-700'}
                                `}
                            >
                                {!selectedVariant ? "Chọn Size/Màu" : getStock(selectedVariant) <= 0 ? "Hết hàng" : "Thêm vào giỏ"}
                            </button>

                            {/* --- MÔ TẢ & SIZE CHART --- */}
                            <div className="border-t border-stone-100 pt-6">
                                <h3 className="font-bold text-stone-700 mb-3 text-sm uppercase">Mô tả chi tiết</h3>
                                <p className="text-stone-600 leading-relaxed text-sm whitespace-pre-line mb-6">
                                    {product.description || "Chưa có mô tả."}
                                </p>

                                {/* ẢNH SIZE CHART */}
                                <div className="mt-4">
                                    <h4 className="font-bold text-stone-700 text-xs uppercase mb-2">Bảng quy đổi kích cỡ</h4>
                                    
                                    {product.size_chart_url ? (
                                        <div className="rounded-lg overflow-hidden border border-stone-200">
                                            <img 
                                                src={product.size_chart_url} 
                                                alt="Size Chart"
                                                className="w-full h-auto object-cover"
                                            />
                                        </div>
                                    ) : (
                                        <div className="rounded-lg overflow-hidden border border-stone-200">
                                             <img 
                                                src="https://file.hstatic.net/200000185994/file/bang_size_ao_thun_nam_ad12822a16c44284ab94132808c1650c_1024x1024.jpg" 
                                                alt="Size Chart Default"
                                                className="w-full h-auto object-cover opacity-50"
                                            />
                                            <p className="text-center text-xs text-stone-400 p-2">Sản phẩm này chưa cập nhật bảng size riêng.</p>
                                        </div>
                                    )}
                                </div>
                            </div>
                        </div>
                    </div>
                </div>

                {/* --- PHẦN 2: SẢN PHẨM LIÊN QUAN --- */}
                {relatedProducts.length > 0 && (
                    <div className="mb-20">
                        <div className="flex items-center justify-between mb-6 border-b border-stone-200 pb-2">
                            <h2 className="text-xl font-serif font-bold text-stone-900">Sản phẩm liên quan</h2>
                            <Link to="/collection" className="text-xs font-bold text-stone-500 hover:text-stone-900">Xem tất cả</Link>
                        </div>
                        <div className="grid grid-cols-2 md:grid-cols-4 gap-x-4 gap-y-8">
                            {relatedProducts.map(p => <ProductCard key={p.id} product={p} />)}
                        </div>
                    </div>
                )}

                {/* --- PHẦN 3: SẢN PHẨM ĐÃ XEM --- */}
                {viewedProducts.length > 0 && (
                    <div>
                         <div className="flex items-center gap-2 mb-6 border-b border-stone-200 pb-2">
                            <FaHistory className="text-stone-400"/>
                            <h2 className="text-xl font-serif font-bold text-stone-900">Sản phẩm vừa xem</h2>
                        </div>
                        <div className="grid grid-cols-2 md:grid-cols-4 gap-x-4 gap-y-8">
                            {viewedProducts.map(p => <ProductCard key={p.id} product={p} />)}
                        </div>
                    </div>
                )}
            </div>
        </div>
    );
};

export default ProductDetail;