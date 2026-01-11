import { useEffect, useState } from 'react';
import axios from 'axios';
import { Link } from 'react-router-dom';

const Collection = () => {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchProducts = async () => {
      try {
        const res = await axios.get('http://localhost:5000/api/products');
        if (res.data.success) {
          setProducts(res.data.data);
        }
      } catch (error) {
        console.error("Lỗi tải sản phẩm:", error);
      } finally {
        setLoading(false);
      }
    };
    fetchProducts();
  }, []);

  return (
    <div className="max-w-7xl mx-auto px-6 py-12">
      <div className="text-center mb-16">
        <h1 className="text-4xl font-serif text-stone-900 mb-4">Tất Cả Sản Phẩm</h1>
        <p className="text-stone-500">Khám phá những thiết kế mới nhất từ BROWN</p>
      </div>

      {loading ? (
        <div className="text-center py-20 text-stone-400">Đang tải danh sách...</div>
      ) : (
        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-x-6 gap-y-10">
          {products.map((product) => (
            <Link to={`/product/${product.slug}`} key={product.id} className="group block">
              <div className="aspect-[3/4] bg-stone-100 mb-4 overflow-hidden relative">
                {product.images?.[0] ? (
                  <img 
                    src={product.images[0]} 
                    alt={product.name} 
                    className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                  />
                ) : (
                  <div className="w-full h-full flex items-center justify-center text-stone-300 bg-stone-50">No Image</div>
                )}
                {/* Nút xem nhanh */}
                <div className="absolute inset-x-0 bottom-0 p-4 translate-y-full group-hover:translate-y-0 transition-transform duration-300">
                  <button className="w-full bg-white/90 backdrop-blur text-stone-900 py-3 text-xs uppercase tracking-widest font-bold hover:bg-stone-900 hover:text-white transition-colors">
                    Xem chi tiết
                  </button>
                </div>
              </div>
              
              <div>
                <h3 className="font-medium text-stone-900 text-sm group-hover:text-stone-600 transition-colors">
                  {product.name}
                </h3>
                <p className="text-stone-500 text-sm mt-1">
                  {new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(product.base_price)}
                </p>
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
};

export default Collection;