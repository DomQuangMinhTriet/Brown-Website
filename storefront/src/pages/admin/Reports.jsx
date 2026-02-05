import { useEffect, useState, useMemo } from 'react';
import axios from 'axios';
import { 
  Chart as ChartJS, 
  ArcElement, 
  Tooltip, 
  Legend, 
  Title 
} from 'chart.js';
import { Doughnut } from 'react-chartjs-2'; // Dùng Doughnut nhìn hiện đại hơn Pie
import { FaCalendarAlt, FaSearch } from 'react-icons/fa';

// Đăng ký các thành phần biểu đồ
ChartJS.register(ArcElement, Tooltip, Legend, Title);

const Reports = () => {
  // Hàm helper format ngày YYYY-MM-DD
  const formatDate = (date) => date.toISOString().split('T')[0];

  // [SỬA LẠI] Logic ngày tháng: Mặc định 7 ngày gần nhất tính đến hôm nay
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

  // --- CẤU HÌNH BIỂU ĐỒ TRÒN ---
  const chartData = useMemo(() => {
    if (!data) return null;

    // Logic: Nếu Lỗ (Profit < 0), thì biểu đồ tròn sẽ không hiển thị được miếng "Lợi nhuận"
    // Lúc này ta chỉ hiển thị Giá vốn và Chi phí (có thể vượt quá 100% doanh thu)
    const profitDisplay = data.netProfit > 0 ? data.netProfit : 0;

    return {
      labels: ['Giá vốn hàng bán (COGS)', 'Chi phí vận hành', 'Lợi nhuận giữ lại'],
      datasets: [
        {
          label: 'Số tiền',
          data: [data.cogs, data.totalExpenses, profitDisplay],
          backgroundColor: [
            '#f59e0b', // Cam (Giá vốn)
            '#ef4444', // Đỏ (Chi phí)
            '#10b981', // Xanh lá (Lợi nhuận)
          ],
          borderColor: ['#ffffff', '#ffffff', '#ffffff'],
          borderWidth: 2,
          hoverOffset: 4
        },
      ],
    };
  }, [data]);

  const chartOptions = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        position: 'bottom',
        labels: {
          padding: 20,
          font: { size: 12 }
        }
      },
      title: {
        display: true,
        text: 'Cơ cấu phân bổ Doanh thu',
        font: { size: 16 }
      },
      tooltip: {
        callbacks: {
          label: function(context) {
            let label = context.label || '';
            if (label) {
              label += ': ';
            }
            if (context.parsed !== null) {
              label += new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(context.parsed);
              
              // Tính phần trăm
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

  if (!data) return <div className="p-10 text-center">Đang tải dữ liệu...</div>;

  return (
    <div className="p-6 md:p-10 max-w-7xl mx-auto min-h-screen">
      <div className="flex flex-col md:flex-row justify-between items-start md:items-center mb-8 gap-4">
        <div>
          <h1 className="text-2xl font-bold text-stone-800">Báo cáo Tài chính</h1>
          <p className="text-stone-500">Phân tích biên lợi nhuận & Cấu trúc chi phí</p>
        </div>

        {/* Bộ lọc ngày */}
        <div className="bg-white p-2 rounded-lg border border-stone-200 flex items-center gap-2 shadow-sm">
            <FaCalendarAlt className="text-stone-400 ml-2"/>
            <input 
                type="date" 
                value={dateRange.start}
                onChange={e => setDateRange({...dateRange, start: e.target.value})}
                className="p-1 outline-none text-sm font-medium text-stone-600"
            />
            <span className="text-stone-400">-</span>
            <input 
                type="date" 
                value={dateRange.end}
                onChange={e => setDateRange({...dateRange, end: e.target.value})}
                className="p-1 outline-none text-sm font-medium text-stone-600"
            />
            <button onClick={fetchReport} className="bg-stone-800 text-white p-2 rounded hover:bg-stone-700">
                <FaSearch/>
            </button>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        
        {/* CỘT TRÁI: CÁC THẺ SỐ LIỆU */}
        <div className="lg:col-span-1 space-y-6">
            {/* 1. Tổng Doanh thu */}
            <div className="bg-white p-6 rounded-xl border border-blue-100 shadow-sm relative overflow-hidden">
                <div className="absolute right-0 top-0 w-20 h-20 bg-blue-50 rounded-bl-full -mr-4 -mt-4"></div>
                <p className="text-xs font-bold text-blue-600 uppercase tracking-wider z-10 relative">Tổng Doanh thu (100%)</p>
                <h3 className="text-3xl font-bold text-stone-800 mt-2 z-10 relative">{formatMoney(data.revenue)}</h3>
                <p className="text-xs text-stone-400 mt-2 z-10 relative">{data.orderCount} đơn hàng (Hoàn thành và Đang vận chuyển)</p>
            </div>

            {/* 2. Giá vốn */}
            <div className="bg-white p-6 rounded-xl border border-orange-100 shadow-sm flex justify-between items-center">
                <div>
                    <p className="text-xs font-bold text-orange-500 uppercase">(-) Giá vốn hàng bán</p>
                    <h3 className="text-xl font-bold text-stone-800 mt-1">{formatMoney(data.cogs)}</h3>
                </div>
                <span className="text-lg font-bold text-orange-400">
                    {data.revenue > 0 ? ((data.cogs / data.revenue) * 100).toFixed(0) : 0}%
                </span>
            </div>

            {/* 3. Chi phí */}
            <div className="bg-white p-6 rounded-xl border border-red-100 shadow-sm flex justify-between items-center">
                <div>
                    <p className="text-xs font-bold text-red-500 uppercase">(-) Chi phí vận hành</p>
                    <h3 className="text-xl font-bold text-stone-800 mt-1">{formatMoney(data.totalExpenses)}</h3>
                </div>
                <span className="text-lg font-bold text-red-400">
                    {data.revenue > 0 ? ((data.totalExpenses / data.revenue) * 100).toFixed(0) : 0}%
                </span>
            </div>

            {/* 4. Lợi nhuận Ròng */}
            <div className={`p-6 rounded-xl border shadow-sm ${data.netProfit >= 0 ? 'bg-green-50 border-green-200' : 'bg-red-50 border-red-200'}`}>
                <p className={`text-xs font-bold uppercase ${data.netProfit >= 0 ? 'text-green-600' : 'text-red-600'}`}>
                    {data.netProfit >= 0 ? '(=) Lợi nhuận ròng' : '(=) Thua lỗ'}
                </p>
                <h3 className={`text-3xl font-bold mt-2 ${data.netProfit >= 0 ? 'text-green-700' : 'text-red-700'}`}>
                    {formatMoney(data.netProfit)}
                </h3>
                <div className="mt-2 w-full bg-white/50 h-2 rounded-full overflow-hidden">
                     <div 
                        className={`h-full ${data.netProfit >= 0 ? 'bg-green-500' : 'bg-red-500'}`} 
                        style={{ width: `${Math.abs(data.margin)}%` }}
                     ></div>
                </div>
                <p className={`text-xs font-bold mt-2 text-right ${data.netProfit >= 0 ? 'text-green-600' : 'text-red-500'}`}>
                    Margin: {data.margin}%
                </p>
            </div>
        </div>

        {/* CỘT PHẢI: BIỂU ĐỒ TRÒN */}
        <div className="lg:col-span-2 bg-white p-6 rounded-xl border border-stone-200 shadow-sm flex flex-col">
            <div className="flex-1 min-h-[400px] relative">
                {data.revenue === 0 ? (
                    <div className="absolute inset-0 flex items-center justify-center text-stone-400 flex-col">
                        <span className="text-4xl mb-2">∅</span>
                        <p>Chưa có doanh thu trong kỳ này</p>
                    </div>
                ) : (
                    <Doughnut data={chartData} options={chartOptions} />
                )}
            </div>
            
            {/* Chú thích thêm */}
            <div className="mt-6 p-4 bg-stone-50 rounded-lg text-xs text-stone-500 leading-relaxed border border-stone-100">
                <h4 className="font-bold text-stone-700 mb-1">Cách đọc biểu đồ:</h4>
                <ul className="list-disc pl-4 space-y-1">
                    <li>Vòng tròn này đại diện cho <strong>100% Doanh thu</strong> bạn kiếm được.</li>
                    <li>Màu <span className="text-orange-500 font-bold">Cam</span> là tiền bạn phải trả cho nhà cung cấp (Giá vốn).</li>
                    <li>Màu <span className="text-red-500 font-bold">Đỏ</span> là tiền bạn trả cho mặt bằng, điện nước, nhân sự...</li>
                    <li>Màu <span className="text-green-500 font-bold">Xanh</span> là phần tiền thực sự bỏ túi (Lợi nhuận).</li>
                    {data.netProfit < 0 && (
                         <li className="text-red-600 font-bold">LƯU Ý: Hiện tại bạn đang lỗ, nên miếng bánh màu xanh (Lợi nhuận) không xuất hiện. Chi phí đang nuốt trọn doanh thu!</li>
                    )}
                </ul>
            </div>
        </div>

      </div>
    </div>
  );
};

export default Reports;