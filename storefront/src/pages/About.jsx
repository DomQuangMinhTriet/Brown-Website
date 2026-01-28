// import React from 'react';
// import { Link } from 'react-router-dom';
// import { FaGem, FaLeaf, FaShippingFast, FaCheckCircle } from 'react-icons/fa';

// const About = () => {
//   return (
//     <div className="bg-white min-h-screen pb-20">
      
//       {/* 1. HERO SECTION - Tiêu đề lớn */}
//       <div className="relative w-full h-[400px] bg-stone-100 flex items-center justify-center mb-16">
//         {/* Nếu bạn có ảnh banner đẹp, bỏ comment dòng dưới và thay link ảnh */}
//         {/* <img src="URL_ANH_BANNER" className="absolute inset-0 w-full h-full object-cover opacity-50" /> */}
        
//         <div className="relative z-10 text-center px-4">
//           <h1 className="text-4xl md:text-6xl font-bold text-stone-800 mb-4 tracking-wider">
//             VỀ BROWN
//           </h1>
//           <p className="text-stone-500 text-lg max-w-2xl mx-auto">
//             Không chỉ là thời trang, chúng tôi mang đến phong cách sống tối giản và tinh tế dành cho phái đẹp.
//           </p>
//         </div>
//       </div>

//       <div className="container mx-auto px-6 md:px-12">
        
//         {/* 2. CÂU CHUYỆN THƯƠNG HIỆU (Chia đôi màn hình) */}
//         <div className="flex flex-col md:flex-row items-center gap-12 mb-24">
//           {/* Cột Ảnh */}
//           <div className="w-full md:w-1/2">
//             <div className="aspect-[4/5] bg-stone-200 rounded-xl overflow-hidden shadow-lg">
//               <img 
//                 src="https://images.unsplash.com/photo-1490481651871-ab68de25d43d?q=80&w=2070&auto=format&fit=crop" 
//                 alt="Our Story" 
//                 className="w-full h-full object-cover hover:scale-105 transition-transform duration-700"
//               />
//             </div>
//           </div>
          
//           {/* Cột Chữ */}
//           <div className="w-full md:w-1/2 space-y-6">
//             <h2 className="text-3xl font-bold text-stone-800">Hành Trình Của Chúng Tôi</h2>
//             <p className="text-stone-600 leading-relaxed text-justify">
//               BROWN được thành lập với niềm tin rằng thời trang không cần phải quá cầu kỳ để trở nên nổi bật. Chúng tôi bắt đầu từ một cửa hàng nhỏ với những thiết kế tập trung vào chất liệu tự nhiên và đường cắt may tinh tế.
//             </p>
//             <p className="text-stone-600 leading-relaxed text-justify">
//               Sứ mệnh của chúng tôi là giúp phụ nữ hiện đại tìm thấy sự tự tin qua những trang phục thoải mái, bền vững nhưng vẫn đầy khí chất. Mỗi sản phẩm tại BROWN đều được chăm chút tỉ mỉ từ khâu chọn vải đến từng đường kim mũi chỉ.
//             </p>
            
//             <div className="pt-4">
//                 <div className="flex items-center gap-3 mb-2">
//                     <FaCheckCircle className="text-stone-800" /> 
//                     <span className="text-stone-700 font-medium">Thiết kế độc quyền</span>
//                 </div>
//                 <div className="flex items-center gap-3 mb-2">
//                     <FaCheckCircle className="text-stone-800" /> 
//                     <span className="text-stone-700 font-medium">Chất liệu cao cấp</span>
//                 </div>
//                 <div className="flex items-center gap-3">
//                     <FaCheckCircle className="text-stone-800" /> 
//                     <span className="text-stone-700 font-medium">Bền vững với thời gian</span>
//                 </div>
//             </div>
//           </div>
//         </div>

//         {/* 3. GIÁ TRỊ CỐT LÕI (3 Cột) */}
//         <div className="mb-24">
//             <div className="text-center mb-12">
//                 <h2 className="text-3xl font-bold text-stone-800 mb-4">Tại Sao Chọn BROWN?</h2>
//                 <div className="w-20 h-1 bg-stone-800 mx-auto"></div>
//             </div>

//             <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
//                 {/* Box 1 */}
//                 <div className="bg-stone-50 p-8 rounded-xl text-center hover:-translate-y-2 transition-transform duration-300 border border-stone-100 shadow-sm">
//                     <div className="w-16 h-16 bg-white rounded-full flex items-center justify-center mx-auto mb-6 shadow text-stone-800 text-2xl">
//                         <FaGem />
//                     </div>
//                     <h3 className="text-xl font-bold text-stone-800 mb-3">Chất Lượng Hàng Đầu</h3>
//                     <p className="text-stone-500 text-sm leading-relaxed">
//                         Chúng tôi cam kết sử dụng những chất liệu vải tốt nhất, mang lại cảm giác thoải mái tuyệt đối cho người mặc.
//                     </p>
//                 </div>

//                 {/* Box 2 */}
//                 <div className="bg-stone-50 p-8 rounded-xl text-center hover:-translate-y-2 transition-transform duration-300 border border-stone-100 shadow-sm">
//                     <div className="w-16 h-16 bg-white rounded-full flex items-center justify-center mx-auto mb-6 shadow text-stone-800 text-2xl">
//                         <FaLeaf />
//                     </div>
//                     <h3 className="text-xl font-bold text-stone-800 mb-3">Thời Trang Bền Vững</h3>
//                     <p className="text-stone-500 text-sm leading-relaxed">
//                         Quy trình sản xuất thân thiện với môi trường, hạn chế rác thải và tôn trọng sức lao động của người thợ.
//                     </p>
//                 </div>

//                 {/* Box 3 */}
//                 <div className="bg-stone-50 p-8 rounded-xl text-center hover:-translate-y-2 transition-transform duration-300 border border-stone-100 shadow-sm">
//                     <div className="w-16 h-16 bg-white rounded-full flex items-center justify-center mx-auto mb-6 shadow text-stone-800 text-2xl">
//                         <FaShippingFast />
//                     </div>
//                     <h3 className="text-xl font-bold text-stone-800 mb-3">Dịch Vụ Tận Tâm</h3>
//                     <p className="text-stone-500 text-sm leading-relaxed">
//                         Giao hàng nhanh chóng, chính sách đổi trả linh hoạt và đội ngũ tư vấn luôn sẵn sàng hỗ trợ bạn.
//                     </p>
//                 </div>
//             </div>
//         </div>

//         {/* 4. NEWSLETTER / CTA */}
//         <div className="bg-stone-900 rounded-2xl p-10 md:p-16 text-center text-white relative overflow-hidden">
//             <div className="relative z-10">
//                 <h2 className="text-3xl md:text-4xl font-bold mb-4">Sẵn sàng thay đổi phong cách?</h2>
//                 <p className="text-stone-300 mb-8 max-w-xl mx-auto">
//                     Khám phá bộ sưu tập mới nhất của chúng tôi ngay hôm nay và nhận ưu đãi đặc biệt cho đơn hàng đầu tiên.
//                 </p>
//                 <Link 
//                     to="/collection" 
//                     className="inline-block bg-white text-stone-900 px-8 py-3 rounded-full font-bold hover:bg-stone-200 transition-colors shadow-lg"
//                 >
//                     Xem Sản Phẩm
//                 </Link>
//             </div>
            
//             {/* Họa tiết trang trí mờ */}
//             <div className="absolute top-0 left-0 w-64 h-64 bg-white opacity-5 rounded-full -translate-x-1/2 -translate-y-1/2"></div>
//             <div className="absolute bottom-0 right-0 w-96 h-96 bg-white opacity-5 rounded-full translate-x-1/3 translate-y-1/3"></div>
//         </div>

//       </div>
//     </div>
//   );
// };

// export default About;