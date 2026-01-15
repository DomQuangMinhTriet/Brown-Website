const express = require('express');
const router = express.Router();
const productController = require('../controllers/productController');

// Import Cache
const { verifyCache } = require('../middleware/cacheMiddleware');

// --- ÁP DỤNG CACHE ---
// Cache 300 giây (5 phút) cho danh sách sản phẩm
// Vì danh sách sản phẩm trang chủ ít khi thay đổi trong 5 phút
router.get('/', verifyCache(300), productController.getProducts);

// Cache 600 giây (10 phút) cho chi tiết sản phẩm
router.get('/:slug', verifyCache(600), productController.getProductBySlug);

// Các route ghi (Tạo/Sửa/Xóa) KHÔNG ĐƯỢC CACHE
router.post('/', productController.createProduct);

module.exports = router;