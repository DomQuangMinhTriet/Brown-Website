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
import { HelmetProvider } from 'react-helmet-async'; // <--- IMPORT MỚI

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <HelmetProvider> {/* <--- BỌC NGOÀI CÙNG HOẶC TRONG AUTHPROVIDER ĐỀU ĐƯỢC */}
      <AuthProvider>
        <CartProvider>
          <App />
        </CartProvider>
      </AuthProvider>
    </HelmetProvider>
>>>>>>> Stashed changes
  </StrictMode>,
)
>>>>>>> Stashed changes
