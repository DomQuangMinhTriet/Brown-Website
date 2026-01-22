// import { StrictMode } from 'react'
// import { createRoot } from 'react-dom/client'
// import './index.css'
// import App from './App.jsx'
// import { AuthProvider } from './context/AuthContext';
// import { CartProvider } from './context/CartContext';
// import { HelmetProvider } from 'react-helmet-async';
// import { LanguageProvider } from './context/LanguageContext';

// // --- THÊM 2 DÒNG NÀY ---
// import { ToastContainer } from 'react-toastify';
// import 'react-toastify/dist/ReactToastify.css';

// createRoot(document.getElementById('root')).render(
//   <StrictMode>
//     <HelmetProvider>
//       <LanguageProvider>
//         <AuthProvider>
//           <CartProvider>
//             <App />
//             {/* Đặt ToastContainer ở đây để hiện thông báo trên toàn Website */}
//             <ToastContainer position="top-right" autoClose={3000} hideProgressBar={false} />
//           </CartProvider>
//         </AuthProvider>
//       </LanguageProvider>
//     </HelmetProvider>
//   </StrictMode>,
// )

import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import './index.css';
import App from './App.jsx';

// --- Providers Storefront ---
import { AuthProvider } from './context/AuthContext';
import { CartProvider } from './context/CartContext';
import { HelmetProvider } from 'react-helmet-async';
import { LanguageProvider } from './context/LanguageContext';

// --- Providers Admin ---
import { AdminAuthProvider } from './context/AdminAuthContext';

// --- Common ---
import { ToastContainer } from 'react-toastify';
import 'react-toastify/dist/ReactToastify.css';

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <HelmetProvider>
      <LanguageProvider>
        {/* Bọc cả AdminAuth và CustomerAuth */}
        <AdminAuthProvider>
          <AuthProvider>
            <CartProvider>
              <App />
              {/* ToastContainer dùng chung cho cả 2 hệ thống */}
              <ToastContainer position="top-right" autoClose={3000} hideProgressBar={false} />
            </CartProvider>
          </AuthProvider>
        </AdminAuthProvider>
      </LanguageProvider>
    </HelmetProvider>
  </StrictMode>,
);