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
    } finally {
      setLoading(false);
    }
  };

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
    </div>
  );
};

export default Orders;