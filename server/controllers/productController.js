const supabase = require('../config/supabase');

// 1. LẤY DANH SÁCH SẢN PHẨM (Kèm tính toán tồn kho thực tế)
exports.getProducts = async (req, res) => {
    try {
        const { search, category } = req.query; 

        // [GIỮ NGUYÊN]
        let query = supabase
            .from('products')
            .select(`
                *,
                variants (id, size, color, sku, image_url),
                categories!fk_products_main_category (id, name, slug),
                product_collections ( category_id ) 
            `)
            .eq('is_active', true)
            .order('created_at', { ascending: false });

        if (search) {
            query = query.ilike('name', `%${search}%`);
        }

        if (category) {
             const { data: catData } = await supabase.from('categories').select('id').eq('slug', category).single();
             if (catData) {
                const targetCatId = catData.id;
                const { data: collectionItems } = await supabase.from('product_collections').select('product_id').eq('category_id', targetCatId);
                const productIds = collectionItems.map(item => item.product_id);
                
                if (productIds.length > 0) {
                    query = query.in('id', productIds);
                } else {
                    return res.json({ success: true, data: [] });
                }
             }
        }

        const { data, error } = await query;
        if (error) throw error;

        res.json({ success: true, data: data });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// 2. LẤY CHI TIẾT SẢN PHẨM (SLUG)
exports.getProductBySlug = async (req, res) => {
    try {
        const { slug } = req.params;
        const { data, error } = await supabase
            .from('products')
            .select(`
                *,
                variants (id, size, color, sku, image_url),
                categories (id, name, slug)
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
exports.createProduct = async (req, res) => {
    try {
        const { name, slug, base_price, description, category_id, images, variants, collection_ids } = req.body;

        // 1. Tạo Product
        const { data: newProduct, error: prodError } = await supabase
            .from('products')
            .insert([{
                name, slug, base_price, description, category_id, images
            }])
            .select()
            .single();

        if (prodError) throw prodError;

        // 2. Tạo Variants
        if (variants && variants.length > 0) {
            const variantData = variants.map(v => ({
                product_id: newProduct.id,
                size: v.size,
                color: v.color,
                sku: v.sku,
                image_url: v.image_url || null // <--- [THÊM MỚI] Lưu ảnh vào DB
            }));

            const { error: varError } = await supabase.from('variants').insert(variantData);
            if (varError) throw varError;
        }

        // 3. Thêm vào bộ sưu tập
        if (collection_ids && collection_ids.length > 0) {
            const collectionData = collection_ids.map(catId => ({
                product_id: newProduct.id,
                category_id: catId
            }));
            await supabase.from('product_collections').insert(collectionData);
        }

        res.json({ success: true, message: 'Tạo sản phẩm thành công', data: newProduct });

    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// 4. CẬP NHẬT SẢN PHẨM
exports.updateProduct = async (req, res) => {
    try {
        const { id } = req.params;
        const { name, slug, base_price, description, category_id, images, variants, collection_ids } = req.body;

        // 1. Update thông tin chung
        const { error: updateError } = await supabase
            .from('products')
            .update({ name, slug, base_price, description, category_id, images })
            .eq('id', id);

        if (updateError) throw updateError;

        // 2. Update Collections
        await supabase.from('product_collections').delete().eq('product_id', id);
        if (collection_ids && collection_ids.length > 0) {
            const collectionData = collection_ids.map(catId => ({ product_id: id, category_id: catId }));
            await supabase.from('product_collections').insert(collectionData);
        }

        // 3. Xử lý Variants (Logic giữ nguyên, chỉ thêm update ảnh)
        const { data: oldVariants } = await supabase.from('variants').select('id').eq('product_id', id);
        const oldVariantIds = oldVariants.map(v => v.id);
        
        const { count } = await supabase
            .from('inventory_batches')
            .select('*', { count: 'exact', head: true })
            .in('variant_id', oldVariantIds);

        const hasHistory = count > 0;

        if (hasHistory) {
            // TRƯỜNG HỢP 1: CÓ LỊCH SỬ KHO -> KHÔNG XÓA, CHỈ UPDATE ẢNH & SKU
            if (variants && variants.length > 0) {
                for (const v of variants) {
                    await supabase.from('variants')
                        .update({ 
                            image_url: v.image_url || null, // <--- [THÊM MỚI] Cho phép sửa ảnh
                            sku: v.sku 
                        })
                        .eq('product_id', id)
                        .eq('size', v.size)
                        .eq('color', v.color);
                }
            }
            
            // Trả về luôn (như logic cũ của bạn, nhưng giờ đã update được ảnh)
            return res.json({ 
                success: true, 
                message: 'Đã cập nhật thông tin chung và hình ảnh. (Không thể sửa Size/Màu vì có lịch sử kho)' 
            });
        } 
        
        // TRƯỜNG HỢP 2: CHƯA CÓ LỊCH SỬ -> XÓA CŨ TẠO MỚI
        else {
            await supabase.from('variants').delete().eq('product_id', id);
            
            if (variants && variants.length > 0) {
                const variantData = variants.map(v => ({
                    product_id: id,
                    size: v.size,
                    color: v.color,
                    sku: v.sku,
                    image_url: v.image_url || null // <--- [THÊM MỚI] Lưu ảnh khi tạo lại
                }));
                await supabase.from('variants').insert(variantData);
            }
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
    }
};