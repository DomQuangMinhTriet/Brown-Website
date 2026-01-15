const supabase = require('../config/supabase');
const { sendOrderConfirmation } = require('../services/emailService');
const { generateTrackingCode } = require('./shippingController');

exports.createOrder = async (req, res) => {
    try {
        const { customer, items, payment_method, voucher_code, shipping_fee } = req.body;
        const userId = req.user ? req.user.id : null;

        // --- BƯỚC 1: TÍNH TOÁN LẠI TỔNG TIỀN (SERVER SIDE VALIDATION) ---
        // Không tin tưởng 'total' từ frontend gửi lên
        let subtotal = 0;
        let cogs_total_order = 0; // Tổng giá vốn cả đơn

        // Kiểm tra tồn kho và lấy giá bán từ DB
        for (const item of items) {
            const { data: variant } = await supabase
                .from('variants')
                .select('price, products(base_price)')
                .eq('id', item.variant_id)
                .single();

            // Giá bán = Giá variant (nếu có) hoặc giá gốc sản phẩm
            const price = variant.price || variant.products.base_price;
            subtotal += price * item.quantity;
            
            // Gán lại giá đúng vào item để lưu DB
            item.real_price = price;
        }

        // Tính giảm giá (Check lại voucher lần nữa cho chắc)
        let discount_amount = 0;
        if (voucher_code) {
            const { data: promo } = await supabase
                .from('promotions')
                .select('*')
                .eq('code', voucher_code)
                .single();
            
            if (promo) {
                // Logic tính giảm giá (copy từ promotionController hoặc tách hàm chung)
                if (promo.discount_type === 'percentage') {
                    discount_amount = subtotal * (promo.discount_value / 100);
                    if (promo.max_discount_amount) discount_amount = Math.min(discount_amount, promo.max_discount_amount);
                } else {
                    discount_amount = promo.discount_value;
                }
                
                // Tăng biến đếm sử dụng voucher
                await supabase.from('promotions').update({ used_count: promo.used_count + 1 }).eq('id', promo.id);
            }
        }

        const final_total = subtotal + (shipping_fee || 0) - discount_amount;

        // --- BƯỚC 2: TẠO ĐƠN HÀNG ---
        const orderCode = `ORD-${Date.now().toString().slice(-6)}`;
        const trackingCode = generateTrackingCode(); // Tạo mã vận đơn SPX

        const { data: newOrder, error: orderError } = await supabase
            .from('orders')
            .insert([{
                code: orderCode,
                customer_name: customer.fullName,
                customer_phone: customer.phone,
                customer_email: customer.email, // Lưu email để gửi mail
                shipping_address: customer.address + (customer.province ? `, ${customer.province}` : ''),
                payment_method,
                status: 'pending',
                subtotal,
                shipping_fee: shipping_fee || 0,
                discount_amount,
                total_amount: final_total,
                voucher_code: voucher_code || null,
                shipping_carrier: 'SPX',          // <--- Mới
                shipping_tracking_code: trackingCode // <--- Mới
            }])
            .select()
            .single();

        if (orderError) throw orderError;

        // --- BƯỚC 3: XỬ LÝ TRỪ KHO (FIFO) & LƯU ORDER ITEMS ---
        for (const item of items) {
            let remainingNeeded = item.quantity;
            let itemCOGS = 0; // Giá vốn của item này

            // Lấy các lô hàng còn tồn (FIFO: Cũ nhất trước)
            const { data: batches } = await supabase
                .from('inventory_batches')
                .select('*')
                .eq('variant_id', item.variant_id)
                .gt('quantity_remaining', 0)
                .order('created_at', { ascending: true });

            if (!batches || batches.length === 0) {
                 throw new Error(`Sản phẩm ${item.variant_id} hết hàng trong kho!`);
            }

            for (const batch of batches) {
                if (remainingNeeded <= 0) break;

                const take = Math.min(remainingNeeded, batch.quantity_remaining);
                
                // Trừ kho
                await supabase
                    .from('inventory_batches')
                    .update({ quantity_remaining: batch.quantity_remaining - take })
                    .eq('id', batch.id);

                // Cộng dồn giá vốn (Số lượng lấy * Giá vốn lô đó)
                itemCOGS += take * batch.cost_price;
                remainingNeeded -= take;
            }

            // Lưu chi tiết đơn hàng
            await supabase.from('order_items').insert([{
                order_id: newOrder.id,
                variant_id: item.variant_id,
                quantity: item.quantity,
                unit_price: item.real_price, // Giá bán tại thời điểm mua
                cogs_total: itemCOGS         // Tổng giá vốn thực tế
            }]);
        }

        // --- BƯỚC 4: GỬI EMAIL & PHẢN HỒI ---
        // Gửi mail không cần await để tránh bắt khách chờ lâu
        sendOrderConfirmation(newOrder, customer, items); 

        // Tự động lưu khách hàng nếu chưa có (CRM)
        // (Logic này database trigger đã làm, nhưng có thể giữ lại update địa chỉ nếu muốn)

        res.json({ success: true, orderCode, message: 'Đặt hàng thành công!' });

    } catch (error) {
        console.error("Order Error:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};

// 2. LẤY DANH SÁCH ĐƠN HÀNG (Get All Orders)
exports.getAllOrders = async (req, res) => {
    try {
        console.log("📥 Admin đang lấy danh sách đơn hàng...");

        // SỬA LỖI: Query lồng nhau phải khớp tên cột trong Schema
        const { data, error } = await supabase
            .from('orders')
            .select(`
                *,
                order_items (
                    id,
                    quantity,
                    price_at_purchase, 
                    variants (
                        sku,
                        size,
                        color,
                        products (
                            name,
                            images
                        )
                    )
                )
            `)
            .order('created_at', { ascending: false });

        if (error) {
            console.error("Supabase Error:", error);
            throw error;
        }

        // Map lại dữ liệu một chút để Frontend dễ hiển thị (nếu cần)
        // Hoặc trả về nguyên gốc, Frontend tự xử lý unit_price vs price_at_purchase
        const formattedData = data.map(order => ({
            ...order,
            order_items: order.order_items.map(item => ({
                ...item,
                unit_price: item.price_at_purchase, // Map sang tên thông dụng cho Frontend dễ dùng
                total_price: item.price_at_purchase * item.quantity,
                product_name: item.variants?.products?.name,
                product_image: item.variants?.products?.images?.[0]
            }))
        }));

        res.json({ success: true, data: formattedData });

    } catch (error) {
        console.error("Lỗi lấy đơn hàng:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};

// 3. CẬP NHẬT TRẠNG THÁI (Update Status)
exports.updateOrderStatus = async (req, res) => {
    try {
        const { id } = req.params;
        const { status } = req.body; 

        // 1. Lấy thông tin đơn hàng hiện tại
        const { data: currentOrder } = await supabase
            .from('orders')
            .select('status, order_items(variant_id, quantity)')
            .eq('id', id)
            .single();

        // 2. LOGIC HOÀN KHO (RESTOCK)
        // Nếu chuyển sang 'cancelled' hoặc 'returned' TỪ trạng thái khác
        if (['cancelled', 'returned'].includes(status) && !['cancelled', 'returned'].includes(currentOrder.status)) {
            console.log("🔄 Đang hoàn kho cho đơn:", id);
            
            for (const item of currentOrder.order_items) {
                // Tìm lô hàng gần nhất của biến thể này để cộng lại số lượng
                const { data: latestBatch } = await supabase
                    .from('inventory_batches')
                    .select('id, quantity_remaining')
                    .eq('variant_id', item.variant_id)
                    .order('created_at', { ascending: false }) // Lấy lô mới nhất
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

        // 3. Cập nhật trạng thái
        const { data, error } = await supabase
            .from('orders')
            .update({ status })
            .eq('id', id)
            .select();

        if (error) throw error;
        res.json({ success: true, message: 'Cập nhật thành công', data: data[0] });

    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};