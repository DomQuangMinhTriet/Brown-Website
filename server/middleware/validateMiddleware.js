// server/middleware/validateMiddleware.js
const validate = (schema) => (req, res, next) => {
    try {
        // Kiểm tra req.body xem có khớp với schema không
        schema.parse(req.body);
        next(); // Nếu đúng -> Cho đi tiếp vào Controller
    } catch (error) {
        // Nếu sai -> Trả về lỗi 400 kèm chi tiết
        return res.status(400).json({
            success: false,
            message: 'Dữ liệu không hợp lệ',
            errors: error.errors.map(e => ({
                field: e.path.join('.'),
                message: e.message
            }))
        });
    }
};

module.exports = validate;