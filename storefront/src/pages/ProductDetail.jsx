import { useState, useEffect } from 'react';
import { useParams } from 'react-router-dom'; // Thêm useParams để lấy ID từ URL
import axios from 'axios';
import { useCart } from '../context/CartContext';
<<<<<<< Updated upstream
import { FaStore, FaArrowLeft, FaStar, FaShoppingCart, FaCheck } from 'react-icons/fa';
<<<<<<< Updated upstream
=======
import SEO from '../components/SEO'; // <--- IMPORT
>>>>>>> Stashed changes
=======
>>>>>>> Stashed changes

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

<<<<<<< Updated upstream
  // --- HANDLE ADD TO CART ---
  const handleAddToCart = () => {
    if (!selectedSize || !selectedColor) {
      alert('Vui lòng chọn đầy đủ Size và Màu sắc!');
      return;
    }
    
    // Tìm variant ID tương ứng
    const variant = product.variants.find(v => v.size === selectedSize && v.color === selectedColor);
    
    // Kiểm tra tồn kho (nếu có logic check tồn kho frontend)
    if (!variant) {
        alert('Sản phẩm biến thể này tạm thời không khả dụng.');
        return;
    }

    // Thêm vào Context
    addToCart({
      variant_id: variant.id,
      name: product.name,
      price: variant.price || product.base_price,
      image: mainImage, // Lấy ảnh đang xem làm ảnh đại diện trong giỏ
      size: selectedSize,
      color: selectedColor,
      quantity: 1
    });

    // --- LOGIC ĐIỀU HƯỚNG SAU KHI THÊM ---
    if (isPosMode) {
        // POS: Thường mua nhiều món, nên hỏi để quay lại chọn tiếp
        const continueShopping = window.confirm(`✅ Đã thêm "${product.name}" vào đơn!\nBạn có muốn quay lại danh sách để chọn món khác không?`);
        if (continueShopping) {
            navigate('/collection?pos=true');
        }
        // Nếu chọn Cancel -> Ở lại trang này (có thể để sửa số lượng hoặc mua thêm màu khác)
    } else {
        // Khách Online: Thông báo nhẹ nhàng
        alert('✅ Đã thêm sản phẩm vào giỏ hàng');
    }
  };

  if (loading) return <div className="min-h-screen flex items-center justify-center text-stone-500">Đang tải chi tiết...</div>;
  if (!product) return <div className="min-h-screen flex items-center justify-center text-stone-500">Không tìm thấy sản phẩm.</div>;

  // Lọc danh sách Size và Color duy nhất để hiển thị button
  const uniqueColors = [...new Set(product.variants.map(v => v.color))];
  const uniqueSizes = [...new Set(product.variants.map(v => v.size))];

  return (
    <div className={`min-h-screen pb-20 transition-colors ${isPosMode ? "bg-stone-50" : "bg-white"}`}>
      
      {/* 1. HEADER DÀNH RIÊNG CHO POS */}
      {isPosMode && (
          <div className="bg-red-700 text-white px-6 py-3 shadow-md sticky top-0 z-50 flex items-center justify-between">
             <div className="font-bold flex items-center gap-2 text-lg uppercase tracking-wider">
                <FaStore className="text-xl"/> CHẾ ĐỘ POS
             </div>
             <button 
                onClick={() => navigate('/collection?pos=true')} 
                className="bg-white/20 hover:bg-white/30 text-white px-4 py-2 rounded text-sm font-bold flex items-center gap-2 transition-all"
            >
                <FaArrowLeft/> Quay lại danh sách
             </button>
          </div>
      )}

      {/* 2. NỘI DUNG CHÍNH */}
<<<<<<< Updated upstream
      <div className="max-w-6xl mx-auto px-6 py-10">
=======
      <div className="max-w-7xl mx-auto px-6 py-10">
>>>>>>> Stashed changes
        
        {/* Breadcrumb / Back Button (Cho chế độ thường) */}
        {!isPosMode && (
            <div className="mb-6">
                 <button onClick={() => navigate(-1)} className="text-stone-500 hover:text-stone-900 flex items-center gap-2 text-sm">
                    <FaArrowLeft/> Quay lại
                 </button>
            </div>
        )}
<<<<<<< Updated upstream
=======
        
        {/* --- THÊM SEO ĐỘNG --- */}
        <SEO 
          title={product.name} 
          description={product.description ? product.description.substring(0, 150) + '...' : `Mua ngay ${product.name} giá tốt nhất.`}
          image={product.images?.[0]} // Lấy ảnh đầu tiên làm ảnh thumbnail khi share
          url={`/product/${product.slug}`}
        />
>>>>>>> Stashed changes

        <div className="grid grid-cols-1 md:grid-cols-2 gap-12 lg:gap-20">
            
            {/* CỘT TRÁI: HÌNH ẢNH */}
            <div className="space-y-4">
                {/* Ảnh chính */}
                <div className="aspect-[3/4] bg-stone-100 rounded-lg overflow-hidden shadow-sm border border-stone-200">
                    <img src={mainImage} alt={product.name} className="w-full h-full object-cover" />
=======
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
>>>>>>> Stashed changes
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