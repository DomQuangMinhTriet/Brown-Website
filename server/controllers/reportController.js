const supabase = require('../config/supabase');

exports.getDashboardStats = async (req, res) => {
    try {
        // [CẬP NHẬT] DASHBOARD: Tính doanh thu đơn HOÀN THÀNH + ĐANG GIAO
        const { data: revenueData, error: revError } = await supabase
            .from('orders')
            .select('total_amount')
            .in('status', ['completed', 'shipping']); // <--- SỬA: Lấy cả 2 trạng thái
        
        if (revError) throw revError;
        const totalRevenue = revenueData.reduce((sum, order) => sum + order.total_amount, 0);

        // Đếm tổng đơn (vẫn đếm hết để biết traffic)
        const { count: totalOrders, error: orderError } = await supabase
            .from('orders')
            .select('*', { count: 'exact', head: true });
        
        if (orderError) throw orderError;

        const { count: totalCustomers, error: cusError } = await supabase
            .from('customers')
            .select('*', { count: 'exact', head: true });

        if (cusError) throw cusError;

        const { data: recentOrders, error: recentError } = await supabase
            .from('orders')
            .select('id, code, customer_name, total_amount, status, created_at')
            .order('created_at', { ascending: false })
            .limit(5);

        if (recentError) throw recentError;

        res.json({
            success: true,
            data: {
                revenue: totalRevenue,
                orders: totalOrders,
                customers: totalCustomers || 0,
                recentOrders: recentOrders
            }
        });

    } catch (error) {
        console.error("Lỗi báo cáo:", error);
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
                order_items (
                    price_at_purchase,
                    quantity,
                    cogs_total
                )
            `)
            // [SỬA 2] LẤY ĐƠN HOÀN THÀNH VÀ ĐANG GIAO
            .in('status', ['completed', 'shipping']) // <--- SỬA Ở ĐÂY
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
                if (cost === 0 && item.price_at_purchase > 0) {
                    cost = (item.price_at_purchase * item.quantity) * 0.7; 
                }
                return itemSum + cost;
            }, 0);
            return sum + orderCogs;
        }, 0);

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
                expenseCount: expenses.length
            }
        });

    } catch (error) {
        console.error("Lỗi báo cáo tài chính:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};