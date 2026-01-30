// server/routes/uploadRoutes.js
const express = require('express');
const router = express.Router();
const multer = require('multer');
const uploadController = require('../controllers/uploadController');

// Cấu hình Multer: Lưu file tạm vào RAM trước khi đẩy lên Cloud
// (Phần này giữ nguyên vì Cloudinary cần buffer từ RAM)
const storage = multer.memoryStorage();
const upload = multer({ storage: storage });

// API nhận file với key là 'image'
router.post('/', upload.single('image'), uploadController.uploadImage);

module.exports = router;