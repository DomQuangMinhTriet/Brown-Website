import { useState, useEffect } from 'react';
import axios from 'axios';
import { FaTrash, FaPlus, FaImage, FaCloudUploadAlt, FaList, FaEye, FaEyeSlash } from 'react-icons/fa';
import { toast } from 'react-toastify';

const Appearance = () => {
  // --- STATE BANNER ---
  const [banners, setBanners] = useState([]); 
  const [loading, setLoading] = useState(true);
  const [newBanner, setNewBanner] = useState({ title: '', link_to: '', display_order: 0 });
  const [file, setFile] = useState(null);
  const [uploading, setUploading] = useState(false);

  // --- [MỚI] STATE DANH MỤC ---
  const [categories, setCategories] = useState([]);

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    try {
      setLoading(true);
      // Gọi cả 2 API cùng lúc
      const [bannerRes, catRes] = await Promise.all([
          axios.get(`${import.meta.env.VITE_API_URL}/api/content/banners`),
          axios.get(`${import.meta.env.VITE_API_URL}/api/categories`)
      ]);

      // Xử lý Banner
      if (bannerRes.data && Array.isArray(bannerRes.data.data)) {
        setBanners(bannerRes.data.data);
      }

      // Xử lý Danh mục
      if (catRes.data && Array.isArray(catRes.data.data)) {
        setCategories(catRes.data.data);
      }

    } catch (error) {
      console.error("Lỗi tải dữ liệu:", error);
      toast.error("Không tải được dữ liệu giao diện");
    } finally {
      setLoading(false);
    }
  };

  // ==========================================================
  // LOGIC BANNER (GIỮ NGUYÊN)
  // ==========================================================
  const handleUploadFile = async () => {
    if (!file) return null;
    const formData = new FormData();
    formData.append('image', file);
    try {
      setUploading(true);
      const res = await axios.post(`${import.meta.env.VITE_API_URL}/api/upload`, formData, {
        headers: { 'Content-Type': 'multipart/form-data' }
      });
      return res.data.url;
    } catch (error) {
      console.error(error);
      toast.error("Lỗi upload ảnh");
      return null;
    } finally {
      setUploading(false);
    }
  };

  const handleCreateBanner = async (e) => {
    e.preventDefault();
    if (!file && !newBanner.image_url) return toast.warning("Vui lòng chọn ảnh!");
    
    let finalImageUrl = newBanner.image_url;
    if (file) {
       const uploadedUrl = await handleUploadFile();
       if (!uploadedUrl) return;
       finalImageUrl = uploadedUrl;
    }

    try {
      const payload = { ...newBanner, image_url: finalImageUrl };
      const res = await axios.post(`${import.meta.env.VITE_API_URL}/api/content/banners`, payload);
      if (res.data.success) {
         toast.success("Đã thêm banner!");
         setBanners([...banners, res.data.data]); // Update UI ngay lập tức
         setNewBanner({ title: '', link_to: '', display_order: 0 });
         setFile(null);
      }
    } catch (error) {
      toast.error("Lỗi tạo banner");
    }
  };

  const handleDelete = async (id) => {
      if(!confirm("Bạn chắc chắn muốn xóa banner này?")) return;
      try {
          await axios.delete(`${import.meta.env.VITE_API_URL}/api/content/banners/${id}`);
          setBanners(banners.filter(b => b.id !== id));
          toast.success("Đã xóa banner");
      } catch (error) {
          toast.error("Lỗi xóa banner");
      }
  };

  // ==========================================================
  // [MỚI] LOGIC TOGGLE DANH MỤC
  // ==========================================================
  const handleToggleCategory = async (category) => {
    // 1. Tính toán trạng thái mới
    const newStatus = !category.is_visible_on_home;

    // 2. Cập nhật giao diện NGAY LẬP TỨC (Optimistic UI)
    const originalCategories = [...categories]; // Backup để revert nếu lỗi
    setCategories(prev => prev.map(c => 
        c.id === category.id ? { ...c, is_visible_on_home: newStatus } : c
    ));

    try {
        // 3. Gọi API
        await axios.put(`${import.meta.env.VITE_API_URL}/api/categories/${category.id}/visibility`, {
            is_visible_on_home: newStatus
        });
        toast.success(newStatus ? `Đã hiện: ${category.name}` : `Đã ẩn: ${category.name}`);
    } catch (error) {
        // 4. Nếu lỗi thì quay lại trạng thái cũ
        setCategories(originalCategories);
        toast.error("Lỗi cập nhật trạng thái");
        console.error(error);
    }
  };

  if (loading) return <div className="p-8 text-center text-stone-500">Đang tải cấu hình giao diện...</div>;

  return (
    <div className="p-6 max-w-7xl mx-auto space-y-8">
      
      {/* --- PHẦN 1: QUẢN LÝ BANNER (GIỮ NGUYÊN) --- */}
      <div>
        <h2 className="text-2xl font-serif font-bold text-stone-800 mb-6 flex items-center gap-2">
            <FaImage /> Banner Trang chủ
        </h2>

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
            {/* Form thêm mới */}
            <div className="bg-white p-6 rounded-xl shadow-sm border border-stone-200 h-fit">
                <h3 className="font-bold text-stone-700 mb-4 flex items-center gap-2">
                    <FaPlus className="text-stone-400"/> Thêm Banner Mới
                </h3>
                <form onSubmit={handleCreateBanner} className="space-y-4">
                    <div>
                        <label className="text-xs font-bold uppercase text-stone-500 block mb-1">Tiêu đề (Alt text)</label>
                        <input type="text" className="w-full p-2 border rounded focus:border-stone-800 outline-none" 
                            value={newBanner.title} onChange={e => setNewBanner({...newBanner, title: e.target.value})}
                        />
                    </div>
                    <div>
                        <label className="text-xs font-bold uppercase text-stone-500 block mb-1">Link liên kết (Tùy chọn)</label>
                        <input type="text" className="w-full p-2 border rounded focus:border-stone-800 outline-none" placeholder="/collection?category=ao-thun"
                            value={newBanner.link_to} onChange={e => setNewBanner({...newBanner, link_to: e.target.value})}
                        />
                    </div>
                    <div>
                        <label className="text-xs font-bold uppercase text-stone-500 block mb-1">Thứ tự hiển thị</label>
                        <input type="number" className="w-full p-2 border rounded focus:border-stone-800 outline-none" 
                            value={newBanner.display_order} onChange={e => setNewBanner({...newBanner, display_order: e.target.value})}
                        />
                    </div>
                    
                    {/* Upload ảnh */}
                    <div className="border-2 border-dashed border-stone-300 rounded-lg p-4 text-center hover:bg-stone-50 transition-colors cursor-pointer relative">
                        <input 
                            type="file" accept="image/*" 
                            className="absolute inset-0 opacity-0 cursor-pointer"
                            onChange={e => setFile(e.target.files[0])}
                        />
                        <div className="flex flex-col items-center justify-center text-stone-500">
                            <FaCloudUploadAlt size={24} className="mb-2"/>
                            <span className="text-sm font-medium">{file ? file.name : "Kéo thả hoặc chọn ảnh"}</span>
                        </div>
                    </div>

                    <button disabled={uploading} type="submit" className="w-full bg-stone-900 text-white py-3 rounded font-bold hover:bg-black transition-colors disabled:opacity-70">
                        {uploading ? 'Đang tải lên...' : 'Lưu Banner'}
                    </button>
                </form>
            </div>

            {/* Danh sách Banner */}
            <div className="lg:col-span-2 grid grid-cols-1 md:grid-cols-2 gap-4">
                {banners.length === 0 ? (
                    <div className="col-span-full py-10 text-center text-stone-400 bg-stone-50 rounded border border-dashed">
                        Chưa có banner nào
                    </div>
                ) : (
                   banners.map(banner => (
                    <div key={banner.id} className="bg-white rounded-lg shadow border overflow-hidden relative group">
                        <div className="h-40 w-full bg-stone-100 relative">
                            <img 
                                src={banner.image_url} 
                                alt={banner.title} 
                                className="w-full h-full object-cover"
                                onError={(e) => {e.target.src = 'https://via.placeholder.com/400x200?text=Lỗi+Ảnh'}} 
                            />
                        </div>
                        <div className="p-3">
                            <h4 className="font-bold text-stone-800 text-sm truncate">{banner.title}</h4>
                            <div className="flex justify-between items-center mt-2">
                                <span className="text-xs bg-stone-100 px-2 py-1 rounded text-stone-600">Thứ tự: {banner.display_order}</span>
                                <button onClick={() => handleDelete(banner.id)} className="text-stone-400 hover:text-red-500 transition-colors">
                                    <FaTrash />
                                </button>
                            </div>
                        </div>
                    </div>
                    ))
                )}
            </div>
        </div>
      </div>

      <hr className="border-stone-200" />

      {/* --- PHẦN 2: [MỚI] QUẢN LÝ DANH MỤC TRANG CHỦ --- */}
      <div>
        <h2 className="text-2xl font-serif font-bold text-stone-800 mb-6 flex items-center gap-2">
            <FaList /> Danh mục Trang chủ
        </h2>
        <p className="text-stone-500 mb-6 text-sm">
            Chọn các danh mục bạn muốn hiển thị nổi bật trên trang chủ. Bật công tắc để hiển thị.
        </p>

        <div className="bg-white rounded-xl shadow-sm border border-stone-200 overflow-hidden">
            <table className="w-full text-left border-collapse">
                <thead className="bg-stone-100 text-stone-600 uppercase text-xs">
                    <tr>
                        <th className="p-4">Tên danh mục</th>
                        <th className="p-4">Đường dẫn (Slug)</th>
                        <th className="p-4 text-center">Trạng thái trên Home</th>
                    </tr>
                </thead>
                <tbody className="divide-y divide-stone-100">
                    {categories.length === 0 ? (
                        <tr><td colSpan="3" className="p-6 text-center text-stone-400">Chưa có danh mục nào</td></tr>
                    ) : (
                        categories.map(cat => (
                            <tr key={cat.id} className="hover:bg-stone-50 transition-colors">
                                <td className="p-4 font-bold text-stone-800">{cat.name}</td>
                                <td className="p-4 text-stone-500 font-mono text-xs">{cat.slug}</td>
                                <td className="p-4 text-center">
                                    {/* Toggle Switch */}
                                    <label className="relative inline-flex items-center cursor-pointer group">
                                        <input 
                                            type="checkbox" 
                                            className="sr-only peer"
                                            checked={cat.is_visible_on_home || false}
                                            onChange={() => handleToggleCategory(cat)} 
                                        />
                                        <div className="w-11 h-6 bg-stone-200 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-stone-900"></div>
                                        <span className="ml-3 text-sm font-medium text-stone-500 group-hover:text-stone-800 transition-colors w-20 text-left">
                                            {cat.is_visible_on_home ? 'Đang hiện' : 'Đang ẩn'}
                                        </span>
                                    </label>
                                </td>
                            </tr>
                        ))
                    )}
                </tbody>
            </table>
        </div>
      </div>

    </div>
  );
};

export default Appearance;