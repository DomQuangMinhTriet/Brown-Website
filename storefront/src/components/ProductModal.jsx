import { useState, useEffect, useRef } from 'react';
import axios from 'axios';
import { FaTimes, FaUpload, FaTrash, FaPlus, FaArrowUp, FaArrowDown, FaSpinner } from 'react-icons/fa';
import { toast } from 'react-toastify';
import imageCompression from 'browser-image-compression';

const ProductModal = ({ isOpen, onClose, onSuccess, productToEdit }) => {
  // [CẬP NHẬT]: Thêm is_active vào State mặc định
  const [formData, setFormData] = useState({
    name: '',
    slug: '',
    base_price: 0,
    description: '',
    category_id: '',
    collection_ids: [],
    is_active: true
  });

  const [images, setImages] = useState([]);
  const [variants, setVariants] = useState([]);
  const [uploading, setUploading] = useState(false);
  const [categories, setCategories] = useState([]);
  
  // State phụ
  const [isCreatingCat, setIsCreatingCat] = useState(false);
  const [newCatName, setNewCatName] = useState('');
  const [sizeChart, setSizeChart] = useState('');
  const [currentVariant, setCurrentVariant] = useState({ size: '', color: '', sku: '', image_url: '' });
  const fileInputRef = useRef(null);

  // --- HELPER FORMAT TIỀN TỆ ---
  const formatCurrencyInput = (value) => {
      if (!value) return '';
      const number = Number(value.toString().replace(/\D/g, ''));
      return new Intl.NumberFormat('vi-VN').format(number);
  };

  const handlePriceChange = (e) => {
      const raw = e.target.value.replace(/\./g, '');
      if (!isNaN(raw)) {
          setFormData({ ...formData, base_price: raw });
      }
  };

  // --- 1. NẠP DỮ LIỆU ---
  useEffect(() => {
    if (isOpen) {
      fetchCategories();

      if (productToEdit) {
        let loadedCollectionIds = [];
        if (productToEdit.product_collections && Array.isArray(productToEdit.product_collections)) {
            loadedCollectionIds = productToEdit.product_collections
                .map(item => item.category_id)
                .filter(id => id !== null && id !== undefined)
                .map(Number);
        }

        setFormData({
            name: productToEdit.name || '',
            slug: productToEdit.slug || '',
            base_price: productToEdit.base_price || 0,
            description: productToEdit.description || '',
            category_id: productToEdit.category_id || '',
            collection_ids: loadedCollectionIds,
            // [CẬP NHẬT]: Lấy dữ liệu is_active từ DB (nếu có), nếu không mặc định = true
            is_active: productToEdit.is_active !== undefined ? productToEdit.is_active : true 
        });

        setImages(productToEdit.images || []);
        setSizeChart(productToEdit.size_chart_url || '');

        const safeVariants = productToEdit.variants || [];
        setVariants(safeVariants.map(v => ({
            size: v.size || '',
            color: v.color || '',
            sku: v.sku || '',
            image_url: v.image_url || ''
        })));

      } else {
        setFormData({ name: '', slug: '', base_price: 0, description: '', category_id: '', collection_ids: [], is_active: true });
        setImages([]);
        setVariants([]);
        setSizeChart('');
      }
      setCurrentVariant({ size: '', color: '', sku: '', image_url: '' });
    }
  }, [isOpen, productToEdit]);

  const fetchCategories = async () => {
    try {
      const res = await axios.get(`${import.meta.env.VITE_API_URL}/api/categories`);
      if(res.data.success) {
          setCategories(res.data.data);
      }
    } catch (err) { console.error(err); }
  };

  // --- 2. XỬ LÝ CLICK CHECKBOX COLLECTION ---
  const handleToggleCollection = (catId) => {
      const targetId = Number(catId);
      const currentIds = formData.collection_ids.map(Number);
      
      let newIds;
      if (currentIds.includes(targetId)) {
          newIds = currentIds.filter(id => id !== targetId);
      } else {
          newIds = [...currentIds, targetId];
      }
      setFormData({ ...formData, collection_ids: newIds });
  };

  // --- 3. UPLOAD ẢNH (GỌI API SERVER CLOUDINARY) ---
    const handleImageUpload = async (e) => {
        const files = Array.from(e.target.files);
        if (files.length === 0) return;
        setUploading(true);
        const newImages = [];

        const options = {
            maxSizeMB: 1,          
            maxWidthOrHeight: 1500,  
            useWebWorker: true
        };

        try {
            for (const file of files) {
                let fileToUpload = file;
                try {
                    fileToUpload = await imageCompression(file, options);
                } catch (compError) {
                    console.warn("Lỗi nén ảnh, dùng ảnh gốc:", compError);
                }
                
                const uploadData = new FormData();
                uploadData.append('image', fileToUpload);

                const res = await axios.post(`${import.meta.env.VITE_API_URL}/api/upload`, uploadData, {
                    headers: { 'Content-Type': 'multipart/form-data' }
                });
                
                if (res.data.success) {
                    newImages.push(res.data.url);
                }
            }
            setImages(prev => [...prev, ...newImages]);
            toast.success(`Đã tải lên ${newImages.length} ảnh`);
        } catch (error) { 
            console.error(error);
            toast.error('Lỗi upload: ' + (error.response?.data?.message || error.message)); 
        } finally { 
            setUploading(false); 
            if(fileInputRef.current) fileInputRef.current.value = '';
        }
    };

    // --- XỬ LÝ UPLOAD SIZE CHART ---
    const handleUploadSizeChart = async (e) => {
        const file = e.target.files[0];
        if (!file) return;
        const toastId = toast.loading("Đang tải ảnh...");
        
        try {
            const uploadData = new FormData();
            uploadData.append('image', file);

            const res = await axios.post(`${import.meta.env.VITE_API_URL}/api/upload`, uploadData, {
                headers: { 'Content-Type': 'multipart/form-data' }
            });

            if (res.data.success) {
                setSizeChart(res.data.url);
                toast.update(toastId, { render: "Đã tải xong!", type: "success", isLoading: false, autoClose: 2000 });
            }
        } catch (err) {
            toast.update(toastId, { render: "Lỗi upload", type: "error", isLoading: false, autoClose: 2000 });
        }
    };

  // --- 4. CÁC HÀM KHÁC ---
  const handleAddVariant = () => {
      if(!currentVariant.size || !currentVariant.color || !currentVariant.sku) {
          return toast.warn("Vui lòng nhập đủ Size, Màu, SKU");
      }
      setVariants([...variants, { ...currentVariant, image_url: currentVariant.image_url || '' }]);
      setCurrentVariant({ size: '', color: '', sku: '', image_url: '' });
  };

  const handleRemoveVariant = (index) => {
      setVariants(variants.filter((_, i) => i !== index));
  };

  const toSlug = (str) => {
      return str.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[đĐ]/g, 'd').replace(/[^a-z0-9\s-]/g, '').trim().replace(/\s+/g, '-');
  };

  const handleCreateCategory = async () => {
      if (!newCatName) return;
      try {
          const res = await axios.post(`${import.meta.env.VITE_API_URL}/api/categories`, { 
              name: newCatName, slug: toSlug(newCatName) 
          });
          if (res.data.success) {
              setCategories([res.data.data, ...categories]);
              setFormData({ ...formData, category_id: res.data.data.id });
              setIsCreatingCat(false);
              setNewCatName('');
              toast.success("Tạo danh mục thành công!");
          }
      } catch (err) { toast.error("Lỗi tạo danh mục"); }
  };

  const moveImage = (index, direction) => {
      const newImgs = [...images];
      const target = index + direction;
      if (target >= 0 && target < newImgs.length) {
          [newImgs[index], newImgs[target]] = [newImgs[target], newImgs[index]];
          setImages(newImgs);
      }
  };

  // --- 5. SUBMIT FORM ---
  const handleSubmit = async () => {
      if(!formData.name || !formData.base_price) return toast.warn("Tên và giá là bắt buộc");

      // [CẬP NHẬT]: payload sẽ chứa is_active do nằm sẵn trong formData
      const payload = {
          ...formData, 
          base_price: Number(formData.base_price),
          images,
          variants,
          size_chart_url: sizeChart
      };

      try {
          if (productToEdit) {
              const res = await axios.put(`${import.meta.env.VITE_API_URL}/api/products/${productToEdit.id}`, payload);
              if(res.data.success) {
                  toast.success("Cập nhật thành công!");
                  onSuccess();
                  onClose();
              }
          } else {
              const res = await axios.post(`${import.meta.env.VITE_API_URL}/api/products`, payload);
              if(res.data.success) {
                  toast.success("Tạo sản phẩm thành công!");
                  onSuccess();
                  onClose();
              }
          }
      } catch (error) {
          toast.error("Lỗi: " + (error.response?.data?.message || error.message));
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
            
            {/* THÔNG TIN CHUNG */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div>
                    <label className="label">Tên sản phẩm</label>
                    <input className="input" value={formData.name} onChange={e => setFormData({...formData, name: e.target.value, slug: toSlug(e.target.value)})} placeholder="VD: Áo Thun Basic" />
                </div>
                
                {/* DANH MỤC */}
                <div className="md:col-span-2 grid grid-cols-1 md:grid-cols-2 gap-6">
                    <div>
                        <label className="label">Danh mục chính</label>
                        <div className="flex gap-2">
                            {!isCreatingCat ? (
                                <>
                                    <select className="input" value={formData.category_id} onChange={e => setFormData({...formData, category_id: e.target.value})}>
                                        <option value="">-- Chọn danh mục --</option>
                                        {categories.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
                                    </select>
                                    <button onClick={() => setIsCreatingCat(true)} className="px-3 bg-stone-100 rounded hover:bg-stone-200 font-bold">+</button>
                                </>
                            ) : (
                                <>
                                    <input className="input" placeholder="Tên danh mục..." value={newCatName} onChange={e => setNewCatName(e.target.value)} autoFocus />
                                    <button onClick={handleCreateCategory} className="btn-primary px-4">OK</button>
                                    <button onClick={() => setIsCreatingCat(false)} className="px-3 text-stone-500">Hủy</button>
                                </>
                            )}
                        </div>
                    </div>

                    {/* CHECKBOX COLLECTION */}
                    <div>
                        <label className="label">Bộ sưu tập (Phụ)</label>
                        <div className="border border-stone-200 p-2 rounded max-h-[100px] overflow-y-auto bg-stone-50 grid grid-cols-2 gap-2">
                            {categories.map(c => (
                                <label key={c.id} className="flex items-center gap-2 cursor-pointer hover:bg-stone-100 p-1 rounded select-none">
                                    <input 
                                        type="checkbox"
                                        className="accent-stone-900 w-4 h-4"
                                        checked={formData.collection_ids?.some(id => Number(id) === Number(c.id))}
                                        onChange={() => handleToggleCollection(c.id)}
                                    />
                                    <span className="text-sm text-stone-700">{c.name}</span>
                                </label>
                            ))}
                        </div>
                    </div>
                </div>

                <div>
                    <label className="label">Giá bán (VNĐ)</label>
                    <input 
                        type="text" 
                        className="input" 
                        placeholder="0"
                        value={formatCurrencyInput(formData.base_price)} 
                        onChange={handlePriceChange} 
                    />
                </div>
                <div>
                    <label className="label">Slug (Tự động)</label>
                    <input className="input bg-stone-50" value={formData.slug} readOnly placeholder="Tu-dong-tao-khi-luu" />
                </div>
                <div className="md:col-span-2">
                    <label className="label">Mô tả sản phẩm</label>
                    <textarea className="input h-24" value={formData.description} onChange={e => setFormData({...formData, description: e.target.value})} />
                </div>

                {/* [CẬP NHẬT] Khu vực Toggle bật/tắt hiển thị */}
                <div className="md:col-span-2 border-t border-stone-200 pt-4 mt-2">
                    <label className="label mb-2">Trạng thái sản phẩm</label>
                    <label className={`flex items-center gap-3 p-4 border rounded-lg cursor-pointer transition-colors w-fit ${formData.is_active ? 'bg-green-50 border-green-200' : 'bg-stone-100 border-stone-300'}`}>
                        <input 
                            type="checkbox" 
                            className="w-5 h-5 accent-green-600 cursor-pointer"
                            checked={formData.is_active} 
                            onChange={(e) => setFormData({...formData, is_active: e.target.checked})}
                        />
                        <div>
                            <span className={`font-bold block ${formData.is_active ? 'text-green-700' : 'text-stone-500'}`}>
                                {formData.is_active ? '✅ Đang hiển thị cho khách hàng' : '❌ Đang Ẩn (Ngừng kinh doanh)'}
                            </span>
                            <span className="text-xs text-stone-500 mt-1 block">Tắt tùy chọn này thay vì "Xóa" để bảo vệ dữ liệu các đơn hàng cũ.</span>
                        </div>
                    </label>
                </div>
            </div>

            {/* HÌNH ẢNH */}
            <div>
                <label className="label mb-2 flex justify-between">
                    <span>Hình ảnh sản phẩm</span>
                    {uploading && <span className="text-blue-600 text-xs animate-pulse">Đang tải ảnh lên Cloudinary...</span>}
                </label>
                <div className="grid grid-cols-5 gap-3">
                    {images.map((img, idx) => (
                        <div key={idx} className="relative group border border-stone-200 rounded overflow-hidden aspect-square bg-stone-100">
                            <img src={img} alt="" className="w-full h-full object-cover" />
                            <div className="absolute inset-0 bg-black/50 flex items-center justify-center gap-2 opacity-0 group-hover:opacity-100 transition-opacity">
                                <button onClick={() => moveImage(idx, -1)} className="text-white hover:text-stone-300 p-1"><FaArrowUp className="-rotate-90" size={12}/></button>
                                <button onClick={() => setImages(images.filter((_, i) => i !== idx))} className="bg-white text-red-500 rounded-full p-1.5"><FaTrash size={12}/></button>
                                <button onClick={() => moveImage(idx, 1)} className="text-white hover:text-stone-300 p-1"><FaArrowDown className="-rotate-90" size={12}/></button>
                            </div>
                        </div>
                    ))}
                    
                    <button onClick={() => fileInputRef.current.click()} disabled={uploading} className="aspect-square border-2 border-dashed border-stone-300 rounded flex flex-col items-center justify-center text-stone-400 hover:border-stone-800 transition-colors bg-white">
                        {uploading ? <FaSpinner className="animate-spin"/> : <FaUpload size={20} className="mb-2"/>}
                        <span className="text-xs font-bold">{uploading ? '...' : 'Thêm ảnh'}</span>
                    </button>
                    <input type="file" hidden ref={fileInputRef} onChange={handleImageUpload} accept="image/*" multiple />
                </div>
            </div>

            {/* SIZE CHART */}
            <div className="mt-4 p-4 bg-white rounded border border-stone-200 flex items-center gap-4">
                <div>
                    <label className="label mb-2">Size Chart</label>
                    <div className="relative">
                        <input type="file" onChange={handleUploadSizeChart} className="hidden" id="sizeChartUpload" accept="image/*" />
                        <label htmlFor="sizeChartUpload" className="flex items-center gap-2 px-4 py-2 border border-stone-300 rounded cursor-pointer hover:bg-stone-100 text-sm font-bold text-stone-600">
                            <FaUpload /> Tải ảnh lên
                        </label>
                    </div>
                </div>
                {sizeChart && (
                    <div className="relative w-20 h-20 border rounded overflow-hidden group">
                        <img src={sizeChart} className="w-full h-full object-cover" />
                        <button onClick={() => setSizeChart('')} className="absolute top-0 right-0 bg-red-500 text-white p-1 text-xs opacity-0 group-hover:opacity-100"><FaTrash/></button>
                    </div>
                )}
            </div>

            {/* BIẾN THỂ */}
            <div className="bg-stone-50 p-4 rounded-lg border border-stone-200">
                <label className="label mb-3 block text-stone-700">Phân loại hàng (Size / Màu sắc)</label>
                
                <div className="flex flex-wrap gap-2 mb-4 items-end">
                    <div className="w-24">
                        <span className="text-xs font-bold text-stone-500">Size</span>
                        <input className="input text-sm py-1" placeholder="S, M..." value={currentVariant.size} onChange={e => setCurrentVariant({...currentVariant, size: e.target.value})} />
                    </div>
                    <div className="w-32">
                        <span className="text-xs font-bold text-stone-500">Màu sắc</span>
                        <input className="input text-sm py-1" placeholder="Đen..." value={currentVariant.color} onChange={e => setCurrentVariant({...currentVariant, color: e.target.value})} />
                    </div>
                    <div className="flex-1 min-w-[120px]">
                        <span className="text-xs font-bold text-stone-500">SKU</span>
                        <input className="input text-sm py-1" placeholder="Mã..." value={currentVariant.sku} onChange={e => setCurrentVariant({...currentVariant, sku: e.target.value})} />
                    </div>
                    <button onClick={handleAddVariant} className="bg-stone-800 text-white px-4 py-2 rounded h-9 text-sm font-bold flex items-center gap-1 hover:bg-black">
                        <FaPlus size={10}/> Thêm
                    </button>
                </div>

                <div className="space-y-2 max-h-60 overflow-y-auto">
                    {variants.map((v, idx) => (
                        <div key={idx} className="flex justify-between items-center bg-white p-2 rounded border border-stone-200 shadow-sm">
                            <div className="flex gap-4 text-sm items-center flex-1">
                                <span className="font-bold w-10 text-center bg-stone-100 rounded">{v.size}</span>
                                <span className="text-stone-600 min-w-[60px]">{v.color}</span>
                                <span className="font-mono text-stone-400 text-xs py-0.5">{v.sku}</span>
                                
                                {/* HIỂN THỊ ẢNH THUMBNAIL */}
                                {v.image_url ? (
                                    <div className="w-10 h-10 rounded border border-stone-200 overflow-hidden relative group cursor-pointer">
                                        <img src={v.image_url} alt="Variant" className="w-full h-full object-cover" />
                                        <div className="absolute bottom-full mb-2 left-1/2 -translate-x-1/2 w-32 hidden group-hover:block z-50 bg-white border border-stone-300 shadow-xl rounded p-1">
                                            <img src={v.image_url} className="w-full h-auto object-cover" />
                                        </div>
                                    </div>
                                ) : (
                                    <div className="w-10 h-10 bg-stone-50 rounded border border-stone-200 flex items-center justify-center text-[10px] text-stone-400 text-center leading-tight">
                                        No<br/>Img
                                    </div>
                                )}

                                {/* MENU CHỌN ẢNH */}
                                <select 
                                    className="border border-stone-300 rounded text-xs p-1 max-w-[120px] ml-auto focus:border-stone-800 outline-none"
                                    value={v.image_url || ""}
                                    onChange={(e) => {
                                        const newVars = [...variants];
                                        newVars[idx].image_url = e.target.value;
                                        setVariants(newVars);
                                    }}
                                >
                                    <option value="">-- Chọn ảnh --</option>
                                    {images.map((img, i) => (
                                        <option key={i} value={img}>Ảnh {i + 1}</option>
                                    ))}
                                </select>
                            </div>
                            <button onClick={() => handleRemoveVariant(idx)} className="text-red-400 hover:text-red-600 px-2 ml-2 transition-colors">
                                <FaTrash/>
                            </button>
                        </div>
                    ))}
                </div>
            </div>

        </div>

        {/* FOOTER */}
        <div className="p-6 border-t border-stone-100 flex justify-end gap-3 bg-stone-50 rounded-b-xl sticky bottom-0">
            <button onClick={onClose} className="px-6 py-2 rounded font-bold text-stone-500 hover:bg-stone-200 transition-colors">Hủy bỏ</button>
            <button onClick={handleSubmit} disabled={uploading} className="px-6 py-2 rounded font-bold text-white bg-stone-900 hover:bg-black transition-colors shadow-lg disabled:opacity-50 flex items-center gap-2">
                {uploading && <FaSpinner className="animate-spin"/>}
                {uploading ? 'Đang tải...' : (productToEdit ? 'Lưu thay đổi' : 'Tạo sản phẩm')}
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