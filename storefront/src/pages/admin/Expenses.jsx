import { useState, useEffect } from 'react';
import axios from 'axios';
import { FaPlus, FaStore, FaTrash } from 'react-icons/fa';
import { toast } from 'react-toastify';

const Expenses = () => {
    // --- STATE DỮ LIỆU ---
    const [expenses, setExpenses] = useState([]);
    const [stores, setStores] = useState([]); 
    const [categories, setCategories] = useState([]); 

    // --- STATE FORM NHẬP LIỆU ---
    const [newExpense, setNewExpense] = useState({
        note: '',           
        amount: '',         
        category_id: '',    
        store_id: '',       
        expense_date: new Date().toISOString().split('T')[0]
    });

    // --- [MỚI] STATE TẠO DANH MỤC NHANH ---
    const [isAddingType, setIsAddingType] = useState(false);
    const [newTypeName, setNewTypeName] = useState('');

    // --- [MỚI] HELPER FORMAT TIỀN TỆ ---
    const formatCurrencyInput = (value) => {
        if (!value) return '';
        const number = Number(value.toString().replace(/\D/g, ''));
        return new Intl.NumberFormat('vi-VN').format(number);
    };

    useEffect(() => {
        fetchExpenses();
        fetchStores();
        fetchCategories();
    }, []);

    const fetchExpenses = async () => {
        try {
            const res = await axios.get(`${import.meta.env.VITE_API_URL}/api/expenses`);
            if (res.data.success) setExpenses(res.data.data);
        } catch (err) { console.error(err); }
    };

    const fetchStores = async () => {
        try {
            const res = await axios.get(`${import.meta.env.VITE_API_URL}/api/inventory/stores`);
            if (res.data.success) {
                setStores(res.data.data);
                if (res.data.data.length > 0) {
                    setNewExpense(prev => ({ ...prev, store_id: res.data.data[0].id }));
                }
            }
        } catch (err) { console.error(err); }
    };

    const fetchCategories = async () => {
        try {
            // Gọi API lấy danh sách danh mục
            const res = await axios.get(`${import.meta.env.VITE_API_URL}/api/expenses/categories`); 
            if (res.data.success) {
                setCategories(res.data.data);
                if (res.data.data.length > 0) {
                    setNewExpense(prev => ({ ...prev, category_id: res.data.data[0].id }));
                }
            }
        } catch (err) { console.error(err); }
    };

    // --- [MỚI] HÀM XỬ LÝ TẠO DANH MỤC ---
    const handleAddCategory = async () => {
        if (!newTypeName.trim()) return;
        try {
            // Gọi API vừa thêm ở Bước 1
            const res = await axios.post(`${import.meta.env.VITE_API_URL}/api/expenses/categories`, { name: newTypeName });
            
            if (res.data.success) {
                const newCat = res.data.data;
                setCategories([...categories, newCat]); // Cập nhật list ngay lập tức
                setNewExpense(prev => ({ ...prev, category_id: newCat.id })); // Chọn luôn loại vừa tạo
                
                setIsAddingType(false);
                setNewTypeName('');
                toast.success("Đã thêm loại chi phí mới");
            }
        } catch (error) {
            toast.error("Lỗi tạo: " + (error.response?.data?.message || error.message));
        }
    };

    const handleSubmit = async () => {
        if (!newExpense.amount || !newExpense.category_id) return toast.warn("Vui lòng nhập đủ tiền và loại chi phí");
        
        try {
            await axios.post(`${import.meta.env.VITE_API_URL}/api/expenses`, newExpense);
            toast.success("Đã lưu chi phí");
            setNewExpense(prev => ({ ...prev, note: '', amount: '' })); 
            fetchExpenses();
        } catch (err) { 
            toast.error("Lỗi lưu: " + (err.response?.data?.message || err.message)); 
        }
    };

    const handleDelete = async (id) => {
        if(!confirm("Xóa khoản chi này?")) return;
        try {
            await axios.delete(`${import.meta.env.VITE_API_URL}/api/expenses/${id}`);
            toast.success("Đã xóa");
            fetchExpenses();
        } catch (err) { toast.error("Lỗi xóa"); }
    }

    return (
        <div className="p-6 bg-stone-50 min-h-screen">
            <h1 className="text-2xl font-bold mb-6 text-stone-800">Quản lý Chi phí</h1>
            
            {/* FORM NHẬP LIỆU */}
            <div className="bg-white p-6 rounded-xl shadow-sm border border-stone-200 mb-8">
                <h3 className="font-bold text-stone-700 mb-4 border-b pb-2">Lập phiếu chi mới</h3>
                
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
                    
                    {/* 1. CHỌN CỬA HÀNG */}
                    <div>
                        <label className="block text-xs font-bold text-stone-500 mb-1">Chi nhánh / Kho</label>
                        <div className="relative">
                            <FaStore className="absolute left-3 top-3 text-stone-400"/>
                            <select 
                                className="w-full pl-9 p-2 border rounded bg-stone-50 focus:bg-white transition-colors outline-none focus:border-stone-800"
                                value={newExpense.store_id}
                                onChange={e => setNewExpense({...newExpense, store_id: e.target.value})}
                            >
                                <option value="">-- Chọn chi nhánh --</option>
                                {stores.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
                            </select>
                        </div>
                    </div>

                    {/* 2. LOẠI CHI PHÍ (Đã khôi phục nút +) */}
                    <div>
                        <label className="block text-xs font-bold text-stone-500 mb-1">Loại chi phí</label>
                        {!isAddingType ? (
                            <div className="flex gap-2">
                                <select 
                                    className="w-full p-2 border rounded bg-stone-50 focus:bg-white outline-none focus:border-stone-800"
                                    value={newExpense.category_id}
                                    onChange={e => setNewExpense({...newExpense, category_id: e.target.value})}
                                >
                                    <option value="">-- Chọn loại --</option>
                                    {categories.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
                                </select>
                                <button 
                                    onClick={() => setIsAddingType(true)} 
                                    className="px-3 bg-stone-200 rounded hover:bg-stone-300 text-stone-600"
                                    title="Thêm loại mới"
                                >
                                    <FaPlus size={12}/>
                                </button>
                            </div>
                        ) : (
                            <div className="flex gap-2">
                                <input 
                                    className="w-full p-2 border rounded border-blue-400 outline-none" 
                                    placeholder="Nhập tên..." 
                                    autoFocus
                                    value={newTypeName}
                                    onChange={e => setNewTypeName(e.target.value)}
                                />
                                <button onClick={handleAddCategory} className="bg-blue-600 text-white px-3 rounded text-xs font-bold">OK</button>
                                <button onClick={() => setIsAddingType(false)} className="text-stone-400 px-1 text-xs">Hủy</button>
                            </div>
                        )}
                    </div>

                    {/* 3. SỐ TIỀN */}
                    <div>
                        <label className="block text-xs font-bold text-stone-500 mb-1">Số tiền (VNĐ)</label>
                        <input 
                            type="text" 
                            className="w-full p-2 border rounded bg-stone-50 focus:bg-white outline-none focus:border-stone-800 font-bold text-stone-800"
                            placeholder="0"
                            value={formatCurrencyInput(newExpense.amount)}
                            onChange={e => {
                                const raw = e.target.value.replace(/\./g, '');
                                if (!isNaN(raw)) setNewExpense({...newExpense, amount: raw});
                            }}
                        />
                    </div>

                    {/* 4. NGÀY CHI */}
                    <div>
                        <label className="block text-xs font-bold text-stone-500 mb-1">Ngày chi</label>
                        <input 
                            type="date" 
                            className="w-full p-2 border rounded bg-stone-50 focus:bg-white outline-none focus:border-stone-800"
                            value={newExpense.expense_date}
                            onChange={e => setNewExpense({...newExpense, expense_date: e.target.value})}
                        />
                    </div>
                </div>
                
                <div className="mt-4">
                    <label className="block text-xs font-bold text-stone-500 mb-1">Mô tả chi tiết</label>
                    <div className="flex gap-4">
                        <input 
                            className="flex-1 p-2 border rounded bg-stone-50 focus:bg-white outline-none focus:border-stone-800" 
                            placeholder="VD: Mua văn phòng phẩm, tiền cafe tiếp khách..."
                            value={newExpense.note}
                            onChange={e => setNewExpense({...newExpense, note: e.target.value})}
                        />
                        <button 
                            onClick={handleSubmit} 
                            className="bg-stone-900 text-white px-8 py-2 rounded font-bold hover:bg-black transition-transform active:scale-95 shadow-lg"
                        >
                            LƯU PHIẾU
                        </button>
                    </div>
                </div>
            </div>

            {/* DANH SÁCH CHI PHÍ */}
            <div className="bg-white rounded-xl shadow-sm border border-stone-200 overflow-hidden">
                <table className="w-full text-left">
                    <thead className="bg-stone-100 text-stone-600 uppercase text-xs">
                        <tr>
                            <th className="p-4">Ngày</th>
                            <th className="p-4">Nội dung</th>
                            <th className="p-4">Loại / Kho</th>
                            <th className="p-4 text-right">Số tiền</th>
                            <th className="p-4 text-center">Hành động</th>
                        </tr>
                    </thead>
                    <tbody className="divide-y divide-stone-100">
                        {expenses.length === 0 && (
                            <tr><td colSpan="5" className="p-8 text-center text-stone-400 italic">Chưa có dữ liệu chi phí</td></tr>
                        )}
                        {expenses.map(item => (
                            <tr key={item.id} className="hover:bg-stone-50">
                                <td className="p-4 text-stone-500 text-sm">
                                    {new Date(item.expense_date || item.created_at).toLocaleDateString('vi-VN')}
                                </td>
                                <td className="p-4 font-medium text-stone-800">
                                    {item.note || item.description || 'Không có ghi chú'}
                                </td>
                                <td className="p-4 text-sm">
                                    <div className="font-bold text-stone-700">
                                        {item.expense_categories?.name || '---'}
                                    </div>
                                    <div className="text-xs text-stone-400">
                                        {item.stores?.name || '---'}
                                    </div>
                                </td>
                                <td className="p-4 text-right font-bold text-red-600">
                                    {new Intl.NumberFormat('vi-VN').format(item.amount)} ₫
                                </td>
                                <td className="p-4 text-center">
                                    <button onClick={() => handleDelete(item.id)} className="text-stone-300 hover:text-red-500 transition-colors">
                                        <FaTrash />
                                    </button>
                                </td>
                            </tr>
                        ))}
                    </tbody>
                </table>
            </div>
        </div>
    );
};

export default Expenses;