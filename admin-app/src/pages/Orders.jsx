<<<<<<< Updated upstream
// admin-app/src/pages/Orders.jsx

import { useEffect, useState } from 'react';
import axios from 'axios';
import { 
  FaBoxOpen, 
  FaChevronDown, 
  FaChevronUp, 
  FaMapMarkerAlt, 
  FaShoppingCart, // Icon cho nút POS
  FaSync // Icon refresh
} from 'react-icons/fa';

const Orders = () => {
  const [orders, setOrders] = useState([]);
  const [loading, setLoading] = useState(true);
  const [expandedOrderId, setExpandedOrderId] = useState(null);
  
  // Filter state (để lọc đơn hàng theo trạng thái nếu cần)
  const [statusFilter, setStatusFilter] = useState('all');
=======
import { useState, useEffect } from 'react';
import axios from 'axios';
import { FaEye, FaBox, FaShippingFast, FaCheckCircle, FaTimesCircle, FaUndo, FaSearch } from 'react-icons/fa';
import { toast } from 'react-toastify';

const Orders = () => {
  const [orders, setOrders] = useState([]);
  const [filteredOrders, setFilteredOrders] = useState([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');

  // State Modal Chi tiết
  const [selectedOrder, setSelectedOrder] = useState(null);
  const [showModal, setShowModal] = useState(false);
  const [processing, setProcessing] = useState(false);
>>>>>>> Stashed changes

  useEffect(() => {
    fetchOrders();
  }, []);

<<<<<<< Updated upstream
  const fetchOrders = async () => {
    setLoading(true);
    try {
      const res = await axios.get('http://localhost:5000/api/orders');
      if (res.data.success) {
        setOrders(res.data.data);
      }
    } catch (error) {
      console.error("Lỗi tải đơn hàng:", error);
=======
  useEffect(() => {
    // Logic lọc tìm kiếm
    if (!orders) return;
    const lowerTerm = searchTerm.toLowerCase();
    const results = orders.filter(o => 
      o.code?.toLowerCase().includes(lowerTerm) ||
      o.customer_name?.toLowerCase().includes(lowerTerm) ||
      o.customer_phone?.includes(searchTerm)
    );
    setFilteredOrders(results);
  }, [searchTerm, orders]);

  const fetchOrders = async () => {
    try {
      const res = await axios.get('http://localhost:5000/api/orders');
      setOrders(res.data.data);
      setFilteredOrders(res.data.data);
    } catch (error) {
      console.error(error);
>>>>>>> Stashed changes
    } finally {
      setLoading(false);
    }
  };

<<<<<<< Updated upstream
  const handleStatusChange = async (orderId, newStatus) => {
      // Không cần prompt nhập mã nữa, hệ thống tự làm!
      if(!confirm(`Xác nhận chuyển trạng thái sang "${newStatus}"?\nHệ thống sẽ tự động tạo đơn bên SPX và gửi mail cho khách.`)) return;

      try {
        const res = await axios.put(`http://localhost:5000/api/orders/${orderId}/status`, { 
            status: newStatus 
        });

        if(res.data.success) {
          alert(`✅ Thành công! Mã vận đơn SPX: ${res.data.data.shipping_tracking_code || 'Đã tạo'}`);
          fetchOrders(); 
        }
      } catch (error) {
        alert("Lỗi: " + error.response?.data?.message);
      }
  };

  const toggleExpand = (id) => {
    setExpandedOrderId(expandedOrderId === id ? null : id);
  };

  // Helper function: Màu sắc trạng thái
  const getStatusColor = (status) => {
    switch (status) {
      case 'pending': return 'bg-yellow-100 text-yellow-800 border-yellow-200';
      case 'confirmed': return 'bg-blue-100 text-blue-800 border-blue-200';
      case 'shipping': return 'bg-purple-100 text-purple-800 border-purple-200';
      case 'completed': return 'bg-green-100 text-green-800 border-green-200';
      case 'cancelled': return 'bg-red-100 text-red-800 border-red-200';
      default: return 'bg-gray-100 text-gray-800';
    }
  };

  // Helper: Format tiền
  const formatMoney = (amount) => new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(amount);

  return (
    <div className="p-6 md:p-10 max-w-7xl mx-auto">
      
      {/* HEADER: TIÊU ĐỀ & NÚT POS */}
      <div className="flex flex-col md:flex-row md:items-center justify-between mb-8 gap-4">
        <div>
          <h1 className="text-2xl font-bold text-stone-800">Quản lý Đơn hàng</h1>
          <p className="text-stone-500 mt-1">Theo dõi và xử lý đơn hàng từ Website & POS</p>
        </div>
        
        <div className="flex gap-3">
            <button onClick={fetchOrders} className="px-4 py-2 bg-white border border-stone-200 text-stone-600 rounded-lg hover:bg-stone-50 flex items-center gap-2">
                <FaSync /> Làm mới
            </button>
            
            {/* NÚT POS QUAN TRỌNG: Mở trang Checkout ở tab mới với mode POS */}
            <a 
                href="http://localhost:5174/collection?pos=true" // Cần sửa port 5173 nếu Frontend chạy port khác
                target="_blank" 
                rel="noreferrer"
                className="px-6 py-2 bg-stone-900 text-white rounded-lg hover:bg-stone-800 shadow-lg flex items-center gap-2 font-bold uppercase tracking-wide"
            >
                <FaShoppingCart /> Tạo đơn hàng mới (POS)
            </a>
        </div>
      </div>

      {/* DANH SÁCH ĐƠN HÀNG */}
      <div className="bg-white rounded-xl border border-stone-200 shadow-sm overflow-hidden">
        {loading ? (
            <div className="p-10 text-center text-stone-400">Đang tải dữ liệu...</div>
        ) : orders.length === 0 ? (
            <div className="p-10 text-center flex flex-col items-center">
                <FaBoxOpen className="text-4xl text-stone-300 mb-3"/>
                <p className="text-stone-500">Chưa có đơn hàng nào.</p>
            </div>
        ) : (
           <div className="overflow-x-auto">
             <table className="w-full text-left border-collapse">
               <thead className="bg-stone-50 text-stone-500 uppercase text-xs font-bold">
                 <tr>
                   <th className="p-4">Mã đơn</th>
                   <th className="p-4">Khách hàng</th>
                   <th className="p-4 text-center">Nguồn</th>
                   <th className="p-4">Tổng tiền</th>
                   <th className="p-4">Trạng thái</th>
                   <th className="p-4 text-right">Hành động</th>
                 </tr>
               </thead>
               <tbody className="divide-y divide-stone-100 text-sm">
                 {orders.map(order => (
                   <>
                     {/* DÒNG CHÍNH */}
                     <tr key={order.id} className={`hover:bg-stone-50 transition-colors ${expandedOrderId === order.id ? 'bg-stone-50' : ''}`}>
                       <td className="p-4 font-mono font-medium text-blue-600 cursor-pointer" onClick={() => toggleExpand(order.id)}>
                         {order.code}
                       </td>
                       <td className="p-4">
                         <div className="font-bold text-stone-800">{order.customer_name}</div>
                         <div className="text-xs text-stone-500">{order.customer_phone}</div>
                       </td>
                       <td className="p-4 text-center">
                            {/* Hiển thị Icon/Text cho nguồn đơn */}
                            {order.payment_method === 'cash' ? (
                                <span className="text-xs font-bold bg-green-100 text-green-700 px-2 py-1 rounded">POS</span>
                            ) : (
                                <span className="text-xs font-bold bg-blue-50 text-blue-600 px-2 py-1 rounded">WEB</span>
                            )}
                       </td>
                       <td className="p-4 font-bold text-stone-900">{formatMoney(order.total_amount)}</td>
                       <td className="p-4">
                         <span className={`px-3 py-1 rounded-full text-xs font-bold border ${getStatusColor(order.status)}`}>
                           {order.status === 'pending' ? 'Chờ xử lý' : 
                            order.status === 'confirmed' ? 'Đã xác nhận' :
                            order.status === 'shipping' ? 'Đang giao' :
                            order.status === 'completed' ? 'Hoàn thành' : 'Đã hủy'}
                         </span>
                       </td>
                       <td className="p-4 text-right">
                         <button onClick={() => toggleExpand(order.id)} className="text-stone-400 hover:text-stone-800 p-2">
                           {expandedOrderId === order.id ? <FaChevronUp/> : <FaChevronDown/>}
                         </button>
                       </td>
                     </tr>

                     {/* DÒNG CHI TIẾT (Expand) */}
                     {expandedOrderId === order.id && (
                       <tr className="bg-stone-50/50">
                         <td colSpan="6" className="p-0">
                            <div className="p-6 border-b border-stone-200 grid grid-cols-1 md:grid-cols-2 gap-8 animate-fade-in">
                                {/* Cột Trái: Thông tin giao hàng & Xử lý */}
                                <div>
                                    <h3 className="font-bold text-stone-800 mb-3 uppercase text-xs tracking-wider">Thông tin giao hàng</h3>
                                    <div className="text-sm text-stone-600 space-y-2 bg-white p-4 rounded border border-stone-200">
                                        <p className="flex items-start gap-2"><FaMapMarkerAlt className="mt-1 text-stone-400"/> {order.shipping_address}</p>
                                        <p><b>Email:</b> {order.customer_email || 'Không có'}</p>
                                        <p><b>Ghi chú:</b> {order.note || 'Không có'}</p>
                                        <p><b>Vận chuyển:</b> {order.shipping_carrier} - {order.shipping_tracking_code || 'Chưa có mã'}</p>
                                    </div>

                                    <div className="mt-4">
                                        <h3 className="font-bold text-stone-800 mb-3 uppercase text-xs tracking-wider">Cập nhật trạng thái</h3>
                                        <div className="flex gap-2 flex-wrap">
                                            {order.status === 'pending' && (
                                                <button onClick={() => handleStatusChange(order.id, 'confirmed')} className="px-3 py-1 bg-blue-600 text-white text-xs rounded hover:bg-blue-700">Xác nhận đơn</button>
                                            )}
                                            {order.status === 'confirmed' && (
                                                <button onClick={() => handleStatusChange(order.id, 'shipping')} className="px-3 py-1 bg-purple-600 text-white text-xs rounded hover:bg-purple-700">Giao hàng</button>
                                            )}
                                            {order.status === 'shipping' && (
                                                <button onClick={() => handleStatusChange(order.id, 'completed')} className="px-3 py-1 bg-green-600 text-white text-xs rounded hover:bg-green-700">Hoàn thành</button>
                                            )}
                                            {['pending', 'confirmed'].includes(order.status) && (
                                                <button onClick={() => handleStatusChange(order.id, 'cancelled')} className="px-3 py-1 bg-red-100 text-red-600 text-xs rounded border border-red-200 hover:bg-red-200">Hủy đơn</button>
                                            )}
                                        </div>
                                    </div>
                                </div>

                                {/* Cột Phải: Danh sách sản phẩm */}
                                <div>
                                    <h3 className="font-bold text-stone-800 mb-3 uppercase text-xs tracking-wider">Sản phẩm ({order.order_items?.length})</h3>
                                    <div className="space-y-3">
                                        {order.order_items?.map((item, idx) => (
                                            <div key={idx} className="flex gap-3 bg-white p-3 rounded border border-stone-100">
                                                {/* Ảnh (Placeholder nếu ko join bảng) */}
                                                <div className="w-12 h-12 bg-stone-200 rounded flex items-center justify-center text-stone-400 text-xs">IMG</div>
                                                <div className="flex-1">
                                                    {/* Lưu ý: Backend cần join bảng variants -> products để lấy tên */}
                                                    <div className="font-medium text-stone-800">Sản phẩm ID: {item.variant_id}</div> 
                                                    <div className="flex justify-between mt-1 text-sm">
                                                        <span>SL: <b>{item.quantity}</b></span>
                                                        <span className="font-bold">{formatMoney(item.unit_price)}</span>
                                                    </div>
                                                </div>
                                            </div>
                                        ))}
                                    </div>
                                    <div className="flex justify-between items-center mt-3 pt-3 border-t border-stone-200">
                                        <span className="text-sm font-bold">Tổng thanh toán:</span>
                                        <span className="text-lg font-bold text-stone-900">{formatMoney(order.total_amount)}</span>
                                    </div>
                                    {order.discount_amount > 0 && (
                                        <div className="flex justify-between items-center text-green-600 text-sm">
                                            <span>Voucher: {order.voucher_code}</span>
                                            <span>-{formatMoney(order.discount_amount)}</span>
                                        </div>
                                    )}
                                </div>
                            </div>
                         </td>
                       </tr>
                     )}
                   </>
                 ))}
               </tbody>
             </table>
           </div>
        )}
      </div>
=======
  // Hàm xử lý đổi trạng thái
  const handleUpdateStatus = async (newStatus, restock = false) => {
    if (!selectedOrder) return;
    setProcessing(true);
    try {
      await axios.put(`http://localhost:5000/api/orders/${selectedOrder.id}/status`, {
        status: newStatus,
        restock: restock // Gửi kèm yêu cầu hoàn kho hay không
      });
      
      toast.success(`Đã chuyển trạng thái: ${newStatus}`);
      fetchOrders(); // Load lại danh sách
      setShowModal(false); // Đóng modal
    } catch (error) {
      toast.error("Lỗi cập nhật đơn hàng");
    } finally {
      setProcessing(false);
    }
  };

  // Hàm render màu sắc trạng thái
  const getStatusBadge = (status) => {
    const styles = {
      pending: "bg-yellow-100 text-yellow-800",
      paid: "bg-blue-100 text-blue-800",
      shipping: "bg-purple-100 text-purple-800",
      completed: "bg-green-100 text-green-800",
      cancelled: "bg-red-100 text-red-800",
      returned: "bg-stone-200 text-stone-800"
    };
    return (
      <span className={`px-2 py-1 rounded text-xs font-bold uppercase ${styles[status] || "bg-gray-100"}`}>
        {status}
      </span>
    );
  };

  return (
    <div className="p-8">
      <h1 className="text-2xl font-bold text-stone-800 mb-6 flex items-center gap-2">
        <FaBox /> Quản lý Đơn hàng
      </h1>

      {/* Thanh công cụ */}
      <div className="bg-white p-4 rounded-lg shadow-sm mb-6 border border-stone-200">
        <div className="relative">
            <FaSearch className="absolute left-3 top-3 text-stone-400"/>
            <input 
                type="text" 
                placeholder="Tìm mã đơn, tên khách, số điện thoại..." 
                className="w-full pl-10 p-2 border rounded outline-none focus:border-stone-800"
                value={searchTerm}
                onChange={e => setSearchTerm(e.target.value)}
            />
        </div>
      </div>

      {/* Bảng Đơn hàng */}
      <div className="bg-white rounded-xl shadow border border-stone-200 overflow-hidden">
        <table className="w-full text-left">
          <thead className="bg-stone-50 border-b border-stone-200">
            <tr>
              <th className="p-4">Mã đơn</th>
              <th className="p-4">Khách hàng</th>
              <th className="p-4">Tổng tiền</th>
              <th className="p-4">Trạng thái</th>
              <th className="p-4">Ngày tạo</th>
              <th className="p-4 text-right">Hành động</th>
            </tr>
          </thead>
          <tbody>
            {loading ? <tr><td colSpan="6" className="p-6 text-center">Đang tải...</td></tr> : 
             filteredOrders.map(order => (
              <tr key={order.id} className="border-b border-stone-100 hover:bg-stone-50">
                <td className="p-4 font-mono font-bold">{order.code}</td>
                <td className="p-4">
                    <p className="font-bold text-stone-800">{order.customer_name}</p>
                    <p className="text-xs text-stone-500">{order.customer_phone}</p>
                </td>
                <td className="p-4 font-bold">{new Intl.NumberFormat('vi-VN').format(order.total_amount)}đ</td>
                <td className="p-4">{getStatusBadge(order.status)}</td>
                <td className="p-4 text-sm text-stone-500">
                    {new Date(order.created_at).toLocaleDateString('vi-VN')}
                </td>
                <td className="p-4 text-right">
                    <button 
                        onClick={() => { setSelectedOrder(order); setShowModal(true); }}
                        className="text-stone-500 hover:text-stone-900 flex items-center gap-1 ml-auto"
                    >
                        <FaEye /> Chi tiết
                    </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* MODAL CHI TIẾT ĐƠN HÀNG (QUAN TRỌNG) */}
      {showModal && selectedOrder && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
            <div className="bg-white rounded-xl w-full max-w-4xl max-h-[90vh] overflow-y-auto shadow-2xl">
                {/* Header Modal */}
                <div className="p-6 border-b flex justify-between items-center bg-stone-50 sticky top-0">
                    <div>
                        <h3 className="text-xl font-bold flex items-center gap-2">
                            Đơn hàng #{selectedOrder.code} 
                            {getStatusBadge(selectedOrder.status)}
                        </h3>
                        <p className="text-sm text-stone-500">
                            Ngày tạo: {new Date(selectedOrder.created_at).toLocaleString('vi-VN')}
                        </p>
                    </div>
                    <button onClick={() => setShowModal(false)} className="text-stone-400 hover:text-red-500 text-2xl">&times;</button>
                </div>

                <div className="p-6 grid grid-cols-1 md:grid-cols-3 gap-8">
                    {/* Cột Trái: Thông tin khách & Ship */}
                    <div className="md:col-span-1 space-y-6">
                        <div>
                            <h4 className="font-bold text-stone-800 uppercase text-xs mb-2">Khách hàng</h4>
                            <p className="font-bold">{selectedOrder.customer_name}</p>
                            <p>{selectedOrder.customer_phone}</p>
                            <p className="text-sm text-stone-600">{selectedOrder.customer_email}</p>
                        </div>
                        <div>
                            <h4 className="font-bold text-stone-800 uppercase text-xs mb-2">Địa chỉ giao hàng</h4>
                            <p className="text-sm bg-stone-50 p-3 rounded border">
                                {selectedOrder.customer_address}
                            </p>
                        </div>
                        <div>
                             <h4 className="font-bold text-stone-800 uppercase text-xs mb-2">Thanh toán</h4>
                             <p className="text-sm uppercase font-bold text-blue-700">{selectedOrder.payment_method}</p>
                        </div>
                    </div>

                    {/* Cột Phải: Danh sách sản phẩm */}
                    <div className="md:col-span-2">
                        <h4 className="font-bold text-stone-800 uppercase text-xs mb-4">Sản phẩm đã đặt</h4>
                        <div className="space-y-3 mb-6">
                            {selectedOrder.order_items?.map((item, idx) => (
                                <div key={idx} className="flex gap-4 items-center border-b border-stone-100 pb-3">
                                    <img src={item.product_image} alt="" className="w-16 h-20 object-cover rounded bg-stone-200"/>
                                    <div className="flex-1">
                                        <p className="font-bold text-stone-800">{item.product_name}</p>
                                        <p className="text-xs text-stone-500">
                                            Size: {item.variants?.size} | Màu: {item.variants?.color}
                                        </p>
                                    </div>
                                    <div className="text-right">
                                        <p className="font-bold">{item.quantity} x {new Intl.NumberFormat().format(item.unit_price)}đ</p>
                                        <p className="font-bold text-stone-900">{new Intl.NumberFormat().format(item.total_price)}đ</p>
                                    </div>
                                </div>
                            ))}
                        </div>

                        {/* Tổng kết tiền */}
                        <div className="flex justify-end text-right space-y-1 text-sm border-t pt-4">
                            <div className="w-48">
                                <div className="flex justify-between"><span>Tạm tính:</span> <span>{new Intl.NumberFormat().format(selectedOrder.subtotal)}đ</span></div>
                                <div className="flex justify-between"><span>Phí ship:</span> <span>{new Intl.NumberFormat().format(selectedOrder.shipping_fee)}đ</span></div>
                                <div className="flex justify-between text-green-600"><span>Giảm giá:</span> <span>-{new Intl.NumberFormat().format(selectedOrder.discount_amount)}đ</span></div>
                                <div className="flex justify-between font-bold text-lg text-stone-900 mt-2 pt-2 border-t">
                                    <span>Tổng cộng:</span> 
                                    <span>{new Intl.NumberFormat().format(selectedOrder.total_amount)}đ</span>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>

                {/* Footer: Các nút hành động */}
                <div className="p-6 bg-stone-50 border-t flex flex-wrap justify-end gap-3">
                    {selectedOrder.status === 'pending' && (
                        <>
                            <button disabled={processing} onClick={() => handleUpdateStatus('cancelled', true)} className="px-4 py-2 border border-red-200 text-red-600 rounded hover:bg-red-50 flex items-center gap-2">
                                <FaTimesCircle/> Hủy đơn (Hoàn kho)
                            </button>
                            <button disabled={processing} onClick={() => handleUpdateStatus('shipping')} className="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 flex items-center gap-2">
                                <FaShippingFast/> Giao hàng
                            </button>
                        </>
                    )}

                    {selectedOrder.status === 'shipping' && (
                        <button disabled={processing} onClick={() => handleUpdateStatus('completed')} className="px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700 flex items-center gap-2">
                            <FaCheckCircle/> Hoàn tất đơn hàng
                        </button>
                    )}
                    
                    {/* Logic Hoàn Trả phức tạp */}
                    {selectedOrder.status === 'completed' && (
                        <div className="flex gap-2 items-center">
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
>>>>>>> Stashed changes
    </div>
  );
};

export default Orders;