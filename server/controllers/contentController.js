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

        // Validation cơ bản
        if (!image_url) {
            return res.status(400).json({ success: false, message: "Thiếu đường dẫn ảnh!" });
        }
        
        const { data, error } = await supabase
            .from('content_banners')
            .insert([{ 
                title: title || '', 
                image_url, 
                link_to: link_to || '', 
                display_order: Number(display_order) || 0,
                is_active: true
            }])
            .select();

        if (error) {
            console.error("Supabase Insert Error:", error); // Log lỗi ra terminal để dễ debug
            throw error;
        }

        // Xóa Cache để trang chủ cập nhật ngay
        const { clearCache } = require('../middleware/cacheMiddleware'); // Import hàm xóa cache
        // Lưu ý: Đảm bảo bạn đã export clearCache từ cacheMiddleware.js
        // Nếu không import được thì tạm thời comment dòng này lại
        try { clearCache('/api/content/banners'); } catch(e) {}

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

// =====================================================================
// LOOKBOOK (editorial) — mirror banners, có thêm image_url_2 cho slider
// =====================================================================

// 1. Lấy danh sách Lookbook (Public)
exports.getLookbook = async (req, res) => {
    try {
        const { data, error } = await supabase
            .from('content_lookbook')
            .select('*')
            .eq('is_active', true)
            .order('display_order', { ascending: true });

        if (error) throw error;
        res.json({ success: true, data: data });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// 2. Thêm mục Lookbook (Admin)
exports.createLookbook = async (req, res) => {
    try {
        const { title, caption, image_url, image_url_2, display_order, block_type } = req.body;
        const type = block_type || (image_url_2 ? 'compare' : 'full');

        // Khối "quote" (câu trích dẫn) không cần ảnh; các loại khác bắt buộc có ảnh/video chính.
        if (type !== 'quote' && !image_url) {
            return res.status(400).json({ success: false, message: "Thiếu đường dẫn ảnh!" });
        }

        const { data, error } = await supabase
            .from('content_lookbook')
            .insert([{
                title: title || '',
                caption: caption || '',
                image_url: image_url || null,
                image_url_2: image_url_2 || null,
                display_order: Number(display_order) || 0,
                block_type: type,
                is_active: true
            }])
            .select();

        if (error) {
            console.error("Supabase Insert Error (lookbook):", error);
            throw error;
        }

        try { clearCache('/api/content/lookbook'); } catch (e) {}
        res.json({ success: true, data: data[0] });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// 3. Xóa mục Lookbook (Admin)
exports.deleteLookbook = async (req, res) => {
    try {
        const { id } = req.params;
        const { error } = await supabase.from('content_lookbook').delete().eq('id', id);
        if (error) throw error;

        clearCache('/api/content/lookbook');
        res.json({ success: true, message: 'Đã xóa mục lookbook' });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// 4. Cập nhật mục Lookbook (Admin - tắt/bật, sửa...)
exports.updateLookbook = async (req, res) => {
    try {
        const { id } = req.params;
        const updates = req.body;

        const { error } = await supabase
            .from('content_lookbook')
            .update(updates)
            .eq('id', id);

        if (error) throw error;

        clearCache('/api/content/lookbook');
        res.json({ success: true, message: 'Cập nhật thành công' });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};