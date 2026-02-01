import { useState, useEffect } from 'react';
import { useAuth } from '../context/AuthContext';
import axios from 'axios';
import { useNavigate } from 'react-router-dom';
import { ORDER_STATUS_MAP } from '../utils/translations';

const Profile = () => {
  const { user, logout, getToken } = useAuth();
  const navigate = useNavigate();
  const [formData, setFormData] = useState({ full_name: '', phone: '', address: '' });
  const [msg, setMsg] = useState('');

  // Auto-fill form khi có dữ liệu user
  useEffect(() => {
    if (user) {
      setFormData({
        full_name: user.full_name || '',
        phone: user.phone || '',
        address: user.address || ''
      });
    } else {
      navigate('/login');
    }
  }, [user, navigate]);

  const handleUpdate = async (e) => {
    e.preventDefault();
    try {
      const token = getToken();
      await axios.put(`${import.meta.env.VITE_API_URL}/api/customers/me/profile`, formData, {
        headers: { Authorization: `Bearer ${token}` }
      });
      setMsg('✅ Cập nhật thành công!');
    } catch (error) {
      alert('Lỗi cập nhật');
    }
  };

  const handleLogout = async () => {
      await logout();
      navigate('/');
  };

  if (!user) return null;

  return (
    <div className="max-w-6xl mx-auto px-6 py-12">
      <div className="flex justify-between items-center mb-8">
        <h1 className="text-3xl font-serif text-stone-900">Tài khoản của tôi</h1>
        <button onClick={handleLogout} className="text-red-500 underline text-sm">Đăng xuất</button>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-12">
        {/* CỘT 1: THÔNG TIN CÁ NHÂN */}
        <div className="bg-white p-6 rounded shadow-sm h-fit">
          <h2 className="font-bold text-lg mb-4 text-stone-800">Thông tin cá nhân</h2>
          {msg && <p className="text-green-600 text-sm mb-2">{msg}</p>}
          <form onSubmit={handleUpdate} className="space-y-4">
            <div>
                <label className="text-xs text-stone-500 uppercase">Họ tên</label>
                <input value={formData.full_name} onChange={e=>setFormData({...formData, full_name: e.target.value})} className="w-full p-2 border rounded mt-1" />
            </div>
            <div>
                <label className="text-xs text-stone-500 uppercase">Số điện thoại</label>
                <input value={formData.phone} onChange={e=>setFormData({...formData, phone: e.target.value})} className="w-full p-2 border rounded mt-1" />
            </div>
            <div>
                <label className="text-xs text-stone-500 uppercase">Địa chỉ mặc định</label>
                <input value={formData.address} onChange={e=>setFormData({...formData, address: e.target.value})} className="w-full p-2 border rounded mt-1" />
            </div>
            <button className="bg-stone-900 text-white w-full py-2 text-sm font-bold uppercase hover:bg-stone-700">Lưu thay đổi</button>
          </form>
        </div>

        {/* CỘT 2: LỊCH SỬ ĐƠN HÀNG */}
        <div className="md:col-span-2">
          <h2 className="font-bold text-lg mb-4 text-stone-800">Lịch sử đơn hàng</h2>
          {user.history && user.history.length > 0 ? (
            <div className="space-y-4">
              {user.history.map(order => (
                <div key={order.id} className="border border-stone-200 p-4 rounded bg-stone-50 flex justify-between items-center">
                    <div>
                        <p className="font-bold text-stone-900">{order.code}</p>
                        <p className="text-sm text-stone-500">{new Date(order.created_at).toLocaleDateString('vi-VN')}</p>
                        <p className="text-sm mt-1">Tổng tiền: <span className="font-medium text-stone-900">{new Intl.NumberFormat('vi-VN').format(order.total_amount)} đ</span></p>
                    </div>
                    <div className="text-right">
                        <span className={`px-3 py-1 text-xs font-bold rounded-full uppercase 
                            ${order.status === 'completed' ? 'bg-green-100 text-green-700' : 
                              order.status === 'cancelled' ? 'bg-red-100 text-red-700' : 'bg-yellow-100 text-yellow-700'}`}>
                            {ORDER_STATUS_MAP[order.status]?.label || order.status}
                        </span>
                        {order.shipping_tracking_code && (
                            <p className="text-xs text-stone-500 mt-2">Vận đơn: {order.shipping_tracking_code}</p>
                        )}
                    </div>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-stone-500 italic">Bạn chưa có đơn hàng nào.</p>
          )}
        </div>
      </div>
    </div>
  );
};

export default Profile;