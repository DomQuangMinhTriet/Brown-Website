import axios from 'axios';

export const getGeoInfo = async () => {
  try {
    // Sử dụng API miễn phí để lấy thông tin quốc gia dựa trên IP
    // Bạn có thể dùng ipapi.co, ipinfo.io, hoặc services tương tự
    const response = await axios.get('https://ipapi.co/json/');
    
    return {
      countryCode: response.data.country_code, // Ví dụ: 'VN', 'US'
      currency: response.data.currency         // Ví dụ: 'VND', 'USD'
    };
  } catch (error) {
    console.warn("Không thể tự động định vị, chuyển về mặc định VN:", error);
    // Nếu lỗi (do chặn quảng cáo hoặc mất mạng), trả về mặc định là VN
    return { countryCode: 'VN', currency: 'VND' };
  }
};