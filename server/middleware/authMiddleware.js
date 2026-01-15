const supabase = require('../config/supabase');

// Middleware kiểm tra xem User đã đăng nhập chưa
const requireAuth = async (req, res, next) => {
    try {
        // 1. Lấy token từ Header (Format: "Bearer <token>")
        const authHeader = req.headers.authorization;
        if (!authHeader) {
            return res.status(401).json({ success: false, message: 'Thiếu Token xác thực' });
        }

        const token = authHeader.split(' ')[1];

        // 2. Gọi Supabase để verify token
        const { data: { user }, error } = await supabase.auth.getUser(token);

        if (error || !user) {
            return res.status(401).json({ success: false, message: 'Token không hợp lệ hoặc hết hạn' });
        }

        // 3. Nếu OK, gắn thông tin user vào biến req để các hàm sau dùng
        req.user = user;
        
        console.log("🔐 Authenticated User:", user.email);
        next(); // Cho phép đi tiếp

    } catch (error) {
        console.error("Auth Error:", error);
        res.status(500).json({ success: false, message: 'Lỗi xác thực server' });
    }
};

module.exports = requireAuth;