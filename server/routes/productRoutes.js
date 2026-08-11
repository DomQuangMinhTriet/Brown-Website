const express = require('express');
const router = express.Router();
const productController = require('../controllers/productController');
const { verifyCache, invalidateAfterResponse } = require('../middleware/cacheMiddleware');

// Thêm dòng này vào
router.get('/export/sapo', productController.exportProductsToSapoExcel);

router.get('/', verifyCache(120), productController.getProducts);
router.get('/:slug', verifyCache(300), productController.getProductBySlug);

// Route Ghi (Không Cache)
router.post('/', invalidateAfterResponse('/api/products'), productController.createProduct);
router.put('/variants/:id/discount', invalidateAfterResponse('/api/products'), productController.updateVariantDiscount); // Bật/tắt & set giảm giá trực tiếp theo biến thể (màu/size)
router.put('/:id', invalidateAfterResponse('/api/products'), productController.updateProduct);   // Sửa
router.delete('/:id', invalidateAfterResponse('/api/products'), productController.deleteProduct); // Xóa

module.exports = router;
