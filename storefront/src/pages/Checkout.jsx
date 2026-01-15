import { useState, useEffect } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { useCart } from '../context/CartContext';
import { useAuth } from '../context/AuthContext';
import axios from 'axios';
import { FaArrowLeft, FaMoneyBillWave, FaQrcode, FaCheckCircle, FaCopy } from 'react-icons/fa';
import { toast } from 'react-toastify';

// --- CẤU HÌNH NGÂN HÀNG CỦA BẠN TẠI ĐÂY ---
const MY_BANK = {
  BANK_ID: 'SCB', // Ví dụ: MB, VCB, TCB, ACB, VIB, TPB...
  ACCOUNT_NO: '0902173763', // Thay bằng số tài khoản thật của bạn
  ACCOUNT_NAME: 'LUU THI PHUONG QUYNH' // Tên chủ tài khoản
};

const Checkout = () => {
  const { cartItems, cartTotal, clearCart } = useCart();
  const { user } = useAuth();
  const navigate = useNavigate();
  
  // State Form
  const [formData, setFormData] = useState({ fullName: '', phone: '', email: '', address: '', note: '' });
  const [paymentMethod, setPaymentMethod] = useState('cod'); 
  
  // --- STATE KHUYẾN MÃI (MỚI) ---
  const [voucherCode, setVoucherCode] = useState('');
  const [discountAmount, setDiscountAmount] = useState(0);
  const [appliedVoucher, setAppliedVoucher] = useState(null); // Lưu mã đã áp dụng thành công

  // State Tính toán & UI
  const [shippingFee, setShippingFee] = useState(30000); 
  const [loading, setLoading] = useState(false);
  const [orderSuccess, setOrderSuccess] = useState(null);

  // Tự động điền nếu đã đăng nhập
  useEffect(() => {
    if (user) {
      setFormData({
        fullName: user.full_name || '',
        phone: user.phone || '',
        email: user.email || '',
        address: user.address || '',
        note: ''
      });
    }
  }, [user]);

  // --- LOGIC CHECK VOUCHER (MỚI) ---
  const handleApplyVoucher = async () => {
    if (!voucherCode.trim()) return;
    try {
        const res = await axios.post('http://localhost:5000/api/promotions/check', {
            code: voucherCode,
            cartTotal: cartTotal
        });

        if (res.data.success) {
            setDiscountAmount(res.data.data.discountAmount);
            setAppliedVoucher(res.data.data.code);
            toast.success(`Đã áp dụng mã ${res.data.data.code}: -${new Intl.NumberFormat().format(res.data.data.discountAmount)}đ`);
        }
    } catch (error) {
        setDiscountAmount(0);
        setAppliedVoucher(null);
        toast.error(error.response?.data?.message || "Mã không hợp lệ");
    }
  };

  // Tính tổng cuối cùng
  const finalTotal = cartTotal + shippingFee - discountAmount;

  // Xử lý Đặt hàng
  const handlePlaceOrder = async (e) => {
    e.preventDefault();
    setLoading(true);

    try {
      const payload = {
        customer: formData,
        items: cartItems,
        payment_method: paymentMethod,
        voucher_code: appliedVoucher, // Gửi mã đã áp dụng lên server
        shipping_fee: shippingFee,
        note: formData.note
      };

      const res = await axios.post('http://localhost:5000/api/orders', payload, {
        headers: { Authorization: user ? `Bearer ${localStorage.getItem('sb-token')}` : '' }
      });

      if (res.data.success) {
        clearCart();
        setOrderSuccess({
          code: res.data.orderCode,
          total: finalTotal,
          payment_method: paymentMethod
        });
      }
    } catch (error) {
      console.error(error);
      toast.error(error.response?.data?.message || "Có lỗi xảy ra khi đặt hàng");
    } finally {
      setLoading(false);
    }
  };

  // --- MÀN HÌNH THÀNH CÔNG (VIETQR) ---
  if (orderSuccess) {
    const qrUrl = `https://img.vietqr.io/image/${MY_BANK.BANK_ID}-${MY_BANK.ACCOUNT_NO}-compact.jpg?amount=${orderSuccess.total}&addInfo=${orderSuccess.code}&accountName=${encodeURIComponent(MY_BANK.ACCOUNT_NAME)}`;

    return (
      <div className="min-h-screen bg-stone-50 flex items-center justify-center p-4">
        <div className="bg-white p-8 rounded-xl shadow-lg max-w-lg w-full text-center">
          <FaCheckCircle className="text-green-500 text-5xl mx-auto mb-4" />
          <h2 className="text-2xl font-bold text-stone-800 mb-2">Đặt hàng thành công!</h2>
          <p className="text-stone-500 mb-6">Mã đơn hàng: <span className="font-bold text-stone-900">{orderSuccess.code}</span></p>

          {orderSuccess.payment_method === 'banking' ? (
            <div className="bg-stone-50 p-6 rounded-lg border border-stone-200 mb-6">
              <p className="text-sm font-bold text-stone-700 uppercase mb-4">Quét mã để thanh toán</p>
              <img src={qrUrl} alt="VietQR" className="w-48 h-48 mx-auto mb-4 border border-stone-200 rounded" />
              <div className="text-sm text-stone-600 space-y-2 text-left bg-white p-3 rounded border border-stone-100">
                <p className="flex justify-between"><span>Ngân hàng:</span> <span className="font-bold">{MY_BANK.BANK_ID}</span></p>
                <p className="flex justify-between"><span>Số tài khoản:</span> <span className="font-bold">{MY_BANK.ACCOUNT_NO}</span></p>
                <p className="flex justify-between"><span>Số tiền:</span> <span className="font-bold text-red-600">{new Intl.NumberFormat('vi-VN').format(orderSuccess.total)} đ</span></p>
                <p className="flex justify-between"><span>Nội dung:</span> <span className="font-bold text-blue-600">{orderSuccess.code}</span></p>
              </div>
            </div>
          ) : (
            <div className="bg-blue-50 text-blue-800 p-4 rounded-lg mb-6 text-sm">
              Đơn hàng sẽ được thanh toán khi nhận hàng (COD).
            </div>
          )}

          <div className="flex gap-3">
            <button onClick={() => navigate('/')} className="flex-1 px-4 py-3 bg-stone-100 text-stone-700 font-bold rounded hover:bg-stone-200">Về trang chủ</button>
          </div>
        </div>
      </div>
    );
  }

  // --- MÀN HÌNH CHECKOUT ---
  if (cartItems.length === 0) return <div className="text-center p-10">Giỏ hàng trống <Link to="/" className="underline">Mua ngay</Link></div>;

  return (
    <div className="min-h-screen bg-stone-50 py-10 px-4 md:px-8">
      <div className="max-w-6xl mx-auto grid grid-cols-1 lg:grid-cols-2 gap-10">
        
        {/* CỘT TRÁI: FORM */}
        <div>
          <div className="flex items-center gap-2 mb-6 text-stone-500 cursor-pointer" onClick={() => navigate('/cart')}>
             <FaArrowLeft /> Quay lại giỏ hàng
          </div>
          <h2 className="text-2xl font-bold text-stone-900 mb-6 uppercase">Thông tin giao hàng</h2>
          
          <form id="checkout-form" onSubmit={handlePlaceOrder} className="space-y-4">
             <input type="text" placeholder="Họ và tên" required className="w-full p-4 border rounded" value={formData.fullName} onChange={e => setFormData({...formData, fullName: e.target.value})} />
             <div className="grid grid-cols-2 gap-4">
                <input type="email" placeholder="Email" required className="w-full p-4 border rounded" value={formData.email} onChange={e => setFormData({...formData, email: e.target.value})} />
                <input type="tel" placeholder="SĐT" required className="w-full p-4 border rounded" value={formData.phone} onChange={e => setFormData({...formData, phone: e.target.value})} />
             </div>
             <input type="text" placeholder="Địa chỉ" required className="w-full p-4 border rounded" value={formData.address} onChange={e => setFormData({...formData, address: e.target.value})} />
             <textarea placeholder="Ghi chú" rows="3" className="w-full p-4 border rounded" value={formData.note} onChange={e => setFormData({...formData, note: e.target.value})} />
          </form>

          <div className="mt-8">
             <h3 className="font-bold text-stone-800 mb-4 uppercase text-sm">Thanh toán</h3>
             <div className="space-y-3">
                 <label className={`flex items-center gap-4 p-4 border rounded cursor-pointer ${paymentMethod === 'banking' ? 'border-stone-900 bg-stone-50' : ''}`}>
                    <input type="radio" name="payment" value="banking" checked={paymentMethod === 'banking'} onChange={() => setPaymentMethod('banking')} className="accent-stone-900 w-5 h-5"/>
                    <div className="flex items-center gap-3"><FaQrcode className="text-xl"/><span>Chuyển khoản VietQR</span></div>
                 </label>
                 <label className={`flex items-center gap-4 p-4 border rounded cursor-pointer ${paymentMethod === 'cod' ? 'border-stone-900 bg-stone-50' : ''}`}>
                    <input type="radio" name="payment" value="cod" checked={paymentMethod === 'cod'} onChange={() => setPaymentMethod('cod')} className="accent-stone-900 w-5 h-5"/>
                    <div className="flex items-center gap-3"><FaMoneyBillWave className="text-xl text-green-600"/><span>Thanh toán khi nhận hàng (COD)</span></div>
                 </label>
             </div>
          </div>
        </div>

        {/* CỘT PHẢI: TÓM TẮT */}
        <div className="bg-white p-8 rounded-xl shadow-sm h-fit border border-stone-100">
             <h3 className="font-bold text-stone-800 mb-6 uppercase border-b pb-4">Đơn hàng ({cartItems.length} món)</h3>
             <div className="space-y-4 mb-6 max-h-80 overflow-y-auto pr-2">
                {cartItems.map((item, idx) => (
                    <div key={idx} className="flex gap-4">
                        <img src={item.image} className="w-16 h-20 object-cover rounded bg-stone-100"/>
                        <div className="flex-1">
                            <p className="font-medium text-sm">{item.name}</p>
                            <p className="text-xs text-stone-500">{item.size} / {item.color}</p>
                        </div>
                        <p className="font-medium text-sm">{new Intl.NumberFormat('vi-VN').format(item.price * item.quantity)} ₫</p>
                    </div>
                ))}
             </div>
             
             {/* --- VOUCHER INPUT (MỚI) --- */}
             <div className="flex gap-2 mb-6">
                 <input 
                    type="text" placeholder="Mã giảm giá" 
                    className="flex-1 p-3 border border-stone-200 rounded outline-none uppercase font-mono text-sm focus:border-stone-900"
                    value={voucherCode} onChange={e=>setVoucherCode(e.target.value.toUpperCase())}
                 />
                 <button 
                    type="button" 
                    onClick={handleApplyVoucher}
                    className="bg-stone-200 px-4 rounded font-bold text-stone-600 hover:bg-stone-300 text-sm transition-colors"
                 >
                    Áp dụng
                 </button>
             </div>

             <div className="space-y-3 pt-4 border-t border-stone-100 text-sm text-stone-600">
                <div className="flex justify-between"><span>Tạm tính</span><span>{new Intl.NumberFormat('vi-VN').format(cartTotal)} ₫</span></div>
                <div className="flex justify-between"><span>Phí vận chuyển</span><span>{new Intl.NumberFormat('vi-VN').format(shippingFee)} ₫</span></div>
                
                {/* HIỂN THỊ TIỀN GIẢM */}
                {discountAmount > 0 && (
                    <div className="flex justify-between text-green-600 font-bold">
                        <span>Voucher ({appliedVoucher})</span>
                        <span>-{new Intl.NumberFormat('vi-VN').format(discountAmount)} ₫</span>
                    </div>
                )}
             </div>
             
             <div className="flex justify-between items-center mt-6 pt-4 border-t border-stone-100">
                <span className="text-stone-500">Tổng cộng</span>
                <span className="text-2xl font-bold text-stone-900">{new Intl.NumberFormat('vi-VN').format(finalTotal)} ₫</span>
             </div>

             <button type="submit" form="checkout-form" disabled={loading} className="w-full mt-6 bg-stone-900 text-white py-4 font-bold rounded uppercase hover:bg-stone-800 disabled:opacity-70">
                {loading ? 'Đang xử lý...' : 'ĐẶT HÀNG'}
             </button>
        </div>
      </div>
    </div>
  );
};

export default Checkout;