import { useEffect, useState } from 'react';
import axios from 'axios';
import { FaBoxOpen, FaCalendarAlt, FaChevronDown, FaChevronUp, FaMapMarkerAlt, FaPhone, FaSearch, FaUser } from 'react-icons/fa';

const Orders = () => {
  const [orders, setOrders] = useState([]);
  const [loading, setLoading] = useState(true);
  const [expandedOrderId, setExpandedOrderId] = useState(null); // Để mở rộng chi tiết đơn hàng
  const [statusFilter, setStatusFilter] = useState('all');

  useEffect(() => {
    fetchOrders();
  }, []);

  const fetchOrders = async () => {
    try {
      const res = await axios.get('http://localhost:5000/api/orders');
      if (res.data.success) {
        setOrders(res.data.data);
      }
    } catch (error) {
      console.error("Lỗi tải đơn hàng:", error);
    } finally {
      setLoading(false);
    }
  };

  const handleStatusChange = async (orderId, newStatus) => {
    if(!confirm(`Bạn có chắc muốn chuyển trạng thái sang "${newStatus}"?`)) return;

    try {
      const res = await axios.put(`http://localhost:5000/api/orders/${orderId}/status`, { status: newStatus });
      if (res.data.success) {
        // Cập nhật lại UI ngay lập tức
        setOrders(orders.map(o => o.id === orderId ? { ...o, status: newStatus } : o));
        alert("Cập nhật thành công!");
      }
    } catch (error) {
      alert("Lỗi cập nhật: " + error.message);
    }
  };

  // Helper: Màu sắc cho trạng thái
  const getStatusBadge = (status) => {
    const styles = {
      pending: 'bg-yellow-100 text-yellow-700 border-yellow-200',
      confirmed: 'bg-blue-100 text-blue-700 border-blue-200',
      shipping: 'bg-purple-100 text-purple-700 border-purple-200',
      completed: 'bg-green-100 text-green-700 border-green-200',
      cancelled: 'bg-red-100 text-red-700 border-red-200',
    };
    return styles[status] || 'bg-gray-100 text-gray-700';
  };

  // Filter đơn hàng
  const filteredOrders = statusFilter === 'all' 
    ? orders 
    : orders.filter(o => o.status === statusFilter);

  const toggleExpand = (id) => {
    setExpandedOrderId(expandedOrderId === id ? null : id);
  };

  return (
    <div className="p-6 md:p-10 max-w-7xl mx-auto min-h-screen">
      <div className="flex flex-col md:flex-row justify-between items-start md:items-center mb-8 gap-4">
        <div>
          <h1 className="text-2xl font-bold text-stone-800">Quản lý Đơn hàng</h1>
          <p className="text-stone-500">Xem và xử lý các đơn hàng mới</p>
        </div>
        
        {/* Bộ lọc trạng thái */}
        <select 
          className="p-2 border border-stone-300 rounded-lg bg-white"
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
        >
          <option value="all">Tất cả trạng thái</option>
          <option value="pending">Chờ xử lý (Pending)</option>
          <option value="confirmed">Đã xác nhận</option>
          <option value="shipping">Đang giao hàng</option>
          <option value="completed">Hoàn thành</option>
          <option value="cancelled">Đã hủy</option>
        </select>
      </div>

      <div className="bg-white rounded-xl border border-stone-200 shadow-sm overflow-hidden">
        {loading ? (
           <div className="p-10 text-center text-stone-400">Đang tải dữ liệu...</div>
        ) : (
           <div className="overflow-x-auto">
             <table className="w-full text-left border-collapse">
               <thead className="bg-stone-100 text-stone-600 uppercase text-xs">
                 <tr>
                   <th className="p-4">Mã Đơn</th>
                   <th className="p-4">Khách hàng</th>
                   <th className="p-4">Ngày đặt</th>
                   <th className="p-4">Tổng tiền</th>
                   <th className="p-4">Trạng thái</th>
                   <th className="p-4 text-center">Hành động</th>
                 </tr>
               </thead>
               <tbody className="divide-y divide-stone-100 text-sm">
                 {filteredOrders.length === 0 && (
                    <tr><td colSpan="6" className="p-8 text-center text-stone-400">Không tìm thấy đơn hàng nào.</td></tr>
                 )}
                 
                 {filteredOrders.map((order) => (
                   <>
                     {/* DÒNG CHÍNH: THÔNG TIN CƠ BẢN */}
                     <tr key={order.id} className="hover:bg-stone-50 transition-colors">
                       <td className="p-4 font-mono font-bold text-blue-600 cursor-pointer" onClick={() => toggleExpand(order.id)}>
                          {order.code}
                       </td>
                       <td className="p-4">
                          <div className="font-medium">{order.customer_name}</div>
                          <div className="text-xs text-stone-500">{order.customer_phone}</div>
                       </td>
                       <td className="p-4 text-stone-500">
                          {new Date(order.created_at).toLocaleString('vi-VN')}
                       </td>
                       <td className="p-4 font-bold">
                          {new Intl.NumberFormat('vi-VN').format(order.total_amount)} ₫
                       </td>
                       <td className="p-4">
                          <span className={`px-3 py-1 rounded-full text-xs font-bold border ${getStatusBadge(order.status)}`}>
                            {order.status.toUpperCase()}
                          </span>
                       </td>
                       <td className="p-4 text-center">
                          {/* Dropdown đổi trạng thái nhanh */}
                          <select 
                            className="text-xs border p-1 rounded bg-white cursor-pointer hover:border-stone-400"
                            value={order.status}
                            onChange={(e) => handleStatusChange(order.id, e.target.value)}
                          >
                             <option value="pending">Pending</option>
                             <option value="confirmed">Xác nhận</option>
                             <option value="shipping">Giao hàng</option>
                             <option value="completed">Hoàn thành</option>
                             <option value="cancelled">Hủy đơn</option>
                          </select>
                          
                          <button 
                            onClick={() => toggleExpand(order.id)}
                            className="ml-3 text-stone-400 hover:text-stone-800"
                          >
                             {expandedOrderId === order.id ? <FaChevronUp/> : <FaChevronDown/>}
                          </button>
                       </td>
                     </tr>

                     {/* DÒNG PHỤ: CHI TIẾT SẢN PHẨM (Xổ xuống khi click) */}
                     {expandedOrderId === order.id && (
                       <tr className="bg-stone-50">
                         <td colSpan="6" className="p-4 md:p-6 border-b border-stone-200 shadow-inner">
                            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                                {/* Thông tin giao hàng */}
                                <div>
                                    <h4 className="font-bold text-stone-800 mb-3 text-xs uppercase flex items-center gap-2">
                                        <FaMapMarkerAlt/> Thông tin giao hàng
                                    </h4>
                                    <p className="text-sm text-stone-600 mb-1"><b>Người nhận:</b> {order.customer_name}</p>
                                    <p className="text-sm text-stone-600 mb-1"><b>SĐT:</b> {order.customer_phone}</p>
                                    <p className="text-sm text-stone-600 mb-1"><b>Địa chỉ:</b> {order.customer_address}</p>
                                    <p className="text-sm text-stone-600 italic"><b>Ghi chú:</b> {order.note || 'Không có'}</p>
                                </div>

                                {/* Danh sách sản phẩm */}
                                <div>
                                    <h4 className="font-bold text-stone-800 mb-3 text-xs uppercase flex items-center gap-2">
                                        <FaBoxOpen/> Sản phẩm đã mua
                                    </h4>
                                    <div className="bg-white rounded border border-stone-200 overflow-hidden">
                                        {order.order_items.map((item, idx) => (
                                            <div key={idx} className="flex gap-3 p-3 border-b border-stone-100 last:border-0">
                                                <div className="w-12 h-16 bg-stone-100 flex-shrink-0">
                                                    {item.variants?.products?.images?.[0] && (
                                                        <img src={item.variants.products.images[0]} className="w-full h-full object-cover"/>
                                                    )}
                                                </div>
                                                <div className="flex-1">
                                                    <div className="font-medium text-sm text-stone-800">{item.variants?.products?.name}</div>
                                                    <div className="text-xs text-stone-500">
                                                        Phân loại: {item.variants?.color} / {item.variants?.size}
                                                    </div>
                                                    <div className="flex justify-between mt-1 text-sm">
                                                        <span>x{item.quantity}</span>
                                                        <span className="font-bold">{new Intl.NumberFormat('vi-VN').format(item.unit_price)} ₫</span>
                                                    </div>
                                                </div>
                                            </div>
                                        ))}
                                    </div>
                                    <div className="flex justify-between items-center mt-3 pt-3 border-t border-stone-200">
                                        <span className="text-sm font-bold">Thành tiền:</span>
                                        <span className="text-lg font-bold text-stone-900">{new Intl.NumberFormat('vi-VN').format(order.total_amount)} ₫</span>
                                    </div>
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
    </div>
  );
};

export default Orders;