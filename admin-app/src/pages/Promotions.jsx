import { useState, useEffect } from 'react';
import axios from 'axios';
import { FaPlus, FaTrash, FaTicketAlt, FaTimes } from 'react-icons/fa';
import { toast } from 'react-toastify';

const Promotions = () => {
  const [promotions, setPromotions] = useState([]);
  const [showModal, setShowModal] = useState(false);
  const [loading, setLoading] = useState(false);
  
  // Form State
  const initialFormState = {
    code: '',
    discount_type: 'percent', // Khớp với Database: 'percent' hoặc 'fixed'
    discount_value: '',
    min_order_value: 0,
    max_discount_amount: '',
    usage_limit: 100,
    start_date: '',
    end_date: ''
  };
  const [formData, setFormData] = useState(initialFormState);

  useEffect(() => {
    fetchPromotions();
  }, []);

  const fetchPromotions = async () => {
    try {
      const res = await axios.get('http://localhost:5000/api/promotions');
      
      if(res.data.success && Array.isArray(res.data.data)) {
          setPromotions(res.data.data);
      } else {
          console.error("API trả về dữ liệu lỗi:", res.data);
          setPromotions([]); 
      }
    } catch (error) { 
        console.error("Lỗi mạng hoặc Server:", error);
        toast.error("Không thể kết nối tới Server lấy danh sách!");
    }
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);

    const payload = {
        ...formData,
        code: formData.code.toUpperCase().trim(),
        discount_value: Number(formData.discount_value),
        min_order_value: Number(formData.min_order_value) || 0,
        max_discount_amount: formData.max_discount_amount ? Number(formData.max_discount_amount) : null,
        usage_limit: Number(formData.usage_limit) || 100
    };

    if (!payload.code) { setLoading(false); return toast.warning("Nhập mã code!"); }

    try {
      await axios.post('http://localhost:5000/api/promotions', payload);
      toast.success("Tạo mã thành công!");
      setShowModal(false);
      fetchPromotions();
      setFormData(initialFormState);
    } catch (error) {
      const msg = error.response?.data?.message || "Lỗi tạo mã";
      toast.error(msg);
    } finally {
        setLoading(false);
    }
  };

  const handleDelete = async (id) => {
      if(!window.confirm("Xóa mã này?")) return;
      try {
          await axios.delete(`http://localhost:5000/api/promotions/${id}`);
          toast.success("Đã xóa mã");
          fetchPromotions();
      } catch (error) {
          toast.error("Lỗi khi xóa mã");
      }
  };

  // Hàm helper để hiển thị ngày an toàn
  const formatDate = (dateString) => {
      if (!dateString) return '---';
      try {
          return new Date(dateString).toLocaleDateString('vi-VN');
      } catch (e) {
          return 'Lỗi ngày';
      }
  };

  return (
    <div className="p-6">
      <div className="flex justify-between items-center mb-6">
        <h1 className="text-2xl font-serif font-bold text-stone-800">Quản lý Khuyến mãi</h1>
        <button 
          onClick={() => setShowModal(true)}
          className="bg-stone-900 text-white px-4 py-2 rounded flex items-center gap-2 hover:bg-black transition-all"
        >
          <FaPlus /> Tạo Mã Mới
        </button>
      </div>

      {/* DANH SÁCH MÃ */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {promotions.length === 0 ? (
              <p className="text-stone-500 italic col-span-3 text-center">Chưa có chương trình khuyến mãi nào.</p>
          ) : (
              promotions.map(promo => (
                <div key={promo.id} className="bg-white p-4 rounded-lg shadow border border-stone-200 relative group">
                    <div className="flex justify-between items-start">
                        <div>
                            <span className="bg-red-100 text-red-700 font-bold px-2 py-1 rounded text-sm uppercase tracking-wider">
                                {promo.code}
                            </span>
                            <p className="mt-2 font-bold text-stone-800 text-lg">
                                {/* Xử lý hiển thị % hay VNĐ */}
                                Giảm {promo.discount_type === 'percent' 
                                    ? `${promo.discount_value}%` 
                                    : `${new Intl.NumberFormat('vi-VN').format(promo.discount_value)}đ`
                                }
                            </p>
                            <p className="text-xs text-stone-500">Đơn tối thiểu: {new Intl.NumberFormat('vi-VN').format(promo.min_order_value)}đ</p>
                            <p className="text-xs text-stone-500 mt-1">
                                HSD: {formatDate(promo.end_date)}
                            </p>
                        </div>
                        <div className="text-right">
                            <p className="text-2xl font-bold text-stone-200"><FaTicketAlt /></p>
                            <p className="text-xs text-stone-400 mt-2">Đã dùng: {promo.used_count || 0}/{promo.usage_limit}</p>
                        </div>
                    </div>
                    <button 
                        onClick={() => handleDelete(promo.id)}
                        className="absolute top-2 right-2 text-stone-300 hover:text-red-500 opacity-0 group-hover:opacity-100 transition-opacity"
                    >
                        <FaTrash />
                    </button>
                </div>
            ))
          )}
      </div>

      {/* MODAL TẠO MÃ */}
      {showModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
            <div className="bg-white p-6 rounded-xl w-full max-w-lg shadow-2xl relative">
                <button onClick={() => setShowModal(false)} className="absolute top-4 right-4 text-stone-400 hover:text-red-500">
                    <FaTimes size={20}/>
                </button>
                <h2 className="text-xl font-bold mb-4 uppercase text-stone-800">Tạo mã giảm giá</h2>
                
                <form onSubmit={handleSubmit} className="space-y-4 max-h-[70vh] overflow-y-auto pr-2">
                    <div className="grid grid-cols-2 gap-4">
                        <div>
                            <label className="text-xs font-bold block mb-1">Mã Code (VD: TET2025)</label>
                            <input type="text" className="w-full p-2 border rounded uppercase" required
                                value={formData.code}
                                onChange={e => setFormData({...formData, code: e.target.value})} />
                        </div>
                        <div>
                             <label className="text-xs font-bold block mb-1">Loại giảm</label>
                             <select className="w-full p-2 border rounded"
                                value={formData.discount_type}
                                onChange={e => setFormData({...formData, discount_type: e.target.value})}>
                                 <option value="percent">Theo %</option>
                                 <option value="fixed">Số tiền (VNĐ)</option>
                             </select>
                        </div>
                    </div>

                    <div className="grid grid-cols-2 gap-4">
                        <div>
                            <label className="text-xs font-bold block mb-1">Giá trị giảm</label>
                            <input type="number" className="w-full p-2 border rounded" required
                                placeholder={formData.discount_type === 'percent' ? "VD: 10 (=10%)" : "VD: 50000"}
                                value={formData.discount_value}
                                onChange={e => setFormData({...formData, discount_value: e.target.value})} />
                        </div>
                        <div>
                            <label className="text-xs font-bold block mb-1">Đơn tối thiểu</label>
                            <input type="number" className="w-full p-2 border rounded"
                                value={formData.min_order_value}
                                onChange={e => setFormData({...formData, min_order_value: e.target.value})} />
                        </div>
                    </div>

                    {formData.discount_type === 'percent' && (
                        <div>
                            <label className="text-xs font-bold block mb-1">Giảm tối đa (VNĐ)</label>
                            <input type="number" placeholder="VD: 50000 (Để trống nếu không giới hạn)" className="w-full p-2 border rounded"
                                value={formData.max_discount_amount}
                                onChange={e => setFormData({...formData, max_discount_amount: e.target.value})} />
                        </div>
                    )}

                    <div>
                        <label className="text-xs font-bold block mb-1">Số lượng mã</label>
                        <input type="number" className="w-full p-2 border rounded"
                             value={formData.usage_limit}
                             onChange={e => setFormData({...formData, usage_limit: e.target.value})} />
                    </div>

                    <div className="grid grid-cols-2 gap-2">
                        <div>
                            <label className="text-xs font-bold block mb-1">Ngày bắt đầu</label>
                            <input type="date" className="w-full p-2 border rounded" required
                                value={formData.start_date}
                                onChange={e => setFormData({...formData, start_date: e.target.value})} />
                        </div>
                        <div>
                            <label className="text-xs font-bold block mb-1">Ngày kết thúc</label>
                            <input type="date" className="w-full p-2 border rounded" required
                                value={formData.end_date}
                                onChange={e => setFormData({...formData, end_date: e.target.value})} />
                        </div>
                    </div>

                    <div className="flex justify-end gap-2 mt-4 pt-4 border-t">
                        <button type="button" onClick={() => setShowModal(false)} className="px-4 py-2 bg-stone-200 rounded font-bold text-stone-600">Hủy</button>
                        <button disabled={loading} type="submit" className="px-4 py-2 bg-stone-900 text-white rounded font-bold hover:bg-black">
                            {loading ? 'Đang tạo...' : 'Lưu Mã'}
                        </button>
                    </div>
                </form>
            </div>
        </div>
      )}
    </div>
  );
};

export default Promotions;