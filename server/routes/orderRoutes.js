const express = require('express');
const router = express.Router();
const orderController = require('../controllers/orderController');

// Khách hàng tạo đơn
router.post('/', orderController.createOrder);

// Admin xem danh sách
router.get('/', orderController.getAllOrders);

// Admin cập nhật trạng thái
router.put('/:id/status', orderController.updateOrderStatus);

module.exports = router;