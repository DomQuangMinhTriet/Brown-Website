import { createContext, useState, useContext, useEffect } from 'react';
import { translations } from '../utils/translations';

const LanguageContext = createContext();

export const useLanguage = () => useContext(LanguageContext);

export const LanguageProvider = ({ children }) => {
  // Mặc định là tiếng Việt ('vi') hoặc lấy từ bộ nhớ tạm nếu khách đã từng chọn
  const [lang, setLang] = useState(localStorage.getItem('user_lang') || 'vi');

  // Thêm logic tự động định vị khách hàng khi lần đầu vào web
  useEffect(() => {
    const detectLocation = async () => {
      // Chỉ tự động định vị nếu khách chưa từng ấn nút chuyển đổi thủ công
      if (!localStorage.getItem('user_lang')) {
        try {
          const response = await fetch('https://ipapi.co/json/');
          const data = await response.json();
          
          // Nếu mã quốc gia không phải Việt Nam (VN), tự động đổi sang tiếng Anh
          if (data.country_code !== 'VN') {
            setLang('en');
          }
        } catch (error) {
          console.error("Lỗi định vị:", error);
        }
      }
    };
    detectLocation();
  }, []);

  const toggleLang = () => {
    setLang((prev) => {
      const nextLang = prev === 'vi' ? 'en' : 'vi';
      localStorage.setItem('user_lang', nextLang); // Ghi nhớ thao tác thủ công
      return nextLang;
    });
  };

  // Hàm lấy text: t('nav.home')
  const t = (key) => {
    const keys = key.split('.');
    let value = translations[lang];
    keys.forEach(k => {
      value = value ? value[k] : key;
    });
    return value;
  };

  return (
    <LanguageContext.Provider value={{ lang, toggleLang, t }}>
      {children}
    </LanguageContext.Provider>
  );
};