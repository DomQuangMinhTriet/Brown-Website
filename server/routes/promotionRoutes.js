const express = require('express');
const router = express.Router();
const controller = require('../controllers/promotionController');
const requireAuth = require('../middleware/authMiddleware'); // Nếu cần check login

router.post('/check', controller.checkVoucher); // Có thể thêm requireAuth nếu muốn
module.exports = router;