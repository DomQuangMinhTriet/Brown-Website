import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.jsx'

// --- THÊM 2 DÒNG NÀY ---
import { ToastContainer } from 'react-toastify';
import 'react-toastify/dist/ReactToastify.css';

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <App />
    {/* Đặt ToastContainer ở đây để hiện thông báo trên toàn Admin */}
    <ToastContainer position="top-right" autoClose={3000} />
  </StrictMode>,
)