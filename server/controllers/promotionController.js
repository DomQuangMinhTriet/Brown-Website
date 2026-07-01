const supabase = require('../config/supabase');

// =====================================================================
// HELPER: Đánh giá voucher theo danh sách sản phẩm trong giỏ (dùng chung
// cho check (client) và tạo đơn (server) để logic luôn nhất quán).
//
// lineItems: [{ product_id, quantity, unit_price, on_discount }]
//   - unit_price: giá 1 đơn vị SAU khi đã trừ giảm giá trực tiếp của SP (nếu có)
//   - on_discount: true nếu SP đang được giảm giá trực tiếp
//
// Quy tắc (đã chốt với chủ shop):
//   - Voucher chỉ tính giảm trên TIỀN CỦA CÁC SP ĐƯỢC CHỌN (applicable_product_ids).
//     Nếu danh sách rỗng => áp cho mọi SP.
//   - KHÔNG cho voucher chồng lên SP đang giảm giá trực tiếp (loại các SP đó ra).
// =====================================================================
async function evaluateVoucher(code, lineItems) {
    const { data: promo } = await supabase
        .from('promotions')
        .select('*')
        .eq('code', code.toUpperCase().trim())
        .maybeSingle();

    if (!promo) return { ok: false, message: 'Mã khuyến mãi không tồn tại' };
    if (promo.is_active === false) return { ok: false, message: 'Mã đã bị tắt' };

    const now = new Date();
    if (promo.start_date && new Date(promo.start_date) > now) {
        return { ok: false, message: 'Mã chưa đến thời gian áp dụng' };
    }
    if (promo.end_date) {
        const endDate = new Date(promo.end_date);
        endDate.setHours(23, 59, 59, 999);
        if (endDate < now) return { ok: false, message: 'Mã đã hết hạn sử dụng' };
    }
    // usage_limit = null nghĩa là KHÔNG giới hạn số lượng
    if (promo.usage_limit != null && (promo.used_count || 0) >= promo.usage_limit) {
        return { ok: false, message: 'Mã đã hết lượt sử dụng' };
    }

    const cartTotal = lineItems.reduce((s, li) => s + li.unit_price * li.quantity, 0);
    if (cartTotal < (promo.min_order_value || 0)) {
        return {
            ok: false,
            message: `Đơn hàng phải từ ${new Intl.NumberFormat('vi-VN').format(promo.min_order_value)}đ mới được dùng mã này`,
        };
    }

    const applicable = Array.isArray(promo.applicable_product_ids)
        ? promo.applicable_product_ids.map(Number)
        : [];

    // Phần tiền được tính giảm: SP KHÔNG đang giảm giá trực tiếp
    // và (nếu có danh sách áp dụng) phải nằm trong danh sách đó.
    const eligibleItems = lineItems.filter(li =>
        !li.on_discount && (applicable.length === 0 || applicable.includes(Number(li.product_id)))
    );
    const eligibleSubtotal = eligibleItems.reduce((s, li) => s + li.unit_price * li.quantity, 0);

    if (eligibleSubtotal <= 0) {
        return {
            ok: false,
            message: applicable.length > 0
                ? 'Mã chỉ áp dụng cho một số sản phẩm không có trong giỏ (hoặc các sản phẩm đó đang được giảm giá trực tiếp)'
                : 'Không có sản phẩm nào đủ điều kiện áp mã (các sản phẩm đang được giảm giá trực tiếp không được cộng dồn voucher)',
        };
    }

    const type = promo.discount_type ? promo.discount_type.toLowerCase() : '';
    let discountAmount = 0;
    if (type === 'percent' || type === 'percentage') {
        discountAmount = (eligibleSubtotal * promo.discount_value) / 100;
        if (promo.max_discount_amount && promo.max_discount_amount > 0) {
            discountAmount = Math.min(discountAmount, promo.max_discount_amount);
        }
    } else {
        discountAmount = promo.discount_value;
    }
    discountAmount = Math.min(discountAmount, eligibleSubtotal);

    return { ok: true, promo, discountAmount: Math.floor(discountAmount) };
}

exports.evaluateVoucher = evaluateVoucher;

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
        const { code, discount_type, discount_value, min_order_value, max_discount_amount, start_date, end_date, usage_limit, applicable_product_ids } = req.body;

        const { data, error } = await supabase.from('promotions').insert([{
            code: code.toUpperCase(),
            discount_type,
            discount_value,
            min_order_value: min_order_value || 0,
            max_discount_amount,
            start_date: start_date || null,
            end_date: end_date || null,                 // null = không giới hạn thời gian
            usage_limit: usage_limit == null || usage_limit === '' ? null : Number(usage_limit), // null = không giới hạn số lượng
            applicable_product_ids: Array.isArray(applicable_product_ids) ? applicable_product_ids.map(Number) : [], // [] = áp cho mọi SP
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
// Body: { code, items: [{ product_id, quantity }] }  (ưu tiên)  hoặc { code, cartTotal } (fallback cũ)
exports.checkVoucher = async (req, res) => {
    try {
        const { code, items, cartTotal } = req.body;
        if (!code) return res.status(400).json({ success: false, message: "Thiếu mã" });

        let lineItems = [];

        if (Array.isArray(items) && items.length > 0) {
            // Lấy giá gốc + trạng thái giảm giá của các SP từ DB (không tin giá client gửi lên)
            const productIds = [...new Set(items.map(i => i.product_id).filter(Boolean))];
            const { data: products } = await supabase
                .from('products')
                .select('id, base_price, discount_amount, is_discount_active')
                .in('id', productIds.length ? productIds : [-1]);

            const pmap = {};
            (products || []).forEach(p => { pmap[p.id] = p; });

            lineItems = items.map(i => {
                const p = pmap[i.product_id];
                if (!p) return null;
                const onDiscount = p.is_discount_active && Number(p.discount_amount) > 0;
                const unit = onDiscount
                    ? Math.max(0, Number(p.base_price) - Number(p.discount_amount))
                    : Number(p.base_price);
                return { product_id: i.product_id, quantity: Number(i.quantity) || 1, unit_price: unit, on_discount: onDiscount };
            }).filter(Boolean);
        } else if (cartTotal != null) {
            // Fallback tương thích client cũ: coi cả giỏ như 1 dòng, không thuộc SP giảm giá
            lineItems = [{ product_id: null, quantity: 1, unit_price: Number(cartTotal), on_discount: false }];
        }

        if (lineItems.length === 0) {
            return res.status(400).json({ success: false, message: "Giỏ hàng trống hoặc sản phẩm không hợp lệ" });
        }

        const result = await evaluateVoucher(code, lineItems);
        if (!result.ok) {
            return res.status(400).json({ success: false, message: result.message });
        }

        res.json({
            success: true,
            data: { promo: result.promo, discountAmount: result.discountAmount }
        });
    } catch (error) {
        console.error("Check Voucher Error:", error);
        res.status(500).json({ success: false, message: "Lỗi hệ thống khi kiểm tra mã" });
    }
};