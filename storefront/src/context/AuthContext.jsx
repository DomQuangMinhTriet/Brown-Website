// client/src/context/AuthContext.jsx
import { createContext, useContext, useState, useEffect } from 'react';
import axios from 'axios';
// [QUAN TRỌNG] Import từ file cấu hình chung, KHÔNG tự tạo client ở đây nữa
import { supabase } from '../supabaseClient';

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
            headers: { Authorization: `Bearer ${token}` }
        });
        if(res.data.success) {
            setUser({ ...authUser, ...res.data.data }); 
        }
    } catch (error) {
        console.error("Lỗi lấy profile:", error);
        
        // [QUAN TRỌNG] BẮT LỖI 401 ĐỂ CẮT VÒNG LẶP
        // Nếu Server báo 401 (Unauthorized) -> Token hỏng -> Buộc đăng xuất ngay
        if (error.response && (error.response.status === 401 || error.response.status === 403)) {
            console.warn("Token hết hạn/lỗi. Đang đăng xuất sạch sẽ...");
            
            // 1. Đăng xuất trên Supabase
            await supabase.auth.signOut();
            
            // 2. Xóa sạch State
            setSession(null);
            setUser(null);
            
            // 3. Xóa sạch LocalStorage (Xóa tận gốc)
            localStorage.clear(); 
        } else {
            // Nếu lỗi khác (ví dụ 500, hoặc chưa có profile) thì vẫn giữ user cơ bản để không bị văng ra
            setUser(authUser);
        }
    } finally {
        setLoading(false);
    }
  };

  const logout = async () => {
    try {
        // 1. Gửi lệnh đăng xuất lên Server
        await supabase.auth.signOut();
    } catch (error) {
        console.error("Lỗi API đăng xuất:", error);
    } finally {
        // 2. [QUAN TRỌNG] Bất kể API có lỗi hay không, Client PHẢI xóa sạch dữ liệu
        setUser(null);
        setSession(null);
        
        // 3. Xóa sạch LocalStorage (Token, Giỏ hàng...)
        localStorage.clear(); 
        
        // 4. Force Reload trang về Home để đảm bảo sạch bộ nhớ đệm
        window.location.href = '/'; 
    }
  };

  return (
    <AuthContext.Provider value={{ user, session, loading, logout, getToken }}>
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => useContext(AuthContext);