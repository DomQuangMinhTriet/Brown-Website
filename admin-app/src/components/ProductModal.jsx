import { useState, useEffect } from 'react';
import axios from 'axios';
import { FaTimes, FaCloudUploadAlt, FaTrash, FaPlus } from 'react-icons/fa';

const ProductModal = ({ isOpen, onClose, onSuccess }) => {
  // State cho thông tin cơ bản
  const [formData, setFormData] = useState({
    name: '',
    slug: '',
    base_price: '',
    description: '',
    category_id: ''
  });
  
  // State cho danh sách phụ
  const [categories, setCategories] = useState([]);
  const [images, setImages] = useState([]); // Mảng chứa URL ảnh
  const [variants, setVariants] = useState([]); // Mảng chứa biến thể {size, color, sku}
  
  // State cho biến thể đang nhập
  const [currentVariant, setCurrentVariant] = useState({ size: '', color: '', sku: '' });
  
  const [uploading, setUploading] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  // 1. Lấy danh mục khi mở Modal
  useEffect(() => {
    if (isOpen) {
      fetchCategories();
    }
  }, [isOpen]);

  const fetchCategories = async () => {
    try {
      const res = await axios.get('http://localhost:5000/api/categories');
      if (res.data.success) setCategories(res.data.data);
    } catch (err) {
      console.error("Lỗi lấy danh mục", err);
    }
  };

  // 2. Xử lý Upload ảnh
  const handleImageUpload = async (e) => {
    const file = e.target.files[0];
    if (!file) return;

    setUploading(true);
    const formData = new FormData();
    formData.append('image', file);

    try {
      const res = await axios.post('http://localhost:5000/api/upload', formData, {
        headers: { 'Content-Type': 'multipart/form-data' }
      });
      if (res.data.success) {
        setImages([...images, res.data.imageUrl]); // Thêm URL vào mảng
      }
    } catch (err) {
      alert('Upload ảnh thất bại!');
      console.error(err);
    } finally {
      setUploading(false);
    }
  };

  // 3. Xử lý thêm Biến thể
  const handleAddVariant = () => {
    if (!currentVariant.size || !currentVariant.color || !currentVariant.sku) {
      alert("Vui lòng nhập đủ Size, Màu và SKU");
      return;
    }
    setVariants([...variants, currentVariant]);
    setCurrentVariant({ size: '', color: '', sku: '' }); // Reset form biến thể
  };

  // 4. Submit Form lên Server
  const handleSubmit = async () => {
    if (!formData.name || !formData.base_price) {
      alert("Tên và Giá là bắt buộc!");
      return;
    }

    setSubmitting(true);
    try {
      const payload = {
        ...formData,
        images: images,
        variants: variants
      };

      const res = await axios.post('http://localhost:5000/api/products', payload);
      if (res.data.success) {
        alert("Thêm sản phẩm thành công!");
        onSuccess(); // Gọi hàm refresh ở trang cha
        onClose();   // Đóng modal
      }
    } catch (err) {
      alert("Lỗi khi lưu sản phẩm: " + err.message);
    } finally {
      setSubmitting(false);
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40 backdrop-blur-sm">
      <div className="bg-white rounded-xl shadow-2xl w-full max-w-4xl max-h-[90vh] overflow-y-auto">
        
        {/* Header Modal */}
        <div className="flex justify-between items-center p-6 border-b border-stone-100 sticky top-0 bg-white z-10">
          <h2 className="text-xl font-bold text-stone-800">Thêm Sản Phẩm Mới</h2>
          <button onClick={onClose} className="text-stone-400 hover:text-stone-800">
            <FaTimes size={20} />
          </button>
        </div>

        {/* Body Modal */}
        <div className="p-6 grid grid-cols-1 md:grid-cols-2 gap-8">
          
          {/* CỘT TRÁI: THÔNG TIN CƠ BẢN */}
          <div className="space-y-5">
            <div>
              <label className="block text-sm font-medium text-stone-600 mb-1">Tên sản phẩm *</label>
              <input 
                type="text" 
                className="w-full p-2 border border-stone-200 rounded-lg focus:border-stone-500 outline-none"
                placeholder="VD: Đầm Lụa Tơ Tằm"
                value={formData.name}
                onChange={e => setFormData({...formData, name: e.target.value})}
              />
            </div>
            
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-stone-600 mb-1">Slug (URL)</label>
                <input 
                  type="text" 
                  className="w-full p-2 border border-stone-200 rounded-lg focus:border-stone-500 outline-none"
                  placeholder="dam-lua-to-tam"
                  value={formData.slug}
                  onChange={e => setFormData({...formData, slug: e.target.value})}
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-stone-600 mb-1">Giá bán (VNĐ) *</label>
                <input 
                  type="number" 
                  className="w-full p-2 border border-stone-200 rounded-lg focus:border-stone-500 outline-none"
                  placeholder="500000"
                  value={formData.base_price}
                  onChange={e => setFormData({...formData, base_price: e.target.value})}
                />
              </div>
            </div>

            <div>
              <label className="block text-sm font-medium text-stone-600 mb-1">Danh mục</label>
              <select 
                className="w-full p-2 border border-stone-200 rounded-lg focus:border-stone-500 outline-none"
                onChange={e => setFormData({...formData, category_id: e.target.value})}
              >
                <option value="">-- Chọn danh mục --</option>
                {categories.map(cat => (
                  <option key={cat.id} value={cat.id}>{cat.name}</option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-sm font-medium text-stone-600 mb-1">Mô tả</label>
              <textarea 
                rows="4"
                className="w-full p-2 border border-stone-200 rounded-lg focus:border-stone-500 outline-none"
                value={formData.description}
                onChange={e => setFormData({...formData, description: e.target.value})}
              ></textarea>
            </div>
          </div>

          {/* CỘT PHẢI: ẢNH & BIẾN THỂ */}
          <div className="space-y-6">
            
            {/* 1. Upload Ảnh */}
            <div>
              <label className="block text-sm font-medium text-stone-600 mb-2">Hình ảnh</label>
              <div className="flex gap-2 flex-wrap mb-2">
                {images.map((img, idx) => (
                  <div key={idx} className="w-20 h-24 border border-stone-200 rounded overflow-hidden relative group">
                    <img src={img} alt="preview" className="w-full h-full object-cover" />
                    <button 
                      onClick={() => setImages(images.filter((_, i) => i !== idx))}
                      className="absolute top-1 right-1 bg-red-500 text-white rounded-full p-1 opacity-0 group-hover:opacity-100 transition"
                    >
                      <FaTimes size={10}/>
                    </button>
                  </div>
                ))}
                
                <label className="w-20 h-24 border-2 border-dashed border-stone-300 rounded flex flex-col items-center justify-center cursor-pointer hover:border-stone-500 hover:bg-stone-50 transition">
                  {uploading ? <span className="text-xs">Uploading...</span> : <><FaCloudUploadAlt size={24} className="text-stone-400"/><span className="text-xs text-stone-400 mt-1">Thêm ảnh</span></>}
                  <input type="file" className="hidden" onChange={handleImageUpload} />
                </label>
              </div>
            </div>

            {/* 2. Biến thể (Variants) */}
            <div className="bg-stone-50 p-4 rounded-xl border border-stone-200">
              <h3 className="font-bold text-stone-700 mb-3 text-sm">Các biến thể (Size/Màu)</h3>
              
              {/* Form nhập biến thể */}
              <div className="grid grid-cols-4 gap-2 mb-3">
                <input placeholder="Size (S,M)" className="p-2 border rounded text-sm" value={currentVariant.size} onChange={e => setCurrentVariant({...currentVariant, size: e.target.value})} />
                <input placeholder="Màu (Trắng)" className="p-2 border rounded text-sm" value={currentVariant.color} onChange={e => setCurrentVariant({...currentVariant, color: e.target.value})} />
                <input placeholder="SKU (Mã kho)" className="p-2 border rounded text-sm" value={currentVariant.sku} onChange={e => setCurrentVariant({...currentVariant, sku: e.target.value})} />
                <button onClick={handleAddVariant} className="bg-stone-800 text-white rounded hover:bg-stone-700"><FaPlus className="mx-auto"/></button>
              </div>

              {/* Danh sách biến thể đã thêm */}
              <div className="space-y-2 max-h-40 overflow-y-auto">
                {variants.map((v, idx) => (
                  <div key={idx} className="flex justify-between items-center bg-white p-2 rounded border border-stone-200 text-sm">
                    <span><b>{v.size}</b> - {v.color}</span>
                    <span className="text-stone-500 text-xs font-mono">{v.sku}</span>
                    <button onClick={() => setVariants(variants.filter((_, i) => i !== idx))} className="text-red-400 hover:text-red-600"><FaTrash size={12}/></button>
                  </div>
                ))}
                {variants.length === 0 && <p className="text-xs text-stone-400 text-center italic">Chưa có biến thể nào</p>}
              </div>
            </div>

          </div>
        </div>

        {/* Footer Actions */}
        <div className="p-6 border-t border-stone-100 flex justify-end gap-3 sticky bottom-0 bg-white">
          <button onClick={onClose} className="px-6 py-2 rounded-lg border border-stone-200 text-stone-600 hover:bg-stone-50">Hủy bỏ</button>
          <button 
            onClick={handleSubmit} 
            disabled={submitting}
            className="px-6 py-2 rounded-lg bg-stone-900 text-white hover:bg-stone-800 disabled:opacity-50"
          >
            {submitting ? 'Đang lưu...' : 'Hoàn tất & Lưu'}
          </button>
        </div>
      </div>
    </div>
  );
};

export default ProductModal;