// Số điện thoại VN: bắt đầu bằng 0, theo sau đúng 9 chữ số (tổng 10 số)
const PHONE_REGEX = /^0\d{9}$/;

const isValidPhone = (phone) => typeof phone === 'string' && PHONE_REGEX.test(phone);

module.exports = { PHONE_REGEX, isValidPhone };
