// server/routes/orderRoutes.js
const express = require('express');
const router = express.Router();
const orderController = require('../controllers/orderController');

// Import Middleware và Schema vừa tạo
const validate = require('../middleware/validateMiddleware');
const { createOrderSchema } = require('../validators/orderSchema');

// --- CẬP NHẬT ROUTE NÀY ---
// Thêm validate(createOrderSchema) vào giữa
router.post('/', validate(createOrderSchema), orderController.createOrder);

// Các route khác giữ nguyên
router.get('/', orderController.getAllOrders);
router.put('/:id/status', orderController.updateOrderStatus);

module.exports = router;