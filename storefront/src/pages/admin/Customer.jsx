import { useState, useEffect } from 'react';
import axios from 'axios';
import { FaUser, FaSearch, FaHistory, FaTimes } from 'react-icons/fa';
import { ORDER_STATUS_MAP } from '../../utils/translations';

const Customers = () => {
  const [customers, setCustomers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');

  // State cho Modal Lịch sử
  const [selectedCustomer, setSelectedCustomer] = useState(null);
  const [history, setHistory] = useState([]);
  const [showModal, setShowModal] = useState(false);

  useEffect(() => {
    fetchCustomers();
  }, []);

  const fetchCustomers = async () => {
    try {
      const res = await axios.get(`${import.meta.env.VITE_API_URL}/api/customers`);
      if (res.data.success) {
        setCustomers(res.data.data);
      }
    } catch (error) {
      console.error("Lỗi tải khách hàng:", error);
    } finally {
      setLoading(false);
    }
  };

  const handleViewHistory = async (customer) => {
    setSelectedCustomer(customer);
    try {
      const res = await axios.get(`${import.meta.env.VITE_API_URL}/api/customers/${customer.id}/history`);
      setHistory(res.data.data);
      setShowModal(true);
    } catch (error) {
      alert("Không tải được lịch sử");
    }
  };

  // Logic tìm kiếm
  const filteredCustomers = customers.filter(c => 
    c.full_name?.toLowerCase().includes(searchTerm.toLowerCase()) || 
    c.phone?.includes(searchTerm) ||
    c.email?.toLowerCase().includes(searchTerm.toLowerCase())
  );

  return (
    <div className="p-4 md:p-8">
      {/* HEADER: RESPONSIVE FLEX */}
      <div className="flex flex-col md:flex-row justify-between items-start md:items-center mb-6 gap-4">
          <h1 className="text-xl md:text-2xl font-bold text-stone-800 flex items-center gap-2">
            <FaUser /> Quản lý Khách hàng (CRM)
          </h1>

          {/* Thanh Tìm kiếm: Full width trên mobile */}
          <div className="bg-white p-2 rounded-lg shadow-sm border border-stone-200 flex w-full md:w-auto items-center">
            <div className="relative flex-1 md:w-64">
                <FaSearch className="absolute left-3 top-3 text-stone-400"/>
                <input 
                    type="text" 
                    placeholder="Tìm tên, email, SĐT..." 
                    className="w-full pl-10 p-2 border-none outline-none text-sm"
                    value={searchTerm}
                    onChange={e => setSearchTerm(e.target.value)}
                />
            </div>
            <div className="bg-stone-100 px-3 py-1 rounded text-stone-600 font-bold text-xs ml-2 whitespace-nowrap">
                {filteredCustomers.length} Khách
            </div>
          </div>
      </div>

      {/* Bảng Danh sách Khách hàng: WRAPPER OVERFLOW-X-AUTO */}
      <div className="bg-white rounded-xl shadow border border-stone-200 overflow-hidden">
        <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse min-w-[800px]">
              <thead className="bg-stone-50 border-b border-stone-200 text-stone-600 text-xs uppercase font-bold tracking-wider">
                <tr>
                  <th className="p-4">Khách hàng</th>
                  <th className="p-4">Liên hệ</th>
                  <th className="p-4 text-center">Đơn hàng</th>
                  <th className="p-4 text-right">Tổng chi tiêu</th>
                  <th className="p-4">Giao dịch cuối</th>
                  <th className="p-4 text-center">Thao tác</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-stone-100 text-sm">
                {loading ? (
                    <tr><td colSpan="6" className="p-8 text-center text-stone-500 italic">Đang tải dữ liệu khách hàng...</td></tr>
                ) : filteredCustomers.length === 0 ? (
                    <tr><td colSpan="6" className="p-8 text-center text-stone-500 italic">Không tìm thấy khách hàng nào.</td></tr>
                ) : (
                    filteredCustomers.map(cus => (
                    <tr key={cus.id} className="hover:bg-stone-50 transition-colors group">
                        {/* 1. Tên Khách */}
                        <td className="p-4">
                            <div className="font-bold text-stone-800">{cus.full_name || "Khách vãng lai"}</div>
                            <div className="text-xs text-stone-400">ID: {cus.id}</div>
                        </td>

                        {/* 2. Liên hệ */}
                        <td className="p-4">
                            <div className="text-sm font-medium text-stone-700">{cus.phone}</div>
                            <div className="text-xs text-stone-500">{cus.email || "---"}</div>
                            <div className="text-xs text-stone-400 truncate max-w-[150px]" title={cus.address}>{cus.address}</div>
                        </td>

                        {/* 3. Số lượng đơn */}
                        <td className="p-4 text-center">
                            <span className={`inline-block px-3 py-1 rounded-full text-xs font-bold 
                                ${cus.order_count > 0 ? 'bg-blue-100 text-blue-700' : 'bg-stone-100 text-stone-400'}`}>
                                {cus.order_count} đơn
                            </span>
                        </td>

                        {/* 4. Tổng chi tiêu */}
                        <td className="p-4 text-right">
                            <span className="font-bold text-stone-900 block">
                                {new Intl.NumberFormat('vi-VN').format(cus.total_spent)} ₫
                            </span>
                            <span className="text-[10px] text-stone-400 uppercase">
                                {cus.total_spent > 5000000 ? 'VIP Member' : 'Member'}
                            </span>
                        </td>

                        {/* 5. Ngày mua gần nhất */}
                        <td className="p-4 text-sm text-stone-600">
                            {cus.last_order_date 
                                ? new Date(cus.last_order_date).toLocaleDateString('vi-VN') 
                                : <span className="text-stone-300 italic">Chưa mua</span>}
                        </td>

                        {/* 6. Nút xem lịch sử */}
                        <td className="p-4 text-center">
                            <button 
                                onClick={() => handleViewHistory(cus)}
                                className="p-2 rounded-full text-stone-400 hover:text-stone-900 hover:bg-stone-200 transition-all"
                                title="Xem lịch sử đơn hàng"
                            >
                                <FaHistory size={16} />
                            </button>
                        </td>
                    </tr>
                    ))
                )}
              </tbody>
            </table>
        </div>
      </div>

      {/* Modal Lịch sử: RESPONSIVE SIZE */}
      {showModal && selectedCustomer && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
            <div className="bg-white rounded-xl w-full max-w-2xl max-h-[85vh] overflow-hidden flex flex-col shadow-2xl">
                <div className="p-4 border-b flex justify-between items-center bg-stone-50 shrink-0">
                    <div>
                        <h3 className="font-bold text-lg text-stone-800">Lịch sử đơn hàng</h3>
                        <p className="text-xs text-stone-500">{selectedCustomer.full_name} - {selectedCustomer.phone}</p>
                    </div>
                    <button onClick={() => setShowModal(false)} className="text-stone-400 hover:text-red-500 p-2"><FaTimes/></button>
                </div>
                
                <div className="p-4 overflow-y-auto flex-1 bg-stone-50/50">
                    {history.length === 0 ? (
                        <div className="text-center py-10 text-stone-400">Chưa có đơn hàng nào.</div>
                    ) : (
                        <div className="space-y-3">
                            {history.map(order => (
                                <div key={order.id} className="bg-white border border-stone-200 rounded-lg p-4 flex flex-col sm:flex-row justify-between items-start sm:items-center shadow-sm gap-2">
                                    <div>
                                        <div className="flex items-center gap-2">
                                            <span className="font-bold text-stone-800 text-sm">{order.code}</span>
                                            <span className={`text-[10px] px-2 py-0.5 rounded uppercase font-bold
                                                ${order.status === 'completed' ? 'bg-green-100 text-green-700' : 
                                                  order.status === 'cancelled' ? 'bg-red-100 text-red-700' : 
                                                  'bg-yellow-100 text-yellow-700'}`}>
                                                {ORDER_STATUS_MAP[order.status]?.label || order.status}
                                            </span>
                                        </div>
                                        <p className="text-xs text-stone-400 mt-1">
                                            {new Date(order.created_at).toLocaleString('vi-VN')}
                                        </p>
                                    </div>
                                    <div className="text-left sm:text-right w-full sm:w-auto border-t sm:border-t-0 pt-2 sm:pt-0 mt-2 sm:mt-0">
                                        <p className="font-bold text-stone-900">{new Intl.NumberFormat('vi-VN').format(order.total_amount)}đ</p>
                                        <p className="text-xs text-stone-500 uppercase">{order.payment_method}</p>
                                    </div>
                                </div>
                            ))}
                        </div>
                    )}
                </div>
            </div>
        </div>
      )}
    </div>
  );
};

export default Customers;