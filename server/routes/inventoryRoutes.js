const express = require('express');
const router = express.Router();
const inventoryController = require('../controllers/inventoryController');
const { invalidateAfterResponse } = require('../middleware/cacheMiddleware');

// --- NHÀ CUNG CẤP & CHI NHÁNH ---
router.get('/suppliers', inventoryController.getSuppliers);
router.post('/suppliers', inventoryController.createSupplier);
router.get('/stores', inventoryController.getStores);
router.post('/stores', inventoryController.createStore);

// --- KHO VẬN ---
router.get('/stock', inventoryController.getStock);      // Lấy tồn kho (Số lượng > 0)
router.get('/history', inventoryController.getHistory);  // <--- [MỚI] Lấy lịch sử nhập
router.post('/inbound', invalidateAfterResponse('/api/products'), inventoryController.inboundStock);
router.post('/adjust', invalidateAfterResponse('/api/products'), inventoryController.adjustStock);

// --- HÀNG LỖI ---
router.post('/defective', invalidateAfterResponse('/api/products'), inventoryController.reportDefectiveItem);
router.get('/defective', inventoryController.getDefectiveLogs);
module.exports = router;
