import React from 'react';
import SEO from '../../components/SEO'; // Nếu bạn đã có component SEO

const ReturnPolicy = () => {
  return (
    <div className="max-w-4xl mx-auto px-6 py-12 text-stone-700 leading-relaxed">
      {/* <SEO title="Chính sách đổi trả - Brown" /> */}
      
      <h1 className="text-3xl font-serif font-bold text-stone-900 mb-8 text-center uppercase">Chính sách đổi trả</h1>
      
      <div className="space-y-6">
        <section>
          <h2 className="font-bold text-lg text-stone-900 mb-2">1. Điều kiện đổi trả</h2>
          <ul className="list-disc pl-5 space-y-1">
            <li>Sản phẩm còn nguyên tem mác, chưa qua sử dụng, giặt là.</li>
            <li>Thời gian đổi trả trong vòng <strong>07 ngày</strong> kể từ ngày nhận hàng.</li>
            <li>Sản phẩm bị lỗi do nhà sản xuất hoặc hư hỏng trong quá trình vận chuyển.</li>
          </ul>
        </section>

        <section>
          <h2 className="font-bold text-lg text-stone-900 mb-2">2. Quy trình đổi trả</h2>
          <p>
            Quý khách vui lòng liên hệ qua Fanpage hoặc Hotline 090xxxxxxx để được hướng dẫn.
            Sau khi xác nhận, quý khách gửi hàng về địa chỉ kho của Brown. Phí vận chuyển chiều đi sẽ do quý khách thanh toán (trừ trường hợp lỗi do Brown).
          </p>
        </section>

        <section>
          <h2 className="font-bold text-lg text-stone-900 mb-2">3. Hoàn tiền</h2>
          <p>
            Đối với các đơn hàng thanh toán trước, Brown sẽ hoàn tiền vào tài khoản ngân hàng của quý khách trong vòng 3-5 ngày làm việc sau khi nhận được hàng trả về hợp lệ.
          </p>
        </section>
      </div>
    </div>
  );
};

export default ReturnPolicy;