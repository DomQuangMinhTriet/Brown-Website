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

// --- 5. LẤY TỒN KHO (Sửa lại cú pháp join bảng stores) ---
exports.getStock = async (req, res) => {
    try {
        const { data, error } = await supabase
            .from('inventory_batches')
            .select(`
                *,
                stores (name),  -- Join bảng stores lấy name
                variants (
                    id, sku, size, color,
                    products (name, images)
                )
            `)
            .gt('quantity_remaining', 0) // Chỉ lấy lô còn hàng
            .order('created_at', { ascending: true }); // FIFO

        if (error) throw error;
        res.json({ success: true, data });
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
  try {
    const { variant_id, quantity_change, store_id, reason } = req.body;

    // 1. Validate dữ liệu đầu vào
    if (!variant_id || quantity_change === undefined) {
      return res.status(400).json({ success: false, message: 'Thiếu thông tin' });
    }
    
    const changeAmount = Number(quantity_change);
    if (changeAmount === 0) return res.json({ success: true, message: 'Không thay đổi' });

    // 2. [QUAN TRỌNG] Nếu là phép TRỪ (số âm), phải kiểm tra tồn kho hiện tại
    if (changeAmount < 0) {
        // Lấy tất cả các batch của sản phẩm này để tính tổng
        const { data: currentBatches, error: fetchError } = await supabase
            .from('inventory_batches')
            .select('quantity_remaining')
            .eq('variant_id', variant_id);
        
        if (fetchError) throw fetchError;

        // Tính tổng hiện tại
        const currentTotal = currentBatches.reduce((sum, batch) => sum + (batch.quantity_remaining || 0), 0);

        // Kiểm tra: Nếu Hiện tại + Số trừ < 0 => BÁO LỖI
        if (currentTotal + changeAmount < 0) {
            return res.status(400).json({ 
                success: false, 
                message: `Không thể giảm! Tồn kho hiện tại (${currentTotal}) không đủ để trừ (${Math.abs(changeAmount)}).` 
            });
        }
    }

    // 3. Nếu đủ điều kiện, mới cho phép chèn dòng âm vào DB
    const { data, error } = await supabase
      .from('inventory_batches')
      .insert([
        {
          variant_id: variant_id,
          store_id: store_id || null,
          original_quantity: changeAmount, // VD: -5
          quantity_remaining: changeAmount, // VD: -5 (Cộng dồn vào tổng sẽ giảm đi 5)
          cost_price: 0,
          is_adjustment: true,
          notes: reason || 'Điều chỉnh thủ công'
        }
      ])
      .select();

    if (error) throw error;

    res.json({ success: true, data: data[0], message: 'Cập nhật thành công' });

  } catch (error) {
    console.error("Lỗi Adjust Stock:", error);
    res.status(500).json({ success: false, message: error.message });
  }
};