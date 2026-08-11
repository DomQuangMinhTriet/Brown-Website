// client/src/pages/ProductDetail.jsx
import { useState, useEffect } from 'react';
import { useParams, Link } from 'react-router-dom';
import axios from 'axios';
import { useCart } from '../context/CartContext';
import { FaHistory, FaChevronRight, FaChevronLeft, FaInfoCircle, FaCheckCircle, FaPlay } from 'react-icons/fa';
import SEO from '../components/SEO';
import { useLanguage } from '../context/LanguageContext';
import { formatPrice, getEffectivePrice } from '../utils/currencyHelper';
import { optimizeImage as getOptimizedImageUrl } from '../utils/cloudinaryHelper';
import Container from '../components/ui/Container';
import Button from '../components/ui/Button';
import ProductCard from '../components/ui/ProductCard';

const ProductDetail = () => {
    const { slug } = useParams();
    const [product, setProduct] = useState(null);
    const [selectedVariant, setSelectedVariant] = useState(null);
    const { addToCart } = useCart();
    const { t, lang } = useLanguage();

    const [relatedProducts, setRelatedProducts] = useState([]);
    const [viewedProducts, setViewedProducts] = useState([]);
    const [mainImage, setMainImage] = useState(null);

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

    useEffect(() => {
        const fetchProductData = async () => {
            // Reset ngay khi đổi sản phẩm để không hiển thị dữ liệu cũ (URL đã đổi nhưng ảnh/chữ còn của SP trước)
            setProduct(null);
            setSelectedVariant(null);
            setMainImage(null);
            try {
                // Chỉ tải đúng 1 sản phẩm theo slug, không kéo cả catalog về client
                const res = await axios.get(`${import.meta.env.VITE_API_URL}/api/products/${slug}`);
                if (!res.data.success) return;
                const found = res.data.data;
                setProduct(found);
                setMainImage(found.images?.[0] || null);
                saveToViewedHistory(found);

                // Sản phẩm liên quan: chỉ gọi API cho đúng danh mục của sản phẩm này
                const catSlug = found.categories?.slug;
                if (catSlug) {
                    try {
                        const relRes = await axios.get(`${import.meta.env.VITE_API_URL}/api/products?category=${encodeURIComponent(catSlug)}&limit=5`);
                        if (relRes.data.success) {
                            setRelatedProducts(relRes.data.data.filter(p => p.id !== found.id).slice(0, 4));
                        }
                    } catch (e) { console.error("Lỗi tải sản phẩm liên quan:", e); }
                } else {
                    setRelatedProducts([]);
                }

                // Sản phẩm đã xem: dùng luôn dữ liệu đã cache trong localStorage
                const localHistory = JSON.parse(localStorage.getItem('viewed_products') || '[]');
                setViewedProducts(localHistory.filter(p => p.id !== found.id).slice(0, 4));
            } catch (error) {
                console.error("Lỗi tải sản phẩm:", error);
            }
        };

        fetchProductData();
        window.scrollTo(0, 0);
    }, [slug]);

    // Video luôn hiển thị sau cùng, sau tất cả ảnh
    const galleryMedia = [...(product?.images || []), ...(product?.videos || [])];
    const videoUrls = new Set(product?.videos || []);
    const isVideoMedia = (url) => videoUrls.has(url);
    const orderedVariants = [...(product?.variants || [])].sort((first, second) =>
        Number(first.display_order ?? Number.MAX_SAFE_INTEGER) - Number(second.display_order ?? Number.MAX_SAFE_INTEGER)
        || Number(first.id) - Number(second.id)
    );

    // SMART PRELOAD: tải ngầm ảnh trái/phải khi mainImage đổi (bỏ qua video)
    useEffect(() => {
        if (!product?.images?.length || !mainImage || (product?.videos || []).includes(mainImage)) return;

        const currentIndex = product.images.indexOf(mainImage);
        if (currentIndex === -1) return;

        const prevIndex = currentIndex <= 0 ? product.images.length - 1 : currentIndex - 1;
        const nextIndex = currentIndex >= product.images.length - 1 ? 0 : currentIndex + 1;

        const imgPrev = new Image();
        imgPrev.src = getOptimizedImageUrl(product.images[prevIndex], 800);

        const imgNext = new Image();
        imgNext.src = getOptimizedImageUrl(product.images[nextIndex], 800);
    }, [mainImage, product?.images, product?.videos]);

    const getStock = (variant) => variant ? variant.quantity_remaining : 0;

    const handlePrevImage = () => {
        if (galleryMedia.length < 2) return;
        const currentIndex = galleryMedia.indexOf(mainImage);
        const prevIndex = currentIndex <= 0 ? galleryMedia.length - 1 : currentIndex - 1;
        setMainImage(galleryMedia[prevIndex]);
    };

    const handleNextImage = () => {
        if (galleryMedia.length < 2) return;
        const currentIndex = galleryMedia.indexOf(mainImage);
        const nextIndex = currentIndex >= galleryMedia.length - 1 ? 0 : currentIndex + 1;
        setMainImage(galleryMedia[nextIndex]);
    };

    const mainImageUrl = mainImage || product?.images?.[0] || 'https://via.placeholder.com/500';

    const handleMainImageError = (event) => {
        const image = event.currentTarget;

        // Some uploaded assets have a working smaller Cloudinary derivative,
        // but fail when a large one is requested. Fall back to the same 200px
        // derivative that is used successfully by the thumbnail.
        if (image.dataset.usedThumbnailFallback !== 'true') {
            image.dataset.usedThumbnailFallback = 'true';
            image.src = getOptimizedImageUrl(mainImageUrl, 200);
            return;
        }

        // A direct original remains the final fallback for assets without a
        // usable Cloudinary derivative.
        if (image.dataset.usedOriginalFallback === 'true' || !mainImageUrl) return;
        image.dataset.usedOriginalFallback = 'true';
        image.src = mainImageUrl;
    };

    if (!product) return <div className="flex min-h-screen items-center justify-center font-heading text-muted">{t('product.loading')}</div>;

    const isOutOfStock = getStock(selectedVariant) <= 0;
    const canBuy = selectedVariant && (product.is_preorder || !isOutOfStock);

    return (
        <div className="min-h-screen bg-cream pb-20 pt-10">
            <SEO
                title={lang === 'en' && product.name_en ? product.name_en : product.name}
                description={(lang === 'en' && product.description_en ? product.description_en : product.description)?.substring(0, 150) + "..."}
                image={product.images?.[0]}
                url={`/product/${product.slug}`}
            />

            <Container className="max-w-6xl">
                <div className="mb-20 grid grid-cols-1 gap-12 md:grid-cols-2">
                    {/* Cột Trái: Ảnh */}
                    <div className="space-y-4">
                        <div className="group relative aspect-[3/4] overflow-hidden rounded-2xl bg-parchment">
                            {isVideoMedia(mainImage) ? (
                                <video
                                    key={mainImage}
                                    src={mainImage}
                                    className="h-full w-full object-cover"
                                    controls
                                    autoPlay
                                    muted
                                    loop
                                    playsInline
                                />
                            ) : (
                                <img
                                    key={mainImageUrl}
                                    src={getOptimizedImageUrl(mainImageUrl, 1000)}
                                    alt={product.name}
                                    className="h-full w-full object-cover"
                                    fetchPriority="high"
                                    decoding="async"
                                    onError={handleMainImageError}
                                />
                            )}

                            {galleryMedia.length > 1 && (
                                <>
                                    <button onClick={handlePrevImage} aria-label="Ảnh trước"
                                        className="absolute left-4 top-1/2 z-10 flex h-10 w-10 -translate-y-1/2 items-center justify-center rounded-full bg-cream/85 text-cocoa shadow-lg backdrop-blur-sm transition-opacity active:scale-95 md:opacity-0 md:group-hover:opacity-100">
                                        <FaChevronLeft />
                                    </button>
                                    <button onClick={handleNextImage} aria-label="Ảnh tiếp theo"
                                        className="absolute right-4 top-1/2 z-10 flex h-10 w-10 -translate-y-1/2 items-center justify-center rounded-full bg-cream/85 text-cocoa shadow-lg backdrop-blur-sm transition-opacity active:scale-95 md:opacity-0 md:group-hover:opacity-100">
                                        <FaChevronRight />
                                    </button>
                                </>
                            )}
                        </div>

                        {/* Thumbnails: ảnh trước, video sau cùng */}
                        {galleryMedia.length > 1 && (
                            <div className="grid grid-cols-4 gap-2">
                                {galleryMedia.map((media, idx) => (
                                    <button
                                        key={idx}
                                        onClick={() => setMainImage(media)}
                                        className={`relative aspect-[3/4] overflow-hidden rounded-xl transition-all ${mainImage === media ? 'opacity-100 ring-2 ring-cocoa' : 'opacity-60 hover:opacity-90'}`}
                                    >
                                        {isVideoMedia(media) ? (
                                            <>
                                                <video src={media} className="h-full w-full object-cover" muted playsInline />
                                                <span className="absolute inset-0 flex items-center justify-center bg-espresso/20">
                                                    <FaPlay className="text-cream drop-shadow" size={14} />
                                                </span>
                                            </>
                                        ) : (
                                            <img src={getOptimizedImageUrl(media, 200)} className="h-full w-full object-cover" alt="" loading="lazy" decoding="async" />
                                        )}
                                    </button>
                                ))}
                            </div>
                        )}
                    </div>

                    {/* Cột Phải: Thông tin */}
                    <div className="flex h-full flex-col">
                        <div className="mb-auto">
                            <h1 className="mb-3 font-heading text-3xl leading-tight text-espresso md:text-4xl">
                                {lang === 'en' && product.name_en ? product.name_en : product.name}
                            </h1>

                            {(() => {
                                const eff = getEffectivePrice(product, selectedVariant);
                                const cur = lang === 'en' ? 'USD' : 'VND';
                                return eff.isDiscounted ? (
                                    <p className="mb-3 flex flex-wrap items-baseline gap-3">
                                        <span className="text-2xl font-semibold text-clay">{formatPrice(eff.price, cur)}</span>
                                        <span className="text-lg text-muted line-through">{formatPrice(eff.original, cur)}</span>
                                        <span className="rounded-full bg-clay/15 px-2 py-0.5 text-xs font-semibold uppercase text-clay">{lang === 'en' ? 'Sale' : 'Giảm giá'}</span>
                                    </p>
                                ) : (
                                    <p className="mb-3 text-2xl font-medium text-cocoa">{formatPrice(eff.price, cur)}</p>
                                );
                            })()}

                            <p className="mb-8 flex items-center gap-2 text-sm text-clay">
                                <FaCheckCircle className="shrink-0" />
                                {lang === 'en' ? 'All products shown are in stock.' : 'Tất cả sản phẩm được hiển thị đều đang có sẵn.'}
                            </p>

                            {/* Chọn Biến thể */}
                            <div className="mb-8">
                                <label className="mb-3 block text-xs font-semibold uppercase tracking-wider text-muted">{t('product.select_variant')}</label>
                                <div className="flex flex-wrap gap-2">
                                    {orderedVariants.map(variant => (
                                        <button
                                            key={variant.id}
                                            onClick={() => {
                                                setSelectedVariant(variant);
                                                if (variant.image_url) setMainImage(variant.image_url);
                                            }}
                                            className={`relative min-w-[80px] overflow-hidden rounded-full border px-5 py-2 text-sm transition-all
                                                ${selectedVariant?.id === variant.id
                                                    ? 'border-cocoa bg-cocoa text-cream'
                                                    : 'border-sand text-ink hover:border-cocoa'}
                                                ${!product.is_preorder && getStock(variant) <= 0 ? 'cursor-not-allowed bg-parchment opacity-50' : ''}`}
                                            disabled={!product.is_preorder && getStock(variant) <= 0}
                                        >
                                            {variant.size} - {lang === 'en' && variant.color_en ? variant.color_en : variant.color}
                                            {getStock(variant) > 0 && getStock(variant) < 5 && (
                                                <span className="absolute right-1 top-1 h-2 w-2 rounded-full bg-clay"></span>
                                            )}
                                        </button>
                                    ))}
                                </div>
                                {selectedVariant && (
                                    <div className="mt-3 text-xs font-medium">
                                        {getStock(selectedVariant) > 0
                                            ? <span className="text-muted">{t('product.in_stock')} {getStock(selectedVariant)}</span>
                                            : product.is_preorder
                                                ? <span className="font-semibold text-cocoa">{lang === 'en' ? 'Available for Pre-order' : 'Sản phẩm này cho phép Đặt trước (Pre-order)'}</span>
                                                : <span className="text-clay">{t('product.out_of_stock')}</span>}
                                    </div>
                                )}
                            </div>

                            {/* Ghi chú preorder */}
                            {product.is_preorder && product.preorder_note && (
                                <div className="mb-6 rounded-xl border border-sand bg-parchment/60 p-4">
                                    <p className="flex items-start gap-2 text-sm text-ink">
                                        <FaInfoCircle className="mt-0.5 shrink-0 text-cocoa" />
                                        <span>{product.preorder_note}</span>
                                    </p>
                                </div>
                            )}

                            {/* Nút Mua */}
                            <Button
                                onClick={() => addToCart(product, selectedVariant, 1)}
                                disabled={!canBuy}
                                variant="clay"
                                size="lg"
                                className="mb-8 w-full"
                            >
                                {!selectedVariant
                                    ? t('product.select_variant')
                                    : isOutOfStock
                                        ? (product.is_preorder ? (lang === 'en' ? 'PRE-ORDER NOW' : 'ĐẶT TRƯỚC SẢN PHẨM NÀY') : t('product.out_of_stock'))
                                        : t('product.add_to_cart')}
                            </Button>

                            {/* Mô tả & Size chart */}
                            <div className="border-t border-sand pt-6">
                                <h2 className="mb-3 text-sm font-semibold uppercase tracking-wider text-cocoa">{t('product.details')}</h2>
                                <p className="mb-6 whitespace-pre-line text-sm leading-relaxed text-ink/80">
                                    {lang === 'en' && product.description_en ? product.description_en : (product.description || t('product.no_description'))}
                                </p>

                                <div className="mt-4">
                                    <h3 className="mb-2 text-xs font-semibold uppercase tracking-wider text-cocoa">{t('product.size_chart')}</h3>
                                    {product.size_chart_url ? (
                                        <div className="overflow-hidden rounded-xl border border-sand">
                                            <img src={getOptimizedImageUrl(product.size_chart_url, 600)} alt="Size Chart" className="h-auto w-full object-cover" loading="lazy" />
                                        </div>
                                    ) : (
                                        <div className="overflow-hidden rounded-xl border border-sand">
                                            <img src="https://file.hstatic.net/200000185994/file/bang_size_ao_thun_nam_ad12822a16c44284ab94132808c1650c_1024x1024.jpg" alt="Size Chart Default" className="h-auto w-full object-cover opacity-50" loading="lazy" />
                                            <p className="p-2 text-center text-xs text-muted">{t('product.no_size_chart')}</p>
                                        </div>
                                    )}
                                </div>
                            </div>
                        </div>
                    </div>
                </div>

                {/* SẢN PHẨM LIÊN QUAN */}
                {relatedProducts.length > 0 && (
                    <div className="mb-20">
                        <div className="mb-8 flex items-center justify-between border-b border-sand pb-4">
                            <h2 className="font-heading text-2xl text-espresso md:text-3xl">{t('product.related_products')}</h2>
                            <Link to="/collection" className="text-xs font-semibold uppercase tracking-wider text-cocoa transition-colors hover:text-clay">{t('product.view_all')}</Link>
                        </div>
                        <div className="grid grid-cols-2 gap-x-5 gap-y-10 md:grid-cols-4 md:gap-x-6">
                            {relatedProducts.map(p => <ProductCard key={p.id} product={p} />)}
                        </div>
                    </div>
                )}

                {/* SẢN PHẨM ĐÃ XEM */}
                {viewedProducts.length > 0 && (
                    <div>
                        <div className="mb-8 flex items-center gap-3 border-b border-sand pb-4">
                            <FaHistory className="text-muted" />
                            <h2 className="font-heading text-2xl text-espresso md:text-3xl">{t('product.viewed_products')}</h2>
                        </div>
                        <div className="grid grid-cols-2 gap-x-5 gap-y-10 md:grid-cols-4 md:gap-x-6">
                            {viewedProducts.map(p => <ProductCard key={p.id} product={p} />)}
                        </div>
                    </div>
                )}
            </Container>
        </div>
    );
};

export default ProductDetail;
