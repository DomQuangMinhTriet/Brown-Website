/* eslint-disable no-unused-vars */
import { useState, useEffect, useRef } from 'react';
import axios from 'axios';
import imageCompression from 'browser-image-compression';
import { FaTrash, FaPlus, FaImage, FaCloudUploadAlt, FaList, FaEye, FaEyeSlash, FaGripVertical, FaQuoteRight, FaVideo } from 'react-icons/fa';
import { toast } from 'react-toastify';
import LookbookBlocks from '../../components/lookbook/LookbookBlocks';
import { toLookbookBlock, isVideoUrl } from '../../components/lookbook/blockUtils';
import { optimizeImage } from '../../utils/cloudinaryHelper';

// [AN TOÀN] Nén ảnh (banner/lookbook) ngay trên trình duyệt trước khi upload —
// giống cách ProductModal đã làm cho ảnh sản phẩm — để tránh 1 ảnh chụp thẳng
// từ điện thoại (vài MB, độ phân giải rất cao) bị đẩy nguyên lên Cloudinary.
// Bỏ qua video vì thư viện nén chỉ xử lý được ảnh.
const compressIfImage = async (file) => {
  if (!file || !file.type?.startsWith('image/')) return file;
  try {
    return await imageCompression(file, { maxSizeMB: 3, maxWidthOrHeight: 2400 });
  } catch (err) {
    console.error('Lỗi nén ảnh, dùng file gốc:', err);
    return file;
  }
};

const Appearance = () => {
  // --- STATE BANNER ---
  const [banners, setBanners] = useState([]); 
  const [loading, setLoading] = useState(true);
  const [newBanner, setNewBanner] = useState({ title: '', link_to: '', display_order: 0 });
  const [file, setFile] = useState(null);
  const [uploading, setUploading] = useState(false);
  const [draggedBannerId, setDraggedBannerId] = useState(null);

  // --- [MỚI] STATE DANH MỤC ---
  const [categories, setCategories] = useState([]);

  // --- STATE LOOKBOOK ---
  const [lookbook, setLookbook] = useState([]);
  const [lookUploading, setLookUploading] = useState(false);
  const [dragId, setDragId] = useState(null);

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    try {
      setLoading(true);
      // Gọi các API cùng lúc
      const [bannerRes, catRes, lookRes] = await Promise.all([
          axios.get(`${import.meta.env.VITE_API_URL}/api/content/banners`),
          axios.get(`${import.meta.env.VITE_API_URL}/api/categories`),
          axios.get(`${import.meta.env.VITE_API_URL}/api/content/lookbook`).catch(() => ({ data: { data: [] } }))
      ]);

      // Xử lý Banner
      if (bannerRes.data && Array.isArray(bannerRes.data.data)) {
        setBanners(bannerRes.data.data);
      }

      // Xử lý Danh mục
      if (catRes.data && Array.isArray(catRes.data.data)) {
        setCategories(catRes.data.data);
      }

      // Xử lý Lookbook
      if (lookRes.data && Array.isArray(lookRes.data.data)) {
        setLookbook(lookRes.data.data);
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
    formData.append('image', await compressIfImage(file));
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

  const reorderBanners = async (targetId) => {
      if (draggedBannerId === null || draggedBannerId === targetId) return;
      const sourceIndex = banners.findIndex((banner) => banner.id === draggedBannerId);
      const targetIndex = banners.findIndex((banner) => banner.id === targetId);
      if (sourceIndex < 0 || targetIndex < 0) return;
      const reordered = [...banners];
      const [moved] = reordered.splice(sourceIndex, 1);
      reordered.splice(targetIndex, 0, moved);
      const ordered = reordered.map((banner, index) => ({ ...banner, display_order: index }));
      setBanners(ordered);
      try {
          await Promise.all(ordered.map((banner) => axios.put(`${import.meta.env.VITE_API_URL}/api/content/banners/${banner.id}`, { display_order: banner.display_order })));
      } catch (error) {
          toast.error('Không thể lưu thứ tự banner.');
          fetchData();
      }
  };

  // ==========================================================
  // LOGIC LOOKBOOK
  // ==========================================================
  const uploadFile = async (f) => {
    if (!f) return null;
    const fd = new FormData();
    fd.append('image', await compressIfImage(f));
    const res = await axios.post(`${import.meta.env.VITE_API_URL}/api/upload`, fd, {
      headers: { 'Content-Type': 'multipart/form-data' }
    });
    return res.data.url;
  };

  // Tải nhiều ảnh/video 1 lần — mỗi file thành 1 khối "Ảnh tràn viền" riêng
  const handleBulkUpload = async (fileList) => {
    const files = Array.from(fileList || []);
    if (!files.length) return;
    setLookUploading(true);
    try {
      let order = lookbook.length ? Math.max(...lookbook.map(l => l.display_order || 0)) + 1 : 0;
      const created = [];
      for (const f of files) {
        const image_url = await uploadFile(f);
        if (!image_url) continue;
        const res = await axios.post(`${import.meta.env.VITE_API_URL}/api/content/lookbook`, {
          title: '', caption: '', image_url, image_url_2: null, block_type: 'full', display_order: order++,
        });
        if (res.data.success) created.push(res.data.data);
      }
      if (created.length) {
        setLookbook(prev => [...prev, ...created]);
        toast.success(`Đã tải lên ${created.length} ảnh/video!`);
      }
    } catch (err) {
      console.error(err);
      toast.error("Lỗi khi tải lên");
    } finally {
      setLookUploading(false);
    }
  };

  // Thêm khối "câu trích dẫn" — chỉ chữ, không cần ảnh
  const handleAddQuote = async () => {
    try {
      const order = lookbook.length ? Math.max(...lookbook.map(l => l.display_order || 0)) + 1 : 0;
      const res = await axios.post(`${import.meta.env.VITE_API_URL}/api/content/lookbook`, {
        title: '', caption: 'Nhập câu trích dẫn...', block_type: 'quote', display_order: order,
      });
      if (res.data.success) {
        setLookbook(prev => [...prev, res.data.data]);
      }
    } catch (err) {
      toast.error("Lỗi tạo khối trích dẫn");
    }
  };

  const handleDeleteLook = async (id) => {
    if (!confirm("Bạn chắc chắn muốn xóa mục lookbook này?")) return;
    try {
      await axios.delete(`${import.meta.env.VITE_API_URL}/api/content/lookbook/${id}`);
      setLookbook(lookbook.filter(l => l.id !== id));
      toast.success("Đã xóa mục lookbook");
    } catch (error) {
      toast.error("Lỗi xóa");
    }
  };

  // Lưu thay đổi 1 mục (title/caption/block_type/ảnh 2...)
  const handleUpdateLook = async (id, updates) => {
    try {
      await axios.put(`${import.meta.env.VITE_API_URL}/api/content/lookbook/${id}`, updates);
      setLookbook(prev => prev.map(l => (l.id === id ? { ...l, ...updates } : l)));
      toast.success("Đã lưu thay đổi");
    } catch (error) {
      toast.error("Lỗi lưu thay đổi");
    }
  };

  const handleBlockTypeChange = async (item, newType) => {
    if (newType === 'compare' && !item.image_url_2) {
      toast.info('Hãy tải "Ảnh 2" bên dưới khối này để bật slider so sánh.');
    }
    if (newType !== 'compare' && item.image_url_2) {
      await handleUpdateLook(item.id, { block_type: newType, image_url_2: null });
      return;
    }
    await handleUpdateLook(item.id, { block_type: newType });
  };

  const handleSetSecondMedia = async (id, file) => {
    const url = await uploadFile(file);
    if (!url) return toast.error("Lỗi upload Ảnh 2");
    await handleUpdateLook(id, { image_url_2: url, block_type: 'compare' });
  };

  // --- KÉO THẢ SẮP XẾP qua Pointer Events (gộp chuột + cảm ứng, chạy được trên mobile/tablet) ---
  const cardRefs = useRef({}); // id -> DOM node, dùng để biết đang kéo qua vị trí thẻ nào
  const dragRef = useRef(null); // id đang kéo (đọc được ngay trong listener, không bị stale closure)
  const lookbookRef = useRef(lookbook); // bản mới nhất của lookbook, đọc trong handlePointerUp để tránh stale closure
  useEffect(() => { lookbookRef.current = lookbook; }, [lookbook]);

  const persistOrder = async (list) => {
    const reordered = list.map((item, idx) => ({ ...item, display_order: idx }));
    setLookbook(reordered);
    try {
      await Promise.all(reordered.map(item =>
        axios.put(`${import.meta.env.VITE_API_URL}/api/content/lookbook/${item.id}`, { display_order: item.display_order })
      ));
    } catch (error) {
      toast.error("Lỗi lưu thứ tự, vui lòng thử lại");
    }
  };

  const handlePointerMove = (e) => {
    const draggingId = dragRef.current;
    if (draggingId == null) return;
    const y = e.clientY;

    // Fix: sắp xếp thẻ theo vị trí Y THỰC TẾ trên màn hình (không phải theo ID),
    // tránh lỗi Object.entries duyệt theo ID tăng dần thay vì thứ tự visual.
    const sorted = Object.entries(cardRefs.current)
      .filter(([cid, node]) => node && Number(cid) !== draggingId)
      .map(([cid, node]) => {
        const rect = node.getBoundingClientRect();
        return { id: Number(cid), mid: rect.top + rect.height / 2 };
      })
      .sort((a, b) => a.mid - b.mid);

    // Thẻ đầu tiên (tính từ trên xuống) mà cursor đang ở TRÊN điểm giữa → chèn TRƯỚC nó.
    // Nếu cursor dưới tất cả thẻ → insertBeforeId = null = chèn vào CUỐI.
    let insertBeforeId = null;
    for (const card of sorted) {
      if (y < card.mid) { insertBeforeId = card.id; break; }
    }

    setLookbook(prev => {
      const fromIdx = prev.findIndex(l => l.id === draggingId);
      if (fromIdx === -1) return prev;

      const list = [...prev];
      const [moved] = list.splice(fromIdx, 1); // rút ra trước

      if (insertBeforeId == null) {
        list.push(moved); // Fix: cursor dưới tất cả → chèn đúng vào CUỐI
      } else {
        // Tìm vị trí trong list ĐÃ RÚT — không cần bù thêm, index đã chính xác
        const insertIdx = list.findIndex(l => l.id === insertBeforeId);
        list.splice(insertIdx === -1 ? list.length : insertIdx, 0, moved);
      }

      return list;
    });
  };

  const handlePointerUp = () => {
    window.removeEventListener('pointermove', handlePointerMove);
    window.removeEventListener('pointerup', handlePointerUp);
    dragRef.current = null;
    setDragId(null);
    persistOrder(lookbookRef.current); // lưu ngay (optimistic) sau khi thả
  };

  const handleGripPointerDown = (e, id) => {
    e.preventDefault();
    dragRef.current = id;
    setDragId(id);
    window.addEventListener('pointermove', handlePointerMove);
    window.addEventListener('pointerup', handlePointerUp);
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
                    <div key={banner.id} draggable
                        onDragStart={() => setDraggedBannerId(banner.id)}
                        onDragOver={(event) => event.preventDefault()}
                        onDrop={() => { reorderBanners(banner.id); setDraggedBannerId(null); }}
                        onDragEnd={() => setDraggedBannerId(null)}
                        className={`bg-white rounded-xl shadow border overflow-hidden relative group cursor-grab active:cursor-grabbing ${draggedBannerId === banner.id ? 'opacity-40 ring-2 ring-stone-900' : ''}`}>
                        <div className="aspect-[4/5] w-full bg-stone-100 relative">
                            <img
                                src={optimizeImage(banner.image_url, 800)}
                                alt={banner.title}
                                className="w-full h-full object-cover"
                                loading="lazy"
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

      <hr className="border-stone-200" />

      {/* --- PHẦN 3: QUẢN LÝ LOOKBOOK --- */}
      <div>
        <h2 className="text-2xl font-serif font-bold text-stone-800 mb-2 flex items-center gap-2">
            <FaImage /> Lookbook (Tạp ảnh)
        </h2>
        <p className="text-stone-500 mb-6 text-sm">
            Nội dung editorial cho trang <span className="font-mono">/lookbook</span>. Tải nhiều ảnh/video 1 lần, <b>kéo-thả</b> để sắp xếp, sửa từng khối để đổi kiểu hiển thị. Xem trước ở cột bên phải.
        </p>

        {/* Vùng tải nhiều ảnh/video 1 lần */}
        <div className="mb-6 flex flex-wrap items-center gap-3">
            <div className="relative flex-1 min-w-[260px] cursor-pointer rounded-lg border-2 border-dashed border-stone-300 p-4 text-center transition-colors hover:bg-stone-50">
                <input type="file" accept="image/*,video/*" multiple disabled={lookUploading}
                    className="absolute inset-0 cursor-pointer opacity-0"
                    onChange={e => { handleBulkUpload(e.target.files); e.target.value = ''; }} />
                <div className="flex flex-col items-center justify-center text-stone-500">
                    <FaCloudUploadAlt size={22} className="mb-1"/>
                    <span className="text-sm font-medium">
                        {lookUploading ? 'Đang tải lên...' : 'Chọn nhiều ảnh/video — mỗi file thành 1 khối riêng'}
                    </span>
                </div>
            </div>
            <button onClick={handleAddQuote} type="button"
                className="flex items-center gap-2 rounded-lg border border-stone-300 px-4 py-3 text-sm font-bold text-stone-700 transition-colors hover:bg-stone-50">
                <FaQuoteRight /> Thêm câu trích dẫn
            </button>
        </div>

        <div className="grid grid-cols-1 gap-8 lg:grid-cols-2">
            {/* Danh sách khối — kéo-thả để sắp xếp */}
            <div className="space-y-3">
                {lookbook.length === 0 ? (
                    <div className="rounded border border-dashed bg-stone-50 py-10 text-center text-stone-400">
                        Chưa có nội dung lookbook nào — hãy tải ảnh lên ở trên.
                    </div>
                ) : (
                    lookbook.map(item => (
                        <LookbookCard
                            key={item.id}
                            item={item}
                            registerRef={(node) => { cardRefs.current[item.id] = node; }}
                            isDragging={dragId === item.id}
                            onGripPointerDown={(e) => handleGripPointerDown(e, item.id)}
                            onUpdate={(updates) => handleUpdateLook(item.id, updates)}
                            onTypeChange={(newType) => handleBlockTypeChange(item, newType)}
                            onSetSecondMedia={(file) => handleSetSecondMedia(item.id, file)}
                            onToggleActive={() => handleUpdateLook(item.id, { is_active: item.is_active === false })}
                            onDelete={() => handleDeleteLook(item.id)}
                        />
                    ))
                )}
            </div>

            {/* Xem trước trực tiếp — dùng đúng component hiển thị ở trang công khai */}
            <div className="lg:sticky lg:top-6 lg:h-fit">
                <h3 className="mb-3 flex items-center gap-2 font-bold text-stone-700">
                    <FaEye className="text-stone-400" /> Xem trước trang Lookbook
                </h3>
                <div className="h-[680px] overflow-y-auto rounded-2xl border border-stone-200 bg-cream">
                    {lookbook.length === 0 ? (
                        <div className="flex h-full items-center justify-center text-stone-400">Chưa có gì để xem trước</div>
                    ) : (
                        <LookbookBlocks blocks={lookbook.filter(l => l.is_active !== false).map(toLookbookBlock)} lang="vi" />
                    )}
                </div>
                <p className="mt-2 text-xs text-stone-400">Khung này phản ánh đúng giao diện thật trên /lookbook. Sửa chữ cần bấm "Lưu" mới cập nhật ở đây; kéo-thả thì cập nhật ngay.</p>
            </div>
        </div>
      </div>

    </div>
  );
};

// --- Thẻ 1 khối Lookbook: kéo-thả để sắp xếp + sửa nhanh title/caption/loại khối ---
const LookbookCard = ({ item, registerRef, isDragging, onGripPointerDown, onUpdate, onTypeChange, onSetSecondMedia, onToggleActive, onDelete }) => {
  const [draft, setDraft] = useState({ title: item.title || '', caption: item.caption || '' });
  const dirty = draft.title !== (item.title || '') || draft.caption !== (item.caption || '');
  const blockType = item.block_type || (item.image_url_2 ? 'compare' : 'full');
  const video = isVideoUrl(item.image_url);

  return (
    <div
      ref={registerRef}
      className={`flex gap-3 rounded-lg border border-stone-200 bg-white p-3 shadow-sm transition-opacity ${isDragging ? 'opacity-40' : ''}`}
    >
      <div
        onPointerDown={onGripPointerDown}
        className="flex touch-none items-center text-stone-300 active:cursor-grabbing"
        style={{ cursor: 'grab' }}
        title="Kéo để sắp xếp"
      >
        <FaGripVertical />
      </div>

      <div className="h-20 w-16 shrink-0 overflow-hidden rounded bg-stone-100">
        {blockType === 'quote' ? (
          <div className="flex h-full w-full items-center justify-center text-stone-400"><FaQuoteRight /></div>
        ) : video ? (
          <video src={item.image_url} muted className="h-full w-full object-cover" />
        ) : item.image_url ? (
          <img src={optimizeImage(item.image_url, 150)} alt={item.title || ''} className="h-full w-full object-cover" loading="lazy"
            onError={(e) => { e.target.src = 'https://via.placeholder.com/100x120?text=Lỗi'; }} />
        ) : null}
      </div>

      <div className="flex-1 space-y-2">
        <div className="flex items-center gap-2">
          <select value={blockType} onChange={(e) => onTypeChange(e.target.value)}
            className="rounded border border-stone-200 bg-white px-2 py-1 text-xs font-bold uppercase text-stone-600">
            <option value="full">Ảnh/Video tràn viền</option>
            <option value="compare">Slider so sánh (2 ảnh)</option>
            <option value="quote">Câu trích dẫn</option>
          </select>
          {video && <span className="flex items-center gap-1 text-[10px] font-bold uppercase text-stone-400"><FaVideo /> Video</span>}
          <button onClick={onToggleActive}
            className={`ml-auto transition-colors ${item.is_active === false ? 'text-stone-300 hover:text-stone-600' : 'text-stone-400 hover:text-stone-700'}`}
            title={item.is_active === false ? 'Đang ẨN trên trang Lookbook — bấm để hiện lại' : 'Đang HIỆN trên trang Lookbook — bấm để ẩn'}>
            {item.is_active === false ? <FaEyeSlash /> : <FaEye />}
          </button>
          <button onClick={onDelete} className="text-stone-400 transition-colors hover:text-red-500" title="Xóa">
            <FaTrash />
          </button>
        </div>
        {item.is_active === false && (
          <span className="inline-block rounded bg-stone-100 px-2 py-0.5 text-[10px] font-bold uppercase text-stone-500">Đang ẩn</span>
        )}

        {blockType !== 'quote' && (
          <input type="text" placeholder="Tiêu đề (tùy chọn)" value={draft.title}
            onChange={(e) => setDraft({ ...draft, title: e.target.value })}
            className="w-full rounded border border-stone-200 px-2 py-1 text-sm outline-none focus:border-stone-800" />
        )}
        <input type="text" placeholder={blockType === 'quote' ? 'Nội dung trích dẫn' : 'Mô tả ngắn (tùy chọn)'} value={draft.caption}
          onChange={(e) => setDraft({ ...draft, caption: e.target.value })}
          className="w-full rounded border border-stone-200 px-2 py-1 text-sm outline-none focus:border-stone-800" />

        {dirty && (
          <button onClick={() => onUpdate(draft)} className="rounded bg-stone-900 px-3 py-1 text-xs font-bold text-white transition-colors hover:bg-black">
            Lưu
          </button>
        )}

        {blockType === 'compare' && (
          <div className="relative rounded border-2 border-dashed border-stone-300 p-2 text-center text-xs text-stone-500 transition-colors hover:bg-stone-50">
            <input type="file" accept="image/*" className="absolute inset-0 cursor-pointer opacity-0"
              onChange={(e) => e.target.files[0] && onSetSecondMedia(e.target.files[0])} />
            {item.image_url_2 ? 'Đổi Ảnh 2 (đang có)' : 'Tải Ảnh 2 để bật slider'}
          </div>
        )}
      </div>
    </div>
  );
};

export default Appearance;
