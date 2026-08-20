import { useState, useEffect, useMemo } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useCart } from '../context/CartContext';
import { useAuth } from '../context/AuthContext';
import axios from 'axios';
import { FaArrowLeft, FaCheckCircle, FaExclamationCircle, FaTimes, FaTag, FaCalendarAlt } from 'react-icons/fa';
import { toast } from 'react-toastify';
import { useLanguage } from '../context/LanguageContext';
import { formatPrice } from '../utils/currencyHelper';
import Container from '../components/ui/Container';
import Button from '../components/ui/Button';
import { clearApiCache } from '../utils/apiCache';

// CẤU HÌNH API GHN
const GHN_TOKEN = '7a83a4ad-f72f-11f0-835a-aa01149835ce';
const GHN_API_BASE = 'https://online-gateway.ghn.vn/shiip/public-api/master-data';

const COUNTRY_LIST = [
  { code: 'US', name: 'United States', mockFee: 'To be announced later' },
  { code: 'GB', name: 'United Kingdom', mockFee: 'To be announced later' },
  { code: 'AU', name: 'Australia', mockFee: 'To be announced later' },
  { code: 'CA', name: 'Canada', mockFee: 'To be announced later' },
  { code: 'SG', name: 'Singapore', mockFee: 'To be announced later' },
  { code: 'MY', name: 'Malaysia', mockFee: 'To be announced later' },
  { code: 'KR', name: 'South Korea', mockFee: 'To be announced later' },
  { code: 'JP', name: 'Japan', mockFee: 'To be announced later' },
];

const PHONE_REGEX = /^0\d{9}$/;

const inputCls = 'w-full rounded-xl border border-sand bg-cream p-3 text-ink outline-none transition-colors focus:border-cocoa placeholder:text-muted/60';
const selectCls = 'w-full rounded-xl border border-sand bg-cream p-3 text-ink outline-none transition-colors focus:border-cocoa';

const Checkout = () => {
  const { cartItems, cartTotal, clearCart } = useCart();
  const { user } = useAuth();
  const { t, lang } = useLanguage();
  const navigate = useNavigate();

  const [provinces, setProvinces] = useState([]);
  const [districts, setDistricts] = useState([]);
  const [wards, setWards] = useState([]);

  const [shippingType, setShippingType] = useState('domestic');
  const [isOrderSuccess, setIsOrderSuccess] = useState(false);

  const [formData, setFormData] = useState({
    fullName: '', phone: '', email: '', note: '', street: '',
    province_id: '', district_id: '', ward_code: '',
    province_name: '', district_name: '', ward_name: '',
    country: '', state_province: '', city: '', zipcode: ''
  });

  const [shippingFee, setShippingFee] = useState(0);
  const [isCalculatingFee] = useState(false);
  const [loading, setLoading] = useState(false);

  const [voucherCode, setVoucherCode] = useState('');
  const [appliedVoucher, setAppliedVoucher] = useState(null);
  const [discountAmount, setDiscountAmount] = useState(0);

  const [isTransferConfirmed, setIsTransferConfirmed] = useState(false);
  const [legacyBikiniProductIds, setLegacyBikiniProductIds] = useState([]);

  const isBikiniItem = (item) => `${item.category_slug || ''} ${item.category_name || ''}`.toLowerCase().includes('bikini');

  // Giỏ tạo từ phiên bản cũ chưa có thông tin danh mục: kiểm tra lại theo slug sản phẩm.
  useEffect(() => {
    let active = true;
    const legacyItems = cartItems.filter((item) => !item.category_slug && !item.category_name && item.slug);
    if (!legacyItems.length) {
      setLegacyBikiniProductIds([]);
      return () => { active = false; };
    }
    Promise.all(legacyItems.map((item) => axios.get(`${import.meta.env.VITE_API_URL}/api/products/${item.slug}`)
      .then(({ data }) => ({ id: item.product_id, category: data?.data?.categories }))
      .catch(() => null)))
      .then((results) => {
        if (active) setLegacyBikiniProductIds(results.filter((result) => result && `${result.category?.slug || ''} ${result.category?.name || ''}`.toLowerCase().includes('bikini')).map((result) => result.id));
      });
    return () => { active = false; };
  }, [cartItems]);

  const hasBikiniInCart = useMemo(() => cartItems.some((item) => isBikiniItem(item) || legacyBikiniProductIds.includes(item.product_id)), [cartItems, legacyBikiniProductIds]);

  // LOGIC KIỂM TRA LỊCH NGHỈ TẾT
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
            if (res.data.code === 200) setProvinces(res.data.data);
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

  useEffect(() => {
    if (cartItems.length === 0 && !isOrderSuccess) navigate('/cart');
  }, [cartItems, navigate, isOrderSuccess]);

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
    setShippingFee(0);
  };

  const handleCountryChange = (e) => {
      const selectedCountry = e.target.value;
      setFormData({...formData, country: selectedCountry});
      setShippingFee(0);
  };

  const handleApplyVoucher = async () => {
    if (!voucherCode) return toast.warn(t('checkout.toast_missing_voucher'));
    try {
        const res = await axios.post(`${import.meta.env.VITE_API_URL}/api/promotions/check`, {
            code: voucherCode,
            items: cartItems.map(i => ({ product_id: i.product_id, variant_id: i.variant_id, quantity: i.quantity })),
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

  const submitOrderToDatabase = async (paymentMethodType) => {
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
            items: cartItems.map(item => ({ variant_id: item.variant_id, quantity: item.quantity })),
            payment_method: paymentMethodType,
            shipping_fee: shippingFee,
            note: formData.note,
            voucher_code: appliedVoucher ? appliedVoucher.code : null,
            discount_amount: discountAmount,
            final_total: finalTotal,
            lang: shippingType === 'international' ? 'en' : lang
        };

        const res = await axios.post(`${import.meta.env.VITE_API_URL}/api/orders`, payload);

        if (res.data.success) {
            toast.success(t('checkout.toast_order_success'));
            clearApiCache('/api/products');
            clearCart();
            setIsOrderSuccess(true);
        }
    } catch (error) {
        console.error(error);
        toast.error(error.response?.data?.message || t('checkout.toast_order_error'));
    } finally {
        setLoading(false);
    }
  };

  const isFormValid = () => {
    if (shippingType === 'domestic') {
        return formData.fullName && formData.phone && formData.street && formData.ward_code;
    } else {
        return formData.fullName && formData.phone && formData.street && formData.country && formData.state_province && formData.city && formData.zipcode;
    }
  };

  const isPhoneValid = () => PHONE_REGEX.test(formData.phone);

  const handleDomesticSubmit = async (e) => {
    e.preventDefault();
    if (shippingType === 'international') return;

    if (tetStatus.code === 'CLOSED') {
        toast.error(t('checkout.toast_tet_closed'));
        return;
    }

    if (!isFormValid()) {
        toast.warning(t('checkout.toast_missing_info'));
        return;
    }

    if (!isPhoneValid()) {
        toast.warning(t('checkout.toast_invalid_phone'));
        return;
    }

    if (formData.email && !formData.email.toLowerCase().endsWith('@gmail.com')) {
        toast.error(lang === 'en' ? 'Please use a @gmail.com address, or leave it blank and contact via IG.' : 'Vui lòng sử dụng @gmail.com để nhận thông báo. Hoặc để trống và LH Zalo/IG.');
        return;
    }

    if (tetStatus.code === 'HCM_ONLY' && shippingType === 'domestic') {
        const isHCM = formData.province_id == 202 || formData.province_name?.toLowerCase().includes('hồ chí minh');
        if (!isHCM) {
            toast.error(t('checkout.toast_hcm_only'));
            return;
        }
    }

    if (!isTransferConfirmed) {
        toast.warning(t('checkout.toast_missing_transfer'));
        return;
    }

    await submitOrderToDatabase('banking');
  };

  return (
    <Container className="max-w-6xl py-10">

        {isOrderSuccess ? (
            <div className="animate-fade-in rounded-2xl border border-sand bg-surface py-20 text-center">
                <div className="mb-4 flex justify-center text-6xl text-sage">
                    <FaCheckCircle />
                </div>
                <h1 className="mb-4 font-heading text-3xl text-espresso">
                    {lang === 'en' ? 'Order Placed Successfully!' : 'Đặt hàng thành công!'}
                </h1>

                <div className="mx-auto mt-6 flex max-w-md items-start gap-4 rounded-2xl border border-sand bg-parchment/60 p-4 text-left">
                    <div className="shrink-0 rounded-full bg-cocoa/10 p-2">
                        <svg className="h-6 w-6 text-cocoa" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                        </svg>
                    </div>
                    <div>
                        <h4 className="font-heading text-base text-espresso">
                            {t('checkout.emailNoteTitle') || (lang === 'en' ? 'Check your inbox' : 'Kiểm tra hộp thư của bạn')}
                        </h4>
                        <p className="mt-1 text-sm leading-relaxed text-ink/75">
                            {t('checkout.emailNoteDesc') || (lang === 'en' ? "We've sent an order confirmation email. You will also receive a shipping update with a tracking number once your order is on its way." : 'Chúng tôi đã gửi email xác nhận đơn hàng. Bạn cũng sẽ nhận được email thông báo kèm mã vận đơn khi đơn hàng bắt đầu được giao.')}
                        </p>
                    </div>
                </div>

                <div className="mt-8 flex justify-center gap-4">
                    <Button to="/" variant="outline">{lang === 'en' ? 'Continue Shopping' : 'Tiếp tục mua sắm'}</Button>
                    {user && (
                        <Button to="/account" variant="solid">{lang === 'en' ? 'View My Orders' : 'Xem đơn hàng'}</Button>
                    )}
                </div>
            </div>
        ) : (
            <>
                <Link to="/cart" className="mb-8 flex w-fit items-center text-muted transition-colors hover:text-cocoa">
                    <FaArrowLeft className="mr-2" /> {t('checkout.back_to_cart')}
                </Link>

                {tetStatus.code !== 'NORMAL' && tetStatus.code !== 'CLOSED' && (
                    <div className="mb-8 flex items-start gap-3 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-amber-800">
                        <FaCalendarAlt className="mt-1 text-xl" />
                        <div>
                            <strong className="block">{t('checkout.tet_notice')}</strong>
                            <span className="text-sm">{t(tetStatus.msgKey)}</span>
                        </div>
                    </div>
                )}

                {hasBikiniInCart && (
                    <div className="mb-8 border-2 border-red-500 bg-red-50 p-5 text-red-950 shadow-lg md:p-6" role="alert">
                        <div className="flex items-start gap-4">
                            <FaExclamationCircle className="mt-0.5 shrink-0 text-3xl text-red-600" />
                            <div>
                                <h2 className="text-lg font-bold uppercase tracking-wide text-red-800">Lưu ý quan trọng về sản phẩm bikini</h2>
                                <p className="mt-3 whitespace-pre-line text-base font-medium leading-relaxed">
                                    Vì lý do vệ sinh và nhằm đảm bảo sự nguyên vẹn của từng thiết kế, bikini là sản phẩm không áp dụng đổi hoặc trả dưới bất kỳ hình thức nào.{"\n"}
                                    Chỉ hỗ trợ đổi trong trường hợp sản phẩm phát sinh lỗi từ phía nhà sản xuất.{"\n"}
                                    Brown trân trọng mong bạn cân nhắc kỹ về lựa chọn trước khi đặt hàng.
                                </p>
                            </div>
                        </div>
                    </div>
                )}

                {tetStatus.code === 'CLOSED' ? (
                    <div className="rounded-2xl border border-sand bg-surface py-20 text-center">
                        <div className="mb-4 text-6xl">🧧</div>
                        <h1 className="mb-2 font-heading text-2xl text-espresso">{t('checkout.tet_happy_new_year')}</h1>
                        <p className="mx-auto mb-6 max-w-md text-ink/75">{t(tetStatus.msgKey)}</p>
                        <Button to="/" variant="solid">{t('checkout.back_to_home')}</Button>
                    </div>
                ) : (
                    <div className="grid grid-cols-1 gap-12 lg:grid-cols-2">

                        {/* CỘT TRÁI: THÔNG TIN GIAO HÀNG */}
                        <div>
                            <h2 className="mb-6 font-heading text-2xl text-espresso">1. {t('checkout.shipping_info')}</h2>
                            <form id="checkout-form" onSubmit={handleDomesticSubmit} className="space-y-4">
                                <input type="text" placeholder={t('checkout.fullname')} required className={inputCls}
                                    value={formData.fullName} onChange={e => setFormData({...formData, fullName: e.target.value})} />

                                <div className="grid grid-cols-2 items-start gap-4">
                                    <input type="tel" inputMode="numeric" placeholder={t('checkout.phone')} required
                                        pattern="0[0-9]{9}" maxLength={10} className={inputCls}
                                        value={formData.phone}
                                        onChange={e => setFormData({...formData, phone: e.target.value.replace(/\D/g, '').slice(0, 10)})} />
                                    <div>
                                        <input type="email" placeholder={t('checkout.email')} className={inputCls}
                                            value={formData.email} onChange={e => setFormData({...formData, email: e.target.value})} />
                                        <p className="mt-1.5 text-[10px] italic leading-tight text-clay">
                                            {lang === 'en' ? '* Required @gmail.com to receive notifications. Or leave blank.' : '* Bắt buộc dùng @gmail.com. Khác vui lòng để trống và LH Zalo/IG.'}
                                        </p>
                                    </div>
                                </div>

                                <div className="mt-6 border-t border-sand pt-6">
                                    <h3 className="font-heading text-2xl text-espresso">{t('checkout.address')}</h3>

                                    <p className="mb-4 mt-1 text-xs italic text-muted">
                                        {lang === 'en' ? '* Please use your familiar shipping address for the fastest delivery.' : '* Vui lòng ưu tiên sử dụng địa chỉ nhận hàng cũ (nếu có) để thuận tiện giao hàng.'}
                                    </p>

                                    <div className="mb-6 flex gap-4">
                                        <label className={`flex flex-1 cursor-pointer items-center justify-center gap-2 rounded-xl border p-3 transition-colors ${shippingType === 'domestic' ? 'border-cocoa bg-parchment font-medium text-cocoa' : 'border-sand text-muted hover:bg-parchment/50'}`}>
                                            <input type="radio" name="shippingType" value="domestic" className="hidden" checked={shippingType === 'domestic'}
                                                onChange={() => { setShippingType('domestic'); setShippingFee(0); setIsTransferConfirmed(false); }} />
                                            {t('checkout.domestic')}
                                        </label>
                                        <label className={`flex flex-1 cursor-pointer items-center justify-center gap-2 rounded-xl border p-3 transition-colors ${shippingType === 'international' ? 'border-cocoa bg-parchment font-medium text-cocoa' : 'border-sand text-muted hover:bg-parchment/50'}`}>
                                            <input type="radio" name="shippingType" value="international" className="hidden" checked={shippingType === 'international'}
                                                onChange={() => { setShippingType('international'); setShippingFee(0); setIsTransferConfirmed(false); }} />
                                            {t('checkout.international')}
                                        </label>
                                    </div>

                                    {shippingType === 'domestic' ? (
                                        <div className="mb-4 grid grid-cols-3 gap-2">
                                            <select className={selectCls} value={formData.province_id} onChange={handleProvinceChange} required>
                                                <option value="">-- {t('checkout.province')} --</option>
                                                {provinces.map(p => <option key={p.ProvinceID} value={p.ProvinceID}>{p.ProvinceName}</option>)}
                                            </select>
                                            <select className={selectCls} value={formData.district_id} onChange={handleDistrictChange} required disabled={!formData.province_id}>
                                                <option value="">-- {t('checkout.district')} --</option>
                                                {districts.map(d => <option key={d.DistrictID} value={d.DistrictID}>{d.DistrictName}</option>)}
                                            </select>
                                            <select className={selectCls} value={formData.ward_code} onChange={handleWardChange} required disabled={!formData.district_id}>
                                                <option value="">-- {t('checkout.ward')} --</option>
                                                {wards.map(w => <option key={w.WardCode} value={w.WardCode}>{w.WardName}</option>)}
                                            </select>
                                        </div>
                                    ) : (
                                        <div className="mb-4 space-y-4">
                                            <div className="grid grid-cols-2 gap-4">
                                                <select className={selectCls} required value={formData.country} onChange={handleCountryChange}>
                                                    <option value="">-- {t('checkout.country')} --</option>
                                                    {COUNTRY_LIST.map(c => <option key={c.code} value={c.code}>{c.name}</option>)}
                                                </select>
                                                <input type="text" placeholder={t('checkout.state_province') || "State/Province"} required className={inputCls} value={formData.state_province} onChange={e => setFormData({...formData, state_province: e.target.value})} />
                                            </div>
                                            <div className="grid grid-cols-2 gap-4">
                                                <input type="text" placeholder={t('checkout.city') || "City"} required className={inputCls} value={formData.city} onChange={e => setFormData({...formData, city: e.target.value})} />
                                                <input type="text" placeholder={t('checkout.zipcode') || "Zip/Postal Code"} required className={inputCls} value={formData.zipcode} onChange={e => setFormData({...formData, zipcode: e.target.value})} />
                                            </div>
                                        </div>
                                    )}

                                    <input type="text" placeholder={t('checkout.street')} required className={inputCls}
                                        value={formData.street} onChange={e => setFormData({...formData, street: e.target.value})} />
                                </div>

                                <textarea placeholder={t('checkout.note')} className={`${inputCls} mt-4 h-24 resize-none`}
                                    value={formData.note} onChange={e => setFormData({...formData, note: e.target.value})} />
                            </form>
                        </div>

                        {/* CỘT PHẢI: TÍNH TIỀN & THANH TOÁN */}
                        <div className="h-fit">
                            <h2 className="mb-6 font-heading text-2xl text-espresso">2. {t('checkout.payment_method')}</h2>

                            <div className="rounded-2xl border border-sand bg-surface p-6 text-center shadow-[0_30px_70px_-45px_rgba(87,52,37,0.45)]">

                                <div className="mb-6 space-y-3 rounded-xl bg-parchment/50 p-4 text-left text-sm">
                                    <div className="mb-2 flex gap-2">
                                        <div className="relative flex-1">
                                            <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-2"><FaTag className="text-xs text-muted" /></div>
                                            <input type="text" value={voucherCode} onChange={(e) => setVoucherCode(e.target.value.toUpperCase())} placeholder={t('checkout.discount_code')} disabled={!!appliedVoucher} className="w-full rounded-lg border border-sand bg-cream p-2 pl-7 text-xs uppercase outline-none focus:border-cocoa" />
                                        </div>
                                        {appliedVoucher ? (
                                            <button type="button" onClick={removeVoucher} className="rounded-lg bg-sand px-3 py-1 text-cocoa transition-colors hover:bg-sand/70"><FaTimes size={12} /></button>
                                        ) : (
                                            <button type="button" onClick={handleApplyVoucher} className="rounded-lg bg-cocoa px-4 py-1 text-xs font-semibold uppercase text-cream transition-colors hover:bg-cocoa-deep">{t('checkout.apply')}</button>
                                        )}
                                    </div>
                                    {appliedVoucher && <div className="mb-2 flex items-center gap-1 text-xs text-sage"><FaCheckCircle size={10} /> {t('checkout.applied_code')}: <strong>{appliedVoucher.code}</strong></div>}
                                    <hr className="border-sand"/>

                                    <div className="flex justify-between">
                                        <span className="text-muted">{t('checkout.subtotal')}:</span>
                                        <span className="font-medium text-ink">{formatPrice(cartTotal, lang === 'en' ? 'USD' : 'VND')} </span>
                                    </div>

                                    <div className="flex justify-between">
                                        <span className="text-muted">{t('checkout.shipping_fee')}:</span>
                                        <span className="font-medium">
                                            {shippingType === 'international' && formData.country
                                                ? <span className="font-semibold text-clay">{lang === 'en' ? 'To be quoted' : 'Sẽ báo giá sau'}</span>
                                                : <span className="font-semibold text-red-600">{formatPrice(20000, lang === 'en' ? 'USD' : 'VND')}<span className="ml-1 text-[10px] font-normal">({lang === 'en' ? 'pay on delivery' : 'trả khi nhận'})</span></span>
                                            }
                                        </span>
                                    </div>

                                    {discountAmount > 0 && (
                                        <div className="flex justify-between font-semibold text-sage">
                                            <span>{t('checkout.discount')}:</span>
                                            <span>- {formatPrice(discountAmount, lang === 'en' ? 'USD' : 'VND')} </span>
                                        </div>
                                    )}

                                    <div className="flex justify-between border-t border-sand pt-2">
                                        <span className="font-semibold text-espresso">{lang === 'en' ? 'Amount to transfer' : 'Số tiền cần chuyển'}:</span>
                                        <span className="text-xl font-bold text-clay">{formatPrice(finalTotal, lang === 'en' ? 'USD' : 'VND')} </span>
                                    </div>
                                    {shippingType === 'domestic' && (
                                        <div className="mt-3 flex items-start gap-2 rounded-xl border border-red-300 bg-red-50 p-3 text-left">
                                            <FaExclamationCircle className="mt-0.5 shrink-0 text-red-600" />
                                            <p className="text-xs leading-relaxed text-red-700">
                                                {lang === 'en' ? (
                                                    <>
                                                        <strong className="font-bold">Shipping fee (20,000đ) is NOT included in the amount above.</strong> You pay it <strong className="font-bold">directly to the courier</strong> in cash when your order arrives. BROWN does not collect it via bank transfer.
                                                    </>
                                                ) : (
                                                    <>
                                                        <strong className="font-bold">Phí vận chuyển (20.000đ) KHÔNG nằm trong số tiền chuyển khoản ở trên.</strong> Bạn thanh toán <strong className="font-bold">trực tiếp cho người giao hàng</strong> khi nhận hàng. BROWN không thu hộ phí ship qua chuyển khoản.
                                                    </>
                                                )}
                                            </p>
                                        </div>
                                    )}
                                </div>

                                {shippingType === 'international' ? (
                                    <div className="animate-fade-in mb-6 rounded-xl border border-sand bg-parchment/50 p-6 text-center">
                                        <FaExclamationCircle className="mx-auto mb-3 text-3xl text-muted"/>
                                        <h3 className="mb-2 font-heading text-lg text-espresso">
                                            {lang === 'en' ? 'International Orders' : 'Đơn hàng quốc tế'}
                                        </h3>
                                        <p className="mb-4 text-sm text-ink/75">
                                            {lang === 'en' ? 'Please contact us directly via Instagram to place an international order and get shipping quotes.' : 'Vui lòng liên hệ trực tiếp qua Instagram để đặt hàng và nhận báo giá vận chuyển quốc tế.'}
                                        </p>
                                        <Button href="https://instagram.com/brown.vn" target="_blank" rel="noopener noreferrer" variant="solid">
                                            {lang === 'en' ? 'Contact on Instagram' : 'Liên hệ Instagram'}
                                        </Button>
                                    </div>
                                ) : (
                                    <>
                                        {formData.phone ? (
                                            <div className="animate-fade-in mb-6">
                                                <p className="mb-4 text-sm text-muted">{t('checkout.scan_qr') || 'Quét mã QR dưới đây để thanh toán:'}</p>

                                                <div className="mb-4 flex justify-center">
                                                    <img src="/QR.jpg" alt="ACB QR Code" className="w-full rounded-xl border border-sand object-contain" />
                                                </div>

                                                <div className="mb-4 space-y-1 rounded-xl border border-sand bg-parchment/50 p-3 text-left text-sm text-ink">
                                                    <p><strong className="text-espresso">Ngân hàng:</strong> ACB (Ngân hàng TMCP Á Châu)</p>
                                                    <p><strong className="text-espresso">Số tài khoản:</strong> 49060577</p>
                                                    <p><strong className="text-espresso">Chủ tài khoản:</strong> HO KINH DOANH BROWNVN</p>
                                                    <p><strong className="text-espresso">Chi nhánh:</strong> PGD Tân Sơn Nhì</p>
                                                </div>
                                            </div>
                                        ) : (
                                            <div className="animate-fade-in mb-6 flex h-48 flex-col items-center justify-center rounded-xl bg-parchment/50 text-muted">
                                                <FaExclamationCircle className="mb-2 text-2xl"/>
                                                <span className="px-4 text-center">{t('checkout.qr_notice') || 'Vui lòng nhập số điện thoại để xem mã chuyển khoản'}</span>
                                            </div>
                                        )}

                                        {/* TICK XÁC NHẬN CHUYỂN KHOẢN */}
                                        <div className={`mb-4 rounded-xl border p-3 text-left transition-colors ${isTransferConfirmed ? 'border-sage bg-sage/10' : 'border-sand bg-parchment/50'}`}>
                                            <label className="flex cursor-pointer select-none items-center gap-3">
                                                <input type="checkbox" className="h-5 w-5 cursor-pointer accent-cocoa"
                                                    checked={isTransferConfirmed}
                                                    onChange={(e) => setIsTransferConfirmed(e.target.checked)} />
                                                <span className="flex-1 text-sm font-medium text-espresso">
                                                    {isTransferConfirmed
                                                        ? `Tôi đã chuyển ${formatPrice(finalTotal, lang === 'en' ? 'USD' : 'VND')}`
                                                        : `Xác nhận đã chuyển ${formatPrice(finalTotal, lang === 'en' ? 'USD' : 'VND')}`}
                                                </span>
                                            </label>
                                        </div>

                                        <Button type="submit" form="checkout-form"
                                            disabled={loading || !isTransferConfirmed || isCalculatingFee}
                                            variant="solid" size="lg" className="w-full">
                                            {loading ? t('checkout.processing') : <><FaCheckCircle/> {t('checkout.banking_confirm')}</>}
                                        </Button>
                                        <p className="mt-4 text-xs italic text-muted">{t('checkout.note_warning')}</p>
                                    </>
                                )}
                            </div>
                        </div>
                    </div>
                )}
            </>
        )}
    </Container>
  );
};

export default Checkout;
