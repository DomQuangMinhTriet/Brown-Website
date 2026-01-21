<<<<<<< HEAD
=======
// server/controllers/uploadController.js
>>>>>>> Frontend
const supabase = require('../config/supabase');

exports.uploadImage = async (req, res) => {
    try {
        const file = req.file;
<<<<<<< HEAD
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
=======
        if (!file) return res.status(400).json({ success: false, message: 'No file uploaded' });

        // 1. Tạo tên file ngẫu nhiên
        const fileExt = file.originalname.split('.').pop();
        const fileName = `${Date.now()}-${Math.round(Math.random() * 1E9)}.${fileExt}`;

        // 2. Upload lên Supabase
        const { error } = await supabase
            .storage
            .from('products') // Đảm bảo tên bucket đúng là 'products'
            .upload(fileName, file.buffer, {
>>>>>>> Frontend
                contentType: file.mimetype,
                upsert: false
            });

<<<<<<< HEAD
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
=======
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
>>>>>>> Frontend
        res.status(500).json({ success: false, message: error.message });
    }
};