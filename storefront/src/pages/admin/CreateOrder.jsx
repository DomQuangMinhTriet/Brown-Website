import { useState, useEffect, useMemo } from 'react';
import axios from 'axios';
import { FaSearch, FaUser, FaMapMarkerAlt, FaPhone, FaTrash, FaBoxOpen } from 'react-icons/fa';
import { toast } from 'react-toastify';

// [MỚI] CẤU HÌNH API GHN ĐỂ LẤY ĐỊA CHỈ CHUẨN
const GHN_TOKEN = '7a83a4ad-f72f-11f0-835a-aa01149835ce'; 
const GHN_API_BASE = 'https://online-gateway.ghn.vn/shiip/public-api/master-data';

const CreateOrder = () => {
    // Dữ liệu
    const [products, setProducts] = useState([]);
    const [cart, setCart] = useState([]);
    const [search, setSearch] = useState('');

    // [MỚI] STATE TỈNH/QUẬN/PHƯỜNG
    const [provinces, setProvinces] = useState([]);
    const [districts, setDistricts] = useState([]);
    const [wards, setWards] = useState([]);

    // Form Khách hàng (Thêm các trường quản lý địa chỉ mới)
    const [customerInfo, setCustomerInfo] = useState({
        name: '', phone: '', address: '', note: '',
        street: '', province_id: '', district_id: '', ward_code: '',
        province_name: '', district_name: '', ward_name: ''
    });

    // Cấu hình đơn
    const [paymentMethod, setPaymentMethod] = useState('cod');
    const [isPaid, setIsPaid] = useState(false);
    
    // [MỚI] Thêm state quản lý phí ship, mặc định là 20.000đ
    const [shippingFee, setShippingFee] = useState(0);

    // Load sản phẩm và Tỉnh/TP khi vào trang
    useEffect(() => {
        const fetchProducts = async () => {
            try {
                const res = await axios.get(`${import.meta.env.VITE_API_URL}/api/products`);
                if (res.data.success) setProducts(res.data.data);
            } catch (err) { console.error(err); }
        };

        const fetchProvinces = async () => {
            try {
                const res = await axios.get(`${GHN_API_BASE}/province`, { headers: { token: GHN_TOKEN } });
                if (res.data.code === 200) setProvinces(res.data.data);
            } catch (error) { console.error("Lỗi lấy Tỉnh/TP:", error); }
        };

        fetchProducts();
        fetchProvinces();
    }, []);

    // [MỚI] LOGIC XỬ LÝ CHỌN ĐỊA CHỈ TỪ DROPDOWN
    const handleProvinceChange = async (e) => {
        const pid = parseInt(e.target.value); 
        const pname = e.target.options[e.target.selectedIndex].text;
        
        setCustomerInfo({...customerInfo, province_id: pid, province_name: pname, district_id: '', district_name: '', ward_code: '', ward_name: ''});
        setDistricts([]); setWards([]);
    
        try {
            const res = await axios.post(`${GHN_API_BASE}/district`, { province_id: pid }, { headers: { token: GHN_TOKEN } });
            if (res.data.code === 200) setDistricts(res.data.data);
        } catch (error) { console.error("Lỗi lấy Quận:", error); }
    };
    
    const handleDistrictChange = async (e) => {
        const did = parseInt(e.target.value); 
        const dname = e.target.options[e.target.selectedIndex].text;
        
        setCustomerInfo({...customerInfo, district_id: did, district_name: dname, ward_code: '', ward_name: ''});
        setWards([]);
    
        try {
            const res = await axios.post(`${GHN_API_BASE}/ward`, { district_id: did }, { headers: { token: GHN_TOKEN } });
            if (res.data.code === 200) setWards(res.data.data);
        } catch (error) { console.error("Lỗi lấy Phường:", error); }
    };
    
    const handleWardChange = (e) => {
        const wcode = e.target.value; 
        const wname = e.target.options[e.target.selectedIndex].text;
        setCustomerInfo({...customerInfo, ward_code: wcode, ward_name: wname});
    };

    // Logic Giỏ hàng
    const addToCart = (product, variant) => {
        if (variant.quantity_remaining <= 0) return toast.error("Hết hàng!");
        
        setCart(prev => {
            const existing = prev.find(item => item.variant_id === variant.id);
            if (existing) {
                if (existing.quantity >= variant.quantity_remaining) {
                    toast.warn(`Kho chỉ còn ${variant.quantity_remaining} sản phẩm!`);
                    return prev;
                }
                return prev.map(item => item.variant_id === variant.id ? { ...item, quantity: item.quantity + 1 } : item);
            }
            return [...prev, {
                product_id: product.id,
                variant_id: variant.id,
                name: product.name,
                size: variant.size,
                color: variant.color,
                price: product.base_price,
                quantity: 1,
                max_stock: variant.quantity_remaining, 
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
    
    // [MỚI] Tách riêng tiền hàng và tổng tiền
    const itemsTotal = cart.reduce((sum, item) => sum + (item.price * item.quantity), 0);
    const totalAmount = itemsTotal + Number(shippingFee);

    // Xử lý Gửi đơn hàng
    const handleCreateOrder = async () => {
        if (cart.length === 0) return toast.error("Giỏ hàng trống!");
        if (!customerInfo.phone) return toast.error("Vui lòng nhập SĐT khách hàng");

        // [MỚI] Ghép chuỗi địa chỉ chuẩn có dấu phẩy để xuất Excel mượt mà
        let finalAddress = customerInfo.address || "Tại quầy"; 
        if (customerInfo.province_id && customerInfo.district_id && customerInfo.ward_code && customerInfo.street) {
            finalAddress = `${customerInfo.street}, ${customerInfo.ward_name}, ${customerInfo.district_name}, ${customerInfo.province_name}`;
        } else if (customerInfo.street) {
            finalAddress = customerInfo.street;
        }

        const payload = {
            customer: {
                fullName: customerInfo.name || "Khách lẻ",
                phone: customerInfo.phone,
                address: finalAddress, // Sử dụng chuỗi địa chỉ đã ghép
                email: "" 
            },
            items: cart.map(item => ({
                product_id: item.product_id || item.id, 
                variant_id: item.variant_id,
                quantity: item.quantity,
                price: item.price
            })),
            payment_method: paymentMethod, 
            is_paid: isPaid,
            note: customerInfo.note,
            // [MỚI] Gửi phí ship xuống Backend
            shipping_fee: Number(shippingFee)
        };

        try {
            const res = await axios.post(`${import.meta.env.VITE_API_URL}/api/orders/create-admin`, payload);
            if (res.data.success) {
                toast.success("Tạo đơn hàng thành công!");
                
                const updatedProducts = products.map(p => {
                    if (!p.variants) return p;
                    const newVariants = p.variants.map(v => {
                        const cartItem = cart.find(c => c.variant_id === v.id);
                        if (cartItem) {
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
                // Cập nhật reset đầy đủ state customerInfo
                setCustomerInfo({ 
                    name: '', phone: '', address: '', note: '', 
                    street: '', province_id: '', district_id: '', ward_code: '',
                    province_name: '', district_name: '', ward_name: '' 
                });
                setDistricts([]);
                setWards([]);
                setSearch('');
                // Reset lại phí ship về 0 cho đơn tiếp theo
                setShippingFee(0);
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
                            <img src={p.images?.[0]} className="w-16 h-20 object-cover rounded bg-stone-100" alt=""/>
                            <div className="flex-1">
                                <div className="font-bold text-sm text-stone-800">{p.name}</div>
                                <div className="text-red-600 font-bold text-sm">{new Intl.NumberFormat('vi-VN').format(p.base_price)}</div>
                                <div className="flex flex-wrap gap-1 mt-2">
                                    {p.variants?.map(v => (
                                        <button 
                                            key={v.id} 
                                            onClick={() => addToCart(p, v)} 
                                            disabled={v.quantity_remaining <= 0} 
                                            className={`text-xs px-2 py-1 border rounded ${
                                                v.quantity_remaining > 0 
                                                ? 'hover:bg-stone-800 hover:text-white' 
                                                : 'bg-stone-100 text-stone-300 line-through'
                                            }`}
                                        >
                                            {v.size}-{v.color} ({v.quantity_remaining})
                                        </button>
                                    ))}
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
                    
                    {/* [MỚI] KHU VỰC CHỌN ĐỊA CHỈ GHN */}
                    <div className="border-t border-stone-200 pt-4 mt-2">
                        <label className="text-xs font-bold text-stone-500 block mb-2">Địa chỉ giao hàng</label>
                        <div className="space-y-2">
                            <select className="w-full p-2 border rounded bg-white text-sm outline-none" value={customerInfo.province_id} onChange={handleProvinceChange}>
                                <option value="">-- Chọn Tỉnh/Thành phố --</option>
                                {provinces.map(p => <option key={p.ProvinceID} value={p.ProvinceID}>{p.ProvinceName}</option>)}
                            </select>
                            
                            <select className="w-full p-2 border rounded bg-white text-sm outline-none" value={customerInfo.district_id} onChange={handleDistrictChange} disabled={!customerInfo.province_id}>
                                <option value="">-- Chọn Quận/Huyện --</option>
                                {districts.map(d => <option key={d.DistrictID} value={d.DistrictID}>{d.DistrictName}</option>)}
                            </select>
                            
                            <select className="w-full p-2 border rounded bg-white text-sm outline-none" value={customerInfo.ward_code} onChange={handleWardChange} disabled={!customerInfo.district_id}>
                                <option value="">-- Chọn Phường/Xã --</option>
                                {wards.map(w => <option key={w.WardCode} value={w.WardCode}>{w.WardName}</option>)}
                            </select>

                            <div className="relative pt-1">
                                <FaMapMarkerAlt className="absolute left-3 top-4 text-stone-400 text-xs"/>
                                <input 
                                    className="w-full pl-8 p-2 border rounded bg-white text-sm" 
                                    placeholder="Số nhà, tên đường..." 
                                    value={customerInfo.street} 
                                    onChange={e => setCustomerInfo({...customerInfo, street: e.target.value})} 
                                />
                            </div>
                        </div>
                    </div>

                    <div className="border-t border-stone-200 pt-4 mt-2">
                        <label className="text-xs font-bold text-stone-500 block mb-1">Ghi chú</label>
                        <input className="w-full p-2 border rounded bg-white text-sm" placeholder="Nguồn đơn..." value={customerInfo.note} onChange={e => setCustomerInfo({...customerInfo, note: e.target.value})} />
                    </div>
                </div>
            </div>

            {/* CỘT 3: CHI TIẾT & THANH TOÁN */}
            <div className="flex-1 w-full flex flex-col bg-white shadow-xl lg:h-full">
                <div className="p-4 bg-stone-900 text-white font-bold flex justify-between"><span>Đơn hàng</span><span>{cart.length} món</span></div>
                
                <div className="flex-1 overflow-y-auto p-4 space-y-4 max-h-[50vh] lg:max-h-full">
                    {cart.map(item => (
                        <div key={item.variant_id} className="flex justify-between items-start border-b pb-2">
                            <div><div className="font-bold text-sm">{item.name}</div><div className="text-xs text-stone-500">{item.size} / {item.color}</div><div className="text-red-600 font-bold text-sm mt-1">{new Intl.NumberFormat('vi-VN').format(item.price)}</div></div>
                            <div className="flex flex-col items-end gap-2">
                                <button onClick={() => removeFromCart(item.variant_id)} className="text-stone-300 hover:text-red-500"><FaTrash size={12}/></button>
                                <div className="flex items-center border rounded"><button onClick={() => updateQty(item.variant_id, -1)} className="px-2 bg-stone-100">-</button><span className="px-2 text-sm font-bold">{item.quantity}</span><button onClick={() => updateQty(item.variant_id, 1)} className="px-2 bg-stone-100">+</button></div>
                            </div>
                        </div>
                    ))}
                </div>

                <div className="p-6 bg-stone-50 border-t">
                    {/* Tách rõ Tạm tính và Phí vận chuyển trên Giao diện */}
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