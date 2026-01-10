const supabase = require('../config/supabase');

// --- XỬ LÝ KHO / CHI NHÁNH (STORES) ---
exports.getStores = async (req, res) => {
    try {
        const { data, error } = await supabase.from('stores').select('*');
        if (error) throw error;
        res.json({ success: true, data });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

exports.createStore = async (req, res) => {
    try {
        const { name, address } = req.body;
        const { data, error } = await supabase.from('stores').insert([{ name, address }]).select();
        if (error) throw error;
        res.json({ success: true, data: data[0] });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// --- XỬ LÝ NHÀ CUNG CẤP (SUPPLIERS) ---
// Đã cập nhật theo bảng mới: name, address, phone
exports.getSuppliers = async (req, res) => {
    try {
        const { data, error } = await supabase
            .from('suppliers')
            .select('*')
            .order('created_at', { ascending: false });
            
        if (error) throw error;
        res.json({ success: true, data });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

exports.createSupplier = async (req, res) => {
    try {
        // Nhận đúng 3 trường dữ liệu từ Frontend
        const { name, address, phone } = req.body;
        
        if (!name) {
             return res.status(400).json({ success: false, message: 'Tên nhà cung cấp là bắt buộc' });
        }

        const { data, error } = await supabase
            .from('suppliers')
            .insert([{ name, address, phone }]) // Insert đúng cột
            .select();

        if (error) throw error;
        res.json({ success: true, data: data[0] });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};