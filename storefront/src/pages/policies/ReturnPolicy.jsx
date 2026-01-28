import React from 'react';
import SEO from '../../components/SEO'; // Nếu bạn đã có component SEO

const ReturnPolicy = () => {
  return (
    <div className="max-w-4xl mx-auto px-6 py-12 text-stone-700 leading-relaxed">
      {/* <SEO title="Chính sách đổi trả - Brown" /> */}
      
      <h1 className="text-3xl font-serif font-bold text-stone-900 mb-8 text-center uppercase">Chính sách đổi hàng</h1>
      
      <div className="space-y-6">
        <section>
          <h2 className="font-bold text-lg text-stone-900 mb-2">1. Điều kiện đổi hàng</h2>
          <ul className="list-disc pl-5 space-y-1">
            <li>Sản phẩm còn nguyên tem mác, chưa qua sử dụng, giặt ủi.</li>
            <li>Thời gian đổi trả trong vòng <strong>03 ngày</strong> kể từ ngày nhận hàng.</li>
            <li>Sản phẩm bị lỗi do nhà sản xuất hoặc do BROWN tư vấn sai kích thước.</li>
          </ul>
        </section>

        <section>
          <h2 className="font-bold text-lg text-stone-900 mb-2">2. Quy trình đổi hàng</h2>
          <p>
            Quý khách vui lòng liên hệ qua Instagram hoặc Zalo 090.695.4860 để được hướng dẫn.
            Sau khi xác nhận, quý khách gửi hàng về địa chỉ kho của BROWN. Tổng phí vận chuyển đổi hàng sẽ do BROWN thanh toán.
          </p>
        </section>
        
      </div>
    </div>
  );
};

export default ReturnPolicy;