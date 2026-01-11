import { useEffect, useState } from 'react';
import axios from 'axios';
import { FaPlus, FaSearch, FaEdit, FaTrash } from 'react-icons/fa';
import ProductModal from '../components/ProductModal'; // <--- IMPORT MODAL

const Products = () => {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [isModalOpen, setIsModalOpen] = useState(false); // <--- State bật tắt modal

  useEffect(() => {
    fetchProducts();
  }, []);

  const fetchProducts = async () => {
    try {
      const response = await axios.get('http://localhost:5000/api/products');
      if (response.data.success) {
        setProducts(response.data.data);
      }
    } catch (error) {
      console.error("Lỗi lấy sản phẩm:", error);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="p-6 md:p-10 max-w-7xl mx-auto">
      <div className="flex flex-col md:flex-row md:items-center justify-between mb-8 gap-4">
        <div>
          <h1 className="text-2xl font-bold text-stone-800">Sản phẩm</h1>
          <p className="text-stone-500 mt-1">Quản lý danh sách quần áo & phụ kiện</p>
        </div>
        
        {/* Nút mở Modal */}
        <button 
          onClick={() => setIsModalOpen(true)} // <--- Sự kiện Click
          className="bg-stone-900 hover:bg-stone-800 text-white px-5 py-2.5 rounded-lg flex items-center gap-2 transition-colors shadow-lg shadow-stone-900/20"
        >
          <FaPlus size={14} />
          <span>Thêm sản phẩm mới</span>
        </button>
      </div>

      {/* --- Giữ nguyên phần Thanh tìm kiếm --- */}
      <div className="bg-white p-4 rounded-xl border border-stone-200 shadow-sm mb-6 flex flex-col md:flex-row gap-4 justify-between">
         {/* ... (Code cũ giữ nguyên) ... */}
         <div className="relative w-full md:w-96">
            <FaSearch className="absolute left-3 top-1/2 -translate-y-1/2 text-stone-400" />
            <input type="text" placeholder="Tìm kiếm..." className="w-full pl-10 pr-4 py-2 bg-stone-50 border border-stone-200 rounded-lg outline-none" />
         </div>
      </div>

      {/* --- Giữ nguyên phần Bảng dữ liệu --- */}
      <div className="bg-white rounded-xl border border-stone-200 shadow-sm overflow-hidden">
        {/* ... (Code Table cũ giữ nguyên hoàn toàn) ... */}
        {loading ? <div className="p-10 text-center">Đang tải...</div> : (
            <div className="overflow-x-auto">
                <table className="w-full text-left border-collapse">
                    <thead className="bg-stone-50 text-stone-500 text-xs uppercase tracking-wider font-semibold">
                        <tr>
                            <th className="p-4 w-16">Ảnh</th>
                            <th className="p-4">Tên sản phẩm</th>
                            <th className="p-4">Giá bán</th>
                            <th className="p-4">Tồn kho</th>
                        </tr>
                    </thead>
                    <tbody className="divide-y divide-stone-100">
                      {products.map((product) => (
                        <tr key={product.id} className="hover:bg-stone-50/60 group"> {/* Thêm class group */}
                          
                          {/* 1. Sửa phần hiển thị ảnh: Thêm ảnh mặc định nếu lỗi */}
                          <td className="p-4">
                            <div className="w-12 h-16 bg-stone-200 rounded overflow-hidden border border-stone-100">
                              {product.images && product.images.length > 0 ? (
                                <img 
                                  src={product.images[0]} 
                                  alt={product.name} 
                                  className="w-full h-full object-cover"
                                  onError={(e) => {e.target.src = 'https://via.placeholder.com/150?text=No+Img'}} // Fallback nếu ảnh lỗi
                                />
                              ) : (
                                <div className="flex items-center justify-center h-full text-xs text-stone-400 bg-stone-100">No img</div>
                              )}
                            </div>
                          </td>

                          <td className="p-4 font-medium text-stone-800">{product.name}</td>
                          
                          <td className="p-4 font-medium">
                            {new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(product.base_price)}
                          </td>
                          
                          <td className="p-4">
                            <span className="text-green-600 bg-green-50 px-2 py-1 rounded text-xs font-medium border border-green-100">
                              Sẵn hàng
                            </span>
                          </td>

                          {/* 2. Sửa phần nút bấm: Xóa opacity-0 để nút LUÔN HIỆN */}
                          <td className="p-4 text-right">
                            <div className="flex items-center justify-end gap-3"> {/* Bỏ opacity-0 */}
                              <button className="text-stone-400 hover:text-blue-600 transition-colors" title="Chỉnh sửa">
                                <FaEdit size={18} />
                              </button>
                              <button className="text-stone-400 hover:text-red-600 transition-colors" title="Xóa">
                                <FaTrash size={18} />
                              </button>
                            </div>
                          </td>

                        </tr>
                      ))}
                    </tbody>
                </table>
            </div>
        )}
      </div>

      {/* --- HIỂN THỊ MODAL --- */}
      <ProductModal 
        isOpen={isModalOpen} 
        onClose={() => setIsModalOpen(false)} 
        onSuccess={fetchProducts} // Refresh lại list sau khi thêm
      />
    </div>
  );
};

export default Products;