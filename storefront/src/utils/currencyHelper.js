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

/**
 * Tính giá bán thực tế, có xét GIẢM GIÁ TRỰC TIẾP theo BIẾN THỂ (màu/size).
 * Trả về { price, original, isDiscounted }:
 *  - price: giá cuối cùng khách phải trả
 *  - original: giá gốc (base_price) để gạch ngang nếu đang giảm
 *  - isDiscounted: có đang giảm giá không
 *
 * - Có truyền `variant` cụ thể (đã chọn màu/size) → tính đúng theo giảm giá của biến thể đó.
 * - Không truyền `variant` (VD: thẻ sản phẩm ở trang danh sách, chưa biết khách chọn gì)
 *   → lấy giá THẤP NHẤT trong các biến thể còn hiển thị của sản phẩm.
 */
export const getEffectivePrice = (product, variant) => {
  const base = Number(product?.base_price) || 0;

  if (variant) {
    const off = Number(variant.discount_amount) || 0;
    const active = !!variant.is_discount_active && off > 0;
    if (!active) return { price: base, original: base, isDiscounted: false };
    return { price: Math.max(0, base - off), original: base, isDiscounted: true };
  }

  const variants = (product?.variants || []).filter(v => !v.is_deleted);
  if (variants.length === 0) return { price: base, original: base, isDiscounted: false };

  let best = null;
  for (const v of variants) {
    const off = Number(v.discount_amount) || 0;
    const active = !!v.is_discount_active && off > 0;
    const price = active ? Math.max(0, base - off) : base;
    if (!best || price < best.price) best = { price, original: base, isDiscounted: active };
  }
  return best;
};