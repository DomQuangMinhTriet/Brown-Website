import { useState, useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useCart } from '../context/CartContext';
import { useAuth } from '../context/AuthContext';
import axios from 'axios';
<<<<<<< Updated upstream
<<<<<<< Updated upstream
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
=======
import { FaArrowLeft, FaMoneyBillWave, FaQrcode, FaCheckCircle, FaCopy } from 'react-icons/fa';
=======
import { FaArrowLeft, FaCheckCircle, FaExclamationCircle } from 'react-icons/fa';
>>>>>>> Stashed changes
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
<<<<<<< Updated upstream
      console.error(error);
      toast.error(error.response?.data?.message || "Có lỗi xảy ra khi đặt hàng");
>>>>>>> Stashed changes
=======
        console.error(error);
        toast.error(error.response?.data?.message || "Lỗi khi đặt hàng. Vui lòng thử lại.");
>>>>>>> Stashed changes
    } finally {
        setLoading(false);
    }
  };

<<<<<<< Updated upstream
<<<<<<< Updated upstream
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
=======
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

=======
>>>>>>> Stashed changes
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

<<<<<<< Updated upstream
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
>>>>>>> Stashed changes
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
>>>>>>> Stashed changes
        </div>
    </div>
  );
};

export default Checkout;