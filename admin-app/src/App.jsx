<<<<<<< Updated upstream
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
=======
<<<<<<< Updated upstream
import { useState } from 'react'
import reactLogo from './assets/react.svg'
import viteLogo from '/vite.svg'
import './App.css'
>>>>>>> Stashed changes

function App() {
  return (
<<<<<<< Updated upstream
    <AdminAuthProvider> {/* 1. Bọc Provider ngoài cùng */}
      <BrowserRouter>
        <Routes>
          {/* Route Công khai */}
          <Route path="/login" element={<Login />} />

          {/* Route Bảo vệ (Phải đăng nhập mới thấy) */}
=======
    <>
      <div>
        <a href="https://vite.dev" target="_blank">
          <img src={viteLogo} className="logo" alt="Vite logo" />
        </a>
        <a href="https://react.dev" target="_blank">
          <img src={reactLogo} className="logo react" alt="React logo" />
        </a>
      </div>
      <h1>Vite + React</h1>
      <div className="card">
        <button onClick={() => setCount((count) => count + 1)}>
          count is {count}
        </button>
        <p>
          Edit <code>src/App.jsx</code> and save to test HMR
        </p>
      </div>
      <p className="read-the-docs">
        Click on the Vite and React logos to learn more
      </p>
    </>
  )
=======
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
>>>>>>> Stashed changes
          <Route element={<AdminRoute />}>
            <Route
              path="/*"
              element={
<<<<<<< Updated upstream
                <div className="flex min-h-screen bg-stone-50">
                  <Sidebar />
                  <div className="flex-1">
=======
                <AdminLayout>
                  <Sidebar />
                  <div className="flex-1 ml-64"> {/* Margin left bằng width sidebar */}
>>>>>>> Stashed changes
                    <Routes>
                      <Route path="/" element={<Dashboard />} />
                      <Route path="/products" element={<Products />} />
                      <Route path="/orders" element={<Orders />} />
<<<<<<< Updated upstream
                      <Route path="/inventory" element={<Inventory />} />
=======
                      <Route path="/customers" element={<Customers />} />
                      <Route path="/inventory" element={<Inventory />} />
                      <Route path="/promotions" element={<Promotions />} /> {/* <--- ROUTE MỚI */}
                      <Route path="/appearance" element={<Appearance />} />
>>>>>>> Stashed changes
                      <Route path="/reports" element={<Reports />} />
                      <Route path="/expenses" element={<Expenses />} />
                    </Routes>
                  </div>
<<<<<<< Updated upstream
                </div>
=======
                </AdminLayout>
>>>>>>> Stashed changes
              }
            />
          </Route>
        </Routes>
      </BrowserRouter>
    </AdminAuthProvider>
  );
<<<<<<< Updated upstream
=======
>>>>>>> Stashed changes
>>>>>>> Stashed changes
}

export default App;