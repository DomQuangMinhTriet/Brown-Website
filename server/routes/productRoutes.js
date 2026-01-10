const express = require('express');
const router = express.Router();
// Import controller (chúng ta sẽ tạo ngay sau đây)
const productController = require('../controllers/productController');

// Định nghĩa: GET / -> gọi hàm getProducts
router.get('/', productController.getProducts);

// POST /api/products -> Tạo mới (MỚI THÊM)
router.post('/', productController.createProduct);

// Định nghĩa: GET /:slug -> gọi hàm getProductBySlug
router.get('/:slug', productController.getProductBySlug);

module.exports = router;