import { useState, useEffect, useMemo } from 'react';
import axios from 'axios';
import { FaSearch, FaUser, FaMapMarkerAlt, FaPhone, FaTrash, FaBoxOpen } from 'react-icons/fa';
import { toast } from 'react-toastify';

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
    const [orderStatus, setOrderStatus] = useState('pending');

    // Load sản phẩm khi vào trang
    useEffect(() => {
        const fetchProducts = async () => {
            try {
                // Gọi API lấy sản phẩm (đã bao gồm logic tính tồn kho ở backend)
                const res = await axios.get('http://localhost:5000/api/products');
                if (res.data.success) setProducts(res.data.data);
            } catch (err) { console.error(err); }
        };
        fetchProducts();
    }, []);

    // Logic Giỏ hàng
    const addToCart = (product, variant) => {
        // SỬA: variant.stock -> variant.quantity_remaining
        if (variant.quantity_remaining <= 0) return toast.error("Hết hàng!");
        
        setCart(prev => {
            const existing = prev.find(item => item.variant_id === variant.id);
            if (existing) {
                // SỬA: variant.stock -> variant.quantity_remaining
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
                // SỬA: variant.stock -> variant.quantity_remaining
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
    const totalAmount = cart.reduce((sum, item) => sum + (item.price * item.quantity), 0);

    // Xử lý Gửi đơn hàng
    const handleCreateOrder = async () => {
        if (cart.length === 0) return toast.error("Giỏ hàng trống!");
        if (!customerInfo.phone) return toast.error("Vui lòng nhập SĐT khách hàng");

        const payload = {
            customer: {
                fullName: customerInfo.name || "Khách lẻ",
                phone: customerInfo.phone,
                address: customerInfo.address || "Tại quầy",
                email: "" // Để trống nếu không có
            },
            items: cart.map(item => ({
                product_id: item.product_id || item.id, // Gửi thêm product_id
                variant_id: item.variant_id,
                quantity: item.quantity,
                price: item.price
            })),
            
            // FIX: Gửi đúng key 'payment_method' (snake_case)
            payment_method: paymentMethod, 
            
        
            
            note: customerInfo.note
        };

        try {
            const res = await axios.post('http://localhost:5000/api/orders/create-admin', payload);
            if (res.data.success) {
                toast.success("Tạo đơn hàng thành công!");
                // Reset form
                setCart([]);
                setCustomerInfo({ name: '', phone: '', address: '', note: '' });
                setSearch('');
            }
        } catch (error) {
            console.error(error);
            toast.error(error.response?.data?.message || "Lỗi tạo đơn hàng");
        }
    };

    // Filter tìm kiếm
    const filteredProducts = useMemo(() => {
        return products.filter(p => 
            p.name.toLowerCase().includes(search.toLowerCase()) || 
            p.variants?.some(v => v.sku.toLowerCase().includes(search.toLowerCase()))
        );
    }, [products, search]);

    return (
        <div className="flex flex-col lg:flex-row h-screen bg-stone-100 overflow-hidden">
            {/* CỘT 1: DANH SÁCH SẢN PHẨM */}
            <div className="lg:w-2/5 flex flex-col p-4 border-r border-stone-200 bg-white">
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
                                {/* Tìm đoạn code hiển thị variants trong phần return */}
                                <div className="flex flex-wrap gap-1 mt-2">
                                    {p.variants?.map(v => (
                                        <button 
                                            key={v.id} 
                                            onClick={() => addToCart(p, v)} 
                                            // SỬA: v.stock -> v.quantity_remaining
                                            disabled={v.quantity_remaining <= 0} 
                                            className={`text-xs px-2 py-1 border rounded ${
                                                // SỬA: v.stock -> v.quantity_remaining
                                                v.quantity_remaining > 0 
                                                ? 'hover:bg-stone-800 hover:text-white' 
                                                : 'bg-stone-100 text-stone-300 line-through'
                                            }`}
                                        >
                                            {/* SỬA: v.stock -> v.quantity_remaining */}
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
            <div className="lg:w-1/4 p-6 overflow-y-auto bg-stone-50 border-r border-stone-200">
                <h2 className="font-bold text-lg mb-6 flex items-center gap-2"><FaUser/> Khách hàng</h2>
                <div className="space-y-4">
                    <div><label className="text-xs font-bold text-stone-500 block mb-1">Tên khách (*)</label><input className="w-full p-2 border rounded bg-white" value={customerInfo.name} onChange={e => setCustomerInfo({...customerInfo, name: e.target.value})} /></div>
                    <div><label className="text-xs font-bold text-stone-500 block mb-1">Điện thoại (*)</label><div className="relative"><FaPhone className="absolute left-3 top-3 text-stone-400 text-xs"/><input className="w-full pl-8 p-2 border rounded bg-white" value={customerInfo.phone} onChange={e => setCustomerInfo({...customerInfo, phone: e.target.value})} /></div></div>
                    <div><label className="text-xs font-bold text-stone-500 block mb-1">Địa chỉ giao</label><div className="relative"><FaMapMarkerAlt className="absolute left-3 top-3 text-stone-400 text-xs"/><textarea className="w-full pl-8 p-2 border rounded bg-white h-20" value={customerInfo.address} onChange={e => setCustomerInfo({...customerInfo, address: e.target.value})} /></div></div>
                    <div><label className="text-xs font-bold text-stone-500 block mb-1">Ghi chú</label><input className="w-full p-2 border rounded bg-white" placeholder="Nguồn đơn..." value={customerInfo.note} onChange={e => setCustomerInfo({...customerInfo, note: e.target.value})} /></div>
                </div>
            </div>

            {/* CỘT 3: CHI TIẾT & THANH TOÁN */}
            <div className="flex-1 flex flex-col bg-white shadow-xl">
                <div className="p-4 bg-stone-900 text-white font-bold flex justify-between"><span>Đơn hàng</span><span>{cart.length} món</span></div>
                <div className="flex-1 overflow-y-auto p-4 space-y-4">
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
                    <div className="flex justify-between mb-4 text-xl font-bold"><span>Tổng tiền:</span><span className="text-red-600">{new Intl.NumberFormat('vi-VN').format(totalAmount)} ₫</span></div>
                    <div className="grid grid-cols-2 gap-4 mb-4">
                        <div><label className="text-xs font-bold block mb-1">Thanh toán</label><select className="w-full p-2 border rounded bg-white" value={paymentMethod} onChange={e => setPaymentMethod(e.target.value)}><option value="cod">COD (Thu hộ)</option><option value="transfer">Chuyển khoản</option></select></div>
                        <div><label className="text-xs font-bold block mb-1">Trạng thái TT</label><select className="w-full p-2 border rounded bg-white" value={isPaid} onChange={e => setIsPaid(e.target.value === 'true')}><option value="false">Chưa thanh toán</option><option value="true">Đã thanh toán</option></select></div>
                    </div>
                    <button onClick={handleCreateOrder} className="w-full bg-stone-900 text-white py-3 rounded font-bold uppercase hover:bg-black shadow-lg">TẠO ĐƠN HÀNG</button>
                </div>
            </div>
        </div>
    );
};

export default CreateOrder;