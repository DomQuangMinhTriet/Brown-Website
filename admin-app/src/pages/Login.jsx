import { useState } from 'react';
import { useAdminAuth } from '../context/AdminAuthContext';
import { useNavigate } from 'react-router-dom';

const Login = () => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const { login } = useAdminAuth();
  const navigate = useNavigate();

  const handleLogin = async (e) => {
    e.preventDefault();
    setLoading(true);
    try {
      await login(email, password);
      navigate('/'); // Đăng nhập xong chuyển về Dashboard
    } catch (error) {
      alert("Đăng nhập thất bại: " + error.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-stone-100">
      <div className="bg-white p-8 rounded-lg shadow-md w-full max-w-sm">
        <h1 className="text-2xl font-bold text-center text-stone-800 mb-6 uppercase tracking-widest">BROWN ADMIN</h1>
        
        <form onSubmit={handleLogin} className="space-y-4">
          <div>
            <label className="block text-sm font-bold text-stone-600 mb-1">Email</label>
            <input 
              type="email" required
              className="w-full p-3 border border-stone-300 rounded focus:border-stone-900 outline-none"
              value={email} onChange={e => setEmail(e.target.value)}
            />
          </div>
          <div>
            <label className="block text-sm font-bold text-stone-600 mb-1">Mật khẩu</label>
            <input 
              type="password" required
              className="w-full p-3 border border-stone-300 rounded focus:border-stone-900 outline-none"
              value={password} onChange={e => setPassword(e.target.value)}
            />
          </div>
          <button 
            disabled={loading}
            className="w-full bg-stone-900 text-white py-3 rounded font-bold uppercase hover:bg-stone-800 transition-all"
          >
            {loading ? 'Đang xử lý...' : 'Đăng nhập hệ thống'}
          </button>
        </form>
      </div>
    </div>
  );
};

export default Login;