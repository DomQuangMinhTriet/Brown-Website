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
        
        console.log(`🔍 Checking voucher: ${code} | Cart: ${cartTotal}`); // Log để debug

        // 1. Tìm mã trong DB (Chuyển hết về chữ hoa để so sánh)
        const { data: promo, error } = await supabase
            .from('promotions')
            .select('*')
            .eq('code', code.toUpperCase().trim()) // Trim bỏ khoảng trắng thừa
            .maybeSingle(); // Dùng maybeSingle để không throw lỗi nếu không tìm thấy

        // 2. Kiểm tra nếu không tìm thấy
        if (error || !promo) {
            console.log("❌ Không tìm thấy mã trong DB");
            return res.status(400).json({ success: false, message: "Mã khuyến mãi không tồn tại" });
        }

        console.log("✅ Tìm thấy mã:", promo);

        // 3. Logic Validate chi tiết
        const now = new Date();
        const startDate = new Date(promo.start_date);
        
        // Xử lý ngày kết thúc: Set về 23:59:59 của ngày đó để khách dùng được đến hết ngày
        const endDate = new Date(promo.end_date);
        endDate.setHours(23, 59, 59, 999);

        // Check 1: Ngày bắt đầu
        if (startDate > now) {
            return res.status(400).json({ success: false, message: "Mã chưa đến thời gian áp dụng" });
        }

        // Check 2: Ngày kết thúc
        if (endDate < now) {
            return res.status(400).json({ success: false, message: "Mã đã hết hạn sử dụng" });
        }

        // Check 3: Số lượng
        if (promo.used_count >= promo.usage_limit) {
            return res.status(400).json({ success: false, message: "Mã đã hết lượt sử dụng" });
        }

        // Check 4: Giá trị đơn tối thiểu
        if (cartTotal < promo.min_order_value) {
            return res.status(400).json({ 
                success: false, 
                message: `Đơn hàng phải từ ${new Intl.NumberFormat('vi-VN').format(promo.min_order_value)}đ mới được dùng mã này` 
            });
        }

        // 4. Tính toán số tiền giảm
        console.log("Loại mã trong DB:", promo.discount_type); // <--- LOG ĐỂ KIỂM TRA

        let discountAmount = 0;
        
        // SỬA ĐOẠN NÀY: So sánh linh hoạt hơn (chấp nhận cả 'percent', 'percentage', 'PERCENT')
        const type = promo.discount_type ? promo.discount_type.toLowerCase() : '';

        if (type === 'percent' || type === 'percentage') {
            // --- LOGIC PHẦN TRĂM ---
            console.log("Đang tính theo %:", promo.discount_value);
            discountAmount = (cartTotal * promo.discount_value) / 100;
            
            // Kiểm tra giảm tối đa
            if (promo.max_discount_amount && promo.max_discount_amount > 0) {
                discountAmount = Math.min(discountAmount, promo.max_discount_amount);
            }
        } else {
            // --- LOGIC TIỀN MẶT (Mặc định) ---
            console.log("Đang tính theo tiền mặt:", promo.discount_value);
            discountAmount = promo.discount_value;
        }

        // Đảm bảo không giảm quá giá trị đơn hàng
        discountAmount = Math.min(discountAmount, cartTotal);

        res.json({
            success: true,
            data: {
                promo: promo,
                discountAmount: Math.floor(discountAmount) // Làm tròn số nguyên
            }
        });

    } catch (error) {
        console.error("Check Voucher Error:", error);
        res.status(500).json({ success: false, message: "Lỗi hệ thống khi kiểm tra mã" });
    }
};