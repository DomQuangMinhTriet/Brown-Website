const supabase = require('../config/supabase');

// 1. Lấy danh sách (Admin)
exports.getAllPromotions = async (req, res) => {
    try {
        const { data, error } = await supabase
            .from('promotions')
            .select('*')
            // SỬA DÒNG NÀY: Đổi 'created_at' thành 'id'
            .order('id', { ascending: false }); 

        if (error) throw error;
        // Luôn trả về mảng (nếu data null thì trả về [])
        res.json({ success: true, data: data || [] });
    } catch (error) {
        console.error("Get Promotions Error:", error.message);
        // Trả về mảng rỗng để Frontend không bị lỗi map()
        res.json({ success: false, message: error.message, data: [] });
    }
};

// 2. Tạo Promotion mới (Admin)
exports.createPromotion = async (req, res) => {
    try {
        // Lấy đúng các trường trong DB bạn đã tạo
        const { code, discount_type, discount_value, min_order_value, max_discount_amount, start_date, end_date, usage_limit } = req.body;
        
        const { data, error } = await supabase.from('promotions').insert([{
            code: code.toUpperCase(),
            discount_type,
            discount_value,
            min_order_value: min_order_value || 0,
            max_discount_amount,
            start_date,
            end_date,
            usage_limit: usage_limit || 100,
            used_count: 0,
            is_active: true
        }]).select();

        if (error) throw error;
        res.json({ success: true, data: data[0] });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// 3. Xóa Promotion (Admin)
exports.deletePromotion = async (req, res) => {
    try {
        const { id } = req.params;
        const { error } = await supabase.from('promotions').delete().eq('id', id);
        if (error) throw error;
        res.json({ success: true, message: "Đã xóa" });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// 4. CHECK VOUCHER (Dùng cho Client)
exports.checkVoucher = async (req, res) => {
    try {
        const { code, cartTotal } = req.body;
        
        // Query DB tìm mã
        const { data: promo, error } = await supabase
            .from('promotions')
            .select('*')
            .eq('code', code.toUpperCase())
            .eq('is_active', true)
            .single();

        if (error || !promo) return res.status(400).json({ success: false, message: "Mã không hợp lệ" });

        // Validate Logic
        const now = new Date();
        if (new Date(promo.start_date) > now) return res.status(400).json({ success: false, message: "Mã chưa bắt đầu" });
        if (new Date(promo.end_date) < now) return res.status(400).json({ success: false, message: "Mã đã hết hạn" });
        if (promo.used_count >= promo.usage_limit) return res.status(400).json({ success: false, message: "Mã đã hết lượt dùng" });
        if (cartTotal < promo.min_order_value) return res.status(400).json({ success: false, message: `Đơn tối thiểu ${new Intl.NumberFormat().format(promo.min_order_value)}đ` });

        // Tính tiền giảm
        let discount = 0;
        
        // SỬA: Đổi điều kiện so sánh thành 'percent'
        if (promo.discount_type === 'percent') { 
            discount = cartTotal * (promo.discount_value / 100);
            
            // Logic max_discount_amount giữ nguyên
            if (promo.max_discount_amount) {
                discount = Math.min(discount, promo.max_discount_amount);
            }
        } else {
            // Trường hợp fixed
            discount = promo.discount_value;
        }

        res.json({ success: true, data: { discountAmount: discount, code: promo.code } });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};