// server/validators/orderSchema.js
const { z } = require('zod');

// Định nghĩa quy tắc cho một món hàng trong giỏ
const itemSchema = z.object({
    variant_id: z.number().int().positive("ID sản phẩm không hợp lệ"),
    quantity: z.number().int().min(1, "Số lượng phải ít nhất là 1"),
});

// Định nghĩa quy tắc cho thông tin khách hàng
const customerSchema = z.object({
    fullName: z.string().min(2, "Tên phải có ít nhất 2 ký tự"),
    phone: z.string().regex(/(84|0[3|5|7|8|9])+([0-9]{8})\b/, "Số điện thoại không đúng định dạng VN"),
    email: z.string().email("Email không hợp lệ").optional().or(z.literal('')),
    address: z.string().min(5, "Địa chỉ quá ngắn"),
    province: z.string().optional(),
    district: z.string().optional(),
    ward: z.string().optional(),
});

// Định nghĩa quy tắc cho toàn bộ đơn hàng gửi lên
const createOrderSchema = z.object({
    customer: customerSchema,
    items: z.array(itemSchema).min(1, "Giỏ hàng không được để trống"),
    payment_method: z.enum(['cod', 'banking'], { 
        errorMap: () => ({ message: "Phương thức thanh toán không hợp lệ" }) 
    }),
    voucher_code: z.string().optional().nullable(),
    shipping_fee: z.number().min(0).default(0),
    note: z.string().optional()
});

module.exports = { createOrderSchema };