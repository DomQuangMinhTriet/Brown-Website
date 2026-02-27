// Tỷ giá cố định (Bạn có thể cập nhật tỷ giá này hoặc lấy từ API nếu muốn chính xác từng ngày)
const EXCHANGE_RATE = 25400; // 1 USD = 25,400 VND

export const formatPrice = (amount, currency = 'VND') => {
  if (!amount) return currency === 'VND' ? '0₫' : '$0.00';

  // Đảm bảo amount là số
  const numericAmount = Number(amount);

  if (currency === 'USD') {
    // Chuyển đổi sang USD
    const converted = numericAmount / EXCHANGE_RATE;
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    }).format(converted);
  }

  // Mặc định là VND
  return new Intl.NumberFormat('vi-VN', {
    style: 'currency',
    currency: 'VND',
  }).format(numericAmount);
};