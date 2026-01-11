const supabase = require('../config/supabase');

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
exports.createCategory = async (req, res) => {
    try {
        const { name, slug } = req.body;
        if (!name || !slug) {
            return res.status(400).json({ success: false, message: 'Thiếu tên hoặc slug!' });
        }

        const { data, error } = await supabase
            .from('categories')
            .insert([{ name, slug }])
            .select();

        if (error) throw error;

        res.json({ success: true, data: data[0] });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
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