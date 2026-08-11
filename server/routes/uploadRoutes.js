// server/routes/uploadRoutes.js
const express = require('express');
const router = express.Router();
const multer = require('multer');
const uploadController = require('../controllers/uploadController');

// Cấu hình Multer: Lưu file tạm vào RAM trước khi đẩy lên Cloud
// (Phần này giữ nguyên vì Cloudinary cần buffer từ RAM)
// [AN TOÀN] Giới hạn 25MB — đủ cho ảnh chất lượng cao và video ngắn (~10s),
// tránh 1 file khổng lồ chiếm hết RAM server hoặc ăn dung lượng Cloudinary.
// Multer không phân biệt được ảnh/video ở bước này nên dùng chung 1 mức trần;
// giới hạn chặt hơn cho từng loại (ảnh 5MB, video 15MB) được kiểm tra thêm ở
// uploadController sau khi đã biết mimetype.
const MAX_UPLOAD_BYTES = 50 * 1024 * 1024;
const storage = multer.memoryStorage();
const upload = multer({ storage, limits: { fileSize: MAX_UPLOAD_BYTES } });

// API nhận file với key là 'image'
router.post('/', upload.single('image'), uploadController.uploadImage);

// [AN TOÀN] Bắt lỗi Multer (vượt dung lượng, sai field...) và trả JSON thân
// thiện thay vì để Express trả HTML lỗi mặc định khiến Frontend crash khi
// cố gắng đọc res.data.url.
router.use((err, req, res, next) => {
    if (err instanceof multer.MulterError) {
        if (err.code === 'LIMIT_FILE_SIZE') {
            return res.status(413).json({
                success: false,
                message: `File quá lớn — tối đa ${MAX_UPLOAD_BYTES / (1024 * 1024)}MB.`,
            });
        }
        return res.status(400).json({ success: false, message: 'Lỗi upload: ' + err.message });
    }
    next(err);
});

module.exports = router;
