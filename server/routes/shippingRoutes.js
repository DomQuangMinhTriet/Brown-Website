const express = require('express');
const router = express.Router();
const controller = require('../controllers/shippingController');

router.post('/calculate', controller.calculateFee);
module.exports = router;