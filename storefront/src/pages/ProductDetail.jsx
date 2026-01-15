import { useEffect, useState } from 'react';
import { useParams, useSearchParams, useNavigate } from 'react-router-dom';
import axios from 'axios';
import { useCart } from '../context/CartContext';
import { FaStore, FaArrowLeft, FaStar, FaShoppingCart, FaCheck } from 'react-icons/fa';

const ProductDetail = () => {
  const { slug } = useParams();
  const navigate = useNavigate();
  const { addToCart } = useCart();
  
  // 1. LẤY THAM SỐ POS TỪ URL
  const [searchParams] = useSearchParams();
  const isPosMode = searchParams.get('pos') === 'true';

  // --- STATE ---
  const [product, setProduct] = useState(null);
  const [loading, setLoading] = useState(true);
  const [selectedSize, setSelectedSize] = useState('');
  const [selectedColor, setSelectedColor] = useState('');
  const [mainImage, setMainImage] = useState(''); // Ảnh đang hiển thị to

  // --- FETCH DATA ---
  useEffect(() => {
    const fetchProduct = async () => {
      try {
        const res = await axios.get(`http://localhost:5000/api/products/${slug}`);
        if (res.data.success) {
            setProduct(res.data.data);
            // Mặc định hiển thị ảnh đầu tiên
            if (res.data.data.images && res.data.data.images.length > 0) {
                setMainImage(res.data.data.images[0]);
            }
        }
      } catch (err) {
        console.error("Lỗi lấy sản phẩm:", err);
      } finally {
        setLoading(false);
      }
    };
    fetchProduct();
  }, [slug]);

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
      <div className="max-w-6xl mx-auto px-6 py-10">
        
        {/* Breadcrumb / Back Button (Cho chế độ thường) */}
        {!isPosMode && (
            <div className="mb-6">
                 <button onClick={() => navigate(-1)} className="text-stone-500 hover:text-stone-900 flex items-center gap-2 text-sm">
                    <FaArrowLeft/> Quay lại
                 </button>
            </div>
        )}

        <div className="grid grid-cols-1 md:grid-cols-2 gap-12 lg:gap-20">
            
            {/* CỘT TRÁI: HÌNH ẢNH */}
            <div className="space-y-4">
                {/* Ảnh chính */}
                <div className="aspect-[3/4] bg-stone-100 rounded-lg overflow-hidden shadow-sm border border-stone-200">
                    <img src={mainImage} alt={product.name} className="w-full h-full object-cover" />
                </div>
                
                {/* Thumbnails (nếu có nhiều ảnh) */}
                {product.images && product.images.length > 1 && (
                    <div className="flex gap-4 overflow-x-auto pb-2">
                        {product.images.map((img, idx) => (
                            <div 
                                key={idx} 
                                onClick={() => setMainImage(img)}
                                className={`w-20 h-24 flex-shrink-0 cursor-pointer rounded border-2 overflow-hidden ${mainImage === img ? 'border-stone-900' : 'border-transparent hover:border-stone-300'}`}
                            >
                                <img src={img} className="w-full h-full object-cover" alt="" />
                            </div>
                        ))}
                    </div>
                )}
            </div>

            {/* CỘT PHẢI: THÔNG TIN */}
            <div className="flex flex-col h-full">
                <h1 className="text-3xl md:text-4xl font-serif text-stone-900 mb-2">{product.name}</h1>
                
                <div className="flex items-center gap-4 mb-6">
                    <p className="text-2xl font-bold text-stone-800">
                        {new Intl.NumberFormat('vi-VN').format(product.base_price)} ₫
                    </p>
                    <div className="flex text-yellow-500 text-sm">
                        <FaStar/><FaStar/><FaStar/><FaStar/><FaStar/>
                    </div>
                </div>

                <div className="w-full h-[1px] bg-stone-200 mb-8"></div>

                {/* CHỌN MÀU */}
                <div className="mb-6">
                    <p className="text-xs font-bold uppercase text-stone-500 mb-3 tracking-wider">Màu sắc: <span className="text-stone-900 ml-1">{selectedColor}</span></p>
                    <div className="flex flex-wrap gap-3">
                        {uniqueColors.map(color => (
                            <button 
                                key={color} 
                                onClick={() => setSelectedColor(color)}
                                className={`px-4 py-2 border text-sm font-medium transition-all ${
                                    selectedColor === color 
                                    ? 'bg-stone-900 text-white border-stone-900 shadow-md' 
                                    : 'bg-white text-stone-600 border-stone-200 hover:border-stone-400'
                                }`}
                            >
                                {color}
                            </button>
                        ))}
                    </div>
                </div>

                {/* CHỌN SIZE */}
                <div className="mb-8">
                    <p className="text-xs font-bold uppercase text-stone-500 mb-3 tracking-wider">Kích thước: <span className="text-stone-900 ml-1">{selectedSize}</span></p>
                    <div className="flex flex-wrap gap-3">
                        {uniqueSizes.map(size => (
                            <button 
                                key={size} 
                                onClick={() => setSelectedSize(size)}
                                className={`w-12 h-12 border text-sm font-medium flex items-center justify-center transition-all ${
                                    selectedSize === size 
                                    ? 'bg-stone-900 text-white border-stone-900 shadow-md' 
                                    : 'bg-white text-stone-600 border-stone-200 hover:border-stone-400'
                                }`}
                            >
                                {size}
                            </button>
                        ))}
                    </div>
                </div>

                {/* NÚT ADD TO CART */}
                <button 
                    onClick={handleAddToCart}
                    className={`w-full py-4 text-white font-bold uppercase tracking-[0.15em] transition-all shadow-lg flex items-center justify-center gap-3 mb-6
                        ${isPosMode 
                            ? 'bg-red-700 hover:bg-red-800 hover:shadow-red-900/30' 
                            : 'bg-stone-900 hover:bg-stone-800 hover:shadow-stone-900/30'
                        }`}
                >
                    <FaShoppingCart className="text-lg" />
                    {isPosMode ? 'Thêm vào đơn (POS)' : 'Thêm vào giỏ hàng'}
                </button>

                {/* MÔ TẢ & CHÍNH SÁCH */}
                <div className="mt-auto space-y-4 text-sm text-stone-600">
                    <p className="leading-relaxed">
                        {product.description || "Chất liệu cao cấp, thiết kế tối giản mang lại sự thanh lịch và thoải mái tối đa cho người mặc."}
                    </p>
                    <ul className="space-y-2 mt-4 pt-4 border-t border-dashed border-stone-200">
                        <li className="flex items-center gap-2"><FaCheck className="text-green-500"/> Miễn phí vận chuyển đơn từ 500k</li>
                        <li className="flex items-center gap-2"><FaCheck className="text-green-500"/> Đổi trả trong vòng 30 ngày</li>
                        <li className="flex items-center gap-2"><FaCheck className="text-green-500"/> Hàng chính hãng 100%</li>
                    </ul>
                </div>

            </div>
        </div>
      </div>
    </div>
  );
};

export default ProductDetail;