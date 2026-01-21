const supabase = require('../config/supabase');

// 1. LẤY DANH SÁCH SẢN PHẨM
exports.getProducts = async (req, res) => {
    try {
<<<<<<< Updated upstream
        const { data, error } = await supabase.from('products').select('*');
        if (error) throw error;
        res.json({ success: true, count: data.length, data: data });
    } catch (err) {
        res.status(500).json({ error: err.message });
=======
        // 1. Lấy sản phẩm + variants (Đã bỏ cột base_price_modifier gây lỗi)
        const { data: products, error: prodError } = await supabase
            .from('products')
            .select(`
                *,
                variants (
                    id, size, color, sku
                )
            `)
            .eq('is_active', true)
            .order('created_at', { ascending: false });

        if (prodError) throw prodError;

        // 2. Lấy toàn bộ lô hàng còn tồn kho
        const { data: batches, error: batchError } = await supabase
            .from('inventory_batches')
            .select('variant_id, quantity_remaining')
            .gt('quantity_remaining', 0);

        if (batchError) throw batchError;

        // 3. Tính toán tồn kho cho từng sản phẩm
        const processedProducts = products.map(product => {
            const variantsWithStock = product.variants ? product.variants.map(variant => {
                // Tính tổng tồn kho của variant này
                const totalStock = batches
                    .filter(b => b.variant_id === variant.id)
                    .reduce((sum, b) => sum + (b.quantity_remaining || 0), 0);

                return {
                    ...variant,
                    stock: totalStock // Luôn trả về số (0 hoặc >0)
                };
            }) : [];

            // Tổng tồn kho của cả sản phẩm
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

// 3. TẠO SẢN PHẨM MỚI (Đã bỏ category_id)
exports.createProduct = async (req, res) => {
    try {
        // Lưu ý: Không lấy category_id từ req.body nữa
        const { name, base_price, description, images, variants } = req.body;

        // Tạo slug tự động từ tên
        const slug = name.toLowerCase()
            .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
            .replace(/đ/g, "d").replace(/[^a-z0-9]/g, "-") 
            + '-' + Date.now();

        // A. Insert vào bảng Products (KHÔNG CÓ category_id)
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

        res.json({ success: true, message: 'Tạo sản phẩm thành công!' });

    } catch (error) {
        console.error("Create Error:", error);
        res.status(500).json({ success: false, message: error.message });
>>>>>>> Stashed changes
    }
};

// 4. CẬP NHẬT SẢN PHẨM (Đã bỏ category_id và logic bảo vệ kho)
exports.updateProduct = async (req, res) => {
    try {
<<<<<<< Updated upstream
        const { slug } = req.params;
        const { data, error } = await supabase
            .from('products')
            .select(`*, variants(*)`) // Lấy kèm biến thể
            .eq('slug', slug)
            .single();
            
        if (error) throw error;
        res.json({ success: true, data: data });
    } catch (err) {
        res.status(500).json({ error: err.message });
=======
        const { id } = req.params;
        // Lưu ý: Không lấy category_id từ req.body nữa
        const { name, base_price, description, images, variants } = req.body;

        // A. Cập nhật thông tin cơ bản (KHÔNG CÓ category_id)
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
            const { data: oldVariants } = await supabase.from('variants').select('id').eq('product_id', id).limit(1);
            
            let hasHistory = false;
            if (oldVariants && oldVariants.length > 0) {
                const { data: stockCheck } = await supabase
                    .from('inventory_batches')
                    .select('id')
                    .eq('variant_id', oldVariants[0].id)
                    .limit(1);
                if (stockCheck && stockCheck.length > 0) hasHistory = true;
            }

            // NẾU ĐÃ CÓ LỊCH SỬ KHO -> KHÔNG ĐƯỢC SỬA BIẾN THỂ
            if (hasHistory) {
                return res.json({ 
                    success: true, 
                    message: 'Đã cập nhật thông tin chung. (Không thể sửa Size/Màu vì sản phẩm đã có trong Kho)' 
                });
            }

            // NẾU CHƯA CÓ LỊCH SỬ -> XÓA CŨ TẠO MỚI
            await supabase.from('variants').delete().eq('product_id', id);
            
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
        const { error } = await supabase.from('products').delete().eq('id', id);
        if (error) throw error;
        res.json({ success: true, message: 'Đã xóa sản phẩm' });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
>>>>>>> Stashed changes
    }
};