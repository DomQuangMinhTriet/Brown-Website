// server/scripts/auditCloudinaryOrphans.js
//
// [ĐỒNG BỘ QUÁ KHỨ] Trước khi có cơ chế dọn rác tự động (thêm ở bản này),
// việc xóa/thay ảnh sản phẩm, banner, lookbook không xóa file trên Cloudinary
// → có thể đã tích tụ file "mồ côi" (không còn được tham chiếu ở đâu trong DB).
//
// Script này liệt kê TOÀN BỘ file trong thư mục Cloudinary "brown_products",
// đối chiếu với mọi URL đang được dùng trong database, và báo cáo file nào
// không còn dùng — CHỈ BÁO CÁO, KHÔNG TỰ XÓA GÌ.
//
// Cách chạy (từ thư mục server/):
//   node scripts/auditCloudinaryOrphans.js
//
// Muốn xóa các file mồ côi sau khi đã xem báo cáo và tự tin xác nhận, chạy:
//   node scripts/auditCloudinaryOrphans.js --delete
// (Script sẽ hỏi lại và yêu cầu gõ đúng "XOA" mới thực sự xóa — không có bước
// xác nhận thì sẽ KHÔNG xóa gì cả.)

const readline = require('readline');
const cloudinary = require('cloudinary').v2;
const supabase = require('../config/supabase');
const { extractCloudinaryAsset } = require('../utils/cloudinaryCleanup');

cloudinary.config({
    cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
    api_key: process.env.CLOUDINARY_API_KEY,
    api_secret: process.env.CLOUDINARY_API_SECRET,
});

const FOLDER_PREFIX = 'brown_products/';

// Gom mọi URL đang được tham chiếu trong toàn bộ database
async function collectInUseUrls() {
    const urls = [];

    const [{ data: products }, { data: variants }, { data: banners }, { data: lookbook }] = await Promise.all([
        supabase.from('products').select('images, videos, size_chart_url'),
        supabase.from('variants').select('image_url'),
        supabase.from('content_banners').select('image_url'),
        supabase.from('content_lookbook').select('image_url, image_url_2'),
    ]);

    (products || []).forEach((p) => {
        urls.push(...(p.images || []), ...(p.videos || []), p.size_chart_url);
    });
    (variants || []).forEach((v) => urls.push(v.image_url));
    (banners || []).forEach((b) => urls.push(b.image_url));
    (lookbook || []).forEach((l) => urls.push(l.image_url, l.image_url_2));

    const publicIds = new Set();
    urls.filter(Boolean).forEach((url) => {
        const asset = extractCloudinaryAsset(url);
        if (asset) publicIds.add(asset.publicId);
    });
    return publicIds;
}

// Liệt kê toàn bộ asset trong thư mục brown_products (có phân trang) theo 1 resource_type
async function listAllCloudinaryAssets(resourceType) {
    const all = [];
    let cursor = undefined;
    do {
        const res = await cloudinary.api.resources({
            type: 'upload',
            resource_type: resourceType,
            prefix: FOLDER_PREFIX,
            max_results: 500,
            next_cursor: cursor,
        });
        all.push(...res.resources);
        cursor = res.next_cursor;
    } while (cursor);
    return all;
}

const formatMB = (bytes) => (bytes / (1024 * 1024)).toFixed(2);

async function confirmDeletion(count, totalBytes) {
    return new Promise((resolve) => {
        const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
        rl.question(
            `\n⚠️  Bạn sắp XÓA VĨNH VIỄN ${count} file (~${formatMB(totalBytes)}MB) trên Cloudinary.\n` +
            `Gõ chính xác "XOA" rồi Enter để xác nhận, hoặc Enter trống để hủy: `,
            (answer) => {
                rl.close();
                resolve(answer.trim() === 'XOA');
            }
        );
    });
}

async function main() {
    const shouldDelete = process.argv.includes('--delete');

    console.log('🔍 Đang quét database để biết file nào đang được dùng...');
    const inUsePublicIds = await collectInUseUrls();
    console.log(`   → ${inUsePublicIds.size} file đang được tham chiếu trong database.`);

    console.log('🔍 Đang liệt kê toàn bộ file trong Cloudinary (brown_products/)...');
    const [images, videos] = await Promise.all([
        listAllCloudinaryAssets('image'),
        listAllCloudinaryAssets('video'),
    ]);
    const allAssets = [...images, ...videos];
    console.log(`   → ${allAssets.length} file thực tế trên Cloudinary (${images.length} ảnh, ${videos.length} video).`);

    const orphans = allAssets.filter((a) => !inUsePublicIds.has(a.public_id));
    const orphanBytes = orphans.reduce((sum, a) => sum + (a.bytes || 0), 0);

    console.log('\n========== KẾT QUẢ ==========');
    console.log(`Tổng file mồ côi (không còn dùng): ${orphans.length}`);
    console.log(`Tổng dung lượng có thể giải phóng: ~${formatMB(orphanBytes)}MB`);

    if (orphans.length > 0) {
        console.log('\nDanh sách (tối đa 50 file đầu, xem đầy đủ trong file JSON bên dưới):');
        orphans.slice(0, 50).forEach((a) => {
            console.log(`  - ${a.public_id} (${a.resource_type}, ${formatMB(a.bytes)}MB)`);
        });

        const fs = require('fs');
        const path = require('path');
        const outPath = path.join(__dirname, `cloudinary-orphans-${Date.now()}.json`);
        fs.writeFileSync(outPath, JSON.stringify(orphans, null, 2));
        console.log(`\n📄 Đã lưu danh sách đầy đủ tại: ${outPath}`);
    }

    if (shouldDelete && orphans.length > 0) {
        const confirmed = await confirmDeletion(orphans.length, orphanBytes);
        if (!confirmed) {
            console.log('❌ Đã hủy — không xóa gì cả.');
            return;
        }
        console.log('🗑️  Đang xóa...');
        for (const a of orphans) {
            try {
                await cloudinary.uploader.destroy(a.public_id, { resource_type: a.resource_type });
                console.log(`  ✅ Đã xóa: ${a.public_id}`);
            } catch (err) {
                console.error(`  ❌ Lỗi xóa ${a.public_id}:`, err.message);
            }
        }
        console.log('✅ Hoàn tất dọn dẹp.');
    } else if (orphans.length > 0) {
        console.log('\nℹ️  Đây chỉ là báo cáo — CHƯA xóa gì. Muốn xóa thật, chạy lại với: node scripts/auditCloudinaryOrphans.js --delete');
    } else {
        console.log('\n✅ Không có file mồ côi nào — dữ liệu đang sạch.');
    }
}

main().catch((err) => {
    console.error('Lỗi khi audit Cloudinary:', err);
    process.exit(1);
});
