const supabase = require('../config/supabase');

// 1. LẤY DANH SÁCH SẢN PHẨM (Kèm tính toán tồn kho thực tế)
exports.getProducts = async (req, res) => {
    try {
        const { search, category } = req.query; // category ở đây là SLUG (ví dụ: 'ao-thun')

        // 1. Khởi tạo Query cơ bản
        let query = supabase
            .from('products')
            .select(`
                *,
                variants (id, size, color, sku),
                categories (id, name, slug)
            `)
            .eq('is_active', true)
            .order('created_at', { ascending: false });

        // 2. Logic tìm kiếm theo tên
        if (search) {
            query = query.ilike('name', `%${search}%`);
        }

        // 3. --- [FIX QUAN TRỌNG] LOGIC LỌC DANH MỤC ---
        if (category) {
            // A. Tìm ID của danh mục dựa trên Slug trước
            const { data: catData, error: catError } = await supabase
                .from('categories')
                .select('id')
                .eq('slug', category)
                .single(); // Lấy 1 dòng duy nhất

            // B. Nếu tìm thấy danh mục -> Lọc sản phẩm theo ID đó
            if (catData) {
                query = query.eq('category_id', catData.id);
            } else {
                // Nếu slug không tồn tại (ví dụ: ?category=lung-tung) -> Trả về rỗng luôn
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
        const { name, base_price, description, category_id, images, variants, size_chart_url } = req.body;

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
                category_id: category_id,
                size_chart_url: size_chart_url,
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
        const { name, slug, base_price, description, category_id, images, variants, size_chart_url } = req.body;

        // A. Cập nhật thông tin cơ bản
        const { error: prodError } = await supabase
            .from('products')
            .update({ 
                name, 
                slug,
                base_price, 
                description, 
                category_id: category_id,
                size_chart_url: size_chart_url,
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