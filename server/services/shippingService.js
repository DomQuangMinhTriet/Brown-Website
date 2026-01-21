<<<<<<< HEAD
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
=======
const axios = require('axios');

const calculateShippingFee = async (toDistrictId, toWardCode, weight = 500) => {
  // 1. Cấu hình mặc định
  const DEFAULT_FEE = 30000; // Phí ship cứng 30k
  const SHOP_ID = process.env.GHN_SHOP_ID;
  const TOKEN = process.env.GHN_API_TOKEN;

  // 2. Kiểm tra biến môi trường
  if (!TOKEN) {
    console.warn('⚠️ SHIPPING: Chưa cấu hình GHN_API_TOKEN. Dùng phí mặc định 30k.');
    return DEFAULT_FEE;
  }

  // 3. [QUAN TRỌNG] Logic xử lý dữ liệu đầu vào
  // Nếu Frontend chưa gửi ID Quận/Huyện (undefined/null), ta trả về phí mặc định ngay
  // để tránh gọi API GHN bị lỗi 400.
  if (!toDistrictId || isNaN(parseInt(toDistrictId)) || !toWardCode) {
    console.log('ℹ️ SHIPPING: Khách chưa chọn Quận/Huyện cụ thể (No ID). Dùng phí mặc định 30k.');
    return DEFAULT_FEE;
  }

  // 4. Chỉ gọi API khi đã có đầy đủ ID
  try {
    const response = await axios.post(
      'https://online-gateway.ghn.vn/shiip/public-api/v2/shipping-order/fee',
      {
        "service_type_id": 2, // Giao chuẩn
        "to_district_id": parseInt(toDistrictId),
        "to_ward_code": String(toWardCode),
        "height": 10, "length": 10, "width": 10, "weight": parseInt(weight),
        "insurance_value": 0,
        "coupon": null 
      },
      { 
        headers: { 
            'token': TOKEN, 
            'shop_id': SHOP_ID 
        } 
      }
    );
    
    if(response.data.code === 200) {
        console.log('✅ GHN: Tính phí thành công:', response.data.data.total);
        return response.data.data.total;
    } else {
        return DEFAULT_FEE;
    }

  } catch (error) {
    // Luôn fallback về phí mặc định để khách mua được hàng dù API lỗi
    console.error('❌ Lỗi kết nối GHN:', error.response?.data?.message || error.message);
    return DEFAULT_FEE; 
  }
};

module.exports = { calculateShippingFee };
>>>>>>> Frontend
