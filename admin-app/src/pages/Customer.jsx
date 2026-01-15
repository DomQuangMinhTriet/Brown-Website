<<<<<<< Updated upstream
import { useEffect, useState } from 'react';
import axios from 'axios';
import { FaUser, FaPhone, FaMapMarkerAlt, FaHistory } from 'react-icons/fa';
=======
import { useState, useEffect } from 'react';
import axios from 'axios';
import { FaUser, FaSearch, FaHistory, FaTimes } from 'react-icons/fa';
>>>>>>> Stashed changes

const Customers = () => {
  const [customers, setCustomers] = useState([]);
  const [loading, setLoading] = useState(true);
<<<<<<< Updated upstream

  useEffect(() => {
    const fetchCustomers = async () => {
      try {
        const res = await axios.get('http://localhost:5000/api/customers');
        if (res.data.success) setCustomers(res.data.data);
      } catch (error) {
        console.error(error);
      } finally {
        setLoading(false);
      }
    };
    fetchCustomers();
  }, []);

  return (
    <div className="p-6 md:p-10 max-w-7xl mx-auto">
      <h1 className="text-2xl font-bold text-stone-800 mb-6">Danh sách Khách hàng (CRM)</h1>
      
      <div className="bg-white rounded-xl border border-stone-200 shadow-sm overflow-hidden">
        <table className="w-full text-left">
          <thead className="bg-stone-50 text-stone-500 uppercase text-xs">
            <tr>
              <th className="p-4">Khách hàng</th>
              <th className="p-4">Liên hệ</th>
              <th className="p-4">Địa chỉ</th>
              <th className="p-4 text-center">Ngày tham gia</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-stone-100 text-sm">
            {customers.map(cus => (
              <tr key={cus.id} className="hover:bg-stone-50">
                <td className="p-4 font-medium text-stone-800 flex items-center gap-3">
                  <div className="w-8 h-8 rounded-full bg-stone-200 flex items-center justify-center text-stone-500">
                    <FaUser size={12}/>
                  </div>
                  {cus.full_name}
                </td>
                <td className="p-4 text-stone-600">
                  <div className="flex items-center gap-2"><FaPhone size={10}/> {cus.phone}</div>
                  <div className="text-xs text-stone-400 mt-1">{cus.email}</div>
                </td>
                <td className="p-4 text-stone-500 truncate max-w-xs">{cus.address}</td>
                <td className="p-4 text-center text-stone-400">
                  {new Date(cus.created_at).toLocaleDateString('vi-VN')}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {customers.length === 0 && !loading && (
            <div className="p-8 text-center text-stone-400">Chưa có dữ liệu khách hàng</div>
        )}
      </div>
=======
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
      const res = await axios.get('http://localhost:5000/api/customers');
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
      const res = await axios.get(`http://localhost:5000/api/customers/${customer.id}/history`);
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
    <div className="p-8">
      <h1 className="text-2xl font-bold text-stone-800 mb-6 flex items-center gap-2">
        <FaUser /> Quản lý Khách hàng (CRM)
      </h1>

      {/* Thanh Tìm kiếm */}
      <div className="bg-white p-4 rounded-lg shadow-sm mb-6 flex gap-4 border border-stone-200">
        <div className="flex-1 relative">
            <FaSearch className="absolute left-3 top-3 text-stone-400"/>
            <input 
                type="text" 
                placeholder="Tìm tên, email, số điện thoại..." 
                className="w-full pl-10 p-2 border rounded outline-none focus:border-stone-800"
                value={searchTerm}
                onChange={e => setSearchTerm(e.target.value)}
            />
        </div>
        <div className="bg-stone-100 px-4 py-2 rounded text-stone-600 font-bold flex items-center">
            {filteredCustomers.length} Khách
        </div>
      </div>

      {/* Bảng Danh sách */}
      <div className="bg-white rounded-xl shadow border border-stone-200 overflow-hidden">
        <table className="w-full text-left">
          <thead className="bg-stone-50 border-b border-stone-200">
            <tr>
              <th className="p-4">Họ tên</th>
              <th className="p-4">Liên hệ</th>
              <th className="p-4 text-center">Số đơn</th>
              <th className="p-4 text-right">Tổng chi (LTV)</th>
              <th className="p-4">Mua gần nhất</th>
              <th className="p-4"></th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
                <tr><td colSpan="6" className="p-8 text-center text-stone-500">Đang tải...</td></tr>
            ) : filteredCustomers.length === 0 ? (
                <tr><td colSpan="6" className="p-8 text-center text-stone-500">Không tìm thấy khách hàng.</td></tr>
            ) : (
                filteredCustomers.map(cus => (
                <tr key={cus.id} className="border-b border-stone-100 hover:bg-stone-50 transition-colors">
                    <td className="p-4 font-bold text-stone-800">{cus.full_name}</td>
                    <td className="p-4 text-sm">
                        <div className="font-mono">{cus.phone}</div>
                        <div className="text-stone-500 text-xs">{cus.email}</div>
                    </td>
                    <td className="p-4 text-center">
                        <span className="bg-blue-50 text-blue-700 px-2 py-1 rounded text-xs font-bold border border-blue-100">
                            {cus.order_count}
                        </span>
                    </td>
                    <td className="p-4 text-right font-bold text-green-700">
                        {new Intl.NumberFormat('vi-VN').format(cus.total_spent)}đ
                    </td>
                    <td className="p-4 text-sm text-stone-500">
                        {cus.last_order_date ? new Date(cus.last_order_date).toLocaleDateString('vi-VN') : '-'}
                    </td>
                    <td className="p-4 text-right">
                        <button 
                            onClick={() => handleViewHistory(cus)}
                            className="text-stone-400 hover:text-stone-900 p-2 rounded hover:bg-stone-200 transition-all tooltip"
                            title="Xem lịch sử mua hàng"
                        >
                            <FaHistory />
                        </button>
                    </td>
                </tr>
                ))
            )}
          </tbody>
        </table>
      </div>

      {/* Modal Lịch sử */}
      {showModal && selectedCustomer && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
            <div className="bg-white rounded-xl w-full max-w-2xl max-h-[80vh] overflow-hidden flex flex-col shadow-2xl">
                <div className="p-4 border-b flex justify-between items-center bg-stone-50">
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
                                <div key={order.id} className="bg-white border border-stone-200 rounded-lg p-4 flex justify-between items-center shadow-sm">
                                    <div>
                                        <div className="flex items-center gap-2">
                                            <span className="font-bold text-stone-800 text-sm">{order.code}</span>
                                            <span className={`text-[10px] px-2 py-0.5 rounded uppercase font-bold
                                                ${order.status === 'completed' ? 'bg-green-100 text-green-700' : 
                                                  order.status === 'cancelled' ? 'bg-red-100 text-red-700' : 
                                                  'bg-yellow-100 text-yellow-700'}`}>
                                                {order.status}
                                            </span>
                                        </div>
                                        <p className="text-xs text-stone-400 mt-1">
                                            {new Date(order.created_at).toLocaleString('vi-VN')}
                                        </p>
                                    </div>
                                    <div className="text-right">
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
>>>>>>> Stashed changes
    </div>
  );
};

export default Customers;