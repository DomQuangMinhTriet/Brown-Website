const supabase = require('../config/supabase');

// 1. Lấy danh sách phiếu chi
exports.getExpenses = async (req, res) => {
    try {
        const { data, error } = await supabase
            .from('expenses')
            .select(`
                *,
                expense_categories (name),
                stores (name)
            `)
            .order('expense_date', { ascending: false });

        if (error) throw error;
        res.json({ success: true, data });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// 2. Lấy danh mục chi phí (để hiện dropdown)
exports.getCategories = async (req, res) => {
    try {
        const { data, error } = await supabase.from('expense_categories').select('*');
        if (error) throw error;
        res.json({ success: true, data });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// 3. Tạo phiếu chi mới
exports.createExpense = async (req, res) => {
    try {
        const { store_id, category_id, amount, note, expense_date } = req.body;

        if (!amount || !category_id) {
            return res.status(400).json({ success: false, message: 'Thiếu thông tin bắt buộc!' });
        }

        const { data, error } = await supabase
            .from('expenses')
            .insert([{
                store_id,
                category_id,
                amount,
                note,
                expense_date: expense_date || new Date()
            }])
            .select();

        if (error) throw error;
        res.json({ success: true, message: 'Đã lưu phiếu chi', data: data[0] });

    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// 4. Xóa phiếu chi
exports.deleteExpense = async (req, res) => {
    try {
        const { id } = req.params;
        const { error } = await supabase.from('expenses').delete().eq('id', id);
        if (error) throw error;
        res.json({ success: true, message: 'Đã xóa thành công' });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
<<<<<<< HEAD
=======
};

// 5. [MỚI] Tạo danh mục chi phí
exports.createCategory = async (req, res) => {
    try {
        const { name } = req.body;
        if (!name) return res.status(400).json({ success: false, message: "Tên danh mục không được để trống" });

        // Insert vào bảng expense_categories
        const { data, error } = await supabase
            .from('expense_categories')
            .insert([{ name }])
            .select()
            .single();

        if (error) throw error;
        res.json({ success: true, data });

    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
>>>>>>> Frontend
};