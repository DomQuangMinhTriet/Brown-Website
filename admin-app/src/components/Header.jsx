import { FaBars, FaUserCircle } from 'react-icons/fa';

const Header = ({ toggleSidebar }) => {
  return (
    <header className="bg-white/80 backdrop-blur-md h-16 fixed w-full z-20 top-0 left-0 border-b border-stone-200 px-4 flex items-center justify-between md:px-6">
      {/* Nút mở Menu trên mobile */}
      <div className="flex items-center gap-4">
        <button onClick={toggleSidebar} className="text-stone-500 md:hidden focus:outline-none">
          <FaBars className="w-6 h-6" />
        </button>
        {/* Logo hiển thị trên mobile */}
        <h1 className="text-lg font-bold text-stone-800 tracking-widest md:hidden">BROWN</h1>
        {/* Tiêu đề trang (sẽ thay đổi động sau này) */}
        <h2 className="text-xl font-medium text-stone-800 hidden md:block">Tổng quan</h2>
      </div>

      {/* Phần thông tin User bên phải */}
      <div className="flex items-center gap-4">
        <div className="hidden md:flex flex-col items-end">
          <span className="font-medium text-stone-700 text-sm">Admin</span>
          <span className="text-stone-500 text-xs">Quản trị viên</span>
        </div>
        <FaUserCircle className="w-8 h-8 text-stone-400 cursor-pointer" />
      </div>
    </header>
  );
};

export default Header;