<<<<<<< HEAD
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
=======
const validate = (schema) => (req, res, next) => {
    try {
        // Dùng safeParse thay vì parse để không gây crash server
        const result = schema.safeParse(req.body);

        if (!result.success) {
            // Lấy danh sách lỗi từ result.error.issues (chuẩn Zod)
            const errorList = result.error.issues;

            // Format lại lỗi cho đẹp để trả về frontend
            const errorMessages = errorList.map((issue) => {
                const field = issue.path.join('.');
                return `${field}: ${issue.message}`;
            });

            console.log("Validation Error:", errorMessages); // Log để debug

            return res.status(400).json({
                success: false,
                message: 'Dữ liệu không hợp lệ',
                errors: errorMessages // Trả về mảng string lỗi đơn giản
            });
        }

        // Gán lại dữ liệu đã được làm sạch (quan trọng)
        // Zod sẽ loại bỏ các trường thừa không có trong schema nếu dùng strict, hoặc ép kiểu đúng
        req.body = result.data;
        
        next();
    } catch (err) {
        console.error("System Validation Error:", err);
        return res.status(500).json({ 
            success: false, 
            message: "Lỗi hệ thống kiểm tra dữ liệu" 
>>>>>>> Frontend
        });
    }
};

module.exports = validate;