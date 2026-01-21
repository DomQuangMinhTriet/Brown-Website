const supabase = require('../config/supabase');

// 1. LẤY DANH SÁCH SẢN PHẨM
exports.getProducts = async (req, res) => {
    try {
<<<<<<< HEAD

        // THÊM: , variants(*) vào trong select để lấy kèm các biến thể
        const { data, error } = await supabase
            .from('products')
            .select('*, variants(*)') 
            .order('created_at', { ascending: false });
        // Lấy tham số search từ URL (VD: /api/products?search=ao)
        const { search } = req.query;

        let query = supabase
            .from('products')
            .select('*, variants(*)')
            .order('created_at', { ascending: false });

        // NẾU CÓ TỪ KHÓA TÌM KIẾM -> THÊM ĐIỀU KIỆN LỌC
        if (search) {
            // ilike là tìm kiếm không phân biệt hoa thường (Case-insensitive)
            // %search% là tìm kiếm tương đối (chứa từ khóa)
            query = query.ilike('name', `%${search}%`);
        }

        if (error) throw error;
        res.json({ success: true, data });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};
//Tạo sản phẩm
exports.createProduct = async (req, res) => {
    try {
        const { 
            name, 
            slug, 
            description, 
            base_price, 
            images, 
            category_id, 
            variants // Là một mảng: [{size: 'S', color: 'Trắng', sku: 'A-S-W', ...}]
        } = req.body;

        // 1. Validation cơ bản
        if (!name || !slug || !base_price) {
            return res.status(400).json({ success: false, message: 'Thiếu thông tin bắt buộc!' });
        }

        console.log("📝 Đang tạo sản phẩm:", name);

        // 2. Tạo sản phẩm vào bảng 'products'
        const { data: productData, error: productError } = await supabase
            .from('products')
            .insert([{
                name,
                slug,
                description,
                base_price,
                images // Mảng đường dẫn ảnh
            }])
            .select()
            .single();

        if (productError) throw productError;
        const newProductId = productData.id;

        // 3. Liên kết danh mục (nếu có chọn)
        if (category_id) {
            const { error: catError } = await supabase
                .from('product_categories')
                .insert([{ product_id: newProductId, category_id: category_id }]);
            
            if (catError) console.error("Lỗi link danh mục:", catError); // Ko chặn luồng chính
        }

        // 4. Tạo các biến thể (Variants)
        if (variants && variants.length > 0) {
            const variantsData = variants.map(v => ({
                product_id: newProductId,
                sku: v.sku,
                size: v.size,
                color: v.color,
                current_price: v.price || base_price // Nếu không nhập giá riêng thì lấy giá gốc
            }));

            const { error: variantError } = await supabase
                .from('variants')
                .insert(variantsData);

            if (variantError) throw variantError;
        }
        
        clearCache('/api/products');
        
        res.json({ success: true, data: productData, message: 'Tạo sản phẩm thành công!' });

    } catch (error) {
        console.error("❌ Lỗi tạo sản phẩm:", error);
=======
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
>>>>>>> Frontend
        res.status(500).json({ success: false, message: error.message });
    }
};

// 2. LẤY CHI TIẾT 1 SẢN PHẨM (THEO SLUG)
exports.getProductBySlug = async (req, res) => {
    try {
        const { slug } = req.params;
        
        // 1. Lấy thông tin sản phẩm và các biến thể
        const { data: product, error } = await supabase
            .from('products')
            .select(`
                *,
<<<<<<< HEAD
                variants (*)
            `)
=======
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
>>>>>>> Frontend
            .eq('slug', slug)
            .single();

        if (error) throw error;
<<<<<<< HEAD
        if (!product) return res.status(404).json({ success: false, message: 'Not found' });

        // 2. TÍNH TOÁN TỒN KHO CHO TỪNG BIẾN THỂ (MỚI)
        // Lấy danh sách ID của các biến thể
        const variantIds = product.variants.map(v => v.id);

        // Lấy tất cả các lô hàng (batches) của các biến thể này
        const { data: batches } = await supabase
            .from('inventory_batches')
            .select('variant_id, quantity_remaining')
            .in('variant_id', variantIds);

        // Cộng dồn số lượng tồn kho theo từng variant_id
        const stockMap = {};
        batches.forEach(batch => {
            if (!stockMap[batch.variant_id]) stockMap[batch.variant_id] = 0;
            stockMap[batch.variant_id] += batch.quantity_remaining;
        });

        // Gán số lượng tồn kho ngược lại vào mảng variants
        product.variants = product.variants.map(v => ({
            ...v,
            inventory: stockMap[v.id] || 0 // Nếu không có batch nào thì tồn = 0
        }));

        res.json({ success: true, data: product });

    } catch (error) {
        console.error("Lỗi lấy sản phẩm:", error);
        res.status(500).json({ success: false, message: error.message });
=======
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
>>>>>>> Frontend
    }
};