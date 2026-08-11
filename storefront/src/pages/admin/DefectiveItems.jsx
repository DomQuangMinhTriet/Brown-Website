import { useEffect, useState } from 'react';
import axios from 'axios';
import { FaPlus, FaExclamationTriangle, FaTimes, FaSpinner } from 'react-icons/fa';
import { toast } from 'react-toastify';

const DefectiveItems = () => {
  const [logs, setLogs] = useState([]);
  const [loading, setLoading] = useState(true);
  
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [products, setProducts] = useState([]);
  const [selectedProduct, setSelectedProduct] = useState(null);
  const [selectedVariant, setSelectedVariant] = useState(null);
  const [formData, setFormData] = useState({ quantity: 1, reason: '' });
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    fetchLogs();
    fetchProducts();
  }, []);

  const fetchLogs = async () => {
      try {
          const res = await axios.get(`${import.meta.env.VITE_API_URL}/api/inventory/defective`);
          if (res.data.success) setLogs(res.data.data);
      } catch (error) {
          console.error(error);
      } finally {
          setLoading(false);
      }
  };

  const fetchProducts = async () => {
      try {
          const res = await axios.get(`${import.meta.env.VITE_API_URL}/api/products?admin=true&view=card`);
          if (res.data.success) setProducts(res.data.data);
      } catch (error) {
          console.error(error);
      }
  };

  const handleProductChange = (productId) => {
      const prod = products.find(p => p.id === Number(productId));
      setSelectedProduct(prod);
      setSelectedVariant(null);
  };

  const handleSubmit = async () => {
      if (!selectedProduct || formData.quantity <= 0 || !formData.reason) {
          return toast.warning("Vui lòng nhập đầy đủ thông tin hàng lỗi!");
      }
      if (selectedProduct.variants?.length > 0 && !selectedVariant) {
          return toast.warning("Vui lòng chọn phân loại hàng bị lỗi!");
      }

      setSubmitting(true);
      try {
          const finalVariant = selectedVariant || (selectedProduct.variants?.length > 0 ? selectedProduct.variants[0] : null);
          const finalVariantName = finalVariant ? `${finalVariant.size} - ${finalVariant.color}` : 'Mặc định';

          // [ĐÃ SỬA]: Gửi kèm Tên sản phẩm và Phân loại để lưu vào Bảng Chi phí
          const payload = {
              variant_id: finalVariant.id,
              quantity: Number(formData.quantity),
              reason: formData.reason,
              product_name: selectedProduct.name,
              variant_name: finalVariantName
          };

          const res = await axios.post(`${import.meta.env.VITE_API_URL}/api/inventory/defective`, payload);
          
          if (res.data.success) {
              toast.success(`Đã trừ kho và hạch toán ${new Intl.NumberFormat('vi-VN').format(res.data.totalLoss)}đ vào Chi phí.`);
              setIsModalOpen(false);
              fetchLogs(); 
              
              setSelectedProduct(null);
              setSelectedVariant(null);
              setFormData({ quantity: 1, reason: '' });
          }
      } catch (error) {
          toast.error("Lỗi: " + (error.response?.data?.message || "Không thể lưu báo cáo"));
      } finally {
          setSubmitting(false);
      }
  };

  const totalLossAmount = logs.reduce((sum, log) => sum + Math.abs(log.original_quantity * log.cost_price), 0);

  return (
    <div className="p-4 md:p-6 max-w-7xl mx-auto animate-fade-in">
        <div className="flex flex-col md:flex-row md:items-center justify-between mb-6 gap-4">
            <div>
                <h1 className="text-2xl font-bold text-stone-800 flex items-center gap-2">
                    <FaExclamationTriangle className="text-orange-500"/> Quản lý Hàng Lỗi
                </h1>
                <p className="text-stone-500 mt-1">Ghi nhận hư hỏng, rách lỗi để trừ kho và tính chi phí giá vốn tự động.</p>
            </div>
            <button 
                onClick={() => setIsModalOpen(true)} 
                className="bg-orange-600 text-white px-6 py-3 rounded-lg flex items-center justify-center gap-2 hover:bg-orange-700 shadow-lg font-bold"
            >
                <FaPlus size={14} /> Báo cáo hàng lỗi
            </button>
        </div>

        {/* THỐNG KÊ */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
            <div className="bg-white p-6 rounded-xl shadow-sm border-l-4 border-l-orange-500">
                <p className="text-stone-500 text-sm font-bold uppercase mb-1">Tổng sản phẩm hỏng</p>
                <p className="text-3xl font-black text-stone-800">{logs.reduce((sum, l) => sum + Math.abs(l.original_quantity), 0)} <span className="text-base font-medium">sp</span></p>
            </div>
            <div className="bg-white p-6 rounded-xl shadow-sm border-l-4 border-l-red-600">
                <p className="text-stone-500 text-sm font-bold uppercase mb-1">Tổng thiệt hại vốn</p>
                <p className="text-3xl font-black text-red-600">{new Intl.NumberFormat('vi-VN').format(totalLossAmount)} ₫</p>
            </div>
        </div>

        {/* BẢNG LỊCH SỬ */}
        <div className="bg-white rounded-xl shadow-sm border border-stone-200 overflow-hidden">
            <table className="w-full text-left border-collapse">
                <thead className="bg-stone-50 text-stone-600 uppercase text-xs font-bold border-b border-stone-200">
                    <tr>
                        <th className="p-4">Ngày báo</th>
                        <th className="p-4">Sản phẩm / Phân loại</th>
                        <th className="p-4">Ghi chú lỗi</th>
                        <th className="p-4 text-center">Số lượng</th>
                        <th className="p-4 text-right">Tổng Giá Vốn mất đi</th>
                    </tr>
                </thead>
                <tbody className="divide-y divide-stone-100">
                    {loading ? <tr><td colSpan="5" className="p-8 text-center text-stone-500">Đang tải...</td></tr> : 
                    logs.map((log) => {
                        const qty = Math.abs(log.original_quantity);
                        const loss = qty * log.cost_price;
                        // [ĐÃ SỬA]: Kiểm tra alias từ DB an toàn hơn (products hoặc product)
                        const productName = log.variants?.products?.name || log.variants?.product?.name || "Sản phẩm đã bị xóa";
                        
                        return (
                            <tr key={log.id} className="hover:bg-orange-50/50">
                                <td className="p-4 text-sm text-stone-500">
                                    {new Date(log.created_at).toLocaleString('vi-VN')}
                                </td>
                                <td className="p-4">
                                    <div className="font-bold text-stone-800">{productName}</div>
                                    <div className="text-xs text-stone-500">{log.variants?.size} - {log.variants?.color} | SKU: {log.variants?.sku}</div>
                                </td>
                                <td className="p-4 text-sm font-medium text-red-600">{log.notes.replace('[HÀNG LỖI] ', '')}</td>
                                <td className="p-4 text-center font-bold text-lg">{qty}</td>
                                <td className="p-4 text-right font-bold text-stone-900">-{new Intl.NumberFormat('vi-VN').format(loss)} ₫</td>
                            </tr>
                        );
                    })}
                    {!loading && logs.length === 0 && (
                        <tr><td colSpan="5" className="p-8 text-center text-stone-500">Tuyệt vời! Cửa hàng chưa ghi nhận hàng lỗi nào.</td></tr>
                    )}
                </tbody>
            </table>
        </div>

        {/* MODAL */}
        {isModalOpen && (
            <div className="fixed inset-0 bg-black/60 z-50 flex items-center justify-center p-4">
                <div className="bg-white rounded-xl w-full max-w-xl shadow-2xl flex flex-col">
                    <div className="p-5 border-b flex justify-between items-center bg-orange-50 rounded-t-xl">
                        <h2 className="text-lg font-bold text-orange-800 flex items-center gap-2">
                            <FaExclamationTriangle/> Báo cáo sản phẩm lỗi
                        </h2>
                        <button onClick={() => setIsModalOpen(false)} className="text-stone-400 hover:text-red-500"><FaTimes size={20}/></button>
                    </div>

                    <div className="p-6 space-y-6">
                        <div>
                            <label className="block text-xs font-bold uppercase text-stone-500 mb-2">1. Chọn Sản phẩm</label>
                            <select 
                                className="w-full p-3 border border-stone-200 rounded-lg outline-none focus:border-orange-500"
                                value={selectedProduct?.id || ''}
                                onChange={(e) => handleProductChange(e.target.value)}
                            >
                                <option value="">-- Tìm chọn sản phẩm --</option>
                                {products.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
                            </select>
                        </div>

                        {selectedProduct && selectedProduct.variants?.length > 0 && (
                            <div className="p-4 bg-stone-50 border border-stone-200 rounded-lg">
                                <label className="block text-xs font-bold uppercase text-stone-500 mb-3">2. Chọn phân loại bị lỗi</label>
                                <div className="flex flex-wrap gap-2">
                                    {selectedProduct.variants.map(v => (
                                        <button 
                                            key={v.id}
                                            onClick={() => setSelectedVariant(v)}
                                            className={`px-3 py-2 border rounded-md text-sm transition-colors ${selectedVariant?.id === v.id ? 'bg-stone-900 text-white border-stone-900' : 'bg-white text-stone-700 hover:border-stone-400'}`}
                                        >
                                            {v.size} - {v.color}
                                        </button>
                                    ))}
                                </div>
                            </div>
                        )}

                        <div className="grid grid-cols-2 gap-6">
                            <div className="col-span-2">
                                <label className="block text-xs font-bold uppercase text-stone-500 mb-2">Số lượng hư hỏng / lỗi</label>
                                <input 
                                    type="number" min="1"
                                    className="w-full p-3 border border-stone-200 rounded-lg outline-none focus:border-orange-500 font-bold text-xl text-center"
                                    value={formData.quantity}
                                    onChange={e => setFormData({...formData, quantity: Math.max(1, e.target.value)})}
                                />
                            </div>
                            <div className="col-span-2">
                                <label className="block text-xs font-bold uppercase text-stone-500 mb-2">Lý do lỗi / Ghi chú (Bắt buộc)</label>
                                <textarea 
                                    className="w-full p-3 border border-stone-200 rounded-lg outline-none focus:border-orange-500 h-24"
                                    placeholder="Ví dụ: Áo bị rách phần nách khi kiểm kho, dính vết bẩn không giặt được..."
                                    value={formData.reason}
                                    onChange={e => setFormData({...formData, reason: e.target.value})}
                                />
                            </div>
                        </div>
                        <p className="text-xs text-red-500 italic mt-2">*Hệ thống sẽ tự động dò giá vốn của sản phẩm này để tính tổng chi phí thiệt hại.</p>
                    </div>

                    <div className="p-5 border-t border-stone-100 flex justify-end gap-3 bg-stone-50 rounded-b-xl">
                        <button onClick={() => setIsModalOpen(false)} className="px-6 py-2 rounded font-bold text-stone-500 hover:bg-stone-200">Hủy</button>
                        <button 
                            onClick={handleSubmit} disabled={submitting}
                            className="px-6 py-2 rounded font-bold text-white bg-orange-600 hover:bg-orange-700 flex items-center gap-2 disabled:opacity-50"
                        >
                            {submitting ? <FaSpinner className="animate-spin"/> : 'Xác nhận Trừ kho'}
                        </button>
                    </div>
                </div>
            </div>
        )}
    </div>
  );
};

export default DefectiveItems;
