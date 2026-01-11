import { useState, useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useCart } from '../context/CartContext';
import axios from 'axios';
import { FaArrowLeft } from 'react-icons/fa';

const Checkout = () => {
  const { cartItems, cartTotal, clearCart } = useCart();
  const navigate = useNavigate();

  const [formData, setFormData] = useState({
    fullName: '', phone: '', email: '', address: '', note: ''
  });

  useEffect(() => {
    if (cartItems.length === 0) navigate('/');
  }, [cartItems, navigate]);

  const handlePlaceOrder = async (e) => {
    e.preventDefault();
    
    if (!formData.fullName || !formData.phone || !formData.address) {
      alert("Vui lòng điền đầy đủ thông tin giao hàng!");
      return;
    }

    try {
      const payload = {
        customer: formData,
        total: cartTotal,
        payment_method: 'COD',
        items: cartItems.map(item => ({
          variant_id: item.variant_id,
          quantity: item.quantity,
          price: item.price
        }))
      };

      const res = await axios.post('http://localhost:5000/api/orders', payload);

      if (res.data.success) {
        alert(`✅ Cảm ơn ${formData.fullName}! Đơn hàng #${res.data.orderCode} đã đặt thành công.`);
        
        // GỌI HÀM XÓA GIỎ
        clearCart();
        
        // CHUYỂN VỀ TRANG CHỦ
        navigate('/');
      }
    } catch (error) {
      console.error(error);
      alert("❌ Lỗi đặt hàng: " + (error.response?.data?.message || "Có lỗi xảy ra"));
    }
  };

  return (
    <div className="min-h-screen bg-stone-50 py-10 px-6">
      <div className="max-w-6xl mx-auto grid grid-cols-1 lg:grid-cols-2 gap-12">
        {/* Cột trái: Form */}
        <div>
          <Link to="/cart" className="text-sm text-stone-500 mb-6 inline-block">← Quay lại giỏ hàng</Link>
          <h2 className="text-2xl font-bold mb-6">BROWN FASHION</h2>
          <form id="checkout-form" onSubmit={handlePlaceOrder} className="space-y-4">
            <input name="fullName" placeholder="Họ và tên" className="w-full p-3 border rounded" onChange={e => setFormData({...formData, fullName: e.target.value})} required />
            <div className="grid grid-cols-2 gap-4">
               <input name="email" placeholder="Email" className="w-full p-3 border rounded" onChange={e => setFormData({...formData, email: e.target.value})} />
               <input name="phone" placeholder="Số điện thoại" className="w-full p-3 border rounded" onChange={e => setFormData({...formData, phone: e.target.value})} required />
            </div>
            <input name="address" placeholder="Địa chỉ nhận hàng" className="w-full p-3 border rounded" onChange={e => setFormData({...formData, address: e.target.value})} required />
            <textarea name="note" placeholder="Ghi chú" className="w-full p-3 border rounded" onChange={e => setFormData({...formData, note: e.target.value})}></textarea>
          </form>
        </div>

        {/* Cột phải: Tóm tắt & Nút bấm */}
        <div className="bg-white p-8 rounded shadow h-fit">
          <h3 className="font-bold mb-6">Đơn hàng ({cartItems.length} món)</h3>
          <div className="space-y-4 mb-6 max-h-60 overflow-y-auto">
            {cartItems.map(item => (
              <div key={item.variant_id} className="flex justify-between text-sm">
                <span>{item.name} ({item.size}/{item.color}) x {item.quantity}</span>
                <span className="font-medium">{new Intl.NumberFormat('vi-VN').format(item.price * item.quantity)} ₫</span>
              </div>
            ))}
          </div>
          <div className="flex justify-between font-bold text-xl mb-6 pt-4 border-t">
            <span>Tổng cộng</span>
            <span>{new Intl.NumberFormat('vi-VN').format(cartTotal)} ₫</span>
          </div>
          <div className="mb-6 p-3 bg-stone-50 border rounded text-sm">
             ● Thanh toán khi nhận hàng (COD)
          </div>
          <button type="submit" form="checkout-form" className="w-full bg-stone-900 text-white py-4 font-bold rounded uppercase hover:bg-stone-800">
            Hoàn tất đơn hàng
          </button>
        </div>
      </div>
    </div>
  );
};

export default Checkout;