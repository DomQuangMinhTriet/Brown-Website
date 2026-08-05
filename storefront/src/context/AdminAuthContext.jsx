/* eslint-disable react-refresh/only-export-components */
// client/src/context/AdminAuthContext.jsx
import { createContext, useContext, useState, useEffect } from 'react';
// [QUAN TRỌNG] Import client chung, KHÔNG ĐƯỢC TỰ TẠO CLIENT MỚI
import { supabase } from '../supabaseClient'; 

const AdminAuthContext = createContext();

export const useAdminAuth = () => useContext(AdminAuthContext);

export const AdminAuthProvider = ({ children }) => {
  const [admin, setAdmin] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // 1. Kiểm tra session khi mới vào
    const checkSession = async () => {
      const { data: { session } } = await supabase.auth.getSession();
      setAdmin(session?.user || null);
      setLoading(false);
    };
    checkSession();

    // 2. Lắng nghe sự kiện đăng nhập/đăng xuất
    const { data: listener } = supabase.auth.onAuthStateChange((_event, session) => {
      setAdmin(session?.user || null);
      setLoading(false);
    });

    return () => listener.subscription.unsubscribe();
  }, []);

  const login = async (email, password) => {
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) throw error;
    return data;
  };

  const logout = async () => {
    try {
        await supabase.auth.signOut();
    } catch (error) {
        console.error("Admin logout error:", error);
    } finally {
        // Xóa sạch trạng thái Admin
        setAdmin(null);
        
        // Xóa Token trong LocalStorage
        localStorage.removeItem('sb-dbuwgocouxlpxulnlajl-auth-token'); 
        
        // Điều hướng về trang login admin
        window.location.href = '/admin/login';
    }
  };

  return (
    <AdminAuthContext.Provider value={{ admin, loading, login, logout, supabase }}>
      {children}
    </AdminAuthContext.Provider>
  );
};
