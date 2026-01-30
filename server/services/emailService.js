// server/services/emailService.js
const nodemailer = require('nodemailer');
require('dotenv').config();

// CẤU HÌNH TỐI ƯU CHO RAILWAY/CLOUD
const transporter = nodemailer.createTransport({
  host: "smtp.gmail.com",  // Khai báo rõ host thay vì dùng service: 'gmail'
  port: 465,               // Dùng Port 465 (SSL) thay vì 587. Port này ít bị chặn hơn.
  secure: true,            // Bắt buộc dùng SSL
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS
  },
  // Các option phụ để tránh timeout
  tls: {
    // Không check chứng chỉ lỗi (giúp vượt qua một số firewall chặt)
    rejectUnauthorized: false, // Thêm các options này để thử bypass
    ciphers: 'SSLv3'
  },
  // Tăng thời gian chờ kết nối (mặc định là quá ngắn với server cloud)
  connectionTimeout: 10000, // 10 giây
  greetingTimeout: 5000,    // 5 giây
  socketTimeout: 10000      // 10 giây
});

const sendEmail = async (to, subject, text, html) => {
  // Kiểm tra biến môi trường
  if (!process.env.SMTP_USER || !process.env.SMTP_PASS) {
    console.warn('⚠️ EMAIL WARNING: Chưa cấu hình SMTP. Email không được gửi.');
    return null; 
  }

  try {    
    const info = await transporter.sendMail({
      from: `"BROWN" <${process.env.SMTP_USER}>`,
      to: to, 
      subject: subject, 
      text: text, 
      html: html, 
    });

    console.log('✅ Email sent: %s', info.messageId);
    return info;

  } catch (error) {
    console.error('❌ Email Error:', error.message);
    return null; 
  }
};

const sendOrderConfirmation = async (order, customerEmail) => {
    if (!customerEmail) return;

    const subject = `[BROWN] Xác nhận đơn hàng #${order.code}`;
    
    // NỘI DUNG EMAIL MỚI (DÀNH CHO CHUYỂN KHOẢN)
    const htmlContent = `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; border: 1px solid #eee; border-radius: 8px; overflow: hidden;">
            <div style="background-color: #1c1917; color: white; padding: 20px; text-align: center;">
                <h2 style="margin: 0;">ĐƠN HÀNG ĐÃ ĐƯỢC GHI NHẬN</h2>
            </div>
            <div style="padding: 20px;">
                <p>Xin chào <b>${order.customer_name}</b>,</p>
                <p>Cảm ơn bạn đã đặt hàng tại BROWN. Đơn hàng <b>${order.code}</b> của bạn đã được khởi tạo.</p>
                
                <div style="background: #f5f5f4; padding: 15px; margin: 20px 0; border-radius: 5px; border-left: 4px solid #1c1917;">
                    <p style="margin: 5px 0;"><strong>Tổng thanh toán:</strong> ${new Intl.NumberFormat('vi-VN').format(order.total_amount * 1000)} đ</p>
                    <p style="margin: 5px 0;"><strong>Hình thức:</strong> Chuyển khoản ngân hàng (QR)</p>
                </div>

                <div style="margin-bottom: 20px;">
                    <p>Nếu bạn chưa hoàn tất thanh toán, vui lòng chuyển khoản đến:</p>
                    <ul style="color: #444; background: #fff; border: 1px dashed #ccc; padding: 15px 30px; border-radius: 5px;">
                        <li>Ngân hàng: <b>Sacombank</b></li>
                        <li>Số TK: <b>0902173763</b></li>
                        <li>Chủ TK: <b>LUU THI PHUONG QUYNH</b></li>
                        <li>Nội dung: SĐT <b> ${order.customer_name}</b></li>
                    </ul>
                </div>

                <p>Chúng tôi sẽ xử lý và giao hàng ngay khi nhận được thanh toán.</p>
            </div>
            <div style="background-color: #f5f5f4; color: #78716c; padding: 15px; text-align: center; font-size: 12px;">
                © 2026 BROWN FASHION. All rights reserved.
            </div>
        </div>
    `;

    return await sendEmail(customerEmail, subject, `Đơn hàng ${order.code} đã được nhận.`, htmlContent);
};

// --- [MỚI] THÊM HÀM NÀY ĐỂ FIX LỖI ---
const sendShippingConfirmation = async (order, trackingCode) => {
    // Kiểm tra email khách hàng, nếu không có thì bỏ qua
    // Lưu ý: data trả về từ updateOrderStatus có cấu trúc hơi khác createOrder, 
    // nên ta cần lấy email từ customer_info nếu có
    const email = order.customer_info?.email || order.customer_email; 
    if (!email) return;

    const subject = `[BROWN] Đơn hàng #${order.code} đang được vận chuyển 🚚`;
    const trackingLink = `https://khachhang.ghn.vn/order-tracking?code=${trackingCode}`;

    const htmlContent = `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; border: 1px solid #e5e7eb; border-radius: 8px; overflow: hidden;">
            <div style="background-color: #292524; color: white; padding: 20px; text-align: center;">
                <h2 style="margin: 0;">ĐƠN HÀNG ĐANG VẬN CHUYỂN</h2>
            </div>
            <div style="padding: 20px;">
                <p>Xin chào quý khách,</p>
                <p>Tin vui! Đơn hàng <strong>${order.code}</strong> của bạn đã được bàn giao cho đơn vị vận chuyển.</p>

                <div style="background-color: #f5f5f4; padding: 20px; margin: 20px 0; border-radius: 8px; text-align: center;">
                    <p style="margin: 0 0 10px 0; color: #78716c; font-size: 14px; text-transform: uppercase;">Mã vận đơn (GHN)</p>
                    <div style="font-size: 24px; font-weight: bold; color: #dc2626; margin-bottom: 15px;">
                        ${trackingCode}
                    </div>
                    <a href="${trackingLink}" target="_blank" style="display: inline-block; background-color: #292524; color: #ffffff; text-decoration: none; padding: 10px 20px; border-radius: 4px; font-weight: bold;">
                        THEO DÕI ĐƠN HÀNG
                    </a>
                </div>
                
                <p style="font-size: 13px; color: #57534e;">*Trạng thái đơn hàng có thể mất vài giờ để cập nhật trên hệ thống vận chuyển.</p>
            </div>
        </div>
    `;

    return await sendEmail(email, subject, `Đơn hàng ${order.code} đang vận chuyển.`, htmlContent);
};

// 2. THÊM HÀM MỚI NÀY VÀO:
const sendNewOrderNotifyToAdmin = async (orderData) => {
  try {
    const adminEmail = process.env.SMTP_USER; // Gửi cho chính mình
    
    // Format tiền tệ
    const formattedPrice = new Intl.NumberFormat('vi-VN', { 
      style: 'currency', 
      currency: 'VND' 
    }).format(orderData.total_amount);

    const mailOptions = {
      from: `"BROWN System" <${process.env.SMTP_USER}>`,
      to: adminEmail,
      subject: `🔔 Đơn mới #${orderData.id} - ${formattedPrice}`,
      html: `
        <h3>Bạn có đơn hàng mới!</h3>
        <p>Mã đơn: <strong>${orderData.id}</strong></p>
        <p>Khách hàng: ${orderData.customer_name}</p>
        <p>SĐT: ${orderData.phone}</p>
        <p>Tổng tiền: <span style="color:red; font-weight:bold">${formattedPrice}</span></p>
        <p>Thanh toán: ${orderData.payment_method}</p>
      `
    };

    await transporter.sendMail(mailOptions);
    console.log(`✅ Đã gửi mail thông báo đơn hàng #${orderData.id}`);
  } catch (error) {
    console.error('❌ Lỗi gửi mail Admin:', error);
  }
};

// [QUAN TRỌNG] Nhớ export cả sendShippingConfirmation
module.exports = { sendEmail, sendOrderConfirmation, sendShippingConfirmation, sendNewOrderNotifyToAdmin };