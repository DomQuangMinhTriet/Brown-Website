import { useState } from 'react';
import { supabase } from '../supabaseClient';
import { Link, useNavigate } from 'react-router-dom';
import { useLanguage } from '../context/LanguageContext';
import Button from '../components/ui/Button';

const inputCls =
  'w-full mt-2 rounded-xl border border-sand bg-cream px-4 py-3 text-ink outline-none transition-colors focus:border-cocoa placeholder:text-muted/60';

const Login = () => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();
  const { t } = useLanguage();

  const handleLogin = async (e) => {
    e.preventDefault();
    setLoading(true);

    const { error } = await supabase.auth.signInWithPassword({ email, password });

    if (error) {
      alert(t('auth.toast_error') + error.message);
    } else {
      navigate('/');
    }
    setLoading(false);
  };

  return (
    <div className="flex min-h-[80vh] items-center justify-center bg-cream px-4 py-16">
      <div className="w-full max-w-md rounded-2xl border border-sand bg-surface p-8 shadow-[0_30px_70px_-40px_rgba(87,52,37,0.4)] md:p-10">
        <div className="mb-8 text-center">
          <Link to="/" className="font-sugo text-3xl uppercase tracking-[0.1em] text-cocoa">BROWN</Link>
          <h1 className="mt-3 font-heading text-2xl text-espresso">{t('auth.login_title')}</h1>
        </div>

        <form onSubmit={handleLogin} className="space-y-5">
          <div>
            <label className="text-xs font-semibold uppercase tracking-wider text-muted">{t('auth.email')}</label>
            <input type="email" className={inputCls} value={email} onChange={(e) => setEmail(e.target.value)} required autoComplete="email" />
          </div>

          <div>
            <label className="text-xs font-semibold uppercase tracking-wider text-muted">{t('auth.password')}</label>
            <input type="password" className={inputCls} value={password} onChange={(e) => setPassword(e.target.value)} required autoComplete="current-password" />
          </div>

          <Button type="submit" variant="solid" size="lg" disabled={loading} className="w-full">
            {loading ? t('auth.authenticating') : t('auth.login_btn')}
          </Button>
        </form>

        <p className="mt-7 text-center text-sm text-muted">
          {t('auth.no_account')}{' '}
          <Link to="/register" className="font-medium text-cocoa transition-colors hover:text-clay">{t('auth.register_now')}</Link>
        </p>
      </div>
    </div>
  );
};

export default Login;
