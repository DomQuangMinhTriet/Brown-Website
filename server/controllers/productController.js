const supabase = require('../config/supabase');

// 1. LẤY DANH SÁCH SẢN PHẨM (Kèm tính toán tồn kho thực tế)
exports.getProducts = async (req, res) => {
    try {
        const { search, category } = req.query; 

        // [FIX LỖI PGRST201]
        // Sử dụng cú pháp: tên_bảng!tên_constraint (...)
        let query = supabase
            .from('products')
            .select(`
                *,
                variants (id, size, color, sku),
                categories!fk_products_main_category (id, name, slug)
            `)
            .eq('is_active', true)
            .order('created_at', { ascending: false });

        if (search) {
            query = query.ilike('name', `%${search}%`);
        }

        if (category) {
            // Tìm ID danh mục
            const { data: catData } = await supabase
                .from('categories')
                .select('id')
                .eq('slug', category)
                .single();

            if (catData) {
                // Hoặc lọc theo danh mục chính OR lọc theo collection
                // Lưu ý: Logic lọc phức tạp hơn khi có collection, ở đây ta tạm giữ lọc theo category_id
                query = query.eq('category_id', catData.id);
            } else {
                return res.json({ success: true, data: [] });
            }
        }

        // 4. Thực thi Query lấy sản phẩm
        const { data: products, error: prodError } = await query;
        if (prodError) throw prodError;

        // 5. Tính toán tồn kho (Giữ nguyên logic cũ của bạn)
        const { data: batches, error: batchError } = await supabase
            .from('inventory_batches')
            .select('variant_id, quantity_remaining')
            .gt('quantity_remaining', 0);

        if (batchError) throw batchError;

        // Map dữ liệu tồn kho
        const processedProducts = products.map(product => {
            const variantsWithStock = product.variants ? product.variants.map(variant => {
                const stock = batches
                    .filter(b => b.variant_id === variant.id)
                    .reduce((sum, b) => sum + b.quantity_remaining, 0);
                return { ...variant, quantity_remaining: stock };
            }) : [];

            const totalStock = variantsWithStock.reduce((sum, v) => sum + v.quantity_remaining, 0);
            return { ...product, variants: variantsWithStock, total_stock: totalStock };
        });

        res.json({ success: true, data: processedProducts });

    } catch (error) {
        console.error("Get Products Error:", error); // Log lỗi ra terminal để debug
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
                variants (id, size, color, sku, image_url),
                categories!fk_products_main_category (id, name, slug),
                product_collections (
                    categories (id, name, slug)
                )
            `)
            .eq('slug', slug)
            .single();

        if (error) throw error;
        res.json({ success: true, data });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// 3. TẠO SẢN PHẨM MỚI
// 3. TẠO SẢN PHẨM MỚI
exports.createProduct = async (req, res) => {
    try {
        // [MỚI] Nhận thêm collection_ids từ frontend
        const { name, base_price, description, category_id, images, variants, size_chart_url, collection_ids } = req.body;

        // Validation cơ bản
        if (!name || !base_price) {
            return res.status(400).json({ success: false, message: 'Tên và giá là bắt buộc' });
        }

        // Tạo slug
        const slug = name.toLowerCase()
            .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
            .replace(/đ/g, "d").replace(/[^a-z0-9]/g, "-") 
            + '-' + Date.now();

        // A. Tạo Product
        const { data: product, error: prodError } = await supabase
            .from('products')
            .insert([{
                name, slug, base_price, description, images,
                category_id: category_id, // Vẫn giữ category chính để sort
                size_chart_url, is_active: true
            }])
            .select()
            .single();

        if (prodError) throw prodError;

        // B. [MỚI] Lưu danh sách Collection phụ (product_collections)
        if (collection_ids && Array.isArray(collection_ids) && collection_ids.length > 0) {
            const collectionData = collection_ids.map(catId => ({
                product_id: product.id,
                category_id: catId
            }));
            const { error: collError } = await supabase.from('product_collections').insert(collectionData);
            if (collError) throw collError;
        }

        // C. [CẬP NHẬT] Lưu Variants kèm Ảnh
        if (variants && variants.length > 0) {
            const variantData = variants.map(v => ({
                product_id: product.id,
                size: v.size,
                color: v.color,
                sku: v.sku,
                image_url: v.image_url || null // [MỚI] Lưu link ảnh biến thể
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

// 4. CẬP NHẬT SẢN PHẨM
exports.updateProduct = async (req, res) => {
    try {
        const { id } = req.params;
        // [MỚI] Nhận collection_ids
        const { name, slug, base_price, description, category_id, images, variants, size_chart_url, collection_ids } = req.body;

        // 1. Update bảng Products
        const { error: prodError } = await supabase
            .from('products')
            .update({ name, slug, base_price, description, category_id, size_chart_url, images })
            .eq('id', id);

        if (prodError) throw prodError;

        // 2. [MỚI] Update Collections (Xóa cũ -> Thêm mới)
        if (collection_ids) {
            // Xóa hết collection cũ của sp này
            await supabase.from('product_collections').delete().eq('product_id', id);
            
            // Thêm mới nếu có chọn
            if (collection_ids.length > 0) {
                const collectionData = collection_ids.map(catId => ({
                    product_id: id,
                    category_id: catId
                }));
                await supabase.from('product_collections').insert(collectionData);
            }
        }

        // 3. Xử lý Biến thể (Size/Màu) - Logic an toàn kho hàng
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
            
            const variantData = variants.map(v => ({
                product_id: id,
                size: v.size,
                color: v.color,
                sku: v.sku,
                image_url: v.image_url || null // [MỚI]
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