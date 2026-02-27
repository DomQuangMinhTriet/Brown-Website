import { useState } from 'react';
import { supabase } from '../supabaseClient'; 
import { Link, useNavigate } from 'react-router-dom';
import { useLanguage } from '../context/LanguageContext';

const Login = () => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();
  const { t } = useLanguage();

  const handleLogin = async (e) => {
    e.preventDefault();
    setLoading(true);
    
    const { error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });

    if (error) {
      alert(t('auth.toast_error') + error.message);
    } else {
      navigate('/'); // Về trang chủ
    }
    setLoading(false);
  };

  return (
    <div className="min-h-[80vh] flex items-center justify-center bg-stone-50 py-12 px-4">
      <div className="bg-white p-8 rounded shadow-sm w-full max-w-md border border-stone-100">
        <h2 className="text-2xl font-bold mb-6 text-center text-stone-800 font-serif">{t('auth.login_title')}</h2>
        
        <form onSubmit={handleLogin} className="space-y-4">
          <div>
            <label className="text-xs uppercase font-bold text-stone-500">{t('auth.email')}</label>
            <input 
              type="email" className="w-full p-3 border border-stone-200 rounded mt-1 focus:border-stone-900 outline-none"
              value={email} onChange={e => setEmail(e.target.value)} required
            />
          </div>
          
          <div>
            <label className="text-xs uppercase font-bold text-stone-500">{t('auth.password')}</label>
            <input 
              type="password" className="w-full p-3 border border-stone-200 rounded mt-1 focus:border-stone-900 outline-none"
              value={password} onChange={e => setPassword(e.target.value)} required
            />
          </div>

          <button disabled={loading} className="w-full bg-stone-900 text-white py-4 font-bold uppercase tracking-widest hover:bg-stone-800 transition-all mt-4">
            {loading ? t('auth.authenticating') : t('auth.login_btn')}
          </button>
        </form>
        
        <p className="mt-6 text-center text-sm text-stone-500">
          {t('auth.no_account')} <Link to="/register" className="font-bold text-stone-900 hover:underline">{t('auth.register_now')}</Link>
        </p>
      </div>
    </div>
  );
};

export default Login;