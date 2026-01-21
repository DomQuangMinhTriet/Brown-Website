import { useState, useEffect, useRef } from 'react';
import axios from 'axios';
import { FaTimes, FaUpload, FaTrash, FaPlus } from 'react-icons/fa';
import { toast } from 'react-toastify';

const ProductModal = ({ isOpen, onClose, onSuccess, productToEdit }) => {
  // State Form
  const [formData, setFormData] = useState({
    name: '',
    slug: '',
    base_price: '',
    description: '',
    category_id: ''
  });
  const [images, setImages] = useState([]);
  const [variants, setVariants] = useState([]);
  
  // State phụ trợ
  const [categories, setCategories] = useState([]);
  const [isCreatingCat, setIsCreatingCat] = useState(false);
  const [newCatName, setNewCatName] = useState('');
  
  // State thêm biến thể con
  const [currentVariant, setCurrentVariant] = useState({ size: '', color: '', sku: '' });
  
  const fileInputRef = useRef(null);

  // 1. NẠP DỮ LIỆU KHI MỞ MODAL (QUAN TRỌNG NHẤT)
  useEffect(() => {
    if (isOpen) {
      fetchCategories();

      if (productToEdit) {
        // --- CHẾ ĐỘ SỬA ---
        console.log("📝 Đang nạp dữ liệu sửa:", productToEdit);
        setFormData({
            name: productToEdit.name || '',
            slug: productToEdit.slug || '',
            base_price: productToEdit.base_price || 0,
            description: productToEdit.description || '',
            category_id: productToEdit.category_id || ''
        });

        // Bảo vệ mảng ảnh (nếu null thì thành mảng rỗng)
        setImages(productToEdit.images || []);

        // Bảo vệ variants
        const safeVariants = productToEdit.variants || [];
        const formattedVariants = safeVariants.map(v => ({
            size: v.size || '',
            color: v.color || '',
            sku: v.sku || ''
        }));
        setVariants(formattedVariants);

      } else {
        // --- CHẾ ĐỘ THÊM MỚI (RESET FORM) ---
        setFormData({ name: '', slug: '', base_price: '', description: '', category_id: '' });
        setImages([]);
        setVariants([]);
      }
      
      // Reset input variant nhỏ
      setCurrentVariant({ size: '', color: '', sku: '' });
    }
  }, [isOpen, productToEdit]);

  const fetchCategories = async () => {
    try {
      const res = await axios.get('http://localhost:5000/api/categories');
      if(res.data.success) setCategories(res.data.data);
    } catch (err) { console.error(err); }
  };

  // 2. CÁC HÀM XỬ LÝ (Upload, Thêm biến thể...)
  const handleFileUpload = async (e) => {
    const file = e.target.files[0];
    if (!file) return;
    
    const formDataUpload = new FormData();
    formDataUpload.append('image', file);

    try {
      // Đang upload...
      const res = await axios.post('http://localhost:5000/api/upload', formDataUpload);
      if (res.data.success) {
         setImages(prev => [...prev, res.data.url]); // Backend phải trả về { success: true, url: "..." }
         toast.success("Đã tải ảnh lên");
      }
    } catch (error) {
      toast.error("Lỗi upload ảnh");
      console.error(error);
    }
  };

  const handleAddVariant = () => {
      if(!currentVariant.size || !currentVariant.color || !currentVariant.sku) {
          return toast.warn("Vui lòng nhập đủ Size, Màu, SKU");
      }
      setVariants([...variants, currentVariant]);
      setCurrentVariant({ size: '', color: '', sku: '' });
  };

  const handleRemoveVariant = (index) => {
      setVariants(variants.filter((_, i) => i !== index));
  };

  const handleCreateCategory = async () => {
      if(!newCatName) return;
      try {
          const res = await axios.post('http://localhost:5000/api/categories', { name: newCatName });
          if(res.data.success) {
              setCategories([...categories, res.data.data]);
              setFormData({...formData, category_id: res.data.data.id});
              setIsCreatingCat(false);
              setNewCatName('');
          }
      } catch (err) { toast.error("Lỗi tạo danh mục"); }
  };

  // 3. HÀM SUBMIT (LƯU)
  const handleSubmit = async () => {
      if(!formData.name || !formData.base_price) return toast.warn("Tên và giá là bắt buộc");

      const payload = {
          ...formData,
          images,
          variants
      };

      try {
          if (productToEdit) {
              // GỌI API SỬA (PUT)
              const res = await axios.put(`http://localhost:5000/api/products/${productToEdit.id}`, payload);
              if(res.data.success) {
                  toast.success(res.data.message); // Hiển thị thông báo từ backend
                  onSuccess();
                  onClose();
              }
          } else {
              // GỌI API TẠO MỚI (POST)
              const res = await axios.post('http://localhost:5000/api/products', payload);
              if(res.data.success) {
                  toast.success("Tạo sản phẩm thành công");
                  onSuccess();
                  onClose();
              }
          }
      } catch (error) {
          toast.error("Có lỗi xảy ra: " + (error.response?.data?.message || error.message));
      }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 z-50 flex items-center justify-center p-4">
      <div className="bg-white rounded-xl w-full max-w-4xl max-h-[90vh] overflow-y-auto shadow-2xl animate-fade-in">
        
        {/* HEADER */}
        <div className="flex justify-between items-center p-6 border-b border-stone-100 sticky top-0 bg-white z-10">
            <h2 className="text-xl font-bold text-stone-800">
                {productToEdit ? `Chỉnh sửa: ${productToEdit.name}` : "Thêm sản phẩm mới"}
            </h2>
            <button onClick={onClose} className="text-stone-400 hover:text-red-500 transition-colors"><FaTimes size={24}/></button>
        </div>

        {/* BODY */}
        <div className="p-6 space-y-6">
            
            {/* 1. Thông tin chung */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div>
                    <label className="label">Tên sản phẩm</label>
                    <input className="input" value={formData.name} onChange={e => setFormData({...formData, name: e.target.value})} placeholder="VD: Áo Thun Basic" />
                </div>
                <div>
                    <label className="label">Danh mục</label>
                    <div className="flex gap-2">
                        {!isCreatingCat ? (
                            <>
                                <select className="input" value={formData.category_id} onChange={e => setFormData({...formData, category_id: e.target.value})}>
                                    <option value="">-- Chọn danh mục --</option>
                                    {categories.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
                                </select>
                                <button onClick={() => setIsCreatingCat(true)} className="px-3 bg-stone-100 rounded hover:bg-stone-200 text-xl font-bold">+</button>
                            </>
                        ) : (
                            <>
                                <input className="input" placeholder="Tên danh mục mới..." value={newCatName} onChange={e => setNewCatName(e.target.value)} autoFocus />
                                <button onClick={handleCreateCategory} className="btn-primary px-4">OK</button>
                                <button onClick={() => setIsCreatingCat(false)} className="px-3 text-stone-500">Hủy</button>
                            </>
                        )}
                    </div>
                </div>
                <div>
                    <label className="label">Giá bán (VNĐ)</label>
                    <input type="number" className="input" value={formData.base_price} onChange={e => setFormData({...formData, base_price: e.target.value})} />
                </div>
                <div>
                    <label className="label">Slug (URL - Tự động)</label>
                    <input className="input bg-stone-50" value={formData.slug} readOnly placeholder="Tu-dong-tao-khi-luu" />
                </div>
                <div className="md:col-span-2">
                    <label className="label">Mô tả sản phẩm</label>
                    <textarea className="input h-24" value={formData.description} onChange={e => setFormData({...formData, description: e.target.value})} />
                </div>
            </div>

            {/* 2. Hình ảnh */}
            <div>
                <label className="label mb-2 block">Hình ảnh sản phẩm</label>
                <div className="flex flex-wrap gap-4">
                    {images.map((img, idx) => (
                        <div key={idx} className="relative w-24 h-32 border border-stone-200 rounded overflow-hidden group">
                            <img src={img} alt="" className="w-full h-full object-cover" />
                            <button onClick={() => setImages(images.filter((_, i) => i !== idx))} className="absolute top-1 right-1 bg-red-500 text-white rounded-full p-1 opacity-0 group-hover:opacity-100 transition-opacity"><FaTrash size={10}/></button>
                        </div>
                    ))}
                    <button onClick={() => fileInputRef.current.click()} className="w-24 h-32 border-2 border-dashed border-stone-300 rounded flex flex-col items-center justify-center text-stone-400 hover:border-stone-800 hover:text-stone-800 transition-colors">
                        <FaUpload size={20} className="mb-2"/>
                        <span className="text-xs font-bold">Thêm ảnh</span>
                    </button>
                    <input type="file" hidden ref={fileInputRef} onChange={handleFileUpload} accept="image/*" />
                </div>
            </div>

            {/* 3. Biến thể (Variants) */}
            <div className="bg-stone-50 p-4 rounded-lg border border-stone-200">
                <label className="label mb-3 block text-stone-700">Phân loại hàng (Size / Màu sắc)</label>
                
                {/* Form thêm variant nhỏ */}
                <div className="flex flex-wrap gap-2 mb-4 items-end">
                    <div className="w-24">
                        <span className="text-xs font-bold text-stone-500">Size</span>
                        <input className="input text-sm py-1" placeholder="S, M..." value={currentVariant.size} onChange={e => setCurrentVariant({...currentVariant, size: e.target.value})} />
                    </div>
                    <div className="w-32">
                        <span className="text-xs font-bold text-stone-500">Màu sắc</span>
                        <input className="input text-sm py-1" placeholder="Đen, Trắng..." value={currentVariant.color} onChange={e => setCurrentVariant({...currentVariant, color: e.target.value})} />
                    </div>
                    <div className="flex-1 min-w-[120px]">
                        <span className="text-xs font-bold text-stone-500">Mã SKU (Duy nhất)</span>
                        <input className="input text-sm py-1" placeholder="VD: AO-TRANG-S" value={currentVariant.sku} onChange={e => setCurrentVariant({...currentVariant, sku: e.target.value})} />
                    </div>
                    <button onClick={handleAddVariant} className="bg-stone-800 text-white px-4 py-2 rounded h-9 text-sm font-bold hover:bg-stone-900 flex items-center gap-1">
                        <FaPlus size={10}/> Thêm
                    </button>
                </div>

                {/* Danh sách variants */}
                <div className="space-y-2">
                    {variants.length === 0 && <p className="text-sm text-stone-400 italic">Chưa có phân loại nào.</p>}
                    {variants.map((v, idx) => (
                        <div key={idx} className="flex justify-between items-center bg-white p-2 rounded border border-stone-200 shadow-sm">
                            <div className="flex gap-4 text-sm">
                                <span className="font-bold w-10 text-center bg-stone-100 rounded">{v.size}</span>
                                <span className="text-stone-600">{v.color}</span>
                                <span className="font-mono text-stone-400 text-xs py-0.5">{v.sku}</span>
                            </div>
                            <button onClick={() => handleRemoveVariant(idx)} className="text-red-400 hover:text-red-600"><FaTrash/></button>
                        </div>
                    ))}
                </div>
                {productToEdit && variants.length > 0 && (
                     <p className="text-xs text-orange-600 mt-2 italic">* Lưu ý: Nếu sản phẩm đã có trong kho, bạn sẽ không thể thay đổi Size/Màu tại đây.</p>
                )}
            </div>

        </div>

        {/* FOOTER */}
        <div className="p-6 border-t border-stone-100 flex justify-end gap-3 bg-stone-50 rounded-b-xl sticky bottom-0">
            <button onClick={onClose} className="px-6 py-2 rounded font-bold text-stone-500 hover:bg-stone-200 transition-colors">Hủy bỏ</button>
            <button onClick={handleSubmit} className="px-6 py-2 rounded font-bold text-white bg-stone-900 hover:bg-black transition-colors shadow-lg">
                {productToEdit ? 'Lưu thay đổi' : 'Tạo sản phẩm'}
            </button>
        </div>

      </div>

      <style>{`
        .label { display: block; font-size: 0.75rem; font-weight: 700; color: #78716c; margin-bottom: 0.25rem; text-transform: uppercase; }
        .input { width: 100%; padding: 0.5rem; border: 1px solid #e7e5e4; border-radius: 0.375rem; outline: none; transition: border-color 0.2s; }
        .input:focus { border-color: #1c1917; }
        .btn-primary { background-color: #1c1917; color: white; font-weight: 700; border-radius: 0.375rem; transition: background-color 0.2s; }
        .btn-primary:hover { background-color: #000; }
        @keyframes fade-in { from { opacity: 0; transform: scale(0.95); } to { opacity: 1; transform: scale(1); } }
        .animate-fade-in { animation: fade-in 0.2s ease-out; }
      `}</style>
    </div>
  );
};

export default ProductModal;