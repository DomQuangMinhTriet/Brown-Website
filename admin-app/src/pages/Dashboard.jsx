<<<<<<< Updated upstream
import { FaArrowUp, FaArrowDown, FaShoppingBag, FaMoneyBillWave, FaExclamationTriangle } from 'react-icons/fa';

// Component Thẻ thống kê (Giữ nguyên nhưng tinh chỉnh nhẹ)
const DashboardCard = ({ title, value, icon, trend, trendValue, color }) => (
=======
import { useEffect, useState } from 'react';
import axios from 'axios';
import { FaArrowUp, FaShoppingBag, FaMoneyBillWave, FaUsers, FaClock } from 'react-icons/fa';
import { Link } from 'react-router-dom';

// Component Card nhỏ
const DashboardCard = ({ title, value, icon, color, subtext }) => (
>>>>>>> Stashed changes
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
<<<<<<< Updated upstream
    <div className="flex items-center gap-2 text-sm">
      {trend === 'up' ? (
        <span className="text-green-600 flex items-center gap-1 font-medium bg-green-50 px-2 py-0.5 rounded">
          <FaArrowUp size={10} /> {trendValue}
        </span>
      ) : (
        <span className="text-red-600 flex items-center gap-1 font-medium bg-red-50 px-2 py-0.5 rounded">
          <FaArrowDown size={10} /> {trendValue}
        </span>
      )}
      <span className="text-stone-400">so với hôm qua</span>
=======
    <div className="text-sm text-stone-500">
       {subtext}
>>>>>>> Stashed changes
    </div>
  </div>
);

<<<<<<< Updated upstream
// Component Bảng đơn hàng mới (Để lấp khoảng trống bên dưới)
const RecentOrders = () => {
  const orders = [
    { id: '#ORD-001', customer: 'Nguyễn Văn A', product: 'Đầm Lụa (S)', total: '500,000 ₫', status: 'Mới', date: '10:30 AM' },
    { id: '#ORD-002', customer: 'Trần Thị B', product: 'Áo Croptop (M)', total: '320,000 ₫', status: 'Đóng gói', date: '09:15 AM' },
    { id: '#ORD-003', customer: 'Lê C', product: 'Quần Jeans (L)', total: '450,000 ₫', status: 'Vận chuyển', date: 'Yesterday' },
    { id: '#ORD-004', customer: 'Phạm D', product: 'Set Blazer', total: '1,200,000 ₫', status: 'Hoàn thành', date: 'Yesterday' },
  ];

  return (
    <div className="bg-white rounded-xl border border-stone-100 shadow-sm overflow-hidden">
      <div className="p-6 border-b border-stone-100 flex justify-between items-center">
        <h3 className="font-bold text-stone-800">Đơn hàng gần đây</h3>
        <button className="text-sm text-stone-500 hover:text-stone-800">Xem tất cả</button>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-left border-collapse">
          <thead>
            <tr className="bg-stone-50 text-stone-500 text-xs uppercase tracking-wider">
              <th className="p-4 font-medium">Mã đơn</th>
              <th className="p-4 font-medium">Khách hàng</th>
              <th className="p-4 font-medium">Sản phẩm</th>
              <th className="p-4 font-medium">Tổng tiền</th>
              <th className="p-4 font-medium">Trạng thái</th>
            </tr>
          </thead>
          <tbody className="text-sm text-stone-700">
            {orders.map((order, index) => (
              <tr key={index} className="border-b border-stone-50 last:border-0 hover:bg-stone-50/50 transition-colors">
                <td className="p-4 font-medium text-stone-900">{order.id}</td>
                <td className="p-4">{order.customer}</td>
                <td className="p-4 text-stone-600">{order.product}</td>
                <td className="p-4 font-medium">{order.total}</td>
                <td className="p-4">
                  <span className={`px-2 py-1 rounded text-xs font-medium 
                    ${order.status === 'Mới' ? 'bg-blue-50 text-blue-600' : 
                      order.status === 'Hoàn thành' ? 'bg-green-50 text-green-600' : 'bg-stone-100 text-stone-600'}`}>
                    {order.status}
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
};

const Dashboard = () => {
  return (
    <div className="p-6 md:p-10 max-w-7xl mx-auto space-y-8">
      {/* Phần Header chào mừng */}
      <div>
        <h1 className="text-2xl font-bold text-stone-800">Tổng quan</h1>
        <p className="text-stone-500">Chào mừng trở lại, đây là tình hình kinh doanh hôm nay.</p>
      </div>

      {/* Grid thống kê: Trên màn hình lớn chia làm 3 cột */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <DashboardCard 
          title="Doanh thu" 
          value="4,500,000 ₫" 
          icon={<FaMoneyBillWave className="text-emerald-600" />} 
          trend="up" 
          trendValue="12%" 
          color="bg-emerald-50"
        />
        <DashboardCard 
          title="Đơn hàng" 
          value="18" 
          icon={<FaShoppingBag className="text-blue-600" />} 
          trend="up" 
          trendValue="5%" 
          color="bg-blue-50"
        />
        <DashboardCard 
          title="Cảnh báo tồn kho" 
          value="3" 
          icon={<FaExclamationTriangle className="text-amber-600" />} 
          trend="down" 
          trendValue="2 sp" 
          color="bg-amber-50"
        />
      </div>

      {/* Layout chia cột 2:1 (Bảng đơn hàng lớn bên trái, Thống kê nhỏ bên phải) */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* Cột chính: Chiếm 2 phần */}
        <div className="lg:col-span-2">
          <RecentOrders />
        </div>

        {/* Cột phụ: Chiếm 1 phần - Placeholder cho Biểu đồ hoặc Top sản phẩm */}
        <div className="bg-white p-6 rounded-xl border border-stone-100 shadow-sm h-full">
          <h3 className="font-bold text-stone-800 mb-4">Top Sản phẩm</h3>
          <div className="space-y-4">
            {[1, 2, 3].map((i) => (
              <div key={i} className="flex items-center gap-4 p-3 hover:bg-stone-50 rounded-lg transition-colors cursor-pointer">
                <div className="w-12 h-12 bg-stone-200 rounded-md"></div> {/* Placeholder ảnh */}
                <div className="flex-1">
                  <p className="text-sm font-medium text-stone-800">Đầm Body Basic</p>
                  <p className="text-xs text-stone-500">Đã bán: 120</p>
                </div>
                <span className="text-sm font-bold text-stone-800">#1</span>
              </div>
            ))}
          </div>
          <button className="w-full mt-6 py-2 text-sm text-stone-500 border border-stone-200 rounded-lg hover:bg-stone-50">
            Xem báo cáo chi tiết
          </button>
=======
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
>>>>>>> Stashed changes
        </div>
      </div>
    </div>
  );
};

export default Dashboard;