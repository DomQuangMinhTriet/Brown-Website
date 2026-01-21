import { useState, useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useCart } from '../context/CartContext';
import { useAuth } from '../context/AuthContext';
import axios from 'axios';
import { FaArrowLeft, FaMoneyBillWave, FaQrcode, FaCheckCircle, FaCopy } from 'react-icons/fa';
import { toast } from 'react-toastify';

// --- CẤU HÌNH TÀI KHOẢN NHẬN TIỀN ---
const MY_BANK = {
  BANK_ID: 'SACOMBANK', // Mã ngân hàng (MB, VCB, TCB, ACB, VPB...)
  ACCOUNT_NO: '0902173763', // Số tài khoản của bạn
  ACCOUNT_NAME: 'LUU THI PHUONG QUYNH', // Tên chủ tài khoản
  TEMPLATE: 'compact' // Giao diện QR
};

const Checkout = () => {
  const { cartItems, cartTotal, clearCart } = useCart();
  const { user } = useAuth();
  const navigate = useNavigate();
  
  // Form State
  const [formData, setFormData] = useState({ fullName: '', phone: '', email: '', address: '', note: '' });
  
  // Payment Method: Khóa cứng là 'banking'
  const [paymentMethod] = useState('banking'); 
  
  const [shippingFee] = useState(30000); // Phí mặc định 30k (Backend sẽ xử lý an toàn)
  const [loading, setLoading] = useState(false);

  // Auto-fill nếu đã đăng nhập
  useEffect(() => {
    if (user) {
      setFormData(prev => ({
        ...prev,
        fullName: user.full_name || '',
        phone: user.phone || '',
        email: user.email || '',
        address: user.address || ''
      }));
    }
  }, [user]);

  // Nếu giỏ hàng rỗng -> Quay về
  useEffect(() => {
    if (cartItems.length === 0) navigate('/cart');
  }, [cartItems, navigate]);

  const finalTotal = cartTotal + shippingFee;

  // --- TẠO LINK QR CODE (VIETQR) ---
  // Nội dung CK: "SDT + Ten" (Để dễ đối soát)
  const transferContent = `${formData.phone} ${formData.fullName}`.trim().replace(/\s+/g, '%20').toUpperCase();
  const qrUrl = `https://img.vietqr.io/image/${MY_BANK.BANK_ID}-${MY_BANK.ACCOUNT_NO}-${MY_BANK.TEMPLATE}.png?amount=${finalTotal}&addInfo=${transferContent}`;

  const handleSubmit = async (e) => {
    e.preventDefault();
    
    if (!formData.fullName || !formData.phone || !formData.address) {
        toast.warning("Vui lòng điền đầy đủ thông tin giao hàng!");
        return;
    }

    setLoading(true);

    try {
        const payload = {
            customer: {
                fullName: formData.fullName,
                phone: formData.phone,
                email: formData.email,
                address: formData.address,
                // Frontend hiện tại chưa có dropdown chọn Quận/Huyện nên gửi rỗng
                province: "", district: "", ward: "" 
            },
            items: cartItems,
            payment_method: 'banking', // Chỉ gửi banking
            shipping_fee: shippingFee,
            note: formData.note
        };

        const res = await axios.post('http://localhost:5000/api/orders', payload);
        
        if (res.data.success) {
            toast.success("🎉 Đặt hàng thành công! Chúng tôi sẽ kiểm tra khoản chuyển và gửi hàng.");
            clearCart();
            navigate(user ? '/account' : '/');
        }

    } catch (error) {
        console.error(error);
        toast.error(error.response?.data?.message || "Lỗi khi đặt hàng. Vui lòng thử lại.");

    } finally {
        setLoading(false);
    }
  };

  return (
    <div className="max-w-6xl mx-auto px-6 py-10">
        <Link to="/cart" className="flex items-center text-stone-500 hover:text-stone-900 mb-8 w-fit">
            <FaArrowLeft className="mr-2" /> Quay lại giỏ hàng
        </Link>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-12">
            
            {/* CỘT TRÁI: THÔNG TIN GIAO HÀNG */}
            <div>
                <h2 className="text-xl font-serif font-bold text-stone-900 mb-6 uppercase tracking-wider">1. Thông tin giao hàng</h2>
                <form id="checkout-form" onSubmit={handleSubmit} className="space-y-4">
                    <input 
                        type="text" placeholder="Họ và tên" required
                        className="w-full p-3 border border-stone-200 rounded focus:border-stone-900 outline-none"
                        value={formData.fullName} onChange={e => setFormData({...formData, fullName: e.target.value})}
                    />
                    <div className="grid grid-cols-2 gap-4">
                        <input 
                            type="text" placeholder="Số điện thoại" required
                            className="w-full p-3 border border-stone-200 rounded focus:border-stone-900 outline-none"
                            value={formData.phone} onChange={e => setFormData({...formData, phone: e.target.value})}
                        />
                         <input 
                            type="email" placeholder="Email (để nhận thông báo)"
                            className="w-full p-3 border border-stone-200 rounded focus:border-stone-900 outline-none"
                            value={formData.email} onChange={e => setFormData({...formData, email: e.target.value})}
                        />
                    </div>
                    <input 
                        type="text" placeholder="Địa chỉ nhận hàng (Số nhà, Đường, Quận/Huyện...)" required
                        className="w-full p-3 border border-stone-200 rounded focus:border-stone-900 outline-none"
                        value={formData.address} onChange={e => setFormData({...formData, address: e.target.value})}
                    />
                    <textarea 
                        placeholder="Ghi chú đơn hàng (Tùy chọn)"
                        className="w-full p-3 border border-stone-200 rounded focus:border-stone-900 outline-none h-24 resize-none"
                        value={formData.note} onChange={e => setFormData({...formData, note: e.target.value})}
                    ></textarea>
                </form>
            </div>

            {/* CỘT PHẢI: QUÉT MÃ QR */}
            <div className="h-fit">
                 <h2 className="text-xl font-serif font-bold text-stone-900 mb-6 uppercase tracking-wider">2. Thanh toán QR Code</h2>
                 
                 <div className="bg-white p-6 rounded-xl shadow-lg border border-stone-100 text-center">
                    
                    {formData.phone ? (
                        <>
                            <p className="text-sm text-stone-500 mb-4">Vui lòng quét mã bên dưới để thanh toán</p>
                            <div className="flex justify-center mb-4">
                                <img src={qrUrl} alt="VietQR" className="w-56 h-56 object-contain border border-stone-200 rounded-lg" />
                            </div>
                            
                            <div className="bg-stone-50 p-4 rounded text-left text-sm space-y-2 mb-6">
                                <div className="flex justify-between">
                                    <span className="text-stone-500">Tổng thanh toán:</span>
                                    <span className="font-bold text-xl text-stone-900">{new Intl.NumberFormat('vi-VN').format(finalTotal)} ₫</span>
                                </div>
                                <div className="flex justify-between">
                                    <span className="text-stone-500">Chủ tài khoản:</span>
                                    <span className="font-medium">{MY_BANK.ACCOUNT_NAME}</span>
                                </div>
                                <div className="flex justify-between">
                                    <span className="text-stone-500">Nội dung CK:</span>
                                    <span className="font-medium text-blue-600">{formData.phone} {formData.fullName}</span>
                                </div>
                            </div>
                        </>
                    ) : (
                        <div className="h-48 flex flex-col items-center justify-center bg-stone-50 rounded text-stone-400 mb-6">
                            <FaExclamationCircle className="text-2xl mb-2"/>
                            <span>Nhập thông tin giao hàng để hiện mã QR</span>
                        </div>
                    )}
=======
                    <button 
                        type="submit" 
                        form="checkout-form" 
                        disabled={loading} 
                        className="w-full bg-stone-900 text-white py-4 font-bold rounded uppercase hover:bg-stone-800 disabled:opacity-70 transition-all flex items-center justify-center gap-2"
                    >
                        {loading ? 'Đang xử lý...' : <><FaCheckCircle/> Tôi đã chuyển khoản & Đặt hàng</>}
                    </button>
                    
                    <p className="text-xs text-stone-400 mt-4 italic">
                        *Lưu ý: Đơn hàng sẽ được xử lý sau khi hệ thống nhận được thanh toán.
                    </p>
                 </div>
            </div>
        </div>
    </div>
  );
};

export default Checkout;