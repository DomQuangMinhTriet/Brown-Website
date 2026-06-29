import { useState } from 'react';
import { supabase } from '../supabaseClient';
import { Link, useNavigate } from 'react-router-dom';
import { useLanguage } from '../context/LanguageContext';
import Button from '../components/ui/Button';

const inputCls =
  'w-full mt-2 rounded-xl border border-sand bg-cream px-4 py-3 text-ink outline-none transition-colors focus:border-cocoa placeholder:text-muted/60';

const Register = () => {
  const [formData, setFormData] = useState({ fullName: '', phone: '', email: '', password: '' });
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();
  const { t } = useLanguage();

  const handleRegister = async (e) => {
    e.preventDefault();
    setLoading(true);

    try {
      const { error } = await supabase.auth.signUp({
        email: formData.email,
        password: formData.password,
        options: {
          data: {
            full_name: formData.fullName,
            phone: formData.phone,
          },
        },
      });

      if (error) throw error;

      alert(t('auth.toast_register_success'));
      navigate('/');
    } catch (error) {
      alert(t('auth.toast_error') + error.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="flex min-h-[80vh] items-center justify-center bg-cream px-4 py-16">
      <div className="w-full max-w-md rounded-2xl border border-sand bg-surface p-8 shadow-[0_30px_70px_-40px_rgba(87,52,37,0.4)] md:p-10">
        <div className="mb-8 text-center">
          <Link to="/" className="font-sugo text-3xl uppercase tracking-[0.1em] text-cocoa">BROWN</Link>
          <h1 className="mt-3 font-heading text-2xl text-espresso">{t('auth.register_title')}</h1>
        </div>

        <form onSubmit={handleRegister} className="space-y-5">
          <div>
            <label className="text-xs font-semibold uppercase tracking-wider text-muted">{t('auth.fullname')}</label>
            <input type="text" className={inputCls} value={formData.fullName} onChange={(e) => setFormData({ ...formData, fullName: e.target.value })} required autoComplete="name" />
          </div>

          <div>
            <label className="text-xs font-semibold uppercase tracking-wider text-muted">{t('auth.phone')}</label>
            <input type="tel" className={inputCls} value={formData.phone} onChange={(e) => setFormData({ ...formData, phone: e.target.value })} required autoComplete="tel" />
          </div>

          <div>
            <label className="text-xs font-semibold uppercase tracking-wider text-muted">{t('auth.email')}</label>
            <input type="email" className={inputCls} value={formData.email} onChange={(e) => setFormData({ ...formData, email: e.target.value })} required autoComplete="email" />
          </div>

          <div>
            <label className="text-xs font-semibold uppercase tracking-wider text-muted">{t('auth.password')}</label>
            <input type="password" className={inputCls} value={formData.password} onChange={(e) => setFormData({ ...formData, password: e.target.value })} required autoComplete="new-password" placeholder={t('auth.password_min')} />
          </div>

          <Button type="submit" variant="solid" size="lg" disabled={loading} className="w-full">
            {loading ? t('auth.processing') : t('auth.register_btn')}
          </Button>
        </form>

        <p className="mt-7 text-center text-sm text-muted">
          {t('auth.have_account')}{' '}
          <Link to="/login" className="font-medium text-cocoa transition-colors hover:text-clay">{t('auth.login_now')}</Link>
        </p>
      </div>
    </div>
  );
};

export default Register;
