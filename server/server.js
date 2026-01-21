// server.js
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const morgan = require('morgan');

// Import Routes
const productRoutes = require('./routes/productRoutes');
const categoryRoutes = require('./routes/categoryRoutes');
const uploadRoutes = require('./routes/uploadRoutes');
const orderRoutes = require('./routes/orderRoutes');
const inventoryRoutes = require('./routes/inventoryRoutes');
const reportRoutes = require('./routes/reportRoutes');
const customerRoutes = require('./routes/customerRoutes');
const promotionRoutes = require('./routes/promotionRoutes');
const expenseRoutes = require('./routes/expenseRoutes');
const shippingRoutes = require('./routes/shippingRoutes');
const contentRoutes = require('./routes/contentRoutes');
const masterRoutes = require('./routes/masterRoutes');

const app = express();

// --- CẤU HÌNH BẢO MẬT (QUAN TRỌNG) ---
// Cho phép Frontend (Localhost + Production Domain) truy cập
const allowedOrigins = [
  'http://localhost:5173', // Frontend Local
  'http://localhost:3000', // Admin Local (nếu chạy port khác)
  // 'https://your-domain.com' // Domain thật (hãy uncomment khi deploy)
];

app.use(cors({
  origin: function (origin, callback) {
    if (!origin) return callback(null, true); // Cho phép gọi từ Postman/Mobile App
    if (allowedOrigins.indexOf(origin) === -1) {
      // Tạm thời cho phép tất cả để dễ test, sau này chặn sau:
      // return callback(new Error('CORS Policy: Blocked'), false); 
      return callback(null, true); 
    }
    return callback(null, true);
  },
  credentials: true 
}));

app.use(express.json());
app.use(morgan('dev'));

// --- ĐĂNG KÝ ROUTE (QUAN TRỌNG) ---
app.use('/api/products', productRoutes);
app.use('/api/categories', categoryRoutes);
app.use('/api/upload', uploadRoutes);
app.use('/api/orders', orderRoutes);
app.use('/api/inventory', inventoryRoutes);
app.use('/api/reports', reportRoutes);
app.use('/api/customers', customerRoutes);
app.use('/api/promotions', promotionRoutes);
app.use('/api/expenses', expenseRoutes);
app.use('/api/shipping', shippingRoutes);
app.use('/api/content', contentRoutes);
app.use('/api/master', masterRoutes);

// Health Check
app.get('/', (req, res) => {
  res.send('API Server is running...');
});

// Start Server
const PORT = process.env.PORT || 5000;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});