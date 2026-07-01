import { useMemo, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { FaPlus, FaCheck } from 'react-icons/fa';
import { formatPrice, getEffectivePrice } from '../../utils/currencyHelper';
import { useLanguage } from '../../context/LanguageContext';
import { useCart } from '../../context/CartContext';

// Nén ảnh Cloudinary
const optimize = (url, w = 500) => {
  if (!url || typeof url !== 'string' || !url.includes('cloudinary.com')) return url;
  const i = url.indexOf('upload/') + 7;
  return url.slice(0, i) + `c_scale,w_${w},f_auto,q_auto/` + url.slice(i);
};

const SWIPE_THRESHOLD = 30;

/**
 * Thẻ sản phẩm dùng chung.
 * - Swatch MÀU theo phân loại; chọn 1 màu sẽ khoá card về đúng ảnh màu đó.
 * - Khi chưa chọn màu: hover (desktop) / vuốt (mobile) để xem thêm ảnh sản phẩm + chấm chỉ số.
 * - Quick-add: bấm nút "+" → chọn size ngay trên card, không cần vào trang chi tiết.
 * - posMode: link kèm ?pos=true + overlay "chọn" (tắt quick-add để không đổi luồng POS).
 */
const ProductCard = ({ product, posMode = false }) => {
  const { t, lang } = useLanguage();
  const { addToCart } = useCart();
  const name = lang === 'en' && product.name_en ? product.name_en : product.name;
  const eff = getEffectivePrice(product);
  const cur = lang === 'en' ? 'USD' : 'VND';

  const colors = useMemo(() => {
    const seen = new Set();
    const list = [];
    (product.variants || []).forEach((v) => {
      if (v.color && !seen.has(v.color)) {
        seen.add(v.color);
        list.push({ color: v.color, color_en: v.color_en, image: v.image_url || product.images?.[0] });
      }
    });
    return list;
  }, [product.variants, product.images]);

  const [activeColor, setActiveColor] = useState(null);
  const [imgIndex, setImgIndex] = useState(0);
  const [quickAddOpen, setQuickAddOpen] = useState(false);
  const [justAdded, setJustAdded] = useState(false);

  const gallery = product.images?.length ? product.images : [];
  const currentImages = activeColor
    ? [colors.find((c) => c.color === activeColor)?.image].filter(Boolean)
    : gallery;
  const currentSrc = currentImages[Math.min(imgIndex, currentImages.length - 1)] || gallery[0];

  const to = `/product/${product.slug}${posMode ? '?pos=true' : ''}`;

  const pickColor = (e, c) => {
    e.preventDefault();
    e.stopPropagation();
    setActiveColor(c.color);
    setImgIndex(0);
  };

  // Hover preview (desktop only — không can thiệp khi đang chọn 1 màu cụ thể)
  const onImgEnter = () => { if (!activeColor && currentImages.length > 1) setImgIndex(1); };
  const onImgLeave = () => { if (!activeColor) setImgIndex(0); };

  // Vuốt ngang trên ảnh (mobile) để xem thêm ảnh; chặn click-điều-hướng nếu vừa vuốt
  const touchStartX = useRef(null);
  const touchDeltaX = useRef(0);
  const justSwiped = useRef(false);

  const onTouchStart = (e) => {
    if (activeColor || currentImages.length <= 1) return;
    touchStartX.current = e.touches[0].clientX;
    touchDeltaX.current = 0;
  };
  const onTouchMove = (e) => {
    if (touchStartX.current == null) return;
    touchDeltaX.current = e.touches[0].clientX - touchStartX.current;
  };
  const onTouchEnd = () => {
    if (touchStartX.current == null) return;
    if (Math.abs(touchDeltaX.current) > SWIPE_THRESHOLD) {
      justSwiped.current = true;
      setImgIndex((i) =>
        touchDeltaX.current < 0
          ? Math.min(i + 1, currentImages.length - 1)
          : Math.max(i - 1, 0)
      );
    }
    touchStartX.current = null;
  };
  const onCardClick = (e) => {
    if (justSwiped.current) {
      e.preventDefault();
      justSwiped.current = false;
    }
  };

  // Quick-add: gom size theo màu đang active (hoặc màu đầu tiên / mọi variant nếu SP không phân loại theo màu)
  const sizesForQuickAdd = useMemo(() => {
    const relevant = colors.length > 0
      ? (product.variants || []).filter((v) => v.color === (activeColor || colors[0].color))
      : (product.variants || []);
    const seen = new Set();
    const list = [];
    relevant.forEach((v) => {
      if (v.size && !seen.has(v.size)) { seen.add(v.size); list.push(v); }
    });
    return list;
  }, [product.variants, colors, activeColor]);

  const hasVariants = (product.variants || []).length > 0;

  const confirmAdd = (e, variant) => {
    e.preventDefault();
    e.stopPropagation();
    addToCart(product, variant, 1);
    setQuickAddOpen(false);
    setJustAdded(true);
    setTimeout(() => setJustAdded(false), 1400);
  };

  const toggleQuickAdd = (e) => {
    e.preventDefault();
    e.stopPropagation();
    if (sizesForQuickAdd.length === 1) { confirmAdd(e, sizesForQuickAdd[0]); return; }
    setQuickAddOpen((v) => !v);
  };

  return (
    <div className="group">
      <Link to={to} onClick={onCardClick} className="block transition-transform duration-500 ease-out hover:-translate-y-1.5">
        <div
          className="relative aspect-[3/4] overflow-hidden rounded-2xl bg-parchment shadow-[0_2px_10px_-6px_rgba(63,46,38,0.25)] transition-shadow duration-500 group-hover:shadow-[0_34px_60px_-28px_rgba(87,52,37,0.55)]"
          onMouseEnter={onImgEnter}
          onMouseLeave={onImgLeave}
          onTouchStart={onTouchStart}
          onTouchMove={onTouchMove}
          onTouchEnd={onTouchEnd}
        >
          <img
            key={currentSrc}
            src={optimize(currentSrc, 500)}
            alt={name}
            loading="lazy"
            decoding="async"
            className="h-full w-full animate-fade-in object-cover transition-transform duration-[900ms] ease-out group-hover:scale-105"
          />

          <div className="pointer-events-none absolute inset-0 bg-gradient-to-t from-espresso/30 via-transparent to-transparent opacity-0 transition-opacity duration-500 group-hover:opacity-100" />

          {/* Nhãn giảm giá */}
          {eff.isDiscounted && (
            <span className="absolute left-2.5 top-2.5 z-10 rounded-full bg-clay px-2.5 py-1 text-[10px] font-semibold uppercase tracking-wider text-cream shadow">
              {lang === 'en' ? 'Sale' : 'Giảm giá'}
            </span>
          )}

          {/* Chấm chỉ số ảnh — chỉ khi chưa chọn màu và có nhiều ảnh */}
          {!activeColor && currentImages.length > 1 && (
            <div className="absolute inset-x-0 top-2.5 z-10 flex justify-center gap-1">
              {currentImages.map((_, i) => (
                <span key={i} className={`h-1 rounded-full transition-all ${i === imgIndex ? 'w-4 bg-cream' : 'w-1 bg-cream/50'}`} />
              ))}
            </div>
          )}

          {posMode ? (
            <div className="absolute inset-0 flex items-center justify-center bg-espresso/20 opacity-0 transition-opacity group-hover:opacity-100">
              <span className="rounded-full bg-cream px-4 py-1.5 text-xs font-semibold uppercase tracking-wider text-cocoa shadow">{t('collection.select')}</span>
            </div>
          ) : (
            <>
              {/* Quick-add */}
              {hasVariants && (
                <button
                  type="button"
                  onClick={toggleQuickAdd}
                  aria-label={t('product.add_to_cart')}
                  className={`absolute right-2.5 top-2.5 z-20 flex h-9 w-9 items-center justify-center rounded-full shadow-lg transition-all active:scale-90 md:opacity-0 md:group-hover:opacity-100 ${justAdded ? 'bg-sage text-cream' : 'bg-cream text-cocoa hover:bg-cocoa hover:text-cream'}`}
                >
                  {justAdded ? <FaCheck size={13} /> : <FaPlus size={13} />}
                </button>
              )}

              {quickAddOpen ? (
                <div className="absolute inset-x-2 bottom-2 z-20 rounded-xl bg-cream/95 p-3 shadow-lg backdrop-blur-sm">
                  <span className="mb-2 block text-[10px] uppercase tracking-wider text-muted">{t('product.select_size')}</span>
                  <div className="flex flex-wrap gap-1.5">
                    {sizesForQuickAdd.map((v) => {
                      const outOfStock = !product.is_preorder && (v.quantity_remaining ?? 0) <= 0;
                      return (
                        <button
                          key={v.id}
                          type="button"
                          disabled={outOfStock}
                          onClick={(e) => confirmAdd(e, v)}
                          className={`rounded-full border px-3 py-1 text-xs transition-colors ${outOfStock ? 'cursor-not-allowed border-sand text-muted/50' : 'border-cocoa/30 text-ink hover:border-cocoa hover:bg-cocoa hover:text-cream'}`}
                        >
                          {v.size}
                        </button>
                      );
                    })}
                  </div>
                </div>
              ) : (
                <div className="absolute inset-x-3 bottom-3 translate-y-3 opacity-0 transition-all duration-500 group-hover:translate-y-0 group-hover:opacity-100">
                  <span className="block rounded-full bg-cream/95 py-3 text-center text-[11px] font-medium uppercase tracking-[0.2em] text-cocoa backdrop-blur-sm">
                    {t('home.view_detail')}
                  </span>
                </div>
              )}
            </>
          )}
        </div>
      </Link>

      {/* Swatch màu theo phân loại */}
      {colors.length > 1 && (
        <div className="mt-3 flex flex-wrap items-center gap-1.5">
          {colors.slice(0, 5).map((c, i) => (
            <button
              key={i}
              type="button"
              onClick={(e) => pickColor(e, c)}
              onMouseEnter={() => { setActiveColor(c.color); setImgIndex(0); }}
              title={lang === 'en' && c.color_en ? c.color_en : c.color}
              aria-label={c.color}
              className={`h-7 w-7 overflow-hidden rounded-full border transition-all ${activeColor === c.color ? 'border-cocoa ring-1 ring-cocoa' : 'border-sand hover:border-cocoa'}`}
            >
              <img src={optimize(c.image, 80)} alt="" className="h-full w-full object-cover" />
            </button>
          ))}
          {colors.length > 5 && <span className="ml-1 text-xs text-muted">+{colors.length - 5}</span>}
        </div>
      )}

      {/* Tên + giá */}
      <Link to={to} className="mt-2 block px-0.5">
        <h3 className="font-heading text-[17px] leading-snug text-espresso transition-colors group-hover:text-cocoa line-clamp-1">
          {name}
        </h3>
        {eff.isDiscounted ? (
          <p className="mt-1 flex items-center gap-2 text-sm">
            <span className="font-medium text-clay">{formatPrice(eff.price, cur)}</span>
            <span className="text-muted line-through">{formatPrice(eff.original, cur)}</span>
          </p>
        ) : (
          <p className="mt-1 text-sm text-muted">{formatPrice(eff.price, cur)}</p>
        )}
      </Link>
    </div>
  );
};

export default ProductCard;
