const axios = require('axios');

// Hàm tạo đơn hàng bên SPX (Hiện tại là giả lập)
const createSPXOrder = async (orderData) => {
    console.log("🚚 Đang gửi yêu cầu tạo đơn sang SPX...", orderData.code);

    // --- PHẦN NÀY LÀ CẤU HÌNH API THẬT (Khi nào có Key thì dùng) ---
    /*
    const apiUrl = 'https://open.spx.co.id/api/v1/order/create'; // URL ví dụ
    const apiKey = process.env.SPX_API_KEY;
    
    const payload = {
        consignee: {
            name: orderData.customer_name,
            phone: orderData.customer_phone,
            address: orderData.shipping_address,
            // ... các trường khác theo tài liệu SPX
        },
        weight: 1000, // Cân nặng
        cod_amount: orderData.payment_method === 'cod' ? orderData.total_amount : 0
    };

    try {
        const response = await axios.post(apiUrl, payload, { headers: { Authorization: apiKey } });
        return response.data.tracking_number;
    } catch (error) {
        throw new Error('Lỗi kết nối SPX API');
    }
    */
    // -----------------------------------------------------------

    // --- PHẦN GIẢ LẬP (MOCK) ĐỂ CODE CHẠY ĐƯỢC NGAY ---
    return new Promise((resolve) => {
        setTimeout(() => {
            // Giả vờ SPX trả về mã vận đơn ngẫu nhiên
            const mockTrackingCode = `SPX${Math.floor(Math.random() * 1000000000)}`;
            console.log("✅ SPX đã tạo đơn thành công. Tracking Code:", mockTrackingCode);
            resolve(mockTrackingCode);
        }, 1000); // Giả lập độ trễ mạng 1 giây
    });
};

module.exports = { createSPXOrder };