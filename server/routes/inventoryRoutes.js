const express = require('express');
const router = express.Router();
const inventoryController = require('../controllers/inventoryController');

// GET /api/inventory -> Xem lịch sử nhập
router.get('/', inventoryController.getInventoryBatches);

// POST /api/inventory/import -> Nhập hàng mới
router.post('/import', inventoryController.importStock);

module.exports = router;