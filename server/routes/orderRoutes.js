// server/routes/orderRoutes.js
const express = require('express');
const router = express.Router();
const orderController = require('../controllers/orderController');
const { invalidateAfterResponse } = require('../middleware/cacheMiddleware');

// --- 1. ROUTE TÍNH PHÍ SHIP (BẮT BUỘC PHẢI CÓ) ---
// Frontend gọi cái này để tính tiền ship GHN trước khi đặt
router.post('/shipping-fee', orderController.getShippingFee);

// --- 2. ROUTE TẠO ĐƠN HÀNG ---
// LƯU Ý QUAN TRỌNG: Tôi đã bỏ "validate(createOrderSchema)" ở đây.
// Vì trong orderController.createOrder chúng ta đã có Zod Schema mới nhất rồi.
// Để lại middleware cũ ở đây sẽ khiến dữ liệu ID bị lọc mất -> Gây lỗi.
router.post('/', invalidateAfterResponse('/api/products'), orderController.createOrder);

// --- 3. CÁC ROUTE ADMIN ---
router.get('/', orderController.getAllOrders);
router.put('/bulk-status', invalidateAfterResponse('/api/products'), orderController.bulkUpdateOrderStatus);

// [MỚI THÊM] Route để Admin cập nhật thông tin giao hàng & ghi chú
router.put('/:id/details', orderController.updateOrderDetails);

// Route update trạng thái đơn lẻ (Dòng này phải nằm dưới bulk-status và details)
router.put('/:id/status', invalidateAfterResponse('/api/products'), orderController.updateOrderStatus);
router.post('/create-admin', invalidateAfterResponse('/api/products'), orderController.createAdminOrder);

router.get('/export/sapo', orderController.exportOrdersToSapoExcel);

router.get('/accessory', orderController.getAccessoryProduct);
router.get('/:id', orderController.getOrderById);
module.exports = router;
