const supabase = require('../config/supabase');
const { evaluateVoucher } = require('./promotionController');
const { sendOrderConfirmation, sendShippingConfirmation, sendNewOrderNotifyToAdmin } = require('../services/emailService');
const { calculateShippingFee, createGHNOrder } = require('../services/shippingService'); // <--- IMPORT HELPER
const { z } = require('zod');
const exceljs = require('exceljs');

// --- 1. CẬP NHẬT BỘ LỌC DỮ LIỆU (VALIDATION SCHEMA) ---
const orderSchema = z.object({
    customer: z.object({
        fullName: z.string().min(2, "Tên phải có ít nhất 2 ký tự"),
        phone: z.string().min(8, "Số điện thoại phải có ít nhất 8 ký tự"), 
        email: z.string().email("Email không hợp lệ").nullable().optional().or(z.literal('')),
        address: z.string().min(5, "Địa chỉ quá ngắn"),
        province: z.string().nullable().optional(),
        district: z.string().nullable().optional(),
        ward: z.string().nullable().optional(),
        province_id: z.any().nullable().optional(), 
        district_id: z.any().nullable().optional(),
        ward_code: z.any().nullable().optional(),
        country: z.string().nullable().optional(),
        zipcode: z.string().nullable().optional(), 
        shipping_type: z.string().nullable().optional()
    }),
    items: z.array(z.object({
        variant_id: z.number().int().positive(),
        quantity: z.number().int().min(1, "Số lượng phải lớn hơn 0")
    })).min(1, "Giỏ hàng không được để trống"),
    payment_method: z.enum(['done', 'banking', 'cod'], { 
        errorMap: () => ({ message: "Phương thức thanh toán không hợp lệ" }) 
    }).nullable().optional(),
    voucher_code: z.string().nullable().optional(),
    shipping_fee: z.number().min(0).default(0),
    note: z.string().nullable().optional(),
    discount_amount: z.number().nullable().optional(),
    final_total: z.number().nullable().optional(),
    lang: z.string().nullable().optional()
});

// --- [MỚI] API TÍNH PHÍ SHIP (Frontend sẽ gọi cái này) ---
exports.getShippingFee = async (req, res) => {
    try {
        const { district_id, ward_code } = req.body;
        const fee = await calculateShippingFee(district_id, ward_code);
        res.json({ success: true, fee });
    } catch (error) {
        res.status(500).json({ success: false, fee: 20000 });
    }
};

// --- 2. API TẠO ĐƠN HÀNG (SỬ DỤNG TRANSACTION) ---
exports.createOrder = async (req, res) => {
    try {
        // A. VALIDATE DỮ LIỆU ĐẦU VÀO
        const parseResult = orderSchema.safeParse(req.body);
        if (!parseResult.success) {
            return res.status(400).json({ 
                success: false, 
                message: 'Dữ liệu không hợp lệ',
                errors: parseResult.error.issues.map(e => e.message) 
            });
        }

        const { customer, items, payment_method, voucher_code, shipping_fee, note, lang } = parseResult.data;
        console.log("👉 Dữ liệu Customer sau khi Validate:", customer);

        if (customer.email && !customer.email.toLowerCase().endsWith('@gmail.com')) {
            return res.status(400).json({ success: false, message: 'Hệ thống chỉ hỗ trợ gửi thông báo qua địa chỉ @gmail.com' });
        }

        // B. XÁC ĐỊNH KHÁCH HÀNG
        let customerId = null;

        if (req.user && req.user.id) {
             const { data: cusData } = await supabase
                .from('customers')
                .select('id')
                .eq('user_id', req.user.id)
                .single();
             if (cusData) customerId = cusData.id;
        }

        if (!customerId && customer.phone) {
            const { data: existingCus } = await supabase
                .from('customers')
                .select('id')
                .eq('phone', customer.phone)
                .single();

            if (existingCus) {
                customerId = existingCus.id;
            } else {
                const { data: newCus, error: createError } = await supabase
                    .from('customers')
                    .insert([{
                        full_name: customer.fullName || customer.name || "Khách mới",
                        phone: customer.phone,
                        email: customer.email || null,
                        address: customer.address || null
                    }])
                    .select('id')
                    .single();
                
                if (!createError && newCus) {
                    customerId = newCus.id;
                }
            }
        }
        // C. CHUẨN BỊ DỮ LIỆU & BẢO MẬT GIÁ + KIỂM TRA TỒN KHO THỰC TẾ
        const cleanItems = [];
        let subtotal_check = 0;
        const itemsToNegative = [];
        const mailItems = []; // [BỔ SUNG] Mảng chứa dữ liệu chi tiết cho Email
        const voucherLineItems = []; // Dùng để tính voucher theo từng SP

        const variantIds = items.map(i => i.variant_id);
        
        // [BỔ SUNG] Thêm size, color, color_en, products(name) để lấy thông tin đưa vào Email
        const { data: variantsDB, error: varError } = await supabase
            .from('variants')
            .select(`
                id,
                size, color, color_en,
                current_price,
                discount_amount, is_discount_active,
                products(id, name, base_price, is_preorder),
                inventory_batches(quantity_remaining)
            `)
            .in('id', variantIds);

        if (varError || !variantsDB) throw new Error("Lỗi khi lấy thông tin sản phẩm");

        for (const item of items) {
            const variant = variantsDB.find(v => v.id === item.variant_id);
            if (!variant) {
                return res.status(400).json({ success: false, message: `Sản phẩm không còn tồn tại.` });
            }

            const totalStock = variant.inventory_batches
                ? variant.inventory_batches.reduce((sum, batch) => sum + (Number(batch.quantity_remaining) || 0), 0)
                : 0;

            const isPreorder = variant.products?.is_preorder;

            if (!isPreorder && item.quantity > totalStock) {
                return res.status(400).json({ 
                    success: false, 
                    message: `Rất tiếc! Một sản phẩm trong giỏ hàng của bạn hiện chỉ còn ${totalStock} chiếc. Vui lòng cập nhật lại số lượng.` 
                });
            }

            if (item.quantity > totalStock) {
                itemsToNegative.push({
                    variant_id: item.variant_id,
                    excess_qty: item.quantity - totalStock
                });
            }

            // [MỚI] Áp GIẢM GIÁ TRỰC TIẾP theo biến thể (màu/size), nếu đang bật
            const prod = variant.products;
            const onDiscount = variant.is_discount_active && Number(variant.discount_amount) > 0;
            let realPrice = variant.current_price || prod.base_price;
            if (onDiscount) {
                realPrice = Math.max(0, realPrice - Number(variant.discount_amount));
            }

            // Gom dữ liệu để tính voucher theo từng SP (SP đang giảm giá trực tiếp sẽ bị loại khỏi phần tính voucher)
            voucherLineItems.push({
                product_id: prod?.id,
                quantity: item.quantity,
                unit_price: realPrice,
                on_discount: onDiscount
            });

            const { data: latestBatch } = await supabase
                .from('inventory_batches')
                .select('cost_price')
                .eq('variant_id', item.variant_id)
                .order('created_at', { ascending: false }) 
                .limit(1)
                .single();

            const unitCost = latestBatch ? Number(latestBatch.cost_price) : 0;
            const totalCogs = unitCost * item.quantity;

            cleanItems.push({
                variant_id: item.variant_id,
                quantity: item.quantity,
                unit_price: realPrice,
                cogs_total: totalCogs 
            });

            // [BỔ SUNG] Push dữ liệu đầy đủ vào mảng gửi mail
            mailItems.push({
                product_name: variant.products?.name,
                variants: {
                    size: variant.size,
                    color: variant.color,
                    color_en: variant.color_en
                },
                quantity: item.quantity,
                price: realPrice
            });
            
            subtotal_check += realPrice * item.quantity;
        }

        // D. XỬ LÝ VOUCHER (Server tính toán — dùng chung helper evaluateVoucher,
        //    voucher chỉ giảm trên SP được chọn & không cộng dồn với SP đang giảm giá trực tiếp)
        let discount_amount = 0;
        if (voucher_code) {
            const result = await evaluateVoucher(voucher_code, voucherLineItems);
            if (result.ok) {
                discount_amount = result.discountAmount;
                const newUsed = (result.promo.used_count || 0) + 1;
                await supabase.from('promotions').update({ used_count: newUsed }).eq('id', result.promo.id);
            }
        }

        // E. GỌI DATABASE TRANSACTION (RPC)
        // Nối sẵn địa chỉ đầy đủ để dùng cho cả DB và Mail
        const fullAddress = customer.address + (customer.province ? `, ${customer.ward || ''}, ${customer.district || ''}, ${customer.province || ''}` : '');

        const { data, error } = await supabase.rpc('create_order_transaction', {
            p_customer_id: customerId,
            p_customer_info: {
                name: customer.fullName,
                phone: customer.phone,
                email: customer.email,
                address: fullAddress,
                province_id: customer.province_id,
                district_id: customer.district_id,
                ward_code: customer.ward_code
            },
            p_payment_method: payment_method,
            p_shipping_fee: shipping_fee, 
            p_discount_amount: discount_amount,
            p_voucher_code: voucher_code || null,
            p_items: cleanItems 
        });

        if (error) {
            console.error("RPC Error:", error);
            return res.status(400).json({ success: false, message: error.message });
        }

        if (itemsToNegative.length > 0) {
            for (const neg of itemsToNegative) {
                const { data: latestBatch } = await supabase
                    .from('inventory_batches')
                    .select('id, quantity_remaining')
                    .eq('variant_id', neg.variant_id)
                    .order('created_at', { ascending: false })
                    .limit(1)
                    .single();
                
                if (latestBatch) {
                    await supabase.from('inventory_batches')
                        .update({ quantity_remaining: latestBatch.quantity_remaining - neg.excess_qty })
                        .eq('id', latestBatch.id);
                } else {
                    await supabase.from('inventory_batches').insert([{
                        variant_id: neg.variant_id,
                        original_quantity: 0,
                        quantity_remaining: -neg.excess_qty,
                        cost_price: 0,
                        is_adjustment: true,
                        notes: 'Lô âm tự động (Khách Preorder)'
                    }]);
                }
            }
        }

        // F. GỬI EMAIL THÔNG BÁO (CHO KHÁCH & ADMIN)
        const emailCustomerName = data.customer_name || customer.fullName || customer.name || "Quý khách";
        const rawTotalAmount = data.total_amount || (subtotal_check + shipping_fee - discount_amount);
        const emailAddress = customer.email;

        // 1. Gửi mail xác nhận cho Khách Hàng 
        if (emailAddress) {
            const orderInfoForMail = {
                customer_name: emailCustomerName,
                code: data.order_code,
                total_amount: rawTotalAmount, 
                shipping_tracking_code: 'Đang cập nhật',
                // [BỔ SUNG] Các trường còn thiếu để hiển thị mail chi tiết
                customer_phone: customer.phone,
                customer_address: fullAddress,
                customer_email: customer.email,
                note: note,
                subtotal: subtotal_check,
                discount_amount: discount_amount,
                shipping_fee: shipping_fee,
                payment_method: payment_method,
                items: mailItems
            };
            sendOrderConfirmation(orderInfoForMail, emailAddress, lang || 'vi').catch(err => console.error("Mail Khách Error:", err));
        }

        // 2. Gửi mail thông báo cho Admin
        const adminOrderData = {
            id: data.order_code,            
            customer_name: emailCustomerName, 
            phone: customer.phone,          
            total_amount: rawTotalAmount,   
            payment_method: payment_method,
            // [BỔ SUNG] Các trường còn thiếu cho Admin
            address: fullAddress,
            email: customer.email,
            note: note,
            subtotal: subtotal_check,
            discount_amount: discount_amount,
            shipping_fee: shipping_fee,
            items: mailItems  
        };

        sendNewOrderNotifyToAdmin(adminOrderData).catch(err => console.error("Mail Admin Error:", err));

        res.json({ 
            success: true, 
            orderCode: data.order_code, 
            message: 'Đặt hàng thành công!' 
        });

    } catch (error) {
        console.error("Order Controller Error:", error);
        res.status(500).json({ success: false, message: 'Lỗi hệ thống: ' + error.message });
    }
};

// --- GIỮ NGUYÊN TOÀN BỘ CÁC HÀM KHÁC (Admin View) BÊN DƯỚI ... ---
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
        const { status, restock, skip_ghn, tracking_code, cost_price_overrides } = req.body;

        console.log("-------------------------------------------------");
        console.log(`🛠 Đang update đơn #${id} sang trạng thái: ${status}`);

        const { data: currentOrder, error: fetchError } = await supabase
            .from('orders')
            .select(`
                *,
                order_items (
                    quantity,
                    price_at_purchase,
                    variant_id,
                    variants (
                        sku,
                        size,
                        color,
                        weight, 
                        products ( name )
                    )
                )
            `)
            .eq('id', id)
            .single();

        if (fetchError || !currentOrder) {
            console.error("Lỗi tìm đơn hàng:", fetchError);
            return res.status(404).json({success: false, message: "Không tìm thấy đơn hàng"});
        }

        let trackingCode = currentOrder.shipping_tracking_code;
        let updateData = { status };

        if (status === 'shipping' && !trackingCode && !skip_ghn) {
            try {
                console.log("🚀 Đang tạo đơn qua GHN...");
                trackingCode = await createGHNOrder(currentOrder);
                updateData.shipping_tracking_code = trackingCode;
            } catch (ghnError) {
                console.error("❌ Lỗi GHN:", ghnError.message);
                return res.status(400).json({ 
                    success: false, 
                    message: `Lỗi tạo đơn GHN: ${ghnError.message}. Hãy thử chọn 'SPX / Tự giao'.` 
                });
            }
        } else if (status === 'shipping' && skip_ghn) {
            console.log("🛵 Admin chọn SPX / Tự giao hàng.");
            if (tracking_code) {
                trackingCode = tracking_code;
                updateData.shipping_tracking_code = trackingCode;
            }
        }

        if (status === 'cancelled') {
             console.log("ℹ️ Đơn hủy: Để Database Trigger tự động hoàn kho.");
        } else if (status === 'returned' && restock === true) {
            if (currentOrder.status !== 'returned') {
                console.log("🔄 Đang xử lý trả hàng (Code hoàn kho thủ công)...");
                const orderItems = currentOrder.order_items;
                if (orderItems && orderItems.length > 0) {
                    const overrides = cost_price_overrides || {};

                    // Pass 1: xác định biến thể nào CHƯA từng có lô kho nào — những biến thể
                    // này cần giá vốn thủ công (client gửi cost_price_overrides), không tự ý để 0đ.
                    const batchByVariant = {};
                    const missing = [];
                    for (const item of orderItems) {
                        const { data: latestBatch } = await supabase.from('inventory_batches')
                            .select('id, quantity_remaining')
                            .eq('variant_id', item.variant_id)
                            .order('created_at', { ascending: false })
                            .limit(1)
                            .single();
                        batchByVariant[item.variant_id] = latestBatch || null;
                        if (!latestBatch && !(Number(overrides[item.variant_id]) > 0)) {
                            missing.push(item);
                        }
                    }

                    if (missing.length > 0) {
                        return res.status(400).json({
                            success: false,
                            needsCostPrice: true,
                            message: 'Một số biến thể trong đơn chưa từng có lô kho nào — cần nhập giá vốn thủ công trước khi hoàn kho.',
                            missingCost: missing.map(item => ({
                                variant_id: item.variant_id,
                                name: item.variants?.products?.name,
                                sku: item.variants?.sku,
                                size: item.variants?.size,
                                color: item.variants?.color,
                                quantity: item.quantity
                            }))
                        });
                    }

                    // Pass 2: áp dụng hoàn kho thật
                    for (const item of orderItems) {
                        const latestBatch = batchByVariant[item.variant_id];
                        if (latestBatch) {
                            await supabase.from('inventory_batches')
                                .update({ quantity_remaining: latestBatch.quantity_remaining + item.quantity })
                                .eq('id', latestBatch.id);
                        } else {
                            await supabase.from('inventory_batches').insert([{
                                variant_id: item.variant_id,
                                original_quantity: item.quantity,
                                quantity_remaining: item.quantity,
                                cost_price: Number(overrides[item.variant_id]),
                                is_adjustment: true,
                                notes: `Hoàn kho từ đơn trả hàng #${id}`
                            }]);
                        }
                    }
                }
            }
        }

        const { data, error } = await supabase
            .from('orders')
            .update(updateData)
            .eq('id', id)
            .select()
            .single();

        if (error) throw error;
        
        if (status === 'shipping' && trackingCode) {
            console.log("📧 Đang gửi email tracking cho khách...");
            sendShippingConfirmation(data, trackingCode, skip_ghn).catch(err => console.error("Mail Error:", err));
        }

        res.json({ success: true, message: 'Cập nhật thành công', data: data });

    } catch (error) {
        console.error("Update Order Error:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};

exports.createAdminOrder = async (req, res) => {
    try {
        const { customer, items, payment_method, note, shipping_fee, is_paid, voucher_code, discount_amount } = req.body;
        const discountAmt = Number(discount_amount) || 0;

        let customerId = null;
        const { data: existingCus } = await supabase
            .from('customers')
            .select('id')
            .eq('phone', customer.phone)
            .single();

        if (existingCus) {
            customerId = existingCus.id;
        } else {
            const { data: newCus, error: createError } = await supabase
                .from('customers')
                .insert([{
                    full_name: customer.fullName,
                    phone: customer.phone,
                    address: customer.address || "Tại quầy",
                    email: customer.email || null
                }])
                .select()
                .single();
            
            if (createError) throw new Error("Lỗi tạo khách hàng: " + createError.message);
            customerId = newCus.id;
        }

        const itemTotal = items.reduce((sum, item) => sum + (item.price * item.quantity), 0);
        const orderCode = `#ADM-${Date.now().toString().slice(-6)}`;
        
        const finalShippingFee = shipping_fee !== undefined ? Number(shipping_fee) : 20000;

        let finalNote = note || "";
        if (is_paid === true || is_paid === 'true') {
            finalNote += " [ĐÃ THANH TOÁN]";
        }

        // Tra promotion_id từ mã voucher (bảng orders lưu promotion_id, không lưu voucher_code)
        let promotionId = null;
        let promoRow = null;
        if (voucher_code && discountAmt > 0) {
            const { data: promo } = await supabase.from('promotions').select('id, used_count').eq('code', voucher_code.toUpperCase().trim()).maybeSingle();
            if (promo) { promotionId = promo.id; promoRow = promo; }
        }

        const orderPayload = {
            code: orderCode,
            customer_id: customerId,
            customer_name: customer.fullName,
            customer_phone: customer.phone,
            customer_address: customer.address || "Tại quầy",
            subtotal: itemTotal,
            total_amount: Math.max(0, itemTotal + finalShippingFee - discountAmt),
            shipping_fee: finalShippingFee,
            discount_amount: discountAmt,
            promotion_id: promotionId,
            payment_method: payment_method || 'cod',
            status: 'pending',
            note: finalNote.trim()
        };

        const { data: order, error: orderError } = await supabase
            .from('orders')
            .insert([orderPayload])
            .select()
            .single();

        if (orderError) throw orderError;

        // Tăng lượt dùng voucher (nếu có áp mã)
        if (promoRow) {
            await supabase.from('promotions').update({ used_count: (promoRow.used_count || 0) + 1 }).eq('id', promoRow.id);
        }

        const orderItemsData = [];

        for (const item of items) {
            const { data: latestBatch } = await supabase
                .from('inventory_batches')
                .select('cost_price')
                .eq('variant_id', item.variant_id)
                .order('created_at', { ascending: false }) 
                .limit(1)
                .single();

            const unitCost = latestBatch ? Number(latestBatch.cost_price) : 0;
            const totalCogs = unitCost * item.quantity;

            orderItemsData.push({
                order_id: order.id,
                variant_id: item.variant_id,
                quantity: item.quantity,
                price_at_purchase: item.price || 0,
                cogs_total: totalCogs 
            });
        }

        const { error: itemsError } = await supabase.from('order_items').insert(orderItemsData);
        if (itemsError) throw itemsError;

        console.log("--- BẮT ĐẦU TRỪ KHO FIFO ---");

        for (const item of items) {
            let remainingNeeded = item.quantity; 

            const { data: batches } = await supabase
                .from('inventory_batches')
                .select('id, quantity_remaining, created_at')
                .eq('variant_id', item.variant_id)
                .gt('quantity_remaining', 0) 
                .order('created_at', { ascending: true }); 

            if (batches && batches.length > 0) {
                for (const batch of batches) {
                    if (remainingNeeded <= 0) break; 

                    const deductAmount = Math.min(batch.quantity_remaining, remainingNeeded);

                    await supabase
                        .from('inventory_batches')
                        .update({ quantity_remaining: batch.quantity_remaining - deductAmount })
                        .eq('id', batch.id);

                    console.log(`-> Trừ ${deductAmount} từ Batch #${batch.id}`);
                    remainingNeeded -= deductAmount;
                }
            }

            const { data: variant } = await supabase
                .from('product_variants')
                .select('quantity_remaining') 
                .eq('id', item.variant_id)
                .single();

            if (variant) {
                const newTotal = Math.max(0, (variant.quantity_remaining || 0) - item.quantity);
                
                await supabase
                    .from('product_variants')
                    .update({ quantity_remaining: newTotal }) 
                    .eq('id', item.variant_id);
            }
        }
        console.log("--- HOÀN TẤT TRỪ KHO ---");

        res.json({ success: true, message: "Tạo đơn thành công!", orderCode });

    } catch (error) {
        console.error("Create Admin Order Error:", error);
        if (!res.headersSent) {
            res.status(500).json({ success: false, message: error.message });
        }
    }
};

exports.bulkUpdateOrderStatus = async (req, res) => {
    try {
        const { orderIds, status, restock, skip_ghn } = req.body;

        if (!orderIds || !Array.isArray(orderIds) || orderIds.length === 0) {
            return res.status(400).json({ success: false, message: "Chưa chọn đơn hàng nào" });
        }

        console.log(`📦 Bulk Update: ${orderIds.length} đơn -> ${status}`);
        const results = { success: [], failed: [] };

        for (const id of orderIds) {
            try {
                const { data: currentOrder } = await supabase.from('orders').select('*, order_items(*)').eq('id', id).single();
                if (!currentOrder) continue;

                let trackingCode = currentOrder.shipping_tracking_code;
                let updateData = { status };

                if (status === 'shipping' && !trackingCode && !skip_ghn) {
                    try {
                        trackingCode = await createGHNOrder(currentOrder);
                        updateData.shipping_tracking_code = trackingCode;
                    } catch (e) {
                        console.error(`Lỗi GHN đơn ${id}:`, e.message);
                    }
                }

                if (status === 'returned' && restock === true && currentOrder.status !== 'returned') {
                    const orderItems = currentOrder.order_items;
                    if (orderItems && orderItems.length > 0) {
                        // Pass 1: biến thể nào chưa từng có lô kho nào thì KHÔNG được tự ý tạo lô 0đ —
                        // fail riêng đơn này (không chặn cả loạt), admin xử lý thủ công qua trang chi tiết đơn.
                        const batchByVariant = {};
                        for (const item of orderItems) {
                            const { data: batch } = await supabase.from('inventory_batches')
                                .select('id, quantity_remaining')
                                .eq('variant_id', item.variant_id)
                                .order('created_at', { ascending: false }).limit(1).single();
                            batchByVariant[item.variant_id] = batch || null;
                            if (!batch) {
                                throw new Error(`Biến thể #${item.variant_id} chưa từng có lô kho nào — cần nhập giá vốn thủ công qua trang chi tiết đơn hàng.`);
                            }
                        }

                        for (const item of orderItems) {
                            const batch = batchByVariant[item.variant_id];
                            await supabase.from('inventory_batches').update({ quantity_remaining: batch.quantity_remaining + item.quantity }).eq('id', batch.id);
                        }
                    }
                }

                await supabase.from('orders').update(updateData).eq('id', id);
                
                if (status === 'shipping' && trackingCode) {
                    sendShippingConfirmation(currentOrder, trackingCode).catch(console.error);
                }

                results.success.push(id);

            } catch (err) {
                results.failed.push({ id, reason: err.message });
            }
        }

        res.json({ success: true, message: `Đã xử lý: ${results.success.length} thành công, ${results.failed.length} lỗi`, results });

    } catch (error) {
        console.error("Bulk Update Error:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};

async function decreaseStock(variantId, qtyNeeded) {
    const { data: batches } = await supabase
        .from('inventory_batches')
        .select('*')
        .eq('variant_id', variantId)
        .gt('quantity_remaining', 0)
        .order('created_at', { ascending: true });

    let remainingToDeduct = qtyNeeded;

    for (const batch of batches) {
        if (remainingToDeduct <= 0) break;

        const deduct = Math.min(batch.quantity_remaining, remainingToDeduct);
        
        await supabase
            .from('inventory_batches')
            .update({ quantity_remaining: batch.quantity_remaining - deduct })
            .eq('id', batch.id);

        remainingToDeduct -= deduct;
    }
}

exports.updateOrderDetails = async (req, res) => {
    try {
        const { id } = req.params;
        const { customer_name, customer_phone, customer_address, note } = req.body;

        const { data, error } = await supabase
            .from('orders')
            .update({ 
                customer_name, 
                customer_phone, 
                customer_address, 
                note 
            })
            .eq('id', id)
            .select()
            .single();

        if (error) throw error;

        res.json({ success: true, message: 'Cập nhật thông tin thành công', data });

    } catch (error) {
        console.error("Update Order Details Error:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};

const translateColorToEn = (color) => {
    if (!color) return '';
    const normalized = color.toString().toLowerCase().trim();
    const colorMap = {
        'xanh': 'Blue',
        'xanh dương': 'Blue',
        'xanh nước biển': 'Blue',
        'xanh navy': 'Navy Blue',
        'xanh lá': 'Green',
        'xanh rêu': 'Olive Green',
    };
    return colorMap[normalized] || color;
};

exports.exportOrdersToSapoExcel = async (req, res) => {
    try {
        const { startDate, endDate, ids } = req.query;

        const formatSapoPhone = (phone) => {
            if (!phone) return null;
            let cleaned = phone.toString().replace(/\D/g, '');
            if (cleaned.startsWith('84')) {
                cleaned = '0' + cleaned.slice(2);
            } else if (!cleaned.startsWith('0')) {
                cleaned = '0' + cleaned;
            }
            const vnPhoneRegex = /^0[35789]\d{8}$/;
            if (vnPhoneRegex.test(cleaned)) {
                return cleaned; 
            }
            return null;
        };

        let query = supabase
            .from('orders')
            .select(`
                *,
                customers ( email ),
                order_items (
                    quantity, price_at_purchase,
                    variants (
                        sku, size, color,
                        products ( name )
                    )
                )
            `)
            .order('created_at', { ascending: true });

        if (ids) {
            const idArray = ids.split(',').map(id => id.trim());
            query = query.in('id', idArray);
        } else {
            if (startDate) {
                query = query.gte('created_at', startDate);
            }
            if (endDate) {
                const end = new Date(endDate);
                end.setHours(23, 59, 59, 999);
                query = query.lte('created_at', end.toISOString());
            }
        }

        const { data: orders, error } = await query;
        if (error) throw error;

        if (orders && orders.length > 0) {
            const exportedIds = orders.map(o => o.id);
            const currentTime = new Date().toISOString();
            
            supabase
                .from('orders')
                .update({ exported_at: currentTime })
                .in('id', exportedIds)
                .then(({ error: updateError }) => {
                    if (updateError) console.error("Lỗi cập nhật exported_at:", updateError);
                });
        }

        const workbook = new exceljs.Workbook();
        const worksheet = workbook.addWorksheet('FileNhapDonHang');

        worksheet.addRow([
            'STT*', 'Thông tin đơn hàng', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '',
            'Thông tin mua hàng', '', '', '', '', '', '', '', '', '', '', '', 'Thuế', '',
            'Khách hàng', '', 'Địa chỉ giao hàng', '', '', '', '', '', '', 'Thông tin khác', '', '', ''
        ]);
        worksheet.addRow([
            '', 'Mã đơn hàng', 'Nguồn đơn hàng', 'Ngày đặt hàng', 'Tác động tồn kho', 'Cho phép bán âm', 'Gửi email thông báo', 'Giá đã bao gồm thuế', 'Trạng thái thanh toán', 'Phương thức thanh toán', 'Trạng thái giao hàng', 'Hình thức giao hàng', 'Đối tác vận chuyển', 'Phí giao hàng', 'Giảm giá đơn hàng', '', '',
            'Mã phiên bản', 'Tên sản phẩm', 'Tên phiên bản', 'SKU', 'Đơn vị', 'Số lượng*', 'Giá bán', 'Giảm giá sản phẩm', 'Khối lượng', 'Yêu cầu vận chuyển', 'Ghi chú sản phẩm', 'Nhãn hiệu', '', '',
            'Số điện thoại', 'Email', 'Họ khách hàng', 'Tên khách hàng', 'SĐT giao hàng', 'Địa chỉ', 'Tỉnh thành', 'Quận huyện', 'Phường xã', 'SĐT nhân viên phụ trách', 'Ghi chú', 'Tags', 'Tham chiếu'
        ]);
        worksheet.addRow([
            '', '', '', '', '', '', '', '', '', '', '', '', '', '', '%', 'VND', 'Mô tả',
            '', '', '', '', '', '', '', '', '', '', '', '', 'Tỉ lệ', 'Số tiền',
            '', '', '', '', '', '', '', '', '', '', '', '', ''
        ]);

        worksheet.mergeCells('B1:Q1');
        worksheet.mergeCells('R1:AC1');
        worksheet.mergeCells('AD1:AE1');
        worksheet.mergeCells('AF1:AG1');
        worksheet.mergeCells('AH1:AN1');
        worksheet.mergeCells('AO1:AR1');

        let stt = 1;
        orders.forEach(order => {
            const date = new Date(order.created_at);
            const vnTime = new Date(date.getTime() + 7 * 60 * 60 * 1000); 
            const formattedDate = vnTime.toISOString().replace('T', ' ').substring(0, 16); 

            const isPaid = order.payment_method !== 'cod' ? 'Đã thanh toán' : (['completed'].includes(order.status) ? 'Đã thanh toán' : 'Chưa thanh toán');
            const paymentMethodStr = order.payment_method === 'cod' ? 'Thanh toán COD' : 'Chuyển khoản';
            
            let deliveryStatus = 'Chưa giao hàng';
            if (order.status === 'shipping') deliveryStatus = 'Đang giao hàng';
            if (order.status === 'completed') deliveryStatus = 'Đã giao hàng';

            let province = null, district = null, ward = null, street = order.customer_address || null;
            if (street) {
                const addrParts = street.split(',').map(s => s.trim());
                if (addrParts.length >= 4) {
                    province = addrParts[addrParts.length - 1];
                    district = addrParts[addrParts.length - 2];
                    ward = addrParts[addrParts.length - 3];
                    street = addrParts.slice(0, addrParts.length - 3).join(', ');
                }
            }

            const sapoPhone = formatSapoPhone(order.customer_phone);

            let orderSource = 'Web';
            
            if (order.note) {
                let cleanNote = order.note.replace(/\r?\n|\r/g, ' ');
                cleanNote = cleanNote.replace(/[\[\(]?đã thanh toán[\]\)]?/gi, '');
                cleanNote = cleanNote.replace(/[\[\(]?chưa thanh toán[\]\)]?/gi, '');
                cleanNote = cleanNote.replace(/\s+/g, ' ').replace(/^[-,\s]+|[-,\s]+$/g, '').trim();

                if (cleanNote) {
                    orderSource += ` - ${cleanNote}`;
                }
            }

            let isPrepaid = false;
            if (order.code && order.code.startsWith('ORD')) {
                isPrepaid = true;
                if (order.customer_name) {
                    orderSource += ` - ${order.customer_name}`;
                }
            }
            if (order.note && order.note.toLowerCase().includes('đã thanh toán')) {
                isPrepaid = true;
            }

            if (isPrepaid) {
                orderSource += ' - R';
            }

            if (order.order_items && order.order_items.length > 0) {
                order.order_items.forEach((item, index) => {
                    const isFirst = index === 0;

                    worksheet.addRow([
                        stt, 
                        isFirst ? order.code : null, 
                        isFirst ? orderSource : null,  
                        isFirst ? formattedDate : null, 
                        isFirst ? 'Có' : null, 
                        isFirst ? 'Không' : null, 
                        isFirst ? 'Có' : null, 
                        isFirst ? 'Có' : null, 
                        isFirst ? isPaid : null, 
                        isFirst ? paymentMethodStr : null, 
                        isFirst ? deliveryStatus : null, 
                        isFirst ? 'Giao hàng' : null, 
                        isFirst ? 'other' : null,  
                        isFirst ? (order.shipping_fee || 0) : null, 
                        null, 
                        isFirst ? (order.discount_amount || null) : null, 
                        isFirst ? (order.voucher_code || null) : null, 
                        null, 
                        item.variants?.products?.name || null, 
                        `${item.variants?.size || ''} - ${translateColorToEn(item.variants?.color)}`.trim(), 
                        item.variants?.sku || null, 
                        'Cái', 
                        item.quantity, 
                        item.price_at_purchase, 
                        null, 
                        null, 
                        'Có', 
                        null, 
                        null, 
                        null, 
                        null, 
                        isFirst ? sapoPhone : null, 
                        isFirst ? (order.customers?.email || null) : null, 
                        isFirst ? order.customer_name : null, 
                        null, 
                        isFirst ? sapoPhone : null, 
                        isFirst ? street : null, 
                        isFirst ? province : null, 
                        isFirst ? district : null, 
                        isFirst ? ward : null, 
                        null, 
                        isFirst ? (order.note || null) : null, 
                        null, 
                        null  
                    ]);
                });
            }
            stt++;
        });

        res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        res.setHeader('Content-Disposition', `attachment; filename=Sapo_Orders_Export_${new Date().toISOString().slice(0,10)}.xlsx`);

        await workbook.xlsx.write(res);
        res.end();

    } catch (error) {
        console.error("Export Sapo Orders Error:", error);
        res.status(500).json({ success: false, message: 'Lỗi xuất file Excel: ' + error.message });
    }
};

exports.getAccessoryProduct = async (req, res) => {
    try {
        const { data, error } = await supabase
            .from('products')
            .select(`
                *,
                variants (*)
            `)
            .eq('name', 'Phụ kiện BrownVN')
            .single();

        if (error) {
            return res.json({ success: true, data: null });
        }

        res.json({ success: true, data });
    } catch (error) {
        console.error("Get Accessory Error:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};