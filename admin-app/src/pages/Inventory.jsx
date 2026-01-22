import { useEffect, useState, useMemo } from 'react';
import axios from 'axios';
// [MỚI] Thêm FaUndo, FaCheck để làm nút Hủy và Lưu
import { FaHistory, FaPlus, FaSave, FaTrash, FaWarehouse, FaBoxOpen, FaSearch, FaUndo, FaCheck } from 'react-icons/fa';

const Inventory = () => {
  const [activeTab, setActiveTab] = useState('inbound'); // 'inbound', 'history', 'stock'
  
  // --- DATA TỪ SERVER ---
  const [suppliers, setSuppliers] = useState([]);
  const [stores, setStores] = useState([]);
  const [products, setProducts] = useState([]); // Chứa cả variants
  const [batches, setBatches] = useState([]);   // Lịch sử nhập

  // --- STATE FORM NHẬP HÀNG ---
  const [selectedSupplier, setSelectedSupplier] = useState('');
  const [selectedStore, setSelectedStore] = useState('');
  const [importItems, setImportItems] = useState([]); 

  // State tạm để add từng dòng
  const [tempProduct, setTempProduct] = useState('');
  const [tempVariant, setTempVariant] = useState('');
  const [tempQuantity, setTempQuantity] = useState(10);
  const [tempCost, setTempCost] = useState(0);

  // --- STATE TÌM KIẾM TỒN KHO ---
  const [stockSearch, setStockSearch] = useState('');

  // --- [MỚI] STATE CHO TÍNH NĂNG TẠO NHANH ---
  const [isCreatingSupplier, setIsCreatingSupplier] = useState(false);
  const [newSupplierName, setNewSupplierName] = useState('');

  const [isCreatingStore, setIsCreatingStore] = useState(false);
  const [newStoreName, setNewStoreName] = useState('');

  // 1. Lấy dữ liệu ban đầu
  useEffect(() => {
    fetchMasterData();
    fetchHistory();
  }, []);

  const fetchMasterData = async () => {
    try {
      const [supRes, storeRes, prodRes] = await Promise.all([
        // Đã sửa đường dẫn đúng
        axios.get(`${import.meta.env.VITE_API_URL}/api/inventory/suppliers`), 
        axios.get(`${import.meta.env.VITE_API_URL}/api/inventory/stores`),
        axios.get(`${import.meta.env.VITE_API_URL}/api/products`) 
      ]);
      
      if (supRes.data.success) setSuppliers(supRes.data.data);
      if (storeRes.data.success) setStores(storeRes.data.data);
      if (prodRes.data.success) setProducts(prodRes.data.data);

      if (supRes.data.data.length > 0) setSelectedSupplier(supRes.data.data[0].id);
      if (storeRes.data.data.length > 0) setSelectedStore(storeRes.data.data[0].id);

    } catch (error) {
      console.error("Lỗi tải dữ liệu nguồn:", error);
    }
  };

  const fetchHistory = async () => {
    try {
      // --- [SỬA LẠI ĐƯỜNG DẪN API] ---
      // Thêm /history vào cuối để gọi đúng route lấy lịch sử
      const res = await axios.get(`${import.meta.env.VITE_API_URL}/api/inventory/history`);
      if (res.data.success) setBatches(res.data.data);
    } catch (error) {
      console.error("Lỗi tải lịch sử:", error);
    }
  };

  // --- [MỚI] HÀM XỬ LÝ TẠO NHANH ---
  const handleQuickCreateSupplier = async () => {
      if (!newSupplierName.trim()) return alert("Vui lòng nhập tên NCC!");
      try {
          const res = await axios.post(`${import.meta.env.VITE_API_URL}/api/inventory/suppliers`, { name: newSupplierName });
          if(res.data.success) {
              const newSup = res.data.data;
              setSuppliers([...suppliers, newSup]); // Thêm vào list hiện tại
              setSelectedSupplier(newSup.id); // Tự động chọn NCC vừa tạo
              setIsCreatingSupplier(false);
              setNewSupplierName('');
          }
      } catch (error) {
          alert("Lỗi tạo NCC: " + error.message);
      }
  };

  const handleQuickCreateStore = async () => {
      if (!newStoreName.trim()) return alert("Vui lòng nhập tên Kho!");
      try {
          const res = await axios.post(`${import.meta.env.VITE_API_URL}/api/inventory/stores`, { name: newStoreName });
          if(res.data.success) {
              const newStore = res.data.data;
              setStores([...stores, newStore]); // Thêm vào list hiện tại
              setSelectedStore(newStore.id); // Tự động chọn Kho vừa tạo
              setIsCreatingStore(false);
              setNewStoreName('');
          }
      } catch (error) {
          alert("Lỗi tạo Kho: " + error.message);
      }
  };
  // ------------------------------------

  // 2. Logic tính toán Tổng Tồn kho (Giữ nguyên)
  const inventorySummary = useMemo(() => {
    if (!products.length || !batches.length) return [];

    let summaryList = [];

    products.forEach(prod => {
      if (prod.variants) {
        prod.variants.forEach(variant => {
            // SỬA: Dùng '==' thay vì '===' để so sánh (tránh lỗi string vs number)
            // SỬA: Ép kiểu Number() cho quantity_remaining để cộng toán học
            const totalStock = batches
                .filter(b => b.variant_id == variant.id) 
                .reduce((sum, b) => sum + (Number(b.quantity_remaining) || 0), 0);

            // SỬA: Ép kiểu Number() cho cost_price
            const totalValue = batches
                .filter(b => b.variant_id == variant.id)
                .reduce((sum, b) => sum + ((Number(b.quantity_remaining) || 0) * (Number(b.cost_price) || 0)), 0);

            summaryList.push({
                id: variant.id,
                product_name: prod.name,
                image: prod.images?.[0],
                sku: variant.sku,
                size: variant.size,
                color: variant.color,
                stock: totalStock,
                value: totalValue
            });
        });
      }
    });

    // Lọc theo tìm kiếm
    if (stockSearch) {
        summaryList = summaryList.filter(item => 
            item.product_name.toLowerCase().includes(stockSearch.toLowerCase()) || 
            item.sku.toLowerCase().includes(stockSearch.toLowerCase())
        );
    }

    return summaryList;
  }, [products, batches, stockSearch]);


  // 3. Xử lý logic nhập hàng (Giữ nguyên)
  const handleAddItem = () => {
    if (!tempProduct || !tempVariant || tempQuantity <= 0 || tempCost <= 0) {
      alert("Vui lòng nhập đầy đủ thông tin hợp lệ!"); return;
    }
    const prod = products.find(p => p.id == tempProduct);
    const variant = prod.variants.find(v => v.id == tempVariant);

    const newItem = {
      variant_id: variant.id,
      product_name: prod.name,
      sku: variant.sku,
      size: variant.size,
      color: variant.color,
      quantity: parseInt(tempQuantity),
      cost_price: parseFloat(tempCost)
    };
    setImportItems([...importItems, newItem]);
    setTempQuantity(10); 
  };

  const handleRemoveItem = (index) => {
    const newItems = [...importItems];
    newItems.splice(index, 1);
    setImportItems(newItems);
  };

  const handleImportStock = async () => {
    if (importItems.length === 0) return;
    if (!confirm("Xác nhận nhập kho?")) return;

    try {
      const payload = {
        supplier_id: selectedSupplier,
        store_id: selectedStore,
        items: importItems.map(item => ({
          variant_id: item.variant_id,
          quantity: item.quantity,
          cost_price: item.cost_price
        }))
      };

      const res = await axios.post(`${import.meta.env.VITE_API_URL}/api/inventory/inbound`, payload);

      if (res.data.success) {
        alert("✅ Nhập hàng thành công!");
        setImportItems([]);
        fetchHistory(); // Tải lại lịch sử -> Tự động cập nhật tồn kho
        setActiveTab('stock'); // Chuyển ngay sang tab Tồn kho để xem kết quả
      }
    } catch (error) {
      alert("❌ Lỗi nhập hàng: " + (error.response?.data?.message || error.message));
    }
  };

  const totalImportValue = importItems.reduce((sum, item) => sum + (item.quantity * item.cost_price), 0);

  return (
    <div className="p-6 md:p-10 max-w-7xl mx-auto min-h-screen">
      <div className="flex flex-col md:flex-row justify-between items-start md:items-center mb-8 gap-4">
        <div>
          <h1 className="text-2xl font-bold text-stone-800">Quản lý Kho hàng</h1>
          <p className="text-stone-500">Theo dõi nhập xuất và tồn kho thời gian thực</p>
        </div>
      </div>

      {/* TABS NAVIGATION */}
      <div className="flex gap-6 border-b border-stone-200 mb-6 overflow-x-auto">
        <button 
          onClick={() => setActiveTab('inbound')}
          className={`pb-3 px-2 font-medium transition-colors whitespace-nowrap ${activeTab === 'inbound' ? 'text-stone-900 border-b-2 border-stone-900' : 'text-stone-400 hover:text-stone-600'}`}
        >
          <FaPlus className="inline mb-1 mr-2"/> Nhập hàng
        </button>
        <button 
          onClick={() => setActiveTab('stock')}
          className={`pb-3 px-2 font-medium transition-colors whitespace-nowrap ${activeTab === 'stock' ? 'text-stone-900 border-b-2 border-stone-900' : 'text-stone-400 hover:text-stone-600'}`}
        >
          <FaBoxOpen className="inline mb-1 mr-2"/> Tồn kho hiện tại
        </button>
        <button 
          onClick={() => setActiveTab('history')}
          className={`pb-3 px-2 font-medium transition-colors whitespace-nowrap ${activeTab === 'history' ? 'text-stone-900 border-b-2 border-stone-900' : 'text-stone-400 hover:text-stone-600'}`}
        >
          <FaHistory className="inline mb-1 mr-2"/> Lịch sử nhập
        </button>
      </div>

      {/* --- TAB 1: NHẬP HÀNG --- */}
      {activeTab === 'inbound' && (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
          <div className="lg:col-span-2 space-y-6">
            
            {/* Form chọn NCC & Kho (ĐÃ NÂNG CẤP) */}
            <div className="bg-white p-6 rounded-xl border border-stone-200 shadow-sm">
              <h3 className="font-bold text-stone-800 mb-4 flex items-center gap-2"><FaWarehouse/> Thông tin phiếu nhập</h3>
              <div className="grid grid-cols-2 gap-4">
                
                {/* --- CỘT 1: NHÀ CUNG CẤP --- */}
                <div>
                  <div className="flex justify-between items-center mb-1">
                      <label className="block text-sm font-medium text-stone-600">Nhà cung cấp</label>
                      {/* Nút Toggle */}
                      <button 
                        onClick={() => setIsCreatingSupplier(!isCreatingSupplier)} 
                        className="text-xs text-blue-600 hover:underline flex items-center gap-1"
                      >
                        {isCreatingSupplier ? <><FaUndo/> Hủy</> : <><FaPlus/> Tạo mới</>}
                      </button>
                  </div>
                  
                  {isCreatingSupplier ? (
                      // Input tạo mới
                      <div className="flex gap-2">
                          <input 
                              type="text"
                              className="w-full p-2 border rounded bg-blue-50 focus:border-blue-500 outline-none text-sm"
                              placeholder="Nhập tên NCC..."
                              value={newSupplierName}
                              onChange={e => setNewSupplierName(e.target.value)}
                              autoFocus
                          />
                          <button onClick={handleQuickCreateSupplier} className="bg-blue-600 text-white px-3 rounded hover:bg-blue-700">
                              <FaCheck/>
                          </button>
                      </div>
                  ) : (
                      // Dropdown chọn cũ
                      <select className="w-full p-2 border rounded bg-stone-50" value={selectedSupplier} onChange={e => setSelectedSupplier(e.target.value)}>
                        {suppliers.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
                      </select>
                  )}
                </div>

                {/* --- CỘT 2: KHO HÀNG --- */}
                <div>
                    <div className="flex justify-between items-center mb-1">
                        <label className="block text-sm font-medium text-stone-600">Nhập về Kho</label>
                        {/* Nút Toggle */}
                        <button 
                            onClick={() => setIsCreatingStore(!isCreatingStore)} 
                            className="text-xs text-blue-600 hover:underline flex items-center gap-1"
                        >
                            {isCreatingStore ? <><FaUndo/> Hủy</> : <><FaPlus/> Tạo mới</>}
                        </button>
                    </div>

                    {isCreatingStore ? (
                        // Input tạo mới
                        <div className="flex gap-2">
                            <input 
                                type="text"
                                className="w-full p-2 border rounded bg-blue-50 focus:border-blue-500 outline-none text-sm"
                                placeholder="Nhập tên Kho..."
                                value={newStoreName}
                                onChange={e => setNewStoreName(e.target.value)}
                                autoFocus
                            />
                            <button onClick={handleQuickCreateStore} className="bg-blue-600 text-white px-3 rounded hover:bg-blue-700">
                                <FaCheck/>
                            </button>
                        </div>
                    ) : (
                        // Dropdown chọn cũ
                        <select className="w-full p-2 border rounded bg-stone-50" value={selectedStore} onChange={e => setSelectedStore(e.target.value)}>
                            {stores.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
                        </select>
                    )}
                </div>

              </div>
            </div>

            {/* Form chọn Sản phẩm (GIỮ NGUYÊN) */}
            <div className="bg-white p-6 rounded-xl border border-stone-200 shadow-sm">
              <h3 className="font-bold text-stone-800 mb-4 flex items-center gap-2"><FaPlus/> Thêm sản phẩm</h3>
              <div className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-stone-600 mb-1">Sản phẩm</label>
                  <select className="w-full p-2 border rounded" value={tempProduct} onChange={e => { setTempProduct(e.target.value); setTempVariant(''); }}>
                    <option value="">-- Chọn sản phẩm --</option>
                    {products.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
                  </select>
                </div>
                {tempProduct && (
                  <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                    <div className="md:col-span-3">
                        <label className="block text-sm font-medium text-stone-600 mb-1">Phiên bản</label>
                        <select className="w-full p-2 border rounded" value={tempVariant} onChange={e => setTempVariant(e.target.value)}>
                          <option value="">-- Chọn Size/Màu --</option>
                          {products.find(p => p.id == tempProduct)?.variants.map(v => (
                            <option key={v.id} value={v.id}>{v.sku} - {v.color} / {v.size}</option>
                          ))}
                        </select>
                    </div>
                  </div>
                )}
                <div className="grid grid-cols-2 gap-4">
                    <div>
                        <label className="block text-sm font-medium text-stone-600 mb-1">Số lượng</label>
                        <input type="number" className="w-full p-2 border rounded" value={tempQuantity} onChange={e => setTempQuantity(e.target.value)} />
                    </div>
                    <div>
                        <label className="block text-sm font-medium text-stone-600 mb-1">Giá vốn (đ)</label>
                        <input type="number" className="w-full p-2 border rounded" value={tempCost} onChange={e => setTempCost(e.target.value)} />
                    </div>
                </div>
                <button onClick={handleAddItem} className="w-full bg-stone-800 text-white py-2 rounded hover:bg-stone-700 font-medium">Thêm vào phiếu</button>
              </div>
            </div>
          </div>

          {/* Review List (GIỮ NGUYÊN) */}
          <div className="bg-white p-6 rounded-xl border border-stone-200 shadow-sm h-fit">
            <h3 className="font-bold text-stone-800 mb-4">Phiếu nhập ({importItems.length})</h3>
            <div className="space-y-3 mb-6 max-h-[400px] overflow-y-auto">
              {importItems.length === 0 && <p className="text-stone-400 text-sm italic">Chưa có sản phẩm nào.</p>}
              {importItems.map((item, idx) => (
                <div key={idx} className="flex justify-between items-start border-b border-stone-100 pb-2">
                  <div>
                    <div className="font-medium text-sm">{item.product_name}</div>
                    <div className="text-xs text-stone-500">{item.color} / {item.size}</div>
                    <div className="text-xs font-mono mt-1">SL: <b>{item.quantity}</b> x {new Intl.NumberFormat('vi-VN').format(item.cost_price)}đ</div>
                  </div>
                  <button onClick={() => handleRemoveItem(idx)} className="text-red-400 hover:text-red-600"><FaTrash/></button>
                </div>
              ))}
            </div>
            <div className="border-t border-stone-200 pt-4 mb-4 flex justify-between font-bold text-lg">
                  <span>Tổng tiền:</span>
                  <span>{new Intl.NumberFormat('vi-VN').format(totalImportValue)} đ</span>
            </div>
            <button onClick={handleImportStock} disabled={importItems.length === 0} className={`w-full py-3 rounded-lg font-bold text-white uppercase tracking-wider ${importItems.length === 0 ? 'bg-stone-300 cursor-not-allowed' : 'bg-green-600 hover:bg-green-700'}`}>
               <FaSave className="inline mb-1 mr-2"/> Hoàn tất
            </button>
          </div>
        </div>
      )}

      {/* --- TAB 2: TỒN KHO HIỆN TẠI (GIỮ NGUYÊN) --- */}
      {activeTab === 'stock' && (
        <div className="space-y-4">
            {/* Thanh tìm kiếm */}
            <div className="flex gap-4">
                <div className="relative flex-1 max-w-md">
                    <FaSearch className="absolute left-3 top-3 text-stone-400" />
                    <input 
                        type="text" 
                        placeholder="Tìm theo tên sản phẩm hoặc mã SKU..." 
                        className="w-full pl-10 pr-4 py-2 border rounded-lg focus:outline-none focus:border-stone-800"
                        value={stockSearch}
                        onChange={e => setStockSearch(e.target.value)}
                    />
                </div>
            </div>

            <div className="bg-white rounded-xl border border-stone-200 shadow-sm overflow-hidden">
                <table className="w-full text-left border-collapse">
                    <thead className="bg-stone-100 text-stone-600 uppercase text-xs">
                        <tr>
                            <th className="p-4">Sản phẩm</th>
                            <th className="p-4">SKU</th>
                            <th className="p-4">Phân loại</th>
                            <th className="p-4 text-center">Tồn kho</th>
                            <th className="p-4 text-right">Giá trị tồn (Ước tính)</th>
                            <th className="p-4 text-center">Trạng thái</th>
                        </tr>
                    </thead>
                    <tbody className="divide-y divide-stone-100 text-sm">
                        {inventorySummary.length > 0 ? inventorySummary.map((item) => (
                            <tr key={item.id} className="hover:bg-stone-50">
                                <td className="p-4 flex items-center gap-3">
                                    <div className="w-10 h-10 bg-stone-200 rounded overflow-hidden">
                                        {item.image && <img src={item.image} className="w-full h-full object-cover"/>}
                                    </div>
                                    <span className="font-medium text-stone-800">{item.product_name}</span>
                                </td>
                                <td className="p-4 font-mono text-stone-500 text-xs">{item.sku}</td>
                                <td className="p-4 text-stone-600">{item.color} / {item.size}</td>
                                <td className="p-4 text-center font-bold text-lg">{item.stock}</td>
                                <td className="p-4 text-right text-stone-600">{new Intl.NumberFormat('vi-VN').format(item.value)} ₫</td>
                                <td className="p-4 text-center">
                                    {item.stock > 0 ? (
                                        <span className="bg-green-100 text-green-700 px-2 py-1 rounded text-xs font-bold">Sẵn hàng</span>
                                    ) : (
                                        <span className="bg-red-100 text-red-700 px-2 py-1 rounded text-xs font-bold">Hết hàng</span>
                                    )}
                                </td>
                            </tr>
                        )) : (
                            <tr><td colSpan="6" className="p-8 text-center text-stone-400">Không tìm thấy dữ liệu tồn kho</td></tr>
                        )}
                    </tbody>
                </table>
            </div>
        </div>
      )}

      {/* --- TAB 3: LỊCH SỬ NHẬP (GIỮ NGUYÊN) --- */}
      {activeTab === 'history' && (
        <div className="bg-white rounded-xl border border-stone-200 shadow-sm overflow-hidden">
          <table className="w-full text-left border-collapse">
              <thead className="bg-stone-100 text-stone-600 uppercase text-xs">
                <tr>
                  <th className="p-4">Ngày nhập</th>
                  <th className="p-4">Mã Lô</th>
                  <th className="p-4">Sản phẩm</th>
                  <th className="p-4">Kho</th>
                  <th className="p-4">SL Ban đầu</th>
                  <th className="p-4">SL Hiện tại (FIFO)</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-stone-100 text-sm">
                {batches.map((batch) => (
                  <tr key={batch.id} className="hover:bg-stone-50">
                    <td className="p-4 text-stone-500">{new Date(batch.created_at).toLocaleDateString('vi-VN')}</td>
                    {/* --- [SỬA] THAY BATCH_NAME BẰNG ID --- */}
                    <td className="p-4 font-mono text-xs text-blue-600">Batch #{batch.id}</td>
                    <td className="p-4">
                      <div className="font-medium">{batch.variants?.products?.name}</div>
                      <div className="text-xs text-stone-500">{batch.variants?.size} / {batch.variants?.color}</div>
                    </td>
                    <td className="p-4 text-stone-600">{batch.stores?.name}</td>
                    <td className="p-4 font-bold">{batch.original_quantity}</td>
                    <td className="p-4 font-bold text-green-600">{batch.quantity_remaining}</td>
                  </tr>
                ))}
              </tbody>
          </table>
        </div>
      )}
    </div>
  );
};

export default Inventory;