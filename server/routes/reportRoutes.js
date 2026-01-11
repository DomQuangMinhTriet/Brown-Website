const express = require('express');
const router = express.Router();
const reportController = require('../controllers/reportController');

router.get('/dashboard', reportController.getDashboardStats);
router.get('/financial', reportController.getFinancialReport); // <--- Route mới

module.exports = router;