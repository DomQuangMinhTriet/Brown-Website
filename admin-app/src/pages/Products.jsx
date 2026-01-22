import { useEffect, useState } from 'react';
import axios from 'axios';
import { FaPlus, FaSearch, FaEdit, FaTrash } from 'react-icons/fa';
import ProductModal from '../components/ProductModal';
import { toast } from 'react-toastify'; // Nhớ import toast

const Products = () => {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  
  // State Modal
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [selectedProduct, setSelectedProduct] = useState(null); // [MỚI] Lưu sản phẩm đang sửa

  useEffect(() => {
    fetchProducts();
  }, []);

  const fetchProducts = async () => {
    try {
      const response = await axios.get(`${import.meta.env.VITE_API_URL}/api/products`);
      if (response.data.success) {
        setProducts(response.data.data);
      }
    } catch (error) {
      console.error("Lỗi lấy sản phẩm:", error);
    } finally {
      setLoading(false);
    }
  };

  // --- [MỚI] HÀM XÓA SẢN PHẨM ---
  const handleDelete = async (id, name) => {
    if (window.confirm(`Bạn có chắc muốn xóa sản phẩm "${name}"? Hành động này không thể hoàn tác.`)) {
        try {
            const res = await axios.delete(`${import.meta.env.VITE_API_URL}/api/products/${id}`);
            if (res.data.success) {
                toast.success("Đã xóa sản phẩm!");
                fetchProducts(); // Load lại danh sách
            }
        } catch (error) {
            toast.error("Lỗi xóa: " + (error.response?.data?.message || error.message));
        }
    }
  };

  // Hàm này phải set sản phẩm vào state rồi mới mở Modal
  const handleEdit = (product) => {
      if (!product) return;
      console.log("Đang sửa sản phẩm:", product); // <--- Thêm dòng này để check
      setSelectedProduct(product); 
      setIsModalOpen(true);        
  };

  // --- [MỚI] HÀM MỞ MODAL THÊM MỚI ---
  const handleCreate = () => {
      setSelectedProduct(null); // Reset về null để Modal biết là đang tạo mới
      setIsModalOpen(true);
  };

  return (
    <div className="p-6 md:p-10 max-w-7xl mx-auto">
      <div className="flex flex-col md:flex-row md:items-center justify-between mb-8 gap-4">
        <div>
          <h1 className="text-2xl font-bold text-stone-800">Sản phẩm</h1>
          <p className="text-stone-500 mt-1">Quản lý danh sách quần áo & phụ kiện</p>
        </div>
        
        {/* Sửa nút Thêm mới gọi hàm handleCreate */}
        <button 
            onClick={handleCreate} 
            className="bg-stone-900 text-white px-6 py-3 rounded-lg flex items-center gap-2 hover:bg-stone-800 shadow-lg transition-all"
        >
          <FaPlus size={14} /> Thêm sản phẩm
        </button>
      </div>

      {/* ... (Phần tìm kiếm giữ nguyên) ... */}

      <div className="bg-white rounded-xl shadow-sm border border-stone-200 overflow-hidden">
        {loading ? (
            <div className="p-10 text-center text-stone-500">Đang tải dữ liệu...</div>
        ) : (
            <div className="overflow-x-auto">
                <table className="w-full text-left border-collapse">
                    <thead className="bg-stone-50 text-stone-600 uppercase text-xs tracking-wider font-bold">
                      <tr>
                        <th className="p-4 border-b border-stone-100">Hình ảnh</th>
                        <th className="p-4 border-b border-stone-100">Tên sản phẩm</th>
                        <th className="p-4 border-b border-stone-100">Giá bán</th>
                        <th className="p-4 border-b border-stone-100">Trạng thái</th>
                        <th className="p-4 border-b border-stone-100 text-right">Hành động</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-stone-100">
                      {products.map((product) => (
                        <tr key={product.id} className="hover:bg-stone-50 transition-colors group">
                          <td className="p-4">
                            <div className="w-12 h-16 bg-stone-200 rounded overflow-hidden border border-stone-100">
                                {product.images && product.images.length > 0 ? (
                                    <img src={product.images[0]} alt={product.name} className="w-full h-full object-cover" />
                                ) : (
                                    <div className="w-full h-full flex items-center justify-center text-xs text-stone-400">No Img</div>
                                )}
                            </div>
                          </td>
                          <td className="p-4 font-medium text-stone-800">{product.name}</td>
                          <td className="p-4 font-bold text-stone-900">{new Intl.NumberFormat('vi-VN').format(product.base_price)} ₫</td>
                          
                          <td className="p-4">
                            <span className="text-green-600 bg-green-50 px-2 py-1 rounded text-xs font-medium border border-green-100">
                              Sẵn hàng
                            </span>
                          </td>

                          {/* CỘT HÀNH ĐỘNG */}
                          <td className="p-4 text-right">
                            <div className="flex items-center justify-end gap-3">
                              {/* Nút Sửa */}
                              <button 
                                onClick={() => handleEdit(product)}
                                className="text-stone-400 hover:text-blue-600 transition-colors" title="Chỉnh sửa"
                              >
                                <FaEdit size={18} />
                              </button>
                              
                              {/* Nút Xóa */}
                              <button 
                                onClick={() => handleDelete(product.id, product.name)}
                                className="text-stone-400 hover:text-red-600 transition-colors" title="Xóa"
                              >
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

      {/* --- TRUYỀN selectedProduct VÀO MODAL --- */}
      <ProductModal 
        isOpen={isModalOpen} 
        onClose={() => setIsModalOpen(false)} 
        onSuccess={fetchProducts}
        productToEdit={selectedProduct} // [MỚI] Truyền sản phẩm cần sửa vào
      />
    </div>
  );
};

export default Products;