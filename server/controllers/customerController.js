const supabase = require('../config/supabase');

exports.getCustomers = async (req, res) => {
    try {
        const { data, error } = await supabase
            .from('customers')
            .select('*, orders(id, total_amount, created_at)') // Join bảng orders
            .neq('role', 'admin')
            .order('created_at', { ascending: false });
            

        if (error) throw error;

        const enhancedData = data.map(cus => {
            // FIX QUAN TRỌNG: Kiểm tra mảng orders có tồn tại không
            const orders = cus.orders || []; 
            
            return {
                ...cus,
                order_count: orders.length, 
                total_spent: orders.reduce((sum, o) => sum + (Number(o.total_amount) || 0), 0),
                // Lấy ngày mua gần nhất nếu có
                last_order_date: orders.length > 0 ? orders[0].created_at : null 
            };
        });

        res.json({ success: true, data: enhancedData });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// 2. LẤY LỊCH SỬ CHI TIẾT (Fix lỗi truy vấn sai ID)
exports.getCustomerHistory = async (req, res) => {
    try {
        const { id } = req.params; // Đây là customer_id
        
        const { data, error } = await supabase
            .from('orders')
            .select('*')
            .eq('customer_id', id) // Query chính xác theo customer_id
            .order('created_at', { ascending: false });

        if (error) throw error;

        res.json({ success: true, data: data || [] }); // Luôn trả về mảng
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// 2. Lấy chi tiết khách hàng + Lịch sử đơn hàng
exports.getCustomerDetail = async (req, res) => {
    try {
        const { id } = req.params;
        
        // Lấy thông tin khách
        const { data: customer, error: cusError } = await supabase
            .from('customers')
            .select('*')
            .eq('id', id)
            .single();
            
        if (cusError) throw cusError;

        // Lấy lịch sử đơn hàng của khách này (Dựa theo số điện thoại hoặc ID)
        // Vì lúc tạo đơn ta lưu snapshot text, nên tìm theo SĐT là chắc ăn nhất
        const { data: orders, error: ordError } = await supabase
            .from('orders')
            .select('*')
            .eq('customer_phone', customer.phone)
            .order('created_at', { ascending: false });

        if (ordError) throw ordError;

        res.json({ success: true, data: { ...customer, history: orders } });

    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// [MỚI] Lấy thông tin Profile của người đang đăng nhập
exports.getMyProfile = async (req, res) => {
    try {
        const userId = req.user.id; // Lấy từ middleware requireAuth

        // Tìm trong bảng customers dựa trên user_id (link với Auth)
        const { data, error } = await supabase
            .from('customers')
            .select('*')
            .eq('user_id', userId)
            .single();

        if (error) throw error;

        // Lấy thêm lịch sử mua hàng
        const { data: orders } = await supabase
            .from('orders')
            .select('*')
            .eq('customer_email', data.email) // Hoặc query theo customer_id nếu đã link
            .order('created_at', { ascending: false });

        res.json({ 
            success: true, 
            data: { ...data, history: orders } 
        });

    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// [MỚI] Cập nhật Profile
exports.updateMyProfile = async (req, res) => {
    try {
        const userId = req.user.id;
        const { full_name, phone, address } = req.body;

        const { data, error } = await supabase
            .from('customers')
            .update({ full_name, phone, address })
            .eq('user_id', userId)
            .select();

        if (error) throw error;
        res.json({ success: true, message: 'Cập nhật thành công', data: data[0] });

    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};