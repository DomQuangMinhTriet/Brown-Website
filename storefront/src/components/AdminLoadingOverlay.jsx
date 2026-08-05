import { useEffect, useRef, useState } from 'react';
import axios from 'axios';
import { FaSpinner } from 'react-icons/fa';

const messageForRequest = (config = {}) => {
  const method = String(config.method || 'get').toLowerCase();
  const url = String(config.url || '');

  if (url.includes('/upload')) return 'Đang tải tệp lên…';
  if (method === 'delete') return 'Đang xóa dữ liệu…';
  if (method === 'put' || method === 'patch') return 'Đang lưu thay đổi…';
  if (method === 'post') return 'Đang xử lý dữ liệu…';
  return 'Đang tải dữ liệu…';
};

// Chỉ được render trong AdminLayoutWrapper. Axios interceptors được tháo khi rời
// khu vực quản trị, nên storefront của khách hàng không bị ảnh hưởng.
const AdminLoadingOverlay = () => {
  const pendingRequests = useRef(0);
  const [isLoading, setIsLoading] = useState(false);
  const [message, setMessage] = useState('Đang xử lý…');

  useEffect(() => {
    const start = (config) => {
      pendingRequests.current += 1;
      setMessage(messageForRequest(config));
      setIsLoading(true);
      return config;
    };

    const finish = () => {
      pendingRequests.current = Math.max(0, pendingRequests.current - 1);
      if (pendingRequests.current === 0) setIsLoading(false);
    };

    const requestInterceptor = axios.interceptors.request.use(start, (error) => {
      finish();
      return Promise.reject(error);
    });
    const responseInterceptor = axios.interceptors.response.use((response) => {
      finish();
      return response;
    }, (error) => {
      finish();
      return Promise.reject(error);
    });

    return () => {
      axios.interceptors.request.eject(requestInterceptor);
      axios.interceptors.response.eject(responseInterceptor);
    };
  }, []);

  if (!isLoading) return null;

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center bg-stone-950/35 p-4 backdrop-blur-[1px]" role="status" aria-live="polite" aria-label={message}>
      <div className="flex min-w-52 items-center gap-3 rounded-xl bg-white px-5 py-4 text-sm font-semibold text-stone-700 shadow-2xl">
        <FaSpinner className="animate-spin text-stone-900" aria-hidden="true" />
        <span>{message}</span>
      </div>
    </div>
  );
};

export default AdminLoadingOverlay;
