import { lazy, Suspense, useEffect, useMemo, useState } from 'react';
import axios from 'axios';
import { FaPlus, FaSearch, FaEdit, FaTrash, FaFileExcel } from 'react-icons/fa';
import { toast } from 'react-toastify';
import { optimizeImage as getOptimizedImageUrl } from '../../utils/cloudinaryHelper';

const ProductModal = lazy(() => import('../../components/ProductModal'));

const Products = () => {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  
  const [searchTerm, setSearchTerm] = useState('');
  
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [selectedProduct, setSelectedProduct] = useState(null); 

  useEffect(() => {
    fetchProducts();
  }, []);

  const fetchProducts = async () => {
    try {
      const response = await axios.get(`${import.meta.env.VITE_API_URL}/api/products?admin=true&view=admin-list`);
      if (response.data.success) {
        setProducts(response.data.data);
      }
    } catch (error) {
      console.error("Lỗi lấy sản phẩm:", error);
    } finally {
      setLoading(false);
    }
  };

  const handleDelete = async (id, name) => {
    if (window.confirm(`Bạn có chắc muốn xóa sản phẩm "${name}"? Hành động này không thể hoàn tác.`)) {
        try {
            const res = await axios.delete(`${import.meta.env.VITE_API_URL}/api/products/${id}`);
            if (res.data.success) {
                toast.success("Đã xóa sản phẩm!");
                fetchProducts(); 
            }
        } catch (error) {
            toast.error("Lỗi xóa: " + (error.response?.data?.message || error.message));
        }
    }
  };

  const handleEdit = async (product) => {
      if (!product) return;
      try {
        const response = await axios.get(`${import.meta.env.VITE_API_URL}/api/products/${product.slug}?admin=true`);
        if (response.data.success) {
          setSelectedProduct(response.data.data);
          setIsModalOpen(true);
        }
      } catch (error) {
        toast.error('Không thể tải chi tiết sản phẩm: ' + (error.response?.data?.message || error.message));
      }
  };

  const handleCreate = () => {
      setSelectedProduct(null); 
      setIsModalOpen(true);
  };

  const filteredProducts = useMemo(() => products.filter(product =>
      product.name.toLowerCase().includes(searchTerm.toLowerCase())
  ), [products, searchTerm]);

  // Hàm xử lý xuất file Excel
  const handleExportSapo = async () => {
      try {
          const response = await fetch(`${import.meta.env.VITE_API_URL}/api/products/export/sapo`);
          const blob = await response.blob();
          
          // Tạo đường link ảo để trình duyệt tự tải file về
          const url = window.URL.createObjectURL(new Blob([blob]));
          const link = document.createElement('a');
          link.href = url;
          link.setAttribute('download', `Sapo_Products_Export_${new Date().toISOString().slice(0,10)}.xlsx`);
          document.body.appendChild(link);
          link.click();
          link.parentNode.removeChild(link);
      } catch (error) {
          console.error("Lỗi xuất file:", error);
          toast.error("Không thể xuất file Excel");
      }
  };

  return (
    <div className="p-4 md:p-6 max-w-7xl mx-auto">
      <div className="flex flex-col md:flex-row md:items-center justify-between mb-6 gap-4">
        <div>
          <h1 className="text-2xl font-bold text-stone-800">Sản phẩm</h1>
          <p className="text-stone-500 mt-1">Quản lý danh sách quần áo & phụ kiện</p>
        </div>
        
        <button 
            onClick={handleExportSapo}
            className="ml-auto bg-green-600 text-white px-6 py-3 rounded-lg flex items-center justify-center gap-2 hover:bg-stone-800 shadow-lg transition-all"
            //className="flex items-center gap-2 bg-green-600 hover:bg-green-700 text-white px-4 py-2 rounded shadow font-bold text-sm"
        >
            <FaFileExcel size={14} />
            Xuất file Sapo
        </button>

        <button 
            onClick={handleCreate} 
            className="bg-stone-900 text-white px-6 py-3 rounded-lg flex items-center justify-center gap-2 hover:bg-green-800 shadow-lg transition-all"
        >
          <FaPlus size={14} /> Thêm sản phẩm
        </button>
      </div>

      <div className="bg-white p-4 rounded-xl shadow-sm border border-stone-200 mb-6">
        <div className="relative">
            <FaSearch className="absolute left-4 top-1/2 -translate-y-1/2 text-stone-400" />
            <input 
                type="text" 
                placeholder="Tìm kiếm sản phẩm theo tên..." 
                className="w-full pl-10 pr-4 py-3 border border-stone-200 rounded-lg outline-none focus:border-stone-500 focus:ring-1 focus:ring-stone-500 transition-all"
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
            />
        </div>
      </div>

      <div className="bg-white rounded-xl shadow-sm border border-stone-200 overflow-hidden">
        {loading ? (
            <div className="p-10 text-center text-stone-500">Đang tải dữ liệu...</div>
        ) : (
            <div className="overflow-x-auto">
                <table className="w-full text-left border-collapse min-w-[1000px]">
                    <thead className="bg-stone-50 text-stone-600 uppercase text-xs tracking-wider font-bold">
                      <tr>
                        <th className="p-4 border-b border-stone-100 w-24">Hình ảnh</th>
                        <th className="p-4 border-b border-stone-100">Tên sản phẩm</th>
                        <th className="p-4 border-b border-stone-100">Giá bán</th>
                        <th className="p-4 border-b border-stone-100">Trạng thái</th>
                        <th className="p-4 border-b border-stone-100 text-right">Hành động</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-stone-100">
                      {filteredProducts.length > 0 ? (
                          filteredProducts.map((product) => (
                            <tr key={product.id} className={`transition-colors group ${!product.is_active ? 'bg-stone-50/70 opacity-60 hover:opacity-100' : 'hover:bg-stone-50'}`}>
                              <td className="p-4">
                                <div className="w-12 h-16 bg-stone-200 rounded overflow-hidden border border-stone-100">
                                    {product.images && product.images.length > 0 ? (
                                        <img 
                                            // [CHỈNH SỬA] Thêm nén ảnh
                                            src={getOptimizedImageUrl(product.images[0], 100)} 
                                            alt={product.name} 
                                            className="w-full h-full object-cover" 
                                            loading="lazy" 
                                            decoding="async" 
                                        />
                                    ) : (
                                        <div className="w-full h-full flex items-center justify-center text-xs text-stone-400">No Img</div>
                                    )}
                                </div>
                              </td>
                              <td className="p-4 font-medium text-stone-800">
                                  {product.name}
                                  <div className="text-xs text-stone-400 font-normal mt-0.5">{product.slug}</div>
                              </td>
                              <td className="p-4 font-bold text-stone-900">{new Intl.NumberFormat('vi-VN').format(product.base_price)} ₫</td>
                              
                              <td className="p-4">
                                {product.is_active !== false ? (
                                    <span className="text-green-600 bg-green-50 px-2 py-1 rounded text-xs font-medium border border-green-100">
                                      Hiển thị
                                    </span>
                                ) : (
                                    <span className="text-stone-500 bg-stone-100 px-2 py-1 rounded text-xs font-medium border border-stone-200">
                                      Đã ẩn
                                    </span>
                                )}
                              </td>

                              <td className="p-4 text-right">
                                <div className="flex items-center justify-end gap-3">
                                  <button 
                                    onClick={() => handleEdit(product)}
                                    className="text-stone-400 hover:text-blue-600 transition-colors p-2 rounded-full hover:bg-blue-50" title="Chỉnh sửa"
                                  >
                                    <FaEdit size={18} />
                                  </button>
                                  
                                  <button 
                                    onClick={() => handleDelete(product.id, product.name)}
                                    className="text-stone-400 hover:text-red-600 transition-colors p-2 rounded-full hover:bg-red-50" title="Xóa"
                                  >
                                    <FaTrash size={18} />
                                  </button>
                                </div>
                              </td>
                            </tr>
                          ))
                      ) : (
                          <tr>
                              <td colSpan="5" className="p-8 text-center text-stone-500">
                                  Không tìm thấy sản phẩm nào khớp với "{searchTerm}"
                              </td>
                          </tr>
                      )}
                    </tbody>
                </table>
            </div>
        )}
      </div>

      {isModalOpen && (
        <Suspense fallback={<div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 text-white">Đang mở trình chỉnh sửa...</div>}>
          <ProductModal
            isOpen
            onClose={() => setIsModalOpen(false)}
            onSuccess={fetchProducts}
            productToEdit={selectedProduct}
          />
        </Suspense>
      )}
    </div>
  );
};

export default Products;
