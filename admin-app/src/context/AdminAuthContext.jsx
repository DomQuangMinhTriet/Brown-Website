import { createContext, useContext, useState, useEffect } from 'react';
import { createClient } from '@supabase/supabase-js';

// Khởi tạo Supabase Client riêng cho Admin
const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseKey = import.meta.env.VITE_SUPABASE_ANON_KEY;
export const supabase = createClient(supabaseUrl, supabaseKey);

const AdminAuthContext = createContext();

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
    await supabase.auth.signOut();
  };

  return (
    <AdminAuthContext.Provider value={{ admin, login, logout, loading }}>
      {children}
    </AdminAuthContext.Provider>
  );
};

export const useAdminAuth = () => useContext(AdminAuthContext);