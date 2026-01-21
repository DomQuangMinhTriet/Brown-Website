import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App.jsx'
<<<<<<< Updated upstream
import './index.css'
import { AuthProvider } from './context/AuthContext'; // <--- QUAN TRỌNG: Import Auth
import { CartProvider } from './context/CartContext'; // <--- Import Cart

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    {/* Bọc AuthProvider ở ngoài cùng để toàn bộ App dùng được User */}
    <AuthProvider>
      <CartProvider>
        <App />
      </CartProvider>
    </AuthProvider>
  </React.StrictMode>,
)
=======
<<<<<<< Updated upstream

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <App />
=======
import { AuthProvider } from './context/AuthContext';
import { CartProvider } from './context/CartContext';
import { HelmetProvider } from 'react-helmet-async';
import { LanguageProvider } from './context/LanguageContext';

// --- THÊM 2 DÒNG NÀY ---
import { ToastContainer } from 'react-toastify';
import 'react-toastify/dist/ReactToastify.css';

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <HelmetProvider>
      <LanguageProvider>
        <AuthProvider>
          <CartProvider>
            <App />
            {/* Đặt ToastContainer ở đây để hiện thông báo trên toàn Website */}
            <ToastContainer position="top-right" autoClose={3000} hideProgressBar={false} />
          </CartProvider>
        </AuthProvider>
      </LanguageProvider>
    </HelmetProvider>
>>>>>>> Stashed changes
  </StrictMode>,
)
>>>>>>> Stashed changes
