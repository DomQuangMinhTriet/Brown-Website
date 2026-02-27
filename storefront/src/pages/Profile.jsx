import { useState, useEffect } from 'react';
import { useAuth } from '../context/AuthContext';
import axios from 'axios';
import { useNavigate } from 'react-router-dom';
import { ORDER_STATUS_MAP } from '../utils/translations';
import { useLanguage } from '../context/LanguageContext';

const Profile = () => {
  const { user, logout, getToken } = useAuth();
  const navigate = useNavigate();
  const { t, lang } = useLanguage();
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
      setMsg(t('profile.toast_update_success'));
    } catch (error) {
      alert(t('profile.toast_update_error'));
    }
  };

  const handleLogout = async () => {
      await logout();
      navigate('/');
  };

  if (!user) return <div className="text-center py-20">Đang tải...</div>;

  return (
    <div className="max-w-5xl mx-auto px-6 py-12 min-h-[60vh]">
      <div className="flex justify-between items-end mb-8 border-b border-stone-200 pb-4">
        <h1 className="text-3xl font-serif text-stone-900">{t('profile.title')}</h1>
        <button onClick={handleLogout} className="text-sm font-bold text-stone-500 hover:text-red-600 transition-colors uppercase">
          {t('nav.logout')}
        </button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-12">
        {/* CỘT TRÁI: THÔNG TIN CÁ NHÂN */}
        <div className="lg:col-span-1">
          <h2 className="text-lg font-bold text-stone-900 mb-6 uppercase tracking-wider">{t('profile.personal_info')}</h2>
          <form onSubmit={handleUpdate} className="space-y-4">
            <div>
              <label className="text-xs font-bold text-stone-500 uppercase">{t('profile.fullname')}</label>
              <input 
                type="text" className="w-full p-3 border border-stone-200 rounded mt-1 bg-stone-50 focus:bg-white focus:border-stone-900 outline-none transition-colors"
                value={formData.full_name} onChange={e => setFormData({...formData, full_name: e.target.value})}
              />
            </div>
            <div>
              <label className="text-xs font-bold text-stone-500 uppercase">{t('profile.phone')}</label>
              <input 
                type="text" className="w-full p-3 border border-stone-200 rounded mt-1 bg-stone-50 focus:bg-white focus:border-stone-900 outline-none transition-colors"
                value={formData.phone} onChange={e => setFormData({...formData, phone: e.target.value})}
              />
            </div>
            <div>
              <label className="text-xs font-bold text-stone-500 uppercase">{t('profile.address')}</label>
              <textarea 
                className="w-full p-3 border border-stone-200 rounded mt-1 bg-stone-50 focus:bg-white focus:border-stone-900 outline-none transition-colors h-24 resize-none"
                value={formData.address} onChange={e => setFormData({...formData, address: e.target.value})}
              ></textarea>
            </div>
            
            {msg && <p className="text-green-600 text-sm font-medium">{msg}</p>}

            <button className="w-full bg-stone-900 text-white py-3 font-bold uppercase tracking-widest hover:bg-stone-800 transition-colors">
              {t('profile.update_btn')}
            </button>
          </form>
        </div>

        {/* CỘT PHẢI: LỊCH SỬ ĐƠN HÀNG */}
        <div className="lg:col-span-2">
          <h2 className="text-lg font-bold text-stone-900 mb-6 uppercase tracking-wider">{t('profile.order_history')}</h2>
          
          {user.history && user.history.length > 0 ? (
            <div className="space-y-4">
              {user.history.map(order => (
                <div key={order.id} className="border border-stone-200 p-4 rounded bg-stone-50 flex justify-between items-center">
                    <div>
                        <p className="font-bold text-stone-900">{order.code}</p>
                        <p className="text-sm text-stone-500">{new Date(order.created_at).toLocaleDateString(lang === 'vi' ? 'vi-VN' : 'en-US')}</p>
                        <p className="text-sm mt-1">{t('profile.total_amount')}: <span className="font-medium text-stone-900">{new Intl.NumberFormat('vi-VN').format(order.total_amount)} đ</span></p>
                    </div>
                    <div className="text-right">
                        <span className={`px-3 py-1 text-xs font-bold rounded-full uppercase 
                            ${order.status === 'completed' ? 'bg-green-100 text-green-700' : 
                              order.status === 'cancelled' ? 'bg-red-100 text-red-700' : 'bg-yellow-100 text-yellow-700'}`}>
                            {lang === 'vi' 
                                ? (ORDER_STATUS_MAP[order.status]?.label || order.status) 
                                : order.status.charAt(0).toUpperCase() + order.status.slice(1)}
                        </span>
                        {order.shipping_tracking_code && (
                            <p className="text-xs text-stone-500 mt-2">{t('profile.tracking_code')}: {order.shipping_tracking_code}</p>
                        )}
                    </div>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-stone-500 italic">{t('profile.no_orders')}</p>
          )}
        </div>
      </div>
    </div>
  );
};

export default Profile;