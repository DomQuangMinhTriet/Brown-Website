
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
          <main className="flex-1 pt-16 bg-stone-50/50">
            <Routes>
              <Route path="/" element={<Dashboard />} />
              <Route path="/products" element={<Products />} />
              <Route path="/inventory" element={<Inventory />} />
              <Route path="/orders" element={<Orders />} />
              
              {/* Đảm bảo 2 dòng này tồn tại */}
              <Route path="/expenses" element={<Expenses />} />
              <Route path="/reports" element={<Reports />} />
            </Routes>
          </main>
        </div>
      </div>
    </BrowserRouter>
  );
}

export default App;