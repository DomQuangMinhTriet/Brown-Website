// server/routes/orderRoutes.js
const express = require('express');
const router = express.Router();
const orderController = require('../controllers/orderController');

// --- 1. ROUTE TÍNH PHÍ SHIP (BẮT BUỘC PHẢI CÓ) ---
// Frontend gọi cái này để tính tiền ship GHN trước khi đặt
router.post('/shipping-fee', orderController.getShippingFee);

// --- 2. ROUTE TẠO ĐƠN HÀNG ---
// LƯU Ý QUAN TRỌNG: Tôi đã bỏ "validate(createOrderSchema)" ở đây.
// Vì trong orderController.createOrder chúng ta đã có Zod Schema mới nhất rồi.
// Để lại middleware cũ ở đây sẽ khiến dữ liệu ID bị lọc mất -> Gây lỗi.
router.post('/', orderController.createOrder);

// --- 3. CÁC ROUTE ADMIN ---
router.get('/', orderController.getAllOrders);
// [THÊM DÒNG NÀY ĐỂ FIX LỖI 404]
router.put('/bulk-status', orderController.bulkUpdateOrderStatus); 

// Route update trạng thái đơn lẻ (Dòng này phải nằm dưới bulk-status)
router.put('/:id/status', orderController.updateOrderStatus);
router.post('/create-admin', orderController.createAdminOrder);

module.exports = router;