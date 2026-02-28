import { useState, useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useCart } from '../context/CartContext';
import { useAuth } from '../context/AuthContext';
import axios from 'axios';
import { FaArrowLeft, FaCheckCircle, FaExclamationCircle, FaTimes, FaTag, FaCalendarAlt } from 'react-icons/fa';
import { toast } from 'react-toastify';
import { useLanguage } from '../context/LanguageContext';
import { formatPrice } from '../utils/currencyHelper';

// --- CẤU HÌNH TÀI KHOẢN NHẬN TIỀN ---
const MY_BANK = {
  BANK_ID: 'SACOMBANK', 
  ACCOUNT_NO: '0902173763', 
  ACCOUNT_NAME: 'LUU THI PHUONG QUYNH', 
  TEMPLATE: 'compact' 
};

// --- CẤU HÌNH TÀI KHOẢN NHẬN TIỀN QUỐC TẾ (SWIFT) ---
const INTL_BANK = {
  BANK_NAME: 'Techcombank',
  SWIFT_CODE: 'VTCBVNVX',
  ACCOUNT_NAME: 'Le Thi My Nhi',
  ACCOUNT_NO: '19037727414020',
  ADDRESS: '15 Nguyen Xuan Khoat street, Tan Son Nhi ward, Tan Phu District, Ho Chi Minh City',
  POST_CODE: '700000'
};

// CẤU HÌNH API GHN ĐỂ LẤY ĐỊA CHỈ CHUẨN
const GHN_TOKEN = '7a83a4ad-f72f-11f0-835a-aa01149835ce'; 
const GHN_API_BASE = 'https://online-gateway.ghn.vn/shiip/public-api/master-data';

// Thêm danh sách Quốc gia cơ bản (Có gắn kèm phí ship giả lập)
const COUNTRY_LIST = [
  { code: 'US', name: 'United States', mockFee: 500000 },
  { code: 'GB', name: 'United Kingdom', mockFee: 450000 },
  { code: 'AU', name: 'Australia', mockFee: 400000 },
  { code: 'CA', name: 'Canada', mockFee: 550000 },
  { code: 'SG', name: 'Singapore', mockFee: 150000 },
  { code: 'MY', name: 'Malaysia', mockFee: 150000 },
  { code: 'KR', name: 'South Korea', mockFee: 200000 },
  { code: 'JP', name: 'Japan', mockFee: 250000 },
];

const Checkout = () => {
  const { cartItems, cartTotal, clearCart } = useCart();
  const { user } = useAuth();
  const { t, lang } = useLanguage();
  const navigate = useNavigate();
  
  // --- STATE ĐỊA CHỈ ---
  const [provinces, setProvinces] = useState([]);
  const [districts, setDistricts] = useState([]);
  const [wards, setWards] = useState([]);
  
  // SHIPPING TYPE (DOMESTIC/INTERNATIONAL) 
  const [shippingType, setShippingType] = useState('domestic');

  // Form State
  const [formData, setFormData] = useState({ 
    fullName: '', phone: '', email: '', note: '', street: '', 
    province_id: '', district_id: '', ward_code: '', 
    province_name: '', district_name: '', ward_name: '',
    country: '', state_province: '', city: '', zipcode: ''
  });
  
  // Payment & Shipping
  const [shippingFee, setShippingFee] = useState(20000); 
  const [isCalculatingFee, setIsCalculatingFee] = useState(false);
  const [loading, setLoading] = useState(false);

  // Voucher State
  const [voucherCode, setVoucherCode] = useState('');
  const [appliedVoucher, setAppliedVoucher] = useState(null);
  const [discountAmount, setDiscountAmount] = useState(0);

  // State xác nhận chuyển khoản
  const [isTransferConfirmed, setIsTransferConfirmed] = useState(false);

  // =================================================================================
  // [TẾT] LOGIC KIỂM TRA LỊCH NGHỈ TẾT
  // =================================================================================
  const getTetStatus = () => {
      const now = new Date();
      const year = now.getFullYear();
      const t8Feb = new Date(year, 1, 8, 23, 59, 59);   
      const t10Feb = new Date(year, 1, 10, 19, 59, 59); 
      const t21Feb = new Date(year, 1, 21, 0, 0, 0);    
      const t25Feb = new Date(year, 1, 25, 0, 0, 0);    

      if (now > t10Feb && now < t21Feb) return { code: 'CLOSED', msgKey: 'checkout.tet_closed_msg' };
      if (now > t8Feb && now <= t10Feb) return { code: 'HCM_ONLY', msgKey: 'checkout.tet_hcm_msg' };
      if (now >= t21Feb && now < t25Feb) return { code: 'DELAYED', msgKey: 'checkout.tet_delayed_msg' };

      return { code: 'NORMAL', msgKey: '' };
  };
  const tetStatus = getTetStatus();

  // LOAD TỈNH THÀNH TỪ GHN
  useEffect(() => {
    const fetchProvinces = async () => {
        try {
            const res = await axios.get(`${GHN_API_BASE}/province`, { headers: { token: GHN_TOKEN } });
            if (res.data.code === 200) {
                setProvinces(res.data.data);
            }
        } catch (error) {
            console.error("Lỗi lấy Tỉnh:", error);
        }
    };
    fetchProvinces();
      
    if (user) {
      setFormData(prev => ({
        ...prev,
        fullName: user.full_name || '',
        phone: user.phone || '',
        email: user.email || '',
      }));
    }
  }, [user]);

  // Nếu giỏ hàng rỗng -> Quay về
  useEffect(() => {
    if (cartItems.length === 0) navigate('/cart');
  }, [cartItems, navigate]);
  
  // SỬA LOGIC CHANGE ĐỂ GỌI API GHN
  const handleProvinceChange = async (e) => {
    const pid = parseInt(e.target.value); 
    const pname = e.target.options[e.target.selectedIndex].text;
    
    setFormData({...formData, province_id: pid, province_name: pname, district_id: '', district_name: '', ward_code: '', ward_name: ''});
    setDistricts([]); setWards([]); setShippingFee(0);

    try {
        const res = await axios.post(`${GHN_API_BASE}/district`, { province_id: pid }, { headers: { token: GHN_TOKEN } });
        if (res.data.code === 200) setDistricts(res.data.data);
    } catch (error) { console.error("Lỗi lấy Quận:", error); }
  };

  const handleDistrictChange = async (e) => {
    const did = parseInt(e.target.value); 
    const dname = e.target.options[e.target.selectedIndex].text;
    
    setFormData({...formData, district_id: did, district_name: dname, ward_code: '', ward_name: ''});
    setWards([]); setShippingFee(0);

    try {
        const res = await axios.post(`${GHN_API_BASE}/ward`, { district_id: did }, { headers: { token: GHN_TOKEN } });
        if (res.data.code === 200) setWards(res.data.data);
    } catch (error) { console.error("Lỗi lấy Phường:", error); }
  };

  const handleWardChange = async (e) => {
    const wcode = e.target.value; 
    const wname = e.target.options[e.target.selectedIndex].text;
    setFormData({...formData, ward_code: wcode, ward_name: wname});
    
    // Giả lập tính xong phí ship nội địa
    setShippingFee(30000); 
  };

  // XỬ LÝ ĐỔI QUỐC GIA QUỐC TẾ (Mock phí ship Easyship)
  const handleCountryChange = (e) => {
    const selectedCountry = e.target.value;
    setFormData({...formData, country: selectedCountry});
    
    if (!selectedCountry) {
        setShippingFee(0);
        return;
    }

    setIsCalculatingFee(true);
    // Giả lập gọi API Easyship tốn 0.8s
    setTimeout(() => {
        const countryInfo = COUNTRY_LIST.find(c => c.code === selectedCountry);
        setShippingFee(countryInfo ? countryInfo.mockFee : 500000);
        setIsCalculatingFee(false);
    }, 800);
  };

  // XỬ LÝ VOUCHER
  const handleApplyVoucher = async () => {
    if (!voucherCode) return toast.warn(t('checkout.toast_missing_voucher'));
    try {
        const res = await axios.post(`${import.meta.env.VITE_API_URL}/api/promotions/check`, {
            code: voucherCode,
            cartTotal: cartTotal
        });
        if (res.data.success) {
            const { discountAmount, promo } = res.data.data;
            setDiscountAmount(discountAmount);
            setAppliedVoucher(promo);
            toast.success(`${t('checkout.toast_discount_applied')} ${promo.code}`);
        }
    } catch (error) {
        setDiscountAmount(0);
        setAppliedVoucher(null);
        toast.error(error.response?.data?.message || t('checkout.toast_invalid_voucher'));
    }
  };

  const removeVoucher = () => {
    setVoucherCode('');
    setAppliedVoucher(null);
    setDiscountAmount(0);
  };

  const finalTotal = Math.max(0, cartTotal + shippingFee - discountAmount);

  // QR Code (Vẫn sinh ra link VND gốc để lỡ cần dùng)
  const transferContent = `${formData.phone} ${formData.fullName}`.trim().replace(/\s+/g, '%20').toUpperCase();
  const qrUrl = `https://img.vietqr.io/image/${MY_BANK.BANK_ID}-${MY_BANK.ACCOUNT_NO}-${MY_BANK.TEMPLATE}.png?amount=${finalTotal}&addInfo=${transferContent}`;

  // --- SUBMIT ĐƠN HÀNG ---
  const handleSubmit = async (e) => {
    e.preventDefault();
    
    if (tetStatus.code === 'CLOSED') {
        toast.error(t('checkout.toast_tet_closed'));
        return;
    }

    // VALIDATION
    if (shippingType === 'domestic') {
        if (!formData.fullName || !formData.phone || !formData.street || !formData.ward_code) {
            toast.warning(t('checkout.toast_missing_info'));
            return;
        }
    } else {
        if (!formData.fullName || !formData.phone || !formData.street || !formData.country || !formData.state_province || !formData.city || !formData.zipcode) {
            toast.warning(t('checkout.toast_missing_info'));
            return;
        }
    }

    if (tetStatus.code === 'HCM_ONLY' && shippingType === 'domestic') {
        const isHCM = formData.province_id == 202 || formData.province_name?.toLowerCase().includes('hồ chí minh');
        if (!isHCM) {
            toast.error(t('checkout.toast_hcm_only'));
            return;
        }
    }

    // Phải tích xác nhận chuyển khoản mới cho đi tiếp
    if (!isTransferConfirmed) {
        toast.warning(t('checkout.toast_missing_transfer'));
        return;
    }

    setLoading(true);

    try {
        const payload = {
            customer: {
                fullName: formData.fullName,
                phone: formData.phone,
                email: formData.email,
                address: formData.street,
                shipping_type: shippingType, 
                
                province: shippingType === 'domestic' ? formData.province_name : formData.state_province,
                district: shippingType === 'domestic' ? formData.district_name : formData.city,
                ward: shippingType === 'domestic' ? formData.ward_name : formData.zipcode,
                
                province_id: shippingType === 'domestic' ? formData.province_id : null,
                district_id: shippingType === 'domestic' && formData.district_id ? parseInt(formData.district_id) : null,
                ward_code: shippingType === 'domestic' ? formData.ward_code : null,
                
                country: shippingType === 'international' ? formData.country : 'VN',
                zipcode: shippingType === 'international' ? formData.zipcode : null
            },
            items: cartItems,
            payment_method: 'banking', // Cả 2 loại ship đều dùng hình thức chuyển khoản thủ công
            shipping_fee: shippingFee, 
            note: formData.note,
            voucher_code: appliedVoucher ? appliedVoucher.code : null,
            discount_amount: discountAmount,
            final_total: finalTotal,
            // [CẬP NHẬT QUAN TRỌNG]: Ép kiểu 'en' nếu là ship quốc tế để Email gửi về là tiếng Anh
            lang: shippingType === 'international' ? 'en' : lang 
        };

        const res = await axios.post(`${import.meta.env.VITE_API_URL}/api/orders`, payload);
        
        if (res.data.success) {
            toast.success(t('checkout.toast_order_success'));
            clearCart();
            navigate(user ? '/account' : '/');
        }

    } catch (error) {
        console.error(error);
        toast.error(error.response?.data?.message || t('checkout.toast_order_error'));
    } finally {
        setLoading(false);
    }
  };

  return (
    <div className="max-w-6xl mx-auto px-6 py-10">
        <Link to="/cart" className="flex items-center text-stone-500 hover:text-stone-900 mb-8 w-fit">
            <FaArrowLeft className="mr-2" /> {t('checkout.back_to_cart')}
        </Link>

        {tetStatus.code !== 'NORMAL' && tetStatus.code !== 'CLOSED' && (
            <div className="bg-orange-50 border border-orange-200 text-orange-800 px-4 py-3 rounded-lg mb-8 flex items-start gap-3">
                <FaCalendarAlt className="mt-1 text-xl" />
                <div>
                    <strong className="block font-bold">{t('checkout.tet_notice')}</strong>
                    <span className="text-sm">{t(tetStatus.msgKey)}</span>
                </div>
            </div>
        )}

        {tetStatus.code === 'CLOSED' ? (
            <div className="text-center py-20 bg-stone-50 rounded-xl border border-stone-200">
                <div className="text-6xl mb-4">🧧</div>
                <h2 className="text-2xl font-bold text-stone-800 mb-2">{t('checkout.tet_happy_new_year')}</h2>
                <p className="text-stone-600 max-w-md mx-auto mb-6">{t(tetStatus.msgKey)}</p>
                <Link to="/" className="bg-stone-900 text-white px-6 py-3 rounded font-bold hover:bg-stone-800">
                    {t('checkout.back_to_home')}
                </Link>
            </div>
        ) : (
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-12">
                
                {/* CỘT TRÁI: THÔNG TIN GIAO HÀNG */}
                <div>
                    <h2 className="text-xl font-serif font-bold text-stone-900 mb-6 uppercase tracking-wider">1. {t('checkout.shipping_info')}</h2>
                    <form id="checkout-form" onSubmit={handleSubmit} className="space-y-4">
                        <input 
                            type="text" placeholder={t('checkout.fullname')} required
                            className="w-full p-3 border border-stone-200 rounded focus:border-stone-900 outline-none"
                            value={formData.fullName} onChange={e => setFormData({...formData, fullName: e.target.value})}
                        />
                        <div className="grid grid-cols-2 gap-4">
                            <input 
                                type="text" placeholder={t('checkout.phone')} required
                                className="w-full p-3 border border-stone-200 rounded focus:border-stone-900 outline-none"
                                value={formData.phone} onChange={e => setFormData({...formData, phone: e.target.value})}
                            />
                            <input 
                                type="email" placeholder={t('checkout.email')}
                                className="w-full p-3 border border-stone-200 rounded focus:border-stone-900 outline-none"
                                value={formData.email} onChange={e => setFormData({...formData, email: e.target.value})}
                            />
                        </div>

                        {/* --- KHU VỰC CHỌN ĐỊA CHỈ --- */}
                        <div className="border-t border-stone-200 pt-6 mt-6">
                            <h3 className="text-xl font-serif font-bold text-stone-900 mb-4 uppercase tracking-wider">{t('checkout.address')}</h3>
                            
                            {/* NÚT TOGGLE TRONG NƯỚC / QUỐC TẾ */}
                            <div className="flex gap-4 mb-6">
                                <label className={`flex-1 flex items-center justify-center gap-2 p-3 border rounded cursor-pointer transition-colors ${shippingType === 'domestic' ? 'border-stone-900 bg-stone-50 font-bold text-stone-900' : 'border-stone-200 text-stone-500 hover:bg-stone-50'}`}>
                                    <input type="radio" name="shippingType" value="domestic" className="hidden" checked={shippingType === 'domestic'} 
                                        onChange={() => { setShippingType('domestic'); setShippingFee(0); setIsTransferConfirmed(false); }} />
                                    {t('checkout.domestic')}
                                </label>
                                <label className={`flex-1 flex items-center justify-center gap-2 p-3 border rounded cursor-pointer transition-colors ${shippingType === 'international' ? 'border-stone-900 bg-stone-50 font-bold text-stone-900' : 'border-stone-200 text-stone-500 hover:bg-stone-50'}`}>
                                    <input type="radio" name="shippingType" value="international" className="hidden" checked={shippingType === 'international'} 
                                        onChange={() => { setShippingType('international'); setShippingFee(0); setIsTransferConfirmed(false); }} />
                                    {t('checkout.international')}
                                </label>
                            </div>

                            {/* FORM ĐỊA CHỈ TƯƠNG ỨNG */}
                            {shippingType === 'domestic' ? (
                                <div className="grid grid-cols-3 gap-2 mb-4">
                                    <select className="p-3 border rounded outline-none bg-white" value={formData.province_id} onChange={handleProvinceChange} required>
                                        <option value="">-- {t('checkout.province')} --</option>
                                        {provinces.map(p => <option key={p.ProvinceID} value={p.ProvinceID}>{p.ProvinceName}</option>)}
                                    </select>
                                    <select className="p-3 border rounded outline-none bg-white" value={formData.district_id} onChange={handleDistrictChange} required disabled={!formData.province_id}>
                                        <option value="">-- {t('checkout.district')} --</option>
                                        {districts.map(d => <option key={d.DistrictID} value={d.DistrictID}>{d.DistrictName}</option>)}
                                    </select>
                                    <select className="p-3 border rounded outline-none bg-white" value={formData.ward_code} onChange={handleWardChange} required disabled={!formData.district_id}>
                                        <option value="">-- {t('checkout.ward')} --</option>
                                        {wards.map(w => <option key={w.WardCode} value={w.WardCode}>{w.WardName}</option>)}
                                    </select>
                                </div>
                            ) : (
                                <div className="space-y-4 mb-4">
                                    <div className="grid grid-cols-2 gap-4">
                                        <select className="w-full p-3 border border-stone-200 rounded focus:border-stone-900 outline-none bg-white" required value={formData.country} onChange={handleCountryChange}>
                                            <option value="">-- {t('checkout.country')} --</option>
                                            {COUNTRY_LIST.map(c => <option key={c.code} value={c.code}>{c.name}</option>)}
                                        </select>
                                        <input type="text" placeholder={t('checkout.state_province')} required className="w-full p-3 border border-stone-200 rounded focus:border-stone-900 outline-none" value={formData.state_province} onChange={e => setFormData({...formData, state_province: e.target.value})} />
                                    </div>
                                    <div className="grid grid-cols-2 gap-4">
                                        <input type="text" placeholder={t('checkout.city')} required className="w-full p-3 border border-stone-200 rounded focus:border-stone-900 outline-none" value={formData.city} onChange={e => setFormData({...formData, city: e.target.value})} />
                                        <input type="text" placeholder={t('checkout.zipcode')} required className="w-full p-3 border border-stone-200 rounded focus:border-stone-900 outline-none" value={formData.zipcode} onChange={e => setFormData({...formData, zipcode: e.target.value})} />
                                    </div>
                                </div>
                            )}

                            <input 
                                type="text" placeholder={t('checkout.street')} required
                                className="w-full p-3 border border-stone-200 rounded focus:border-stone-900 outline-none"
                                value={formData.street} onChange={e => setFormData({...formData, street: e.target.value})}
                            />
                        </div>

                        <textarea 
                            placeholder={t('checkout.note')}
                            className="w-full p-3 border border-stone-200 rounded focus:border-stone-900 outline-none h-24 resize-none mt-4"
                            value={formData.note} onChange={e => setFormData({...formData, note: e.target.value})}
                        ></textarea>
                    </form>
                </div>

                {/* CỘT PHẢI: TÍNH TIỀN & THANH TOÁN */}
                <div className="h-fit">
                    <h2 className="text-xl font-serif font-bold text-stone-900 mb-6 uppercase tracking-wider">2. {t('checkout.payment_method')}</h2>
                    
                    <div className="bg-white p-6 rounded-xl shadow-lg border border-stone-100 text-center">
                        
                        {/* HIỂN THỊ DỰA VÀO LỰA CHỌN VẬN CHUYỂN */}
                        {shippingType === 'international' ? (
                            // --- GIAO DIỆN CHUYỂN KHOẢN SWIFT CHO KHÁCH QUỐC TẾ ---
                            <div className="bg-stone-50 p-6 rounded-lg mb-6 border border-stone-200 text-left animate-fade-in">
                                <h4 className="font-bold text-stone-800 mb-2">{t('checkout.swift_transfer')}</h4>
                                <p className="text-sm text-stone-600 mb-4">{t('checkout.swift_instructions')}</p>
                                <div className="bg-white p-4 rounded border border-stone-200">
                                    <ul className="text-sm space-y-3 text-stone-700">
                                        <li className="flex flex-col"><span className="text-xs text-stone-400">{t('checkout.bank_name_intl') || 'Bank Name'}</span> <strong className="font-mono text-base">{INTL_BANK.BANK_NAME}</strong></li>
                                        <li className="flex flex-col"><span className="text-xs text-stone-400">{t('checkout.swift_code')}</span> <strong className="font-mono">{INTL_BANK.SWIFT_CODE}</strong></li>
                                        <li className="flex flex-col"><span className="text-xs text-stone-400">{t('checkout.bank_account_name')}</span> <strong>{INTL_BANK.ACCOUNT_NAME}</strong></li>
                                        <li className="flex flex-col"><span className="text-xs text-stone-400">{t('checkout.bank_account_no')}</span> <strong className="font-mono text-lg text-blue-600">{INTL_BANK.ACCOUNT_NO}</strong></li>
                                        <li className="flex flex-col"><span className="text-xs text-stone-400">{t('checkout.address')}</span> <span>{INTL_BANK.ADDRESS} - {INTL_BANK.POST_CODE}</span></li>
                                    </ul>
                                </div>
                            </div>
                        ) : (
                            // --- GIAO DIỆN VIETQR CHO TRONG NƯỚC ---
                            formData.phone ? (
                                <div className="animate-fade-in mb-6">
                                    <p className="text-sm text-stone-500 mb-4">{t('checkout.scan_qr')}</p>
                                    <div className="flex justify-center mb-4">
                                        <img src={qrUrl} alt="VietQR" className="w-56 h-56 object-contain border border-stone-200 rounded-lg" />
                                    </div>
                                </div>
                            ) : (
                                <div className="h-48 flex flex-col items-center justify-center bg-stone-50 rounded text-stone-400 mb-6 animate-fade-in">
                                    <FaExclamationCircle className="text-2xl mb-2"/>
                                    <span>{t('checkout.qr_notice')}</span>
                                </div>
                            )
                        )}

                        <div className="bg-stone-50 p-4 rounded text-left text-sm space-y-3 mb-6">
                            {/* VOUCHER INPUT */}
                            <div className="flex gap-2 mb-2">
                                <div className="relative flex-1">
                                    <div className="absolute inset-y-0 left-0 pl-2 flex items-center pointer-events-none"><FaTag className="text-stone-400 text-xs" /></div>
                                    <input type="text" value={voucherCode} onChange={(e) => setVoucherCode(e.target.value.toUpperCase())} placeholder={t('checkout.discount_code')} disabled={!!appliedVoucher} className="w-full pl-7 p-2 text-xs border border-stone-200 rounded uppercase outline-none focus:border-stone-900" />
                                </div>
                                {appliedVoucher ? (
                                    <button type="button" onClick={removeVoucher} className="bg-stone-200 text-stone-600 px-3 py-1 rounded hover:bg-stone-300"><FaTimes size={12} /></button>
                                ) : (
                                    <button type="button" onClick={handleApplyVoucher} className="bg-stone-800 text-white px-3 py-1 rounded text-xs font-bold hover:bg-black">{t('checkout.apply')}</button>
                                )}
                            </div>
                            {appliedVoucher && <div className="text-green-600 text-xs flex items-center gap-1 mb-2"><FaCheckCircle size={10} /> {t('checkout.applied_code')}: <strong>{appliedVoucher.code}</strong></div>}
                            <hr className="border-stone-200"/>

                            <div className="flex justify-between">
                                <span className="text-stone-500">{t('checkout.subtotal')}:</span>
                                <span className="font-medium">{formatPrice(cartTotal, lang === 'en' ? 'USD' : 'VND')} </span>
                            </div>
                            <div className="flex justify-between">
                                <span className="text-stone-500">{t('checkout.shipping_fee')}:</span>
                                <span className="font-medium">
                                    {isCalculatingFee ? <span className="text-stone-400 italic">{t('checkout.calculating_fee')}</span> : formatPrice(shippingFee, lang === 'en' ? 'USD' : 'VND')}
                                </span>
                            </div>

                            {discountAmount > 0 && (
                                <div className="flex justify-between text-green-600 font-bold">
                                    <span>{t('checkout.discount')}:</span>
                                    <span>- {formatPrice(discountAmount, lang === 'en' ? 'USD' : 'VND')} </span>
                                </div>
                            )}

                            <div className="flex justify-between border-t border-stone-200 pt-2">
                                <span className="text-stone-900 font-bold">{t('checkout.total')}:</span>
                                <span className="font-bold text-xl text-red-600">{formatPrice(finalTotal, lang === 'en' ? 'USD' : 'VND')} </span>
                            </div>
                            
                            <div className="flex justify-between text-xs mt-2 pt-2 border-t border-stone-200 border-dashed">
                                <span className="text-stone-500">{t('checkout.bank_transfer_content')}:</span>
                                <span className="font-medium text-blue-600">{formData.phone} {formData.fullName}</span>
                            </div>
                        </div>

                        {/* CHECKBOX XÁC NHẬN CHUYỂN KHOẢN (Hiển thị cho cả VietQR và SWIFT) */}
                        {(shippingType === 'international' || formData.phone) && (
                            <div className="bg-blue-50 border border-blue-200 p-3 rounded mb-4 text-left">
                                <label className="flex items-start gap-3 cursor-pointer select-none">
                                    <input 
                                        type="checkbox" 
                                        className="mt-1 w-5 h-5 accent-blue-600 cursor-pointer"
                                        checked={isTransferConfirmed}
                                        onChange={(e) => setIsTransferConfirmed(e.target.checked)}
                                    />
                                    <span className="text-sm font-bold text-stone-800">
                                        {t('checkout.confirm_transfer')} {formatPrice(finalTotal, lang === 'en' ? 'USD' : 'VND')}
                                    </span>
                                </label>
                            </div>
                        )}
                        
                        <button 
                            type="submit" 
                            form="checkout-form" 
                            disabled={loading || !isTransferConfirmed || isCalculatingFee} 
                            className={`w-full py-4 font-bold rounded uppercase transition-all flex items-center justify-center gap-2
                                ${loading || !isTransferConfirmed || isCalculatingFee
                                    ? 'bg-stone-300 text-stone-500 cursor-not-allowed' 
                                    : 'bg-stone-900 text-white hover:bg-stone-800 shadow-lg'}
                            `}
                        >
                            {loading ? t('checkout.processing') : <><FaCheckCircle/> {t('checkout.banking_confirm')}</>}
                        </button>
                        <p className="text-xs text-stone-400 mt-4 italic">{t('checkout.note_warning')}</p>
                    </div>
                </div>
            </div>
        )}
    </div>
  );
};

export default Checkout;