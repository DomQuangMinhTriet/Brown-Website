// server/services/emailService.js
const { Resend } = require('resend');
require('dotenv').config();

// KHỞI TẠO RESEND (Thay thế cho Nodemailer Transporter)
const resend = new Resend(process.env.RESEND_API_KEY);

// CẤU HÌNH CỐ ĐỊNH (Vì bạn đã có domain brownvn.com)
const SENDER_EMAIL = 'BROWN <donhang@brownvn.com>'; 
const ADMIN_EMAIL = 'brownvn25@gmail.com'; 

// --- [MỚI] HELPER: FORMAT TIỀN TỆ ---
const formatMoney = (amount) => {
    return new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(amount);
};

// --- [MỚI] HELPER: TẠO HTML DANH SÁCH SẢN PHẨM ---
const generateProductRows = (items) => {
    if (!items || items.length === 0) return '';

    return items.map(item => {
        // Xử lý lấy tên: Ưu tiên lấy từ cấu trúc lồng nhau (variants -> products -> name)
        let productName = "Sản phẩm";
        if (item.variants?.products?.name) productName = item.variants.products.name;
        else if (item.product_name) productName = item.product_name; // Fallback
        else if (item.name) productName = item.name;

        // Xử lý lấy Size/Màu
        let variantInfo = "";
        if (item.variants) {
            variantInfo = `${item.variants.size || ''} / ${item.variants.color || ''}`;
        } else {
            variantInfo = `${item.size || ''} / ${item.color || ''}`;
        }

        return `
            <tr style="border-bottom: 1px solid #eee;">
                <td style="padding: 8px 0; color: #444;">
                    <div style="font-weight: bold; font-size: 13px;">${productName}</div>
                    <div style="font-size: 11px; color: #888;">${variantInfo}</div>
                </td>
                <td style="padding: 8px 0; text-align: center; font-size: 13px;">x${item.quantity}</td>
                <td style="padding: 8px 0; text-align: right; font-weight: bold; font-size: 13px;">${formatMoney(item.price)}</td>
            </tr>
        `;
    }).join('');
};

// --- HÀM GỬI MAIL LÕI (DÙNG API RESEND) ---
const sendViaResend = async (toEmail, subject, htmlContent) => {
    try {
        const { data, error } = await resend.emails.send({
            from: SENDER_EMAIL,
            to: [toEmail],
            subject: subject,
            html: htmlContent,
        });

        if (error) {
            console.error('❌ Lỗi Resend:', error);
            return null;
        }

        console.log(`✅ Đã gửi mail tới ${toEmail} | ID: ${data.id}`);
        return data;
    } catch (err) {
        console.error('❌ Lỗi ngoại lệ gửi mail:', err.message);
        return null;
    }
};

// 1. HÀM GỬI MAIL CƠ BẢN (Giữ nguyên tên để không lỗi Controller)
const sendEmail = async (to, subject, text, html) => {
    // Gọi hàm lõi ở trên
    return await sendViaResend(to, subject, html || text);
};

// 2. GỬI XÁC NHẬN ĐƠN HÀNG (Đã chèn thêm bảng sản phẩm)
const sendOrderConfirmation = async (order, customerEmail) => {
    if (!customerEmail) return;

    const formattedPrice = formatMoney(order.total_amount);
    
    // [MỚI] Tạo danh sách sản phẩm
    const items = order.items || order.order_items || [];
    const productRows = generateProductRows(items);

    const subject = `[BROWN] Xác nhận đơn hàng #${order.code || order.id}`; // Fallback nếu code null
    
    // GIỮ NGUYÊN HTML CŨ CỦA BẠN & CHÈN THÊM BẢNG SẢN PHẨM
    const htmlContent = `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; border: 1px solid #eee; border-radius: 8px; overflow: hidden;">
            <div style="background-color: #1c1917; color: white; padding: 20px; text-align: center;">
                <h2 style="margin: 0;">ĐƠN HÀNG ĐÃ ĐƯỢC GHI NHẬN</h2>
            </div>
            <div style="padding: 20px;">
                <p>Xin chào <b>${order.customer_name}</b>,</p>
                <p>Cảm ơn bạn đã đặt hàng tại BROWN. Đơn hàng <b>${order.code || order.id}</b> của bạn đã được khởi tạo.</p>
                
                <div style="margin: 20px 0;">
                    <p style="font-weight:bold; border-bottom: 2px solid #1c1917; padding-bottom: 5px;">Chi tiết đơn hàng:</p>
                    <table style="width: 100%; border-collapse: collapse;">
                        ${productRows}
                    </table>
                </div>
                <div style="background: #f5f5f4; padding: 15px; margin: 20px 0; border-radius: 5px; border-left: 4px solid #1c1917;">
                    <p style="margin: 5px 0;"><strong>Tổng thanh toán:</strong> ${formattedPrice}</p>
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

    return await sendViaResend(customerEmail, subject, htmlContent);
};

// 3. GỬI THÔNG BÁO VẬN CHUYỂN (Giữ nguyên HTML cũ)
const sendShippingConfirmation = async (order, trackingCode) => {
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

    return await sendViaResend(email, subject, htmlContent);
};

// 4. GỬI THÔNG BÁO CHO ADMIN (Sửa để dùng Resend gửi về Gmail của bạn)
const sendNewOrderNotifyToAdmin = async (orderData) => {
    // Format tiền tệ
    const formattedPrice = formatMoney(orderData.total_amount);
    
    // [MỚI] Tạo danh sách sản phẩm
    const items = orderData.items || orderData.order_items || [];
    const productRows = generateProductRows(items);

    const subject = `🔔 Đơn mới #${orderData.id} - ${formattedPrice}`;
    
    // GIỮ NGUYÊN HTML CŨ & CHÈN THÊM BẢNG
    const htmlContent = `
        <div style="font-family: Arial, sans-serif;">
            <h3>Bạn có đơn hàng mới!</h3>
            <p>Mã đơn: <strong>${orderData.id}</strong></p>
            <p>Khách hàng: ${orderData.customer_name}</p>
            <p>SĐT: ${orderData.phone}</p>
            
            <table style="width: 100%; border-collapse: collapse; margin: 15px 0; border: 1px solid #ddd;">
                <tr style="background:#f9f9f9; font-weight:bold;">
                    <td style="padding:8px; border:1px solid #ddd;">Sản phẩm</td>
                    <td style="padding:8px; border:1px solid #ddd;">SL</td>
                    <td style="padding:8px; border:1px solid #ddd;">Giá</td>
                </tr>
                ${productRows}
            </table>
            <p>Tổng tiền: <span style="color:red; font-weight:bold">${formattedPrice}</span></p>
            <p>Thanh toán: ${orderData.payment_method}</p>
        </div>
    `;

    // Gửi trực tiếp vào email ADMIN_EMAIL (brownvn25@gmail.com)
    return await sendViaResend(ADMIN_EMAIL, subject, htmlContent);
};

module.exports = { sendEmail, sendOrderConfirmation, sendShippingConfirmation, sendNewOrderNotifyToAdmin };