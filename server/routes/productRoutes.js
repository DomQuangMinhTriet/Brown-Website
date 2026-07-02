const express = require('express');
const router = express.Router();
const productController = require('../controllers/productController');

// Thêm dòng này vào
router.get('/export/sapo', productController.exportProductsToSapoExcel);

router.get('/', productController.getProducts);
router.get('/:slug', productController.getProductBySlug);

// Route Ghi (Không Cache)
router.post('/', productController.createProduct);
router.put('/:id/discount', productController.updateProductDiscount); // Bật/tắt & set giảm giá trực tiếp
router.put('/:id', productController.updateProduct);   // Sửa
router.delete('/:id', productController.deleteProduct); // Xóa

module.exports = router;