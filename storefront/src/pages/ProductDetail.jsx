import { useState, useEffect } from 'react';
import { useParams } from 'react-router-dom'; // Thêm useParams để lấy ID từ URL
import axios from 'axios';
import { useCart } from '../context/CartContext';

import { FaStore, FaArrowLeft, FaStar, FaShoppingCart, FaCheck } from 'react-icons/fa';
import SEO from '../components/SEO'; // <--- IMPORT

const ProductDetail = () => {
    const { slug } = useParams(); // Lấy slug từ URL
    const [product, setProduct] = useState(null);
    const [selectedVariant, setSelectedVariant] = useState(null);
    const { addToCart } = useCart();

    // Fetch dữ liệu sản phẩm
    useEffect(() => {
        const fetchProduct = async () => {
            try {
                // Gọi API lấy chi tiết sản phẩm (Lưu ý: API này cũng cần trả về stock giống getProducts)
                // Nếu API getProductBySlug của bạn chưa tính stock, bạn có thể tạm dùng logic lọc từ danh sách getProducts
                // Hoặc đơn giản là dùng API getProducts và lọc client-side cho nhanh:
                const res = await axios.get('http://localhost:5000/api/products'); 
                if (res.data.success) {
                    const found = res.data.data.find(p => p.slug === slug);
                    setProduct(found);
                }
            } catch (error) {
                console.error("Lỗi tải sản phẩm:", error);
            }
        };
        fetchProduct();
    }, [slug]);

    if (!product) return <div className="p-10 text-center">Đang tải dữ liệu...</div>;

    // --- HÀM KIỂM TRA TỒN KHO AN TOÀN ---
    // Sử dụng ?? 0 để đảm bảo nếu null/undefined thì sẽ là 0
    const getStock = (variant) => {
        return variant?.stock ?? variant?.quantity_remaining ?? 0;
    };

    return (
        <div className="container mx-auto p-4 md:p-10">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-10">
                
                {/* 1. ẢNH SẢN PHẨM */}
                <div className="border rounded-xl overflow-hidden shadow-sm">
                    <img 
                        src={product.images?.[0] || 'https://via.placeholder.com/500'} 
                        alt={product.name} 
                        className="w-full h-full object-cover"
                    />
                </div>

                {/* 2. THÔNG TIN & MUA HÀNG */}
                <div>
                    <h1 className="text-3xl font-bold text-stone-800 mb-2">{product.name}</h1>
                    <p className="text-2xl text-red-600 font-bold mb-6">
                        {new Intl.NumberFormat('vi-VN').format(product.base_price)} ₫
                    </p>

                    <hr className="border-stone-100 mb-6"/>

                    {/* CHỌN PHÂN LOẠI */}
                    <div className="mb-8">
                        <label className="block font-bold text-stone-700 mb-3 uppercase text-sm">Chọn Phân loại:</label>
                        <div className="flex flex-wrap gap-3">
                            {product.variants?.map((variant) => {
                                const stock = getStock(variant);
                                const isOutOfStock = stock <= 0; // Nhỏ hơn hoặc bằng 0 là hết hàng
                                const isSelected = selectedVariant?.id === variant.id;

                                return (
                                    <button
                                        key={variant.id}
                                        onClick={() => !isOutOfStock && setSelectedVariant(variant)}
                                        disabled={isOutOfStock} // <--- KHÓA NÚT NẾU HẾT HÀNG
                                        className={`
                                            relative px-6 py-3 border rounded-lg transition-all text-sm font-medium
                                            ${isOutOfStock 
                                                ? 'bg-stone-100 text-stone-300 border-stone-100 cursor-not-allowed decoration-slice' 
                                                : isSelected 
                                                    ? 'border-stone-900 bg-stone-900 text-white shadow-lg' 
                                                    : 'border-stone-200 hover:border-stone-900 text-stone-700 hover:shadow'
                                            }
                                        `}
                                    >
                                        {variant.size} - {variant.color}
                                        
                                        {/* Hiển thị số lượng tồn */}
                                        {isOutOfStock ? (
                                             <span className="absolute -top-2 -right-2 bg-stone-200 text-stone-500 text-[10px] px-1.5 py-0.5 rounded-full font-bold">Hết</span>
                                        ) : (
                                             <span className={`absolute -top-2 -right-2 text-[10px] px-1.5 py-0.5 rounded-full font-bold ${isSelected ? 'bg-white text-stone-900' : 'bg-red-100 text-red-600'}`}>
                                                {stock}
                                             </span>
                                        )}
                                    </button>
                                );
                            })}
                        </div>
                        {(!product.variants || product.variants.length === 0) && (
                            <p className="text-stone-400 italic">Sản phẩm này chưa có phân loại.</p>
                        )}
                    </div>

                    {/* NÚT THÊM VÀO GIỎ */}
                    <button
                        onClick={() => addToCart(product, selectedVariant, 1)}
                        disabled={!selectedVariant || getStock(selectedVariant) <= 0}
                        className={`
                            w-full py-4 rounded-xl font-bold text-white uppercase tracking-wider shadow-lg transition-transform active:scale-95
                            ${(!selectedVariant || getStock(selectedVariant) <= 0)
                                ? 'bg-stone-300 cursor-not-allowed shadow-none' 
                                : 'bg-red-600 hover:bg-red-700'}
                        `}
                    >
                        {!selectedVariant 
                            ? "Vui lòng chọn Size/Màu" 
                            : getStock(selectedVariant) <= 0 
                                ? "Tạm thời hết hàng" 
                                : "Thêm vào giỏ hàng"}
                    </button>
                    
                    {/* Mô tả */}
                    <div className="mt-8 pt-6 border-t border-stone-100">
                        <h3 className="font-bold text-stone-700 mb-2 text-sm uppercase">Mô tả sản phẩm</h3>
                        <p className="text-stone-600 leading-relaxed text-sm whitespace-pre-line">
                            {product.description || "Chưa có mô tả."}
                        </p>
                    </div>
                </div>
            </div>
        </div>
    );
};

export default ProductDetail;