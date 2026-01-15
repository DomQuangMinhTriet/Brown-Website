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

  useEffect(() => {
    fetchOrders();
  }, []);

  const fetchOrders = async () => {
    setLoading(true);
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
    </div>
  );
};

export default Orders;