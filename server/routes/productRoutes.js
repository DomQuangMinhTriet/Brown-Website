const express = require('express');
const router = express.Router();
const productController = require('../controllers/productController');

// Thêm dòng này vào
router.get('/export/sapo', productController.exportProductsToSapoExcel);

router.get('/', productController.getProducts);
router.get('/:slug', productController.getProductBySlug);

// Route Ghi (Không Cache)
router.post('/', productController.createProduct);
router.put('/variants/:id/discount', productController.updateVariantDiscount); // Bật/tắt & set giảm giá trực tiếp theo biến thể (màu/size)
router.put('/:id', productController.updateProduct);   // Sửa
router.delete('/:id', productController.deleteProduct); // Xóa

module.exports = router;