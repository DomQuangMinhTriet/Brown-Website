import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.jsx'
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
  </StrictMode>,
)