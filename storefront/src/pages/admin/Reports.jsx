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
import { FaCalendarAlt, FaSearch } from 'react-icons/fa';

// Đăng ký các thành phần biểu đồ
ChartJS.register(ArcElement, Tooltip, Legend, Title);

const Reports = () => {
  // Hàm helper format ngày YYYY-MM-DD
  const formatDate = (date) => date.toISOString().split('T')[0];

  // Logic ngày tháng: Mặc định 7 ngày gần nhất tính đến hôm nay
  const [dateRange, setDateRange] = useState(() => {
      const end = new Date(); // Hôm nay
      const start = new Date(); 
      start.setDate(end.getDate() - 7); // Lùi lại 7 ngày

      return {
          start: formatDate(start),
          end: formatDate(end)
      };
  });

  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchReport();
  }, [dateRange]);

  const fetchReport = async () => {
    setLoading(true);
    try {
      const res = await axios.get(`${import.meta.env.VITE_API_URL}/api/reports/financial?startDate=${dateRange.start}&endDate=${dateRange.end}`);
      if (res.data.success) {
        setData(res.data.data);
      }
    } catch (error) {
      console.error("Lỗi tải báo cáo:", error);
    } finally {
      setLoading(false);
    }
  };

  const formatMoney = (amount) => new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(amount);

  // --- 1. BIỂU ĐỒ CƠ CẤU CHI PHÍ ---
  const chartData = useMemo(() => {
    if (!data) return null;
    const profitDisplay = data.netProfit > 0 ? data.netProfit : 0;
    return {
      labels: ['Giá vốn (COGS)', 'Chi phí vận hành', 'Lợi nhuận ròng'],
      datasets: [
        {
          label: 'Số tiền',
          data: [data.cogs, data.totalExpenses, profitDisplay],
          backgroundColor: [
            '#f59e0b', // Cam
            '#ef4444', // Đỏ
            '#10b981', // Xanh
          ],
          borderColor: ['#ffffff', '#ffffff', '#ffffff'],
          borderWidth: 2,
          hoverOffset: 4
        },
      ],
    };
  }, [data]);

  // --- 2. [MỚI] BIỂU ĐỒ NGUỒN ĐƠN HÀNG ---
  const sourceChartData = useMemo(() => {
      if (!data || !data.revenueBySource) return null;
      
      const labels = Object.keys(data.revenueBySource);
      const values = Object.values(data.revenueBySource);
      
      // Bảng màu cho các nguồn
      const bgColors = [
          '#3b82f6', // Web (Xanh dương)
          '#ec4899', // Instagram/Tiktok (Hồng)
          '#f97316', // Shopee (Cam)
          '#6366f1', // Facebook (Tím)
          '#64748b', // Tại quầy (Xám)
          '#8b5cf6', '#14b8a6', '#f43f5e' // Các màu khác
      ];

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

  // Option riêng cho biểu đồ nguồn (chỉ đổi title)
  const sourceChartOptions = {
      ...chartOptions,
      plugins: {
          ...chartOptions.plugins,
          title: { display: true, text: 'Doanh thu theo Nguồn', font: { size: 14 } }
      }
  };

  if (!data) return <div className="p-10 text-center">Đang tải dữ liệu...</div>;

  return (
    <div className="p-6 md:p-10 max-w-7xl mx-auto min-h-screen">
      <div className="flex flex-col md:flex-row justify-between items-start md:items-center mb-8 gap-4">
        <div>
          <h1 className="text-2xl font-bold text-stone-800">Báo cáo Tài chính</h1>
          <p className="text-stone-500">Phân tích hiệu quả kinh doanh</p>
        </div>

        {/* Bộ lọc ngày */}
        <div className="bg-white p-2 rounded-lg border border-stone-200 flex items-center gap-2 shadow-sm">
            <FaCalendarAlt className="text-stone-400 ml-2"/>
            <input 
                type="date" 
                value={dateRange.start}
                onChange={e => setDateRange({...dateRange, start: e.target.value})}
                className="p-1 outline-none text-sm font-medium text-stone-600 cursor-pointer"
            />
            <span className="text-stone-400">-</span>
            <input 
                type="date" 
                value={dateRange.end}
                onChange={e => setDateRange({...dateRange, end: e.target.value})}
                className="p-1 outline-none text-sm font-medium text-stone-600 cursor-pointer"
            />
            <button onClick={fetchReport} className="bg-stone-800 text-white p-2 rounded hover:bg-stone-700">
                <FaSearch/>
            </button>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-4 gap-8">
        
        {/* CỘT TRÁI: CÁC THẺ SỐ LIỆU (Chiếm 1 cột) */}
        <div className="lg:col-span-1 space-y-4">
            {/* 1. Tổng Doanh thu */}
            <div className="bg-white p-5 rounded-xl border border-blue-100 shadow-sm relative overflow-hidden">
                <p className="text-xs font-bold text-blue-600 uppercase tracking-wider">Doanh thu</p>
                <h3 className="text-2xl font-bold text-stone-800 mt-1">{formatMoney(data.revenue)}</h3>
                <p className="text-xs text-stone-400 mt-1">{data.orderCount} đơn (Đã/Đang giao)</p>
            </div>

            {/* 2. Giá vốn */}
            <div className="bg-white p-5 rounded-xl border border-orange-100 shadow-sm">
                <p className="text-xs font-bold text-orange-500 uppercase">(-) Giá vốn hàng bán</p>
                <h3 className="text-xl font-bold text-stone-800 mt-1">{formatMoney(data.cogs)}</h3>
                <span className="text-xs font-bold text-orange-400">
                    {data.revenue > 0 ? ((data.cogs / data.revenue) * 100).toFixed(0) : 0}% doanh thu
                </span>
            </div>

            {/* 3. Chi phí */}
            <div className="bg-white p-5 rounded-xl border border-red-100 shadow-sm">
                <p className="text-xs font-bold text-red-500 uppercase">(-) Chi phí vận hành</p>
                <h3 className="text-xl font-bold text-stone-800 mt-1">{formatMoney(data.totalExpenses)}</h3>
            </div>

            {/* 4. Lợi nhuận Ròng */}
            <div className={`p-5 rounded-xl border shadow-sm ${data.netProfit >= 0 ? 'bg-green-50 border-green-200' : 'bg-red-50 border-red-200'}`}>
                <p className={`text-xs font-bold uppercase ${data.netProfit >= 0 ? 'text-green-600' : 'text-red-600'}`}>
                    {data.netProfit >= 0 ? '(=) Lợi nhuận ròng' : '(=) Thua lỗ'}
                </p>
                <h3 className={`text-2xl font-bold mt-1 ${data.netProfit >= 0 ? 'text-green-700' : 'text-red-700'}`}>
                    {formatMoney(data.netProfit)}
                </h3>
                <p className={`text-xs font-bold mt-1 ${data.netProfit >= 0 ? 'text-green-600' : 'text-red-500'}`}>
                    Margin: {data.margin}%
                </p>
            </div>
        </div>

        {/* CỘT PHẢI: BIỂU ĐỒ (Chiếm 3 cột) */}
        <div className="lg:col-span-3 grid grid-cols-1 md:grid-cols-2 gap-6">
            
            {/* BIỂU ĐỒ 1: CƠ CẤU CHI PHÍ */}
            <div className="bg-white p-6 rounded-xl border border-stone-200 shadow-sm flex flex-col h-[400px]">
                {data.revenue === 0 ? (
                    <div className="flex-1 flex items-center justify-center text-stone-400 flex-col">
                        <span className="text-4xl mb-2">∅</span>
                        <p>Chưa có dữ liệu</p>
                    </div>
                ) : (
                    <Doughnut data={chartData} options={chartOptions} />
                )}
            </div>

            {/* BIỂU ĐỒ 2: NGUỒN ĐƠN HÀNG [MỚI] */}
            <div className="bg-white p-6 rounded-xl border border-stone-200 shadow-sm flex flex-col h-[400px]">
                {data.revenue === 0 ? (
                    <div className="flex-1 flex items-center justify-center text-stone-400 flex-col">
                        <span className="text-4xl mb-2">∅</span>
                        <p>Chưa có dữ liệu</p>
                    </div>
                ) : (
                    <Doughnut data={sourceChartData} options={sourceChartOptions} />
                )}
            </div>

            {/* Chú thích */}
            <div className="md:col-span-2 mt-2 p-4 bg-stone-50 rounded-lg text-xs text-stone-500 leading-relaxed border border-stone-100">
                <h4 className="font-bold text-stone-700 mb-1">Ghi chú báo cáo:</h4>
                <ul className="list-disc pl-4 space-y-1">
                    <li>Dữ liệu bao gồm các đơn hàng <strong>Đã hoàn thành</strong> và <strong>Đang giao hàng</strong>.</li>
                    <li><strong>Nguồn Website:</strong> Các đơn có mã bắt đầu bằng "ORD-".</li>
                    <li><strong>Các nguồn khác (Shopee, IG...):</strong> Được nhận diện tự động qua Ghi chú đơn hàng.</li>
                </ul>
            </div>
        </div>

      </div>
    </div>
  );
};

export default Reports;