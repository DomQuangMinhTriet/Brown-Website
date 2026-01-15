const supabase = require('../config/supabase');
const { verifyCache, clearCache } = require('../middleware/cacheMiddleware');

// 1. Lấy danh sách Banner (Public)
exports.getBanners = async (req, res) => {
    try {
        // Lấy banner đang hoạt động, sắp xếp theo thứ tự
        const { data, error } = await supabase
            .from('content_banners')
            .select('*')
            .eq('is_active', true)
            .order('display_order', { ascending: true });

        if (error) throw error;
        res.json({ success: true, data: data });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// 2. Thêm Banner mới (Admin)
exports.createBanner = async (req, res) => {
    try {
        const { title, image_url, link_to, display_order } = req.body;
        
        const { data, error } = await supabase
            .from('content_banners')
            .insert([{ title, image_url, link_to, display_order }])
            .select();

        if (error) throw error;

        // Xóa Cache để trang chủ cập nhật ngay
        clearCache('/api/content/banners');

        res.json({ success: true, data: data[0] });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// 3. Xóa Banner (Admin)
exports.deleteBanner = async (req, res) => {
    try {
        const { id } = req.params;
        const { error } = await supabase.from('content_banners').delete().eq('id', id);
        
        if (error) throw error;

        clearCache('/api/content/banners');
        res.json({ success: true, message: 'Đã xóa banner' });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// 4. Cập nhật Banner (Admin - Tắt/Bật, Sửa link...)
exports.updateBanner = async (req, res) => {
    try {
        const { id } = req.params;
        const updates = req.body; // { is_active: false, ... }
        
        const { error } = await supabase
            .from('content_banners')
            .update(updates)
            .eq('id', id);

        if (error) throw error;

        clearCache('/api/content/banners');
        res.json({ success: true, message: 'Cập nhật thành công' });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};