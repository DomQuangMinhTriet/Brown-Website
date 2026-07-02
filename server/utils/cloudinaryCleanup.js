// server/utils/cloudinaryCleanup.js
//
// [AN TOÀN] Dùng chung mọi nơi có xóa/thay ảnh-video để tránh rò rỉ dung
// lượng Cloudinary: xóa DB row hoặc thay 1 file bằng file mới mà không gọi
// hàm này thì file cũ vẫn nằm mãi trên Cloudinary, không ai dọn.
const cloudinary = require('cloudinary').v2;

cloudinary.config({
    cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
    api_key: process.env.CLOUDINARY_API_KEY,
    api_secret: process.env.CLOUDINARY_API_SECRET,
});

// Tách public_id + loại tài nguyên (image/video) từ 1 secure_url của Cloudinary.
// Bỏ qua URL không phải Cloudinary (ảnh demo/link ngoài) — trả về null, an toàn.
function extractCloudinaryAsset(url) {
    if (!url || typeof url !== 'string' || !url.includes('res.cloudinary.com')) return null;
    const match = url.match(/\/(image|video)\/upload\/(?:v\d+\/)?(.+?)\.[a-zA-Z0-9]+(?:\?.*)?$/);
    if (!match) return null;
    return { resourceType: match[1], publicId: match[2] };
}

// Xóa 1 file trên Cloudinary theo URL — best-effort, không throw (chỉ log lỗi)
// để một lần xóa thất bại không làm hỏng thao tác chính (xóa SP, cập nhật...).
async function deleteCloudinaryAsset(url) {
    const asset = extractCloudinaryAsset(url);
    if (!asset) return;
    try {
        await cloudinary.uploader.destroy(asset.publicId, { resource_type: asset.resourceType });
    } catch (err) {
        console.error('⚠️ Lỗi xóa file Cloudinary:', asset.publicId, err.message);
    }
}

// Xóa nhiều URL cùng lúc (bỏ qua giá trị rỗng/null).
async function deleteCloudinaryAssets(urls) {
    const list = (urls || []).filter(Boolean);
    await Promise.all(list.map(deleteCloudinaryAsset));
}

// So sánh danh sách URL CŨ và MỚI của cùng 1 trường (vd: product.images) —
// trả về những URL đã bị loại bỏ (có trong cũ, không còn trong mới) để xóa.
function diffRemovedUrls(oldUrls, newUrls) {
    const oldList = (oldUrls || []).filter(Boolean);
    const newSet = new Set((newUrls || []).filter(Boolean));
    return oldList.filter((u) => !newSet.has(u));
}

module.exports = { extractCloudinaryAsset, deleteCloudinaryAsset, deleteCloudinaryAssets, diffRemovedUrls };
