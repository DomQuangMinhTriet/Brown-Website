// Chèn transformation của Cloudinary vào URL để lấy bản ảnh đã thu nhỏ/nén,
// thay vì tải nguyên ảnh gốc mỗi lần hiển thị — giảm băng thông đáng kể ở
// mọi nơi chỉ cần ảnh thumbnail (lưới sản phẩm, giỏ hàng, danh sách admin...).
//
// Dùng CHUNG cho toàn bộ storefront + admin thay vì mỗi trang tự định nghĩa
// một bản giống hệt nhau (trước đây có 4 bản trùng lặp).
export const optimizeImage = (url, width = 400) => {
  if (!url || typeof url !== 'string' || !url.includes('cloudinary.com')) return url;
  const uploadIndex = url.indexOf('upload/') + 7;
  const transformations = `c_scale,w_${width},f_auto,q_auto/`;
  return url.substring(0, uploadIndex) + transformations + url.substring(uploadIndex);
};
