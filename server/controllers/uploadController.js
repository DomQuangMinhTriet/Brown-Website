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

exports.uploadImage = async (req, res) => {
    try {
        const file = req.file;
        if (!file) return res.status(400).json({ success: false, message: 'Chưa chọn file nào' });

        // 2. Hàm upload Stream lên Cloudinary
        // Cloudinary không hỗ trợ upload trực tiếp Buffer, nên phải dùng streamifier để chuyển đổi
        const isVideo = file.mimetype?.startsWith('video/');

        const uploadToCloudinary = (buffer) => {
            return new Promise((resolve, reject) => {
                const options = {
                    folder: 'brown_products', // Tên thư mục chứa file trên Cloudinary
                    resource_type: 'auto',    // Tự động nhận diện (ảnh/video)
                };
                // [SỬA LỖI] Chỉ ép format webp + nén ảnh khi file là ẢNH.
                // Ép format webp lên VIDEO sẽ làm hỏng file (webp là định dạng ảnh).
                if (isVideo) {
                    options.transformation = [{ quality: 'auto' }];
                } else {
                    options.format = 'webp';
                    options.transformation = [{ quality: 'auto', fetch_format: 'auto' }];
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

        console.log("✅ Cloudinary Upload thành công:", result.secure_url);

        // 4. Trả về đúng format cũ để Frontend không bị lỗi
        res.json({ 
            success: true, 
            url: result.secure_url 
        });

    } catch (error) {
        console.error("Cloudinary Upload Error:", error);
        res.status(500).json({ success: false, message: 'Lỗi upload ảnh lên Cloudinary: ' + error.message });
    }
};