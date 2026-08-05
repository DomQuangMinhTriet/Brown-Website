import { useState, useCallback } from 'react';

// HOOK 1: Dùng cho nút bấm đơn lẻ (VD: Nút Nhập hàng, Nút Lưu)
export const useAsync = (asyncFunction) => {
  const [loading, setLoading] = useState(false);

  const execute = useCallback(async (...args) => {
    if (loading) return; // Chặn nếu đang chạy
    setLoading(true);
    try {
      return await asyncFunction(...args);
    } finally {
      setLoading(false);
    }
  }, [loading, asyncFunction]);

  return { execute, loading };
};

// HOOK 2: Dùng cho danh sách (VD: Sửa từng dòng tồn kho)
// Quản lý loading theo ID (key)
export const useKeyedAsync = (asyncFunction) => {
  const [processingKeys, setProcessingKeys] = useState({});

  const execute = useCallback(async (key, ...args) => {
    if (processingKeys[key]) return; // Chặn nếu key này đang chạy

    setProcessingKeys(prev => ({ ...prev, [key]: true }));
    try {
      return await asyncFunction(key, ...args);
    } finally {
      setProcessingKeys(prev => {
        const newState = { ...prev };
        delete newState[key];
        return newState;
      });
    }
  }, [processingKeys, asyncFunction]);

  // Hàm kiểm tra xem key nào đang loading
  const isKeyLoading = (key) => !!processingKeys[key];

  return { execute, isKeyLoading };
};
