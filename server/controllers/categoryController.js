const supabase = require('../config/supabase');
const translate = require('translate-google');

// Hàm helper tự động dịch danh mục
const autoTranslate = async (text) => {
    if (!text || text.trim() === '') return '';
    try {
        return await translate(text, { from: 'vi', to: 'en' });
    } catch (err) {
        console.error('Lỗi dịch tự động danh mục:', err);
        return text; // Fallback giữ nguyên tiếng Việt nếu lỗi mạng
    }
};

// 1. Lấy danh sách danh mục
exports.getCategories = async (req, res) => {
    try {
        const { data, error } = await supabase
            .from('categories')
            .select('*')
            .order('created_at', { ascending: false }); // Mới nhất lên đầu

        if (error) throw error;

        res.json({ success: true, data: data });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// 2. Tạo danh mục mới
// Hàm tạo danh mục
exports.createCategory = async (req, res) => {
    try {
        const { name, slug } = req.body;

        if (!name || !slug) {
            return res.status(400).json({ success: false, message: 'Tên và slug là bắt buộc' });
        }

        // --- 1. DỊCH TỰ ĐỘNG ---
        let name_en = name; // Mặc định lấy tiếng Việt
        try {
            name_en = await translate(name, { from: 'vi', to: 'en' });
        } catch (err) {
            console.error("Lỗi dịch danh mục:", err);
        }

        // --- 2. LƯU VÀO DATABASE ---
        const { data: newCategory, error } = await supabase
            .from('categories')
            .insert([{ 
                name, 
                slug,
                name_en // <--- Lưu thêm tên tiếng Anh
            }])
            .select()
            .single();

        if (error) throw error;

        res.status(201).json({ success: true, data: newCategory });
    } catch (error) {
        console.error(error);
        res.status(500).json({ success: false, message: 'Lỗi máy chủ' });
    }
};

// 3. Xóa danh mục
exports.deleteCategory = async (req, res) => {
    try {
        const { id } = req.params;
        const { error } = await supabase.from('categories').delete().eq('id', id);
        if (error) throw error;
        res.json({ success: true, message: 'Đã xóa thành công' });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// 4. [MỚI] Toggle ẩn/hiện danh mục trên web
exports.toggleCategoryVisibility = async (req, res) => {
    try {
        const { id } = req.params;
        const { is_visible_on_home } = req.body;
        
        const { data, error } = await supabase
            .from('categories')
            .update({ is_visible_on_home })
            .eq('id', id)
            .select();
            
        if (error) throw error;
        res.json({ success: true, data: data[0] });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};