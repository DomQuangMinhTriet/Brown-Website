/* eslint-disable no-unused-vars */
import { useState, useEffect, useMemo } from 'react';
import axios from 'axios';
import { FaSearch, FaUser, FaMapMarkerAlt, FaPhone, FaTrash, FaBoxOpen, FaTag, FaTimes } from 'react-icons/fa';
import { toast } from 'react-toastify';
import { getEffectivePrice } from '../../utils/currencyHelper';
import { optimizeImage } from '../../utils/cloudinaryHelper';


// [MỚI] Hàm ép chữ Xanh thành Xanh dương để Google Translate dịch thành Blue
  const formatColorForTranslate = (color) => {
      if (!color) return '';
      const c = color.toString().trim();
      if (c.toLowerCase() === 'xanh') return 'Xanh dương'; 
      return c;
  };

const CreateOrder = () => {
    // Dữ liệu
    const [products, setProducts] = useState([]);
    const [cart, setCart] = useState([]);
    const [search, setSearch] = useState('');

    // Form Khách hàng
    const [customerInfo, setCustomerInfo] = useState({
        name: '', phone: '', address: '', note: ''
    });

    // Cấu hình đơn
    const [paymentMethod, setPaymentMethod] = useState('cod');
    const [isPaid, setIsPaid] = useState(false);
    
    // Thêm state quản lý phí ship, mặc định là 20.000đ
    const [shippingFee, setShippingFee] = useState(0);

    // Voucher
    const [voucherCode, setVoucherCode] = useState('');
    const [appliedVoucher, setAppliedVoucher] = useState(null);
    const [discountAmount, setDiscountAmount] = useState(0);

    // Load sản phẩm khi vào trang
    useEffect(() => {
        const fetchProducts = async () => {
            try {
                const res = await axios.get(`${import.meta.env.VITE_API_URL}/api/products`);
                let allProducts = res.data.success ? res.data.data : [];

                // Kéo thêm sản phẩm "Phụ kiện BrownVN" đang bị ẩn
                try {
                    const accRes = await axios.get(`${import.meta.env.VITE_API_URL}/api/orders/accessory`);
                    if (accRes.data.success && accRes.data.data) {
                        if (!allProducts.find(p => p.id === accRes.data.data.id)) {
                            allProducts.push(accRes.data.data);
                        }
                    }
                } catch (e) {
                    console.log("Không tải được phụ kiện");
                }

                setProducts(allProducts);
            } catch (err) { console.error(err); }
        };
        fetchProducts();
    }, []);

    // Logic Giỏ hàng
    const addToCart = (product, variant) => {
        // [ĐÃ SỬA] Nhận diện phụ kiện để bỏ qua check tồn kho
        const isAccessory = product.name === 'Phụ kiện BrownVN';

        if (variant.quantity_remaining <= 0 && !isAccessory) return toast.error("Hết hàng!");
        
        setCart(prev => {
            const existing = prev.find(item => item.variant_id === variant.id);
            if (existing) {
                // [ĐÃ SỬA] Bỏ qua chặn tăng số lượng nếu là Phụ kiện
                if (existing.quantity >= variant.quantity_remaining && !isAccessory) {
                    toast.warn(`Kho chỉ còn ${variant.quantity_remaining} sản phẩm!`);
                    return prev;
                }
                return prev.map(item => item.variant_id === variant.id ? { ...item, quantity: item.quantity + 1 } : item);
            }
            const eff = getEffectivePrice(product, variant); // Áp giảm giá trực tiếp theo biến thể nếu đang bật
            return [...prev, {
                product_id: product.id,
                variant_id: variant.id,
                name: product.name,
                size: variant.size || '',
                color: variant.color || '',
                price: eff.price || 0,
                original_price: eff.original || 0,
                is_discounted: eff.isDiscounted,
                quantity: 1,
                // [ĐÃ SỬA] Set tồn kho ảo vô hạn cho phụ kiện
                max_stock: isAccessory ? 999999 : variant.quantity_remaining,
                image: product.images?.[0]
            }];
        });
    };

    const updateQty = (variantId, delta) => {
        setCart(prev => prev.map(item => {
            if (item.variant_id === variantId) {
                const newQty = item.quantity + delta;
                if (newQty > item.max_stock) return item; 
                if (newQty < 1) return item;
                return { ...item, quantity: newQty };
            }
            return item;
        }));
    };

    const removeFromCart = (variantId) => setCart(prev => prev.filter(item => item.variant_id !== variantId));
    
    // Hàm cập nhật giá tiền thủ công (Dành riêng cho Phụ kiện)
    const updateCustomPrice = (variantId, newPrice) => {
        setCart(prev => prev.map(item => {
            if (item.variant_id === variantId) {
                return { ...item, price: newPrice };
            }
            return item;
        }));
    };

    // Voucher: kiểm tra qua đúng endpoint (server tự tính giảm theo SP, không tin giá client)
    const handleApplyVoucher = async () => {
        if (!voucherCode) return toast.warning("Nhập mã giảm giá!");
        if (cart.length === 0) return toast.warning("Giỏ hàng trống!");
        try {
            const res = await axios.post(`${import.meta.env.VITE_API_URL}/api/promotions/check`, {
                code: voucherCode,
                items: cart.map(i => ({ product_id: i.product_id, quantity: i.quantity })),
            });
            if (res.data.success) {
                setDiscountAmount(res.data.data.discountAmount);
                setAppliedVoucher(res.data.data.promo);
                toast.success(`Đã áp mã ${res.data.data.promo.code}`);
            }
        } catch (error) {
            setDiscountAmount(0);
            setAppliedVoucher(null);
            toast.error(error.response?.data?.message || "Mã không hợp lệ");
        }
    };

    const removeVoucher = () => { setVoucherCode(''); setAppliedVoucher(null); setDiscountAmount(0); };

    // Tách riêng tiền hàng và tổng tiền
    const itemsTotal = cart.reduce((sum, item) => sum + (item.price * item.quantity), 0);
    const totalAmount = Math.max(0, itemsTotal + Number(shippingFee) - Number(discountAmount || 0));

    // Xử lý Gửi đơn hàng
    const handleCreateOrder = async () => {
        if (cart.length === 0) return toast.error("Giỏ hàng trống!");
        if (!customerInfo.phone) return toast.error("Vui lòng nhập SĐT khách hàng");

        const payload = {
            customer: {
                fullName: customerInfo.name || "Khách lẻ",
                phone: customerInfo.phone,
                address: customerInfo.address || "Tại quầy",
                email: "" 
            },
            items: cart.map(item => ({
                product_id: item.product_id || item.id, 
                variant_id: item.variant_id,
                quantity: item.quantity,
                price: item.price // Gửi giá trị nhập tay lên Backend
            })),
            payment_method: paymentMethod,
            is_paid: isPaid,
            note: customerInfo.note,
            shipping_fee: Number(shippingFee),
            voucher_code: appliedVoucher ? appliedVoucher.code : null,
            discount_amount: Number(discountAmount) || 0
        };

        try {
            const res = await axios.post(`${import.meta.env.VITE_API_URL}/api/orders/create-admin`, payload);
            if (res.data.success) {
                toast.success("Tạo đơn hàng thành công!");
                
                const updatedProducts = products.map(p => {
                    if (!p.variants) return p;
                    const newVariants = p.variants.map(v => {
                        const cartItem = cart.find(c => c.variant_id === v.id);
                        // Không trừ tồn kho nếu là Phụ kiện
                        if (cartItem && p.name !== 'Phụ kiện BrownVN') {
                            return { 
                                ...v, 
                                quantity_remaining: Math.max(0, v.quantity_remaining - cartItem.quantity) 
                            };
                        }
                        return v;
                    });
                    return { ...p, variants: newVariants };
                });
                
                setProducts(updatedProducts); 
                
                setCart([]);
                setCustomerInfo({ name: '', phone: '', address: '', note: '' });
                setSearch('');
                setShippingFee(0);
                setVoucherCode(''); setAppliedVoucher(null); setDiscountAmount(0);
            }
        } catch (error) {
            console.error(error);
            toast.error(error.response?.data?.message || "Lỗi tạo đơn hàng");
        }
    };

    const filteredProducts = useMemo(() => {
        return products.filter(p => 
            p.name.toLowerCase().includes(search.toLowerCase()) || 
            p.variants?.some(v => v.sku.toLowerCase().includes(search.toLowerCase()))
        );
    }, [products, search]);

    return (
        <div className="flex flex-col lg:flex-row lg:h-screen min-h-screen bg-stone-100 lg:overflow-hidden">
            
            {/* CỘT 1: DANH SÁCH SẢN PHẨM */}
            <div className="lg:w-2/5 w-full flex flex-col p-4 border-r border-stone-200 bg-white h-[60vh] lg:h-full">
                <div className="mb-4">
                    <h2 className="font-bold text-lg mb-2 flex items-center gap-2"><FaBoxOpen/> Chọn sản phẩm</h2>
                    <div className="relative">
                        <FaSearch className="absolute left-3 top-3 text-stone-400"/>
                        <input className="w-full pl-10 pr-4 py-2 bg-stone-50 border rounded outline-none" placeholder="Tìm tên, mã SKU..." value={search} onChange={e => setSearch(e.target.value)}/>
                    </div>
                </div>
                <div className="flex-1 overflow-y-auto space-y-3 pr-2">
                    {filteredProducts.map(p => (
                        <div key={p.id} className="flex gap-3 p-2 border rounded hover:border-stone-400 transition-colors">
                            <img src={optimizeImage(p.images?.[0], 120)} className="w-16 h-20 object-cover rounded bg-stone-100" alt="" loading="lazy"/>
                            <div className="flex-1">
                                <div className="font-bold text-sm text-stone-800">{p.name}</div>
                                {(() => { const eff = getEffectivePrice(p); return eff.isDiscounted ? (
                                    <div className="text-sm"><span className="text-red-600 font-bold">{new Intl.NumberFormat('vi-VN').format(eff.price)}</span> <span className="text-stone-400 line-through text-xs">{new Intl.NumberFormat('vi-VN').format(eff.original)}</span></div>
                                ) : (
                                    <div className="text-red-600 font-bold text-sm">{new Intl.NumberFormat('vi-VN').format(eff.price)}</div>
                                ); })()}
                                <div className="flex flex-wrap gap-1 mt-2">
                                    {/* [ĐÃ SỬA] Xử lý hiển thị nút chọn cho Phụ kiện */}
                                    {p.variants?.map(v => {
                                        const isAccessory = p.name === 'Phụ kiện BrownVN';
                                        const hasStock = v.quantity_remaining > 0;

                                        return (
                                            <button 
                                                key={v.id} 
                                                onClick={() => addToCart(p, v)} 
                                                disabled={!hasStock && !isAccessory} 
                                                className={`text-xs px-2 py-1 border rounded ${
                                                    hasStock || isAccessory
                                                    ? 'hover:bg-stone-800 hover:text-white' 
                                                    : 'bg-stone-100 text-stone-300 line-through'
                                                }`}
                                            >
                                                {v.size}-{v.color} ({isAccessory ? '∞' : v.quantity_remaining})
                                            </button>
                                        );
                                    })}
                                </div>
                            </div>
                        </div>
                    ))}
                </div>
            </div>

            {/* CỘT 2: THÔNG TIN KHÁCH HÀNG */}
            <div className="lg:w-1/4 w-full p-4 lg:p-6 lg:overflow-y-auto bg-stone-50 border-r border-stone-200 lg:h-full">
                <h2 className="font-bold text-lg mb-6 flex items-center gap-2"><FaUser/> Khách hàng</h2>
                <div className="space-y-4">
                    <div><label className="text-xs font-bold text-stone-500 block mb-1">Tên khách (*)</label><input className="w-full p-2 border rounded bg-white text-sm" value={customerInfo.name} onChange={e => setCustomerInfo({...customerInfo, name: e.target.value})} /></div>
                    <div><label className="text-xs font-bold text-stone-500 block mb-1">Điện thoại (*)</label><div className="relative"><FaPhone className="absolute left-3 top-3 text-stone-400 text-xs"/><input className="w-full pl-8 p-2 border rounded bg-white text-sm" value={customerInfo.phone} onChange={e => setCustomerInfo({...customerInfo, phone: e.target.value})} /></div></div>
                    <div><label className="text-xs font-bold text-stone-500 block mb-1">Địa chỉ giao</label><div className="relative"><FaMapMarkerAlt className="absolute left-3 top-3 text-stone-400 text-xs"/><textarea className="w-full pl-8 p-2 border rounded bg-white h-20 text-sm" value={customerInfo.address} onChange={e => setCustomerInfo({...customerInfo, address: e.target.value})} /></div></div>
                    <div><label className="text-xs font-bold text-stone-500 block mb-1">Ghi chú</label><input className="w-full p-2 border rounded bg-white text-sm" placeholder="Nguồn đơn..." value={customerInfo.note} onChange={e => setCustomerInfo({...customerInfo, note: e.target.value})} /></div>
                </div>
            </div>

            {/* CỘT 3: CHI TIẾT & THANH TOÁN */}
            <div className="flex-1 w-full flex flex-col bg-white shadow-xl lg:h-full">
                <div className="p-4 bg-stone-900 text-white font-bold flex justify-between"><span>Đơn hàng</span><span>{cart.length} món</span></div>
                
                <div className="flex-1 overflow-y-auto p-4 space-y-4 max-h-[50vh] lg:max-h-full">
                    {cart.map(item => (
                        <div key={item.variant_id} className="flex justify-between items-start border-b pb-2">
                            <div className="flex-1 pr-4">
                                <div className="font-bold text-sm">{item.name}</div>
                                <div className="text-xs text-stone-500">{item.size} / {formatColorForTranslate(item.color)}</div>
                                
                                {/* HIỂN THỊ Ô NHẬP GIÁ NẾU LÀ PHỤ KIỆN BROWNVN */}
                                {item.name === 'Phụ kiện BrownVN' ? (
                                    <div className="mt-2 flex items-center gap-2">
                                        <span className="text-xs font-bold text-stone-500">Giá:</span>
                                        <input 
                                            type="number" 
                                            className="w-24 p-1 text-sm border border-stone-300 rounded outline-none focus:border-stone-900 text-red-600 font-bold"
                                            value={item.price}
                                            onChange={(e) => updateCustomPrice(item.variant_id, Number(e.target.value))}
                                        />
                                        <span className="text-sm font-bold text-stone-500">đ</span>
                                    </div>
                                ) : (
                                    <div className="text-red-600 font-bold text-sm mt-1">{new Intl.NumberFormat('vi-VN').format(item.price)}</div>
                                )}

                            </div>
                            <div className="flex flex-col items-end gap-2">
                                <button onClick={() => removeFromCart(item.variant_id)} className="text-stone-300 hover:text-red-500"><FaTrash size={12}/></button>
                                <div className="flex items-center border rounded"><button onClick={() => updateQty(item.variant_id, -1)} className="px-2 bg-stone-100">-</button><span className="px-2 text-sm font-bold">{item.quantity}</span><button onClick={() => updateQty(item.variant_id, 1)} className="px-2 bg-stone-100">+</button></div>
                            </div>
                        </div>
                    ))}
                </div>

                <div className="p-6 bg-stone-50 border-t">
                    <div className="flex justify-between mb-2 text-sm text-stone-500">
                        <span>Tạm tính:</span>
                        <span className="font-bold text-stone-700">{new Intl.NumberFormat('vi-VN').format(itemsTotal)} ₫</span>
                    </div>
                    
                    <div className="flex justify-between items-center mb-4 pb-4 border-b border-stone-200 border-dashed text-sm text-stone-500">
                        <span>Phí giao hàng:</span>
                        <div className="flex items-center gap-2">
                            <input 
                                type="number" 
                                className="w-24 p-1 text-right border border-stone-300 rounded outline-none font-bold text-stone-700 focus:border-stone-900"
                                value={shippingFee}
                                onChange={(e) => setShippingFee(e.target.value)}
                            />
                            <span className="font-bold">₫</span>
                        </div>
                    </div>

                    {/* VOUCHER */}
                    <div className="mb-4">
                        <div className="flex gap-2">
                            <div className="relative flex-1">
                                <FaTag className="absolute left-2 top-2.5 text-stone-400 text-xs" />
                                <input type="text" value={voucherCode} onChange={e => setVoucherCode(e.target.value.toUpperCase())} placeholder="Mã giảm giá"
                                    disabled={!!appliedVoucher}
                                    className="w-full pl-7 p-2 text-sm border rounded uppercase outline-none focus:border-stone-900 disabled:bg-stone-100" />
                            </div>
                            {appliedVoucher ? (
                                <button type="button" onClick={removeVoucher} className="bg-stone-200 text-stone-600 px-3 rounded hover:bg-stone-300"><FaTimes size={12} /></button>
                            ) : (
                                <button type="button" onClick={handleApplyVoucher} className="bg-stone-800 text-white px-4 rounded text-sm font-bold hover:bg-black">Áp dụng</button>
                            )}
                        </div>
                        {discountAmount > 0 && (
                            <div className="flex justify-between mt-2 text-sm text-green-600 font-bold">
                                <span>Giảm giá ({appliedVoucher?.code}):</span>
                                <span>- {new Intl.NumberFormat('vi-VN').format(discountAmount)} ₫</span>
                            </div>
                        )}
                    </div>

                    <div className="flex justify-between mb-4 text-xl font-bold">
                        <span>Tổng tiền:</span>
                        <span className="text-red-600">{new Intl.NumberFormat('vi-VN').format(totalAmount)} ₫</span>
                    </div>

                    <div className="grid grid-cols-2 gap-4 mb-4">
                        <div><label className="text-xs font-bold block mb-1">Thanh toán</label><select className="w-full p-2 border rounded bg-white text-sm outline-none" value={paymentMethod} onChange={e => setPaymentMethod(e.target.value)}><option value="cod">COD (Thu hộ)</option><option value="transfer">Chuyển khoản</option></select></div>
                        <div><label className="text-xs font-bold block mb-1">Trạng thái TT</label><select className="w-full p-2 border rounded bg-white text-sm outline-none" value={isPaid} onChange={e => setIsPaid(e.target.value === 'true')}><option value="false">Chưa thanh toán</option><option value="true">Đã thanh toán</option></select></div>
                    </div>
                    <button onClick={handleCreateOrder} className="w-full bg-stone-900 text-white py-3 rounded font-bold uppercase hover:bg-black shadow-lg">TẠO ĐƠN HÀNG</button>
                </div>
            </div>
        </div>
    );
};

export default CreateOrder;
