// server/services/shippingService.js
const axios = require('axios');
const crypto = require('crypto');

const SPX_URL = process.env.SPX_API_URL || 'https://mock-api.spx.vn'; // Fallback nếu chưa có
const CLIENT_ID = process.env.SPX_CLIENT_ID;
const SECRET_KEY = process.env.SPX_SECRET_KEY;

// Hàm tạo chữ ký bảo mật (Signature) - Thường bắt buộc
const generateSignature = (payload, timestamp) => {
    const rawString = `${CLIENT_ID}${timestamp}${JSON.stringify(payload)}`;
    return crypto.createHmac('sha256', SECRET_KEY).update(rawString).digest('hex');
};

// 1. TÍNH PHÍ VẬN CHUYỂN (ESTIMATE FEE)
const calculateShippingFee = async (toDistrict, toWard, weight = 1000) => {
    try {
        const payload = {
            service_type: "standard",
            weight: weight, // gram
            recipient_address: {
                district: toDistrict,
                ward: toWard,
                city: "Hồ Chí Minh" // Hoặc lấy từ tham số nếu cần
            }
        };

        // Nếu chưa có key thật, trả về giả lập thông minh
        if (!SECRET_KEY) {
            console.log("⚠️ Chưa cấu hình SPX Key, dùng phí giả lập.");
            return (toDistrict.includes('Hồ Chí Minh') || toDistrict.includes('HCM')) ? 16500 : 32000;
        }

        const timestamp = Math.floor(Date.now() / 1000);
        const signature = generateSignature(payload, timestamp);

        const response = await axios.post(`${SPX_URL}/calculate_fee`, payload, {
            headers: {
                'X-Client-ID': CLIENT_ID,
                'X-Signature': signature,
                'X-Timestamp': timestamp
            }
        });

        return response.data.total_fee; // Giả sử API trả về field này

    } catch (error) {
        console.error("❌ Lỗi tính phí SPX:", error.response?.data || error.message);
        // Fallback: Trả về phí mặc định để không chặn khách mua hàng
        return 35000; 
    }
};

// 2. TẠO ĐƠN HÀNG & LẤY MÃ VẬN ĐƠN (CREATE ORDER)
const createShippingOrder = async (order) => {
    try {
        console.log(`🚚 Đang đẩy đơn ${order.code} sang Shopee Express...`);

        const payload = {
            client_order_code: order.code,
            cod_amount: order.payment_method === 'cod' ? order.total_amount : 0,
            weight: 1000, // Cần tính tổng trọng lượng từ items nếu muốn chính xác
            sender_info: {
                shop_id: process.env.SHOP_ID
            },
            recipient_info: {
                name: order.customer_name,
                phone: order.customer_phone,
                address: order.customer_address
            },
            items: order.order_items // Danh sách sản phẩm
        };

        // Nếu chưa có key thật -> Trả về mã giả lập nhưng có log rõ ràng
        if (!SECRET_KEY) {
            const mockCode = `SPXVN${Date.now().toString().slice(-8)}`;
            console.log("⚠️ DEV MODE: Tạo mã vận đơn giả lập:", mockCode);
            return mockCode;
        }

        const timestamp = Math.floor(Date.now() / 1000);
        const signature = generateSignature(payload, timestamp);

        const response = await axios.post(`${SPX_URL}/order/create`, payload, {
            headers: {
                'X-Client-ID': CLIENT_ID,
                'X-Signature': signature,
                'X-Timestamp': timestamp
            }
        });

        if (response.data && response.data.tracking_number) {
            console.log("✅ Tạo đơn SPX thành công:", response.data.tracking_number);
            return response.data.tracking_number;
        } else {
            throw new Error("API không trả về tracking_number");
        }

    } catch (error) {
        console.error("❌ Lỗi tạo đơn SPX:", error.response?.data || error.message);
        return null; // Trả về null để xử lý sau (Admin tự đẩy tay)
    }
};

module.exports = { calculateShippingFee, createShippingOrder };