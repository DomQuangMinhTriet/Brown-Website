// Import client đã cấu hình sẵn (Lưu ý đường dẫn ../config/supabase)
const supabase = require('../config/supabase');

// Lấy danh sách
exports.getProducts = async (req, res) => {
    try {
<<<<<<< Updated upstream
        // THÊM: , variants(*) vào trong select để lấy kèm các biến thể
        const { data, error } = await supabase
            .from('products')
            .select('*, variants(*)') 
            .order('created_at', { ascending: false });

=======
<<<<<<< Updated upstream
        const { data, error } = await supabase.from('products').select('*');
=======
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

        const { data, error } = await query;

>>>>>>> Stashed changes
>>>>>>> Stashed changes
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

        res.json({ success: true, data: productData, message: 'Tạo sản phẩm thành công!' });

    } catch (error) {
        console.error("❌ Lỗi tạo sản phẩm:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};

// Lấy chi tiết
exports.getProductBySlug = async (req, res) => {
    try {
        const { slug } = req.params;
        
        // 1. Lấy thông tin sản phẩm và các biến thể
        const { data: product, error } = await supabase
            .from('products')
            .select(`
                *,
                variants (*)
            `)
            .eq('slug', slug)
            .single();

        if (error) throw error;
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
    }
};