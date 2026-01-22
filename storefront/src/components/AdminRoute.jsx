import { useAdminAuth } from '../context/AdminAuthContext';
import { Navigate, Outlet } from 'react-router-dom';

const AdminRoute = () => {
  const { admin, loading, logout } = useAdminAuth();

  if (loading) return <div className="h-screen flex items-center justify-center">Đang kiểm tra quyền...</div>;
  
  // 1. Nếu chưa đăng nhập -> Đá về Login
  if (!admin) {
      return <Navigate to="/login" />;
  }

  // 2. LOGIC PHÂN QUYỀN CỐ ĐỊNH:
  // Nếu đã đăng nhập nhưng KHÔNG PHẢI là "brownvn25@gmail.com" -> Đá ra ngoài ngay
  if (admin.email !== 'brownvn25@gmail.com') {
      alert("⛔ Bạn không có quyền truy cập trang Quản trị!");
      logout(); // Đăng xuất tài khoản khách này ra
      return <Navigate to="/login" />;
  }

  // 3. Đúng là Admin xịn -> Cho vào
  return <Outlet />;
};

export default AdminRoute;