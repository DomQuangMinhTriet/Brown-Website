import { Link, useLocation } from 'react-router-dom';
import { FaHome, FaBox, FaWarehouse, FaTruck, FaChartBar, FaTimes } from 'react-icons/fa';
import { FaMoneyBillWave } from 'react-icons/fa';

const Sidebar = ({ isOpen, toggleSidebar }) => {
  const location = useLocation();
  
  const menuItems = [
    { path: '/', name: 'Tổng quan', icon: <FaHome /> },
    { path: '/products', name: 'Sản phẩm', icon: <FaBox /> },
    { path: '/inventory', name: 'Kho & Nhập hàng', icon: <FaWarehouse /> },
    { path: '/orders', name: 'Đơn hàng', icon: <FaTruck /> },
    { path: '/expenses', name: 'Tài chính & Chi phí', icon: <FaMoneyBillWave /> }, // <--- THÊM MỚI
    { path: '/reports', name: 'Báo cáo', icon: <FaChartBar /> },
  ];

  return (
    <>
      {/* Overlay (lớp mờ) khi mở sidebar trên mobile */}
      <div 
        className={`fixed inset-0 bg-black/30 backdrop-blur-sm z-30 md:hidden transition-opacity duration-300 ${isOpen ? 'opacity-100' : 'opacity-0 pointer-events-none'}`}
        onClick={toggleSidebar}
      ></div>

      {/* Sidebar chính */}
      <div className={`fixed top-0 left-0 h-full w-72 bg-stone-100 border-r border-stone-200 z-40 transition-transform duration-300 ease-in-out md:translate-x-0 ${isOpen ? 'translate-x-0' : '-translate-x-full'}`}>
        {/* Logo & Nút đóng */}
        <div className="h-16 flex items-center justify-between px-6 border-b border-stone-200 bg-stone-100">
          <h1 className="text-2xl font-bold text-stone-800 tracking-[0.2em]">BROWN</h1>
          <button onClick={toggleSidebar} className="md:hidden text-stone-500 focus:outline-none">
            <FaTimes className="w-5 h-5" />
          </button>
        </div>

        {/* Menu Items */}
        <nav className="py-6 px-4">
          <ul className="space-y-2">
            {menuItems.map((item) => {
              const isActive = location.pathname === item.path;
              return (
                <li key={item.path}>
                  <Link
                    to={item.path}
                    onClick={() => toggleSidebar(false)} // Đóng sidebar trên mobile khi click
                    className={`flex items-center gap-4 px-4 py-3 rounded-lg transition-all duration-200 group font-medium ${
                      isActive 
                        ? 'bg-stone-200 text-stone-900' 
                        : 'text-stone-500 hover:bg-stone-200 hover:text-stone-700'
                    }`}
                  >
                    <span className={`text-lg ${isActive ? 'text-stone-800' : 'text-stone-400 group-hover:text-stone-600'}`}>{item.icon}</span>
                    <span>{item.name}</span>
                  </Link>
                </li>
              );
            })}
          </ul>
        </nav>

        {/* Footer nhỏ */}
        <div className="absolute bottom-4 left-0 w-full text-center text-xs text-stone-400 tracking-wider">
          FASHION ERP V1.0
        </div>
      </div>
    </>
  );
};

export default Sidebar;