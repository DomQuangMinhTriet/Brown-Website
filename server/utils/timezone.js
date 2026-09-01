// Server (Railway) chạy theo giờ UTC, nhưng khách hàng và số liệu kinh doanh đều
// theo giờ Việt Nam (UTC+7, không có DST). Mọi mốc "đầu ngày/cuối ngày/đầu tháng/
// cuối tháng" dùng cho báo cáo PHẢI tính tường minh theo +07:00, không được dùng
// new Date(y, m, d) hay .setHours() vì các hàm đó lấy theo giờ local của server.
const VN_OFFSET = '+07:00';
const pad2 = (n) => String(n).padStart(2, '0');

// 'YYYY-MM-DD' -> thời điểm UTC tương ứng 00:00:00.000 giờ VN của ngày đó
const vnStartOfDayISO = (dateStr) => new Date(`${dateStr}T00:00:00.000${VN_OFFSET}`).toISOString();

// 'YYYY-MM-DD' -> thời điểm UTC tương ứng 23:59:59.999 giờ VN của ngày đó
const vnEndOfDayISO = (dateStr) => new Date(`${dateStr}T23:59:59.999${VN_OFFSET}`).toISOString();

// Ngày/tháng/năm hiện tại THEO GIỜ VN, bất kể server đang chạy múi giờ nào
const vnNowParts = () => {
    const shifted = new Date(Date.now() + 7 * 60 * 60 * 1000);
    return { year: shifted.getUTCFullYear(), month: shifted.getUTCMonth() + 1, day: shifted.getUTCDate() };
};

// year, month (1-12) -> khoảng ngày + mốc ISO (UTC) bao trọn tháng đó theo giờ VN.
// startDate/endDate ('YYYY-MM-DD') dùng cho cột kiểu date (vd. expense_date);
// startISO/endISO dùng cho cột timestamptz (vd. created_at).
const vnMonthRange = (year, month) => {
    const mm = pad2(month);
    const lastDay = new Date(Date.UTC(year, month, 0)).getUTCDate();
    const startDate = `${year}-${mm}-01`;
    const endDate = `${year}-${mm}-${pad2(lastDay)}`;
    return { startDate, endDate, startISO: vnStartOfDayISO(startDate), endISO: vnEndOfDayISO(endDate) };
};

module.exports = { vnStartOfDayISO, vnEndOfDayISO, vnNowParts, vnMonthRange };
