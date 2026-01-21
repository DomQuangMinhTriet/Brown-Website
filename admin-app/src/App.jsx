import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { ToastContainer } from 'react-toastify';
import 'react-toastify/dist/ReactToastify.css';

// Context & Hooks
import { AdminAuthProvider } from './context/AdminAuthContext';
import useRealtimeOrder from './hooks/useRealtimeOrder';

// Components
import Sidebar from './components/Sidebar';
import AdminRoute from './components/AdminRoute';

// Pages
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';
import Products from './pages/Products';
import Orders from './pages/Orders';
import Inventory from './pages/Inventory';
import Reports from './pages/Reports';
import Expenses from './pages/Expenses';
import Customers from './pages/Customer';
import Appearance from './pages/Appearance';
import Promotions from './pages/Promotions'; // <--- IMPORT TRANG MỚI
import CreateOrder from './pages/CreateOrder';

// Layout bọc để kích hoạt Realtime Notification
const AdminLayout = ({ children }) => {
  useRealtimeOrder();
  return <div className="flex min-h-screen bg-stone-50">{children}</div>;
};

function App() {
  return (
    <AdminAuthProvider>
      <BrowserRouter>
        <ToastContainer position="top-right" autoClose={3000} />
        
        <Routes>
          <Route path="/login" element={<Login />} />

          {/* Các Route cần đăng nhập Admin */}
          <Route element={<AdminRoute />}>
            <Route
              path="/*"
              element={
                <AdminLayout>
                  <Sidebar />
                  <div className="flex-1 ml-64"> {/* Margin left bằng width sidebar */}
                    <Routes>
                      <Route path="/" element={<Dashboard />} />
                      <Route path="/products" element={<Products />} />
                      <Route path="/orders" element={<Orders />} />
                      <Route path="/customers" element={<Customers />} />
                      <Route path="/inventory" element={<Inventory />} />
                      <Route path="/promotions" element={<Promotions />} /> {/* <--- ROUTE MỚI */}
                      <Route path="/appearance" element={<Appearance />} />
                      <Route path="/reports" element={<Reports />} />
                      <Route path="/expenses" element={<Expenses />} />
                      <Route path="/orders/create" element={<CreateOrder />} />
                    </Routes>
                  </div>
                </AdminLayout>
              }
            />
          </Route>
        </Routes>
      </BrowserRouter>
    </AdminAuthProvider>
  );
}

export default App;