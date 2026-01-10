const supabase = require('../config/supabase');

exports.uploadImage = async (req, res) => {
    try {
        const file = req.file;
        if (!file) {
            return res.status(400).json({ success: false, message: 'Vui lòng chọn file ảnh!' });
        }

        // 1. Tạo tên file ngẫu nhiên để không bị trùng
        // Ví dụ: 173849_anh-ao-so-mi.jpg
        const fileExt = file.originalname.split('.').pop();
        const fileName = `${Date.now()}_${Math.random().toString(36).substring(2)}.${fileExt}`;
        const filePath = `uploads/${fileName}`; // Lưu vào thư mục con uploads/

        console.log(`📤 Đang upload file: ${fileName}...`);

        // 2. Upload lên Supabase Storage (Bucket 'products')
        // Lưu ý: Tên bucket 'PRODUCTS' phải khớp 100% với trên Supabase
        const { data, error } = await supabase
            .storage
            .from('products')
            .upload(filePath, file.buffer, {
                contentType: file.mimetype,
                upsert: false
            });

        if (error) throw error;

        // 3. Lấy đường dẫn công khai (Public URL)
        const { data: publicUrlData } = supabase
            .storage
            .from('products')
            .getPublicUrl(filePath);

        console.log("✅ Upload thành công:", publicUrlData.publicUrl);

        res.json({
            success: true,
            imageUrl: publicUrlData.publicUrl
        });

    } catch (error) {
        console.error("❌ Lỗi upload:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};