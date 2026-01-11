import { useEffect, useState } from 'react';
import axios from 'axios';
import { FaArrowUp, FaShoppingBag, FaMoneyBillWave, FaUsers, FaClock } from 'react-icons/fa';
import { Link } from 'react-router-dom';

// Component Card nhỏ
const DashboardCard = ({ title, value, icon, color, subtext }) => (
  <div className="bg-white p-6 rounded-xl border border-stone-100 shadow-sm hover:shadow-md transition-shadow">
    <div className="flex items-start justify-between mb-4">
      <div>
        <p className="text-stone-500 text-xs font-bold uppercase tracking-wider mb-1">{title}</p>
        <h3 className="text-2xl font-bold text-stone-800">{value}</h3>
      </div>
      <div className={`p-3 rounded-full ${color}`}>
        {icon}
      </div>
    </div>
    <div className="text-sm text-stone-500">
       {subtext}
    </div>
  </div>
);

const Dashboard = () => {
  const [stats, setStats] = useState({
    revenue: 0,
    orders: 0,
    customers: 0,
    recentOrders: []
  });
  const [loading, setLoading] = useState(true);

  // Gọi API lấy số liệu thật
  useEffect(() => {
    const fetchStats = async () => {
      try {
        const res = await axios.get('http://localhost:5000/api/reports/dashboard');
        if (res.data.success) {
          setStats(res.data.data);
        }
      } catch (error) {
        console.error("Lỗi tải báo cáo:", error);
      } finally {
        setLoading(false);
      }
    };
    fetchStats();
  }, []);

  // Helper format tiền tệ
  const formatMoney = (amount) => new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(amount);
  
  // Helper màu trạng thái
  const getStatusColor = (status) => {
    const colors = {
      pending: 'text-yellow-600 bg-yellow-50 border-yellow-200',
      confirmed: 'text-blue-600 bg-blue-50 border-blue-200',
      completed: 'text-green-600 bg-green-50 border-green-200',
      cancelled: 'text-red-600 bg-red-50 border-red-200'
    };
    return colors[status] || 'text-gray-600 bg-gray-50';
  };

  if (loading) return <div className="p-10 text-center text-stone-400">Đang tổng hợp số liệu...</div>;

  return (
    <div className="p-6 md:p-10 max-w-7xl mx-auto">
      <div className="mb-8">
        <h1 className="text-2xl font-bold text-stone-800">Tổng quan kinh doanh</h1>
        <p className="text-stone-500">Cập nhật lúc: {new Date().toLocaleString('vi-VN')}</p>
      </div>

      {/* 1. CÁC THẺ THỐNG KÊ (DỮ LIỆU THẬT) */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
        <DashboardCard 
          title="Tổng Doanh Thu" 
          value={formatMoney(stats.revenue)} 
          icon={<FaMoneyBillWave className="text-green-600 text-xl" />} 
          color="bg-green-50"
          subtext="Doanh thu thực tế (trừ đơn hủy)"
        />
        <DashboardCard 
          title="Tổng Đơn Hàng" 
          value={stats.orders} 
          icon={<FaShoppingBag className="text-blue-600 text-xl" />} 
          color="bg-blue-50"
          subtext="Đơn hàng trên toàn hệ thống"
        />
        <DashboardCard 
          title="Khách Hàng" 
          value={stats.customers} 
          icon={<FaUsers className="text-purple-600 text-xl" />} 
          color="bg-purple-50"
          subtext="Khách hàng đã lưu hồ sơ"
        />
      </div>

      {/* 2. BẢNG ĐƠN HÀNG GẦN ĐÂY */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <div className="lg:col-span-2 bg-white p-6 rounded-xl border border-stone-200 shadow-sm">
          <div className="flex justify-between items-center mb-6">
            <h3 className="font-bold text-stone-800 flex items-center gap-2"><FaClock/> Đơn hàng vừa đặt</h3>
            <Link to="/orders" className="text-sm text-blue-600 hover:underline">Xem tất cả</Link>
          </div>

          <div className="overflow-x-auto">
            <table className="w-full text-left">
              <thead className="text-xs text-stone-500 uppercase bg-stone-50">
                <tr>
                  <th className="p-3 rounded-l">Mã đơn</th>
                  <th className="p-3">Khách hàng</th>
                  <th className="p-3">Tổng tiền</th>
                  <th className="p-3 rounded-r">Trạng thái</th>
                </tr>
              </thead>
              <tbody className="text-sm">
                {stats.recentOrders.length === 0 ? (
                    <tr><td colSpan="4" className="p-4 text-center text-stone-400">Chưa có đơn hàng nào</td></tr>
                ) : (
                    stats.recentOrders.map(order => (
                    <tr key={order.id} className="border-b border-stone-100 last:border-0 hover:bg-stone-50">
                        <td className="p-3 font-mono font-medium text-stone-700">{order.code}</td>
                        <td className="p-3">{order.customer_name}</td>
                        <td className="p-3 font-bold">{formatMoney(order.total_amount)}</td>
                        <td className="p-3">
                        <span className={`px-2 py-1 rounded text-xs font-bold border ${getStatusColor(order.status)}`}>
                            {order.status}
                        </span>
                        </td>
                    </tr>
                    ))
                )}
              </tbody>
            </table>
          </div>
        </div>

        {/* CỘT PHỤ (Placeholder cho Top Product - Có thể phát triển sau) */}
        <div className="bg-stone-900 text-white p-6 rounded-xl shadow-lg flex flex-col justify-center items-center text-center">
            <h3 className="text-xl font-serif mb-2">BROWN FASHION</h3>
            <p className="text-stone-400 text-sm mb-6">Hệ thống quản lý vận hành</p>
            <div className="w-full bg-stone-800 p-4 rounded-lg mb-2">
                <p className="text-xs text-stone-400 uppercase tracking-widest mb-1">Target tháng này</p>
                <p className="text-2xl font-bold">100.000.000 ₫</p>
            </div>
            <p className="text-xs text-stone-500">Tiếp tục cố gắng nhé!</p>
        </div>
      </div>
    </div>
  );
};

export default Dashboard;