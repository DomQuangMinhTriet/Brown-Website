import { Link, useLocation } from 'react-router-dom';
import { 
  FaHome, 
  FaBoxOpen, 
  FaClipboardList, 
  FaWarehouse, 
  FaChartBar, 
  FaMoneyBillAlt, 
  FaSignOutAlt, 
  FaImage, 
  FaUsers,
  FaPlusCircle,
  FaTags // <--- Icon cho Khuyến mãi
} from 'react-icons/fa';
import { useAdminAuth } from '../context/AdminAuthContext';

const Sidebar = () => {
  const location = useLocation();
  const { logout } = useAdminAuth();

  const menuItems = [
    { path: '/admin', icon: <FaHome />, label: 'Tổng quan' },
    { path: '/admin/products', icon: <FaBoxOpen />, label: 'Sản phẩm' },
    { path: '/admin/orders', icon: <FaClipboardList />, label: 'Đơn hàng' },
    { path: '/admin/orders/create', icon: <FaPlusCircle />, label: 'Tạo đơn mới' },
    { path: '/admin/customers', icon: <FaUsers />, label: 'Khách hàng' },
    { path: '/admin/inventory', icon: <FaWarehouse />, label: 'Kho hàng' },
    { path: '/admin/promotions', icon: <FaTags />, label: 'Khuyến mãi' }, // <--- MỤC MỚI
    { path: '/admin/appearance', icon: <FaImage />, label: 'Giao diện' },
    { path: '/admin/reports', icon: <FaChartBar />, label: 'Báo cáo' },
    { path: '/admin/expenses', icon: <FaMoneyBillAlt />, label: 'Chi phí' },
  ];

  return (
    <div className="w-64 bg-white h-screen border-r border-stone-200 flex flex-col fixed left-0 top-0 z-10">
      {/* Logo */}
      <div className="h-16 flex items-center justify-center border-b border-stone-100">
        <h1 className="text-2xl font-bold text-stone-800 tracking-widest">BROWN</h1>
      </div>

      {/* Menu */}
      <nav className="flex-1 overflow-y-auto py-4">
        <ul className="space-y-1 px-2">
          {menuItems.map((item) => {
            const isActive = location.pathname === item.path;
            return (
              <li key={item.path}>
                <Link
                  to={item.path}
                  className={`flex items-center gap-3 px-4 py-3 rounded-lg transition-colors ${
                    isActive
                      ? 'bg-stone-900 text-white shadow-md'
                      : 'text-stone-500 hover:bg-stone-50 hover:text-stone-900'
                  }`}
                >
                  <span className="text-lg">{item.icon}</span>
                  <span className="font-medium text-sm">{item.label}</span>
                </Link>
              </li>
            );
          })}
        </ul>
      </nav>

      {/* Logout */}
      <div className="p-4 border-t border-stone-100">
        <button
          onClick={logout}
          className="flex items-center gap-3 px-4 py-3 w-full text-red-500 hover:bg-red-50 rounded-lg transition-colors"
        >
          <FaSignOutAlt />
          <span className="font-medium text-sm">Đăng xuất</span>
        </button>
      </div>
    </div>
  );
};

export default Sidebar;