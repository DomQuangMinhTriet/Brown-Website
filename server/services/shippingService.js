const axios = require('axios');

// const calculateShippingFee = async (toDistrictId, toWardCode, weight = 500) => {
//   // 1. Cấu hình mặc định
//   const DEFAULT_FEE = 30000; 
//   const SHOP_ID = process.env.GHN_SHOP_ID;
//   const TOKEN = process.env.GHN_API_TOKEN;

//   // 2. Kiểm tra biến môi trường
//   if (!TOKEN) {
//     console.warn('⚠️ SHIPPING: Chưa cấu hình GHN_API_TOKEN. Dùng phí mặc định 30k.');
//     return DEFAULT_FEE;
//   }

//   // 3. Logic xử lý dữ liệu đầu vào
//   if (!toDistrictId || isNaN(parseInt(toDistrictId)) || !toWardCode) {
//     console.log('ℹ️ SHIPPING: Khách chưa chọn Quận/Huyện cụ thể (No ID). Dùng phí mặc định 30k.');
//     return DEFAULT_FEE;
//   }

//   // 4. Gọi API GHN
//   try {
//     const response = await axios.post(
//       'https://online-gateway.ghn.vn/shiip/public-api/v2/shipping-order/fee',
//       {
//         "service_type_id": 2, // Giao chuẩn
//         "to_district_id": parseInt(toDistrictId),
//         "to_ward_code": String(toWardCode),
//         "height": 10, "length": 10, "width": 10, "weight": parseInt(weight),
//         "insurance_value": 0,
//         "coupon": null 
//       },
//       { 
//         headers: { 
//             'token': TOKEN, 
//             'shop_id': SHOP_ID 
//         } 
//       }
//     );
    
//     if(response.data.code === 200) {
//         console.log('✅ GHN: Tính phí thành công:', response.data.data.total);
//         return response.data.data.total;
//     } else {
//         return DEFAULT_FEE;
//     }

//   } catch (error) {
//     console.error('❌ Lỗi kết nối GHN:', error.response?.data?.message || error.message);
//     return DEFAULT_FEE; 
//   }
// };

const calculateShippingFee = async (toDistrictId, toWardCode, weight = 500) => {
    // Trả về phí cố định ngay lập tức
    return 20000; 
};

const isRevenueAdjustment = (product) =>
    product?.is_revenue_adjustment === true || product?.name === 'Phụ kiện BrownVN';

// 2. HÀM TẠO ĐƠN GHN (ĐÃ UPDATE CHO SCHEMA MỚI)
const createGHNOrder = async (order) => {
    console.log("------------------------------------------------");
    console.log("🚀 BẮT ĐẦU TẠO ĐƠN GHN CHO ĐƠN HÀNG:", order.code);

    try {
        const SHOP_ID = process.env.GHN_SHOP_ID;
        const TOKEN = process.env.GHN_API_TOKEN;
        const API_URL = 'https://online-gateway.ghn.vn/shiip/public-api/v2/shipping-order/create';

        // Check biến môi trường
        if (!SHOP_ID || !TOKEN) {
            throw new Error("Thiếu GHN_SHOP_ID hoặc GHN_API_TOKEN trong file .env");
        }

        // ====================================================================
        // [QUAN TRỌNG] LẤY DỮ LIỆU TỪ CÁC CỘT MỚI (KHÔNG LẤY TỪ CUSTOMER_INFO)
        // ====================================================================
        
        const districtId = order.customer_district_id; // Lấy từ cột mới
        const wardCode = order.customer_ward_code;     // Lấy từ cột mới
        const cusName = order.customer_name;
        const cusPhone = order.customer_phone;
        const cusAddress = order.customer_address;

        console.log("🔍 Dữ liệu địa chỉ lấy từ DB:", {
            name: cusName,
            phone: cusPhone,
            district_id: districtId, 
            ward_code: wardCode      
        });

        // VALIDATE DỮ LIỆU QUAN TRỌNG
        if (!districtId || !wardCode) {
            console.error("❌ LỖI: Đơn hàng thiếu ID Quận/Huyện.");
            throw new Error("Đơn hàng thiếu District ID hoặc Ward Code. Vui lòng đặt đơn mới để hệ thống lưu ID.");
        }

        // Fees and other revenue adjustments belong to the order total, not to
        // the physical parcel declaration sent to GHN.
        const physicalItems = (order.order_items || []).filter(
            (item) => !isRevenueAdjustment(item.variants?.products)
        );
        if (physicalItems.length === 0) {
            throw new Error('Đơn chỉ có khoản thu điều chỉnh, không có hàng vật lý để tạo vận đơn GHN.');
        }

        const payload = {
            "payment_type_id": 1, // Người gửi trả phí (Shop trả)
            "note": order.note || "Cho xem hàng, không cho thử",
            "required_note": "CHOXEMHANGKHONGTHU",
            
            "to_name": cusName || "Khách hàng",
            "to_phone": cusPhone,
            "to_address": cusAddress || "Địa chỉ chi tiết",
            "to_ward_code": String(wardCode),
            "to_district_id": parseInt(districtId),
            
            // COD: Nếu thanh toán Banking rồi thì thu 0đ, ngược lại thu tổng tiền
            "cod_amount": order.payment_method === 'banking' ? 0 : Math.round(order.total_amount),
            
            // Cân nặng: Tính tổng từ các món hàng (Mặc định 200g/món nếu chưa nhập weight)
            "weight": physicalItems.reduce((acc, item) => acc + (item.variants?.weight || 200) * item.quantity, 0),
            "length": 10, "width": 10, "height": 10,
            
            "service_id": 53320, 
            "service_type_id": 2,
            
            // [QUAN TRỌNG] MAP DỮ LIỆU SẢN PHẨM THẬT
            "items": physicalItems.map(item => {
                const productInfo = item.variants?.products;
                const variantInfo = item.variants;
                
                // Tạo tên đầy đủ: "Áo Polo Basic - L / Đen"
                const fullName = `${productInfo?.name || 'Sản phẩm'} - ${variantInfo?.size || ''}/${variantInfo?.color || ''}`;

                return {
                    "name": fullName, 
                    "code": variantInfo?.sku || String(item.variant_id),
                    "quantity": item.quantity,
                    "price": Number(item.price), // Giá khai báo bảo hiểm (quan trọng khi mất hàng)
                    "weight": variantInfo?.weight || 200
                };
            })
        };

        console.log("📦 Đang gửi Payload sang GHN...");

        const response = await axios.post(API_URL, payload, { 
            headers: { 'Token': TOKEN, 'ShopId': SHOP_ID } 
        });

        console.log("✅ GHN Phản hồi thành công!");
        console.log("🎫 Mã vận đơn:", response.data.data.order_code);
        
        return response.data.data.order_code;

    } catch (error) {
        // Log chi tiết lỗi trả về từ GHN
        console.error("❌ GHN TRẢ VỀ LỖI:");
        if (error.response) {
            console.error("Status:", error.response.status);
            console.error("Data:", JSON.stringify(error.response.data, null, 2)); 
        } else {
            console.error("Message:", error.message);
        }
        throw new Error("Lỗi GHN: " + (error.response?.data?.message || error.message));
    }
};

module.exports = { calculateShippingFee, createGHNOrder };
