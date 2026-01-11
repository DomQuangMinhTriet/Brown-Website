import { useState } from 'react';
import { BrowserRouter, Routes, Route } from 'react-router-dom';
import Sidebar from './components/Sidebar';
import Header from './components/Header';
import Dashboard from './pages/Dashboard';
import Products from './pages/Products';
import Inventory from './pages/Inventory';

function App() {
  // State để quản lý việc đóng mở sidebar trên mobile
  const [isSidebarOpen, setIsSidebarOpen] = useState(false);

  const toggleSidebar = (state) => {
    // Nếu truyền vào state cụ thể thì dùng nó, không thì đảo ngược state hiện tại
    setIsSidebarOpen(state !== undefined ? state : !isSidebarOpen);
  };

  return (
    <BrowserRouter>
      <div className="flex min-h-screen bg-stone-50 font-sans">
        {/* Sidebar */}
        <Sidebar isOpen={isSidebarOpen} toggleSidebar={toggleSidebar} />

        {/* Main Content */}
        <div className="flex-1 flex flex-col md:ml-72 transition-all duration-300">
          {/* Header */}
          <Header toggleSidebar={toggleSidebar} />

          {/* Khu vực nội dung chính (có padding-top để không bị header che) */}
          <main className="flex-1 pt-16 bg-stone-50/50">
            <Routes>
              <Route path="/" element={<Dashboard />} />
              <Route path="/products" element={<Products />} />
              <Route path="/inventory" element={<Inventory />} />
            </Routes>
          </main>
        </div>
      </div>
    </BrowserRouter>
  );
}

export default App;