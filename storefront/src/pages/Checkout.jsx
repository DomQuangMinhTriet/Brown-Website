import { useState, useEffect } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { useCart } from '../context/CartContext';
import { useAuth } from '../context/AuthContext';
import axios from 'axios';
import { FaArrowLeft, FaTag, FaShippingFast, FaMoneyBillWave, FaQrcode, FaStore, FaSync } from 'react-icons/fa';

const Checkout = () => {
  const { cartItems, cartTotal, clearCart } = useCart();
  const { user, getToken } = useAuth();
  const navigate = useNavigate();
  
  // 1. LẤY THAM SỐ URL (?pos=true)
  const [searchParams] = useSearchParams();
  const isPosMode = searchParams.get('pos') === 'true';

  // --- STATE ---
  const [formData, setFormData] = useState({
    fullName: '', phone: '', email: '', address: '', note: ''
  });
  const [province, setProvince] = useState('');
  
  // Mặc định Banking, nếu là POS có thể chọn Cash
  const [paymentMethod, setPaymentMethod] = useState('banking'); 
  
  const [voucherCode, setVoucherCode] = useState('');
  const [discountAmount, setDiscountAmount] = useState(0);
  const [shippingFee, setShippingFee] = useState(0);
  const [loading, setLoading] = useState(false);

  const finalTotal = cartTotal + shippingFee - discountAmount;

  // --- EFFECT: ĐIỀU HƯỚNG ---
  useEffect(() => {
    // Chỉ đá về trang chủ nếu: Giỏ hàng trống VÀ Không phải chế độ POS
    if (cartItems.length === 0 && !isPosMode) {
        navigate('/');
    }
  }, [cartItems, navigate, isPosMode]);

  // --- EFFECT: AUTO-FILL USER ---
  useEffect(() => {
    // Chỉ auto-fill nếu không phải POS (POS thì admin tự nhập tay cho khách)
    // Hoặc nếu muốn POS auto-fill theo user đang login (Admin) thì giữ nguyên, nhưng thường POS nhập cho khách vãng lai
    if (user && !isPosMode) {
      setFormData(prev => ({
        ...prev,
        fullName: user.full_name || '',
        phone: user.phone || '',
        email: user.email || '',
        address: user.address || ''
      }));
    }
  }, [user, isPosMode]);

  // --- EFFECT: TÍNH SHIP ---
  useEffect(() => {
    const calcShip = async () => {
        if (!province) {
            setShippingFee(0);
            return;
        }
        // Nếu là POS chọn 'Nhận tại cửa hàng' (Logic giả định) hoặc tỉnh khác
        if (isPosMode && province === 'Tại cửa hàng') {
            setShippingFee(0);
            return;
        }

        try {
            const res = await axios.post('http://localhost:5000/api/shipping/calculate', {
                province: province,
                weight: cartItems.length * 500
            });
            if (res.data.success) setShippingFee(res.data.data.fee);
        } catch (err) { 
            setShippingFee(30000); // Fallback
        }
    };
    calcShip();
  }, [province, cartItems, isPosMode]);

  // --- HANDLERS ---
  const handleApplyVoucher = async () => {
    if (!voucherCode.trim()) return;
    setLoading(true);
    try {
        const token = getToken();
        const headers = token ? { Authorization: `Bearer ${token}` } : {};
        const res = await axios.post('http://localhost:5000/api/promotions/check', { 
            code: voucherCode, cartTotal 
        }, { headers });
        
        if (res.data.success) {
            setDiscountAmount(res.data.data.discount);
            alert("✅ Áp dụng mã thành công!");
        }
    } catch (error) {
        alert("❌ " + (error.response?.data?.message || "Mã không hợp lệ"));
        setDiscountAmount(0);
    } finally {
        setLoading(false);
    }
  };

  const resetForm = () => {
      setFormData({ fullName: '', phone: '', email: '', address: '', note: '' });
      setProvince('');
      setVoucherCode('');
      setDiscountAmount(0);
      setShippingFee(0);
      setPaymentMethod('banking');
  };

  const handlePlaceOrder = async (e) => {
    e.preventDefault();
    
    // Validate cơ bản
    if (!formData.fullName || !formData.phone) {
        alert("Vui lòng nhập Tên và SĐT khách hàng!");
        return;
    }
    if (!isPosMode && (!formData.address || !province)) {
        alert("Vui lòng nhập địa chỉ giao hàng!");
        return;
    }

    setLoading(true);
    try {
      const payload = {
        customer: { ...formData, province: province || 'Tại cửa hàng' },
        items: cartItems.map(item => ({
          variant_id: item.variant_id, quantity: item.quantity, price: item.price
        })),
        shipping_fee: shippingFee,
        discount_amount: discountAmount,
        total: finalTotal,
        payment_method: paymentMethod, 
        voucher_code: discountAmount > 0 ? voucherCode : null,
        source: isPosMode ? 'pos' : 'website' 
      };

      const token = getToken();
      const headers = token ? { Authorization: `Bearer ${token}` } : {};
      
      const res = await axios.post('http://localhost:5000/api/orders', payload, { headers });

      if (res.data.success) {
        // 1. Xóa giỏ hàng
        clearCart(); 

        // 2. Xử lý điều hướng
        if (isPosMode) {
            alert(`✅ [POS] Đã tạo đơn #${res.data.orderCode} thành công!`);
            // Reset form để nhập đơn mới ngay lập tức, KHÔNG reload trang để giữ ?pos=true
            resetForm();
        } else {
            alert("✅ Đặt hàng thành công! Vui lòng kiểm tra email.");
            navigate(user ? '/account' : '/');
        }
      }
    } catch (error) {
      alert("❌ Lỗi: " + (error.response?.data?.message || "Có lỗi xảy ra"));
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className={`min-h-screen py-10 px-4 md:px-6 ${isPosMode ? 'bg-stone-200' : 'bg-stone-50'}`}>
      
      {/* HEADER POS MODE */}
      {isPosMode && (
          <div className="max-w-6xl mx-auto mb-6 bg-red-600 text-white p-4 rounded-lg shadow-lg flex items-center justify-between animate-pulse">
             <span className="font-bold text-lg uppercase tracking-widest flex items-center gap-2">
                <FaStore/> CHẾ ĐỘ POS (TẠI QUẦY)
             </span>
             <div className="flex items-center gap-3">
                 <button onClick={resetForm} className="text-xs bg-white text-red-600 px-3 py-1 rounded font-bold flex items-center gap-1">
                    <FaSync/> Reset Form
                 </button>
                 <span className="text-sm bg-red-700 px-3 py-1 rounded border border-red-500">Admin Only</span>
             </div>
          </div>
      )}

      <div className="max-w-6xl mx-auto grid grid-cols-1 lg:grid-cols-2 gap-12">
        {/* FORM */}
        <div>
          {!isPosMode && (
             <Link to="/cart" className="text-sm text-stone-500 mb-6 inline-flex items-center gap-2 hover:text-stone-900"><FaArrowLeft /> Quay lại giỏ hàng</Link>
          )}
          
          <form id="checkout-form" onSubmit={handlePlaceOrder} className="space-y-6">
            <div className="bg-white p-6 rounded shadow-sm border border-stone-100">
                <h2 className="text-lg font-bold mb-4">1. Thông tin khách hàng</h2>
                <div className="space-y-4">
                    <input name="fullName" placeholder="Họ và tên khách" className="w-full p-3 border rounded" value={formData.fullName} onChange={e => setFormData({...formData, fullName: e.target.value})} required />
                    <div className="grid grid-cols-2 gap-4">
                        <input name="phone" placeholder="Số điện thoại" className="w-full p-3 border rounded" value={formData.phone} onChange={e => setFormData({...formData, phone: e.target.value})} required />
                        <input name="email" placeholder="Email (Không bắt buộc)" className="w-full p-3 border rounded" value={formData.email} onChange={e => setFormData({...formData, email: e.target.value})} />
                    </div>

                    {/* Địa chỉ: Bắt buộc nếu Online, Tùy chọn nếu POS */}
                    <select className="w-full p-3 border rounded bg-white" value={province} onChange={e => setProvince(e.target.value)} required={!isPosMode}>
                        <option value="">-- Chọn Tỉnh / Thành phố --</option>
                        {isPosMode && <option value="Tại cửa hàng">⭐ Khách mua tại cửa hàng (No Ship)</option>}
                        <option value="Hồ Chí Minh">Hồ Chí Minh</option>
                        <option value="Hà Nội">Hà Nội</option>
                        <option value="Đà Nẵng">Đà Nẵng</option>
                        <option value="Khác">Tỉnh khác...</option>
                    </select>
                    
                    <input name="address" placeholder="Địa chỉ chi tiết" className="w-full p-3 border rounded" value={formData.address} onChange={e => setFormData({...formData, address: e.target.value})} required={!isPosMode} />
                    <textarea name="note" placeholder="Ghi chú đơn hàng" className="w-full p-3 border rounded" value={formData.note} onChange={e => setFormData({...formData, note: e.target.value})}></textarea>
                </div>
            </div>

            <div className="bg-white p-6 rounded shadow-sm border border-stone-100">
                <h2 className="text-lg font-bold mb-4">2. Thanh toán</h2>
                <div className="space-y-3">
                    {/* OPTION 1: QR (Luôn hiện) */}
                    <div onClick={() => setPaymentMethod('banking')} className={`p-4 border rounded cursor-pointer flex items-center gap-3 ${paymentMethod === 'banking' ? 'border-stone-900 bg-stone-50 ring-1 ring-stone-900' : 'hover:bg-stone-50'}`}>
                        <FaQrcode className="text-xl"/>
                        <div>
                            <p className="font-bold text-sm">Chuyển khoản QR</p>
                            <p className="text-xs text-stone-500">Khách quét mã VietQR</p>
                        </div>
                    </div>

                    {/* OPTION 2: TIỀN MẶT (Chỉ POS) */}
                    {isPosMode && (
                        <div onClick={() => setPaymentMethod('cash')} className={`p-4 border rounded cursor-pointer flex items-center gap-3 ${paymentMethod === 'cash' ? 'border-green-600 bg-green-50 ring-1 ring-green-600' : 'hover:bg-green-50'}`}>
                            <FaMoneyBillWave className="text-xl text-green-600"/>
                            <div>
                                <p className="font-bold text-sm text-green-700">Tiền mặt / Đã thanh toán</p>
                                <p className="text-xs text-green-600">Thu tiền trực tiếp tại quầy</p>
                            </div>
                        </div>
                    )}
                </div>

                {/* HIỂN THỊ ẢNH QR */}
                {paymentMethod === 'banking' && (
                    <div className="mt-6 text-center">
                        <p className="text-sm text-stone-500 mb-3">Mở App Ngân hàng để quét mã</p>
                        <div className="w-48 h-48 mx-auto bg-stone-100 border p-1">
                             {/* Đường dẫn ảnh trong thư mục public */}
                            <img src="/QR.jpg" alt="QR Code" className="w-full h-full object-contain" 
                                onError={(e) => {e.target.onerror = null; e.target.src="https://placehold.co/200x200?text=QR+Lỗi"}}
                            />
                        </div>
                        <p className="mt-2 font-bold text-xl">{new Intl.NumberFormat('vi-VN').format(finalTotal)} ₫</p>
                    </div>
                )}
            </div>
          </form>
        </div>

        {/* TÓM TẮT ĐƠN HÀNG */}
        <div className="h-fit sticky top-4">
            <div className="bg-white p-6 rounded shadow-sm">
                <h3 className="font-bold mb-6 border-b pb-4">Giỏ hàng ({cartItems.length} món)</h3>
                
                <div className="space-y-4 mb-6 max-h-80 overflow-y-auto">
                    {cartItems.length === 0 ? (
                        <p className="text-stone-400 text-center italic">Chưa có sản phẩm nào. {isPosMode && "Hãy thêm vào giỏ ở tab khác."}</p>
                    ) : (
                        cartItems.map(item => (
                        <div key={item.variant_id} className="flex justify-between text-sm">
                            <span>{item.name} ({item.size}/{item.color}) x {item.quantity}</span>
                            <span className="font-medium">{new Intl.NumberFormat('vi-VN').format(item.price * item.quantity)} ₫</span>
                        </div>
                        ))
                    )}
                </div>

                <div className="flex gap-2 mb-4">
                     <input className="border p-2 w-full rounded uppercase" placeholder="MÃ GIẢM GIÁ" value={voucherCode} onChange={e=>setVoucherCode(e.target.value)} />
                     <button type="button" onClick={handleApplyVoucher} className="bg-stone-200 px-4 rounded font-bold hover:bg-stone-300">Áp dụng</button>
                </div>

                <div className="border-t pt-4 space-y-2">
                    <div className="flex justify-between"><span>Tạm tính</span><span>{new Intl.NumberFormat('vi-VN').format(cartTotal)} ₫</span></div>
                    <div className="flex justify-between"><span>Ship</span><span>{new Intl.NumberFormat('vi-VN').format(shippingFee)} ₫</span></div>
                    {discountAmount > 0 && <div className="flex justify-between text-green-600"><span>Giảm giá</span><span>-{new Intl.NumberFormat('vi-VN').format(discountAmount)} ₫</span></div>}
                    <div className="flex justify-between font-bold text-xl mt-4"><span>Tổng cộng</span><span>{new Intl.NumberFormat('vi-VN').format(finalTotal)} ₫</span></div>
                </div>

                <button type="submit" form="checkout-form" disabled={loading || cartItems.length === 0} className={`w-full mt-6 text-white py-4 font-bold rounded uppercase shadow-lg ${isPosMode ? 'bg-green-700 hover:bg-green-800' : 'bg-stone-900 hover:bg-stone-800'} disabled:bg-stone-300`}>
                    {loading ? 'Đang xử lý...' : isPosMode ? 'HOÀN TẤT ĐƠN POS' : 'ĐẶT HÀNG'}
                </button>
            </div>
        </div>
      </div>
    </div>
  );
};

export default Checkout;