const NodeCache = require('node-cache');

// stdTTL: Thời gian sống mặc định (giây) - 300s = 5 phút
const cache = new NodeCache({ stdTTL: 300 });

const verifyCache = (duration) => (req, res, next) => {
    try {
        // Tạo Key duy nhất dựa trên URL (Ví dụ: /api/products?search=ao)
        // Nếu URL khác nhau thì Cache khác nhau
        const key = '__express__' + req.originalUrl || req.url;
        
        const cachedBody = cache.get(key);

        if (cachedBody) {
            // ✅ HIT: Đã có trong Cache -> Trả về ngay
            console.log(`🚀 Cache Hit: ${key}`);
            return res.json(JSON.parse(cachedBody));
        } else {
            // ❌ MISS: Chưa có -> Ghi đè hàm res.json để tự động lưu Cache khi Controller trả về
            console.log(`🐢 Cache Miss: ${key}`);
            
            res.sendResponse = res.json;
            res.json = (body) => {
                // Lưu vào RAM trước khi trả về cho khách
                cache.set(key, JSON.stringify(body), duration);
                res.sendResponse(body);
            };
            next();
        }
    } catch (error) {
        console.error("Cache Error:", error);
        next(); // Nếu lỗi cache thì cứ cho chạy bình thường
    }
};

// Hàm để xóa Cache khi Admin cập nhật sản phẩm (Advanced)
const clearCache = (keyPart) => {
    const keys = cache.keys();
    // Tìm và xóa các key có chứa từ khóa (VD: xóa tất cả cache liên quan products)
    const matches = keys.filter(k => k.includes(keyPart));
    cache.del(matches);
    console.log(`🧹 Đã dọn dẹp ${matches.length} cache keys chứa '${keyPart}'`);
};

module.exports = { verifyCache, clearCache };