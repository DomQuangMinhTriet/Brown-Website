const supabase = require('../config/supabase');

// A non-inventory product has intentionally no COGS. Do not apply the legacy
// 70% fallback to it, otherwise a zero COGS line becomes a false loss again.
const hasNoInventoryCost = (product) =>
    product?.tracks_inventory === false || product?.name === 'Phụ kiện BrownVN';
const isRevenueAdjustment = (product) =>
    product?.is_revenue_adjustment === true || product?.name === 'Phụ kiện BrownVN';

exports.getDashboardStats = async (req, res) => {
    try {
        // [MỚI] Lấy ngày đầu và ngày cuối của tháng hiện tại
        const date = new Date();
        const startOfMonth = new Date(date.getFullYear(), date.getMonth(), 1).toISOString();
        const endOfMonth = new Date(date.getFullYear(), date.getMonth() + 1, 0, 23, 59, 59, 999).toISOString();

        // Tính doanh thu tháng này
        const revenuePromise = supabase.from('orders').select('total_amount')
            .in('status', ['completed', 'shipping']).gte('created_at', startOfMonth).lte('created_at', endOfMonth);

        // Đếm số đơn hàng tháng này
        const ordersPromise = supabase
            .from('orders')
            .select('*', { count: 'exact', head: true })
            .gte('created_at', startOfMonth)
            .lte('created_at', endOfMonth);
        
        // Đếm số khách hàng mới tháng này
        const customersPromise = supabase
            .from('customers')
            .select('*', { count: 'exact', head: true })
            .gte('created_at', startOfMonth)
            .lte('created_at', endOfMonth);

        // Đơn hàng gần nhất thì vẫn lấy 5 đơn mới nhất
        const recentPromise = supabase
            .from('orders')
            .select('id, code, customer_name, total_amount, status, created_at')
            .order('created_at', { ascending: false })
            .limit(5);

        const [revenueResult, ordersResult, customersResult, recentResult] = await Promise.all([
            revenuePromise, ordersPromise, customersPromise, recentPromise,
        ]);
        const firstError = revenueResult.error || ordersResult.error || customersResult.error || recentResult.error;
        if (firstError) throw firstError;

        const totalRevenue = (revenueResult.data || []).reduce((sum, order) => sum + Number(order.total_amount || 0), 0);
        const totalOrders = ordersResult.count || 0;
        const totalCustomers = customersResult.count || 0;
        const recentOrders = recentResult.data || [];

        res.json({
            success: true,
            data: {
                revenue: totalRevenue,
                orders: totalOrders || 0,
                customers: totalCustomers || 0,
                recentOrders: recentOrders || []
            }
        });

    } catch (error) {
        console.error("Lỗi báo cáo Dashboard:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};

// 2. BÁO CÁO TÀI CHÍNH CHI TIẾT
exports.getFinancialReport = async (req, res) => {
    try {
        const { startDate, endDate } = req.query;

        // [SỬA 1] CHUẨN HÓA NGÀY THÁNG SANG ISO STRING
        const startISO = new Date(startDate).toISOString();
        const endObj = new Date(endDate);
        endObj.setHours(23, 59, 59, 999);
        const endISO = endObj.toISOString();

        console.log(`📊 Báo cáo từ ${startISO} đến ${endISO}`);

        let queryOrders = supabase
            .from('orders')
            .select(`
                total_amount,
                created_at,
                status,
                code, 
                note,
                order_items (
                    price_at_purchase,
                    quantity,
                    cogs_total,
                    variants ( products ( name, tracks_inventory ) )
                )
            `)
            // [SỬA 2] LẤY ĐƠN HOÀN THÀNH VÀ ĐANG GIAO
            .in('status', ['completed', 'shipping']) 
            .gte('created_at', startISO)
            .lte('created_at', endISO);

        let queryExpenses = supabase
            .from('expenses')
            .select('amount, created_at')
            .gte('expense_date', startISO)
            .lte('expense_date', endISO);

        const [ordersRes, expensesRes] = await Promise.all([queryOrders, queryExpenses]);

        if (ordersRes.error) throw ordersRes.error;
        if (expensesRes.error) throw expensesRes.error;

        const orders = ordersRes.data;
        const expenses = expensesRes.data;

        // --- TÍNH TOÁN ---

        // 1. Doanh thu
        const revenue = orders.reduce((sum, o) => sum + o.total_amount, 0);

        // 2. Giá vốn (CÓ FALLBACK CHO DỮ LIỆU CŨ)
        const cogs = orders.reduce((sum, o) => {
            const orderCogs = o.order_items.reduce((itemSum, item) => {
                let cost = item.cogs_total || 0;
                // Nếu dữ liệu cũ chưa có giá vốn, tạm tính = 70% giá bán
                if (cost === 0 && item.price_at_purchase > 0 && !hasNoInventoryCost(item.variants?.products)) {
                    cost = (item.price_at_purchase * item.quantity) * 0.7; 
                }
                return itemSum + cost;
            }, 0);
            return sum + orderCogs;
        }, 0);

        // --- [MỚI] TÍNH TOÁN NGUỒN ĐƠN HÀNG (SOURCE BREAKDOWN) ---
        const sourceStats = {};
        
        orders.forEach(o => {
            let source = 'Khác';
            const noteLower = o.note ? o.note.toLowerCase() : '';
            const code = o.code || '';

            // Logic xác định nguồn
            if (code.startsWith('ORD-')) {
                source = 'Website';
            } else if (noteLower.includes('shopee')) {
                source = 'Shopee';
            } else if (noteLower.includes('tiktok')) {
                source = 'TikTok';
            } else if (noteLower.includes('ig') || noteLower.includes('instagram')) {
                source = 'Instagram';
            } else if (noteLower.includes('fb') || noteLower.includes('facebook')) {
                source = 'Facebook';
            } else if (noteLower.includes('zalo')) {
                source = 'Zalo';
            } else {
                source = 'Khác';
            }

            // Cộng dồn doanh thu theo nguồn
            if (!sourceStats[source]) {
                sourceStats[source] = 0;
            }
            sourceStats[source] += o.total_amount;
        });

        const grossProfit = revenue - cogs;
        const totalExpenses = expenses.reduce((sum, e) => sum + e.amount, 0);
        const netProfit = grossProfit - totalExpenses;
        const margin = revenue > 0 ? ((netProfit / revenue) * 100).toFixed(2) : 0;

        res.json({
            success: true,
            data: {
                revenue,
                cogs,
                grossProfit,
                totalExpenses,
                netProfit,
                margin,
                orderCount: orders.length,
                expenseCount: expenses.length,
                revenueBySource: sourceStats // [MỚI] Trả về dữ liệu nguồn
            }
        });

    } catch (error) {
        console.error("Lỗi báo cáo tài chính:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};

// [MỚI] BÁO CÁO SẢN PHẨM BÁN CHẠY THEO THỜI GIAN — dùng cùng bộ lọc trạng thái
// đơn (completed/shipping) với getFinancialReport để số liệu nhất quán giữa
// các báo cáo cùng khoảng thời gian.
exports.getProductSalesReport = async (req, res) => {
    try {
        const { startDate, endDate } = req.query;

        const startISO = new Date(startDate).toISOString();
        const endObj = new Date(endDate);
        endObj.setHours(23, 59, 59, 999);
        const endISO = endObj.toISOString();

        const { data: orders, error } = await supabase
            .from('orders')
            .select(`
                created_at, status,
                order_items (
                    quantity, price_at_purchase, cogs_total,
                    variants ( product_id, products ( id, name, images, tracks_inventory, is_revenue_adjustment ) )
                )
            `)
            .in('status', ['completed', 'shipping'])
            .gte('created_at', startISO)
            .lte('created_at', endISO);

        if (error) throw error;

        // Gộp theo product_id: tổng số lượng bán, doanh thu, giá vốn
        const map = {};
        for (const order of orders) {
            for (const item of order.order_items || []) {
                const product = item.variants?.products;
                if (!product) continue;

                if (!map[product.id]) {
                    map[product.id] = {
                        product_id: product.id,
                        name: product.name,
                        image: product.images?.[0] || null,
                        quantity: 0,
                        revenue: 0,
                        cogs: 0,
                        is_revenue_adjustment: isRevenueAdjustment(product),
                    };
                }
                map[product.id].quantity += item.quantity || 0;
                map[product.id].revenue += (item.price_at_purchase || 0) * (item.quantity || 0);
                map[product.id].cogs += Number(item.cogs_total) || 0;
            }
        }

        const list = Object.values(map)
            .map((p) => ({ ...p, profit: p.revenue - p.cogs }))
            .sort((a, b) => b.revenue - a.revenue);

        res.json({ success: true, data: list });
    } catch (error) {
        console.error("Lỗi báo cáo sản phẩm:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};

exports.getMonthlyFinancialReport = async (req, res) => {
    try {
        const { month, year } = req.query;
        const targetMonth = parseInt(month);
        const targetYear = parseInt(year);

        // Tháng hiện tại được chọn
        const startCurrent = new Date(targetYear, targetMonth - 1, 1).toISOString();
        const endCurrent = new Date(targetYear, targetMonth, 0, 23, 59, 59, 999).toISOString();

        // Tháng liền trước đó để so sánh
        const startPrev = new Date(targetYear, targetMonth - 2, 1).toISOString();
        const endPrev = new Date(targetYear, targetMonth - 1, 0, 23, 59, 59, 999).toISOString();

        // Hàm helper để truy xuất số liệu theo khoảng thời gian
        const getStatsForPeriod = async (start, end) => {
            const [ordersRes, expensesRes] = await Promise.all([
                supabase.from('orders').select('total_amount, order_items(cogs_total, variants(products(name, tracks_inventory)))')
                        .in('status', ['completed', 'shipping']).gte('created_at', start).lte('created_at', end),
                supabase.from('expenses').select('amount').gte('expense_date', start).lte('expense_date', end)
            ]);

            const orders = ordersRes.data || [];
            const expenses = expensesRes.data || [];

            const revenue = orders.reduce((sum, o) => sum + o.total_amount, 0);
            // Tính tổng giá vốn (cogs_total lưu trong bảng order_items)
            const cogs = orders.reduce((sum, o) => {
                const itemsCogs = o.order_items?.reduce((itemSum, item) => itemSum + (Number(item.cogs_total) || 0), 0) || 0;
                return sum + itemsCogs;
            }, 0);
            
            const totalExpenses = expenses.reduce((sum, e) => sum + Number(e.amount), 0);
            const netProfit = revenue - cogs - totalExpenses;

            return { revenue, cogs, totalExpenses, netProfit, orderCount: orders.length };
        };

        const currentData = await getStatsForPeriod(startCurrent, endCurrent);
        const prevData = await getStatsForPeriod(startPrev, endPrev);

        res.json({
            success: true,
            data: { current: currentData, previous: prevData }
        });
    } catch (error) {
        console.error("Lỗi báo cáo tháng:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};
