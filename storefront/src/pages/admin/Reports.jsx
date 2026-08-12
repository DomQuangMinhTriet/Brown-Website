/* eslint-disable react-hooks/exhaustive-deps */
import { useEffect, useState, useMemo } from 'react';
import axios from 'axios';
import { 
  Chart as ChartJS, 
  ArcElement, 
  Tooltip, 
  Legend, 
  Title 
} from 'chart.js';
import { Doughnut } from 'react-chartjs-2'; 
import { FaCalendarAlt, FaFileExcel, FaFilter, FaSort, FaSortUp, FaSortDown } from 'react-icons/fa';
import { optimizeImage } from '../../utils/cloudinaryHelper';

// Đăng ký các thành phần biểu đồ
ChartJS.register(ArcElement, Tooltip, Legend, Title);

// Hàm Helper: Định dạng Date -> YYYY-MM-DD theo múi giờ local
const toYMD = (d) => {
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
};

const Reports = () => {
  // State: Mặc định chế độ là 'month'
  const [reportMode, setReportMode] = useState('month'); 
  
  // State: Lưu giá trị input ngày/tháng
  const [dateValue, setDateValue] = useState(() => {
      const today = new Date();
      return `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}`;
  });

  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);

  // Cập nhật giá trị mặc định khi đổi chế độ (Từ tháng -> ngày hoặc ngược lại)
  const handleModeChange = (e) => {
      const newMode = e.target.value;
      setReportMode(newMode);
      const today = new Date();
      if (newMode === 'month') {
          setDateValue(`${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}`);
      } else {
          setDateValue(toYMD(today));
      }
  };

  // Hàm tính toán Khoảng thời gian Hiện tại & Kỳ trước
  const getPeriods = (mode, val) => {
      let startCurr, endCurr, startPrev, endPrev;
      const d = new Date(val);

      if (mode === 'day') {
          startCurr = endCurr = toYMD(d);
          const prev = new Date(d);
          prev.setDate(prev.getDate() - 1);
          startPrev = endPrev = toYMD(prev);
      } 
      else if (mode === 'week') {
          // Tính Thứ 2 và Chủ nhật của tuần hiện tại
          const day = d.getDay() || 7; 
          const monday = new Date(d);
          monday.setDate(monday.getDate() - day + 1);
          const sunday = new Date(monday);
          sunday.setDate(sunday.getDate() + 6);
          
          startCurr = toYMD(monday);
          endCurr = toYMD(sunday);

          // Lùi 7 ngày để lấy tuần trước
          const prevMonday = new Date(monday);
          prevMonday.setDate(prevMonday.getDate() - 7);
          const prevSunday = new Date(sunday);
          prevSunday.setDate(prevSunday.getDate() - 7);

          startPrev = toYMD(prevMonday);
          endPrev = toYMD(prevSunday);
      } 
      else if (mode === 'month') {
          const [y, m] = val.split('-');
          const year = parseInt(y);
          const month = parseInt(m);

          startCurr = toYMD(new Date(year, month - 1, 1));
          endCurr = toYMD(new Date(year, month, 0));

          startPrev = toYMD(new Date(year, month - 2, 1));
          endPrev = toYMD(new Date(year, month - 1, 0));
      }

      return { startCurr, endCurr, startPrev, endPrev };
  };

  useEffect(() => {
    fetchReport();
  }, [reportMode, dateValue]);

  // --- BẢNG XẾP HẠNG SẢN PHẨM: bộ lọc nhanh riêng, mặc định Tuần này ---
  const [productPreset, setProductPreset] = useState('week');
  const [productCustomStart, setProductCustomStart] = useState(toYMD(new Date()));
  const [productCustomEnd, setProductCustomEnd] = useState(toYMD(new Date()));
  const [productSales, setProductSales] = useState([]);
  const [productSalesLoading, setProductSalesLoading] = useState(true);
  const [productSort, setProductSort] = useState({ key: 'revenue', dir: 'desc' });

  const getProductDateRange = () => {
      const today = new Date();
      if (productPreset === 'week') {
          const day = today.getDay() || 7;
          const monday = new Date(today);
          monday.setDate(monday.getDate() - day + 1);
          const sunday = new Date(monday);
          sunday.setDate(sunday.getDate() + 6);
          return { start: toYMD(monday), end: toYMD(sunday) };
      }
      if (productPreset === 'month') {
          return {
              start: toYMD(new Date(today.getFullYear(), today.getMonth(), 1)),
              end: toYMD(new Date(today.getFullYear(), today.getMonth() + 1, 0))
          };
      }
      if (productPreset === 'quarter') {
          const q = Math.floor(today.getMonth() / 3);
          return {
              start: toYMD(new Date(today.getFullYear(), q * 3, 1)),
              end: toYMD(new Date(today.getFullYear(), q * 3 + 3, 0))
          };
      }
      return { start: productCustomStart, end: productCustomEnd };
  };

  useEffect(() => {
      fetchProductSales();
  }, [productPreset, productCustomStart, productCustomEnd]);

  const fetchProductSales = async () => {
      setProductSalesLoading(true);
      try {
          const { start, end } = getProductDateRange();
          const res = await axios.get(`${import.meta.env.VITE_API_URL}/api/reports/products?startDate=${start}&endDate=${end}`);
          if (res.data.success) setProductSales(res.data.data);
      } catch (error) {
          console.error("Lỗi tải báo cáo sản phẩm:", error);
      } finally {
          setProductSalesLoading(false);
      }
  };

  const sortedProductSales = useMemo(() => {
      const arr = [...productSales];
      const { key, dir } = productSort;
      arr.sort((a, b) => dir === 'asc' ? a[key] - b[key] : b[key] - a[key]);
      return arr;
  }, [productSales, productSort]);

  const handleSortProduct = (key) => {
      setProductSort(prev => prev.key === key ? { key, dir: prev.dir === 'desc' ? 'asc' : 'desc' } : { key, dir: 'desc' });
  };

  const SortIcon = ({ column }) => {
      if (productSort.key !== column) return <FaSort className="text-stone-300" size={11} />;
      return productSort.dir === 'desc' ? <FaSortDown size={11} /> : <FaSortUp size={11} />;
  };

  const fetchReport = async () => {
    setLoading(true);
    try {
        const { startCurr, endCurr, startPrev, endPrev } = getPeriods(reportMode, dateValue);

        const [resCurr, resPrev] = await Promise.all([
            axios.get(`${import.meta.env.VITE_API_URL}/api/reports/financial?startDate=${startCurr}&endDate=${endCurr}`),
            axios.get(`${import.meta.env.VITE_API_URL}/api/reports/financial?startDate=${startPrev}&endDate=${endPrev}`)
        ]);

        if (resCurr.data.success && resPrev.data.success) {
            setData({
                current: resCurr.data.data,
                previous: resPrev.data.data,
                periodInfo: { startCurr, endCurr }
            });
        }
    } catch (error) {
      console.error("Lỗi tải báo cáo:", error);
    } finally {
      setLoading(false);
    }
  };

  const formatMoney = (amount) => new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(amount || 0);

  // Tính % tăng trưởng
  const calcGrowth = (curr, prev) => {
      if (!prev || prev === 0) return curr > 0 ? '+100%' : '0%';
      const percent = ((curr - prev) / prev) * 100;
      return percent > 0 ? `+${percent.toFixed(1)}%` : `${percent.toFixed(1)}%`;
  };

  // Lấy nhãn so sánh hiển thị trên UI
  const getComparisonLabel = () => {
      if (reportMode === 'day') return 'vs Hôm qua';
      if (reportMode === 'week') return 'vs Tuần trước';
      return 'vs Tháng trước';
  };

  // Xuất Excel
  const handleExportExcel = async () => {
      if (!data) return;
      const XLSX = await import('xlsx');
      const exportData = [
          { "Chỉ tiêu": "Doanh thu", "Kỳ này": data.current.revenue, "Kỳ trước": data.previous.revenue, "Tăng trưởng": calcGrowth(data.current.revenue, data.previous.revenue) },
          { "Chỉ tiêu": "Giá vốn (COGS)", "Kỳ này": data.current.cogs, "Kỳ trước": data.previous.cogs, "Tăng trưởng": calcGrowth(data.current.cogs, data.previous.cogs) },
          { "Chỉ tiêu": "Chi phí vận hành", "Kỳ này": data.current.totalExpenses, "Kỳ trước": data.previous.totalExpenses, "Tăng trưởng": calcGrowth(data.current.totalExpenses, data.previous.totalExpenses) },
          { "Chỉ tiêu": "Lợi nhuận ròng", "Kỳ này": data.current.netProfit, "Kỳ trước": data.previous.netProfit, "Tăng trưởng": calcGrowth(data.current.netProfit, data.previous.netProfit) },
          { "Chỉ tiêu": "Số lượng đơn hàng", "Kỳ này": data.current.orderCount, "Kỳ trước": data.previous.orderCount, "Tăng trưởng": calcGrowth(data.current.orderCount, data.previous.orderCount) }
      ];

      const worksheet = XLSX.utils.json_to_sheet(exportData);
      const workbook = XLSX.utils.book_new();
      XLSX.utils.book_append_sheet(workbook, worksheet, "BaoCao");
      XLSX.writeFile(workbook, `BROWN_BaoCao_${reportMode}_${dateValue}.xlsx`);
  };

  // --- BIỂU ĐỒ CƠ CẤU CHI PHÍ ---
  const chartData = useMemo(() => {
    if (!data) return null;
    const current = data.current;
    const profitDisplay = current.netProfit > 0 ? current.netProfit : 0;
    return {
      labels: ['Giá vốn (COGS)', 'Chi phí vận hành', 'Lợi nhuận ròng'],
      datasets: [
        {
          label: 'Số tiền',
          data: [current.cogs, current.totalExpenses, profitDisplay],
          backgroundColor: ['#f59e0b', '#ef4444', '#10b981'],
          borderColor: ['#ffffff', '#ffffff', '#ffffff'],
          borderWidth: 2,
          hoverOffset: 4
        },
      ],
    };
  }, [data]);

  // --- BIỂU ĐỒ NGUỒN ĐƠN HÀNG ---
  const sourceChartData = useMemo(() => {
      if (!data || !data.current.revenueBySource) return null;
      
      const labels = Object.keys(data.current.revenueBySource);
      const values = Object.values(data.current.revenueBySource);
      
      const bgColors = ['#3b82f6', '#ec4899', '#f97316', '#6366f1', '#64748b', '#8b5cf6', '#14b8a6', '#f43f5e'];

      return {
          labels: labels,
          datasets: [{
              label: 'Doanh thu',
              data: values,
              backgroundColor: bgColors.slice(0, labels.length),
              borderWidth: 2,
              borderColor: '#ffffff'
          }]
      };
  }, [data]);

  const chartOptions = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: { position: 'bottom', labels: { padding: 20, font: { size: 11 } } },
      title: { display: true, text: 'Cơ cấu chi phí', font: { size: 14 } },
      tooltip: {
        callbacks: {
          label: function(context) {
            let label = context.label || '';
            if (label) { label += ': '; }
            if (context.parsed !== null) {
              label += new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(context.parsed);
              const total = context.chart._metasets[context.datasetIndex].total;
              const percentage = ((context.parsed / total) * 100).toFixed(1) + '%';
              label += ` (${percentage})`;
            }
            return label;
          }
        }
      }
    },
  };

  const sourceChartOptions = {
      ...chartOptions,
      plugins: {
          ...chartOptions.plugins,
          title: { display: true, text: 'Doanh thu theo Nguồn', font: { size: 14 } }
      }
  };

  if (!data && loading) return <div className="p-10 text-center mt-20 text-stone-500">Đang tổng hợp dữ liệu...</div>;

  return (
    <div className="p-6 md:p-10 max-w-7xl mx-auto min-h-screen">
      <div className="flex flex-col lg:flex-row justify-between items-start lg:items-center mb-8 gap-4">
        <div>
          <h1 className="text-2xl font-bold text-stone-800">Báo cáo Tài chính</h1>
          <p className="text-stone-500">Phân tích hiệu quả kinh doanh</p>
        </div>

        {/* CỤM CÔNG CỤ BỘ LỌC & EXCEL */}
        <div className="flex flex-wrap items-center gap-3">
            <div className="bg-white p-2 rounded-lg border border-stone-200 flex items-center gap-2 shadow-sm">
                <FaFilter className="text-stone-400 ml-2" size={14} />
                <select 
                    value={reportMode} 
                    onChange={handleModeChange}
                    className="p-1 outline-none text-sm font-bold text-stone-700 cursor-pointer bg-transparent border-r border-stone-200 pr-2"
                >
                    <option value="day">Theo Ngày</option>
                    <option value="week">Theo Tuần</option>
                    <option value="month">Theo Tháng</option>
                </select>
                
                <FaCalendarAlt className="text-stone-400 ml-2" size={14} />
                <input 
                    type={reportMode === 'month' ? 'month' : 'date'} 
                    value={dateValue}
                    onChange={e => setDateValue(e.target.value)}
                    className="p-1 outline-none text-sm font-medium text-stone-600 cursor-pointer"
                />
            </div>
            
            <button 
                onClick={handleExportExcel} 
                className="bg-green-600 text-white px-4 py-2.5 rounded-lg hover:bg-green-700 font-medium flex items-center gap-2 transition-colors shadow-sm text-sm"
            >
                <FaFileExcel/> Xuất Excel
            </button>
        </div>
      </div>

      {/* Hiển thị khoảng thời gian đang lọc */}
      {data && (
          <div className="mb-6 bg-stone-50 border border-stone-200 px-4 py-2 rounded-md inline-block text-sm text-stone-600">
              Đang xem dữ liệu từ: <strong className="text-stone-800">{data.periodInfo.startCurr.split('-').reverse().join('/')}</strong> đến <strong className="text-stone-800">{data.periodInfo.endCurr.split('-').reverse().join('/')}</strong>
          </div>
      )}

      {data && (
          <div className="grid grid-cols-1 lg:grid-cols-4 gap-8">
            {/* CỘT TRÁI: CÁC THẺ SỐ LIỆU */}
            <div className="lg:col-span-1 space-y-4">
                {/* 1. Tổng Doanh thu */}
                <div className="bg-white p-5 rounded-xl border border-blue-100 shadow-sm relative overflow-hidden">
                    <p className="text-xs font-bold text-blue-600 uppercase tracking-wider">Doanh thu</p>
                    <h3 className="text-2xl font-bold text-stone-800 mt-1">{formatMoney(data.current.revenue)}</h3>
                    <div className="flex items-center gap-2 mt-1">
                        <span className={`text-xs font-bold ${data.current.revenue >= data.previous.revenue ? 'text-green-500' : 'text-red-500'}`}>
                            {calcGrowth(data.current.revenue, data.previous.revenue)}
                        </span>
                        <span className="text-xs text-stone-400">{getComparisonLabel()}</span>
                    </div>
                </div>

                {/* 2. Giá vốn */}
                <div className="bg-white p-5 rounded-xl border border-orange-100 shadow-sm">
                    <p className="text-xs font-bold text-orange-500 uppercase">(-) Giá vốn hàng bán</p>
                    <h3 className="text-xl font-bold text-stone-800 mt-1">{formatMoney(data.current.cogs)}</h3>
                    <div className="flex items-center gap-2 mt-1 text-xs">
                        <span className={`font-bold ${data.current.cogs <= data.previous.cogs ? 'text-green-500' : 'text-red-500'}`}>
                            {calcGrowth(data.current.cogs, data.previous.cogs)}
                        </span>
                        <span className="text-stone-400">{getComparisonLabel()}</span>
                    </div>
                </div>

                {/* 3. Chi phí */}
                <div className="bg-white p-5 rounded-xl border border-red-100 shadow-sm">
                    <p className="text-xs font-bold text-red-500 uppercase">(-) Chi phí vận hành</p>
                    <h3 className="text-xl font-bold text-stone-800 mt-1">{formatMoney(data.current.totalExpenses)}</h3>
                    <div className="flex items-center gap-2 mt-1 text-xs">
                        <span className={`font-bold ${data.current.totalExpenses <= data.previous.totalExpenses ? 'text-green-500' : 'text-red-500'}`}>
                            {calcGrowth(data.current.totalExpenses, data.previous.totalExpenses)}
                        </span>
                        <span className="text-stone-400">{getComparisonLabel()}</span>
                    </div>
                </div>

                {/* 4. Lợi nhuận Ròng */}
                <div className={`p-5 rounded-xl border shadow-sm ${data.current.netProfit >= 0 ? 'bg-green-50 border-green-200' : 'bg-red-50 border-red-200'}`}>
                    <p className={`text-xs font-bold uppercase ${data.current.netProfit >= 0 ? 'text-green-600' : 'text-red-600'}`}>
                        {data.current.netProfit >= 0 ? '(=) Lợi nhuận ròng' : '(=) Thua lỗ'}
                    </p>
                    <h3 className={`text-2xl font-bold mt-1 ${data.current.netProfit >= 0 ? 'text-green-700' : 'text-red-700'}`}>
                        {formatMoney(data.current.netProfit)}
                    </h3>
                    <div className="flex items-center justify-between mt-1">
                        <span className={`text-xs font-bold ${data.current.netProfit >= data.previous.netProfit ? 'text-green-600' : 'text-red-500'}`}>
                            {calcGrowth(data.current.netProfit, data.previous.netProfit)} {getComparisonLabel()}
                        </span>
                        <span className="text-xs font-bold text-stone-500">
                            Biên LN: {data.current.margin}%
                        </span>
                    </div>
                </div>
            </div>

            {/* CỘT PHẢI: BIỂU ĐỒ (Chiếm 3 cột) */}
            <div className="lg:col-span-3 grid grid-cols-1 md:grid-cols-2 gap-6">
                
                {/* BIỂU ĐỒ 1: CƠ CẤU CHI PHÍ */}
                <div className="bg-white p-6 rounded-xl border border-stone-200 shadow-sm flex flex-col h-[400px]">
                    {data.current.revenue === 0 ? (
                        <div className="flex-1 flex items-center justify-center text-stone-400 flex-col">
                            <span className="text-4xl mb-2">∅</span>
                            <p>Không có dữ liệu trong khoảng thời gian này</p>
                        </div>
                    ) : (
                        <Doughnut data={chartData} options={chartOptions} />
                    )}
                </div>

                {/* BIỂU ĐỒ 2: NGUỒN ĐƠN HÀNG */}
                <div className="bg-white p-6 rounded-xl border border-stone-200 shadow-sm flex flex-col h-[400px]">
                    {data.current.revenue === 0 ? (
                        <div className="flex-1 flex items-center justify-center text-stone-400 flex-col">
                            <span className="text-4xl mb-2">∅</span>
                            <p>Không có dữ liệu trong khoảng thời gian này</p>
                        </div>
                    ) : (
                        <Doughnut data={sourceChartData} options={sourceChartOptions} />
                    )}
                </div>

                {/* Chú thích */}
                <div className="md:col-span-2 mt-2 p-4 bg-stone-50 rounded-lg text-xs text-stone-500 leading-relaxed border border-stone-100">
                    <h4 className="font-bold text-stone-700 mb-1">Ghi chú báo cáo:</h4>
                    <ul className="list-disc pl-4 space-y-1">
                        <li><strong>Chế độ so sánh:</strong> Hệ thống tự động đối chiếu số liệu với thời gian tương đương của kỳ trước (Hôm qua / Tuần trước / Tháng trước).</li>
                        <li><strong>Báo cáo tuần:</strong> Tuần được tính từ Thứ Hai đến Chủ Nhật. Chọn một ngày bất kỳ, hệ thống sẽ tự quét cả tuần chứa ngày đó.</li>
                        <li>Màu <span className="text-green-500 font-bold">Xanh</span> báo hiệu hiệu suất tốt (Tăng doanh thu / Giảm chi phí). Màu <span className="text-red-500 font-bold">Đỏ</span> ngược lại.</li>
                    </ul>
                </div>
            </div>
          </div>
      )}

      {/* BẢNG XẾP HẠNG SẢN PHẨM BÁN CHẠY */}
      <div className="mt-10 bg-white rounded-xl border border-stone-200 shadow-sm overflow-hidden">
          <div className="p-5 border-b border-stone-100 flex flex-col md:flex-row md:items-center justify-between gap-4">
              <div>
                  <h2 className="text-lg font-bold text-stone-800">Bảng xếp hạng sản phẩm</h2>
                  <p className="text-sm text-stone-500">Số lượng bán, doanh thu, giá vốn & lợi nhuận theo từng sản phẩm</p>
              </div>
              <div className="flex flex-wrap items-center gap-2">
                  {[['week', 'Tuần này'], ['month', 'Tháng này'], ['quarter', 'Quý này'], ['custom', 'Tùy chọn']].map(([val, label]) => (
                      <button
                          key={val}
                          onClick={() => setProductPreset(val)}
                          className={`px-3 py-1.5 rounded-full text-xs font-bold border transition-colors ${productPreset === val ? 'bg-stone-900 text-white border-stone-900' : 'bg-white text-stone-600 border-stone-200 hover:border-stone-400'}`}
                      >
                          {label}
                      </button>
                  ))}
                  {productPreset === 'custom' && (
                      <div className="flex items-center gap-1 ml-1">
                          <input type="date" value={productCustomStart} onChange={e => setProductCustomStart(e.target.value)} className="border border-stone-200 rounded px-2 py-1.5 text-xs" />
                          <span className="text-stone-400 text-xs">-</span>
                          <input type="date" value={productCustomEnd} onChange={e => setProductCustomEnd(e.target.value)} className="border border-stone-200 rounded px-2 py-1.5 text-xs" />
                      </div>
                  )}
              </div>
          </div>

          <div className="overflow-x-auto">
              <table className="w-full text-sm">
                  <thead>
                      <tr className="text-left text-stone-500 border-b border-stone-100 bg-stone-50">
                          <th className="p-4 font-bold">Sản phẩm</th>
                          <th className="p-4 font-bold cursor-pointer select-none" onClick={() => handleSortProduct('quantity')}>
                              <span className="flex items-center justify-end gap-1.5">SL bán <SortIcon column="quantity" /></span>
                          </th>
                          <th className="p-4 font-bold cursor-pointer select-none" onClick={() => handleSortProduct('revenue')}>
                              <span className="flex items-center justify-end gap-1.5">Doanh thu <SortIcon column="revenue" /></span>
                          </th>
                          <th className="p-4 font-bold cursor-pointer select-none" onClick={() => handleSortProduct('cogs')}>
                              <span className="flex items-center justify-end gap-1.5">Giá vốn <SortIcon column="cogs" /></span>
                          </th>
                          <th className="p-4 font-bold cursor-pointer select-none" onClick={() => handleSortProduct('profit')}>
                              <span className="flex items-center justify-end gap-1.5">Lợi nhuận <SortIcon column="profit" /></span>
                          </th>
                      </tr>
                  </thead>
                  <tbody>
                      {sortedProductSales.map(p => (
                          <tr key={p.product_id} className="border-b border-stone-50 hover:bg-stone-50 transition-colors">
                              <td className="p-4">
                                  <div className="flex items-center gap-3">
                                      {p.image ? (
                                          <img src={optimizeImage(p.image, 80)} alt="" className="w-10 h-10 rounded object-cover border border-stone-200 shrink-0" loading="lazy" />
                                      ) : (
                                          <div className="w-10 h-10 rounded bg-stone-100 border border-stone-200 shrink-0" />
                                      )}
                                      <div>
                                        <span className="font-medium text-stone-700">{p.name}</span>
                                        {p.is_revenue_adjustment && <span className="ml-2 text-[10px] font-bold uppercase tracking-wide text-blue-600">Khoản thu điều chỉnh</span>}
                                      </div>
                                  </div>
                              </td>
                              <td className="p-4 text-right text-stone-600">{p.quantity}</td>
                              <td className="p-4 text-right text-stone-700 font-medium">{formatMoney(p.revenue)}</td>
                              <td className="p-4 text-right text-stone-500">{formatMoney(p.cogs)}</td>
                              <td className={`p-4 text-right font-bold ${p.profit >= 0 ? 'text-green-600' : 'text-red-500'}`}>{formatMoney(p.profit)}</td>
                          </tr>
                      ))}
                  </tbody>
              </table>

              {productSalesLoading && (
                  <div className="p-10 text-center text-stone-400">Đang tải dữ liệu...</div>
              )}
              {!productSalesLoading && sortedProductSales.length === 0 && (
                  <div className="p-10 text-center text-stone-400">Không có sản phẩm nào được bán trong khoảng thời gian này.</div>
              )}
          </div>
      </div>
    </div>
  );
};

export default Reports;
