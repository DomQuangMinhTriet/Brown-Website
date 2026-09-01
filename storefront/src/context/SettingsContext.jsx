/* eslint-disable react-refresh/only-export-components */
import { createContext, useContext, useEffect, useState } from 'react';
import { cachedGet } from '../utils/apiCache';

const SettingsContext = createContext();

export const useSettings = () => useContext(SettingsContext);

// Mặc định true (hiện) khi chưa tải xong hoặc API lỗi, để tránh việc ẩn nhầm
// nội dung chỉ vì mạng chậm/API tạm lỗi.
const DEFAULT_SETTINGS = { lookbook_enabled: true };

export const SettingsProvider = ({ children }) => {
  const [settings, setSettings] = useState(DEFAULT_SETTINGS);

  useEffect(() => {
    cachedGet(`${import.meta.env.VITE_API_URL}/api/content/settings`, 120_000)
      .then((res) => {
        if (res.data?.success && res.data.data) {
          setSettings((prev) => ({ ...prev, ...res.data.data }));
        }
      })
      .catch(() => {});
  }, []);

  return (
    <SettingsContext.Provider value={settings}>
      {children}
    </SettingsContext.Provider>
  );
};
