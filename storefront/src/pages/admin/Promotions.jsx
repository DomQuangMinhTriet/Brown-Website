import { useState, useEffect, useMemo } from 'react';
import axios from 'axios';
import { FaPlus, FaTrash, FaTicketAlt, FaTimes, FaTags, FaSearch } from 'react-icons/fa';
import { toast } from 'react-toastify';

const API = import.meta.env.VITE_API_URL;

const Promotions = () => {
  const [promotions, setPromotions] = useState([]);
  const [products, setProducts] = useState([]);
  const [showModal, setShowModal] = useState(false);
  const [loading, setLoading] = useState(false);
  const [productSearch, setProductSearch] = useState('');   // cho ô chọn SP áp dụng voucher
  const [discountSearch, setDiscountSearch] = useState('');  // cho mục giảm giá trực tiếp

  const initialFormState = {
    code: '',
    discount_type: 'percent',
    discount_value: '',
    min_order_value: 0,
    max_discount_amount: '',
    usage_limit: 100,
    unlimited_usage: false,
    start_date: '',
    end_date: '',
    unlimited_time: false,
    applicable_product_ids: [], // rỗng = áp cho mọi SP
  };
  const [formData, setFormData] = useState(initialFormState);

  const formatCurrencyInput = (value) => {
    if (!value) return '';
    const number = Number(value.toString().replace(/\D/g, ''));
    return new Intl.NumberFormat('vi-VN').format(number);
  };
  const money = (v) => new Intl.NumberFormat('vi-VN').format(Number(v) || 0);

  useEffect(() => {
    fetchPromotions();
    fetchProducts();
  }, []);

  const fetchPromotions = async () => {
    try {
      const res = await axios.get(`${API}/api/promotions`);
      setPromotions(res.data.success && Array.isArray(res.data.data) ? res.data.data : []);
    } catch (error) {
      toast.error("Không thể kết nối tới Server lấy danh sách!");
    }
  };

  const fetchProducts = async () => {
    try {
      const res = await axios.get(`${API}/api/products?admin=true`);
      setProducts(res.data.success ? res.data.data : []);
    } catch (error) {
      console.error("Lỗi tải sản phẩm:", error);
    }
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);

    const payload = {
      code: formData.code.toUpperCase().trim(),
      discount_type: formData.discount_type,
      discount_value: Number(formData.discount_value),
      min_order_value: Number(formData.min_order_value) || 0,
      max_discount_amount: formData.max_discount_amount ? Number(formData.max_discount_amount) : null,
      usage_limit: formData.unlimited_usage ? null : (Number(formData.usage_limit) || null),
      start_date: formData.start_date || null,
      end_date: formData.unlimited_time ? null : (formData.end_date || null),
      applicable_product_ids: formData.applicable_product_ids,
    };

    if (!payload.code) { setLoading(false); return toast.warning("Nhập mã code!"); }

    try {
      await axios.post(`${API}/api/promotions`, payload);
      toast.success("Tạo mã thành công!");
      setShowModal(false);
      fetchPromotions();
      setFormData(initialFormState);
      setProductSearch('');
    } catch (error) {
      toast.error(error.response?.data?.message || "Lỗi tạo mã");
    } finally {
      setLoading(false);
    }
  };

  const handleDelete = async (id) => {
    if (!window.confirm("Xóa mã này?")) return;
    try {
      await axios.delete(`${API}/api/promotions/${id}`);
      toast.success("Đã xóa mã");
      fetchPromotions();
    } catch (error) {
      toast.error("Lỗi khi xóa mã");
    }
  };

  const formatDate = (d) => (d ? new Date(d).toLocaleDateString('vi-VN') : 'Không giới hạn');

  const toggleApplicable = (id) => {
    setFormData(prev => ({
      ...prev,
      applicable_product_ids: prev.applicable_product_ids.includes(id)
        ? prev.applicable_product_ids.filter(x => x !== id)
        : [...prev.applicable_product_ids, id],
    }));
  };

  // --- GIẢM GIÁ TRỰC TIẾP ---
  const saveDiscount = async (product, { discount_amount, is_discount_active }) => {
    try {
      const res = await axios.put(`${API}/api/products/${product.id}/discount`, { discount_amount, is_discount_active });
      if (res.data.success) {
        setProducts(prev => prev.map(p => (p.id === product.id ? { ...p, ...res.data.data } : p)));
        toast.success(`Đã cập nhật giảm giá: ${product.name}`);
      }
    } catch (error) {
      toast.error("Lỗi lưu giảm giá");
    }
  };

  const promoProducts = products.filter(p => p.name.toLowerCase().includes(productSearch.toLowerCase()));
  const discountProducts = products.filter(p => p.name.toLowerCase().includes(discountSearch.toLowerCase()));
  const productNameById = useMemo(() => Object.fromEntries(products.map(p => [p.id, p.name])), [products]);

  return (
    <div className="p-6 space-y-10">
      {/* ============ PHẦN 1: VOUCHER ============ */}
      <div>
        <div className="flex justify-between items-center mb-6">
          <h1 className="text-2xl font-serif font-bold text-stone-800 flex items-center gap-2"><FaTicketAlt /> Mã giảm giá (Voucher)</h1>
          <button onClick={() => setShowModal(true)} className="bg-stone-900 text-white px-4 py-2 rounded flex items-center gap-2 hover:bg-black transition-all">
            <FaPlus /> Tạo Mã Mới
          </button>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {promotions.length === 0 ? (
            <p className="text-stone-500 italic col-span-3 text-center">Chưa có mã khuyến mãi nào.</p>
          ) : (
            promotions.map(promo => (
              <div key={promo.id} className="bg-white p-4 rounded-lg shadow border border-stone-200 relative group">
                <div className="flex justify-between items-start">
                  <div>
                    <span className="bg-red-100 text-red-700 font-bold px-2 py-1 rounded text-sm uppercase tracking-wider">{promo.code}</span>
                    <p className="mt-2 font-bold text-stone-800 text-lg">
                      Giảm {promo.discount_type === 'percent' ? `${promo.discount_value}%` : `${money(promo.discount_value)}đ`}
                    </p>
                    <p className="text-xs text-stone-500">Đơn tối thiểu: {money(promo.min_order_value)}đ</p>
                    <p className="text-xs text-stone-500 mt-1">HSD: {formatDate(promo.end_date)}</p>
                    {Array.isArray(promo.applicable_product_ids) && promo.applicable_product_ids.length > 0 && (
                      <p className="text-xs text-blue-600 mt-1 font-medium">
                        Chỉ áp dụng cho: {promo.applicable_product_ids.map(id => productNameById[id] || `#${id}`).join(', ')}
                      </p>
                    )}
                  </div>
                  <div className="text-right">
                    <p className="text-2xl font-bold text-stone-200"><FaTicketAlt /></p>
                    <p className="text-xs text-stone-400 mt-2">Đã dùng: {promo.used_count || 0}/{promo.usage_limit == null ? '∞' : promo.usage_limit}</p>
                  </div>
                </div>
                <button onClick={() => handleDelete(promo.id)} className="absolute top-2 right-2 text-stone-300 hover:text-red-500 opacity-0 group-hover:opacity-100 transition-opacity">
                  <FaTrash />
                </button>
              </div>
            ))
          )}
        </div>
      </div>

      {/* ============ PHẦN 2: GIẢM GIÁ TRỰC TIẾP ============ */}
      <div>
        <h2 className="text-2xl font-serif font-bold text-stone-800 mb-2 flex items-center gap-2"><FaTags /> Giảm giá sản phẩm trực tiếp</h2>
        <p className="text-stone-500 text-sm mb-4">Giảm thẳng theo số tiền trên giá bán. Bật công tắc để áp dụng ngay cho khách và khi tạo đơn. Không cộng dồn với voucher.</p>

        <div className="relative mb-4 max-w-md">
          <FaSearch className="absolute left-3 top-3 text-stone-400" />
          <input className="w-full pl-10 pr-4 py-2 border rounded outline-none" placeholder="Tìm sản phẩm..." value={discountSearch} onChange={e => setDiscountSearch(e.target.value)} />
        </div>

        <div className="bg-white rounded-xl border border-stone-200 divide-y divide-stone-100 max-h-[520px] overflow-y-auto">
          {discountProducts.length === 0 ? (
            <p className="p-6 text-center text-stone-400">Không có sản phẩm</p>
          ) : (
            discountProducts.map(p => <DiscountRow key={p.id} product={p} onSave={saveDiscount} money={money} />)
          )}
        </div>
      </div>

      {/* MODAL TẠO MÃ */}
      {showModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-white p-6 rounded-xl w-full max-w-lg shadow-2xl relative">
            <button onClick={() => setShowModal(false)} className="absolute top-4 right-4 text-stone-400 hover:text-red-500"><FaTimes size={20} /></button>
            <h2 className="text-xl font-bold mb-4 uppercase text-stone-800">Tạo mã giảm giá</h2>

            <form onSubmit={handleSubmit} className="space-y-4 max-h-[75vh] overflow-y-auto pr-2">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="text-xs font-bold block mb-1">Mã Code</label>
                  <input type="text" className="w-full p-2 border rounded uppercase" required value={formData.code} onChange={e => setFormData({ ...formData, code: e.target.value })} />
                </div>
                <div>
                  <label className="text-xs font-bold block mb-1">Loại giảm</label>
                  <select className="w-full p-2 border rounded" value={formData.discount_type} onChange={e => setFormData({ ...formData, discount_type: e.target.value })}>
                    <option value="percent">Theo %</option>
                    <option value="fixed">Số tiền (VNĐ)</option>
                  </select>
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="text-xs font-bold block mb-1">Giá trị giảm</label>
                  {formData.discount_type === 'percent' ? (
                    <input type="number" className="w-full p-2 border rounded" required placeholder="VD: 10 (=10%)" value={formData.discount_value} onChange={e => setFormData({ ...formData, discount_value: e.target.value })} />
                  ) : (
                    <input type="text" className="w-full p-2 border rounded" required placeholder="VD: 50.000" value={formatCurrencyInput(formData.discount_value)}
                      onChange={e => { const raw = e.target.value.replace(/\./g, ''); if (!isNaN(raw)) setFormData({ ...formData, discount_value: raw }); }} />
                  )}
                </div>
                <div>
                  <label className="text-xs font-bold block mb-1">Đơn tối thiểu</label>
                  <input type="text" className="w-full p-2 border rounded" placeholder="0" value={formatCurrencyInput(formData.min_order_value)}
                    onChange={e => { const raw = e.target.value.replace(/\./g, ''); if (!isNaN(raw)) setFormData({ ...formData, min_order_value: raw }); }} />
                </div>
              </div>

              {formData.discount_type === 'percent' && (
                <div>
                  <label className="text-xs font-bold block mb-1">Giảm tối đa (VNĐ)</label>
                  <input type="text" placeholder="VD: 50.000 (Để trống nếu không giới hạn)" className="w-full p-2 border rounded" value={formatCurrencyInput(formData.max_discount_amount)}
                    onChange={e => { const raw = e.target.value.replace(/\./g, ''); if (!isNaN(raw)) setFormData({ ...formData, max_discount_amount: raw }); }} />
                </div>
              )}

              {/* Số lượng + không giới hạn */}
              <div>
                <label className="text-xs font-bold block mb-1">Số lượng mã</label>
                <div className="flex items-center gap-3">
                  <input type="number" disabled={formData.unlimited_usage} className="flex-1 p-2 border rounded disabled:bg-stone-100 disabled:text-stone-400"
                    value={formData.unlimited_usage ? '' : formData.usage_limit} onChange={e => setFormData({ ...formData, usage_limit: e.target.value })} />
                  <label className="flex items-center gap-2 text-sm whitespace-nowrap">
                    <input type="checkbox" checked={formData.unlimited_usage} onChange={e => setFormData({ ...formData, unlimited_usage: e.target.checked })} /> Không giới hạn
                  </label>
                </div>
              </div>

              {/* Thời gian + không giới hạn */}
              <div className="grid grid-cols-2 gap-2">
                <div>
                  <label className="text-xs font-bold block mb-1">Ngày bắt đầu</label>
                  <input type="date" className="w-full p-2 border rounded" value={formData.start_date} onChange={e => setFormData({ ...formData, start_date: e.target.value })} />
                </div>
                <div>
                  <label className="text-xs font-bold block mb-1">Ngày kết thúc</label>
                  <input type="date" disabled={formData.unlimited_time} className="w-full p-2 border rounded disabled:bg-stone-100" value={formData.unlimited_time ? '' : formData.end_date} onChange={e => setFormData({ ...formData, end_date: e.target.value })} />
                </div>
              </div>
              <label className="flex items-center gap-2 text-sm">
                <input type="checkbox" checked={formData.unlimited_time} onChange={e => setFormData({ ...formData, unlimited_time: e.target.checked })} /> Không giới hạn thời gian
              </label>

              {/* Áp dụng cho sản phẩm cụ thể */}
              <div>
                <label className="text-xs font-bold block mb-1">
                  Áp dụng cho sản phẩm ({formData.applicable_product_ids.length === 0 ? 'Tất cả sản phẩm' : `${formData.applicable_product_ids.length} SP đã chọn`})
                </label>
                <div className="relative mb-2">
                  <FaSearch className="absolute left-3 top-2.5 text-stone-400 text-xs" />
                  <input className="w-full pl-8 pr-3 py-1.5 border rounded text-sm outline-none" placeholder="Tìm để chọn SP (để trống = áp cho tất cả)" value={productSearch} onChange={e => setProductSearch(e.target.value)} />
                </div>
                <div className="border rounded max-h-40 overflow-y-auto divide-y divide-stone-100">
                  {promoProducts.slice(0, 50).map(p => (
                    <label key={p.id} className="flex items-center gap-2 px-3 py-2 text-sm hover:bg-stone-50 cursor-pointer">
                      <input type="checkbox" checked={formData.applicable_product_ids.includes(p.id)} onChange={() => toggleApplicable(p.id)} />
                      <img src={p.images?.[0]} alt="" className="w-8 h-8 object-cover rounded bg-stone-100" />
                      <span className="flex-1 truncate">{p.name}</span>
                      <span className="text-xs text-stone-400">{money(p.base_price)}đ</span>
                    </label>
                  ))}
                </div>
              </div>

              <div className="flex justify-end gap-2 mt-4 pt-4 border-t">
                <button type="button" onClick={() => setShowModal(false)} className="px-4 py-2 bg-stone-200 rounded font-bold text-stone-600">Hủy</button>
                <button disabled={loading} type="submit" className="px-4 py-2 bg-stone-900 text-white rounded font-bold hover:bg-black">{loading ? 'Đang tạo...' : 'Lưu Mã'}</button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};

// --- 1 dòng sản phẩm trong mục Giảm giá trực tiếp ---
const DiscountRow = ({ product, onSave, money }) => {
  const [amount, setAmount] = useState(product.discount_amount || 0);
  const active = !!product.is_discount_active;
  const finalPrice = Math.max(0, Number(product.base_price) - (Number(amount) || 0));

  return (
    <div className="flex items-center gap-4 p-3">
      <img src={product.images?.[0]} alt="" className="w-12 h-14 object-cover rounded bg-stone-100" />
      <div className="flex-1 min-w-0">
        <p className="font-bold text-sm text-stone-800 truncate">{product.name}</p>
        <p className="text-xs text-stone-500">
          Giá gốc: {money(product.base_price)}đ
          {active && Number(amount) > 0 && <span className="text-red-600 font-bold"> → Còn {money(finalPrice)}đ</span>}
        </p>
      </div>

      <div className="flex items-center gap-1">
        <input type="text" className="w-28 p-2 border rounded text-right text-sm outline-none focus:border-stone-800"
          value={money(amount)}
          onChange={(e) => { const raw = e.target.value.replace(/\./g, ''); if (!isNaN(raw)) setAmount(raw); }}
          onBlur={() => { if (Number(amount) !== Number(product.discount_amount)) onSave(product, { discount_amount: Number(amount) || 0, is_discount_active: active }); }} />
        <span className="text-xs text-stone-400">đ giảm</span>
      </div>

      <label className="relative inline-flex items-center cursor-pointer">
        <input type="checkbox" className="sr-only peer" checked={active}
          onChange={() => onSave(product, { discount_amount: Number(amount) || 0, is_discount_active: !active })} />
        <div className="w-11 h-6 bg-stone-200 rounded-full peer peer-checked:after:translate-x-full after:content-[''] after:absolute after:top-0.5 after:left-0.5 after:bg-white after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-red-600"></div>
      </label>
    </div>
  );
};

export default Promotions;
