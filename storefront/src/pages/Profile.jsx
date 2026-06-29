import { useState, useEffect } from 'react';
import { useAuth } from '../context/AuthContext';
import axios from 'axios';
import { useNavigate } from 'react-router-dom';
import { ORDER_STATUS_MAP } from '../utils/translations';
import { useLanguage } from '../context/LanguageContext';
import Container from '../components/ui/Container';
import Button from '../components/ui/Button';

const inputCls =
  'w-full mt-2 rounded-xl border border-sand bg-cream px-4 py-3 text-ink outline-none transition-colors focus:border-cocoa';

const statusBadge = (status) => {
  if (status === 'completed') return 'bg-sage/15 text-sage';
  if (status === 'cancelled') return 'bg-clay/15 text-clay';
  return 'bg-amber-100 text-amber-700';
};

const Profile = () => {
  const { user, logout, getToken } = useAuth();
  const navigate = useNavigate();
  const { t, lang } = useLanguage();
  const [formData, setFormData] = useState({ full_name: '', phone: '', address: '' });
  const [msg, setMsg] = useState('');

  useEffect(() => {
    if (user) {
      setFormData({
        full_name: user.full_name || '',
        phone: user.phone || '',
        address: user.address || '',
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
        headers: { Authorization: `Bearer ${token}` },
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

  if (!user) return <div className="py-20 text-center text-muted">Đang tải...</div>;

  return (
    <Container className="min-h-[60vh] py-12">
      <div className="mb-10 flex items-end justify-between border-b border-sand pb-4">
        <h1 className="font-heading text-4xl text-espresso">{t('profile.title')}</h1>
        <button onClick={handleLogout} className="text-sm font-semibold uppercase tracking-wider text-muted transition-colors hover:text-clay">
          {t('nav.logout')}
        </button>
      </div>

      <div className="grid grid-cols-1 gap-12 lg:grid-cols-3">
        {/* THÔNG TIN CÁ NHÂN */}
        <div className="lg:col-span-1">
          <h2 className="mb-6 font-heading text-xl text-espresso">{t('profile.personal_info')}</h2>
          <form onSubmit={handleUpdate} className="space-y-4">
            <div>
              <label className="text-xs font-semibold uppercase tracking-wider text-muted">{t('profile.fullname')}</label>
              <input type="text" className={inputCls} value={formData.full_name} onChange={(e) => setFormData({ ...formData, full_name: e.target.value })} />
            </div>
            <div>
              <label className="text-xs font-semibold uppercase tracking-wider text-muted">{t('profile.phone')}</label>
              <input type="text" className={inputCls} value={formData.phone} onChange={(e) => setFormData({ ...formData, phone: e.target.value })} />
            </div>
            <div>
              <label className="text-xs font-semibold uppercase tracking-wider text-muted">{t('profile.address')}</label>
              <textarea className={`${inputCls} h-24 resize-none`} value={formData.address} onChange={(e) => setFormData({ ...formData, address: e.target.value })} />
            </div>

            {msg && <p className="text-sm font-medium text-sage">{msg}</p>}

            <Button type="submit" variant="solid" size="lg" className="w-full">
              {t('profile.update_btn')}
            </Button>
          </form>
        </div>

        {/* LỊCH SỬ ĐƠN HÀNG */}
        <div className="lg:col-span-2">
          <h2 className="mb-6 font-heading text-xl text-espresso">{t('profile.order_history')}</h2>

          {user.history && user.history.length > 0 ? (
            <div className="space-y-4">
              {user.history.map((order) => (
                <div key={order.id} className="flex items-center justify-between rounded-2xl border border-sand bg-surface p-5">
                  <div>
                    <p className="font-heading text-lg text-espresso">{order.code}</p>
                    <p className="text-sm text-muted">{new Date(order.created_at).toLocaleDateString(lang === 'vi' ? 'vi-VN' : 'en-US')}</p>
                    <p className="mt-1 text-sm text-ink/80">{t('profile.total_amount')}: <span className="font-medium text-espresso">{new Intl.NumberFormat('vi-VN').format(order.total_amount)} đ</span></p>
                  </div>
                  <div className="text-right">
                    <span className={`rounded-full px-3 py-1 text-xs font-semibold uppercase ${statusBadge(order.status)}`}>
                      {lang === 'vi'
                        ? (ORDER_STATUS_MAP[order.status]?.label || order.status)
                        : order.status.charAt(0).toUpperCase() + order.status.slice(1)}
                    </span>
                    {order.shipping_tracking_code && (
                      <p className="mt-2 text-xs text-muted">{t('profile.tracking_code')}: {order.shipping_tracking_code}</p>
                    )}
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <p className="italic text-muted">{t('profile.no_orders')}</p>
          )}
        </div>
      </div>
    </Container>
  );
};

export default Profile;
