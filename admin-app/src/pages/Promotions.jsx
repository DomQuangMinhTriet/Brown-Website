import { useState, useEffect } from 'react';
import axios from 'axios';
import { FaPlus, FaTrash, FaTicketAlt } from 'react-icons/fa';
import { toast } from 'react-toastify';

const Promotions = () => {
  const [promotions, setPromotions] = useState([]);
  const [showModal, setShowModal] = useState(false);
  
  // Form State
  const [formData, setFormData] = useState({
    code: '',
    discount_type: 'percentage', // percentage hoặc fixed
    discount_value: '',
    min_order_value: 0,
    max_discount_amount: '',
    usage_limit: 100,
    start_date: '',
    end_date: ''
  });

  useEffect(() => {
    fetchPromotions();
  }, []);

  const fetchPromotions = async () => {
    try {
      const res = await axios.get('http://localhost:5000/api/promotions');
      setPromotions(res.data.data);
    } catch (error) { console.error(error); }
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    try {
      await axios.post('http://localhost:5000/api/promotions', formData);
      toast.success("Tạo mã thành công!");
      setShowModal(false);
      fetchPromotions();
      // Reset form...
    } catch (error) {
      toast.error(error.response?.data?.message || "Lỗi tạo mã");
    }
  };

  const handleDelete = async (id) => {
    if(!confirm("Xóa mã này?")) return;
    try {
      await axios.delete(`http://localhost:5000/api/promotions/${id}`);
      fetchPromotions();
      toast.success("Đã xóa");
    } catch (error) { toast.error("Lỗi xóa"); }
  };

  return (
    <div className="p-8">
      <div className="flex justify-between items-center mb-6">
        <h1 className="text-2xl font-bold text-stone-800">Quản lý Khuyến mãi</h1>
        <button onClick={() => setShowModal(true)} className="bg-stone-900 text-white px-4 py-2 rounded flex items-center gap-2">
            <FaPlus/> Tạo Mã Mới
        </button>
      </div>

      {/* Danh sách Mã */}
      <div className="bg-white rounded-xl shadow border border-stone-200 overflow-hidden">
        <table className="w-full text-left">
          <thead className="bg-stone-50 border-b border-stone-200">
            <tr>
              <th className="p-4">Mã Code</th>
              <th className="p-4">Giảm giá</th>
              <th className="p-4">Đơn tối thiểu</th>
              <th className="p-4">Hạn dùng</th>
              <th className="p-4">Đã dùng</th>
              <th className="p-4"></th>
            </tr>
          </thead>
          <tbody>
            {promotions.map(p => (
              <tr key={p.id} className="border-b border-stone-100 hover:bg-stone-50">
                <td className="p-4 font-bold text-green-600 flex items-center gap-2">
                    <FaTicketAlt/> {p.code}
                </td>
                <td className="p-4">
                    {p.discount_type === 'percentage' ? `${p.discount_value}%` : `${new Intl.NumberFormat().format(p.discount_value)}đ`}
                </td>
                <td className="p-4">{new Intl.NumberFormat().format(p.min_order_value)}đ</td>
                <td className="p-4 text-sm text-stone-500">
                    {new Date(p.end_date).toLocaleDateString('vi-VN')}
                </td>
                <td className="p-4">
                    {p.used_count} / {p.usage_limit}
                </td>
                <td className="p-4 text-right">
                    <button onClick={() => handleDelete(p.id)} className="text-red-400 hover:text-red-600"><FaTrash/></button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Modal Tạo Mã (Đơn giản hóa) */}
      {showModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
            <div className="bg-white p-6 rounded-lg w-full max-w-md">
                <h3 className="font-bold text-xl mb-4">Tạo Mã Giảm Giá</h3>
                <form onSubmit={handleSubmit} className="space-y-3">
                    <input type="text" placeholder="Mã (VD: HELLO)" className="w-full p-2 border rounded uppercase" required
                        onChange={e => setFormData({...formData, code: e.target.value})} />
                    
                    <div className="flex gap-2">
                        <select className="p-2 border rounded" onChange={e => setFormData({...formData, discount_type: e.target.value})}>
                            <option value="percentage">Theo %</option>
                            <option value="fixed">Tiền mặt</option>
                        </select>
                        <input type="number" placeholder="Giá trị (VD: 10 hoặc 50000)" className="w-full p-2 border rounded" required
                            onChange={e => setFormData({...formData, discount_value: e.target.value})} />
                    </div>

                    <input type="number" placeholder="Đơn tối thiểu" className="w-full p-2 border rounded"
                        onChange={e => setFormData({...formData, min_order_value: e.target.value})} />
                    
                    {formData.discount_type === 'percentage' && (
                        <input type="number" placeholder="Giảm tối đa (VD: 50000)" className="w-full p-2 border rounded"
                            onChange={e => setFormData({...formData, max_discount_amount: e.target.value})} />
                    )}

                    <div className="grid grid-cols-2 gap-2">
                        <div>
                            <label className="text-xs">Ngày bắt đầu</label>
                            <input type="date" className="w-full p-2 border rounded" required
                                onChange={e => setFormData({...formData, start_date: e.target.value})} />
                        </div>
                        <div>
                            <label className="text-xs">Ngày kết thúc</label>
                            <input type="date" className="w-full p-2 border rounded" required
                                onChange={e => setFormData({...formData, end_date: e.target.value})} />
                        </div>
                    </div>

                    <div className="flex justify-end gap-2 mt-4">
                        <button type="button" onClick={() => setShowModal(false)} className="px-4 py-2 bg-stone-200 rounded">Hủy</button>
                        <button type="submit" className="px-4 py-2 bg-stone-900 text-white rounded">Tạo Mã</button>
                    </div>
                </form>
            </div>
        </div>
      )}
    </div>
  );
};

export default Promotions;