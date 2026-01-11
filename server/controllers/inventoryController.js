const supabase = require('../config/supabase');

// 1. API: Lấy lịch sử nhập hàng (Lấy các lô hàng - Batches)
exports.getInventoryBatches = async (req, res) => {
    try {
        // Kết nối bảng batches với variants -> products để lấy tên hiển thị
        const { data, error } = await supabase
            .from('inventory_batches')
            .select(`
                *,
                variants (
                    sku, size, color,
                    products (name, images)
                ),
                stores (name),
                suppliers (name)
            `)
            .order('created_at', { ascending: false });

        if (error) throw error;
        res.json({ success: true, data });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// 2. API: Tạo Phiếu Nhập Hàng (Import Stock)
exports.importStock = async (req, res) => {
    try {
        const { supplier_id, store_id, items } = req.body;
        // items là mảng: [{ variant_id, quantity, cost_price }, ...]

        if (!supplier_id || !store_id || !items || items.length === 0) {
            return res.status(400).json({ success: false, message: 'Thiếu thông tin nhập hàng!' });
        }

        console.log("📦 Đang nhập kho:", items.length, "món");

        // Chuẩn bị dữ liệu để insert vào bảng inventory_batches
        const batchData = items.map(item => ({
            variant_id: item.variant_id,
            store_id: store_id,
            supplier_id: supplier_id,      // Đã thêm cột này ở bước 1
            batch_name: `PO-${Date.now()}`, // Đã thêm cột này ở bước 1
            
            original_quantity: item.quantity,
            
            // --- SỬA DÒNG NÀY ---
            // Code cũ: current_quantity: item.quantity,
            // Sửa thành tên cột đúng trong DB của bạn:
            quantity_remaining: item.quantity, 
            
            cost_price: item.cost_price
        }));

        // Thực hiện Insert
        const { data, error } = await supabase
            .from('inventory_batches')
            .insert(batchData)
            .select();

        if (error) throw error;

        res.json({ success: true, message: 'Nhập hàng thành công!', data });

    } catch (error) {
        console.error("❌ Lỗi nhập hàng:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};