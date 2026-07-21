const supabase = require('../config/supabase');

// --- 1. NHÀ CUNG CẤP ---
exports.getSuppliers = async (req, res) => {
    const { data, error } = await supabase.from('suppliers').select('*').order('id', { ascending: false });
    if (error) return res.status(500).json({ success: false, message: error.message });
    res.json({ success: true, data });
};

exports.createSupplier = async (req, res) => {
    const { name } = req.body; // Bạn có thể thêm address, phone nếu muốn
    const { data, error } = await supabase.from('suppliers').insert([{ name }]).select().single();
    if (error) return res.status(500).json({ success: false, message: error.message });
    res.json({ success: true, data });
};

// --- 2. CHI NHÁNH (STORES) ---
exports.getStores = async (req, res) => {
    try {
        const { data, error } = await supabase.from('stores').select('*').order('id', { ascending: true });
        if (error) throw error;
        res.json({ success: true, data });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

exports.createStore = async (req, res) => {
    try {
        const { name } = req.body; // Chỉ cần tên là đủ tạo nhanh
        if (!name) return res.status(400).json({ success: false, message: "Tên chi nhánh là bắt buộc" });

        const { data, error } = await supabase
            .from('stores')
            .insert([{ name, is_active: true }])
            .select()
            .single();

        if (error) throw error;
        res.json({ success: true, data });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};



// --- 4. NHẬP KHO (Lưu store_id) ---
exports.inboundStock = async (req, res) => {
    try {
        const { supplier_id, store_id, items, note } = req.body;

        if (!items || items.length === 0) return res.status(400).json({ success: false, message: "Chưa chọn sản phẩm" });
        if (!store_id) return res.status(400).json({ success: false, message: "Chưa chọn Chi nhánh nhập về" });

        // [MỚI] Server tự kiểm tra lại giá vốn — UI có "required" nhưng đó chỉ là JS phía
        // client, không chặn được nếu ai đó gọi thẳng API. Chặn ở đây để không lọt lô 0đ.
        const invalidItem = items.find(item => !(Number(item.cost_price) > 0));
        if (invalidItem) {
            return res.status(400).json({
                success: false,
                message: `Thiếu giá vốn hợp lệ cho biến thể #${invalidItem.variant_id}. Vui lòng nhập giá vốn > 0 cho tất cả sản phẩm trước khi nhập kho.`
            });
        }

        // Tính tổng tiền
        const totalCost = items.reduce((sum, item) => sum + (item.quantity * item.cost_price), 0);

        // 1. Tạo Phiếu Nhập (purchase_orders)
        const { data: po, error: poError } = await supabase
            .from('purchase_orders')
            .insert([{
                supplier_id: supplier_id || null,
                store_id: store_id,
                total_cost: totalCost,
                note: note
                // id, purchase_date tự động sinh
            }])
            .select()
            .single();

        if (poError) throw poError;

        // 2. Tạo Chi tiết nhập kho (purchase_items)
        // Chuẩn bị dữ liệu
        const purchaseItemsData = items.map(item => ({
            purchase_order_id: po.id,
            variant_id: item.variant_id,
            quantity: item.quantity,
            unit_cost: item.cost_price // <-- Đúng tên cột schema của bạn
        }));

        // Insert và lấy lại dữ liệu vừa tạo (để lấy ID cho bước sau)
        const { data: insertedItems, error: itemsError } = await supabase
            .from('purchase_items')
            .insert(purchaseItemsData)
            .select();

        if (itemsError) throw itemsError;

        // 3. Tạo Lô hàng tồn kho (inventory_batches) - Dựa trên items vừa tạo
        const batchData = insertedItems.map(pItem => ({
            store_id: store_id,
            variant_id: pItem.variant_id,
            purchase_item_id: pItem.id, // <-- Link chính xác tới dòng chi tiết nhập
            original_quantity: pItem.quantity,
            quantity_remaining: pItem.quantity, // Mới nhập thì còn nguyên
            cost_price: pItem.unit_cost
            // created_at tự động sinh (dùng để tính FIFO)
        }));

        const { error: batchError } = await supabase
            .from('inventory_batches')
            .insert(batchData);

        if (batchError) throw batchError;

        // 4. Ghi nhận Chi phí (Expenses)
        await supabase.from('expenses').insert([{
            title: `Nhập hàng Phiếu #${po.id}`,
            amount: totalCost,
            category: 'cost_of_goods',
            date: new Date()
        }]);

        res.json({ success: true, message: "Nhập kho thành công!", poId: po.id });

    } catch (error) {
        console.error("Lỗi nhập kho:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};

// --- 5. LẤY TỒN KHO (Đã sửa: Tính toán Tổng giá trị tồn kho) ---
exports.getStock = async (req, res) => {
    try {
        const { data, error } = await supabase
            .from('inventory_batches')
            .select(`
                *,
                stores (name),
                variants (
                    id, sku, size, color,
                    products (name, images)
                )
            `)
            .gt('quantity_remaining', 0) // Chỉ lấy lô còn hàng
            .order('created_at', { ascending: true }); // FIFO

        if (error) throw error;

        // --- [FIX BẮT ĐẦU] ---
        // Tính tổng giá trị tồn kho ngay tại Backend để đảm bảo đồng bộ
        // Logic: Tổng = Tổng (Số lượng còn lại * Giá vốn lô hàng)
        const totalStockValue = data.reduce((sum, batch) => {
            const quantity = batch.quantity_remaining || 0;
            const cost = batch.cost_price || 0; 
            return sum + (quantity * cost);
        }, 0);
        // --- [FIX KẾT THÚC] ---

        res.json({ 
            success: true, 
            data: data, 
            totalValue: totalStockValue // <--- Frontend lấy số này hiển thị vào thẻ "Tổng giá trị tồn"
        });

    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// --- 6. [MỚI] LẤY LỊCH SỬ NHẬP ---
exports.getHistory = async (req, res) => {
    try {
        const { data, error } = await supabase
            .from('inventory_batches')
            .select(`
                id,
                variant_id,  
                created_at,
                original_quantity,
                quantity_remaining,
                cost_price,
                purchase_item_id,
                stores (name),
                variants (
                    size, color,
                    products (name)
                )
            `)
            .order('created_at', { ascending: false });

        if (error) throw error;
        res.json({ success: true, data });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

exports.adjustStock = async (req, res) => {
  // Đảm bảo import đúng client (nếu chưa có ở đầu file thì uncomment dòng dưới)
  // const supabase = require('../config/supabase'); 

  try {
    const { variant_id, quantity_change, store_id, reason, cost_price } = req.body;
    const changeAmount = Number(quantity_change);

    // 1. Validate cơ bản
    if (!variant_id || changeAmount === 0) {
      return res.status(400).json({ success: false, message: 'Dữ liệu không hợp lệ hoặc không có thay đổi' });
    }

    // ==================================================================
    // TRƯỜNG HỢP A: GIẢM KHO (changeAmount < 0)
    // Sửa lỗi: Trừ trực tiếp vào lô hàng có sẵn (FIFO) để giảm đúng giá trị tiền
    // ==================================================================
    if (changeAmount < 0) {
        let qtyToDeduct = Math.abs(changeAmount);

        // Lấy các lô hàng còn tồn, sắp xếp theo CŨ NHẤT (FIFO)
        const { data: batches, error: fetchError } = await supabase
            .from('inventory_batches')
            .select('id, quantity_remaining, cost_price')
            .eq('variant_id', variant_id)
            .gt('quantity_remaining', 0)
            .order('created_at', { ascending: true });

        if (fetchError) throw fetchError;

        // Kiểm tra tổng tồn
        const currentTotal = batches.reduce((sum, b) => sum + b.quantity_remaining, 0);
        if (currentTotal < qtyToDeduct) {
            return res.status(400).json({ 
                success: false, 
                message: `Không đủ hàng để trừ! Tồn kho hiện tại: ${currentTotal}, Cần trừ: ${qtyToDeduct}` 
            });
        }

        // Thực hiện trừ dần từng lô
        for (const batch of batches) {
            if (qtyToDeduct <= 0) break;

            const deduct = Math.min(batch.quantity_remaining, qtyToDeduct);
            
            // Cập nhật lô hàng này
            await supabase
                .from('inventory_batches')
                .update({ quantity_remaining: batch.quantity_remaining - deduct })
                .eq('id', batch.id);

            qtyToDeduct -= deduct;
        }

        return res.json({ success: true, message: 'Đã cập nhật giảm tồn kho thành công' });
    }

    // ==================================================================
    // TRƯỜNG HỢP B: TĂNG KHO (changeAmount > 0)
    // Sửa lỗi: Phải lấy GIÁ VỐN GẦN NHẤT thay vì để 0. Nếu không đoán được
    // giá và client cũng không tự nhập (cost_price) thì CHẶN, không tạo lô
    // giá 0đ — tránh làm sai "Tổng giá trị tồn kho".
    // ==================================================================
    else {
        let estimatedCost = Number(cost_price) > 0 ? Number(cost_price) : 0;

        if (!estimatedCost) {
            // Tìm giá vốn của lô nhập gần nhất có giá > 0
            const { data: lastBatch } = await supabase
                .from('inventory_batches')
                .select('cost_price')
                .eq('variant_id', variant_id)
                .gt('cost_price', 0)
                .order('created_at', { ascending: false })
                .limit(1)
                .single();

            if (lastBatch) {
                estimatedCost = lastBatch.cost_price;
            } else {
                // Nếu là sản phẩm mới tinh chưa từng nhập, lấy tạm giá gốc từ bảng variants
                const { data: variantInfo } = await supabase
                    .from('variants')
                    .select('original_price, products(base_price)')
                    .eq('id', variant_id)
                    .single();

                if (variantInfo) {
                    estimatedCost = variantInfo.original_price || variantInfo.products?.base_price || 0;
                }
            }
        }

        if (!estimatedCost) {
            return res.status(400).json({
                success: false,
                needsCostPrice: true,
                message: 'Biến thể này chưa từng có giá vốn nào (chưa nhập kho lần nào và cũng chưa có giá gốc). Vui lòng nhập giá vốn thủ công để tiếp tục.'
            });
        }

        // Tạo lô hàng mới với giá vốn vừa tìm được
        const { data, error } = await supabase
            .from('inventory_batches')
            .insert([{
                variant_id: variant_id,
                store_id: store_id || null,
                original_quantity: changeAmount,
                quantity_remaining: changeAmount,
                cost_price: estimatedCost, // <--- ĐÃ FIX: Lưu giá vốn để tính đúng tổng tiền
                is_adjustment: true,
                notes: reason || 'Điều chỉnh tăng thủ công'
            }])
            .select();

        if (error) throw error;

        return res.json({ 
            success: true, 
            message: 'Đã cập nhật tăng tồn kho thành công', 
            data: data[0] 
        });
    }

  } catch (error) {
    console.error("Lỗi Adjust Stock:", error);
    res.status(500).json({ success: false, message: error.message });
  }
};

// --- XỬ LÝ HÀNG LỖI (DEFECTIVE ITEMS) ---
exports.reportDefectiveItem = async (req, res) => {
    try {
        // [ĐÃ SỬA] Nhận thêm product_name và variant_name từ Frontend
        const { variant_id, quantity, reason, store_id, product_name, variant_name } = req.body;

        if (!variant_id || !quantity || quantity <= 0) {
            return res.status(400).json({ success: false, message: "Dữ liệu không hợp lệ" });
        }

        const qtyToDeduct = Number(quantity);

        // 1. Lấy các lô hàng đang còn tồn kho của phân loại này
        const { data: batches, error: batchError } = await supabase
            .from('inventory_batches')
            .select('*')
            .eq('variant_id', variant_id)
            .gt('quantity_remaining', 0)
            .order('created_at', { ascending: true });

        if (batchError) throw batchError;

        let remainingToDeduct = qtyToDeduct;
        let totalLoss = 0;
        const updates = [];

        // 2. Tính toán trừ kho và gom giá vốn
        for (const batch of batches) {
            if (remainingToDeduct <= 0) break;

            const deductQty = Math.min(batch.quantity_remaining, remainingToDeduct);
            totalLoss += (deductQty * batch.cost_price);
            remainingToDeduct -= deductQty;

            updates.push({
                id: batch.id,
                quantity_remaining: batch.quantity_remaining - deductQty
            });
        }

        if (remainingToDeduct > 0) {
            return res.status(400).json({ success: false, message: "Số lượng báo lỗi lớn hơn số lượng tồn kho hiện có!" });
        }

        // 3. Thực hiện trừ kho trên các lô thật
        for (const update of updates) {
            const { error: updateError } = await supabase
                .from('inventory_batches')
                .update({ quantity_remaining: update.quantity_remaining })
                .eq('id', update.id);
            if (updateError) throw updateError;
        }

        // 4. [FIX LỖI TRỪ ĐÚP]: Lưu lịch sử Hàng lỗi
        const { error: logError } = await supabase.from('inventory_batches').insert([{
            variant_id,
            store_id: store_id || 1, 
            original_quantity: -qtyToDeduct, 
            quantity_remaining: 0, // <--- QUAN TRỌNG: Để 0 để không bị cộng dồn thành trừ đúp tồn kho
            cost_price: Math.round(totalLoss / qtyToDeduct), 
            is_adjustment: true,
            notes: `[HÀNG LỖI] ${reason}`
        }]);
        if (logError) throw logError;

        // 5. [FIX LỖI GHI CHÚ CHI PHÍ]: Ghi chi tiết vào bảng Expenses
        const expenseNote = `Hàng lỗi: ${quantity}x ${product_name || ''} ${variant_name ? `(${variant_name})` : ''} - Lý do: ${reason}`;
        
        const { error: expenseError } = await supabase.from('expenses').insert([{
            store_id: store_id || 1,
            category_id: 1, 
            amount: totalLoss,
            note: expenseNote, // <--- Ghi chú chi tiết sẽ hiện ở Báo cáo chi phí
            expense_date: new Date().toISOString().split('T')[0]
        }]);
        if (expenseError) throw expenseError;

        res.json({ success: true, message: "Đã trừ kho và hạch toán chi phí!", totalLoss });

    } catch (error) {
        console.error("Lỗi reportDefectiveItem:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};

// Hàm lấy lịch sử hàng lỗi ra màn hình
exports.getDefectiveLogs = async (req, res) => {
    try {
        const { data, error } = await supabase
            .from('inventory_batches')
            .select(`
                *,
                variants (
                    size, color, sku,
                    products ( name, images ) 
                )
            `)
            // Dùng ilike tìm kiếm mờ an toàn hơn
            .ilike('notes', '%[HÀNG LỖI]%') 
            .order('created_at', { ascending: false });

        if (error) throw error;
        res.json({ success: true, data });
    } catch (error) {
        console.error("Lỗi getDefectiveLogs:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};