// Import client đã cấu hình sẵn (Lưu ý đường dẫn ../config/supabase)
const supabase = require('../config/supabase');

// Lấy danh sách
exports.getProducts = async (req, res) => {
    try {
        const { data, error } = await supabase.from('products').select('*');
        if (error) throw error;
        res.json({ success: true, count: data.length, data: data });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
};

// Lấy chi tiết
exports.getProductBySlug = async (req, res) => {
    try {
        const { slug } = req.params;
        const { data, error } = await supabase
            .from('products')
            .select(`*, variants(*)`) // Lấy kèm biến thể
            .eq('slug', slug)
            .single();
            
        if (error) throw error;
        res.json({ success: true, data: data });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
};