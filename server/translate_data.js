// // Tải các biến môi trường (nếu bạn dùng file .env ở backend)
// require('dotenv').config(); 

// // Import file cấu hình Supabase có sẵn của bạn
// const supabase = require('./config/supabase'); 
// const translate = require('translate-google');

// // Hàm tạo độ trễ (Sleep) để tránh bị Google chặn IP vì gửi request quá nhanh
// const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

// const runTranslation = async () => {
//     console.log("⏳ Bắt đầu quét các sản phẩm chưa được dịch...");

//     try {
//         // 1. Lấy danh sách sản phẩm chưa có name_en
//         const { data: products, error } = await supabase
//             .from('products')
//             .select('id, name, description')
//             .is('name_en', null);

//         if (error) throw error;

//         if (!products || products.length === 0) {
//             console.log("🎉 Tuyệt vời! Tất cả sản phẩm đều đã có tiếng Anh.");
//             return;
//         }

//         console.log(`📦 Tìm thấy ${products.length} sản phẩm cần xử lý. Bắt đầu dịch...\n`);
//         let successCount = 0;

//         // 2. Dịch từng sản phẩm một (Dùng vòng lặp for...of để đợi)
//         for (const product of products) {
//             try {
//                 console.log(`▶ Đang dịch: "${product.name}"...`);
                
//                 // Dịch Tên
//                 const name_en = await translate(product.name, { from: 'vi', to: 'en' });
                
//                 // Dịch Mô tả (Nếu có)
//                 let description_en = null;
//                 if (product.description && product.description.trim() !== '') {
//                     description_en = await translate(product.description, { from: 'vi', to: 'en' });
//                 }

//                 // 3. Cập nhật vào Database
//                 const { error: updateError } = await supabase
//                     .from('products')
//                     .update({ name_en, description_en })
//                     .eq('id', product.id);

//                 if (updateError) throw updateError;

//                 console.log(`   ✅ Xong: "${name_en}"`);
//                 successCount++;

//                 // 4. Nghỉ 1.5 giây trước khi dịch món tiếp theo
//                 await sleep(1500); 

//             } catch (err) {
//                 console.error(`   ❌ Lỗi khi dịch "${product.name}":`, err.message);
//             }
//         }

//         console.log(`\n🎉 HOÀN TẤT! Đã dịch thành công ${successCount}/${products.length} sản phẩm.`);
//         process.exit(0); // Tự động thoát script khi chạy xong

//     } catch (err) {
//         console.error("❌ Lỗi hệ thống:", err);
//         process.exit(1);
//     }
// };

// // Khởi chạy script
// runTranslation();

// require('dotenv').config(); 
// const supabase = require('./config/supabase'); 
// const translate = require('translate-google');

// const runCategoryTranslation = async () => {
//     console.log("⏳ Bắt đầu quét các danh mục chưa được dịch...");

//     try {
//         // Lấy danh mục chưa có tiếng Anh
//         const { data: categories, error } = await supabase
//             .from('categories')
//             .select('id, name')
//             .is('name_en', null);

//         if (error) throw error;

//         if (!categories || categories.length === 0) {
//             console.log("🎉 Tất cả danh mục đều đã có tiếng Anh!");
//             return process.exit(0);
//         }

//         for (const cat of categories) {
//             console.log(`▶ Đang dịch danh mục: "${cat.name}"...`);
//             try {
//                 const name_en = await translate(cat.name, { from: 'vi', to: 'en' });
                
//                 // Cập nhật vào Database
//                 await supabase
//                     .from('categories')
//                     .update({ name_en })
//                     .eq('id', cat.id);

//                 console.log(`   ✅ Xong: "${name_en}"`);
//             } catch (err) {
//                 console.error(`   ❌ Lỗi:`, err.message);
//             }
//         }

//         console.log("\n🎉 HOÀN TẤT DỊCH DANH MỤC!");
//         process.exit(0);

//     } catch (err) {
//         console.error("❌ Lỗi hệ thống:", err);
//         process.exit(1);
//     }
// };

// runCategoryTranslation();

require('dotenv').config(); 
const supabase = require('./config/supabase'); 
const translate = require('translate-google');

const runVariantTranslation = async () => {
    console.log("⏳ Bắt đầu quét các biến thể chưa được dịch màu...");

    try {
        const { data: variants, error } = await supabase
            .from('variants') // Sửa tên bảng nếu cần
            .select('id, color')
            .is('color_en', null);

        if (error) throw error;
        if (!variants || variants.length === 0) return console.log("🎉 Tất cả màu sắc đã được dịch!");

        for (const v of variants) {
            if (!v.color) continue;
            console.log(`▶ Đang dịch màu: "${v.color}"...`);
            try {
                const color_en = await translate(v.color, { from: 'vi', to: 'en' });
                
                await supabase
                    .from('variants')
                    .update({ color_en })
                    .eq('id', v.id);

                console.log(`   ✅ Xong: "${color_en}"`);
                // Nghỉ 1s tránh bị block IP
                await new Promise(res => setTimeout(res, 1000)); 
            } catch (err) {
                console.error(`   ❌ Lỗi:`, err.message);
            }
        }
        console.log("\n🎉 HOÀN TẤT DỊCH MÀU SẮC!");
        process.exit(0);
    } catch (err) {
        console.error("❌ Lỗi hệ thống:", err);
        process.exit(1);
    }
};

runVariantTranslation();