const express = require('express');
const router = express.Router();
const customerController = require('../controllers/customerController');
const requireAuth = require('../middleware/authMiddleware'); // <--- Import Middleware

// Các Route Admin (Giữ nguyên hoặc thêm middleware Admin nếu cần)
router.get('/', customerController.getCustomers);
router.get('/:id', customerController.getCustomerDetail); // Lưu ý: Route này có thể xung đột với /profile bên dưới nếu id giống profile
router.get('/:id/history', customerController.getCustomerHistory);

// --- ROUTE CHO KHÁCH HÀNG (Cần đăng nhập) ---
// Đặt route này LÊN TRƯỚC route /:id để tránh bị nhầm 'profile' là 1 cái id
router.get('/me/profile', requireAuth, customerController.getMyProfile);
router.put('/me/profile', requireAuth, customerController.updateMyProfile);

module.exports = router;
router.post('/register', async (req, res) => {
    // Logic đơn giản: Insert vào bảng customers
    // Bạn có thể tách ra controller nếu muốn gọn
    const { user_id, full_name, phone, email } = req.body;
    const supabase = require('../config/supabase');
    
    const { data, error } = await supabase.from('customers').insert({
        user_id, full_name, phone, email
    });
    
    if(error) return res.status(400).json({success: false, error});
    res.json({success: true});
});

module.exports = router;