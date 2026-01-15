require('dotenv').config();
const express = require('express');
const cors = require('cors');

// Import các Routes
const productRoutes = require('./routes/productRoutes');

const uploadRoutes = require('./routes/uploadRoutes');
const categoryRoutes = require('./routes/categoryRoutes');
const masterRoutes = require('./routes/masterRoutes');
const inventoryRoutes = require('./routes/inventoryRoutes');
const orderRoutes = require('./routes/orderRoutes');
const expenseRoutes = require('./routes/expenseRoutes'); // <--- MỚI
const reportRoutes = require('./routes/reportRoutes');   // <--- MỚI
const customerRoutes = require('./routes/customerRoutes'); // <--- Thêm
const promotionRoutes = require('./routes/promotionRoutes'); // <--- Thêm
const shippingRoutes = require('./routes/shippingRoutes');
const contentRoutes = require('./routes/contentRoutes');



const app = express();
const port = process.env.PORT || 5000;

app.use(cors());
app.use(express.json());

// --- ĐĂNG KÝ ROUTE (QUAN TRỌNG) ---
app.use('/api/products', productRoutes);

app.use('/api/upload', uploadRoutes);
app.use('/api/categories', categoryRoutes);
app.use('/api', masterRoutes); // stores, suppliers
app.use('/api/inventory', inventoryRoutes);
app.use('/api/orders', orderRoutes);
app.use('/api/expenses', expenseRoutes); // <--- Đảm bảo dòng này có
app.use('/api/reports', reportRoutes);   // <--- Đảm bảo dòng này có
app.use('/api/customers', customerRoutes); // <--- Thêm
app.use('/api/promotions', promotionRoutes); // <--- Đăng ký
app.use('/api/shipping', shippingRoutes);
app.use('/api/content', contentRoutes);

app.get('/', (req, res) => res.send('API Running...'));

app.listen(port, () => console.log(`Server chạy tại port ${port}`));