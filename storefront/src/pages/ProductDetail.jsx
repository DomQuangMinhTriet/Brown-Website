// client/src/pages/ProductDetail.jsx
import { useState, useEffect } from 'react';
import { useParams, Link } from 'react-router-dom';
import axios from 'axios';
import { useCart } from '../context/CartContext';
import { FaStar, FaCheck, FaHistory, FaBoxOpen, FaChevronRight, FaChevronLeft } from 'react-icons/fa';
import SEO from '../components/SEO';
import { useLanguage } from '../context/LanguageContext';
import { formatPrice } from '../utils/currencyHelper';

const getOptimizedImageUrl = (url, width = 800) => {
    if (!url || !url.includes('cloudinary.com')) return url;
    const uploadIndex = url.indexOf('upload/') + 7;
    const transformations = `c_scale,w_${width},f_auto,q_auto/`;
    return url.substring(0, uploadIndex) + transformations + url.substring(uploadIndex);
};

const ProductCard = ({ product, lang }) => (
    <Link to={`/product/${product.slug}`} className="group block">
        <div className="aspect-[3/4] overflow-hidden rounded-lg mb-3 relative bg-stone-100">
            <img 
                src={getOptimizedImageUrl(product.images?.[0], 400)} 
                alt={product.name} 
                className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                loading="lazy"
                decoding="async"
            />
        </div>
        <h3 className="font-medium text-stone-900 text-sm truncate group-hover:text-stone-600 transition-colors">
            {lang === 'en' && product.name_en ? product.name_en : product.name}
        </h3>
        <p className="text-stone-500 font-bold mt-1 text-sm">
            {formatPrice(product.base_price, lang === 'en' ? 'USD' : 'VND')}
        </p>
    </Link>
);

const ProductDetail = () => {
    const { slug } = useParams();
    const [product, setProduct] = useState(null);
    const [selectedVariant, setSelectedVariant] = useState(null);
    const { addToCart } = useCart();
    const { t, lang } = useLanguage();
    
    const [relatedProducts, setRelatedProducts] = useState([]);
    const [viewedProducts, setViewedProducts] = useState([]);
    const [mainImage, setMainImage] = useState(null);

    useEffect(() => {
        const fetchProductData = async () => {
            try {
                const res = await axios.get(`${import.meta.env.VITE_API_URL}/api/products`); 
                if (res.data.success) {
                    const allProducts = res.data.data;
                    const found = allProducts.find(p => p.slug === slug);
                    
                    if (found) {
                        setProduct(found);
                        
                        const related = allProducts.filter(p => 
                            p.category_id === found.category_id && p.id !== found.id
                        ).slice(0, 4);
                        setRelatedProducts(related);

                        saveToViewedHistory(found);

                        const localHistory = JSON.parse(localStorage.getItem('viewed_products') || '[]');
                        const validHistory = localHistory
                            .map(localItem => allProducts.find(realItem => realItem.id === localItem.id))
                            .filter(item => item !== undefined); 

                        localStorage.setItem('viewed_products', JSON.stringify(validHistory));
                        setViewedProducts(validHistory.filter(p => p.id !== found.id).slice(0, 4));
                    }
                }
            } catch (error) {
                console.error("Lỗi tải sản phẩm:", error);
            }
        };

        fetchProductData();
        window.scrollTo(0, 0); 
    }, [slug]);

    useEffect(() => {
        if (product?.images?.length > 0 && !mainImage) {
            setMainImage(product.images[0]);
        }
    }, [product?.id]);

    // [MỚI] SMART PRELOAD: Chỉ tải ngầm ảnh Trái và Phải khi mainImage thay đổi
    useEffect(() => {
        if (!product?.images?.length || !mainImage) return;

        const currentIndex = product.images.indexOf(mainImage);
        if (currentIndex === -1) return;

        // Tính toán vị trí của 2 ảnh lân cận
        const prevIndex = currentIndex <= 0 ? product.images.length - 1 : currentIndex - 1;
        const nextIndex = currentIndex >= product.images.length - 1 ? 0 : currentIndex + 1;

        // Chỉ tạo object Image tải ngầm đúng 2 ảnh này qua bộ nén Cloudinary
        const imgPrev = new Image(); 
        imgPrev.src = getOptimizedImageUrl(product.images[prevIndex], 800);
        
        const imgNext = new Image(); 
        imgNext.src = getOptimizedImageUrl(product.images[nextIndex], 800);

    }, [mainImage, product?.images]); // Chạy lại mỗi khi khách lướt sang ảnh mới

    const saveToViewedHistory = (currentProduct) => {
        try {
            const history = JSON.parse(localStorage.getItem('viewed_products') || '[]');
            const newHistory = history.filter(item => item.id !== currentProduct.id);
            newHistory.unshift({
                id: currentProduct.id,
                name: currentProduct.name,
                slug: currentProduct.slug,
                base_price: currentProduct.base_price,
                images: currentProduct.images
            });
            const limitedHistory = newHistory.slice(0, 8);
            localStorage.setItem('viewed_products', JSON.stringify(limitedHistory));
        } catch (e) { console.error(e); }
    };

    const getStock = (variant) => variant ? variant.quantity_remaining : 0;

    const handlePrevImage = () => {
        if (!product?.images?.length) return;
        const currentIndex = product.images.indexOf(mainImage);
        const prevIndex = currentIndex <= 0 ? product.images.length - 1 : currentIndex - 1;
        setMainImage(product.images[prevIndex]);
    };

    const handleNextImage = () => {
        if (!product?.images?.length) return;
        const currentIndex = product.images.indexOf(mainImage);
        const nextIndex = currentIndex >= product.images.length - 1 ? 0 : currentIndex + 1;
        setMainImage(product.images[nextIndex]);
    };

    if (!product) return <div className="min-h-screen flex justify-center items-center">{t('product.loading')}</div>;

    // Các biến kiểm tra trạng thái hiển thị nút mua
    const isOutOfStock = getStock(selectedVariant) <= 0;
    const canBuy = selectedVariant && (product.is_preorder || !isOutOfStock);

    return (
        <div className="min-h-screen pt-10 pb-20 px-4 bg-white">
             <SEO 
                title={lang === 'en' && product.name_en ? product.name_en : product.name} 
                description={(lang === 'en' && product.description_en ? product.description_en : product.description)?.substring(0, 150) + "..."} 
                image={product.images?.[0]} 
                url={`/product/${product.slug}`}
            />

            <div className="max-w-6xl mx-auto">
                <div className="grid grid-cols-1 md:grid-cols-2 gap-12 mb-20">
                    {/* Cột Trái: Ảnh */}
                    <div className="space-y-4">
                        <div className="rounded-xl overflow-hidden aspect-[3/4] relative group bg-stone-50">
                            <img 
                                key={mainImage}
                                src={getOptimizedImageUrl(mainImage || product.images?.[0] || 'https://via.placeholder.com/500', 800)} 
                                alt={product.name} 
                                className="w-full h-full object-cover transition-all animate-fade-in"
                                fetchPriority="high"
                            />
                            
                            {/* Nút chuyển ảnh */}
                            {product.images?.length > 1 && (
                                <>
                                    <button 
                                        onClick={handlePrevImage}
                                        className="absolute left-4 top-1/2 -translate-y-1/2 bg-white/80 hover:bg-white text-stone-800 w-10 h-10 flex items-center justify-center rounded-full shadow-lg opacity-100 md:opacity-0 md:group-hover:opacity-100 transition-opacity z-10 active:scale-95"
                                        aria-label="Ảnh trước"
                                    >
                                        <FaChevronLeft />
                                    </button>
                                    <button 
                                        onClick={handleNextImage}
                                        className="absolute right-4 top-1/2 -translate-y-1/2 bg-white/80 hover:bg-white text-stone-800 w-10 h-10 flex items-center justify-center rounded-full shadow-lg opacity-100 md:opacity-0 md:group-hover:opacity-100 transition-opacity z-10 active:scale-95"
                                        aria-label="Ảnh tiếp theo"
                                    >
                                        <FaChevronRight />
                                    </button>
                                </>
                            )}
                        </div>
                        
                        {/* Ảnh nhỏ (Thumbnails) */}
                        {product.images?.length > 1 && (
                            <div className="grid grid-cols-4 gap-2">
                                {product.images.map((img, idx) => (
                                    <div 
                                        key={idx} 
                                        onClick={() => setMainImage(img)} 
                                        className={`
                                            aspect-[3/4] rounded-lg overflow-hidden cursor-pointer hover:opacity-80 transition-all
                                            ${mainImage === img ? 'ring-2 ring-stone-900 opacity-100' : 'border border-transparent opacity-60'}
                                        `}
                                    >
                                        <img 
                                            src={getOptimizedImageUrl(img, 200)} 
                                            className="w-full h-full object-cover" 
                                            alt="" 
                                            loading="lazy" 
                                            decoding="async" 
                                        />
                                    </div>
                                ))}
                            </div>
                        )}
                    </div>

                    {/* Cột Phải: Thông tin */}
                    <div className="flex flex-col h-full">
                        <div className="mb-auto">
                            <h1 className="text-3xl font-serif text-stone-900 mb-2">
                                {lang === 'en' && product.name_en ? product.name_en : product.name}
                            </h1>
                            <div className="flex items-center gap-2 mb-6">
                            </div>

                            <p className="text-2xl font-bold text-stone-800 mb-8">
                                {formatPrice(product.base_price, lang === 'en' ? 'USD' : 'VND')}
                            </p>

                            {/* Chọn Biến thể */}
                            <div className="mb-8">
                                <label className="text-xs font-bold uppercase text-stone-500 mb-3 block">{t('product.select_variant')}</label>
                                <div className="flex flex-wrap gap-2">
                                    {product.variants?.map(variant => (
                                        <button
                                            key={variant.id}
                                            onClick={() => {
                                                setSelectedVariant(variant);
                                                if (variant.image_url) {
                                                    setMainImage(variant.image_url);
                                                }
                                            }}
                                            className={`
                                                min-w-[80px] px-4 py-2 border rounded-lg text-sm transition-all relative overflow-hidden
                                                ${selectedVariant?.id === variant.id 
                                                    ? 'border-stone-900 bg-stone-900 text-white' 
                                                    : 'border-stone-200 text-stone-600 hover:border-stone-900'}
                                                ${!product.is_preorder && getStock(variant) <= 0 ? 'opacity-50 cursor-not-allowed bg-stone-100' : ''}
                                            `}
                                            disabled={!product.is_preorder && getStock(variant) <= 0}
                                        >
                                            {variant.size} - {lang === 'en' && variant.color_en ? variant.color_en : variant.color}
                                            {getStock(variant) > 0 && getStock(variant) < 5 && (
                                                <span className="absolute top-0 right-0 w-2 h-2 bg-red-500 rounded-full"></span>
                                            )}
                                        </button>
                                    ))}
                                </div>
                                {selectedVariant && (
                                    <div className="mt-2 text-xs text-stone-500 font-medium">
                                        {getStock(selectedVariant) > 0 
                                            ? `${t('product.in_stock')} ${getStock(selectedVariant)}` 
                                            : product.is_preorder 
                                                ? <span className="text-blue-600 font-bold">{lang === 'en' ? 'Available for Pre-order' : 'Sản phẩm này cho phép Đặt trước (Pre-order)'}</span>
                                                : <span className="text-red-500">{t('product.out_of_stock')}</span>}
                                    </div>
                                )}
                            </div>

                            {/* HIỂN THỊ GHI CHÚ PREORDER NẾU CÓ */}
                            {product.is_preorder && product.preorder_note && (
                                <div className="mb-6 p-4 bg-blue-50 border border-blue-200 rounded-lg">
                                    <p className="text-sm text-blue-800 flex items-start gap-2">
                                        <span className="mt-0.5">ℹ️</span> 
                                        <span>{product.preorder_note}</span>
                                    </p>
                                </div>
                            )}

                            {/* Nút Mua */}
                            <button 
                                onClick={() => addToCart(product, selectedVariant, 1)}
                                disabled={!canBuy}
                                className={`
                                    w-full py-4 rounded-xl font-bold text-white uppercase tracking-wider shadow-lg transition-transform active:scale-95 mb-8
                                    ${!canBuy ? 'bg-stone-300 cursor-not-allowed shadow-none' : 'bg-red-600 hover:bg-red-700'}
                                `}
                            >
                                {!selectedVariant 
                                    ? t('product.select_variant') 
                                    : isOutOfStock 
                                        ? (product.is_preorder ? (lang === 'en' ? 'PRE-ORDER NOW' : 'ĐẶT TRƯỚC SẢN PHẨM NÀY') : t('product.out_of_stock')) 
                                        : t('product.add_to_cart')}
                            </button>

                            {/* --- MÔ TẢ & SIZE CHART --- */}
                            <div className="border-t border-stone-100 pt-6">
                                <h3 className="font-bold text-stone-700 mb-3 text-sm uppercase">{t('product.details')}</h3>
                                <p className="text-stone-600 leading-relaxed text-sm whitespace-pre-line mb-6">
                                    {lang === 'en' && product.description_en ? product.description_en : (product.description || t('product.no_description'))}
                                </p>

                                {/* ẢNH SIZE CHART */}
                                <div className="mt-4">
                                    <h4 className="font-bold text-stone-700 text-xs uppercase mb-2">{t('product.size_chart')}</h4>
                                    
                                    {product.size_chart_url ? (
                                        <div className="rounded-lg overflow-hidden border border-stone-200">
                                            <img 
                                                src={getOptimizedImageUrl(product.size_chart_url, 600)} 
                                                alt="Size Chart"
                                                className="w-full h-auto object-cover"
                                                loading="lazy"
                                            />
                                        </div>
                                    ) : (
                                        <div className="rounded-lg overflow-hidden border border-stone-200">
                                             <img 
                                                src="https://file.hstatic.net/200000185994/file/bang_size_ao_thun_nam_ad12822a16c44284ab94132808c1650c_1024x1024.jpg" 
                                                alt="Size Chart Default"
                                                className="w-full h-auto object-cover opacity-50"
                                                loading="lazy"
                                            />
                                            <p className="text-center text-xs text-stone-400 p-2">{t('product.no_size_chart')}</p>
                                        </div>
                                    )}
                                </div>
                            </div>
                        </div>
                    </div>
                </div>

                {/* --- PHẦN 2: SẢN PHẨM LIÊN QUAN --- */}
                {relatedProducts.length > 0 && (
                    <div className="mb-20">
                        <div className="flex items-center justify-between mb-6 border-b border-stone-200 pb-2">
                            <h2 className="text-xl font-serif font-bold text-stone-900">{t('product.related_products')}</h2>
                            <Link to="/collection" className="text-xs font-bold text-stone-500 hover:text-stone-900">{t('product.view_all')}</Link>
                        </div>
                        <div className="grid grid-cols-2 md:grid-cols-4 gap-x-4 gap-y-8">
                            {relatedProducts.map(p => <ProductCard key={p.id} product={p} lang={lang} />)}
                        </div>
                    </div>
                )}

                {/* --- PHẦN 3: SẢN PHẨM ĐÃ XEM --- */}
                {viewedProducts.length > 0 && (
                    <div>
                         <div className="flex items-center gap-2 mb-6 border-b border-stone-200 pb-2">
                            <FaHistory className="text-stone-400"/>
                            <h2 className="text-xl font-serif font-bold text-stone-900">{t('product.viewed_products')}</h2>
                        </div>
                        <div className="grid grid-cols-2 md:grid-cols-4 gap-x-4 gap-y-8">
                            {viewedProducts.map(p => <ProductCard key={p.id} product={p} lang={lang} />)}
                        </div>
                    </div>
                )}
            </div>

            {/* [MỚI] ĐỊNH NGHĨA CSS HIỆU ỨNG FADE-IN */}
            <style>{`
                @keyframes fade-in-smooth {
                    from { opacity: 0.6; }
                    to { opacity: 1; }
                }
                .animate-fade-in {
                    animation: fade-in-smooth 0.3s ease-out forwards;
                }
            `}</style>
        </div>
    );
};

export default ProductDetail;