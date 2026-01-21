import { createContext, useState, useContext } from 'react';
import { translations } from '../utils/translations';

const LanguageContext = createContext();

export const useLanguage = () => useContext(LanguageContext);

export const LanguageProvider = ({ children }) => {
  // Mặc định là tiếng Việt ('vi')
  const [lang, setLang] = useState('vi');

  const toggleLang = () => {
    setLang((prev) => (prev === 'vi' ? 'en' : 'vi'));
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