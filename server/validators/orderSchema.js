const { z } = require('zod');

// Validate món hàng
const itemSchema = z.object({
    variant_id: z.number().int().positive("ID sản phẩm không hợp lệ"),
    quantity: z.number().int().min(1, "Số lượng phải ít nhất là 1"),
});

// Validate khách hàng
const customerSchema = z.object({
    fullName: z.string().min(2, "Tên phải có ít nhất 2 ký tự"),
    
    // [ĐÃ SỬA]: Cho phép nhập số điện thoại quốc tế (chỉ yêu cầu tối thiểu 8 ký tự)
    phone: z.string().min(8, "Số điện thoại không hợp lệ"), 
    
    email: z.string().email("Email không hợp lệ").optional().or(z.literal('')),
    address: z.string().min(5, "Địa chỉ quá ngắn"),
    province: z.string().optional(),
    district: z.string().optional(),
    ward: z.string().optional(),
    
    // [MỚI]: Thêm trường quốc gia để lưu DB
    country: z.string().optional(), 
});

// MAIN SCHEMA
const createOrderSchema = z.object({
    customer: customerSchema,
    items: z.array(itemSchema).min(1, "Giỏ hàng không được để trống"),
    
    // THAY ĐỔI: Chỉ chấp nhận 'banking'. Nếu gửi 'cod' sẽ báo lỗi.
    payment_method: z.enum(['banking'], { 
        errorMap: () => ({ message: "Hệ thống hiện tại chỉ chấp nhận Chuyển khoản QR" }) 
    }),
    
    voucher_code: z.string().optional().nullable(),
    shipping_fee: z.number().min(0).default(0),
    note: z.string().optional(),
    lang: z.string().optional()
});



module.exports = { createOrderSchema };