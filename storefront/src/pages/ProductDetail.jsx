import { useEffect, useState } from 'react';
import { useParams } from 'react-router-dom';
import axios from 'axios';
import { FaStar, FaTruck, FaBox } from 'react-icons/fa';
import { useCart } from '../context/CartContext';

const ProductDetail = () => {
  const { slug } = useParams();
  const { addToCart } = useCart();
  
  const [product, setProduct] = useState(null);
  const [loading, setLoading] = useState(true);

  // State lựa chọn
  const [selectedImage, setSelectedImage] = useState('');
  const [selectedColor, setSelectedColor] = useState('');
  const [selectedSize, setSelectedSize] = useState('');
  const [quantity, setQuantity] = useState(1);

  // 1. Lấy dữ liệu
  useEffect(() => {
    const fetchProduct = async () => {
      try {
        const res = await axios.get(`http://localhost:5000/api/products/${slug}`);
        if (res.data.success) {
          const data = res.data.data;
          setProduct(data);
          if (data.images?.length > 0) setSelectedImage(data.images[0]);
        }
      } catch (error) {
        console.error("Lỗi:", error);
      } finally {
        setLoading(false);
      }
    };
    fetchProduct();
  }, [slug]);

  if (loading) return <div className="pt-32 text-center">Đang tải...</div>;
  if (!product) return <div className="pt-32 text-center">Không tìm thấy sản phẩm</div>;

  // 2. Logic Variants
  const uniqueColors = [...new Set(product.variants?.map(v => v.color))];
  const uniqueSizes = [...new Set(product.variants?.map(v => v.size))];

  // Tìm variant đang chọn
  const currentVariant = product.variants?.find(
    v => v.color === selectedColor && v.size === selectedSize
  );

  // Check tồn kho của Variant đang chọn
  const currentStock = currentVariant ? currentVariant.inventory : 0;

  const handleAddToCart = () => {
    if (!selectedColor || !selectedSize) {
      alert("Vui lòng chọn Màu sắc và Kích thước!"); return;
    }
    
    // Check kỹ lần cuối trước khi thêm
    if (!currentVariant || currentStock <= 0) {
      alert("Sản phẩm này vừa hết hàng!"); return;
    }

    if (quantity > currentStock) {
        alert(`Kho chỉ còn ${currentStock} sản phẩm!`); return;
    }

    addToCart(product, currentVariant, quantity);
    alert(`Đã thêm vào giỏ: ${product.name}`);
  };

  return (
    <div className="max-w-7xl mx-auto px-6 py-10 min-h-screen">
      <div className="grid grid-cols-1 md:grid-cols-2 gap-12">
        
        {/* CỘT TRÁI: ẢNH */}
        <div className="space-y-4">
          <div className="aspect-[3/4] bg-stone-100 rounded-lg overflow-hidden relative">
            <img src={selectedImage} alt={product.name} className="w-full h-full object-cover" />
            {/* Badge hết hàng toàn bộ nếu cần */}
            {product.variants.every(v => v.inventory === 0) && (
                <div className="absolute inset-0 bg-white/60 flex items-center justify-center">
                    <span className="bg-stone-900 text-white px-6 py-2 uppercase font-bold tracking-widest">Hết hàng</span>
                </div>
            )}
          </div>
          <div className="flex gap-4 overflow-x-auto pb-2">
            {product.images?.map((img, idx) => (
              <div key={idx} onClick={() => setSelectedImage(img)} className={`w-20 h-28 flex-shrink-0 cursor-pointer border-2 rounded ${selectedImage === img ? 'border-stone-800' : 'border-transparent'}`}>
                <img src={img} className="w-full h-full object-cover" />
              </div>
            ))}
          </div>
        </div>

        {/* CỘT PHẢI: INFO */}
        <div>
          <h1 className="text-3xl font-serif text-stone-900 mb-2">{product.name}</h1>
          <p className="text-xl font-medium text-stone-800 mb-6">{new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(product.base_price)}</p>
          
          <hr className="border-stone-200 mb-8" />

          {/* CHỌN MÀU */}
          <div className="mb-6">
            <h3 className="text-sm font-bold uppercase text-stone-900 mb-3">Màu sắc: {selectedColor}</h3>
            <div className="flex flex-wrap gap-3">
              {uniqueColors.map(color => {
                // Kiểm tra xem màu này có size nào còn hàng không?
                const isColorAvailable = product.variants.some(v => v.color === color && v.inventory > 0);
                
                return (
                  <button
                    key={color}
                    onClick={() => { setSelectedColor(color); setSelectedSize(''); }} // Reset size khi đổi màu
                    className={`px-4 py-2 border text-sm transition-all ${
                      selectedColor === color 
                        ? 'border-stone-900 bg-stone-900 text-white' 
                        : isColorAvailable 
                            ? 'border-stone-300 text-stone-600 hover:border-stone-900'
                            : 'border-stone-100 text-stone-300 bg-stone-50 line-through opacity-50 cursor-not-allowed'
                    }`}
                    disabled={!isColorAvailable} // Disable nếu màu này hết sạch hàng mọi size
                  >
                    {color}
                  </button>
                );
              })}
            </div>
          </div>

          {/* CHỌN SIZE (Logic hiển thị quan trọng nhất ở đây) */}
          <div className="mb-8">
            <h3 className="text-sm font-bold uppercase text-stone-900 mb-3">Kích thước: {selectedSize}</h3>
            <div className="flex flex-wrap gap-3">
              {uniqueSizes.map(size => {
                // Tìm biến thể tương ứng (Màu đang chọn + Size này)
                const variantCheck = product.variants.find(v => v.color === selectedColor && v.size === size);
                
                // Điều kiện disable:
                // 1. Chưa chọn màu.
                // 2. Không tồn tại biến thể (VD: Màu Đỏ không có Size S).
                // 3. Có biến thể nhưng inventory = 0.
                const isDisabled = !selectedColor || !variantCheck || variantCheck.inventory <= 0;

                return (
                  <button
                    key={size}
                    onClick={() => setSelectedSize(size)}
                    disabled={isDisabled}
                    className={`w-12 h-12 flex items-center justify-center border text-sm transition-all ${
                      selectedSize === size 
                        ? 'border-stone-900 bg-stone-900 text-white' 
                        : !isDisabled
                          ? 'border-stone-300 text-stone-600 hover:border-stone-900'
                          : 'border-stone-100 text-stone-300 bg-stone-50 cursor-not-allowed opacity-50 decoration-stone-400 line-through' 
                    }`}
                    title={isDisabled ? "Hết hàng" : `Còn ${variantCheck?.inventory} sản phẩm`}
                  >
                    {size}
                  </button>
                );
              })}
            </div>
            
            {/* Hiển thị số lượng tồn kho khi chọn đủ */}
            {currentVariant && (
                <div className="text-sm text-stone-500 mt-2">
                    {currentStock > 0 ? (
                        <span className="text-green-600">● Còn {currentStock} sản phẩm</span>
                    ) : (
                        <span className="text-red-500">● Hết hàng</span>
                    )}
                </div>
            )}
          </div>

          {/* NÚT MUA */}
          <div className="flex gap-4 mb-8">
            <div className="flex items-center border border-stone-300 w-32">
              <button onClick={() => setQuantity(Math.max(1, quantity - 1))} className="w-10 h-10 hover:bg-stone-100">-</button>
              <input type="text" value={quantity} readOnly className="flex-1 text-center w-full h-10 outline-none" />
              <button onClick={() => setQuantity(Math.min(currentStock || 1, quantity + 1))} className="w-10 h-10 hover:bg-stone-100">+</button>
            </div>
            <button 
              onClick={handleAddToCart}
              disabled={!currentVariant || currentStock <= 0}
              className={`flex-1 text-white uppercase tracking-widest font-bold h-12 transition-colors ${
                  !currentVariant || currentStock <= 0 
                  ? 'bg-stone-300 cursor-not-allowed' 
                  : 'bg-stone-900 hover:bg-stone-700'
              }`}
            >
              {currentStock <= 0 ? 'Hết hàng' : 'Thêm vào giỏ'}
            </button>
          </div>

          {/* Policy */}
          <div className="grid grid-cols-2 gap-4 text-xs text-stone-500">
            <div className="flex items-center gap-2"><FaTruck className="text-lg"/> Freeship đơn từ 500k</div>
            <div className="flex items-center gap-2"><FaBox className="text-lg"/> Đổi trả trong 30 ngày</div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default ProductDetail;