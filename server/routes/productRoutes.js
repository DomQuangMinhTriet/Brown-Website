const express = require('express');
const router = express.Router();
// Import controller (chúng ta sẽ tạo ngay sau đây)
const productController = require('../controllers/productController');

<<<<<<< Updated upstream
// Định nghĩa: GET / -> gọi hàm getProducts
router.get('/', productController.getProducts);

// Định nghĩa: GET /:slug -> gọi hàm getProductBySlug
router.get('/:slug', productController.getProductBySlug);
=======
// Route GET (Lấy dữ liệu - Có Cache)
router.get('/', productController.getProducts);
router.get('/:slug', productController.getProductBySlug);

// Route Ghi (Không Cache)
router.post('/', productController.createProduct);
>>>>>>> Stashed changes

// --- [MỚI] THÊM 2 ROUTE NÀY ---
router.put('/:id', productController.updateProduct);   // Sửa
router.delete('/:id', productController.deleteProduct); // Xóa

module.exports = router;