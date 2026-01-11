<<<<<<< Updated upstream
import { useState } from 'react';
import { BrowserRouter, Routes, Route } from 'react-router-dom';
import Sidebar from './components/Sidebar';
import Header from './components/Header';
import Dashboard from './pages/Dashboard';
import Products from './pages/Products';
import Inventory from './pages/Inventory';
=======
<<<<<<< Updated upstream
import { useState } from 'react'
import reactLogo from './assets/react.svg'
import viteLogo from '/vite.svg'
import './App.css'
>>>>>>> Stashed changes

function App() {
  // State để quản lý việc đóng mở sidebar trên mobile
  const [isSidebarOpen, setIsSidebarOpen] = useState(false);

  const toggleSidebar = (state) => {
    // Nếu truyền vào state cụ thể thì dùng nó, không thì đảo ngược state hiện tại
    setIsSidebarOpen(state !== undefined ? state : !isSidebarOpen);
  };

  return (
<<<<<<< Updated upstream
    <BrowserRouter>
      <div className="flex min-h-screen bg-stone-50 font-sans">
        {/* Sidebar */}
        <Sidebar isOpen={isSidebarOpen} toggleSidebar={toggleSidebar} />

        {/* Main Content */}
        <div className="flex-1 flex flex-col md:ml-72 transition-all duration-300">
          {/* Header */}
          <Header toggleSidebar={toggleSidebar} />

          {/* Khu vực nội dung chính (có padding-top để không bị header che) */}
=======
    <>
      <div>
        <a href="https://vite.dev" target="_blank">
          <img src={viteLogo} className="logo" alt="Vite logo" />
        </a>
        <a href="https://react.dev" target="_blank">
          <img src={reactLogo} className="logo react" alt="React logo" />
        </a>
=======
import { useState } from 'react';
import { BrowserRouter, Routes, Route } from 'react-router-dom';
import Sidebar from './components/Sidebar';
import Header from './components/Header';
import Dashboard from './pages/Dashboard';
import Products from './pages/Products';
import Inventory from './pages/Inventory';
import Orders from './pages/Orders';      // <--- Đảm bảo có import
import Expenses from './pages/Expenses';  // <--- Đảm bảo có import
import Reports from './pages/Reports';    // <--- Đảm bảo có import

function App() {
  const [isSidebarOpen, setIsSidebarOpen] = useState(false);

  const toggleSidebar = (state) => {
    setIsSidebarOpen(state !== undefined ? state : !isSidebarOpen);
  };

  return (
    <BrowserRouter>
      <div className="flex min-h-screen bg-stone-50 font-sans">
        <Sidebar isOpen={isSidebarOpen} toggleSidebar={toggleSidebar} />
        <div className="flex-1 flex flex-col md:ml-72 transition-all duration-300">
          <Header toggleSidebar={toggleSidebar} />
>>>>>>> Stashed changes
          <main className="flex-1 pt-16 bg-stone-50/50">
            <Routes>
              <Route path="/" element={<Dashboard />} />
              <Route path="/products" element={<Products />} />
              <Route path="/inventory" element={<Inventory />} />
<<<<<<< Updated upstream
            </Routes>
          </main>
        </div>
=======
              <Route path="/orders" element={<Orders />} />
              
              {/* Đảm bảo 2 dòng này tồn tại */}
              <Route path="/expenses" element={<Expenses />} />
              <Route path="/reports" element={<Reports />} />
            </Routes>
          </main>
        </div>
>>>>>>> Stashed changes
>>>>>>> Stashed changes
      </div>
    </BrowserRouter>
  );
}

export default App;