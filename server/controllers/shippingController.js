// Giả lập API tính phí của SPX
exports.calculateFee = async (req, res) => {
    try {
        const { province, weight } = req.body; // province: Tên tỉnh thành
        
        let fee = 30000; // Mặc định liên tỉnh
        
        // Logic giả lập đơn giản
        if (province && (province.includes('Hồ Chí Minh') || province.includes('Sai Gon'))) {
            fee = 15000; // Nội thành rẻ
        } else if (province && (province.includes('Hà Nội') || province.includes('Ha Noi'))) {
            fee = 35000; // Xa
        }

        // Cộng thêm phí nếu nặng
        if (weight > 2000) fee += 10000; 

        res.json({ success: true, data: { fee } });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// Hàm nội bộ để tạo mã vận đơn (Dùng trong orderController)
exports.generateTrackingCode = () => {
    return `SPX${Date.now()}${Math.floor(Math.random() * 1000)}`;
};