import { useState, useEffect } from 'react';
import axios from 'axios';
import { FaTrash, FaPlus, FaImage, FaCloudUploadAlt } from 'react-icons/fa';
import { toast } from 'react-toastify';

const Appearance = () => {
  const [banners, setBanners] = useState([]); 
  const [loading, setLoading] = useState(true);
  
  // Form State
  const [newBanner, setNewBanner] = useState({ title: '', link_to: '', display_order: 0 });
  const [file, setFile] = useState(null);
  const [uploading, setUploading] = useState(false);

  useEffect(() => {
    fetchBanners();
  }, []);

  const fetchBanners = async () => {
    try {
      const res = await axios.get('http://localhost:5000/api/content/banners');
      if (res.data && Array.isArray(res.data.data)) {
        setBanners(res.data.data);
      } else {
        setBanners([]);
      }
    } catch (error) {
      console.error("Lỗi tải banner:", error);
      toast.error("Không tải được danh sách Banner");
    } finally {
      setLoading(false);
    }
  };

  // 1. HÀM UPLOAD ẢNH RIÊNG
  const handleUploadFile = async () => {
    if (!file) return null;
    
    const formData = new FormData();
    formData.append('image', file);

    try {
        const res = await axios.post('http://localhost:5000/api/upload', formData, {
            headers: { 'Content-Type': 'multipart/form-data' }
        });
        return res.data.url; // Trả về URL ảnh từ Server
    } catch (error) {
        throw new Error("Lỗi khi upload ảnh lên Server");
    }
  };

  // 2. HÀM TẠO BANNER
  const handleCreateBanner = async (e) => {
    e.preventDefault();
    
    if (!file) return toast.warning("Vui lòng chọn file ảnh!");
    if (!newBanner.title) return toast.warning("Vui lòng nhập tiêu đề!");

    setUploading(true); // Bắt đầu loading

    try {
        // Bước 1: Upload ảnh trước
        const imageUrl = await handleUploadFile();
        if (!imageUrl) throw new Error("Không lấy được URL ảnh");

        // Bước 2: Gửi thông tin xuống DB
        await axios.post('http://localhost:5000/api/content/banners', {
            title: newBanner.title,
            link_to: newBanner.link_to,
            display_order: Number(newBanner.display_order),
            image_url: imageUrl
        });

        toast.success("✅ Thêm Banner thành công!");
        
        // Reset form
        setNewBanner({ title: '', link_to: '', display_order: 0 });
        setFile(null);
        // Reset input file (trick để xóa tên file trên giao diện)
        document.getElementById('bannerInput').value = ""; 
        
        fetchBanners();

    } catch (error) {
        toast.error(`❌ ${error.message}`);
    } finally {
        setUploading(false); // Kết thúc loading
    }
  };

  const handleDelete = async (id) => {
      if(!window.confirm("Bạn chắc chắn muốn xóa banner này?")) return;
      try {
          await axios.delete(`http://localhost:5000/api/content/banners/${id}`);
          toast.success("Đã xóa banner");
          fetchBanners();
      } catch (error) {
          toast.error("Lỗi khi xóa banner");
      }
  };

  return (
    <div className="p-6">
      <h1 className="text-2xl font-serif font-bold text-stone-800 mb-6">Giao diện Trang chủ</h1>
      
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        
        {/* FORM THÊM BANNER */}
        <div className="lg:col-span-1">
            <div className="bg-white p-6 rounded-lg shadow-sm border border-stone-200">
                <h3 className="font-bold text-lg mb-4 flex items-center gap-2"><FaPlus /> Thêm Banner Mới</h3>
                <form onSubmit={handleCreateBanner} className="space-y-4">
                    <div>
                        <label className="text-xs font-bold block mb-1">Tiêu đề (Alt text)</label>
                        <input 
                            type="text" className="w-full p-2 border rounded"
                            value={newBanner.title}
                            onChange={e => setNewBanner({...newBanner, title: e.target.value})}
                        />
                    </div>
                    <div>
                        <label className="text-xs font-bold block mb-1">Đường dẫn khi click (Tùy chọn)</label>
                        <input 
                            type="text" className="w-full p-2 border rounded" placeholder="/collection?search=..."
                            value={newBanner.link_to}
                            onChange={e => setNewBanner({...newBanner, link_to: e.target.value})}
                        />
                    </div>
                    <div>
                        <label className="text-xs font-bold block mb-1">Thứ tự hiển thị</label>
                        <input 
                            type="number" className="w-full p-2 border rounded"
                            value={newBanner.display_order}
                            onChange={e => setNewBanner({...newBanner, display_order: e.target.value})}
                        />
                    </div>
                    <div>
                        <label className="text-xs font-bold block mb-1">Hình ảnh</label>
                        <div className="border-2 border-dashed border-stone-300 rounded p-4 text-center cursor-pointer hover:bg-stone-50 relative">
                            <input 
                                id="bannerInput"
                                type="file" accept="image/*" 
                                className="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
                                onChange={e => setFile(e.target.files[0])}
                            />
                            <div className="text-stone-400">
                                <FaCloudUploadAlt className="mx-auto text-2xl mb-1"/>
                                <span className="text-sm">{file ? file.name : "Kéo thả hoặc chọn ảnh"}</span>
                            </div>
                        </div>
                    </div>

                    <button 
                        disabled={uploading}
                        className={`w-full py-3 rounded font-bold text-white transition-all ${uploading ? 'bg-stone-400' : 'bg-stone-900 hover:bg-black'}`}
                    >
                        {uploading ? 'Đang tải lên...' : 'Thêm Banner'}
                    </button>
                </form>
            </div>
        </div>

        {/* DANH SÁCH BANNER */}
        <div className="lg:col-span-2">
            <h3 className="font-bold text-lg mb-4 flex items-center gap-2"><FaImage /> Banner Hiện Tại</h3>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                {loading ? <p>Đang tải...</p> : banners.length === 0 ? <p className="text-stone-500 italic">Chưa có banner nào.</p> : (
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
    </div>
  );
};

export default Appearance;