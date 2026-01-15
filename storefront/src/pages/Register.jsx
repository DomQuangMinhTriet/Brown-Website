import { useState } from 'react';
import { supabase } from '../context/AuthContext'; // Import từ Context
import { Link, useNavigate } from 'react-router-dom';

const Register = () => {
  const [formData, setFormData] = useState({ fullName: '', phone: '', email: '', password: '' });
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();

  const handleRegister = async (e) => {
    e.preventDefault();
    setLoading(true);

    try {
      // Đăng ký với Supabase Auth
      // Quan trọng: Truyền data vào options để Trigger Database bắt được
      const { data, error } = await supabase.auth.signUp({
        email: formData.email,
        password: formData.password,
        options: {
          data: {
            full_name: formData.fullName, // Trigger sẽ lấy cái này
            phone: formData.phone         // Trigger sẽ lấy cái này
          }
        }
      });

      if (error) throw error;

      alert("✅ Đăng ký thành công! Bạn đã được tự động đăng nhập.");
      navigate('/'); // Chuyển về trang chủ

    } catch (error) {
      alert("❌ Lỗi: " + error.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-[80vh] flex items-center justify-center bg-stone-50 py-12 px-4">
      <div className="bg-white p-8 rounded shadow-sm w-full max-w-md border border-stone-100">
        <h2 className="text-2xl font-bold mb-6 text-center text-stone-800 font-serif">TẠO TÀI KHOẢN</h2>
        
        <form onSubmit={handleRegister} className="space-y-4">
          <div>
            <label className="text-xs uppercase font-bold text-stone-500">Họ và tên</label>
            <input 
              type="text" className="w-full p-3 border border-stone-200 rounded mt-1 focus:border-stone-900 outline-none"
              value={formData.fullName} onChange={e => setFormData({...formData, fullName: e.target.value})} required
            />
          </div>
          
          <div>
            <label className="text-xs uppercase font-bold text-stone-500">Số điện thoại</label>
            <input 
              type="text" className="w-full p-3 border border-stone-200 rounded mt-1 focus:border-stone-900 outline-none"
              value={formData.phone} onChange={e => setFormData({...formData, phone: e.target.value})} required
            />
          </div>

          <div>
            <label className="text-xs uppercase font-bold text-stone-500">Email</label>
            <input 
              type="email" className="w-full p-3 border border-stone-200 rounded mt-1 focus:border-stone-900 outline-none"
              value={formData.email} onChange={e => setFormData({...formData, email: e.target.value})} required
            />
          </div>

          <div>
            <label className="text-xs uppercase font-bold text-stone-500">Mật khẩu</label>
            <input 
              type="password" className="w-full p-3 border border-stone-200 rounded mt-1 focus:border-stone-900 outline-none"
              value={formData.password} onChange={e => setFormData({...formData, password: e.target.value})} required
              placeholder="Tối thiểu 6 ký tự"
            />
          </div>

          <button disabled={loading} className="w-full bg-stone-900 text-white py-4 font-bold uppercase tracking-widest hover:bg-stone-800 transition-all mt-4">
            {loading ? 'Đang xử lý...' : 'Đăng Ký'}
          </button>
        </form>
        
        <p className="mt-6 text-center text-sm text-stone-500">
          Đã có tài khoản? <Link to="/login" className="font-bold text-stone-900 underline">Đăng nhập</Link>
        </p>
      </div>
    </div>
  );
};

export default Register;