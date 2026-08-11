const exceljs = require('exceljs');
const supabase = require('../config/supabase');
const translate = require('translate-google');
const { deleteCloudinaryAssets, diffRemovedUrls } = require('../utils/cloudinaryCleanup');

const PRODUCT_SLUG_CONSTRAINT = 'products_slug_key';
const MAX_SLUG_ATTEMPTS = 100;

const isDuplicateSlugError = (error) =>
    error?.code === '23505' && (
        error?.constraint === PRODUCT_SLUG_CONSTRAINT ||
        error?.message?.includes(PRODUCT_SLUG_CONSTRAINT)
    );

const slugBase = (slug, name) => {
    const value = String(slug || name || '')
        .toLowerCase()
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .replace(/[đĐ]/g, 'd')
        .replace(/[^a-z0-9\s-]/g, '')
        .trim()
        .replace(/\s+/g, '-')
        .replace(/-+/g, '-');

    return value.replace(/^-|-$/g, '');
};

const availableProductSlug = async (base, excludeId) => {
    for (let suffix = 1; suffix <= MAX_SLUG_ATTEMPTS; suffix++) {
        const candidate = suffix === 1 ? base : `${base}-${suffix}`;
        let query = supabase.from('products').select('id').eq('slug', candidate).limit(1);
        if (excludeId) query = query.neq('id', excludeId);

        const { data, error } = await query;
        if (error) throw error;
        if (!data || data.length === 0) return candidate;
    }

    throw new Error('Không thể tạo slug duy nhất cho sản phẩm này. Vui lòng đổi tên sản phẩm.');
};

const sortVariantsByDisplayOrder = (variants = []) => [...variants].sort((a, b) => {
    const first = Number.isFinite(Number(a.display_order)) ? Number(a.display_order) : Number.MAX_SAFE_INTEGER;
    const second = Number.isFinite(Number(b.display_order)) ? Number(b.display_order) : Number.MAX_SAFE_INTEGER;
    return first - second || Number(a.id || 0) - Number(b.id || 0);
});

const withNormalizedDisplayOrder = (variants = []) => {
    let nextPosition = 0;
    return variants.map((variant) => ({
        ...variant,
        // Các biến thể đang hiển thị luôn có thứ tự liên tục: 0, 1, 2...
        display_order: variant.is_deleted ? -1 : nextPosition++
    }));
};

const autoTranslate = async (text) => {
    if (!text || text.trim() === '') return '';
    // Đảm bảo text là string trước khi gọi .trim() để tránh crash app
    if (!text || typeof text !== 'string' || text.trim() === '') return '';
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
        const { search, category, admin, limit, view } = req.query;

        const selectFields = view === 'media'
            ? 'id, images'
            : view === 'admin-list'
                ? 'id, name, slug, base_price, is_active, images, created_at'
            : view === 'card'
                ? `
                    id, name, name_en, slug, base_price, category_id, images,
                    is_active, is_preorder, preorder_note,
                    variants (
                        id, size, color, color_en, sku, image_url, is_deleted, display_order,
                        discount_amount, is_discount_active,
                        inventory_batches ( quantity_remaining )
                    ),
                    categories!fk_products_main_category (id, name, name_en, slug),
                    product_collections ( category_id )
                `
                : `
                    *,
                    variants (
                        id, size, color, color_en, sku, image_url, is_deleted, display_order,
                        discount_amount, is_discount_active,
                        inventory_batches ( quantity_remaining )
                    ),
                    categories!fk_products_main_category (id, name, slug),
                    product_collections ( category_id )
                `;

        let query = supabase
            .from('products')
            .select(selectFields)
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

        // [HIỆU NĂNG] limit tùy chọn — không truyền thì giữ nguyên hành vi cũ (trả về tất cả).
        // Chỉ dùng ở những nơi thật sự chỉ cần vài sản phẩm (VD: sản phẩm liên quan).
        const limitNum = parseInt(limit, 10);
        if (Number.isFinite(limitNum) && limitNum > 0) {
            query = query.limit(limitNum);
        }

        const { data, error } = await query;
        if (error) throw error;

        const productsWithStock = data.map(product => {
            if (view === 'media' || view === 'admin-list') return product;
            const validVariants = sortVariantsByDisplayOrder(product.variants ? product.variants.filter(v => v.is_deleted === false) : []);
            const variantsWithStock = validVariants.map(v => {
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
        let query = supabase
            .from('products')
            .select(`
                *,
                variants (
                    id, size, color, color_en, sku, image_url, is_deleted, display_order,
                    discount_amount, is_discount_active,
                    inventory_batches ( quantity_remaining )
                ),
                categories!fk_products_main_category (id, name, slug),
                product_collections ( category_id )
            `)
            .eq('slug', slug);
        if (req.query.admin !== 'true') query = query.eq('is_active', true);
        const { data, error } = await query.single();

        if (error) throw error;

        const validVariants = sortVariantsByDisplayOrder(data.variants ? data.variants.filter(v => v.is_deleted === false) : []);
        const variantsWithStock = validVariants.map(v => {
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
        const { name, slug, base_price, description, category_id, images, videos, variants, collection_ids, size_chart_url, is_active, is_preorder, preorder_note } = req.body;

        const baseSlug = slugBase(slug, name);
        if (!baseSlug) {
            return res.status(400).json({ success: false, message: 'Tên sản phẩm không hợp lệ để tạo đường dẫn (slug).' });
        }

        const name_en = await autoTranslate(name);
        const description_en = await autoTranslate(description);

        // Đã tắt tự động dịch màu sắc sang tiếng Anh
        // if (variants && Array.isArray(variants)) {
        //     for (let i = 0; i < variants.length; i++) {
        //         if (variants[i].color) {
        //             variants[i].color_en = await autoTranslate(variants[i].color);
        //         }
        //     }
        // }

        const productData = {
            name, base_price, description, category_id: category_id || null, images,
            videos: videos || [],
            size_chart_url: size_chart_url || null,
            name_en, description_en,
            is_active: is_active !== undefined ? is_active : true,
            is_preorder: is_preorder || false,
            preorder_note: preorder_note || null
        };

        // PostgreSQL giữ unique constraint làm lớp bảo vệ cuối cùng. Nếu có request
        // đồng thời chiếm slug vừa chọn, vòng lặp sẽ lấy hậu tố tiếp theo và thử lại.
        let newProduct;
        let finalSlug;
        for (let attempt = 0; attempt < MAX_SLUG_ATTEMPTS; attempt++) {
            finalSlug = await availableProductSlug(baseSlug);
            const { data, error } = await supabase
                .from('products')
                .insert([{ ...productData, slug: finalSlug }])
                .select()
                .single();

            if (!error) {
                newProduct = data;
                break;
            }
            if (!isDuplicateSlugError(error)) throw error;
        }

        if (!newProduct) {
            throw new Error('Không thể tạo slug duy nhất cho sản phẩm này. Vui lòng thử lại.');
        }

        if (variants && Array.isArray(variants) && variants.length > 0) {
            const variantData = withNormalizedDisplayOrder(variants).map(v => ({
                product_id: newProduct.id,
                size: v.size,
                color: v.color,
                color_en: v.color_en || null, 
                sku: v.sku,
                image_url: v.image_url || null,
                display_order: v.display_order,
                is_deleted: v.is_deleted || false
            }));

            const { error: varError } = await supabase.from('variants').insert(variantData);
            if (varError) throw varError;
        }

        if (collection_ids && Array.isArray(collection_ids) && collection_ids.length > 0) {
            const collectionData = collection_ids.map(catId => ({
                product_id: newProduct.id,
                category_id: catId
            }));
            const { error: colError } = await supabase.from('product_collections').insert(collectionData);
            if (colError) throw colError;
        }

        const slugAdjusted = finalSlug !== baseSlug;
        res.json({
            success: true,
            message: slugAdjusted
                ? `Tên sản phẩm đã có, hệ thống dùng slug "${finalSlug}" để tránh trùng.`
                : 'Tạo sản phẩm thành công',
            data: newProduct,
            slugAdjusted
        });

    } catch (error) {
        console.error("Create Product Error:", error); // <-- In lỗi ra Terminal để biết nguyên nhân
        if (isDuplicateSlugError(error)) {
            return res.status(409).json({ success: false, message: 'Slug sản phẩm đã tồn tại. Vui lòng thử lại.' });
        }
        res.status(500).json({ success: false, message: error.message || 'Lỗi server khi tạo sản phẩm' });
    }
};

// 4. CẬP NHẬT SẢN PHẨM
exports.updateProduct = async (req, res) => {
    try {
        const { id } = req.params;
        const { name, slug, base_price, description, category_id, images, videos, variants, collection_ids, size_chart_url, is_active, is_preorder, preorder_note } = req.body;

        const baseSlug = slugBase(slug, name);
        if (!baseSlug) {
            return res.status(400).json({ success: false, message: 'Tên sản phẩm không hợp lệ để tạo đường dẫn (slug).' });
        }

        // [AN TOÀN] Lấy media CŨ trước khi ghi đè, để sau khi lưu xong biết file
        // nào đã bị bỏ đi (đổi ảnh, xóa ảnh, đổi size chart...) mà dọn trên Cloudinary.
        const { data: oldProduct } = await supabase
            .from('products')
            .select('images, videos, size_chart_url')
            .eq('id', id)
            .single();

        const name_en = await autoTranslate(name);
        const description_en = await autoTranslate(description);

        // Đã tắt tự động dịch màu sắc sang tiếng Anh
        // if (variants && Array.isArray(variants)) {
        //     for (let i = 0; i < variants.length; i++) {
        //         if (variants[i].color) {
        //             variants[i].color_en = await autoTranslate(variants[i].color);
        //         }
        //     }
        // }

        // 1. Update thông tin chung
        const generalUpdate = {
            name, base_price, description, category_id: category_id || null, images,
            size_chart_url: size_chart_url || null,
            name_en, description_en,
            is_active: is_active !== undefined ? is_active : true,
            is_preorder: is_preorder || false,
            preorder_note: preorder_note || null
        };
        if (videos !== undefined) generalUpdate.videos = videos;

        let finalSlug;
        let updateError;
        for (let attempt = 0; attempt < MAX_SLUG_ATTEMPTS; attempt++) {
            finalSlug = await availableProductSlug(baseSlug, id);
            ({ error: updateError } = await supabase
                .from('products')
                .update({ ...generalUpdate, slug: finalSlug })
                .eq('id', id));

            if (!updateError) break;
            if (!isDuplicateSlugError(updateError)) throw updateError;
        }

        if (updateError) {
            throw new Error('Không thể tạo slug duy nhất cho sản phẩm này. Vui lòng thử lại.');
        }

        // [AN TOÀN] Dọn rác Cloudinary cho ảnh/video/size-chart đã bị thay hoặc xóa
        // (best-effort — không chặn phản hồi nếu Cloudinary lỗi tạm thời).
        if (oldProduct) {
            const removed = [
                ...diffRemovedUrls(oldProduct.images, images),
                ...diffRemovedUrls(oldProduct.videos, videos),
            ];
            if (oldProduct.size_chart_url && oldProduct.size_chart_url !== size_chart_url) {
                removed.push(oldProduct.size_chart_url);
            }
            deleteCloudinaryAssets(removed).catch(() => {});
        }

        // 2. Update Collections
        await supabase.from('product_collections').delete().eq('product_id', id);
        if (collection_ids && collection_ids.length > 0) {
            const collectionData = collection_ids.map(catId => ({ product_id: id, category_id: catId }));
            await supabase.from('product_collections').insert(collectionData);
        }

        // 3. Xử lý biến thể theo id: cho phép sửa trực tiếp size, màu, SKU và thứ tự.
        // Không xóa/tạo lại biến thể cũ để không làm mất liên kết dữ liệu kho.
        const { data: oldVariants } = await supabase.from('variants').select('id, size, color, is_deleted, image_url').eq('product_id', id);
        const variantsToSave = withNormalizedDisplayOrder(variants || []);

        for (const v of variantsToSave) {
            const existingVariant = v.id
                ? oldVariants.find(ov => String(ov.id) === String(v.id))
                : null;
            const variantData = {
                size: v.size,
                color: v.color,
                color_en: v.color_en || null,
                sku: v.sku,
                image_url: v.image_url || null,
                display_order: v.display_order,
                is_deleted: v.is_deleted || false
            };

            if (existingVariant) {
                if (existingVariant.image_url && existingVariant.image_url !== variantData.image_url) {
                    deleteCloudinaryAssets([existingVariant.image_url]).catch(() => {});
                }
                const { error: variantUpdateError } = await supabase
                    .from('variants')
                    .update(variantData)
                    .eq('id', existingVariant.id)
                    .eq('product_id', id);
                if (variantUpdateError) throw variantUpdateError;
            } else {
                const { error: variantInsertError } = await supabase
                    .from('variants')
                    .insert([{ product_id: id, ...variantData }]);
                if (variantInsertError) throw variantInsertError;
            }
        }

        res.json({
            success: true,
            message: finalSlug !== baseSlug
                ? `Cập nhật thành công. Slug đã được đổi thành "${finalSlug}" để tránh trùng.`
                : 'Cập nhật sản phẩm thành công!',
            slugAdjusted: finalSlug !== baseSlug
        });
    } catch (error) {
        console.error("Update Error:", error);
        if (isDuplicateSlugError(error)) {
            return res.status(409).json({ success: false, message: 'Slug sản phẩm đã tồn tại. Vui lòng thử lại.' });
        }
        res.status(500).json({ success: false, message: error.message });
    }
};

// 5. XÓA SẢN PHẨM
exports.deleteProduct = async (req, res) => {
    try {
        const { id } = req.params;

        // [AN TOÀN] Gom media TRƯỚC khi xóa DB, để dọn trên Cloudinary sau khi xóa thành công
        const { data: productMedia } = await supabase.from('products').select('images, videos, size_chart_url').eq('id', id).single();
        const { data: variantMedia } = await supabase.from('variants').select('image_url').eq('product_id', id);

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

        // [AN TOÀN] Xóa xong DB mới dọn Cloudinary — best-effort, không chặn phản hồi
        const mediaToDelete = [
            ...(productMedia?.images || []),
            ...(productMedia?.videos || []),
            productMedia?.size_chart_url,
            ...(variantMedia || []).map(v => v.image_url),
        ].filter(Boolean);
        deleteCloudinaryAssets(mediaToDelete).catch(() => {});

        res.json({ success: true, message: 'Đã xóa sản phẩm và dữ liệu liên quan' });

    } catch (error) {
        console.error("Delete Error:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};

// [MỚI] CẬP NHẬT GIẢM GIÁ TRỰC TIẾP CHO 1 BIẾN THỂ (bật/tắt + số tiền giảm theo màu/size)
exports.updateVariantDiscount = async (req, res) => {
    try {
        const { id } = req.params;
        const { discount_amount, is_discount_active } = req.body;

        const updates = {};
        if (discount_amount !== undefined) updates.discount_amount = Number(discount_amount) || 0;
        if (is_discount_active !== undefined) updates.is_discount_active = !!is_discount_active;

        const { data, error } = await supabase
            .from('variants')
            .update(updates)
            .eq('id', id)
            .select('id, product_id, sku, size, color, discount_amount, is_discount_active')
            .single();

        if (error) throw error;
        res.json({ success: true, data });
    } catch (error) {
        console.error("Update Product Discount Error:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};

// [MỚI] XUẤT EXCEL THEO CHUẨN SAPO
exports.exportProductsToSapoExcel = async (req, res) => {
    try {
        // 1. Lấy toàn bộ dữ liệu sản phẩm, biến thể và tồn kho
        const { data: products, error } = await supabase
            .from('products')
            .select(`
                *,
                variants (
                    id, size, color, sku, image_url, current_price, is_deleted,
                    inventory_batches ( quantity_remaining, cost_price, created_at ) 
                ),
                categories!fk_products_main_category (name)
            `)
            .order('created_at', { ascending: false });

        if (error) throw error;

        // 2. Chuẩn bị file Excel
        const workbook = new exceljs.Workbook();
        const worksheet = workbook.addWorksheet('Danh sách sản phẩm');

        // Định nghĩa chính xác các cột theo mẫu Sapo
        worksheet.columns = [
            { header: 'Đường dẫn/Alias', key: 'alias', width: 25 },
            { header: 'Tên sản phẩm*', key: 'name', width: 40 },
            { header: 'Mô tả sản phẩm', key: 'description', width: 30 },
            { header: 'Nhãn hiệu', key: 'brand', width: 15 },
            { header: 'Loại sản phẩm', key: 'category', width: 20 },
            { header: 'Nhóm ngành nghề tính thuế GTGT, TNCN', key: 'tax_group', width: 15 },
            { header: 'Tags', key: 'tags', width: 15 },
            { header: 'Yêu cầu vận chuyển', key: 'require_shipping', width: 15 },
            { header: 'Hiển thị*', key: 'is_active', width: 15 },
            { header: 'Thuộc tính 1', key: 'attr1_name', width: 15 },
            { header: 'Giá trị thuộc tính 1', key: 'attr1_val', width: 20 },
            { header: 'Thuộc tính 2', key: 'attr2_name', width: 15 },
            { header: 'Giá trị thuộc tính 2', key: 'attr2_val', width: 20 },
            { header: 'Thuộc tính 3', key: 'attr3_name', width: 15 },
            { header: 'Giá trị thuộc tính 3', key: 'attr3_val', width: 20 },
            { header: 'Áp dụng thuế', key: 'taxable', width: 15 },
            { header: 'Mã SKU', key: 'sku', width: 20 },
            { header: 'Barcode', key: 'barcode', width: 15 },
            { header: 'Đơn vị tính', key: 'unit', width: 15 },
            { header: 'Ảnh đại diện', key: 'main_image', width: 40 },
            { header: 'Chú thích ảnh', key: 'image_alt', width: 15 },
            { header: 'Thẻ tiêu đề(SEO Title)', key: 'seo_title', width: 15 },
            { header: 'Thẻ mô tả(SEO Description)', key: 'seo_desc', width: 15 },
            { header: 'Mô tả ngắn', key: 'short_desc', width: 15 },
            { header: 'Quản lý kho', key: 'inventory_tracker', width: 15 },
            { header: 'Quản lý lô - HSD', key: 'lot_tracking', width: 15 },
            { header: 'Số ngày cảnh báo trước hết hạn', key: 'expire_warning', width: 15 },
            { header: 'Khối lượng', key: 'weight', width: 15 },
            { header: 'Đơn vị khối lượng', key: 'weight_unit', width: 15 },
            { header: 'Ảnh phiên bản', key: 'variant_image', width: 40 },
            { header: 'Cho phép tiếp tục mua khi hết hàng', key: 'continue_selling', width: 25 },
            { header: 'Giá', key: 'price', width: 15 },
            { header: 'Giá so sánh', key: 'compare_price', width: 15 },
            { header: 'Giá vốn', key: 'cost_price', width: 15 },
            { header: 'Cửa hàng chính_Tồn kho', key: 'stock', width: 20 },
            { header: 'Id phiên bản', key: 'variant_id', width: 15 }
        ];

        // 3. Đổ dữ liệu vào hàng (Logic: Dòng đầu tiên đầy đủ, các dòng biến thể sau ẩn thông tin chung)
        products.forEach(product => {
            const alias = product.slug;
            const categoryName = product.categories?.name || '';
            const isActive = product.is_active ? 'Có' : 'Không';
            const isPreorder = product.is_preorder ? 'Có' : 'Không';
            const mainImage = product.images && product.images.length > 0 ? product.images[0] : '';
            
            // Xóa HTML tags trong mô tả (Sapo nhận text trơn hoặc HTML)
            let description = product.description || '';

            const validVariants = product.variants ? product.variants.filter(v => v.is_deleted === false) : [];
            if (validVariants && validVariants.length > 0) {
                validVariants.forEach((variant, index) => {
                    const isFirst = index === 0; // Đánh dấu dòng biến thể đầu tiên của sản phẩm

                    // Tính tồn kho
                    const totalStock = variant.inventory_batches 
                        ? variant.inventory_batches.reduce((sum, batch) => sum + (Number(batch.quantity_remaining) || 0), 0)
                        : 0;

                    // Tính giá vốn (lấy lô mới nhất)
                    let costPrice = 0;
                    if (variant.inventory_batches && variant.inventory_batches.length > 0) {
                        const sortedBatches = variant.inventory_batches.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
                        costPrice = sortedBatches[0].cost_price || 0;
                    }

                    worksheet.addRow({
                        alias: alias,
                        name: isFirst ? product.name : '',
                        description: isFirst ? description : '',
                        brand: '',
                        category: isFirst ? categoryName : '',
                        tax_group: '101',
                        tags: '',
                        require_shipping: isFirst ? 'Có' : '',
                        is_active: isFirst ? isActive : '',
                        
                        attr1_name: variant.size ? 'Kích thước' : '',
                        attr1_val: variant.size || '',
                        attr2_name: variant.color ? 'Màu sắc' : '',
                        attr2_val: variant.color || '',
                        attr3_name: '',
                        attr3_val: '',
                        
                        taxable: 'Không',
                        sku: variant.sku || '',
                        barcode: '',
                        unit: isFirst ? 'Cái' : '', // Đơn vị tính mặc định
                        main_image: isFirst ? mainImage : '',
                        image_alt: '',
                        seo_title: '',
                        seo_desc: '',
                        short_desc: '',
                        
                        inventory_tracker: 'Sapo', // Chữ "Sapo" để Sapo hiểu là quản lý kho
                        lot_tracking: '',
                        expire_warning: '',
                        weight: '',
                        weight_unit: '',
                        
                        variant_image: variant.image_url || '',
                        continue_selling: isPreorder, // Preorder chính là "Cho phép tiếp tục mua"
                        
                        price: variant.current_price || product.base_price || 0,
                        compare_price: product.base_price || 0,
                        cost_price: costPrice,
                        stock: totalStock,
                        variant_id: variant.id || '' // Rất quan trọng khi cập nhật Sapo
                    });
                });
            } else {
                // Trường hợp sản phẩm không có biến thể nào
                worksheet.addRow({
                    alias: alias,
                    name: product.name,
                    description: description,
                    category: categoryName,
                    require_shipping: 'Có',
                    is_active: isActive,
                    taxable: 'Không',
                    unit: 'Cái',
                    main_image: mainImage,
                    inventory_tracker: 'Sapo',
                    continue_selling: isPreorder,
                    price: product.base_price || 0,
                    compare_price: product.base_price || 0,
                    cost_price: 0,
                    stock: 0
                });
            }
        });

        // 4. Trả file về cho trình duyệt tải xuống
        res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        res.setHeader('Content-Disposition', 'attachment; filename=' + `Sapo_Products_Export_${new Date().toISOString().slice(0,10)}.xlsx`);

        await workbook.xlsx.write(res);
        res.end();

    } catch (error) {
        console.error("Export Sapo Excel Error:", error);
        res.status(500).json({ success: false, message: 'Lỗi xuất file Excel Sapo: ' + error.message });
    }
};
