import { BrowserRouter, Routes, Route } from 'react-router-dom';
import Sidebar from './components/Sidebar';
import Dashboard from './pages/Dashboard';
import Products from './pages/Products';
import Orders from './pages/Orders';
import Inventory from './pages/Inventory';
import Reports from './pages/Reports';
import Expenses from './pages/Expenses';
// Import mới
import Login from './pages/Login';
import { AdminAuthProvider } from './context/AdminAuthContext';
import AdminRoute from './components/AdminRoute';

function App() {
  return (
    <AdminAuthProvider> {/* 1. Bọc Provider ngoài cùng */}
      <BrowserRouter>
        <Routes>
          {/* Route Công khai */}
          <Route path="/login" element={<Login />} />

          {/* Route Bảo vệ (Phải đăng nhập mới thấy) */}
          <Route element={<AdminRoute />}>
            <Route
              path="/*"
              element={
                <div className="flex min-h-screen bg-stone-50">
                  <Sidebar />
                  <div className="flex-1">
                    <Routes>
                      <Route path="/" element={<Dashboard />} />
                      <Route path="/products" element={<Products />} />
                      <Route path="/orders" element={<Orders />} />
                      <Route path="/inventory" element={<Inventory />} />
                      <Route path="/reports" element={<Reports />} />
                      <Route path="/expenses" element={<Expenses />} />
                    </Routes>
                  </div>
                </div>
              }
            />
          </Route>
        </Routes>
      </BrowserRouter>
    </AdminAuthProvider>
  );
}

export default App;