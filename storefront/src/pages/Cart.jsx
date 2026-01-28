import { Link } from 'react-router-dom';
import { useCart } from '../context/CartContext';
import { FaTrash, FaArrowRight } from 'react-icons/fa';

const Cart = () => {
  const { cartItems, removeFromCart, updateQuantity, cartTotal } = useCart();

  if (cartItems.length === 0) {
    return (
      <div className="min-h-[60vh] flex flex-col items-center justify-center text-center px-4">
        <h2 className="text-2xl font-serif text-stone-800 mb-4">Giỏ hàng của bạn đang trống</h2>
        <p className="text-stone-500 mb-8">Hãy khám phá bộ sưu tập mới nhất của chúng tôi.</p>
        <Link to="/" className="bg-stone-900 text-white px-8 py-3 uppercase tracking-wider text-sm hover:bg-stone-700">
          Mua sắm ngay
        </Link>
      </div>
    );
  }

  return (
    <div className="max-w-7xl mx-auto px-6 py-10 md:py-16">
      <h1 className="text-3xl font-serif text-stone-900 mb-10 text-center">Giỏ Hàng</h1>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-12">
        {/* DANH SÁCH SẢN PHẨM */}
        <div className="lg:col-span-2 space-y-6">
          {cartItems.map((item) => (
            <div key={item.variant_id} className="flex gap-6 py-6 border-b border-stone-100">
              {/* Ảnh */}
              <Link to={`/product/${item.slug}`} className="w-24 h-32 bg-stone-100 flex-shrink-0">
                <img src={item.image} alt={item.name} className="w-full h-full object-cover" />
              </Link>

              {/* Thông tin */}
              <div className="flex-1 flex flex-col justify-between">
                <div>
                  <div className="flex justify-between items-start">
                    <Link to={`/product/${item.slug}`} className="font-medium text-stone-800 hover:text-stone-600">
                      {item.name}
                    </Link>
                    <button onClick={() => removeFromCart(item.variant_id)} className="text-stone-400 hover:text-red-500">
                      <FaTrash size={14} />
                    </button>
                  </div>
                  <p className="text-sm text-stone-500 mt-1">{item.size} / {item.color}</p>
                </div>

                <div className="flex justify-between items-end">
                  <div className="flex items-center border border-stone-200">
                    <button onClick={() => updateQuantity(item.variant_id, item.quantity - 1)} className="w-8 h-8 flex items-center justify-center hover:bg-stone-50">-</button>
                    <span className="w-10 text-center text-sm">{item.quantity}</span>
                    <button onClick={() => updateQuantity(item.variant_id, item.quantity + 1)} className="w-8 h-8 flex items-center justify-center hover:bg-stone-50">+</button>
                  </div>
                  <span className="font-medium text-stone-900">
                    {new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(item.price * item.quantity)}
                  </span>
                </div>
              </div>
            </div>
          ))}
        </div>

        {/* TỔNG TIỀN & THANH TOÁN */}
        <div className="lg:col-span-1">
          <div className="bg-stone-50 p-6 rounded-lg sticky top-24">
            <h3 className="font-bold text-stone-900 uppercase tracking-wider mb-6">Tóm tắt đơn hàng</h3>
            
            <div className="flex justify-between mb-4 text-stone-600">
              <span>Tạm tính</span>
              <span>{new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(cartTotal)}</span>
            </div>
            <div className="flex justify-between mb-4 text-stone-600">
              <span>Vận chuyển</span>
              <span>{new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(20000)}</span>
            </div>
            
            <hr className="border-stone-200 my-4" />
            
            <div className="flex justify-between mb-8 text-lg font-bold text-stone-900">
              <span>Tổng cộng</span>
              <span>{new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(cartTotal)}</span>
            </div>

            <Link to="/checkout" className="block w-full bg-stone-900 text-white text-center py-4 uppercase tracking-widest text-sm font-bold hover:bg-stone-800 transition-colors flex items-center justify-center gap-2">
              Thanh toán <FaArrowRight />
            </Link>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Cart;