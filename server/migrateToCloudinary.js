const cloudinary = require('cloudinary').v2;
const { createClient } = require('@supabase/supabase-js');
require('dotenv').config();

// Cấu hình Cloudinary
cloudinary.config({
  cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
  api_key: process.env.CLOUDINARY_API_KEY,
  api_secret: process.env.CLOUDINARY_API_SECRET
});

// Kết nối Supabase với quyền Admin (Service Role)
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_KEY);

// Hàm upload 1 URL lên Cloudinary
async function migrateUrl(oldUrl) {
    // Chỉ xử lý nếu link tồn tại và là link của Supabase
    if (!oldUrl || typeof oldUrl !== 'string' || !oldUrl.includes('supabase.co')) {
        return oldUrl; 
    }

    try {
        const res = await cloudinary.uploader.upload(oldUrl, {
            folder: "brown_migration", // Gom hết vào đây quản lý cho dễ
            resource_type: "auto",
            format: "webp",
            transformation: [{ quality: "auto" }]
        });
        return res.secure_url;
    } catch (e) {
        console.error(`❌ Lỗi link: ${oldUrl}`, e.message);
        return oldUrl; // Giữ nguyên nếu lỗi
    }
}

async function run() {
    console.log("🚀 BẮT ĐẦU DI DỜI DỮ LIỆU (FULL)...");

    // 1. BẢNG BANNERS
    const { data: banners } = await supabase.from('content_banners').select('*');
    console.log(`\n🔍 Đang quét ${banners.length} banners...`);
    for (let b of banners) {
        if (b.image_url && b.image_url.includes('supabase.co')) {
            const newUrl = await migrateUrl(b.image_url);
            if (newUrl !== b.image_url) {
                await supabase.from('content_banners').update({ image_url: newUrl }).eq('id', b.id);
                console.log(`✅ Banner [${b.id}] OK`);
            }
        }
    }

    // 2. BẢNG PRODUCTS (Xử lý cả 'images' và 'size_chart_url')
    const { data: products } = await supabase.from('products').select('*');
    console.log(`\n🔍 Đang quét ${products.length} sản phẩm...`);
    
    for (let p of products) {
        let updates = {};
        let needsUpdate = false;

        // A. Xử lý mảng hình ảnh chính (images)
        if (p.images && Array.isArray(p.images) && p.images.length > 0) {
            const newImages = [];
            let imagesChanged = false;
            
            for (let img of p.images) {
                if (img.includes('supabase.co')) {
                    const newUrl = await migrateUrl(img);
                    newImages.push(newUrl);
                    imagesChanged = true;
                } else {
                    newImages.push(img);
                }
            }

            if (imagesChanged) {
                updates.images = newImages;
                needsUpdate = true;
            }
        }

        // B. Xử lý ảnh Bảng Size (size_chart_url) --- [PHẦN MỚI THÊM]
        if (p.size_chart_url && p.size_chart_url.includes('supabase.co')) {
            const newSizeChartUrl = await migrateUrl(p.size_chart_url);
            if (newSizeChartUrl !== p.size_chart_url) {
                updates.size_chart_url = newSizeChartUrl;
                needsUpdate = true;
            }
        }

        // C. Cập nhật vào Database nếu có thay đổi
        if (needsUpdate) {
            await supabase.from('products').update(updates).eq('id', p.id);
            console.log(`✅ Product [${p.name}] OK`);
        }
    }

    // 3. BẢNG VARIANTS
    const { data: variants } = await supabase.from('variants').select('*');
    console.log(`\n🔍 Đang quét ${variants.length} biến thể...`);
    for (let v of variants) {
        if (v.image_url && v.image_url.includes('supabase.co')) {
            const newUrl = await migrateUrl(v.image_url);
            if (newUrl !== v.image_url) {
                await supabase.from('variants').update({ image_url: newUrl }).eq('id', v.id);
                console.log(`✅ Variant SKU [${v.sku}] OK`);
            }
        }
    }

    console.log("\n🎉🎉🎉 HOÀN TẤT TOÀN BỘ! Bạn có thể yên tâm xóa ảnh trên Supabase.");
}

run();