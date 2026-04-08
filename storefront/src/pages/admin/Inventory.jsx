import { useEffect, useState, useMemo } from 'react'; // <--- Quan trọng nhất là dòng này
import axios from 'axios';
import { FaSearch, FaPlus, FaSpinner, FaBoxOpen, FaHistory, FaWarehouse, FaSave, FaTrash, FaCheck, FaUndo } from 'react-icons/fa';
import { toast } from 'react-toastify';
// Import các hook của bạn (nếu file nằm ở thư mục hooks ngang cấp pages thì sửa đường dẫn)
import { useAsync, useKeyedAsync } from '../../hooks/useAsync';

const Inventory = () => {
  const [activeTab, setActiveTab] = useState('inbound'); 
  
  // --- DATA ---
  const [suppliers, setSuppliers] = useState([]);
  const [stores, setStores] = useState([]);
  const [products, setProducts] = useState([]); 
  
  // [MỚI] State cho Tồn kho hiện tại & Tổng giá trị
  const [inventory, setInventory] = useState([]); 
  const [totalStockValue, setTotalStockValue] = useState(0); // <--- Biến chứa tổng tiền
  
  // State cho Lịch sử nhập xuất
  const [batches, setBatches] = useState([]);   

  // --- FORM NHẬP HÀNG ---
  const [selectedSupplier, setSelectedSupplier] = useState('');
  const [selectedStore, setSelectedStore] = useState('');
  const [importItems, setImportItems] = useState([]); 

  const [tempProduct, setTempProduct] = useState('');
  const [tempVariant, setTempVariant] = useState('');
  const [tempQuantity, setTempQuantity] = useState(10);
  const [tempCost, setTempCost] = useState(0);

  // --- SEARCH & CREATE ---
  const [stockSearch, setStockSearch] = useState('');
  const [isCreatingSupplier, setIsCreatingSupplier] = useState(false);
  const [newSupplierName, setNewSupplierName] = useState('');
  const [isCreatingStore, setIsCreatingStore] = useState(false);
  const [newStoreName, setNewStoreName] = useState('');

  // State tạm khi gõ input
  const [editingStock, setEditingStock] = useState({});

  // --- HELPER ---
  const formatCurrencyInput = (value) => {
      if (!value) return '';
      const number = Number(value.toString().replace(/\D/g, ''));
      return new Intl.NumberFormat('vi-VN').format(number);
  };

  useEffect(() => {
    fetchMasterData();
    fetchHistory();
    fetchInventory(); // [MỚI] Gọi hàm lấy tồn kho ngay khi load trang
  }, []);

  // --- [MỚI] HÀM LẤY TỒN KHO & TỔNG GIÁ TRỊ ---
  const fetchInventory = async () => {
    try {
      // Giả sử route bên backend là /api/inventory/stock (trỏ tới hàm getStock)
      // Bạn cần kiểm tra lại file inventoryRoutes.js để xem đường dẫn chính xác là gì
      const res = await axios.get(`${import.meta.env.VITE_API_URL}/api/inventory/stock`);
      
      if (res.data.success) {
        setInventory(res.data.data); // List danh sách tồn kho
        
        // [QUAN TRỌNG] Cập nhật tổng giá trị từ Backend gửi về
        setTotalStockValue(res.data.totalValue || 0); 
      }
    } catch (error) {
      console.error("Lỗi tải tồn kho:", error);
    }
  };

  const fetchMasterData = async () => {
    try {
      const [supRes, storeRes, prodRes] = await Promise.all([
        axios.get(`${import.meta.env.VITE_API_URL}/api/inventory/suppliers`), 
        axios.get(`${import.meta.env.VITE_API_URL}/api/inventory/stores`),
        axios.get(`${import.meta.env.VITE_API_URL}/api/products`) 
      ]);
      
      if (supRes.data.success) setSuppliers(supRes.data.data);
      if (storeRes.data.success) setStores(storeRes.data.data);
      
      if (prodRes.data.success) {
          let allProducts = prodRes.data.data;

          // [MỚI] Kéo thêm sản phẩm "Phụ kiện BrownVN" đang bị ẩn
          try {
              const accRes = await axios.get(`${import.meta.env.VITE_API_URL}/api/orders/accessory`);
              if (accRes.data.success && accRes.data.data) {
                  // Tránh thêm trùng lặp nếu danh sách đã có
                  if (!allProducts.find(p => p.id === accRes.data.data.id)) {
                      allProducts.push(accRes.data.data);
                  }
              }
          } catch (e) {
              console.log("Không tải được phụ kiện ẩn");
          }

          // Cập nhật toàn bộ danh sách sản phẩm (bao gồm cả phụ kiện) vào State
          setProducts(allProducts);
      }

      if (supRes.data.data && supRes.data.data.length > 0) setSelectedSupplier(supRes.data.data[0].id);
      if (storeRes.data.data && storeRes.data.data.length > 0) setSelectedStore(storeRes.data.data[0].id);

    } catch (error) { console.error("Lỗi data:", error); }
  };

  const fetchHistory = async () => {
    try {
      const res = await axios.get(`${import.meta.env.VITE_API_URL}/api/inventory/history`);
      if (res.data.success) setBatches(res.data.data);
    } catch (error) { console.error("Lỗi history:", error); }
  };

  const handleQuickCreateSupplier = async () => {
      if (!newSupplierName.trim()) return alert("Vui lòng nhập tên NCC!");
      try {
          const res = await axios.post(`${import.meta.env.VITE_API_URL}/api/inventory/suppliers`, { name: newSupplierName });
          if(res.data.success) {
              const newSup = res.data.data;
              setSuppliers([...suppliers, newSup]); 
              setSelectedSupplier(newSup.id); 
              setIsCreatingSupplier(false);
              setNewSupplierName('');
          }
      } catch (error) { alert("Lỗi tạo NCC: " + error.message); }
  };

  const handleQuickCreateStore = async () => {
      if (!newStoreName.trim()) return alert("Vui lòng nhập tên Kho!");
      try {
          const res = await axios.post(`${import.meta.env.VITE_API_URL}/api/inventory/stores`, { name: newStoreName });
          if(res.data.success) {
              const newStore = res.data.data;
              setStores([...stores, newStore]); 
              setSelectedStore(newStore.id); 
              setIsCreatingStore(false);
              setNewStoreName('');
          }
      } catch (error) { alert("Lỗi tạo Kho: " + error.message); }
  };

  // --- TÍNH TỒN KHO HIỆN TẠI (Tab 2) ---
  const inventorySummary = useMemo(() => {
    if (!products.length || !batches.length) return [];
    let summaryList = [];
    products.forEach(prod => {
      if (prod.variants) {
        prod.variants.forEach(variant => {
            const totalStock = batches
                .filter(b => b.variant_id == variant.id) 
                .reduce((sum, b) => sum + (Number(b.quantity_remaining) || 0), 0);
            const totalValue = batches
                .filter(b => b.variant_id == variant.id)
                .reduce((sum, b) => sum + ((Number(b.quantity_remaining) || 0) * (Number(b.cost_price) || 0)), 0);
            
            // [ĐÃ SỬA] Ưu tiên lấy ảnh biến thể, nếu không có mới lấy ảnh sản phẩm
            summaryList.push({
                id: variant.id,
                product_name: prod.name,
                image: variant.image_url || prod.images?.[0], 
                sku: variant.sku,
                size: variant.size,
                color: variant.color,
                stock: totalStock,
                value: totalValue
            });
        });
      }
    });
    if (stockSearch) {
        summaryList = summaryList.filter(item => 
            item.product_name.toLowerCase().includes(stockSearch.toLowerCase()) || 
            item.sku.toLowerCase().includes(stockSearch.toLowerCase())
        );
    }
    return summaryList;
  }, [products, batches, stockSearch]);

  // --- [MỚI] TÍNH TỒN KHO LŨY KẾ (Tab 3 - Giải quyết vấn đề lệch tồn kho) ---
  const processedBatches = useMemo(() => {
      if (!batches.length) return [];

      const groups = {};
      // 1. Sắp xếp tăng dần theo thời gian (Cũ -> Mới) để tính cộng dồn
      const sortedBatches = [...batches].sort((a, b) => new Date(a.created_at) - new Date(b.created_at));

      sortedBatches.forEach(batch => {
          const vId = batch.variant_id;
          if (!groups[vId]) groups[vId] = [];
          
          // Lấy tổng tồn của dòng trước đó
          const prevTotal = groups[vId].length > 0 
              ? groups[vId][groups[vId].length - 1].runningTotal 
              : 0;
          
          // Cộng dồn với số lượng của lô hiện tại
          // (quantity_remaining là số thực tế còn lại trong kho của lô đó)
          const currentQty = Number(batch.quantity_remaining) || 0;
          
          groups[vId].push({
              ...batch,
              runningTotal: prevTotal + currentQty // Đây là tổng tồn kho tại thời điểm đó
          });
      });

      // 2. Gộp lại và sắp xếp giảm dần (Mới nhất lên đầu) để hiển thị ra bảng
      const flatList = Object.values(groups).flat();
      return flatList.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
  }, [batches]);


  // --- LOGIC NHẬP HÀNG ---
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

  // [MỚI] Tách logic nhập kho để dùng Hook
  const importStockCore = async () => {
      if (importItems.length === 0) return;
      
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
        fetchHistory(); 
        setActiveTab('stock'); 
      }
  };

  // Dùng Hook useAsync cho nhập kho
  const { execute: handleImportStockSafe, loading: isImporting } = useAsync(importStockCore);


  // [MỚI] Tách logic điều chỉnh để dùng Hook KeyedAsync
  const adjustStockCore = async (variantId, diff) => {
       const res = await axios.post(`${import.meta.env.VITE_API_URL}/api/inventory/adjust`, {
           variant_id: variantId,
           quantity_change: diff, 
           store_id: selectedStore || stores[0]?.id, 
           reason: "Điều chỉnh nhanh tại Admin"
       });

       if (res.data.success) {
           toast.success(`Đã cập nhật: ${diff > 0 ? '+' : ''}${diff}`);
           fetchHistory(); // Tải lại lịch sử
       }
  };

  // Dùng Hook useKeyedAsync cho điều chỉnh tồn kho
  const { execute: adjustStockSafe, isKeyLoading } = useKeyedAsync(adjustStockCore);

  const handleStockInputChange = (id, value) => {
      setEditingStock(prev => ({ ...prev, [id]: value }));
  };

  // Logic Commit (Chặn số âm, gọi Hook)
  const commitStockChange = async (variantId, currentStock) => {
      const newValueStr = editingStock[variantId];
      if (newValueStr === undefined || newValueStr === '') return;

      const newTotalStock = parseInt(newValueStr);
      if (isNaN(newTotalStock)) return;

      // Chặn nhập số âm cho Tổng tồn kho
      if (newTotalStock < 0) {
          toast.error("Tồn kho không thể nhỏ hơn 0!");
          const newEditing = { ...editingStock };
          delete newEditing[variantId];
          setEditingStock(newEditing);
          return;
      }

      const diff = newTotalStock - currentStock;
      if (diff === 0) {
          const newEditing = { ...editingStock };
          delete newEditing[variantId];
          setEditingStock(newEditing);
          return;
      }

      // Xác nhận giảm kho
      if (diff < 0 && Math.abs(diff) > 10 && !confirm(`Bạn đang GIẢM tồn kho đi ${Math.abs(diff)} cái. Chắc chắn chứ?`)) {
           const newEditing = { ...editingStock };
           delete newEditing[variantId];
           setEditingStock(newEditing);
           return;
      }

      try {
           // GỌI QUA HOOK: Chặn double click & hiện loading
           await adjustStockSafe(variantId, diff);
           
           // Thành công -> Xóa giá trị đang gõ để hiện giá trị thật
           const newEditing = { ...editingStock };
           delete newEditing[variantId];
           setEditingStock(newEditing);
      } catch (error) {
           toast.error(error.response?.data?.message || error.message);
           const newEditing = { ...editingStock };
           delete newEditing[variantId];
           setEditingStock(newEditing);
      }
  };

  const totalImportValue = importItems.reduce((sum, item) => sum + (item.quantity * item.cost_price), 0);

  return (
    <div className="p-4 md:p-10 max-w-7xl mx-auto min-h-screen">
      <div className="flex flex-col md:flex-row justify-between items-start md:items-center mb-6 md:mb-8 gap-4">
        <div>
          <h1 className="text-xl md:text-2xl font-bold text-stone-800">Quản lý Kho hàng</h1>
          <p className="text-sm text-stone-500">Theo dõi nhập xuất và tồn kho thời gian thực</p>
        </div>
      </div>

      {/* TABS - RESPONSIVE: Thêm scrollbar-hide và overflow-x-auto */}
      <div className="flex gap-4 md:gap-6 border-b border-stone-200 mb-6 overflow-x-auto pb-1 scrollbar-hide">
        <button onClick={() => setActiveTab('inbound')} className={`pb-3 px-2 font-medium whitespace-nowrap text-sm md:text-base ${activeTab === 'inbound' ? 'text-stone-900 border-b-2 border-stone-900' : 'text-stone-400 hover:text-stone-600'}`}><FaPlus className="inline mb-1 mr-2"/> Nhập hàng</button>
        <button onClick={() => setActiveTab('stock')} className={`pb-3 px-2 font-medium whitespace-nowrap text-sm md:text-base ${activeTab === 'stock' ? 'text-stone-900 border-b-2 border-stone-900' : 'text-stone-400 hover:text-stone-600'}`}><FaBoxOpen className="inline mb-1 mr-2"/> Tồn kho hiện tại</button>
        <button onClick={() => setActiveTab('history')} className={`pb-3 px-2 font-medium whitespace-nowrap text-sm md:text-base ${activeTab === 'history' ? 'text-stone-900 border-b-2 border-stone-900' : 'text-stone-400 hover:text-stone-600'}`}><FaHistory className="inline mb-1 mr-2"/> Lịch sử nhập</button>
      </div>

      {/* --- TAB 1: NHẬP HÀNG --- */}
      {activeTab === 'inbound' && (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 md:gap-8">
          <div className="lg:col-span-2 space-y-6">
            
            {/* Form chọn NCC & Kho */}
            <div className="bg-white p-4 md:p-6 rounded-xl border border-stone-200 shadow-sm">
                <h3 className="font-bold text-stone-800 mb-4 flex items-center gap-2"><FaWarehouse/> Thông tin phiếu nhập</h3>
                
                {/* [RESPONSIVE] GRID 1 CỘT MOBILE, 2 CỘT PC */}
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div>
                        <label className="block text-sm font-medium text-stone-600 mb-1">Nhà cung cấp</label>
                        <div className="flex gap-2">
                            {isCreatingSupplier ? (
                                <>
                                    <input type="text" className="w-full p-2 border rounded bg-blue-50 text-sm" placeholder="Nhập tên NCC..." value={newSupplierName} onChange={e => setNewSupplierName(e.target.value)} autoFocus />
                                    <button onClick={handleQuickCreateSupplier} className="bg-blue-600 text-white px-3 rounded"><FaCheck/></button>
                                </>
                            ) : (
                                <select className="w-full p-2 border rounded bg-stone-50 text-sm" value={selectedSupplier} onChange={e => setSelectedSupplier(e.target.value)}>
                                    {suppliers.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
                                </select>
                            )}
                            <button onClick={() => setIsCreatingSupplier(!isCreatingSupplier)} className="text-blue-600 text-xs hover:underline whitespace-nowrap px-1">
                                {isCreatingSupplier ? <FaUndo/> : <FaPlus/>}
                            </button>
                        </div>
                    </div>
                    <div>
                        <label className="block text-sm font-medium text-stone-600 mb-1">Kho</label>
                        <div className="flex gap-2">
                            {isCreatingStore ? (
                                <>
                                    <input type="text" className="w-full p-2 border rounded bg-blue-50 text-sm" placeholder="Nhập tên Kho..." value={newStoreName} onChange={e => setNewStoreName(e.target.value)} autoFocus />
                                    <button onClick={handleQuickCreateStore} className="bg-blue-600 text-white px-3 rounded"><FaCheck/></button>
                                </>
                            ) : (
                                <select className="w-full p-2 border rounded bg-stone-50 text-sm" value={selectedStore} onChange={e => setSelectedStore(e.target.value)}>
                                    {stores.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
                                </select>
                            )}
                            <button onClick={() => setIsCreatingStore(!isCreatingStore)} className="text-blue-600 text-xs hover:underline whitespace-nowrap px-1">
                                {isCreatingStore ? <FaUndo/> : <FaPlus/>}</button>
                        </div>
                    </div>
                </div>
            </div>

            {/* Form chọn Sản phẩm */}
            <div className="bg-white p-4 md:p-6 rounded-xl border border-stone-200 shadow-sm">
              <h3 className="font-bold text-stone-800 mb-4 flex items-center gap-2"><FaPlus/> Thêm sản phẩm</h3>
              <div className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-stone-600 mb-1">Sản phẩm</label>
                  <select className="w-full p-2 border rounded text-sm" value={tempProduct} onChange={e => { setTempProduct(e.target.value); setTempVariant(''); }}>
                    <option value="">-- Chọn sản phẩm --</option>
                    {products.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
                  </select>
                </div>
                {tempProduct && (
                  <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                    <div className="md:col-span-3">
                        <label className="block text-sm font-medium text-stone-600 mb-1">Phiên bản</label>
                        <select className="w-full p-2 border rounded text-sm" value={tempVariant} onChange={e => setTempVariant(e.target.value)}>
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
                        <input 
                            type="text" 
                            className="w-full p-2 border rounded font-bold text-stone-800" 
                            placeholder="0"
                            value={formatCurrencyInput(tempCost)} 
                            onChange={(e) => {
                                const raw = e.target.value.replace(/\./g, '');
                                if (!isNaN(raw)) setTempCost(raw);
                            }}
                        />
                    </div>
                </div>
                <button onClick={handleAddItem} className="w-full bg-stone-800 text-white py-3 rounded hover:bg-stone-700 font-medium">Thêm vào phiếu</button>
              </div>
            </div>
          </div>

          <div className="bg-white p-4 md:p-6 rounded-xl border border-stone-200 shadow-sm h-fit">
            <h3 className="font-bold text-stone-800 mb-4">Phiếu nhập ({importItems.length})</h3>
            
            {/* [RESPONSIVE] GIỚI HẠN CHIỀU CAO */}
            <div className="space-y-3 mb-6 max-h-[300px] md:max-h-[400px] overflow-y-auto">
              {importItems.map((item, idx) => (
                <div key={idx} className="flex justify-between items-start border-b border-stone-100 pb-2">
                  <div>
                    <div className="font-medium text-sm">{item.product_name}</div>
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
            
            {/* [SỬA] Nút nhập hàng dùng Hook - Chống double click */}
            <button 
                onClick={() => {
                    if (confirm("Xác nhận nhập kho?")) handleImportStockSafe();
                }} 
                disabled={importItems.length === 0 || isImporting} 
                className={`w-full py-3 rounded-lg font-bold text-white uppercase tracking-wider flex justify-center items-center gap-2 ${importItems.length === 0 ? 'bg-stone-300 cursor-not-allowed' : 'bg-green-600 hover:bg-green-700'}`}
            >
               {isImporting ? <FaSpinner className="animate-spin" /> : <FaSave/>} 
               {isImporting ? 'Đang xử lý...' : 'Hoàn tất'}
            </button>
          </div>
        </div>
      )}

      {/* --- TAB 2: TỒN KHO HIỆN TẠI --- */}
      {activeTab === 'stock' && (
        <div className="space-y-6">
            
            {/* [MỚI] CARD HIỂN THỊ TỔNG GIÁ TRỊ TỒN KHO - Responsive Grid */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div className="bg-white p-5 rounded-xl border border-stone-200 shadow-sm flex items-center justify-between">
                    <div>
                        <p className="text-stone-500 text-xs font-bold uppercase tracking-wider">Tổng giá trị kho</p>
                        <h3 className="text-2xl font-bold text-stone-800 mt-1">
                            {new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(totalStockValue)}
                        </h3>
                    </div>
                    <div className="w-10 h-10 bg-green-100 rounded-full flex items-center justify-center text-green-600">
                        <span className="text-lg font-bold">$</span>
                    </div>
                </div>
                {/* Bạn có thể thêm các card khác như: Tổng số sản phẩm, Sản phẩm sắp hết... */}
            </div>

            <div className="flex gap-4">
                <div className="relative flex-1 max-w-md">
                    <FaSearch className="absolute left-3 top-3 text-stone-400" />
                    <input 
                        type="text" 
                        placeholder="Tìm theo tên sản phẩm hoặc mã SKU..." 
                        className="w-full pl-10 pr-4 py-2 border rounded-lg focus:outline-none focus:border-stone-800 text-sm" 
                        value={stockSearch} 
                        onChange={e => setStockSearch(e.target.value)} 
                    />
                </div>
            </div>

            <div className="bg-white rounded-xl border border-stone-200 shadow-sm overflow-hidden">
                
                {/* [RESPONSIVE] WRAPPER BẢNG: OVERFLOW-X-AUTO */}
                <div className="overflow-x-auto">
                    <table className="w-full text-left border-collapse min-w-[900px]">
                        <thead className="bg-stone-100 text-stone-600 uppercase text-xs">
                            <tr>
                                <th className="p-4">Sản phẩm</th>
                                <th className="p-4">SKU</th>
                                <th className="p-4">Phân loại</th>
                                <th className="p-4 text-center">Tồn kho</th>
                                <th className="p-4 text-right">Giá trị lô (Vốn)</th>
                                <th className="p-4 text-center">Trạng thái</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-stone-100 text-sm">
                            {inventorySummary.length > 0 ? inventorySummary.map((item) => (
                                <tr key={item.id} className="hover:bg-stone-50 transition-colors">
                                    <td className="p-4 flex items-center gap-3">
                                        <div className="w-10 h-10 bg-stone-200 rounded overflow-hidden flex-shrink-0 border border-stone-100">
                                            {item.image ? (
                                                <img src={item.image} className="w-full h-full object-cover"/>
                                            ) : (
                                                <div className="w-full h-full flex items-center justify-center text-xs text-stone-400">No Img</div>
                                            )}
                                        </div>
                                        <span className="font-medium text-stone-800 line-clamp-2 max-w-[200px]">{item.product_name}</span>
                                    </td>
                                    <td className="p-4 font-mono text-stone-500 text-xs">{item.sku}</td>
                                    <td className="p-4 text-stone-600 whitespace-nowrap">{item.color} / {item.size}</td>
                                    
                                    {/* CỘT ĐIỀU CHỈNH TRỰC TIẾP */}
                                    <td className="p-4 text-center">
                                        <div className="relative inline-block group">
                                            {isKeyLoading(item.id) ? (
                                                <div className="relative">
                                                    <input 
                                                        type="number" disabled
                                                        className="w-20 h-9 text-center border bg-stone-100 rounded text-stone-400"
                                                        value={item.stock}
                                                    />
                                                    <div className="absolute inset-0 flex items-center justify-center">
                                                        <FaSpinner className="animate-spin text-stone-600" size={14}/>
                                                    </div>
                                                </div>
                                            ) : (
                                                <input 
                                                    type="number" 
                                                    className="w-16 md:w-20 h-9 text-center border border-stone-200 rounded font-bold text-stone-800 focus:border-stone-800 focus:ring-1 focus:ring-stone-800 outline-none transition-all"
                                                    value={editingStock[item.id] !== undefined ? editingStock[item.id] : item.stock}
                                                    onChange={(e) => handleStockInputChange(item.id, e.target.value)}
                                                    onBlur={() => commitStockChange(item.id, item.stock)}
                                                    onKeyDown={(e) => e.key === 'Enter' && e.target.blur()}
                                                />
                                            )}
                                        </div>
                                    </td>
                                    
                                    <td className="p-4 text-right text-stone-600 font-mono">
                                        {new Intl.NumberFormat('vi-VN').format(item.value)} ₫
                                    </td>
                                    <td className="p-4 text-center">
                                        {item.stock > 5 ? (
                                            <span className="bg-green-100 text-green-700 px-2 py-1 rounded text-[10px] font-bold uppercase tracking-wider">Sẵn hàng</span>
                                        ) : item.stock > 0 ? (
                                            <span className="bg-yellow-100 text-yellow-700 px-2 py-1 rounded text-[10px] font-bold uppercase tracking-wider">Sắp hết</span>
                                        ) : (
                                            <span className="bg-red-100 text-red-700 px-2 py-1 rounded text-[10px] font-bold uppercase tracking-wider">Hết hàng</span>
                                        )}
                                    </td>
                                </tr>
                            )) : (
                                <tr><td colSpan="6" className="p-12 text-center text-stone-400">Không tìm thấy dữ liệu tồn kho</td></tr>
                            )}
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
      )}

      {/* --- TAB 3: LỊCH SỬ NHẬP (ĐÃ SỬA: Hiển thị Tổng tồn sau GD) --- */}
      {activeTab === 'history' && (
        <div className="bg-white rounded-xl border border-stone-200 shadow-sm overflow-hidden">
          
          {/* [RESPONSIVE] WRAPPER BẢNG: OVERFLOW-X-AUTO */}
          <div className="overflow-x-auto">
              <table className="w-full text-left border-collapse min-w-[900px]">
                  <thead className="bg-stone-100 text-stone-600 uppercase text-xs">
                    <tr>
                      <th className="p-4">Ngày nhập</th>
                      <th className="p-4">Mã Lô</th>
                      <th className="p-4">Sản phẩm</th>
                      <th className="p-4">Kho / Ghi chú</th>
                      <th className="p-4">Thay đổi</th>
                      {/* [SỬA TÊN CỘT] */}
                      <th className="p-4">Tổng tồn sau GD</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-stone-100 text-sm">
                    {/* [SỬA DỮ LIỆU] Dùng processedBatches để hiển thị tồn lũy kế */}
                    {processedBatches.map((batch) => (
                      <tr key={batch.id} className={`hover:bg-stone-50 ${batch.is_adjustment ? 'bg-yellow-50' : ''}`}>
                        <td className="p-4 text-stone-500 whitespace-nowrap">{new Date(batch.created_at).toLocaleDateString('vi-VN')}</td>
                        <td className="p-4 font-mono text-xs text-blue-600">
                            {batch.id}
                            {batch.is_adjustment && <span className="ml-2 bg-yellow-200 text-yellow-800 text-[10px] px-1 rounded font-bold">ĐIỀU CHỈNH</span>}
                        </td>
                        
                        <td className="p-4 flex items-center gap-3">
                            <div className="w-10 h-10 bg-stone-100 rounded overflow-hidden border border-stone-200 flex-shrink-0">
                                <img 
                                    src={batch.variants?.image_url || batch.variants?.products?.images?.[0]} 
                                    className="w-full h-full object-cover"
                                    onError={(e) => e.target.style.display = 'none'}
                                />
                            </div>
                            <div>
                                <div className="font-medium line-clamp-1 max-w-[200px]">{batch.variants?.products?.name}</div>
                                <div className="text-xs text-stone-500">{batch.variants?.size} / {batch.variants?.color}</div>
                            </div>
                        </td>

                        <td className="p-4 text-stone-600">
                            {batch.stores?.name}
                            {batch.notes && <div className="text-[10px] italic text-stone-400 max-w-[150px] truncate">{batch.notes}</div>}
                        </td>
                        
                        {/* Hiển thị số lượng thay đổi (+/-) */}
                        <td className="p-4 font-bold">
                            <span className={batch.original_quantity > 0 ? "text-green-600" : "text-red-600"}>
                                {batch.original_quantity > 0 ? '+' : ''}{batch.original_quantity}
                            </span>
                        </td>

                        {/* [SỬA] Hiển thị runningTotal thay vì quantity_remaining */}
                        <td className="p-4 font-bold text-stone-800">{batch.runningTotal}</td>
                      </tr>
                    ))}
                  </tbody>
              </table>
          </div>
        </div>
      )}
    </div>
  );
};

export default Inventory;