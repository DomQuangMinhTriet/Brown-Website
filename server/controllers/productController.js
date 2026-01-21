const supabase = require('../config/supabase');

// 1. LẤY DANH SÁCH SẢN PHẨM (Kèm tính toán tồn kho thực tế)
exports.getProducts = async (req, res) => {
    try {
        const { search } = req.query;

        // A. Xây dựng Query cơ bản
        let query = supabase
            .from('products')
            .select(`
                *,
                variants (
                    id, size, color, sku
                )
            `)
            .eq('is_active', true)
            .order('created_at', { ascending: false });

        // B. Thêm điều kiện tìm kiếm nếu có
        if (search) {
            query = query.ilike('name', `%${search}%`);
        }

        const { data: products, error: prodError } = await query;
        if (prodError) throw prodError;

        // C. Lấy toàn bộ lô hàng còn tồn kho để tính số lượng
        const { data: batches, error: batchError } = await supabase
            .from('inventory_batches')
            .select('variant_id, quantity_remaining')
            .gt('quantity_remaining', 0);

        if (batchError) throw batchError;

        // D. Map dữ liệu: Tính tổng tồn kho cho từng sản phẩm
        const processedProducts = products.map(product => {
            const variantsWithStock = product.variants ? product.variants.map(variant => {
                // Tính tổng tồn kho của variant này từ các lô hàng (batches)
                const totalStock = batches
                    .filter(b => b.variant_id === variant.id)
                    .reduce((sum, b) => sum + (b.quantity_remaining || 0), 0);

                return {
                    ...variant,
                    stock: totalStock // Trả về số lượng tồn
                };
            }) : [];

            // Tổng tồn kho của cả sản phẩm (cộng dồn các variants)
            const productTotalStock = variantsWithStock.reduce((sum, v) => sum + v.stock, 0);

            return {
                ...product,
                variants: variantsWithStock,
                total_stock: productTotalStock
            };
        });

        res.json({ success: true, data: processedProducts });

    } catch (error) {
        console.error("Get Products Error:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};

// 2. LẤY CHI TIẾT 1 SẢN PHẨM (THEO SLUG)
exports.getProductBySlug = async (req, res) => {
    try {
        const { slug } = req.params;
        
        const { data, error } = await supabase
            .from('products')
            .select(`
                *,
                variants (id, size, color, sku)
            `)
            .eq('slug', slug)
            .single();

        if (error) throw error;
        res.json({ success: true, data });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// 3. TẠO SẢN PHẨM MỚI (Logic mới: Tự tạo Slug, bỏ Category_id)
exports.createProduct = async (req, res) => {
    try {
        const { name, base_price, description, images, variants } = req.body;

        // Validation cơ bản
        if (!name || !base_price) {
            return res.status(400).json({ success: false, message: 'Tên và giá là bắt buộc' });
        }

        // Tạo slug tự động từ tên
        const slug = name.toLowerCase()
            .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
            .replace(/đ/g, "d").replace(/[^a-z0-9]/g, "-") 
            + '-' + Date.now();

        // A. Insert vào bảng Products
        const { data: product, error: prodError } = await supabase
            .from('products')
            .insert([{
                name,
                slug,
                base_price,
                description,
                images,
                is_active: true
            }])
            .select()
            .single();

        if (prodError) throw prodError;

        // B. Insert vào bảng Variants (nếu có)
        if (variants && variants.length > 0) {
            const variantData = variants.map(v => ({
                product_id: product.id,
                size: v.size,
                color: v.color,
                sku: v.sku
            }));
            const { error: varError } = await supabase.from('variants').insert(variantData);
            if (varError) throw varError;
        }

        res.json({ success: true, message: 'Tạo sản phẩm thành công!', data: product });

    } catch (error) {
        console.error("Create Product Error:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};

// 4. CẬP NHẬT SẢN PHẨM (Logic: Update theo ID, kiểm tra lịch sử kho)
exports.updateProduct = async (req, res) => {
    try {
        const { id } = req.params;
        const { name, base_price, description, images, variants } = req.body;

        // A. Cập nhật thông tin cơ bản
        const { error: prodError } = await supabase
            .from('products')
            .update({ 
                name, 
                base_price, 
                description, 
                images 
            })
            .eq('id', id);

        if (prodError) throw prodError;

        // B. Xử lý Biến thể (Size/Màu) - Logic an toàn kho hàng
        if (variants && variants.length > 0) {
            // Kiểm tra xem sản phẩm này đã từng nhập kho chưa?
            const { data: oldVariants } = await supabase.from('variants').select('id').eq('product_id', id);
            
            let hasHistory = false;
            // Nếu sản phẩm đã có variant cũ, kiểm tra xem variant đó có trong lô hàng (inventory_batches) không
            if (oldVariants && oldVariants.length > 0) {
                const variantIds = oldVariants.map(v => v.id);
                const { data: stockCheck } = await supabase
                    .from('inventory_batches')
                    .select('id')
                    .in('variant_id', variantIds)
                    .limit(1);
                
                if (stockCheck && stockCheck.length > 0) hasHistory = true;
            }

            // TRƯỜNG HỢP 1: ĐÃ CÓ LỊCH SỬ KHO -> KHÔNG ĐƯỢC SỬA BIẾN THỂ (Để bảo toàn dữ liệu thống kê)
            if (hasHistory) {
                return res.json({ 
                    success: true, 
                    message: 'Đã cập nhật thông tin chung. (Không thể sửa Size/Màu vì sản phẩm đã có lịch sử nhập/xuất kho)' 
                });
            }

            // TRƯỜNG HỢP 2: CHƯA CÓ LỊCH SỬ -> XÓA CŨ TẠO MỚI (Reset variants)
            // Xóa variant cũ
            await supabase.from('variants').delete().eq('product_id', id);
            
            // Tạo variant mới
            const variantData = variants.map(v => ({
                product_id: id,
                size: v.size,
                color: v.color,
                sku: v.sku
            }));
            await supabase.from('variants').insert(variantData);
        }

        res.json({ success: true, message: 'Cập nhật sản phẩm thành công!' });

    } catch (error) {
        console.error("Update Error:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};

// 5. XÓA SẢN PHẨM
exports.deleteProduct = async (req, res) => {
    try {
        const { id } = req.params;
        // Lưu ý: Nếu DB có ràng buộc khóa ngoại (FK), cần xóa variants/inventory_batches trước hoặc set CASCADE ở DB
        const { error } = await supabase.from('products').delete().eq('id', id);
        
        if (error) throw error;
        res.json({ success: true, message: 'Đã xóa sản phẩm' });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};