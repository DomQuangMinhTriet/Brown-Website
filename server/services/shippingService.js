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
