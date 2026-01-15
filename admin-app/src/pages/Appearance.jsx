import { useState, useEffect } from 'react';
import axios from 'axios';
import { supabase } from '../context/AdminAuthContext'; // Hãy chắc chắn file này có export supabase
import { FaTrash, FaPlus, FaImage } from 'react-icons/fa';
import { toast } from 'react-toastify';

const Appearance = () => {
  // Khởi tạo là mảng rỗng [] để tránh lỗi .map()
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
      // Kiểm tra kỹ dữ liệu trả về có phải mảng không
      if (res.data && Array.isArray(res.data.data)) {
        setBanners(res.data.data);
      } else {
        setBanners([]); // Nếu lỗi thì set rỗng để không bị sập web
      }
    } catch (error) {
      console.error("Lỗi tải banner:", error);
      toast.error("Không tải được danh sách banner");
    } finally {
      setLoading(false);
    }
  };

  const handleUploadAndCreate = async (e) => {
    e.preventDefault();
    if (!file) return toast.error("Chưa chọn ảnh!");
    
    // Kiểm tra supabase có tồn tại không
    if (!supabase) {
        return toast.error("Lỗi cấu hình: Không tìm thấy Supabase Client");
    }

    setUploading(true);
    try {
      // 1. Upload ảnh
      const fileName = `${Date.now()}-${file.name.replace(/[^a-zA-Z0-9.]/g, '')}`; // Xóa ký tự lạ tên file
      const { data, error } = await supabase.storage
        .from('banners')
        .upload(fileName, file);

      if (error) throw error;

      // 2. Lấy URL ảnh (THAY ID DỰ ÁN CỦA BẠN VÀO ĐÂY)
      // Cách an toàn hơn: Dùng hàm getPublicUrl
      const { data: urlData } = supabase.storage.from('banners').getPublicUrl(fileName);
      const imageUrl = urlData.publicUrl;

      // 3. Lưu vào DB
      await axios.post('http://localhost:5000/api/content/banners', {
        ...newBanner,
        image_url: imageUrl
      });

      toast.success("Thêm banner thành công!");
      setNewBanner({ title: '', link_to: '', display_order: 0 });
      setFile(null);
      
      // Reset input file (trick)
      document.getElementById('fileInput').value = ""; 
      
      fetchBanners();

    } catch (error) {
      console.error(error);
      toast.error("Lỗi: " + (error.message || "Không thể upload"));
    } finally {
      setUploading(false);
    }
  };

  const handleDelete = async (id) => {
    if (!window.confirm("Xóa banner này?")) return;
    try {
      await axios.delete(`http://localhost:5000/api/content/banners/${id}`);
      fetchBanners();
      toast.success("Đã xóa");
    } catch (error) {
      toast.error("Lỗi xóa");
    }
  };

  return (
    <div className="p-8">
      <h1 className="text-2xl font-bold mb-6 text-stone-800 flex items-center gap-2">
         <FaImage /> Quản lý Giao diện
      </h1>

      {/* Form Thêm Banner */}
      <div className="bg-white p-6 rounded-xl shadow-sm border border-stone-200 mb-8">
        <h3 className="font-bold mb-4 flex items-center gap-2"><FaPlus/> Thêm Banner Mới</h3>
        <form onSubmit={handleUploadAndCreate} className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <input 
            type="text" placeholder="Tiêu đề (VD: Sale Mùa Hè)" className="p-2 border rounded" required
            value={newBanner.title} onChange={e=>setNewBanner({...newBanner, title: e.target.value})}
          />
          <input 
            type="text" placeholder="Link (VD: /products)" className="p-2 border rounded"
            value={newBanner.link_to} onChange={e=>setNewBanner({...newBanner, link_to: e.target.value})}
          />
          <input 
            type="number" placeholder="Thứ tự" className="p-2 border rounded"
            value={newBanner.display_order} onChange={e=>setNewBanner({...newBanner, display_order: e.target.value})}
          />
          <input 
            id="fileInput"
            type="file" accept="image/*" className="p-2 border rounded" required
            onChange={e=>setFile(e.target.files[0])}
          />
          <button disabled={uploading} className="col-span-2 bg-stone-900 text-white py-2 rounded font-bold hover:bg-stone-700 disabled:opacity-50">
            {uploading ? 'Đang tải lên...' : 'Lưu Banner'}
          </button>
        </form>
      </div>

      {/* Danh sách Banner */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        {loading ? <p>Đang tải...</p> : banners.length === 0 ? <p>Chưa có banner nào.</p> : (
            banners.map(banner => (
            <div key={banner.id} className="bg-white rounded-lg shadow border overflow-hidden relative group">
                <div className="h-40 w-full bg-gray-100 relative">
                    {/* Thêm check ảnh lỗi */}
                    <img 
                        src={banner.image_url} 
                        alt={banner.title} 
                        className="w-full h-full object-cover"
                        onError={(e) => {e.target.src = 'https://via.placeholder.com/400x200?text=Lỗi+Ảnh'}} 
                    />
                </div>
                <div className="p-4">
                <h4 className="font-bold text-stone-800">{banner.title}</h4>
                <p className="text-xs text-stone-500 mb-2 truncate">Link: {banner.link_to}</p>
                <div className="flex justify-between items-center mt-2">
                    <span className="text-xs bg-stone-100 px-2 py-1 rounded">Thứ tự: {banner.display_order}</span>
                    <button onClick={() => handleDelete(banner.id)} className="text-red-500 hover:text-red-700 p-2"><FaTrash/></button>
                </div>
                </div>
            </div>
            ))
        )}
      </div>
    </div>
  );
};

export default Appearance;