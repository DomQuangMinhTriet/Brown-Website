const nodemailer = require('nodemailer');

<<<<<<< HEAD
const transporter = nodemailer.createTransport({
    service: 'gmail',
    auth: {
        user: process.env.MAIL_USER,
        pass: process.env.MAIL_PASS
    }
});

const sendOrderConfirmation = async (order, customerEmail) => {
    try {
        if (!customerEmail) return;

        const mailOptions = {
            from: '"BROWN FASHION" <no-reply@brown.com>',
            to: customerEmail,
            subject: `[BROWN] Đơn hàng #${order.code} đã được xác nhận!`,
            html: `
                <div style="font-family: Arial, sans-serif; padding: 20px; border: 1px solid #eee;">
                    <h2 style="color: #2c3e50;">Đơn hàng của bạn đã được xác nhận!</h2>
                    <p>Xin chào, đơn hàng <b>${order.code}</b> đang được đóng gói.</p>
                    
                    <div style="background: #f0f9ff; padding: 15px; border-radius: 5px; margin: 20px 0;">
                        <h3 style="margin: 0 0 10px 0; color: #0288d1;">📦 THÔNG TIN VẬN CHUYỂN</h3>
                        <p>Đơn vị vận chuyển: <b>SPX Express</b></p>
                        <p>Mã vận đơn: <b style="font-size: 18px; color: #d32f2f;">${order.shipping_tracking_code || 'Đang cập nhật'}</b></p>
                        <p><i>Bạn có thể dùng mã này để tra cứu hành trình đơn hàng.</i></p>
                    </div>

                    <p>Tổng thanh toán: <b>${new Intl.NumberFormat('vi-VN').format(order.total_amount)} đ</b></p>
                    <p>Cảm ơn bạn đã mua sắm tại BROWN Fashion.</p>
                </div>
            `
        };

        await transporter.sendMail(mailOptions);
        console.log(`📧 Đã gửi mail vận đơn tới ${customerEmail}`);
    } catch (error) {
        console.error("❌ Email Error:", error);
    }
};

module.exports = { sendOrderConfirmation };
=======
const sendEmail = async (to, subject, text, html) => {
  // Kiểm tra biến môi trường
  if (!process.env.SMTP_USER || !process.env.SMTP_PASS) {
    console.warn('⚠️ EMAIL WARNING: Chưa cấu hình SMTP. Email không được gửi.');
    return null; 
  }

  try {
    const transporter = nodemailer.createTransport({
      host: process.env.SMTP_HOST || 'smtp.gmail.com',
      port: process.env.SMTP_PORT || 587,
      secure: false,
      auth: {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASS,
      },
    });

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
                    <p style="margin: 5px 0;"><strong>Tổng thanh toán:</strong> ${new Intl.NumberFormat('vi-VN').format(order.total_amount)*1000} đ</p>
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

module.exports = { sendEmail, sendOrderConfirmation };
>>>>>>> Frontend
