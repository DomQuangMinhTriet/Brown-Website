import { useState } from 'react';
import { supabase } from '../context/AuthContext';
import { Link, useNavigate } from 'react-router-dom';

const Login = () => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();

  const handleLogin = async (e) => {
    e.preventDefault();
    setLoading(true);
    
    const { error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });

    if (error) {
      alert("Lỗi đăng nhập: " + error.message);
    } else {
      // alert("Đăng nhập thành công!"); // Có thể bỏ alert cho mượt
      navigate('/'); // Về trang chủ
    }
    setLoading(false);
  };

  return (
    <div className="min-h-[80vh] flex items-center justify-center bg-stone-50 py-12 px-4">
      <div className="bg-white p-8 rounded shadow-sm w-full max-w-md border border-stone-100">
        <h2 className="text-2xl font-bold mb-6 text-center text-stone-800 font-serif">ĐĂNG NHẬP</h2>
        
        <form onSubmit={handleLogin} className="space-y-4">
          <div>
            <label className="text-xs uppercase font-bold text-stone-500">Email</label>
            <input 
              type="email" className="w-full p-3 border border-stone-200 rounded mt-1 focus:border-stone-900 outline-none"
              value={email} onChange={e => setEmail(e.target.value)} required
            />
          </div>
          
          <div>
            <label className="text-xs uppercase font-bold text-stone-500">Mật khẩu</label>
            <input 
              type="password" className="w-full p-3 border border-stone-200 rounded mt-1 focus:border-stone-900 outline-none"
              value={password} onChange={e => setPassword(e.target.value)} required
            />
          </div>

          <button disabled={loading} className="w-full bg-stone-900 text-white py-4 font-bold uppercase tracking-widest hover:bg-stone-800 transition-all mt-4">
            {loading ? 'Đang xác thực...' : 'Đăng Nhập'}
          </button>
        </form>
        
        <p className="mt-6 text-center text-sm text-stone-500">
          Chưa có tài khoản? <Link to="/register" className="font-bold text-stone-900 underline">Đăng ký ngay</Link>
        </p>
      </div>
    </div>
  );
};

export default Login;