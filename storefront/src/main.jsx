import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App.jsx'
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