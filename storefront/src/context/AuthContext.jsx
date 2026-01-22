import { createContext, useContext, useState, useEffect } from 'react';
import { createClient } from '@supabase/supabase-js';
import axios from 'axios';

// Dùng biến môi trường từ Vite
const supabaseUrl = import.meta.env.VITE_SUPABASE_URL; 
const supabaseKey = import.meta.env.VITE_SUPABASE_ANON_KEY;
export const supabase = createClient(supabaseUrl, supabaseKey);

const AuthContext = createContext();

export const AuthProvider = ({ children }) => {
  const [user, setUser] = useState(null); // User object đầy đủ (kèm address, phone...)
  const [session, setSession] = useState(null); // Session để lấy Token
  const [loading, setLoading] = useState(true);

  // Hàm lấy Token hiện tại để gọi API
  const getToken = () => session?.access_token;

  useEffect(() => {
    // 1. Kiểm tra session ban đầu
    const initAuth = async () => {
      const { data: { session } } = await supabase.auth.getSession();
      setSession(session);
      if (session?.user) {
         await fetchProfile(session.user, session.access_token);
      } else {
         setLoading(false);
      }
    };
    initAuth();

    // 2. Lắng nghe sự kiện Login/Logout
    const { data: listener } = supabase.auth.onAuthStateChange(async (_event, session) => {
      setSession(session);
      if (session?.user) {
        await fetchProfile(session.user, session.access_token);
      } else {
        setUser(null);
        setLoading(false);
      }
    });

    return () => listener.subscription.unsubscribe();
  }, []);

  // Lấy Profile từ Backend của mình (Bảng customers)
  const fetchProfile = async (authUser, token) => {
    try {
        const res = await axios.get(`${import.meta.env.VITE_API_URL}/api/customers/me/profile`, {
            headers: { Authorization: `Bearer ${token}` } // Gửi Token lên Server check
        });
        if(res.data.success) {
            // Gộp thông tin Auth và thông tin DB
            setUser({ ...authUser, ...res.data.data }); 
        }
    } catch (error) {
        console.error("Lỗi lấy profile:", error);
        // Fallback: Nếu lỗi API thì vẫn cho login với thông tin cơ bản
        setUser(authUser);
    } finally {
        setLoading(false);
    }
  };

  const logout = async () => {
    await supabase.auth.signOut();
    setUser(null);
    setSession(null);
  };

  return (
    <AuthContext.Provider value={{ user, loading, logout, getToken }}>
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => useContext(AuthContext);