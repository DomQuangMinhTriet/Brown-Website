const supabase = require('../config/supabase');
const { sendOrderConfirmation } = require('../services/emailService');
const { z } = require('zod');

// --- 1. ĐỊNH NGHĨA BỘ LỌC DỮ LIỆU (VALIDATION SCHEMA) ---
// Dùng Zod để đảm bảo dữ liệu đầu vào sạch 100%
const orderSchema = z.object({
    customer: z.object({
        fullName: z.string().min(2, "Tên phải có ít nhất 2 ký tự"),
        phone: z.string().regex(/(84|0[3|5|7|8|9])+([0-9]{8})\b/, "Số điện thoại không hợp lệ"),
        email: z.string().email("Email không hợp lệ").optional().or(z.literal('')),
        address: z.string().min(5, "Địa chỉ quá ngắn (tối thiểu 5 ký tự)"),
        province: z.string().optional(),
        district: z.string().optional(),
        ward: z.string().optional(),
    }),
    items: z.array(z.object({
        variant_id: z.number().int().positive(),
        quantity: z.number().int().min(1, "Số lượng phải lớn hơn 0")
    })).min(1, "Giỏ hàng không được để trống"),
    payment_method: z.enum(['cod', 'banking'], { 
        errorMap: () => ({ message: "Phương thức thanh toán không hợp lệ" }) 
    }),
    voucher_code: z.string().nullable().optional(),
    shipping_fee: z.number().min(0).default(0),
    note: z.string().optional()
});

// --- 2. API TẠO ĐƠN HÀNG (SỬ DỤNG TRANSACTION) ---
exports.createOrder = async (req, res) => {
    try {
        // A. VALIDATE DỮ LIỆU ĐẦU VÀO
        const parseResult = orderSchema.safeParse(req.body);
        if (!parseResult.success) {
            // Nếu dữ liệu sai, trả về lỗi ngay lập tức
            return res.status(400).json({ 
                success: false, 
                message: 'Dữ liệu không hợp lệ',
                errors: parseResult.error.issues.map(e => e.message) // Trả về danh sách lỗi cụ thể
            });
        }

        const { customer, items, payment_method, voucher_code, shipping_fee, note } = parseResult.data;
        
        // B. LẤY ID KHÁCH HÀNG (Nếu đã đăng nhập)
        let customerId = null;
        if (req.user && req.user.id) {
             const { data: cusData } = await supabase
                .from('customers')
                .select('id')
                .eq('user_id', req.user.id)
                .single();
             if (cusData) customerId = cusData.id;
        }

        // C. CHUẨN BỊ DỮ LIỆU & BẢO MẬT GIÁ
        // Hacker có thể sửa giá ở Frontend, nên ta phải lấy giá gốc từ Database
        const cleanItems = [];
        let subtotal_check = 0;

        // Lấy danh sách ID sản phẩm để query 1 lần (tối ưu hiệu năng)
        const variantIds = items.map(i => i.variant_id);
        const { data: variantsDB, error: varError } = await supabase
            .from('variants')
            .select('id, current_price, products(base_price)')
            .in('id', variantIds);

        if (varError || !variantsDB) throw new Error("Lỗi khi lấy thông tin sản phẩm");

        // Map lại dữ liệu: Dùng giá từ DB, số lượng từ Khách
        for (const item of items) {
            const variant = variantsDB.find(v => v.id === item.variant_id);
            if (!variant) {
                return res.status(400).json({ success: false, message: `Sản phẩm ID ${item.variant_id} không còn tồn tại` });
            }

            // Ưu tiên giá sale (current_price), nếu không có lấy giá gốc
            const realPrice = variant.current_price || variant.products.base_price;
            
            cleanItems.push({
                variant_id: item.variant_id,
                quantity: item.quantity,
                unit_price: realPrice 
            });
            
            subtotal_check += realPrice * item.quantity;
        }

        // D. XỬ LÝ VOUCHER (Server tính toán)
        let discount_amount = 0;
        if (voucher_code) {
             const { data: promo } = await supabase
                .from('promotions')
                .select('*')
                .eq('code', voucher_code)
                .single();
            
            if (promo && promo.is_active) {
                // Kiểm tra hạn sử dụng & số lượng
                const now = new Date();
                if (new Date(promo.start_date) <= now && new Date(promo.end_date) >= now) {
                     if (promo.discount_type === 'percentage') {
                        discount_amount = subtotal_check * (promo.discount_value / 100);
                        if (promo.max_discount_amount) discount_amount = Math.min(discount_amount, promo.max_discount_amount);
                    } else {
                        discount_amount = promo.discount_value;
                    }
                    
                    // TODO: Nên đưa logic trừ lượt dùng voucher vào RPC luôn để an toàn tuyệt đối
                    await supabase.from('promotions').update({ used_count: promo.used_count + 1 }).eq('id', promo.id);
                }
            }
        }

        // E. GỌI DATABASE TRANSACTION (RPC)
        // Đây là bước quan trọng nhất: Gửi toàn bộ dữ liệu sạch xuống SQL xử lý
        const { data, error } = await supabase.rpc('create_order_transaction', {
            p_customer_id: customerId,
            p_customer_info: {
                name: customer.fullName,
                phone: customer.phone,
                email: customer.email,
                address: customer.address + (customer.province ? `, ${customer.district}, ${customer.province}` : '')
            },
            p_payment_method: payment_method,
            p_shipping_fee: shipping_fee,
            p_discount_amount: discount_amount,
            p_voucher_code: voucher_code || null,
            p_items: cleanItems
        });

        if (error) {
            console.error("RPC Error:", error);
            // Lỗi từ SQL trả về (ví dụ: "Sản phẩm không đủ hàng")
            return res.status(400).json({ success: false, message: error.message });
        }

        // F. GỬI MAIL & PHẢN HỒI
        // Gửi mail async (không await để khách không phải chờ lâu)
        const orderInfoForMail = {
            code: data.order_code,
            total_amount: data.total_amount, // Lấy tổng tiền chính xác từ SQL trả về
            shipping_tracking_code: 'Đang cập nhật' 
        };
        sendOrderConfirmation(orderInfoForMail, customer.email).catch(console.error);

        res.json({ 
            success: true, 
            orderCode: data.order_code, 
            message: 'Đặt hàng thành công!' 
        });

    } catch (error) {
        console.error("Order Controller Error:", error);
        res.status(500).json({ success: false, message: 'Lỗi hệ thống, vui lòng thử lại sau.' });
    }
};

// --- GIỮ NGUYÊN CÁC HÀM KHÁC (Admin View) ---
exports.getAllOrders = async (req, res) => {
    try {
        const { data, error } = await supabase
            .from('orders')
            .select(`*, order_items (id, quantity, price_at_purchase, variants (sku, size, color, products (name, images)))`)
            .order('created_at', { ascending: false });
        if (error) throw error;
        
        const formattedData = data.map(order => ({
            ...order,
            order_items: order.order_items.map(item => ({
                ...item,
                unit_price: item.price_at_purchase,
                total_price: item.price_at_purchase * item.quantity,
                product_name: item.variants?.products?.name,
                product_image: item.variants?.products?.images?.[0]
            }))
        }));
        res.json({ success: true, data: formattedData });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

exports.updateOrderStatus = async (req, res) => {
    try {
        const { id } = req.params;
        const { status, restock } = req.body; // Thêm tham số restock (true/false)
        
        // 1. Lấy thông tin đơn hiện tại
        const { data: currentOrder, error: fetchError } = await supabase
            .from('orders')
            .select('status, order_items(variant_id, quantity)')
            .eq('id', id)
            .single();

        if (fetchError || !currentOrder) return res.status(404).json({success: false, message: "Không tìm thấy đơn hàng"});

        // 2. LOGIC HOÀN KHO (Chỉ chạy khi Admin yêu cầu restock = true)
        // Áp dụng cho trạng thái: Cancelled (Hủy) hoặc Returned (Hoàn hàng)
        if (restock === true && ['cancelled', 'returned'].includes(status)) {
            
            // Chỉ hoàn kho nếu trạng thái cũ CHƯA hoàn (để tránh hoàn 2 lần)
            if (!['cancelled', 'returned'].includes(currentOrder.status)) {
                for (const item of currentOrder.order_items) {
                    // Tìm lô hàng nhập sau cùng (LIFO) để cộng lại (hoặc tạo lô mới)
                    // Ở đây ta cộng vào lô có sẵn để đơn giản hóa
                    const { data: latestBatch } = await supabase
                        .from('inventory_batches')
                        .select('id, quantity_remaining')
                        .eq('variant_id', item.variant_id)
                        .order('created_at', { ascending: false })
                        .limit(1)
                        .single();
                    
                    if (latestBatch) {
                        await supabase
                            .from('inventory_batches')
                            .update({ quantity_remaining: latestBatch.quantity_remaining + item.quantity })
                            .eq('id', latestBatch.id);
                    }
                }
            }
        }

        // 3. Cập nhật trạng thái mới
        const { data, error } = await supabase
            .from('orders')
            .update({ status })
            .eq('id', id)
            .select();

        if (error) throw error;
        
        res.json({ success: true, message: 'Cập nhật trạng thái thành công', data: data[0] });

    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};