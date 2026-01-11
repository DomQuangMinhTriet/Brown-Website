const supabase = require('../config/supabase');

// 1. TẠO ĐƠN HÀNG (Create Order)
exports.createOrder = async (req, res) => {
    try {
        const { customer, items, total, payment_method } = req.body;

        if (!items || items.length === 0) {
            return res.status(400).json({ success: false, message: 'Giỏ hàng trống!' });
        }

        console.log("🚀 Xử lý đơn hàng cho:", customer.fullName);

        // A. Kiểm tra tồn kho (Check Inventory)
        for (const item of items) {
            const { data: batches } = await supabase
                .from('inventory_batches')
                .select('quantity_remaining')
                .eq('variant_id', item.variant_id);
            
            const currentStock = batches?.reduce((sum, b) => sum + b.quantity_remaining, 0) || 0;
            
            if (currentStock < item.quantity) {
                return res.status(400).json({ 
                    success: false, 
                    message: `Sản phẩm ID ${item.variant_id} không đủ hàng (Tồn: ${currentStock}, Mua: ${item.quantity})` 
                });
            }
        }

        // B. Tạo Header Đơn hàng vào bảng 'orders'
        const orderCode = `ORD-${Date.now()}`;
        const subtotal = items.reduce((sum, item) => sum + (item.price * item.quantity), 0);

        // Lưu ý: customer_* là các cột bạn đã thêm bằng ALTER TABLE trong schema
        const { data: orderData, error: orderError } = await supabase
            .from('orders')
            .insert({
                code: orderCode,
                customer_name: customer.fullName,
                customer_phone: customer.phone,
                customer_address: customer.address,
                customer_email: customer.email,
                note: customer.note,
                subtotal: subtotal,
                total_amount: total,
                payment_method: payment_method || 'cod',
                status: 'pending'
            })
            .select()
            .single();

        if (orderError) throw orderError;
        const orderId = orderData.id;

        // C. Trừ kho FIFO & Lưu chi tiết vào 'order_items'
        for (const item of items) {
            const { variant_id, quantity, price } = item;
            let qtyNeeded = quantity;
            let totalCostPrice = 0;

            // Lấy các lô hàng còn tồn (Cũ nhất lên trước)
            const { data: batches } = await supabase
                .from('inventory_batches')
                .select('*')
                .eq('variant_id', variant_id)
                .gt('quantity_remaining', 0)
                .order('created_at', { ascending: true }); 

            // Thuật toán trừ kho
            for (const batch of batches) {
                if (qtyNeeded === 0) break;
                let takeQty = (batch.quantity_remaining >= qtyNeeded) ? qtyNeeded : batch.quantity_remaining;
                qtyNeeded -= takeQty;
                totalCostPrice += (takeQty * batch.cost_price);

                await supabase
                    .from('inventory_batches')
                    .update({ quantity_remaining: batch.quantity_remaining - takeQty })
                    .eq('id', batch.id);
            }

            // INSERT vào order_items
            // SỬA LỖI: Dùng đúng cột 'price_at_purchase' như trong schema
            await supabase.from('order_items').insert({
                order_id: orderId,
                variant_id: variant_id,
                quantity: quantity,
                price_at_purchase: price, // <-- Tên cột đúng trong Schema
                cogs_total: totalCostPrice // <-- Tổng giá vốn
            });
        }

        res.json({ success: true, message: 'Tạo đơn thành công', orderId, orderCode });

    } catch (error) {
        console.error("❌ Lỗi Server:", error);
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

        // Validate status hợp lệ theo thiết kế DB
        const validStatuses = ['pending', 'confirmed', 'shipping', 'completed', 'cancelled', 'returned'];
        if (!validStatuses.includes(status)) {
            return res.status(400).json({ success: false, message: 'Trạng thái không hợp lệ' });
        }
        
        console.log(`🔄 Cập nhật đơn ${id} -> ${status}`);

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