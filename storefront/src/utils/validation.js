// Số điện thoại VN: bắt đầu bằng 0, theo sau đúng 9 chữ số (tổng 10 số)
export const PHONE_REGEX = /^0\d{9}$/;

export const isValidPhone = (phone) => PHONE_REGEX.test(phone);

// Dùng trong onChange của input số điện thoại: chỉ giữ chữ số, tối đa 10 ký tự
export const sanitizePhoneInput = (value) => value.replace(/\D/g, '').slice(0, 10);
