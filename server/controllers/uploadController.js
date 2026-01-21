// server/controllers/uploadController.js
const supabase = require('../config/supabase');

exports.uploadImage = async (req, res) => {
    try {
        const file = req.file;
        if (!file) return res.status(400).json({ success: false, message: 'No file uploaded' });

        // 1. Tạo tên file ngẫu nhiên
        const fileExt = file.originalname.split('.').pop();
        const fileName = `${Date.now()}-${Math.round(Math.random() * 1E9)}.${fileExt}`;

        // 2. Upload lên Supabase
        const { error } = await supabase
            .storage
            .from('products') // Đảm bảo tên bucket đúng là 'products'
            .upload(fileName, file.buffer, {
                contentType: file.mimetype,
                upsert: false
            });

        if (error) {
            console.error("Supabase Upload Error:", error);
            throw error;
        }

        // 3. Lấy Public URL (QUAN TRỌNG NHẤT)
        const { data } = supabase
            .storage
            .from('products')
            .getPublicUrl(fileName);

        // Log ra terminal để bạn kiểm tra
        console.log("✅ Upload thành công. Link:", data.publicUrl);

        // 4. Trả về cho Frontend (Frontend đang đợi biến tên là 'url')
        res.json({ 
            success: true, 
            url: data.publicUrl  // <--- DÒNG NÀY PHẢI CÓ
        });

    } catch (error) {
        console.error('Upload Controller Error:', error.message);
        res.status(500).json({ success: false, message: error.message });
    }
};