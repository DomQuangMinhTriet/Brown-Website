import React from 'react';

const ShippingPolicy = () => {
  return (
    <div className="max-w-4xl mx-auto px-6 py-12 text-stone-700 leading-relaxed">
      <h1 className="text-3xl font-serif font-bold text-stone-900 mb-8 text-center uppercase">Chính sách vận chuyển</h1>
      
      <div className="space-y-6">
        <section>
          <h2 className="font-bold text-lg text-stone-900 mb-2">1. Phí vận chuyển</h2>
          <p>Brown áp dụng mức phí vận chuyển đồng giá: 20.000đ</p>
        </section>

        <section>
          <h2 className="font-bold text-lg text-stone-900 mb-2">2. Thời gian giao hàng</h2>
          <p>
            Thời gian giao hàng dự kiến từ <strong>2-5 ngày</strong> tùy thuộc vào địa chỉ nhận hàng của quý khách.
            Đơn hàng nội thành có thể nhận ngay trong ngày nếu đặt ship hỏa tốc (vui lòng inbox Instagram).
          </p>
        </section>
      </div>
    </div>
  );
};

export default ShippingPolicy;