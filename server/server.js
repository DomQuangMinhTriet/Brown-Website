require('dotenv').config(); // Load env đầu tiên
const express = require('express');
const cors = require('cors');
const productRoutes = require('./routes/productRoutes');

const app = express();
const port = process.env.PORT || 5000;

app.use(cors());
app.use(express.json());

// Gắn route sản phẩm vào đường dẫn /api/products
app.use('/api/products', productRoutes);

app.get('/', (req, res) => res.send('API Running...'));

app.listen(port, () => console.log(`Server chạy tại port ${port}`));