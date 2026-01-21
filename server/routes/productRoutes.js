const express = require('express');
const router = express.Router();
const productController = require('../controllers/productController');
const { verifyCache } = require('../middleware/cacheMiddleware');

router.get('/', productController.getProducts);
router.get('/:slug', productController.getProductBySlug);

// Route Ghi (Không Cache)
router.post('/', productController.createProduct);
// --- [MỚI] THÊM 2 ROUTE NÀY ---
router.put('/:id', productController.updateProduct);   // Sửa
router.delete('/:id', productController.deleteProduct); // Xóa

module.exports = router;