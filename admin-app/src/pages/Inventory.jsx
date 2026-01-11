import { useEffect, useState, useMemo } from 'react';
import axios from 'axios';
import { FaSearch, FaPlus, FaTrash, FaSave, FaWarehouse, FaTruck, FaHistory, FaBoxOpen, FaClipboardList } from 'react-icons/fa';

const Inventory = () => {
  const [activeTab, setActiveTab] = useState('inbound'); // 'inbound', 'history', 'stock'
  
  // --- STATE DỮ LIỆU ---
  const [suppliers, setSuppliers] = useState([]);
  const [stores, setStores] = useState([]);
  const [products, setProducts] = useState([]);
  
  // --- STATE NHẬP HÀNG ---
  const [selectedSupplier, setSelectedSupplier] = useState('');
  const [selectedStore, setSelectedStore] = useState('');
  const [importList, setImportList] = useState([]);
  const [searchTerm, setSearchTerm] = useState('');

  // --- STATE LỊCH SỬ & TỒN KHO ---
  const [batches, setBatches] = useState([]);

  // 1. Lấy dữ liệu
  useEffect(() => {
    fetchMasterData();
    fetchHistory();
  }, []);

  const fetchMasterData = async () => {
    try {
      const [supRes, storeRes, prodRes] = await Promise.all([
        axios.get('http://localhost:5000/api/suppliers'),
        axios.get('http://localhost:5000/api/stores'),
        axios.get('http://localhost:5000/api/products')
      ]);
      if (supRes.data.success) setSuppliers(supRes.data.data);
      if (storeRes.data.success) setStores(storeRes.data.data);
      if (prodRes.data.success) setProducts(prodRes.data.data);
    } catch (error) { console.error("Lỗi master data:", error); }
  };

  const fetchHistory = async () => {
    try {
      const res = await axios.get('http://localhost:5000/api/inventory');
      if (res.data.success) setBatches(res.data.data);
    } catch (error) { console.error("Lỗi lấy lịch sử:", error); }
  };

  // --- LOGIC TÍNH TỔNG TỒN KHO (MỚI) ---
  // Gom nhóm các lô hàng theo Variant ID để tính tổng
  const stockSummary = useMemo(() => {
    const summary = {};
    batches.forEach(batch => {
      const key = batch.variant_id;
      if (!summary[key]) {
        summary[key] = {
          id: batch.variant_id,
          product_name: batch.variants?.products?.name,
          image: batch.variants?.products?.images?.[0],
          variant_name: `${batch.variants?.size} / ${batch.variants?.color}`,
          sku: batch.variants?.sku,
          store_name: batch.stores?.name, // Tạm thời lấy kho của batch gần nhất
          total_quantity: 0
        };
      }
      // Chỉ cộng dồn số lượng còn lại (quantity_remaining)
      summary[key].total_quantity += (batch.quantity_remaining || 0);
    });
    return Object.values(summary);
  }, [batches]);

  // --- CÁC HÀM XỬ LÝ (GIỮ NGUYÊN) ---
  const addToImportList = (product, variant) => {
    const exists = importList.find(item => item.variant_id === variant.id);
    if (exists) { alert("Đã có trong danh sách!"); return; }
    setImportList([...importList, {
      variant_id: variant.id,
      product_name: product.name,
      variant_name: `${variant.size} - ${variant.color}`,
      sku: variant.sku,
      image: product.images?.[0],
      quantity: 1, cost_price: 0
    }]);
  };

  const updateItem = (index, field, value) => {
    const newList = [...importList];
    newList[index][field] = value;
    setImportList(newList);
  };

  const removeItem = (index) => {
    const newList = [...importList];
    newList.splice(index, 1);
    setImportList(newList);
  };

  const handleImport = async () => {
    if (!selectedSupplier || !selectedStore || importList.length === 0) {
      alert("Thiếu thông tin!"); return;
    }
    try {
      const payload = {
        supplier_id: selectedSupplier,
        store_id: selectedStore,
        items: importList.map(item => ({
          variant_id: item.variant_id,
          quantity: Number(item.quantity),
          cost_price: Number(item.cost_price)
        }))
      };
      const res = await axios.post('http://localhost:5000/api/inventory/import', payload);
      if (res.data.success) {
        alert("✅ Nhập kho thành công!");
        setImportList([]);
        fetchHistory();
        setActiveTab('stock'); // Chuyển sang tab tồn kho để xem ngay
      }
    } catch (error) { alert("❌ Lỗi: " + error.message); }
  };

  const filteredProducts = products.filter(p => 
    p.name.toLowerCase().includes(searchTerm.toLowerCase()) || 
    p.slug.toLowerCase().includes(searchTerm.toLowerCase())
  );

  return (
    <div className="p-6 md:p-8 h-[calc(100vh-64px)] flex flex-col">
      <div className="flex flex-col md:flex-row justify-between md:items-end mb-6 gap-4">
        <div>
          <h1 className="text-2xl font-bold text-stone-800">Quản lý Kho hàng</h1>
          <p className="text-stone-500">Hệ thống quản lý nhập xuất tồn FIFO</p>
        </div>
        
        {/* THANH TAB ĐIỀU HƯỚNG */}
        <div className="flex bg-stone-100 p-1 rounded-lg self-start md:self-auto">
          <button onClick={() => setActiveTab('inbound')} className={`px-4 py-2 rounded-md text-sm font-medium transition-all ${activeTab === 'inbound' ? 'bg-white shadow text-stone-800' : 'text-stone-500 hover:text-stone-700'}`}>
            <div className="flex items-center gap-2"><FaBoxOpen/> Nhập Hàng</div>
          </button>
          <button onClick={() => setActiveTab('stock')} className={`px-4 py-2 rounded-md text-sm font-medium transition-all ${activeTab === 'stock' ? 'bg-white shadow text-stone-800' : 'text-stone-500 hover:text-stone-700'}`}>
            <div className="flex items-center gap-2"><FaClipboardList/> Tổng Tồn Kho</div>
          </button>
          <button onClick={() => setActiveTab('history')} className={`px-4 py-2 rounded-md text-sm font-medium transition-all ${activeTab === 'history' ? 'bg-white shadow text-stone-800' : 'text-stone-500 hover:text-stone-700'}`}>
            <div className="flex items-center gap-2"><FaHistory/> Lịch sử Nhập</div>
          </button>
        </div>
      </div>

      {/* --- TAB 1: NHẬP HÀNG --- */}
      {activeTab === 'inbound' && (
        <div className="flex-1 min-h-0 flex flex-col">
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 flex-1 min-h-0">
            {/* Cột trái: Tìm SP */}
            <div className="bg-white p-4 rounded-xl border border-stone-200 shadow-sm flex flex-col h-full">
               <div className="relative mb-4">
                <FaSearch className="absolute left-3 top-1/2 -translate-y-1/2 text-stone-400" />
                <input type="text" placeholder="Tìm sản phẩm..." className="w-full pl-10 pr-4 py-2 bg-stone-50 border border-stone-200 rounded-lg outline-none" value={searchTerm} onChange={e => setSearchTerm(e.target.value)}/>
              </div>
              <div className="flex-1 overflow-y-auto space-y-3 pr-2 custom-scrollbar">
                {filteredProducts.map(product => (
                  <div key={product.id} className="border border-stone-100 rounded-lg p-3 hover:bg-stone-50">
                    <div className="flex gap-3 mb-2">
                      <div className="w-10 h-14 bg-stone-200 rounded overflow-hidden">
                        {product.images?.[0] && <img src={product.images[0]} className="w-full h-full object-cover"/>}
                      </div>
                      <div>
                        <p className="font-medium text-stone-800 text-sm">{product.name}</p>
                        <div className="flex flex-wrap gap-1 mt-1">
                          {product.variants?.map(v => (
                            <button key={v.id} onClick={() => addToImportList(product, v)} className="text-[10px] border border-stone-300 rounded px-1.5 py-0.5 hover:bg-stone-800 hover:text-white transition-colors">
                              {v.size}/{v.color}
                            </button>
                          ))}
                        </div>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </div>

            {/* Cột phải: Form nhập */}
            <div className="lg:col-span-2 flex flex-col gap-6 h-full">
              <div className="bg-white p-5 rounded-xl border border-stone-200 shadow-sm grid grid-cols-2 gap-6">
                <div>
                  <label className="block text-sm font-bold text-stone-700 mb-1">Nhà cung cấp</label>
                  <select className="w-full p-2 border border-stone-300 rounded-lg" value={selectedSupplier} onChange={e => setSelectedSupplier(e.target.value)}>
                    <option value="">-- Chọn NCC --</option>
                    {suppliers.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
                  </select>
                </div>
                <div>
                  <label className="block text-sm font-bold text-stone-700 mb-1">Kho nhập</label>
                  <select className="w-full p-2 border border-stone-300 rounded-lg" value={selectedStore} onChange={e => setSelectedStore(e.target.value)}>
                    <option value="">-- Chọn Kho --</option>
                    {stores.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
                  </select>
                </div>
              </div>

              <div className="bg-white rounded-xl border border-stone-200 shadow-sm flex-1 flex flex-col overflow-hidden">
                <div className="flex-1 overflow-y-auto">
                  <table className="w-full text-left border-collapse">
                    <thead className="bg-stone-100 text-stone-500 text-xs uppercase sticky top-0">
                      <tr><th className="p-3">Sản phẩm</th><th className="p-3">SL</th><th className="p-3">Giá Vốn</th><th className="p-3 text-right"></th></tr>
                    </thead>
                    <tbody className="divide-y divide-stone-100 text-sm">
                      {importList.map((item, index) => (
                        <tr key={index}>
                          <td className="p-3"><div className="font-medium">{item.product_name}</div><div className="text-xs text-stone-500">{item.variant_name}</div></td>
                          <td className="p-3"><input type="number" className="w-16 border rounded p-1 text-center" value={item.quantity} onChange={e => updateItem(index, 'quantity', e.target.value)}/></td>
                          <td className="p-3"><input type="number" className="w-24 border rounded p-1 text-right" value={item.cost_price} onChange={e => updateItem(index, 'cost_price', e.target.value)}/></td>
                          <td className="p-3 text-right"><button onClick={() => removeItem(index)}><FaTrash className="text-red-400"/></button></td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                <div className="p-4 border-t bg-stone-50 flex justify-between items-center">
                    <span className="font-bold">Tổng: {new Intl.NumberFormat('vi-VN').format(importList.reduce((sum, item) => sum + (item.quantity * item.cost_price), 0))} ₫</span>
                    <button onClick={handleImport} className="bg-stone-900 text-white px-4 py-2 rounded-lg flex gap-2 items-center"><FaSave/> Lưu Phiếu</button>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* --- TAB 2: TỔNG TỒN KHO (MỚI) --- */}
      {activeTab === 'stock' && (
        <div className="bg-white rounded-xl border border-stone-200 shadow-sm flex-1 overflow-hidden flex flex-col">
          <div className="p-4 border-b border-stone-100 bg-stone-50 flex justify-between items-center">
            <h3 className="font-bold text-stone-700">Tồn kho hiện tại (Tất cả chi nhánh)</h3>
            <span className="text-sm text-stone-500">Tổng: {stockSummary.length} mã hàng</span>
          </div>
          <div className="overflow-auto flex-1">
            <table className="w-full text-left border-collapse">
              <thead className="bg-stone-100 text-stone-500 text-xs uppercase sticky top-0">
                <tr>
                  <th className="p-4 w-16">Ảnh</th>
                  <th className="p-4">Tên sản phẩm</th>
                  <th className="p-4">Phân loại (Size/Màu)</th>
                  <th className="p-4">Mã SKU</th>
                  <th className="p-4 text-center">Tổng Tồn</th>
                  <th className="p-4">Trạng thái</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-stone-100 text-sm">
                {stockSummary.length > 0 ? stockSummary.map((item) => (
                  <tr key={item.id} className="hover:bg-stone-50">
                    <td className="p-4">
                      <div className="w-10 h-14 bg-stone-200 rounded overflow-hidden">
                        {item.image && <img src={item.image} className="w-full h-full object-cover"/>}
                      </div>
                    </td>
                    <td className="p-4 font-medium text-stone-800">{item.product_name}</td>
                    <td className="p-4 text-stone-600 font-medium">{item.variant_name}</td>
                    <td className="p-4 text-stone-500 font-mono text-xs">{item.sku}</td>
                    <td className="p-4 text-center">
                      <span className={`px-3 py-1 rounded-full font-bold ${item.total_quantity > 0 ? 'bg-blue-50 text-blue-700' : 'bg-red-50 text-red-600'}`}>
                        {item.total_quantity}
                      </span>
                    </td>
                    <td className="p-4">
                      {item.total_quantity > 10 
                        ? <span className="text-green-600 text-xs font-bold">● Sẵn hàng</span> 
                        : item.total_quantity > 0 
                          ? <span className="text-orange-500 text-xs font-bold">● Sắp hết</span> 
                          : <span className="text-red-500 text-xs font-bold">● Hết hàng</span>}
                    </td>
                  </tr>
                )) : (
                   <tr><td colSpan="6" className="p-10 text-center text-stone-400">Kho đang trống. Hãy nhập hàng!</td></tr>
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* --- TAB 3: LỊCH SỬ NHẬP --- */}
      {activeTab === 'history' && (
        <div className="bg-white rounded-xl border border-stone-200 shadow-sm flex-1 overflow-hidden flex flex-col">
          <div className="overflow-auto flex-1">
            <table className="w-full text-left border-collapse">
              <thead className="bg-stone-100 text-stone-500 text-xs uppercase sticky top-0">
                <tr>
                  <th className="p-4">Ngày nhập</th>
                  <th className="p-4">Mã Phiếu</th>
                  <th className="p-4">Sản phẩm</th>
                  <th className="p-4">Kho</th>
                  <th className="p-4">SL Nhập</th>
                  <th className="p-4 text-right">Giá vốn</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-stone-100 text-sm">
                {batches.length > 0 ? batches.map((batch) => (
                  <tr key={batch.id} className="hover:bg-stone-50">
                    <td className="p-4 text-stone-500">{new Date(batch.created_at).toLocaleDateString('vi-VN')}</td>
                    <td className="p-4 font-mono text-xs text-blue-600">{batch.batch_name}</td>
                    <td className="p-4">
                      <div className="font-medium">{batch.variants?.products?.name}</div>
                      <div className="text-xs text-stone-500">{batch.variants?.size} / {batch.variants?.color}</div>
                    </td>
                    <td className="p-4 text-stone-600">{batch.stores?.name}</td>
                    <td className="p-4 font-bold">{batch.original_quantity}</td>
                    <td className="p-4 text-right">{new Intl.NumberFormat('vi-VN').format(batch.cost_price)} ₫</td>
                  </tr>
                )) : (
                  <tr><td colSpan="6" className="p-10 text-center text-stone-400">Chưa có dữ liệu</td></tr>
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
};

export default Inventory;