const supabase = require('../config/supabase');
const translate = require('translate-google');

const autoTranslate = async (text) => {
    if (!text || text.trim() === '') return '';
    try {
        const res = await translate(text, { from: 'vi', to: 'en' });
        return res;
    } catch (err) {
        console.error('Lỗi dịch tự động:', err);
        return text; // Nếu lỗi mạng thì tạm thời lấy chữ tiếng Việt
    }
};

// 1. LẤY DANH SÁCH SẢN PHẨM (Kèm tính toán tồn kho thực tế)
exports.getProducts = async (req, res) => {
    try {
        // [CẬP NHẬT]: Thêm biến admin để phân biệt Khách và Admin
        const { search, category, admin } = req.query; 

        let query = supabase
            .from('products')
            .select(`
                *,
                variants (
                    id, size, color, color_en, sku, image_url,
                    inventory_batches ( quantity_remaining ) 
                ),
                categories!fk_products_main_category (id, name, slug),
                product_collections ( category_id ) 
            `)
            .order('created_at', { ascending: false });

        // [CẬP NHẬT]: Nếu không phải admin gọi (Khách hàng xem web), thì chỉ hiện sản phẩm đang Active
        if (admin !== 'true') {
            query = query.eq('is_active', true);
        }

        if (search) {
            query = query.ilike('name', `%${search}%`);
        }

        if (category) {
             const { data: catData } = await supabase.from('categories').select('id').eq('slug', category).single();
             
             if (catData) {
                const targetCatId = catData.id;
                
                const { data: collectionItems } = await supabase.from('product_collections').select('product_id').eq('category_id', targetCatId);
                const subCollectionIds = collectionItems.map(item => item.product_id);
                
                if (subCollectionIds.length > 0) {
                    query = query.or(`category_id.eq.${targetCatId},id.in.(${subCollectionIds.join(',')})`);
                } else {
                    query = query.eq('category_id', targetCatId);
                }
             }
        }

        const { data, error } = await query;
        if (error) throw error;

        const productsWithStock = data.map(product => {
            const variantsWithStock = product.variants.map(v => {
                const totalStock = v.inventory_batches 
                    ? v.inventory_batches.reduce((sum, batch) => sum + (batch.quantity_remaining || 0), 0)
                    : 0;

                const { inventory_batches, ...variantProps } = v;
                
                return {
                    ...variantProps,
                    quantity_remaining: totalStock 
                };
            });

            return { ...product, variants: variantsWithStock };
        });

        res.json({ success: true, data: productsWithStock });
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
                variants (
                    id, size, color, color_en, sku, image_url,
                    inventory_batches ( quantity_remaining )
                ),
                categories (id, name, slug)
            `)
            .eq('slug', slug)
            .single();

        if (error) throw error;

        const variantsWithStock = data.variants.map(v => {
            const totalStock = v.inventory_batches 
                ? v.inventory_batches.reduce((sum, batch) => sum + (batch.quantity_remaining || 0), 0)
                : 0;
            const { inventory_batches, ...rest } = v;
            return { ...rest, quantity_remaining: totalStock };
        });

        res.json({ success: true, data: { ...data, variants: variantsWithStock } });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// 3. TẠO SẢN PHẨM MỚI
exports.createProduct = async (req, res) => {
    try {
        // [MỚI] Hứng thêm is_preorder và preorder_note
        const { name, slug, base_price, description, category_id, images, variants, collection_ids, size_chart_url, is_active, is_preorder, preorder_note } = req.body;
        
        const name_en = await autoTranslate(name);
        const description_en = await autoTranslate(description);
        
        if (variants && Array.isArray(variants)) {
            for (let i = 0; i < variants.length; i++) {
                if (variants[i].color) {
                    variants[i].color_en = await autoTranslate(variants[i].color);
                }
            }
        }
        
        const { data: newProduct, error: prodError } = await supabase
            .from('products')
            .insert([{
                name, slug, base_price, description, category_id, images, 
                size_chart_url: size_chart_url || null,  
                name_en, description_en,
                is_active: is_active !== undefined ? is_active : true,
                is_preorder: is_preorder || false, // [MỚI]
                preorder_note: preorder_note || null // [MỚI]
            }])
            .select()
            .single();

        if (prodError) throw prodError;

        if (variants && variants.length > 0) {
            const variantData = variants.map(v => ({
                product_id: newProduct.id,
                size: v.size,
                color: v.color,
                color_en: v.color_en || null, 
                sku: v.sku,
                image_url: v.image_url || null 
            }));

            const { error: varError } = await supabase.from('variants').insert(variantData);
            if (varError) throw varError;
        }

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
        // [MỚI] Hứng thêm is_preorder và preorder_note
        const { name, slug, base_price, description, category_id, images, variants, collection_ids, size_chart_url, is_active, is_preorder, preorder_note } = req.body;
        
        const name_en = await autoTranslate(name);
        const description_en = await autoTranslate(description);

        if (variants && Array.isArray(variants)) {
            for (let i = 0; i < variants.length; i++) {
                if (variants[i].color) {
                    variants[i].color_en = await autoTranslate(variants[i].color);
                }
            }
        }
        
        // 1. Update thông tin chung
        const { error: updateError } = await supabase
            .from('products')
            .update({ 
                name, slug, base_price, description, category_id, images, 
                size_chart_url: size_chart_url || null, 
                name_en, description_en,
                is_active: is_active !== undefined ? is_active : true,
                is_preorder: is_preorder || false, // [MỚI]
                preorder_note: preorder_note || null // [MỚI]
            })
            .eq('id', id);

        if (updateError) throw updateError;

        // 2. Update Collections
        await supabase.from('product_collections').delete().eq('product_id', id);
        if (collection_ids && collection_ids.length > 0) {
            const collectionData = collection_ids.map(catId => ({ product_id: id, category_id: catId }));
            await supabase.from('product_collections').insert(collectionData);
        }

        // 3. Xử lý Variants
        const { data: oldVariants } = await supabase.from('variants').select('id').eq('product_id', id);
        const oldVariantIds = oldVariants.map(v => v.id);
        
        const { count } = await supabase
            .from('inventory_batches')
            .select('*', { count: 'exact', head: true })
            .in('variant_id', oldVariantIds);

        const hasHistory = count > 0;

        if (hasHistory) {
            if (variants && variants.length > 0) {
                for (const v of variants) {
                    await supabase.from('variants')
                        .update({ 
                            image_url: v.image_url || null, 
                            sku: v.sku,
                            color_en: v.color_en || null 
                        })
                        .eq('product_id', id)
                        .eq('size', v.size)
                        .eq('color', v.color);
                }
            }
            
            return res.json({ 
                success: true, 
                message: 'Đã cập nhật thông tin. (Không thể sửa Size/Màu vì có lịch sử kho)' 
            });
        } 
        else {
            await supabase.from('variants').delete().eq('product_id', id);
            
            if (variants && variants.length > 0) {
                const variantData = variants.map(v => ({
                    product_id: id,
                    size: v.size,
                    color: v.color,
                    color_en: v.color_en || null, 
                    sku: v.sku,
                    image_url: v.image_url || null 
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

        await supabase.from('product_collections').delete().eq('product_id', id);

        const { data: variants } = await supabase.from('variants').select('id').eq('product_id', id);
        
        if (variants && variants.length > 0) {
            const variantIds = variants.map(v => v.id);
            await supabase.from('inventory_batches').delete().in('variant_id', variantIds);
            await supabase.from('variants').delete().eq('product_id', id);
        }

        const { error } = await supabase.from('products').delete().eq('id', id);

        if (error) {
            if (error.code === '23503') { 
                return res.status(400).json({ 
                    success: false, 
                    message: 'Không thể xóa vì sản phẩm này đã có lịch sử Đơn hàng. Hãy bấm nút "Sửa" và tắt tùy chọn "Trạng thái sản phẩm" để ẩn đi thay vì xóa.' 
                });
            }
            throw error;
        }

        res.json({ success: true, message: 'Đã xóa sản phẩm và dữ liệu liên quan' });

    } catch (error) {
        console.error("Delete Error:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};