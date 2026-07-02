const express = require('express');
const router = express.Router();
const reportController = require('../controllers/reportController');

router.get('/dashboard', reportController.getDashboardStats);
router.get('/financial', reportController.getFinancialReport); // <--- Route mới
router.get('/monthly', reportController.getMonthlyFinancialReport);
router.get('/products', reportController.getProductSalesReport); // Sản phẩm bán chạy theo thời gian

module.exports = router;