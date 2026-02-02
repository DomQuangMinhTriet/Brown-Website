import { useState, useEffect } from 'react';
import axios from 'axios';
import { FaEye, FaBox, FaShippingFast, FaCheckCircle, FaTimesCircle, FaUndo, FaSearch, FaExclamationTriangle, FaMotorcycle } from 'react-icons/fa';
import { toast } from 'react-toastify';
import { ORDER_STATUS_MAP } from '../../utils/translations';

const Orders = () => {
  const [orders, setOrders] = useState([]);
  const [filteredOrders, setFilteredOrders] = useState([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');

  // State Modal Chi tiết
  const [selectedOrder, setSelectedOrder] = useState(null);
  const [showModal, setShowModal] = useState(false);
  const [processing, setProcessing] = useState(false);

  useEffect(() => {
    fetchOrders();
  }, []);

  useEffect(() => {
    // Logic lọc tìm kiếm
    if (!orders) return;
    const lowerTerm = searchTerm.toLowerCase();
    const results = orders.filter(o => 
      o.code?.toLowerCase().includes(lowerTerm) ||
      o.customer_name?.toLowerCase().includes(lowerTerm) ||
      o.customer_phone?.includes(searchTerm) ||
      o.note?.toLowerCase().includes(lowerTerm) 
    );
    setFilteredOrders(results);
  }, [searchTerm, orders]);

  const fetchOrders = async () => {
    try {
      const res = await axios.get(`${import.meta.env.VITE_API_URL}/api/orders`);
      setOrders(res.data.data);
      setFilteredOrders(res.data.data);
    } catch (error) {
      console.error(error);
    } finally {
      setLoading(false);
    }
  };

  // Hàm xử lý đổi trạng thái
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
      fetchOrders(); 
      setShowModal(false); 
    } catch (error) {
      toast.error(error.response?.data?.message || "Lỗi cập nhật đơn hàng");
    } finally {
      setProcessing(false);
    }
  };

  // Hàm render màu sắc trạng thái
  const getStatusBadge = (status) => {
    return (
      <span className={`px-2 py-1 rounded text-xs font-bold uppercase border ${ORDER_STATUS_MAP[status]?.color || "bg-gray-100"}`}>
        {ORDER_STATUS_MAP[status]?.label || status}
      </span>
    );
  };

  return (
    <div className="p-4 md:p-8">
      {/* Header Responsive */}
      <div className="flex flex-col md:flex-row justify-between items-start md:items-center mb-6 gap-4">
          <h1 className="text-xl md:text-2xl font-bold text-stone-800 flex items-center gap-2">
            <FaBox /> Quản lý Đơn hàng
          </h1>

          {/* Thanh công cụ */}
          <div className="bg-white p-2 rounded-lg shadow-sm border border-stone-200 w-full md:w-auto">
            <div className="relative md:w-80">
                <FaSearch className="absolute left-3 top-3 text-stone-400"/>
                <input 
                    type="text" 
                    placeholder="Tìm đơn, tên, SĐT, ghi chú..." 
                    className="w-full pl-10 p-2 border-none outline-none text-sm"
                    value={searchTerm}
                    onChange={e => setSearchTerm(e.target.value)}
                />
            </div>
          </div>
      </div>

      {/* Bảng Đơn hàng (Responsive Table) */}
      <div className="bg-white rounded-xl shadow border border-stone-200 overflow-hidden">
        <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse min-w-[1100px]">
            <thead className="bg-stone-50 border-b border-stone-200 text-stone-600 uppercase text-xs">
                <tr>
                    <th className="p-4">Mã đơn</th>
                    <th className="p-4">Khách hàng</th>
                    <th className="p-4 w-48">Ghi chú</th>
                    <th className="p-4">Tổng tiền</th>
                    <th className="p-4">Trạng thái</th>
                    <th className="p-4">Ngày tạo</th>
                    <th className="p-4 text-right">Hành động</th>
                </tr>
            </thead>
            <tbody className="divide-y divide-stone-100">
                {loading ? <tr><td colSpan="7" className="p-6 text-center text-stone-500">Đang tải...</td></tr> : 
                filteredOrders.map(order => (
                <tr key={order.id} className="hover:bg-stone-50 transition-colors">
                    <td className="p-4 font-mono font-bold text-stone-700">{order.code}</td>
                    <td className="p-4">
                        <p className="font-bold text-stone-800">{order.customer_name}</p>
                        <p className="text-xs text-stone-500">{order.customer_phone}</p>
                    </td>
                    
                    {/* Hiển thị Ghi chú ra ngoài */}
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
                    <td className="p-4 text-right">
                        <button 
                            onClick={() => { setSelectedOrder(order); setShowModal(true); }}
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
      </div>

      {/* MODAL CHI TIẾT ĐƠN HÀNG */}
      {showModal && selectedOrder && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
            <div className="bg-white rounded-xl w-full max-w-4xl max-h-[90vh] overflow-hidden flex flex-col shadow-2xl">
                {/* Header Modal */}
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
                        {/* Cột Trái: Thông tin khách & Ship */}
                        <div className="md:col-span-1 space-y-6">
                            <div>
                                <h4 className="font-bold text-stone-800 uppercase text-xs mb-2 border-b pb-1">Khách hàng</h4>
                                <p className="font-bold">{selectedOrder.customer_name}</p>
                                <p className="text-sm">{selectedOrder.customer_phone}</p>
                                <p className="text-sm text-stone-600">{selectedOrder.customer_email}</p>
                            </div>
                            <div>
                                <h4 className="font-bold text-stone-800 uppercase text-xs mb-2 border-b pb-1">Địa chỉ giao hàng</h4>
                                <p className="text-sm bg-stone-50 p-3 rounded border text-stone-700">
                                    {selectedOrder.customer_address || "Tại quầy"}
                                </p>
                            </div>
                            
                            {/* Hiển thị chi tiết Ghi chú trong Modal */}
                            <div>
                                <h4 className="font-bold text-stone-800 uppercase text-xs mb-2 border-b pb-1">Ghi chú đơn hàng</h4>
                                <div className="text-sm bg-yellow-50 border border-yellow-200 p-3 rounded text-stone-700 italic">
                                    {selectedOrder.note ? selectedOrder.note : "Không có ghi chú"}
                                </div>
                            </div>

                            <div>
                                 <h4 className="font-bold text-stone-800 uppercase text-xs mb-2 border-b pb-1">Thanh toán</h4>
                                 <p className="text-sm uppercase font-bold text-blue-700">{selectedOrder.payment_method}</p>
                            </div>
                        </div>

                        {/* Cột Phải: Danh sách sản phẩm */}
                        <div className="md:col-span-2">
                            <h4 className="font-bold text-stone-800 uppercase text-xs mb-4 border-b pb-1">Sản phẩm đã đặt</h4>
                            <div className="space-y-3 mb-6">
                                {selectedOrder.order_items?.map((item, idx) => (
                                    <div key={idx} className="flex gap-3 md:gap-4 items-center border-b border-stone-100 pb-3">
                                        <div className="w-12 h-16 md:w-16 md:h-20 bg-stone-100 rounded overflow-hidden flex-shrink-0">
                                            {/* Logic hiển thị ảnh: Ưu tiên ảnh variant, fallback ảnh product */}
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

                            {/* Tổng kết tiền */}
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

                {/* Footer: Các nút hành động */}
                <div className="p-4 md:p-6 bg-stone-50 border-t flex flex-wrap justify-end gap-3 shrink-0">
                    
                    {/* TRẠNG THÁI: PENDING HOẶC PROCESSING */}
                    {['pending', 'processing'].includes(selectedOrder.status) && (
                        <>
                            <button disabled={processing} onClick={() => handleUpdateStatus('cancelled', true)} className="px-4 py-2 border border-red-200 text-red-600 rounded hover:bg-red-50 flex items-center gap-2 text-sm font-bold">
                                <FaTimesCircle/> Hủy đơn
                            </button>
                            
                            {/* Nút Giao Hàng (Mặc định - GHN) */}
                            <button disabled={processing} onClick={() => handleUpdateStatus('shipping')} className="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 flex items-center gap-2 text-sm font-bold shadow-sm">
                                <FaShippingFast/> Giao GHN / ĐVVC
                            </button>

                            {/* Nút Tự Giao Hàng (Bỏ qua GHN) */}
                            <button 
                                disabled={processing} 
                                onClick={() => handleUpdateStatus('shipping', false, { skip_ghn: true })} 
                                className="px-4 py-2 bg-white border border-stone-300 text-stone-700 rounded hover:bg-stone-100 flex items-center gap-2 text-sm font-bold shadow-sm"
                                title="Chuyển trạng thái sang Đang giao mà không tạo đơn GHN"
                            >
                                <FaMotorcycle/> Tự giao / Khác
                            </button>
                        </>
                    )}

                    {/* TRẠNG THÁI: SHIPPING (ĐANG GIAO) */}
                    {selectedOrder.status === 'shipping' && (
                        <>
                            {/* Nút 1: Giao thất bại -> Hàng lỗi/mất -> Không hoàn kho */}
                            <button disabled={processing} 
                                onClick={() => {
                                    if(confirm("Xác nhận Giao thất bại & Hàng HƯ HỎNG (Không hoàn kho)?")) handleUpdateStatus('returned', false);
                                }}
                                className="px-4 py-2 border border-stone-300 text-stone-600 rounded hover:bg-stone-200 flex items-center gap-2 text-sm">
                                <FaExclamationTriangle/> Thất bại (Lỗi)
                            </button>

                            {/* Nút 2: Giao thất bại -> Khách trả -> Nhập lại kho */}
                            <button disabled={processing} 
                                onClick={() => {
                                    if(confirm("Xác nhận Giao thất bại & Khách trả hàng (Nhập lại kho)?")) handleUpdateStatus('returned', true);
                                }}
                                className="px-4 py-2 bg-orange-500 text-white rounded hover:bg-orange-600 flex items-center gap-2 text-sm font-bold">
                                <FaUndo/> Thất bại (Hoàn kho)
                            </button>

                            {/* Nút 3: Giao thành công */}
                            <button disabled={processing} onClick={() => handleUpdateStatus('completed')} className="px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700 flex items-center gap-2 text-sm font-bold shadow-lg">
                                <FaCheckCircle/> Giao thành công
                            </button>
                        </>
                    )}
                    
                    {/* TRẠNG THÁI: COMPLETED (HOÀN THÀNH - Xử lý trả hàng sau bán) */}
                    {selectedOrder.status === 'completed' && (
                        <div className="flex gap-2 items-center flex-wrap justify-end">
                            <span className="text-xs text-stone-500 mr-2">Khách trả hàng?</span>
                            <button disabled={processing} 
                                onClick={() => {
                                    if(confirm("Xác nhận hàng LỖI/HỎNG (Không hoàn kho)?")) handleUpdateStatus('returned', false);
                                }} 
                                className="px-3 py-2 border border-stone-300 rounded text-stone-600 text-sm hover:bg-stone-200">
                                Hàng Lỗi (Vứt bỏ)
                            </button>
                            <button disabled={processing} 
                                onClick={() => {
                                    if(confirm("Xác nhận hàng NGUYÊN VẸN (Cộng lại kho)?")) handleUpdateStatus('returned', true);
                                }} 
                                className="px-3 py-2 bg-stone-800 text-white rounded text-sm hover:bg-stone-900 flex items-center gap-2">
                                <FaUndo/> Hàng Tốt (Nhập kho)
                            </button>
                        </div>
                    )}
                </div>
            </div>
        </div>
      )}
    </div>
  );
};

export default Orders;