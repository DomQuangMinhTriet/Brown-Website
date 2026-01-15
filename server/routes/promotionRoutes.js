const express = require('express');
const router = express.Router();
const promotionController = require('../controllers/promotionController');

// Admin quản lý
router.get('/', promotionController.getAllPromotions);
router.post('/', promotionController.createPromotion);
router.delete('/:id', promotionController.deletePromotion);

// Public check
router.post('/check', promotionController.checkVoucher);

module.exports = router;
