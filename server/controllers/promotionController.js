const supabase = require('../config/supabase');

exports.checkVoucher = async (req, res) => {
    try {
        const { code, cartTotal } = req.body;
        const userId = req.user ? req.user.id : null; // Lấy từ middleware auth

        if (!code) return res.status(400).json({ success: false, message: 'Thiếu mã' });

        // 1. Tìm voucher trong DB
        const { data: promo, error } = await supabase
            .from('promotions')
            .select('*')
            .eq('code', code.toUpperCase())
            .single();

        if (error || !promo) {
            return res.status(404).json({ success: false, message: 'Mã không tồn tại' });
        }

        // 2. Validate các điều kiện
        const now = new Date();
        if (new Date(promo.start_date) > now || new Date(promo.end_date) < now) {
            return res.status(400).json({ success: false, message: 'Mã đã hết hạn' });
        }
        
        if (promo.usage_limit > 0 && promo.used_count >= promo.usage_limit) {
            return res.status(400).json({ success: false, message: 'Mã đã hết lượt dùng' });
        }

        if (promo.requires_account && !userId) {
            return res.status(401).json({ success: false, message: 'Voucher này chỉ dành cho thành viên' });
        }

        // 3. Tính tiền giảm
        let discount = 0;
        if (promo.discount_type === 'percentage') {
            discount = cartTotal * (promo.discount_value / 100);
            if (promo.max_discount_amount) {
                discount = Math.min(discount, promo.max_discount_amount);
            }
        } else {
            discount = promo.discount_value;
        }

        res.json({ success: true, data: { discount, code: promo.code } });

    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};