import { useState, useEffect } from 'react';
import axios from 'axios';
import { FaFileExcel, FaEye, FaBox, FaShippingFast, FaCheckCircle, FaTimesCircle, FaUndo, FaSearch, FaExclamationTriangle, FaMotorcycle, FaCheckSquare, FaEdit, FaSave, FaDownload } from 'react-icons/fa';
import { toast } from 'react-toastify';
import { ORDER_STATUS_MAP } from '../../utils/translations';

const Orders = () => {
  const [orders, setOrders] = useState([]);
  const [filteredOrders, setFilteredOrders] = useState([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');

  const [activeTab, setActiveTab] = useState('active'); 
  const [currentPage, setCurrentPage] = useState(1);
  const itemsPerPage = 20;

  const [selectedOrder, setSelectedOrder] = useState(null);
  const [showModal, setShowModal] = useState(false);
  const [processing, setProcessing] = useState(false);

  const [selectedIds, setSelectedIds] = useState([]);

  const [showExportModal, setShowExportModal] = useState(false);
  const [exportDates, setExportDates] = useState({ start: '', end: '' });

  const [isEditingMode, setIsEditingMode] = useState(false);
  const [editForm, setEditForm] = useState({
      customer_name: '', customer_phone: '', customer_address: '', note: ''
  });

  useEffect(() => {
    fetchOrders();
  }, []);

  useEffect(() => {
    if (!orders) return;
    
    const tabFiltered = orders.filter(o => {
      if (activeTab === 'active') {
        return ['pending', 'processing', 'shipping', 'completed'].includes(o.status);
      } else if (activeTab === 'cancelled') {
        return ['cancelled', 'returned'].includes(o.status);
      }
      return true;
    });

    const lowerTerm = searchTerm ? searchTerm.toLowerCase().trim() : '';
    
    let searchFiltered = tabFiltered;
    if (lowerTerm) {
        searchFiltered = tabFiltered.filter(o => {
            const matchCode = o.code ? String(o.code).toLowerCase().includes(lowerTerm) : false;
            const matchName = o.customer_name ? String(o.customer_name).toLowerCase().includes(lowerTerm) : false;
            const matchPhone = o.customer_phone ? String(o.customer_phone).includes(lowerTerm) : false;
            const matchNote = o.note ? String(o.note).toLowerCase().includes(lowerTerm) : false;
            return matchCode || matchName || matchPhone || matchNote;
        });
    }

    setFilteredOrders(searchFiltered);
    setCurrentPage(1);
    setSelectedIds([]);
  }, [searchTerm, orders, activeTab]);

  const fetchOrders = async () => {
    try {
      const res = await axios.get(`${import.meta.env.VITE_API_URL}/api/orders`);
      
      const normalizedOrders = res.data.data.map(order => ({
          ...order,
          status: order.status ? order.status.toLowerCase() : 'pending'
      }));
      
      setOrders(normalizedOrders);
    } catch (error) {
      console.error(error);
    } finally {
      setLoading(false);
    }
  };

  const indexOfLastItem = currentPage * itemsPerPage;
  const indexOfFirstItem = indexOfLastItem - itemsPerPage;
  const currentOrders = filteredOrders.slice(indexOfFirstItem, indexOfLastItem);
  const totalPages = Math.ceil(filteredOrders.length / itemsPerPage);

  const handleSelectAll = (e) => {
      if (e.target.checked) {
          const allIdsOnPage = currentOrders.map(o => o.id);
          const newSelectedIds = Array.from(new Set([...selectedIds, ...allIdsOnPage]));
          setSelectedIds(newSelectedIds);
      } else {
          const idsOnPage = currentOrders.map(o => o.id);
          setSelectedIds(selectedIds.filter(id => !idsOnPage.includes(id)));
      }
  };

  const handleSelectOne = (id) => {
      if (selectedIds.includes(id)) {
          setSelectedIds(selectedIds.filter(item => item !== id));
      } else {
          setSelectedIds([...selectedIds, id]);
      }
  };

  const handleBulkAction = async (status, extraData = {}) => {
      if (selectedIds.length === 0) return;
      if (!confirm(`Xác nhận chuyển ${selectedIds.length} đơn sang "${ORDER_STATUS_MAP[status]?.label || status}"?`)) return;

      setProcessing(true);
      const toastId = toast.loading("Đang xử lý hàng loạt...");

      try {
          const res = await axios.put(`${import.meta.env.VITE_API_URL}/api/orders/bulk-status`, {
              orderIds: selectedIds,
              status: status,
              ...extraData
          });

          if (res.data.success) {
              toast.update(toastId, { render: `Thành công: ${res.data.results.success.length} đơn`, type: "success", isLoading: false, autoClose: 2000 });
              
              const updatedList = orders.map(o => selectedIds.includes(o.id) ? { ...o, status: status } : o);
              setOrders(updatedList);
              setSelectedIds([]); 
          }
      } catch (error) {
          toast.update(toastId, { render: "Lỗi xử lý", type: "error", isLoading: false, autoClose: 3000 });
          console.error(error);
      } finally {
          setProcessing(false);
          fetchOrders(); 
      }
  };

  const handleUpdateStatus = async (newStatus, restock = false, extraData = {}) => {
    if (!selectedOrder) return;
    setProcessing(true);
    try {
      await axios.put(`${import.meta.env.VITE_API_URL}/api/orders/${selectedOrder.id}/status`, {
        status: newStatus,
        restock: restock,
        ...extraData 
      });
      
      toast.success(`Đã chuyển trạng thái: ${newStatus}`);
      
      const updatedList = orders.map(o => o.id === selectedOrder.id ? { ...o, status: newStatus } : o);
      setOrders(updatedList);
      
      setShowModal(false); 
    } catch (error) {
      toast.error(error.response?.data?.message || "Lỗi cập nhật đơn hàng");
    } finally {
      setProcessing(false);
      fetchOrders();
    }
  };

  const handleEditClick = () => {
    setEditForm({
        customer_name: selectedOrder.customer_name || '',
        customer_phone: selectedOrder.customer_phone || '',
        customer_address: selectedOrder.customer_address || '',
        note: selectedOrder.note || ''
    });
    setIsEditingMode(true);
  };

  const handleSaveDetails = async () => {
    setProcessing(true);
    try {
        const res = await axios.put(`${import.meta.env.VITE_API_URL}/api/orders/${selectedOrder.id}/details`, editForm);
        if (res.data.success) {
            toast.success("Cập nhật thông tin thành công!");
            const updatedOrder = { ...selectedOrder, ...editForm };
            setSelectedOrder(updatedOrder);
            setOrders(orders.map(o => o.id === updatedOrder.id ? updatedOrder : o));
            setIsEditingMode(false);
        }
    } catch (error) {
        toast.error(error.response?.data?.message || "Lỗi cập nhật thông tin");
    } finally {
        setProcessing(false);
    }
  };

  const getStatusBadge = (status) => {
    return (
      <span className={`px-2 py-1 rounded text-xs font-bold uppercase border ${ORDER_STATUS_MAP[status]?.color || "bg-gray-100"}`}>
        {ORDER_STATUS_MAP[status]?.label || status}
      </span>
    );
  };

  const getSelectedStatusGroup = () => {
      const selected = orders.filter(o => selectedIds.includes(o.id));
      if (selected.length === 0) return null;
      
      const allPending = selected.every(o => ['pending', 'processing'].includes(o.status));
      if (allPending) return 'pending_group';

      const allShipping = selected.every(o => o.status === 'shipping');
      if (allShipping) return 'shipping_group';

      return 'mixed'; 
  };

  const statusGroup = getSelectedStatusGroup();

    const handleExportOrders = async () => {
        try {
            const query = new URLSearchParams();
            if (exportDates.start) query.append('startDate', exportDates.start);
            if (exportDates.end) query.append('endDate', exportDates.end);
            
            const response = await fetch(`${import.meta.env.VITE_API_URL}/api/orders/export/sapo?${query.toString()}`);
            if (!response.ok) throw new Error('Lỗi xuất file');
            
            const blob = await response.blob();
            const url = window.URL.createObjectURL(new Blob([blob]));
            const link = document.createElement('a');
            link.href = url;
            link.setAttribute('download', `Sapo_Orders_Export_${new Date().toISOString().slice(0,10)}.xlsx`);
            document.body.appendChild(link);
            link.click();
            link.parentNode.removeChild(link);
            
            setShowExportModal(false);
            toast.success('Xuất danh sách đơn hàng thành công');
            
            setTimeout(() => { fetchOrders(); }, 1500);
        } catch (error) {
            console.error(error);
            toast.error('Không thể xuất file Excel');
        }
    };

    const handleExportSelectedSapo = async () => {
        if (selectedIds.length === 0) return toast.warning("Vui lòng chọn ít nhất 1 đơn hàng để xuất!");
        
        const toastId = toast.loading("Đang xuất file Excel...");
        try {
            const query = new URLSearchParams();
            query.append('ids', selectedIds.join(','));
            
            const response = await fetch(`${import.meta.env.VITE_API_URL}/api/orders/export/sapo?${query.toString()}`);
            if (!response.ok) throw new Error('Lỗi xuất file');
            
            const blob = await response.blob();
            const url = window.URL.createObjectURL(new Blob([blob]));
            const link = document.createElement('a');
            link.href = url;
            link.setAttribute('download', `Sapo_Selected_Export_${new Date().toISOString().slice(0,10)}.xlsx`);
            document.body.appendChild(link);
            link.click();
            link.parentNode.removeChild(link);
            
            toast.update(toastId, { render: `Đã xuất ${selectedIds.length} đơn hàng!`, type: "success", isLoading: false, autoClose: 3000 });
            
            setSelectedIds([]);
            setTimeout(() => { fetchOrders(); }, 1500);
        } catch (error) {
            console.error(error);
            toast.update(toastId, { render: "Không thể xuất file Excel", type: "error", isLoading: false, autoClose: 3000 });
        }
    };

  return (
    <div className="p-4 md:p-8 relative min-h-screen">
      <div className="flex flex-col md:flex-row justify-between items-start md:items-center mb-6 gap-4">
          <h1 className="text-xl md:text-2xl font-bold text-stone-800 flex items-center gap-2">
            <FaBox /> Quản lý Đơn hàng
          </h1>

          <div className="flex items-center gap-3 w-full md:w-auto">
            <div className="bg-white p-2 rounded-lg shadow-sm border border-stone-200 flex-1 md:flex-none">
                <div className="relative md:w-80">
                    <FaSearch className="absolute left-3 top-3 text-stone-400"/>
                    <input 
                        type="text" placeholder="Tìm đơn, tên, SĐT, ghi chú..." 
                        className="w-full pl-10 p-2 border-none outline-none text-sm"
                        value={searchTerm} onChange={e => setSearchTerm(e.target.value)}
                    />
                </div>
            </div>
            
            {selectedIds.length > 0 && (
                <button 
                    onClick={handleExportSelectedSapo}
                    className="flex items-center justify-center gap-2 bg-blue-600 hover:bg-blue-700 text-white px-4 py-3 rounded-lg shadow-sm font-bold text-sm shrink-0"
                >
                    <FaDownload size={16} /> <span className="hidden md:inline">Xuất chọn ({selectedIds.length})</span>
                </button>
            )}

            <button 
                onClick={() => setShowExportModal(true)}
                className="flex items-center justify-center gap-2 bg-green-600 hover:bg-green-700 text-white px-4 py-3 rounded-lg shadow-sm font-bold text-sm shrink-0"
            >
                <FaFileExcel size={16} /> <span className="hidden md:inline">Xuất Sapo</span>
            </button>
        </div>
      </div>

      <div className="flex gap-6 border-b border-stone-200 mb-6">
        <button
          className={`pb-3 px-1 text-sm font-bold border-b-2 transition-colors ${activeTab === 'active' ? 'border-stone-900 text-stone-900' : 'border-transparent text-stone-500 hover:text-stone-700'}`}
          onClick={() => setActiveTab('active')}
        >
          Đang xử lý / Đang giao / Hoàn thành ({orders.filter(o => ['pending', 'processing', 'shipping', 'completed'].includes(o.status)).length})
        </button>
        <button
          className={`pb-3 px-1 text-sm font-bold border-b-2 transition-colors ${activeTab === 'cancelled' ? 'border-stone-900 text-stone-900' : 'border-transparent text-stone-500 hover:text-stone-700'}`}
          onClick={() => setActiveTab('cancelled')}
        >
          Đơn Hủy / Hoàn trả ({orders.filter(o => ['cancelled', 'returned'].includes(o.status)).length})
        </button>
      </div>

      <div className="bg-white rounded-xl shadow border border-stone-200 overflow-hidden mb-24">
        <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse min-w-[1200px]">
            <thead className="bg-stone-50 border-b border-stone-200 text-stone-600 uppercase text-xs">
                <tr>
                    <th className="p-4 w-10">
                        <input 
                            type="checkbox" 
                            onChange={handleSelectAll} 
                            checked={currentOrders.length > 0 && currentOrders.every(o => selectedIds.includes(o.id))} 
                            className="w-4 h-4 accent-stone-900 cursor-pointer"
                        />
                    </th>
                    <th className="p-4">Mã đơn</th>
                    <th className="p-4">Khách hàng</th>
                    <th className="p-4 w-48">Ghi chú</th>
                    <th className="p-4">Tổng tiền</th>
                    <th className="p-4">Trạng thái</th>
                    <th className="p-4">Ngày tạo</th>
                    <th className="p-4 text-center">Đã xuất</th>
                    <th className="p-4 text-right">Hành động</th>
                </tr>
            </thead>
            <tbody className="divide-y divide-stone-100">
                {loading ? <tr><td colSpan="9" className="p-6 text-center text-stone-500">Đang tải...</td></tr> : 
                currentOrders.length === 0 ? <tr><td colSpan="9" className="p-6 text-center text-stone-500">Không tìm thấy đơn hàng nào.</td></tr> :
                currentOrders.map(order => (
                <tr key={order.id} className={`transition-colors ${selectedIds.includes(order.id) ? 'bg-blue-50' : 'hover:bg-stone-50'}`}>
                    <td className="p-4">
                        <input type="checkbox" checked={selectedIds.includes(order.id)} onChange={() => handleSelectOne(order.id)} className="w-4 h-4 accent-stone-900 cursor-pointer"/>
                    </td>
                    <td className="p-4 font-mono font-bold text-stone-700">{order.code}</td>
                    <td className="p-4">
                        <p className="font-bold text-stone-800">{order.customer_name}</p>
                        <p className="text-xs text-stone-500">{order.customer_phone}</p>
                    </td>
                    
                    <td className="p-4">
                        <p className="text-sm text-stone-600 truncate max-w-[200px]" title={order.note}>
                            {order.note ? (
                                order.note 
                            ) : (
                                <span className="text-stone-300 italic text-xs">--</span>
                            )}
                        </p>
                    </td>

                    <td className="p-4 font-bold">{new Intl.NumberFormat('vi-VN').format(order.total_amount)}đ</td>
                    <td className="p-4">
                        {getStatusBadge(order.status)}
                    </td>
                    <td className="p-4 text-sm text-stone-500">
                        {new Date(order.created_at).toLocaleDateString('vi-VN')}
                    </td>

                    <td className="p-4 text-center">
                        {order.exported_at ? (
                            <div className="flex flex-col items-center justify-center text-green-600" title={`Đã tải xuống lúc: ${new Date(order.exported_at).toLocaleString('vi-VN')}`}>
                                <FaCheckCircle size={15}/>
                                <span className="text-[10px] text-stone-500 mt-1 font-medium">{new Date(order.exported_at).toLocaleDateString('vi-VN')}</span>
                            </div>
                        ) : (
                            <span className="text-stone-300 text-xs">-</span>
                        )}
                    </td>

                    <td className="p-4 text-right">
                        <button 
                            onClick={() => { 
                                setSelectedOrder(order); 
                                setIsEditingMode(false); 
                                setShowModal(true); 
                            }}
                            className="text-stone-500 hover:text-stone-900 flex items-center gap-1 ml-auto p-2 hover:bg-stone-100 rounded"
                        >
                            <FaEye /> Chi tiết
                        </button>
                    </td>
                </tr>
                ))}
            </tbody>
            </table>
        </div>

        {totalPages > 1 && (
            <div className="p-4 border-t border-stone-200 flex justify-between items-center bg-stone-50">
                <span className="text-sm text-stone-500 hidden md:block">
                    Hiển thị {indexOfFirstItem + 1} - {Math.min(indexOfLastItem, filteredOrders.length)} trên tổng {filteredOrders.length} đơn hàng
                </span>
                <div className="flex gap-2 items-center w-full md:w-auto justify-between md:justify-end">
                    <button
                        onClick={() => setCurrentPage(p => Math.max(1, p - 1))}
                        disabled={currentPage === 1}
                        className="px-4 py-2 border border-stone-300 bg-white rounded text-sm hover:bg-stone-100 disabled:opacity-50 disabled:cursor-not-allowed font-medium"
                    >
                        Trước
                    </button>
                    <span className="px-3 py-1 text-sm font-bold text-stone-700">
                        Trang {currentPage} / {totalPages}
                    </span>
                    <button
                        onClick={() => setCurrentPage(p => Math.min(totalPages, p + 1))}
                        disabled={currentPage === totalPages}
                        className="px-4 py-2 border border-stone-300 bg-white rounded text-sm hover:bg-stone-100 disabled:opacity-50 disabled:cursor-not-allowed font-medium"
                    >
                        Tiếp theo
                    </button>
                </div>
            </div>
        )}
      </div>

      {selectedIds.length > 0 && (
          <div className="fixed bottom-6 left-1/2 -translate-x-1/2 bg-stone-900 text-white px-6 py-3 rounded-full shadow-2xl flex items-center gap-6 z-40 animate-bounce-in">
              <span className="font-bold text-sm flex items-center gap-2">
                  <FaCheckSquare/> Đã chọn: {selectedIds.length}
              </span>
              <div className="h-4 w-[1px] bg-stone-700"></div>
              
              <div className="flex gap-2">
                  {statusGroup === 'pending_group' && (
                      <>
                          <button onClick={() => handleBulkAction('cancelled', { restock: true })} disabled={processing} className="hover:text-red-300 font-bold text-xs uppercase flex flex-col items-center gap-1 px-3">
                              <FaTimesCircle size={16}/> Hủy đơn
                          </button>
                          <button onClick={() => handleBulkAction('shipping')} disabled={processing} className="hover:text-blue-300 font-bold text-xs uppercase flex flex-col items-center gap-1 px-3 border-l border-stone-700">
                              <FaShippingFast size={16}/> Giao GHN
                          </button>
                          <button onClick={() => handleBulkAction('shipping', { skip_ghn: true })} disabled={processing} className="hover:text-yellow-300 font-bold text-xs uppercase flex flex-col items-center gap-1 px-3">
                              <FaMotorcycle size={16}/> Tự giao
                          </button>
                      </>
                  )}

                  {statusGroup === 'shipping_group' && (
                      <>
                          <button onClick={() => handleBulkAction('returned', { restock: false })} disabled={processing} className="hover:text-red-300 font-bold text-xs uppercase flex flex-col items-center gap-1 px-3">
                              <FaExclamationTriangle size={16}/> Lỗi (Vứt bỏ)
                          </button>
                          <button onClick={() => handleBulkAction('returned', { restock: true })} disabled={processing} className="hover:text-orange-300 font-bold text-xs uppercase flex flex-col items-center gap-1 px-3">
                              <FaUndo size={16}/> Lỗi (Hoàn kho)
                          </button>
                          <button onClick={() => handleBulkAction('completed')} disabled={processing} className="hover:text-green-300 font-bold text-xs uppercase flex flex-col items-center gap-1 px-3 border-l border-stone-700">
                              <FaCheckCircle size={16}/> Thành công
                          </button>
                      </>
                  )}

                  {statusGroup === 'mixed' && (
                      <span className="text-yellow-400 text-xs italic font-medium px-2">
                          ⚠️ Vui lòng chỉ chọn các đơn có cùng trạng thái.
                      </span>
                  )}
                  {!['pending_group', 'shipping_group', 'mixed'].includes(statusGroup) && statusGroup !== null && (
                       <span className="text-stone-400 text-xs italic px-2">
                          Không có hành động cho nhóm này.
                      </span>
                  )}
              </div>

              <button onClick={() => setSelectedIds([])} className="ml-2 text-stone-500 hover:text-white font-bold text-lg">&times;</button>
          </div>
      )}

      {showModal && selectedOrder && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
            <div className="bg-white rounded-xl w-full max-w-4xl max-h-[90vh] overflow-hidden flex flex-col shadow-2xl">
                <div className="p-4 md:p-6 border-b flex justify-between items-center bg-stone-50 shrink-0">
                    <div>
                        <h3 className="text-lg md:text-xl font-bold flex items-center gap-2">
                            Đơn hàng #{selectedOrder.code} 
                            {getStatusBadge(selectedOrder.status)}
                        </h3>
                        <p className="text-xs md:text-sm text-stone-500 mt-1">
                            Ngày tạo: {new Date(selectedOrder.created_at).toLocaleString('vi-VN')}
                        </p>
                    </div>
                    <button onClick={() => setShowModal(false)} className="text-stone-400 hover:text-red-500 text-2xl px-2">&times;</button>
                </div>

                <div className="p-4 md:p-6 overflow-y-auto flex-1 bg-white">
                    <div className="grid grid-cols-1 md:grid-cols-3 gap-6 md:gap-8">
                        <div className="md:col-span-1 space-y-4">
                            <div className="flex justify-between items-center border-b pb-1">
                                <h4 className="font-bold text-stone-800 uppercase text-xs">Thông tin giao hàng</h4>
                                {!isEditingMode && ['pending', 'processing'].includes(selectedOrder.status) && (
                                    <button onClick={handleEditClick} className="text-blue-600 hover:text-blue-800 text-xs flex items-center gap-1 font-medium">
                                        <FaEdit /> Sửa
                                    </button>
                                )}
                            </div>
                            
                            {isEditingMode ? (
                                <div className="space-y-3 animate-fade-in bg-stone-50 p-3 rounded border border-stone-200">
                                    <div>
                                        <label className="text-xs font-bold text-stone-500 uppercase">Tên khách hàng</label>
                                        <input type="text" className="w-full border p-2 rounded text-sm outline-none mt-1 focus:border-stone-500" value={editForm.customer_name} onChange={e => setEditForm({...editForm, customer_name: e.target.value})} />
                                    </div>
                                    <div>
                                        <label className="text-xs font-bold text-stone-500 uppercase">Số điện thoại</label>
                                        <input type="text" className="w-full border p-2 rounded text-sm outline-none mt-1 focus:border-stone-500" value={editForm.customer_phone} onChange={e => setEditForm({...editForm, customer_phone: e.target.value})} />
                                    </div>
                                    <div>
                                        <label className="text-xs font-bold text-stone-500 uppercase">Địa chỉ</label>
                                        <textarea className="w-full border p-2 rounded text-sm outline-none mt-1 h-16 focus:border-stone-500" value={editForm.customer_address} onChange={e => setEditForm({...editForm, customer_address: e.target.value})} />
                                    </div>
                                    <div>
                                        <label className="text-xs font-bold text-stone-500 uppercase">Ghi chú</label>
                                        <textarea className="w-full border border-yellow-300 bg-yellow-50 p-2 rounded text-sm outline-none mt-1 h-16 focus:border-yellow-500" value={editForm.note} onChange={e => setEditForm({...editForm, note: e.target.value})} />
                                    </div>
                                    <div className="flex gap-2 justify-end pt-2 border-t mt-2">
                                        <button onClick={() => setIsEditingMode(false)} className="px-4 py-2 text-xs font-bold border rounded hover:bg-stone-200">Hủy</button>
                                        <button onClick={handleSaveDetails} disabled={processing} className="px-4 py-2 text-xs font-bold bg-stone-900 text-white rounded hover:bg-black flex items-center gap-1 disabled:opacity-50">
                                            <FaSave /> Lưu
                                        </button>
                                    </div>
                                </div>
                            ) : (
                                <div className="space-y-4">
                                    <div>
                                        <p className="font-bold">{selectedOrder.customer_name}</p>
                                        <p className="text-sm">{selectedOrder.customer_phone}</p>
                                        <p className="text-sm text-stone-600">{selectedOrder.customer_email}</p>
                                    </div>
                                    <div>
                                        <p className="text-sm bg-stone-50 p-3 rounded border text-stone-700">
                                            {selectedOrder.customer_address || "Tại quầy"}
                                        </p>
                                    </div>
                                    <div>
                                        <div className="text-sm bg-yellow-50 border border-yellow-200 p-3 rounded text-stone-700 italic">
                                            {selectedOrder.note ? selectedOrder.note : "Không có ghi chú"}
                                        </div>
                                    </div>
                                </div>
                            )}

                            <div className="mt-6">
                                 <h4 className="font-bold text-stone-800 uppercase text-xs mb-2 border-b pb-1">Thanh toán</h4>
                                 <p className="text-sm uppercase font-bold text-blue-700">{selectedOrder.payment_method}</p>
                            </div>
                        </div>

                        <div className="md:col-span-2">
                            <h4 className="font-bold text-stone-800 uppercase text-xs mb-4 border-b pb-1">Sản phẩm đã đặt</h4>
                            <div className="space-y-3 mb-6">
                                {selectedOrder.order_items?.map((item, idx) => (
                                    <div key={idx} className="flex gap-3 md:gap-4 items-center border-b border-stone-100 pb-3">
                                        <div className="w-12 h-16 md:w-16 md:h-20 bg-stone-100 rounded overflow-hidden flex-shrink-0">
                                            <img src={item.variants?.image_url || item.product_image} alt="" className="w-full h-full object-cover"/>
                                        </div>
                                        <div className="flex-1">
                                            <p className="font-bold text-stone-800 text-sm md:text-base">{item.product_name || item.variants?.products?.name}</p>
                                            <p className="text-xs text-stone-500">
                                                Size: <span className="font-bold">{item.variants?.size}</span> | Màu: <span className="font-bold">{item.variants?.color}</span>
                                            </p>
                                        </div>
                                        <div className="text-right">
                                            <p className="text-sm font-medium">{item.quantity} x {new Intl.NumberFormat('vi-VN').format(item.price_at_purchase)}</p>
                                            <p className="font-bold text-stone-900">{new Intl.NumberFormat('vi-VN').format(item.price_at_purchase * item.quantity)}</p>
                                        </div>
                                    </div>
                                ))}
                            </div>

                            <div className="flex justify-end text-right space-y-1 text-sm border-t pt-4">
                                <div className="w-full md:w-64 space-y-2">
                                    <div className="flex justify-between"><span>Tạm tính:</span> <span>{new Intl.NumberFormat('vi-VN').format(selectedOrder.total_amount - (selectedOrder.shipping_fee || 0) + (selectedOrder.discount_amount || 0))}đ</span></div>
                                    <div className="flex justify-between"><span>Phí vận chuyển:</span> <span>{new Intl.NumberFormat('vi-VN').format(selectedOrder.shipping_fee || 0)}đ</span></div>
                                    {selectedOrder.discount_amount > 0 && (
                                        <div className="flex justify-between text-green-600"><span>Giảm giá:</span> <span>-{new Intl.NumberFormat('vi-VN').format(selectedOrder.discount_amount)}đ</span></div>
                                    )}
                                    <div className="flex justify-between font-bold text-lg text-stone-900 mt-2 pt-2 border-t border-stone-200">
                                        <span>TỔNG CỘNG:</span> 
                                        <span>{new Intl.NumberFormat('vi-VN').format(selectedOrder.total_amount)}đ</span>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>

                <div className="p-4 md:p-6 bg-stone-50 border-t flex flex-wrap justify-end gap-3 shrink-0">
                    
                    {['pending', 'processing'].includes(selectedOrder.status) && (
                        <>
                            <button disabled={processing} onClick={() => handleUpdateStatus('cancelled', true)} className="px-4 py-2 border border-red-200 text-red-600 rounded hover:bg-red-50 flex items-center gap-2 text-sm font-bold">
                                <FaTimesCircle/> Hủy đơn
                            </button>
                            <button disabled={processing} onClick={() => handleUpdateStatus('shipping')} className="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 flex items-center gap-2 text-sm font-bold shadow-sm">
                                <FaShippingFast/> Giao GHN / ĐVVC
                            </button>
                            <button 
                                disabled={processing} 
                                onClick={() => {
                                    const code = window.prompt("Nhập mã vận đơn SPX Express (Để trống nếu tự đi giao):");
                                    if (code !== null) {
                                        handleUpdateStatus('shipping', false, { 
                                            skip_ghn: true, 
                                            tracking_code: code.trim() 
                                        });
                                    }
                                }} 
                                className="px-4 py-2 bg-white border border-stone-300 text-stone-700 rounded hover:bg-stone-100 flex items-center gap-2 text-sm font-bold shadow-sm"
                            >
                                <FaMotorcycle/> SPX / Tự giao
                            </button>
                        </>
                    )}

                    {selectedOrder.status === 'shipping' && (
                        <>
                            <button disabled={processing} onClick={() => { if(confirm("Xác nhận Giao thất bại & Hàng HƯ HỎNG (Không hoàn kho)?")) handleUpdateStatus('returned', false); }} className="px-4 py-2 border border-stone-300 text-stone-600 rounded hover:bg-stone-200 flex items-center gap-2 text-sm">
                                <FaExclamationTriangle/> Thất bại (Lỗi)
                            </button>
                            <button disabled={processing} onClick={() => { if(confirm("Xác nhận Giao thất bại & Khách trả hàng (Nhập lại kho)?")) handleUpdateStatus('returned', true); }} className="px-4 py-2 bg-orange-500 text-white rounded hover:bg-orange-600 flex items-center gap-2 text-sm font-bold">
                                <FaUndo/> Thất bại (Hoàn kho)
                            </button>
                            <button disabled={processing} onClick={() => handleUpdateStatus('completed')} className="px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700 flex items-center gap-2 text-sm font-bold shadow-lg">
                                <FaCheckCircle/> Giao thành công
                            </button>
                        </>
                    )}
                    
                    {selectedOrder.status === 'completed' && (
                        <div className="flex gap-2 items-center flex-wrap justify-end">
                            <span className="text-xs text-stone-500 mr-2">Khách trả hàng?</span>
                            <button disabled={processing} onClick={() => { if(confirm("Xác nhận hàng LỖI/HỎNG (Không hoàn kho)?")) handleUpdateStatus('returned', false); }} className="px-3 py-2 border border-stone-300 rounded text-stone-600 text-sm hover:bg-stone-200">
                                Hàng Lỗi (Vứt bỏ)
                            </button>
                            <button disabled={processing} onClick={() => { if(confirm("Xác nhận hàng NGUYÊN VẸN (Cộng lại kho)?")) handleUpdateStatus('returned', true); }} className="px-3 py-2 bg-stone-800 text-white rounded text-sm hover:bg-stone-900 flex items-center gap-2">
                                <FaUndo/> Hàng Tốt (Nhập kho)
                            </button>
                        </div>
                    )}
                </div>
            </div>
        </div>
      )}

      {showExportModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
            <div className="bg-white rounded-xl w-full max-w-sm overflow-hidden flex flex-col shadow-2xl animate-fade-in">
                <div className="p-4 border-b bg-stone-50 flex justify-between items-center">
                    <h3 className="font-bold text-lg text-stone-800">Xuất đơn hàng (Sapo)</h3>
                    <button onClick={() => setShowExportModal(false)} className="text-stone-400 hover:text-red-500 text-xl leading-none">&times;</button>
                </div>
                <div className="p-6 space-y-4">
                    <p className="text-xs text-stone-500 italic mb-2">Bỏ trống nếu muốn tải xuống toàn bộ đơn hàng trong hệ thống.</p>
                    <div>
                        <label className="block text-sm font-bold text-stone-700 mb-1">Từ ngày</label>
                        <input type="date" className="w-full border border-stone-300 p-2 rounded outline-none focus:border-stone-900" value={exportDates.start} onChange={e => setExportDates({...exportDates, start: e.target.value})} />
                    </div>
                    <div>
                        <label className="block text-sm font-bold text-stone-700 mb-1">Đến ngày</label>
                        <input type="date" className="w-full border border-stone-300 p-2 rounded outline-none focus:border-stone-900" value={exportDates.end} onChange={e => setExportDates({...exportDates, end: e.target.value})} />
                    </div>
                </div>
                <div className="p-4 bg-stone-50 border-t flex justify-end gap-2">
                    <button onClick={() => setShowExportModal(false)} className="px-4 py-2 text-sm font-bold text-stone-600 hover:bg-stone-200 rounded transition-colors">Hủy bỏ</button>
                    <button onClick={handleExportOrders} className="px-4 py-2 text-sm font-bold bg-green-600 text-white rounded hover:bg-green-700 flex items-center gap-2 shadow transition-colors">
                        <FaFileExcel /> Tải file Excel
                    </button>
                </div>
            </div>
        </div>
      )}
    </div>
  );
};

export default Orders;