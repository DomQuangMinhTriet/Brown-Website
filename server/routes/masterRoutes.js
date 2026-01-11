const express = require('express');
const router = express.Router();
const masterController = require('../controllers/masterController');

// Routes cho Stores (Kho/Chi nhánh)
router.get('/stores', masterController.getStores);
router.post('/stores', masterController.createStore);

// Routes cho Suppliers (Nhà cung cấp)
router.get('/suppliers', masterController.getSuppliers);
router.post('/suppliers', masterController.createSupplier);

module.exports = router;