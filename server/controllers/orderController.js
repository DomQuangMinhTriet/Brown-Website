const supabase = require('../config/supabase');
const { sendOrderConfirmation, sendShippingConfirmation, sendNewOrderNotifyToAdmin } = require('../services/emailService');
const { calculateShippingFee, createGHNOrder } = require('../services/shippingService'); // <--- IMPORT HELPER
const { z } = require('zod');

// --- 1. CẬP NHẬT BỘ LỌC DỮ LIỆU (VALIDATION SCHEMA) ---
const orderSchema = z.object({
    customer: z.object({
        fullName: z.string().min(2, "Tên phải có ít nhất 2 ký tự"),
        
        // Dùng min(8) để chấp nhận cả SĐT quốc tế và SĐT Việt Nam
        phone: z.string().min(8, "Số điện thoại phải có ít nhất 8 ký tự"), 
        
        // Cho phép email trống, null hoặc đúng định dạng
        email: z.string().email("Email không hợp lệ").nullable().optional().or(z.literal('')),
        
        address: z.string().min(5, "Địa chỉ quá ngắn"),
        
        // Thêm nullable() cho tất cả các trường có thể bị truyền null từ Frontend
        province: z.string().nullable().optional(),
        district: z.string().nullable().optional(),
        ward: z.string().nullable().optional(),
        
        province_id: z.any().nullable().optional(), 
        district_id: z.any().nullable().optional(),
        ward_code: z.any().nullable().optional(),
        
        country: z.string().nullable().optional(),
        zipcode: z.string().nullable().optional(), // <--- Fix lỗi nội địa ở đây
        shipping_type: z.string().nullable().optional()
    }),
    items: z.array(z.object({
        variant_id: z.number().int().positive(),
        quantity: z.number().int().min(1, "Số lượng phải lớn hơn 0")
    })).min(1, "Giỏ hàng không được để trống"),
    
    // Giữ lại custom error của bạn và cho phép 'cod' nếu cần
    payment_method: z.enum(['done', 'banking', 'cod'], { 
        errorMap: () => ({ message: "Phương thức thanh toán không hợp lệ" }) 
    }).nullable().optional(),
    
    voucher_code: z.string().nullable().optional(),
    shipping_fee: z.number().min(0).default(0),
    note: z.string().nullable().optional(),
    
    // Các trường tiền tệ & ngôn ngữ quốc tế
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
            // Nếu dữ liệu sai, trả về lỗi ngay lập tức
            return res.status(400).json({ 
                success: false, 
                message: 'Dữ liệu không hợp lệ',
                errors: parseResult.error.issues.map(e => e.message) // Trả về danh sách lỗi cụ thể
            });
        }

        const { customer, items, payment_method, voucher_code, shipping_fee, note, lang } = parseResult.data;
        console.log("👉 Dữ liệu Customer sau khi Validate:", customer);
        // ==============================================================================
        // B. [ĐÃ CHỈNH SỬA] XÁC ĐỊNH KHÁCH HÀNG (Ưu tiên Login -> Tìm SĐT -> Tạo mới)
        // ==============================================================================
        let customerId = null;

        // 1. Kiểm tra nếu khách đã đăng nhập
        if (req.user && req.user.id) {
             const { data: cusData } = await supabase
                .from('customers')
                .select('id')
                .eq('user_id', req.user.id)
                .single();
             if (cusData) customerId = cusData.id;
        }

        // 2. Nếu chưa có ID (Khách vãng lai), tìm trong Database bằng Số điện thoại
        // Bước này giúp gộp đơn hàng vào lịch sử của khách cũ
        if (!customerId && customer.phone) {
            const { data: existingCus } = await supabase
                .from('customers')
                .select('id')
                .eq('phone', customer.phone)
                .single();

            if (existingCus) {
                // -> Tìm thấy khách cũ: Dùng ID đó luôn
                customerId = existingCus.id;
            } else {
                // -> Khách mới hoàn toàn: Tạo hồ sơ khách hàng mới
                const { data: newCus, error: createError } = await supabase
                    .from('customers')
                    .insert([{
                        full_name: customer.fullName || customer.name || "Khách mới",
                        phone: customer.phone,
                        email: customer.email || null,
                        address: customer.address || null
                        // Không có user_id vì là khách vãng lai
                    }])
                    .select('id')
                    .single();
                
                if (!createError && newCus) {
                    customerId = newCus.id;
                }
            }
        }
        // ==============================================================================
        // C. CHUẨN BỊ DỮ LIỆU & BẢO MẬT GIÁ + KIỂM TRA TỒN KHO THỰC TẾ
        // ==============================================================================
        const cleanItems = [];
        let subtotal_check = 0;

        const variantIds = items.map(i => i.variant_id);
        
        // [ĐÃ SỬA]: Truy vấn thêm inventory_batches để lấy số lượng tồn kho
        const { data: variantsDB, error: varError } = await supabase
            .from('variants')
            .select(`
                id, 
                current_price, 
                products(base_price),
                inventory_batches(quantity_remaining) 
            `)
            .in('id', variantIds);

        if (varError || !variantsDB) throw new Error("Lỗi khi lấy thông tin sản phẩm");

        for (const item of items) {
            const variant = variantsDB.find(v => v.id === item.variant_id);
            if (!variant) {
                return res.status(400).json({ success: false, message: `Sản phẩm không còn tồn tại.` });
            }

            // [LOGIC MỚI BỔ SUNG]: Tính tổng tồn kho hiện tại của sản phẩm này
            const totalStock = variant.inventory_batches
                ? variant.inventory_batches.reduce((sum, batch) => sum + (Number(batch.quantity_remaining) || 0), 0)
                : 0;

            // [CHẶN LỖI]: Trả về lỗi ngay nếu khách đặt lố số lượng đang có
            if (item.quantity > totalStock) {
                return res.status(400).json({ 
                    success: false, 
                    message: `Rất tiếc! Một sản phẩm trong giỏ hàng của bạn hiện chỉ còn ${totalStock} chiếc. Vui lòng cập nhật lại số lượng.` 
                });
            }

            // Ưu tiên giá sale (current_price), nếu không có lấy giá gốc
            const realPrice = variant.current_price || variant.products.base_price;
            
            // Lấy giá vốn từ lô hàng nhập mới nhất
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
                     if (promo.discount_type === 'percent') {
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
        // [QUAN TRỌNG] Gửi thêm thông tin ID địa chỉ vào p_customer_info để lưu DB
        const { data, error } = await supabase.rpc('create_order_transaction', {
            p_customer_id: customerId,
            p_customer_info: {
                name: customer.fullName,
                phone: customer.phone,
                email: customer.email,
                // Lưu địa chỉ dạng chuỗi hiển thị
                address: customer.address + (customer.province ? `, ${customer.district}, ${customer.province}` : ''),
                // Lưu ID địa chỉ để dùng cho GHN sau này
                province_id: customer.province_id,
                district_id: customer.district_id,
                ward_code: customer.ward_code
            },
            p_payment_method: payment_method,
            p_shipping_fee: shipping_fee, // Sử dụng phí ship frontend gửi lên (đã tính qua GHN)
            p_discount_amount: discount_amount,
            p_voucher_code: voucher_code || null,
            p_items: cleanItems // Array này giờ đã có cogs_total
        });

        if (error) {
            console.error("RPC Error:", error);
            return res.status(400).json({ success: false, message: error.message });
        }

        // ==============================================================================
        // F. [ĐÃ CHỈNH SỬA] GỬI EMAIL THÔNG BÁO (CHO KHÁCH & ADMIN)
        // ==============================================================================
        
        // Chuẩn bị dữ liệu hiển thị cho email
        const emailCustomerName = data.customer_name || customer.fullName || customer.name || "Quý khách";
        const rawTotalAmount = data.total_amount || (subtotal_check + shipping_fee - discount_amount);
        const emailAddress = customer.email;

        // 1. Gửi mail xác nhận cho Khách Hàng (nếu có email)
        if (emailAddress) {
            const orderInfoForMail = {
                customer_name: emailCustomerName,
                code: data.order_code,
                total_amount: rawTotalAmount, 
                shipping_tracking_code: 'Đang cập nhật' 
            };
            sendOrderConfirmation(orderInfoForMail, emailAddress, lang || 'vi').catch(err => console.error("Mail Khách Error:", err));
        }

        // 2. [MỚI] Gửi mail thông báo cho Admin (brownvn25@gmail.com)
        const adminOrderData = {
            id: data.order_code,            // Mã đơn hàng (ví dụ: #ORD-123)
            customer_name: emailCustomerName, // Tên khách
            phone: customer.phone,          // Số điện thoại
            total_amount: rawTotalAmount,   // Tổng tiền (để format lại trong service)
            payment_method: payment_method  // COD hoặc Banking
        };

        // Gọi hàm gửi mail Admin - dùng .catch để không làm lỗi request nếu mail server lỗi
        sendNewOrderNotifyToAdmin(adminOrderData).catch(err => console.error("Mail Admin Error:", err));

        // ==============================================================================
        
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

// BẮT ĐẦU ĐOẠN CẦN THAY THẾ (Hàm updateOrderStatus)
exports.updateOrderStatus = async (req, res) => {
    try {
        const { id } = req.params;
        // Nhận thêm tracking_code từ Frontend gửi lên
        const { status, restock, skip_ghn, tracking_code } = req.body; 

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

        // 2. LOGIC VẬN CHUYỂN (GHN & SPX)
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
            // Gán mã vận đơn SPX nếu có nhập
            if (tracking_code) {
                trackingCode = tracking_code;
                updateData.shipping_tracking_code = trackingCode;
            }
        }

        // 3. LOGIC HOÀN KHO
        if (status === 'cancelled') {
             console.log("ℹ️ Đơn hủy: Để Database Trigger tự động hoàn kho.");
        } else if (status === 'returned' && restock === true) {
            if (currentOrder.status !== 'returned') {
                console.log("🔄 Đang xử lý trả hàng (Code hoàn kho thủ công)...");
                const orderItems = currentOrder.order_items;
                if (orderItems && orderItems.length > 0) {
                    for (const item of orderItems) {
                        const { data: latestBatch } = await supabase.from('inventory_batches')
                            .select('id, quantity_remaining')
                            .eq('variant_id', item.variant_id)
                            .order('created_at', { ascending: false })
                            .limit(1)
                            .single();
                        
                        if (latestBatch) {
                            await supabase.from('inventory_batches')
                                .update({ quantity_remaining: latestBatch.quantity_remaining + item.quantity })
                                .eq('id', latestBatch.id);
                        } else {
                            await supabase.from('inventory_batches').insert([{
                                variant_id: item.variant_id,
                                original_quantity: item.quantity,
                                quantity_remaining: item.quantity,
                                cost_price: 0, is_adjustment: true,
                                notes: `Hoàn kho từ đơn trả hàng #${id}`
                            }]);
                        }
                    }
                }
            }
        }

        // 4. CẬP NHẬT TRẠNG THÁI VÀO DB
        const { data, error } = await supabase
            .from('orders')
            .update(updateData)
            .eq('id', id)
            .select()
            .single();

        if (error) throw error;
        
        // 5. GỬI EMAIL TỰ ĐỘNG KÈM LINK TRACKING (Truyền thêm skip_ghn để xác định là SPX)
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
        const { customer, items, payment_method, note, shipping_fee, is_paid } = req.body;

        // --- BƯỚC 1: TÌM HOẶC TẠO KHÁCH HÀNG (GIỮ NGUYÊN) ---
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

        // --- BƯỚC 2: TÍNH TOÁN TIỀN ---
        const itemTotal = items.reduce((sum, item) => sum + (item.price * item.quantity), 0);
        const orderCode = `#ADM-${Date.now().toString().slice(-6)}`;
        
        // [MỚI] Xử lý số tiền phí ship (Đảm bảo là số, nếu không có mặc định là 20k)
        const finalShippingFee = shipping_fee !== undefined ? Number(shipping_fee) : 20000;

        // --- BƯỚC 3: XỬ LÝ GHI CHÚ (GIỮ NGUYÊN) ---
        let finalNote = note || "";
        if (is_paid === true || is_paid === 'true') {
            finalNote += " [ĐÃ THANH TOÁN]";
        }

        // --- BƯỚC 4: TẠO ĐƠN HÀNG (ĐÃ SỬA PHÍ SHIP) ---
        const orderPayload = {
            code: orderCode,
            customer_id: customerId,
            customer_name: customer.fullName,
            customer_phone: customer.phone,
            customer_address: customer.address || "Tại quầy", 
            
            subtotal: itemTotal,      
            
            // [SỬA Ở ĐÂY] Tổng tiền = Tiền hàng + Phí ship
            total_amount: itemTotal + finalShippingFee,  
            
            // [SỬA Ở ĐÂY] Lưu phí ship thực tế thay vì số 0
            shipping_fee: finalShippingFee,          
            
            discount_amount: 0,       

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

        // --- BƯỚC 5: LƯU CHI TIẾT SẢN PHẨM (CẬP NHẬT TÍNH GIÁ VỐN) ---
        // Thay đổi cách duyệt để dùng await lấy giá vốn
        const orderItemsData = [];

        for (const item of items) {
            // [LOGIC MỚI] Lấy giá vốn từ lô hàng nhập mới nhất
            const { data: latestBatch } = await supabase
                .from('inventory_batches')
                .select('cost_price')
                .eq('variant_id', item.variant_id)
                .order('created_at', { ascending: false }) // Lấy lô mới nhất
                .limit(1)
                .single();

            const unitCost = latestBatch ? Number(latestBatch.cost_price) : 0;
            const totalCogs = unitCost * item.quantity;

            orderItemsData.push({
                order_id: order.id,
                variant_id: item.variant_id,
                quantity: item.quantity,
                price_at_purchase: item.price || 0,
                cogs_total: totalCogs // <--- [MỚI] Lưu giá vốn vào DB
            });
        }

        const { error: itemsError } = await supabase.from('order_items').insert(orderItemsData);
        if (itemsError) throw itemsError;

        // ============================================================
        // --- BƯỚC 6: TRỪ TỒN KHO THEO LÔ (FIFO - GIỮ NGUYÊN) ---
        // ============================================================
        console.log("--- BẮT ĐẦU TRỪ KHO FIFO ---");

        for (const item of items) {
            let remainingNeeded = item.quantity; // Số lượng cần trừ

            // A. Tìm các lô hàng (batches) còn hàng, sắp xếp cũ nhất lên đầu (created_at ASC)
            const { data: batches } = await supabase
                .from('inventory_batches')
                .select('id, quantity_remaining, created_at')
                .eq('variant_id', item.variant_id)
                .gt('quantity_remaining', 0) // Chỉ lấy lô > 0
                .order('created_at', { ascending: true }); // FIFO: Cũ nhất trước

            // B. Duyệt qua từng lô để trừ
            if (batches && batches.length > 0) {
                for (const batch of batches) {
                    if (remainingNeeded <= 0) break; // Đã trừ đủ thì dừng

                    // Lấy số lượng có thể trừ ở lô này (Min giữa cần trừ và có sẵn)
                    const deductAmount = Math.min(batch.quantity_remaining, remainingNeeded);

                    // Cập nhật lô hàng này
                    await supabase
                        .from('inventory_batches')
                        .update({ quantity_remaining: batch.quantity_remaining - deductAmount })
                        .eq('id', batch.id);

                    console.log(`-> Trừ ${deductAmount} từ Batch #${batch.id}`);
                    remainingNeeded -= deductAmount;
                }
            }

            // C. Cập nhật Tổng tồn kho (product_variants) để đồng bộ hiển thị
            // Lấy tổng tồn kho hiện tại
            const { data: variant } = await supabase
                .from('product_variants')
                .select('quantity_remaining') 
                .eq('id', item.variant_id)
                .single();

            if (variant) {
                // Trừ thẳng vào tổng số lượng
                const newTotal = Math.max(0, (variant.quantity_remaining || 0) - item.quantity);
                
                await supabase
                    .from('product_variants')
                    .update({ quantity_remaining: newTotal }) 
                    .eq('id', item.variant_id);
            }
        }
        console.log("--- HOÀN TẤT TRỪ KHO ---");

        // Chỉ gửi phản hồi 1 lần duy nhất ở cuối cùng
        res.json({ success: true, message: "Tạo đơn thành công!", orderCode });

    } catch (error) {
        console.error("Create Admin Order Error:", error);
        if (!res.headersSent) {
            res.status(500).json({ success: false, message: error.message });
        }
    }
};

// [THÊM MỚI] API XỬ LÝ HÀNG LOẠT (BULK UPDATE)
exports.bulkUpdateOrderStatus = async (req, res) => {
    try {
        const { orderIds, status, restock, skip_ghn } = req.body;

        if (!orderIds || !Array.isArray(orderIds) || orderIds.length === 0) {
            return res.status(400).json({ success: false, message: "Chưa chọn đơn hàng nào" });
        }

        console.log(`📦 Bulk Update: ${orderIds.length} đơn -> ${status}`);
        const results = { success: [], failed: [] };

        // Xử lý tuần tự từng đơn để đảm bảo logic kho/GHN an toàn
        for (const id of orderIds) {
            try {
                // 1. Lấy info đơn
                const { data: currentOrder } = await supabase.from('orders').select('*, order_items(*)').eq('id', id).single();
                if (!currentOrder) continue;

                let trackingCode = currentOrder.shipping_tracking_code;
                let updateData = { status };

                // 2. Xử lý GHN (Nếu chuyển sang shipping và chưa có mã)
                if (status === 'shipping' && !trackingCode && !skip_ghn) {
                    try {
                        trackingCode = await createGHNOrder(currentOrder);
                        updateData.shipping_tracking_code = trackingCode;
                    } catch (e) {
                        console.error(`Lỗi GHN đơn ${id}:`, e.message);
                        // Vẫn update trạng thái dù lỗi GHN để admin xử lý tay
                    }
                }

                // 3. Xử lý Hoàn kho (Nếu trả hàng)
                if (status === 'returned' && restock === true && currentOrder.status !== 'returned') {
                    const orderItems = currentOrder.order_items;
                    if (orderItems && orderItems.length > 0) {
                        for (const item of orderItems) {
                            const { data: batch } = await supabase.from('inventory_batches')
                                .select('id, quantity_remaining')
                                .eq('variant_id', item.variant_id)
                                .order('created_at', { ascending: false }).limit(1).single();
                            
                            if (batch) {
                                await supabase.from('inventory_batches').update({ quantity_remaining: batch.quantity_remaining + item.quantity }).eq('id', batch.id);
                            } else {
                                // Fallback tạo lô mới nếu không tìm thấy
                                await supabase.from('inventory_batches').insert([{ variant_id: item.variant_id, original_quantity: item.quantity, quantity_remaining: item.quantity, cost_price: 0, is_adjustment: true }]);
                            }
                        }
                    }
                }

                // 4. Update DB
                await supabase.from('orders').update(updateData).eq('id', id);
                
                // 5. Gửi mail nếu shipping
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
// 2. Hàm phụ trợ: Trừ kho theo nguyên tắc nhập trước xuất trước (FIFO)
async function decreaseStock(variantId, qtyNeeded) {
    // Lấy các lô hàng còn tồn của variant này, xếp theo cũ nhất trước
    const { data: batches } = await supabase
        .from('inventory_batches')
        .select('*')
        .eq('variant_id', variantId)
        .gt('quantity_remaining', 0)
        .order('created_at', { ascending: true });

    let remainingToDeduct = qtyNeeded;

    for (const batch of batches) {
        if (remainingToDeduct <= 0) break;

        // Lấy số lượng có thể trừ từ lô này
        const deduct = Math.min(batch.quantity_remaining, remainingToDeduct);
        
        // Cập nhật lại lô hàng
        await supabase
            .from('inventory_batches')
            .update({ quantity_remaining: batch.quantity_remaining - deduct })
            .eq('id', batch.id);

        remainingToDeduct -= deduct;
    }
}

// [THÊM MỚI] API CẬP NHẬT THÔNG TIN GIAO HÀNG & GHI CHÚ
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