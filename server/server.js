require('dotenv').config(); // Load env đầu tiên
const express = require('express');
const cors = require('cors');
const productRoutes = require('./routes/productRoutes');
const uploadRoutes = require('./routes/uploadRoutes');
const categoryRoutes = require('./routes/categoryRoutes');
const masterRoutes = require('./routes/masterRoutes');
const inventoryRoutes = require('./routes/inventoryRoutes');

const app = express();
const port = process.env.PORT || 5000;

app.use(cors());
app.use(express.json());

// Gắn route sản phẩm vào đường dẫn /api/products
app.use('/api/products', productRoutes);
app.use('/api/upload', uploadRoutes);
app.use('/api/categories', categoryRoutes);
app.use('/api', masterRoutes);
app.use('/api/inventory', inventoryRoutes);

app.get('/', (req, res) => res.send('API Running...'));

app.listen(port, () => console.log(`Server chạy tại port ${port}`));