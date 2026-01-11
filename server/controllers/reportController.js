const supabase = require('../config/supabase');

exports.getDashboardStats = async (req, res) => {
    try {
        // 1. TÍNH TỔNG DOANH THU (Chỉ tính đơn đã hoàn thành hoặc đang xử lý, trừ đơn hủy)
        const { data: revenueData, error: revError } = await supabase
            .from('orders')
            .select('total_amount')
            .neq('status', 'cancelled'); // Không tính đơn hủy
        
        if (revError) throw revError;
        const totalRevenue = revenueData.reduce((sum, order) => sum + order.total_amount, 0);

        // 2. ĐẾM TỔNG ĐƠN HÀNG
        const { count: totalOrders, error: orderError } = await supabase
            .from('orders')
            .select('*', { count: 'exact', head: true });
        
        if (orderError) throw orderError;

        // 3. ĐẾM TỔNG KHÁCH HÀNG (Dựa trên số điện thoại duy nhất trong bảng orders hoặc bảng customers)
        // Ở đây ta đếm trong bảng customers cho chuẩn
        const { count: totalCustomers, error: cusError } = await supabase
            .from('customers')
            .select('*', { count: 'exact', head: true });

        if (cusError) throw cusError;

        // 4. LẤY 5 ĐƠN HÀNG GẦN NHẤT
        const { data: recentOrders, error: recentError } = await supabase
            .from('orders')
            .select('id, code, customer_name, total_amount, status, created_at')
            .order('created_at', { ascending: false })
            .limit(5);

        if (recentError) throw recentError;

        // Trả về kết quả tổng hợp
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

// 2. BÁO CÁO TÀI CHÍNH CHI TIẾT (Hàm mới)
exports.getFinancialReport = async (req, res) => {
    try {
        const { startDate, endDate } = req.query; // Nhận tham số lọc ngày (VD: ?startDate=2025-01-01&endDate=2025-01-31)

        let queryOrders = supabase
            .from('orders')
            .select(`
                total_amount,
                created_at,
                order_items (
                    cogs_total
                )
            `)
            .neq('status', 'cancelled'); // Không tính đơn hủy

        let queryExpenses = supabase
            .from('expenses')
            .select('amount, created_at');

        // Áp dụng bộ lọc ngày nếu có
        if (startDate && endDate) {
            queryOrders = queryOrders.gte('created_at', startDate).lte('created_at', endDate);
            queryExpenses = queryExpenses.gte('expense_date', startDate).lte('expense_date', endDate);
        }

        // Chạy song song 2 câu lệnh
        const [ordersRes, expensesRes] = await Promise.all([queryOrders, queryExpenses]);

        if (ordersRes.error) throw ordersRes.error;
        if (expensesRes.error) throw expensesRes.error;

        const orders = ordersRes.data;
        const expenses = expensesRes.data;

        // --- TÍNH TOÁN ---

        // 1. Doanh thu (Revenue)
        const revenue = orders.reduce((sum, o) => sum + o.total_amount, 0);

        // 2. Giá vốn hàng bán (COGS)
        // Lưu ý: order_items là mảng, cần tính tổng lồng nhau
        const cogs = orders.reduce((sum, o) => {
            const orderCogs = o.order_items.reduce((itemSum, item) => itemSum + (item.cogs_total || 0), 0);
            return sum + orderCogs;
        }, 0);

        // 3. Lợi nhuận gộp (Gross Profit)
        const grossProfit = revenue - cogs;

        // 4. Tổng Chi phí vận hành (Operating Expenses)
        const totalExpenses = expenses.reduce((sum, e) => sum + e.amount, 0);

        // 5. Lợi nhuận ròng (Net Profit)
        const netProfit = grossProfit - totalExpenses;

        // 6. Tỷ suất lợi nhuận (Profit Margin)
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