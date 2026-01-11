import { useEffect, useState } from 'react';
import axios from 'axios';
import { Link } from 'react-router-dom';

const Home = () => {
  const [products, setProducts] = useState([]);

  useEffect(() => {
    // Gọi API lấy sản phẩm từ Backend
    const fetchProducts = async () => {
      try {
        const res = await axios.get('http://localhost:5000/api/products');
        if (res.data.success) {
          setProducts(res.data.data);
        }
      } catch (error) {
        console.error("Lỗi lấy sản phẩm:", error);
      }
    };
    fetchProducts();
  }, []);

  return (
    <div className="min-h-screen bg-stone-50">
      {/* Banner */}
      <div className="h-[500px] bg-stone-200 flex items-center justify-center mb-10">
        <div className="text-center">
          <h2 className="text-4xl md:text-6xl font-light text-stone-800 mb-4 tracking-widest">NEW ARRIVALS</h2>
          <Link to="/collection" className="inline-block border-b border-stone-800 pb-1 uppercase text-sm tracking-widest hover:text-stone-600">Xem bộ sưu tập</Link>
        </div>
      </div>

      {/* Danh sách sản phẩm */}
      <div className="max-w-7xl mx-auto px-6 pb-20">
        <h3 className="text-2xl font-bold text-stone-800 mb-8 text-center font-serif">Sản Phẩm Mới Nhất</h3>
        
        <div className="grid grid-cols-2 md:grid-cols-4 gap-x-6 gap-y-10">
          {products.map((product) => (
            <Link to={`/product/${product.slug}`} key={product.id} className="group">
              {/* Ảnh sản phẩm */}
              <div className="aspect-[3/4] bg-stone-200 overflow-hidden rounded-sm mb-4 relative">
                {product.images?.[0] ? (
                  <img 
                    src={product.images[0]} 
                    alt={product.name} 
                    className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                  />
                ) : (
                  <div className="w-full h-full flex items-center justify-center text-stone-400">No Image</div>
                )}
                {/* Nút thêm nhanh (Hiện khi hover) */}
                <button className="absolute bottom-0 left-0 w-full bg-stone-900 text-white py-3 translate-y-full group-hover:translate-y-0 transition-transform duration-300 uppercase text-xs tracking-wider">
                  Xem chi tiết
                </button>
              </div>

              {/* Thông tin */}
              <div>
                <h4 className="font-medium text-stone-800 group-hover:text-stone-600 transition-colors">{product.name}</h4>
                <p className="text-stone-500 text-sm mt-1">
                  {new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(product.base_price)}
                </p>
              </div>
            </Link>
          ))}
        </div>
      </div>
    </div>
  );
};

export default Home;