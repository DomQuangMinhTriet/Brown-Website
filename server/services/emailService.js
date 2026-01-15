const nodemailer = require('nodemailer');

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