// server/controllers/uploadController.js
const cloudinary = require('cloudinary').v2;
const streamifier = require('streamifier');
require('dotenv').config();

// 1. Cấu hình Cloudinary (Lấy từ file .env)
cloudinary.config({
  cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
  api_key: process.env.CLOUDINARY_API_KEY,
  api_secret: process.env.CLOUDINARY_API_SECRET
});

// [AN TOÀN] Giới hạn riêng theo loại file — chặt hơn mức trần chung ở Multer,
// để tránh 1 ảnh/video khổng lồ âm thầm ăn hết dung lượng Cloudinary.
const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
const MAX_VIDEO_BYTES = 40 * 1024 * 1024;
const MAX_VIDEO_SECONDS = 30;

exports.uploadImage = async (req, res) => {
    try {
        const file = req.file;
        if (!file) return res.status(400).json({ success: false, message: 'Chưa chọn file nào' });

        const isVideo = file.mimetype?.startsWith('video/');

        // [AN TOÀN] Chặn theo dung lượng TRƯỚC khi tốn công/tiền upload lên Cloudinary
        const limit = isVideo ? MAX_VIDEO_BYTES : MAX_IMAGE_BYTES;
        if (file.size > limit) {
            return res.status(413).json({
                success: false,
                message: `${isVideo ? 'Video' : 'Ảnh'} quá lớn — tối đa ${limit / (1024 * 1024)}MB.`,
            });
        }

        // 2. Hàm upload Stream lên Cloudinary
        // Cloudinary không hỗ trợ upload trực tiếp Buffer, nên phải dùng streamifier để chuyển đổi
        const uploadToCloudinary = (buffer) => {
            return new Promise((resolve, reject) => {
                const options = {
                    folder: 'brown_products', // Tên thư mục chứa file trên Cloudinary
                    resource_type: 'auto',    // Tự động nhận diện (ảnh/video)
                };
                if (isVideo) {
                    // [AN TOÀN] Giới hạn cứng độ phân giải video — dù nguồn là 4K/8K thì file lưu
                    // trên Cloudinary vẫn bị ép về tối đa 1280px chiều rộng (crop:'limit' chỉ thu
                    // nhỏ, không phóng to video nhỏ hơn), giữ dung lượng lưu trữ trong tầm kiểm soát.
                    options.transformation = [{ width: 1920, crop: 'limit', quality: 'auto:good' }];
                } else {
                    // Chỉ ép format webp + nén ảnh khi file là ẢNH.
                    // Ép format webp lên VIDEO sẽ làm hỏng file (webp là định dạng ảnh).
                    options.format = 'webp';
                    options.transformation = [{ quality: 'auto:good', fetch_format: 'auto' }];
                }

                const uploadStream = cloudinary.uploader.upload_stream(options, (error, result) => {
                    if (error) return reject(error);
                    resolve(result);
                });
                // Đẩy buffer vào luồng upload
                streamifier.createReadStream(buffer).pipe(uploadStream);
            });
        };

        // 3. Thực hiện upload
        const result = await uploadToCloudinary(file.buffer);

        // [AN TOÀN] Kiểm tra lại thời lượng SAU khi upload (Cloudinary trả về `duration` cho
        // video) — phòng trường hợp validate phía trình duyệt bị bỏ qua (DevTools, app khác...).
        // Nếu vượt quá, xóa ngay file vừa tải lên để không tốn dung lượng lưu trữ vô ích.
        if (isVideo && result.duration && result.duration > MAX_VIDEO_SECONDS) {
            cloudinary.uploader.destroy(result.public_id, { resource_type: 'video' }).catch((e) =>
                console.error('Lỗi xóa video quá thời lượng:', e.message)
            );
            return res.status(400).json({
                success: false,
                message: `Video dài ${Math.round(result.duration)}s — tối đa ${MAX_VIDEO_SECONDS}s.`,
            });
        }

        console.log("✅ Cloudinary Upload thành công:", result.secure_url);

        // 4. Trả về đúng format cũ để Frontend không bị lỗi
        res.json({
            success: true,
            url: result.secure_url
        });

    } catch (error) {
        console.error("Cloudinary Upload Error:", error);
        res.status(500).json({ success: false, message: 'Lỗi upload lên Cloudinary: ' + error.message });
    }
};
