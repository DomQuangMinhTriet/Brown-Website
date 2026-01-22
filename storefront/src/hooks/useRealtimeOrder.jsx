import { useEffect } from 'react';
import { supabase } from '../context/AdminAuthContext'; // Import client admin
import { toast } from 'react-toastify';
import 'react-toastify/dist/ReactToastify.css';

// Hook này sẽ được gọi ở App.jsx để lắng nghe toàn cục
const useRealtimeOrder = () => {
  useEffect(() => {
    // 1. Tạo kênh lắng nghe bảng 'orders'
    const channel = supabase
      .channel('realtime-orders') // Tên kênh bất kỳ
      .on(
        'postgres_changes',
        {
          event: 'INSERT', // Chỉ nghe khi có đơn mới (INSERT)
          schema: 'public',
          table: 'orders',
        },
        (payload) => {
          // --- KHI CÓ ĐƠN HÀNG MỚI ---
          console.log('🔔 Có đơn hàng mới:', payload.new);

          // 1. Phát âm thanh
          try {
            const audio = new Audio('/sounds/notification.mp3'); // Đảm bảo file này tồn tại trong public/sounds/
            audio.play().catch(err => console.log('Chưa tương tác user nên browser chặn auto-play'));
          } catch (e) {
            console.error("Lỗi phát âm thanh", e);
          }

          // 2. Hiện thông báo Popup đẹp mắt
          toast.success(
            <div onClick={() => window.location.href = '/admin/orders'} className="cursor-pointer">
              <p className="font-bold">🎉 Đơn hàng mới: {payload.new.code}</p>
              <span className="text-xs text-blue-500">Bấm để xem ngay</span>
            </div>, 
            {
              position: "top-right",
              autoClose: 5000,
              hideProgressBar: false,
              closeOnClick: true,
              pauseOnHover: true,
              draggable: true,
            }
          );
        }
      )
      .subscribe();

    // Cleanup khi unmount (để tránh nghe 2 lần)
    return () => {
      supabase.removeChannel(channel);
    };
  }, []);
};

export default useRealtimeOrder;