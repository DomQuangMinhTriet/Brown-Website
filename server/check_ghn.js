// const axios = require('axios');

// // Token bạn đang dùng trong file .env
// const YOUR_TOKEN = '7a83a4ad-f72f-11f0-835a-aa01149835ce'; 

// async function checkShop() {
//     console.log("Dang kiem tra danh sach Shop...");
//     try {
//         const response = await axios.get(
//             'https://online-gateway.ghn.vn/shiip/public-api/v2/shop/all',
//             {
//                 headers: { 'Token': YOUR_TOKEN }
//             }
//         );

//         // IN RA CẤU TRÚC DỮ LIỆU THẬT ĐỂ KIỂM TRA
//         console.log("✅ KẾT QUẢ TỪ GHN (RAW):");
//         console.log(JSON.stringify(response.data, null, 2));

//         // Logic xử lý (Thử các trường hợp cấu trúc khác nhau)
//         let shops = response.data.data;
        
//         // Trường hợp GHN trả về { data: { shops: [...] } }
//         if (shops && shops.shops) {
//             shops = shops.shops;
//         }

//         if (!Array.isArray(shops)) {
//             console.log("\n⚠️ Cảnh báo: Dữ liệu không phải là danh sách (Array).");
//             return;
//         }

//         console.log("\n================================================");
//         console.log(`BẠN ĐANG CÓ ${shops.length} CỬA HÀNG:`);
        
//         shops.forEach(shop => {
//             console.log("------------------------------------------------");
//             console.log(`🏠 Tên Shop: ${shop.name}`);
//             console.log(`🔑 SHOP ID (Dùng cái này): ${shop._id}`); 
//             console.log(`📍 Địa chỉ: ${shop.address}`);
//         });
//         console.log("================================================");
//         console.log("👉 Hãy copy số SHOP ID ở trên vào file .env dòng GHN_SHOP_ID");

//     } catch (error) {
//         console.error("❌ Lỗi kết nối:", error.response?.data || error.message);
//     }
// }

// checkShop();