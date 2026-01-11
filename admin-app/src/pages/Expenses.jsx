import { useEffect, useState } from 'react';
import axios from 'axios';
import { FaMoneyBillAlt, FaPlus, FaTrash, FaCalendarAlt, FaStore, FaTag } from 'react-icons/fa';

const Expenses = () => {
  const [expenses, setExpenses] = useState([]);
  const [categories, setCategories] = useState([]);
  const [stores, setStores] = useState([]);
  
  // Form State
  const [formData, setFormData] = useState({
    amount: '',
    category_id: '',
    store_id: '',
    note: '',
    expense_date: new Date().toISOString().split('T')[0]
  });

  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    try {
      const [expRes, catRes, storeRes] = await Promise.all([
        axios.get('http://localhost:5000/api/expenses'),
        axios.get('http://localhost:5000/api/expenses/categories'),
        axios.get('http://localhost:5000/api/stores')
      ]);

      if(expRes.data.success) setExpenses(expRes.data.data);
      if(catRes.data.success) {
          setCategories(catRes.data.data);
          // Auto select first category
          if(catRes.data.data.length > 0) setFormData(prev => ({...prev, category_id: catRes.data.data[0].id}));
      }
      if(storeRes.data.success) {
          setStores(storeRes.data.data);
          if(storeRes.data.data.length > 0) setFormData(prev => ({...prev, store_id: storeRes.data.data[0].id}));
      }

    } catch (error) {
      console.error("Lỗi tải dữ liệu:", error);
    } finally {
      setLoading(false);
    }
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    if(!formData.amount || !formData.category_id) return alert("Vui lòng nhập số tiền và loại chi phí");

    try {
      const res = await axios.post('http://localhost:5000/api/expenses', formData);
      if(res.data.success) {
        alert("✅ Đã lưu phiếu chi!");
        setFormData({ ...formData, amount: '', note: '' }); // Reset form
        fetchData(); // Reload list
      }
    } catch (error) {
      alert("Lỗi: " + error.message);
    }
  };

  const handleDelete = async (id) => {
    if(!confirm("Bạn chắc chắn muốn xóa phiếu chi này?")) return;
    try {
      await axios.delete(`http://localhost:5000/api/expenses/${id}`);
      setExpenses(expenses.filter(e => e.id !== id));
    } catch (error) {
      alert("Lỗi xóa: " + error.message);
    }
  };

  const totalExpense = expenses.reduce((sum, item) => sum + Number(item.amount), 0);

  return (
    <div className="p-6 md:p-10 max-w-7xl mx-auto min-h-screen">
      <div className="flex flex-col md:flex-row justify-between items-start md:items-center mb-8 gap-4">
        <div>
          <h1 className="text-2xl font-bold text-stone-800">Sổ Quỹ (Chi phí)</h1>
          <p className="text-stone-500">Quản lý các khoản chi tiêu vận hành</p>
        </div>
        <div className="bg-red-50 text-red-700 px-6 py-3 rounded-xl border border-red-100">
            <span className="text-sm font-bold uppercase tracking-wide block">Tổng chi tiêu</span>
            <span className="text-2xl font-bold">{new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(totalExpense)}</span>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        
        {/* FORM NHẬP LIỆU */}
        <div className="bg-white p-6 rounded-xl border border-stone-200 shadow-sm h-fit">
            <h3 className="font-bold text-stone-800 mb-4 flex items-center gap-2">
                <FaPlus className="text-stone-400"/> Lập phiếu chi mới
            </h3>
            <form onSubmit={handleSubmit} className="space-y-4">
                <div>
                    <label className="block text-sm font-medium text-stone-600 mb-1">Ngày chi</label>
                    <div className="relative">
                        <FaCalendarAlt className="absolute left-3 top-3 text-stone-400"/>
                        <input type="date" className="w-full pl-10 p-2 border rounded bg-stone-50" 
                            value={formData.expense_date}
                            onChange={e => setFormData({...formData, expense_date: e.target.value})}
                        />
                    </div>
                </div>

                <div>
                    <label className="block text-sm font-medium text-stone-600 mb-1">Loại chi phí</label>
                    <div className="relative">
                        <FaTag className="absolute left-3 top-3 text-stone-400"/>
                        <select className="w-full pl-10 p-2 border rounded"
                            value={formData.category_id}
                            onChange={e => setFormData({...formData, category_id: e.target.value})}
                        >
                            {categories.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
                        </select>
                    </div>
                </div>

                <div>
                    <label className="block text-sm font-medium text-stone-600 mb-1">Số tiền (VNĐ)</label>
                    <div className="relative">
                        <FaMoneyBillAlt className="absolute left-3 top-3 text-stone-400"/>
                        <input type="number" className="w-full pl-10 p-2 border rounded font-bold text-stone-800" placeholder="0"
                            value={formData.amount}
                            onChange={e => setFormData({...formData, amount: e.target.value})}
                        />
                    </div>
                </div>

                <div>
                    <label className="block text-sm font-medium text-stone-600 mb-1">Chi nhánh chi trả</label>
                    <div className="relative">
                        <FaStore className="absolute left-3 top-3 text-stone-400"/>
                        <select className="w-full pl-10 p-2 border rounded"
                            value={formData.store_id}
                            onChange={e => setFormData({...formData, store_id: e.target.value})}
                        >
                            {stores.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
                        </select>
                    </div>
                </div>

                <div>
                    <label className="block text-sm font-medium text-stone-600 mb-1">Ghi chú / Diễn giải</label>
                    <textarea className="w-full p-2 border rounded" rows="3" placeholder="VD: Mua văn phòng phẩm..."
                        value={formData.note}
                        onChange={e => setFormData({...formData, note: e.target.value})}
                    ></textarea>
                </div>

                <button type="submit" className="w-full bg-stone-900 text-white py-3 rounded font-bold hover:bg-stone-700 transition-colors">
                    Lưu Phiếu Chi
                </button>
            </form>
        </div>

        {/* DANH SÁCH LỊCH SỬ */}
        <div className="lg:col-span-2 bg-white rounded-xl border border-stone-200 shadow-sm overflow-hidden">
            <div className="p-4 border-b border-stone-100 bg-stone-50 flex justify-between items-center">
                <span className="font-bold text-stone-700">Lịch sử chi tiêu gần đây</span>
            </div>
            
            <div className="overflow-x-auto">
                <table className="w-full text-left border-collapse">
                    <thead className="bg-white text-stone-500 text-xs uppercase">
                        <tr>
                            <th className="p-4">Ngày</th>
                            <th className="p-4">Nội dung</th>
                            <th className="p-4">Danh mục</th>
                            <th className="p-4 text-right">Số tiền</th>
                            <th className="p-4 text-center">Xóa</th>
                        </tr>
                    </thead>
                    <tbody className="divide-y divide-stone-100 text-sm">
                        {expenses.length === 0 && (
                            <tr><td colSpan="5" className="p-8 text-center text-stone-400">Chưa có dữ liệu</td></tr>
                        )}
                        {expenses.map(item => (
                            <tr key={item.id} className="hover:bg-stone-50">
                                <td className="p-4 text-stone-500 font-mono">
                                    {new Date(item.expense_date).toLocaleDateString('vi-VN')}
                                </td>
                                <td className="p-4">
                                    <div className="font-medium text-stone-800">{item.note || 'Không có ghi chú'}</div>
                                    <div className="text-xs text-stone-400">{item.stores?.name}</div>
                                </td>
                                <td className="p-4">
                                    <span className="bg-stone-100 text-stone-600 px-2 py-1 rounded text-xs">
                                        {item.expense_categories?.name}
                                    </span>
                                </td>
                                <td className="p-4 text-right font-bold text-red-600">
                                    -{new Intl.NumberFormat('vi-VN').format(item.amount)} ₫
                                </td>
                                <td className="p-4 text-center">
                                    <button onClick={() => handleDelete(item.id)} className="text-stone-300 hover:text-red-500 transition-colors">
                                        <FaTrash/>
                                    </button>
                                </td>
                            </tr>
                        ))}
                    </tbody>
                </table>
            </div>
        </div>

      </div>
    </div>
  );
};

export default Expenses;