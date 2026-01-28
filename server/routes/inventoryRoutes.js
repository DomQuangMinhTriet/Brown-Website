const express = require('express');
const router = express.Router();
const inventoryController = require('../controllers/inventoryController');

// --- NHÀ CUNG CẤP & CHI NHÁNH ---
router.get('/suppliers', inventoryController.getSuppliers);
router.post('/suppliers', inventoryController.createSupplier);
router.get('/stores', inventoryController.getStores);
router.post('/stores', inventoryController.createStore);

// --- KHO VẬN ---
router.get('/stock', inventoryController.getStock);      // Lấy tồn kho (Số lượng > 0)
router.get('/history', inventoryController.getHistory);  // <--- [MỚI] Lấy lịch sử nhập
router.post('/inbound', inventoryController.inboundStock);
router.post('/adjust', inventoryController.adjustStock);
module.exports = router;