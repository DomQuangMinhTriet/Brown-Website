import { useEffect, useRef, useState } from 'react';
import axios from 'axios';
import { Link } from 'react-router-dom';
// eslint-disable-next-line no-unused-vars -- motion được dùng trong JSX.
import { motion, AnimatePresence, useScroll, useTransform, useReducedMotion } from 'framer-motion';
import { FaArrowRight } from 'react-icons/fa';
import SEO from '../components/SEO';
import Container from '../components/ui/Container';
import Button from '../components/ui/Button';
import ProductCard from '../components/ui/ProductCard';
import { isVideoUrl } from '../components/lookbook/blockUtils';
import { optimizeImage } from '../utils/cloudinaryHelper';
import { useLanguage } from '../context/LanguageContext';

const EASE = [0.16, 1, 0.3, 1];

const Home = () => {
  const { t, lang } = useLanguage();
  const reduce = useReducedMotion();

  const [banners, setBanners] = useState([]);
  const [categories, setCategories] = useState([]);
  const [catProducts, setCatProducts] = useState({}); // { slug: products[] }
  const [lookImgs, setLookImgs] = useState([]); // ảnh lookbook cho teaser
  const [loading, setLoading] = useState(true);
  const [currentBanner, setCurrentBanner] = useState(0);
  const [activeIndex, setActiveIndex] = useState(0); // Mục lục

  // Parallax cho section đóng
  const closeRef = useRef(null);
  const { scrollYProgress } = useScroll({ target: closeRef, offset: ['start end', 'end start'] });
  const parallaxY = useTransform(scrollYProgress, [0, 1], reduce ? ['0%', '0%'] : ['-12%', '12%']);

  useEffect(() => {
    const fetchAll = async () => {
      try {
        const [banRes, catRes, lookRes] = await Promise.all([
          axios.get(`${import.meta.env.VITE_API_URL}/api/content/banners`),
          axios.get(`${import.meta.env.VITE_API_URL}/api/categories`),
          axios.get(`${import.meta.env.VITE_API_URL}/api/content/lookbook`).catch(() => ({ data: { data: [] } })),
        ]);
        if (banRes.data.success) setBanners(banRes.data.data);
        if (lookRes.data?.data) {
          // Teaser trên Home chỉ lấy ẢNH — bỏ qua mọi mục là video
          const imgOnly = lookRes.data.data
            .map((r) => r.image_url)
            .filter((url) => url && !isVideoUrl(url));
          setLookImgs(imgOnly);
        }

        let visibleCats = [];
        if (catRes.data.success) {
          visibleCats = catRes.data.data.filter((c) => c.is_visible_on_home !== false);
          setCategories(visibleCats);
        }

        // Gộp thành 1 lần gọi duy nhất thay vì 1 request/danh mục (tránh N+1 truy vấn DB)
        const allProductsRes = await axios.get(`${import.meta.env.VITE_API_URL}/api/products`);
        const allProducts = allProductsRes.data.success ? allProductsRes.data.data : [];
        const grouped = {};
        for (const cat of visibleCats) {
          grouped[cat.slug] = allProducts.filter((p) =>
            p.category_id === cat.id || (p.product_collections || []).some((pc) => pc.category_id === cat.id)
          );
        }
        setCatProducts(grouped);
      } catch (err) {
        console.error(err);
      } finally {
        setLoading(false);
      }
    };
    fetchAll();
  }, []);

  useEffect(() => {
    if (banners.length <= 1) return;
    const interval = setInterval(() => {
      setCurrentBanner((prev) => (prev === banners.length - 1 ? 0 : prev + 1));
    }, 6000);
    return () => clearInterval(interval);
  }, [banners]);

  const isVideo = (url) => url?.match(/\.(mp4|webm|ogg)$/i);
  const nameOf = (c) => (lang === 'en' && c?.name_en ? c.name_en : c?.name);
  const repImg = (slug) => catProducts[slug]?.[0]?.images?.[0];

  const activeCat = categories[activeIndex] || categories[0];
  const sloganWords = ['Brown', 'Made in Vietnam', 'Brown', 'Made in Vietnam'];

  // Ảnh cố định cho 2 dải full-bleed (đóng trang + editorial shoppable)
  const closingImg = "/background.avif";
  const editorialImg = "/background.avif";
  const teaserImgs = (lookImgs.length ? lookImgs : categories.map((c) => repImg(c.slug)).filter(Boolean)).slice(0, 3);

  return (
    <>
      <SEO title={t('home.title')} />

      {/* ============================================================
          1. HERO — BANNER SẠCH (không chữ đè, để banner rõ ràng)
         ============================================================ */}
      <section className="relative w-full overflow-hidden bg-parchment min-h-[82dvh]">
        {loading ? (
          <div className="absolute inset-0 flex items-center justify-center font-sugo text-4xl tracking-[0.1em] text-muted animate-pulse">BROWN</div>
        ) : banners.length > 0 ? (
          banners.map((banner, index) => (
            <Link
              to={banner.link_to || '/collection'}
              key={banner.id}
              className={`absolute inset-0 block transition-opacity duration-[1200ms] ease-in-out ${index === currentBanner ? 'opacity-100 z-10' : 'opacity-0 z-0'}`}
            >
              {isVideo(banner.image_url) ? (
                <video autoPlay loop muted playsInline className="h-full w-full object-cover">
                  <source src={banner.image_url} type="video/mp4" />
                </video>
              ) : (
                <img src={optimizeImage(banner.image_url, 1600)} alt={banner.title || 'BROWN'} className="h-full w-full object-cover animate-ken-burns" />
              )}
            </Link>
          ))
        ) : (
          <div className="absolute inset-0 bg-cocoa" />
        )}

        {/* Chỉ giữ chấm điều hướng, không có chữ đè */}
        {!loading && banners.length > 1 && (
          <div className="absolute bottom-6 left-1/2 z-20 flex -translate-x-1/2 gap-2">
            {banners.map((_, idx) => (
              <button
                key={idx}
                onClick={(e) => { e.preventDefault(); setCurrentBanner(idx); }}
                aria-label={`Banner ${idx + 1}`}
                className={`h-1.5 rounded-full shadow-sm transition-all duration-500 ${idx === currentBanner ? 'w-8 bg-cream' : 'w-2 bg-cream/60 hover:bg-cream'}`}
              />
            ))}
          </div>
        )}
      </section>

      {/* ============================================================
          2. SLOGAN — MARQUEE chữ chạy (điểm nhấn động)
         ============================================================ */}
      <section className="marquee-group overflow-hidden bg-cocoa py-14 md:py-20">
        <div className="flex w-max animate-marquee">
          {[0, 1].map((g) => (
            <div key={g} className="flex shrink-0 items-center" aria-hidden={g === 1}>
              {sloganWords.map((w, i) => (
                <span key={i} className="flex items-center">
                  <span className={`whitespace-nowrap px-8 font-body text-5xl font-semibold uppercase tracking-tight md:text-7xl ${i % 2 === 0 ? 'text-cream' : 'text-outline-cream'}`}>{w}</span>
                  <span className="h-2.5 w-2.5 shrink-0 rounded-full bg-sage" />
                </span>
              ))}
            </div>
          ))}
        </div>
      </section>

      {!loading && (
        <>
          {/* ============================================================
              3. MỤC LỤC — theo CATEGORY (hover đổi ảnh) — SIGNATURE
             ============================================================ */}
          {categories.length > 0 && (
            <section className="bg-espresso text-cream">
              <Container className="py-16 md:py-28">
                <div className="mb-12 flex items-end justify-between">
                  <h2 className="font-heading text-3xl text-cream md:text-5xl">
                    {lang === 'en' ? 'Brown has:' : 'Brown có:'}
                  </h2>
                </div>

                {/* Desktop: list trái + ảnh dính phải */}
                <div className="hidden lg:grid lg:grid-cols-12 lg:gap-14">
                  <ul className="lg:col-span-7">
                    {categories.map((cat, i) => {
                      const count = catProducts[cat.slug]?.length || 0;
                      const active = activeIndex === i;
                      return (
                        <li key={cat.id} onMouseEnter={() => setActiveIndex(i)}>
                          <a href={`#cat-${cat.slug}`} className="group flex items-center gap-6 border-b border-cream/15 py-6">
                            <span className={`font-heading text-sm tabular-nums transition-colors ${active ? 'text-clay' : 'text-cream/40'}`}>{String(i + 1).padStart(2, '0')}</span>
                            <span className={`flex-1 font-heading text-3xl leading-tight transition-all duration-500 group-hover:translate-x-3 xl:text-5xl ${active ? 'text-clay' : 'text-cream'}`}>
                              {nameOf(cat)}
                            </span>
                            <span className="text-sm tabular-nums text-cream/40">{count}</span>
                            <FaArrowRight className={`text-clay transition-all duration-500 ${active ? 'translate-x-0 opacity-100' : '-translate-x-2 opacity-0'}`} />
                          </a>
                        </li>
                      );
                    })}
                  </ul>

                  <div className="lg:col-span-5">
                    <div className="sticky top-28 aspect-[3/4] overflow-hidden rounded-2xl bg-cocoa/40">
                      <AnimatePresence mode="wait">
                        {repImg(activeCat?.slug) ? (
                          <motion.img
                            key={activeCat?.slug}
                            src={optimizeImage(repImg(activeCat?.slug), 700)}
                            alt={nameOf(activeCat)}
                            initial={{ opacity: 0, scale: 1.06 }}
                            animate={{ opacity: 1, scale: 1 }}
                            exit={{ opacity: 0 }}
                            transition={{ duration: 0.6, ease: EASE }}
                            className="absolute inset-0 h-full w-full object-cover"
                          />
                        ) : (
                          <div key="ph" className="absolute inset-0 flex items-center justify-center">
                            <span className="font-heading text-7xl text-cream/15">{nameOf(activeCat)?.[0]}</span>
                          </div>
                        )}
                      </AnimatePresence>
                      <div className="pointer-events-none absolute inset-x-0 bottom-0 bg-gradient-to-t from-espresso/90 to-transparent p-6">
                        <p className="font-heading text-2xl text-cream">{nameOf(activeCat)}</p>
                        <p className="text-sm text-cream/65">{catProducts[activeCat?.slug]?.length || 0} {lang === 'en' ? 'items' : 'sản phẩm'}</p>
                      </div>
                    </div>
                  </div>
                </div>

                {/* Mobile: dòng có thumbnail */}
                <ul className="lg:hidden">
                  {categories.map((cat, i) => (
                    <li key={cat.id}>
                      <a href={`#cat-${cat.slug}`} className="flex items-center gap-4 border-b border-cream/15 py-4">
                        <span className="font-heading text-xs tabular-nums text-cream/40">{String(i + 1).padStart(2, '0')}</span>
                        <div className="h-20 w-16 shrink-0 overflow-hidden rounded-lg bg-cocoa/40">
                          {repImg(cat.slug) ? (
                            <img src={optimizeImage(repImg(cat.slug), 150)} alt={nameOf(cat)} loading="lazy" className="h-full w-full object-cover" />
                          ) : (
                            <div className="flex h-full w-full items-center justify-center font-heading text-2xl text-cream/20">{nameOf(cat)?.[0]}</div>
                          )}
                        </div>
                        <span className="flex-1 font-heading text-xl leading-tight text-cream">{nameOf(cat)}</span>
                        <FaArrowRight className="text-clay" />
                      </a>
                    </li>
                  ))}
                </ul>
              </Container>
            </section>
          )}

          {/* ============================================================
              4. LOOKBOOK — teaser dẫn tới trang /lookbook
             ============================================================ */}
          <section className="bg-cream py-16 md:py-24">
            <Container>
              <div className="mb-8 flex items-end justify-between">
                <div>
                  <h2 className="mt-2 font-heading text-3xl text-espresso md:text-5xl">Lookbook</h2>
                </div>
                <Link to="/lookbook" className="hidden items-center gap-2 text-sm uppercase tracking-[0.2em] text-cocoa transition-colors hover:text-clay sm:flex">
                  {lang === 'en' ? 'View all' : 'Xem tất cả'} <FaArrowRight />
                </Link>
              </div>

              {teaserImgs.length > 0 && (
                <Link to="/lookbook" className="group grid grid-cols-2 gap-3 md:grid-cols-3 md:gap-4">
                  {teaserImgs.map((src, i) => (
                    <div key={i} className={`overflow-hidden rounded-2xl bg-parchment ${i === 0 ? 'col-span-2 aspect-[16/10] md:col-span-1 md:aspect-[3/4]' : 'aspect-[3/4]'}`}>
                      <img src={optimizeImage(src, i === 0 ? 900 : 500)} alt="BROWN Lookbook" loading="lazy" className="h-full w-full object-cover transition-transform duration-700 group-hover:scale-105" />
                    </div>
                  ))}
                </Link>
              )}

              <div className="mt-10 text-center">
                <Button to="/lookbook" variant="outline" size="lg" magnetic>
                  {lang === 'en' ? 'Open the Lookbook' : 'Mở Lookbook'}
                </Button>
              </div>
            </Container>
          </section>

          {/* ============================================================
              EDITORIAL — ảnh lớn tràn viền + CTA mua ngay (phá nhịp lưới)
             ============================================================ */}
          {editorialImg && (
            <section className="relative h-[58vh] overflow-hidden bg-cocoa md:h-[78vh]">
              <img src={editorialImg} alt="BROWN" loading="lazy" className="absolute inset-0 h-full w-full object-cover" />
              <div className="absolute inset-0 bg-gradient-to-t from-espresso/75 via-espresso/10 to-transparent" />
              <Container className="relative z-10 flex h-full flex-col items-start justify-end pb-14 md:pb-20">
                <motion.div
                  initial={{ opacity: 0, y: 24 }}
                  whileInView={{ opacity: 1, y: 0 }}
                  viewport={{ once: true, amount: 0.4 }}
                  transition={{ duration: 0.9, ease: EASE }}
                  className="max-w-xl"
                >
                  <p className="font-heading text-3xl italic leading-snug text-cream md:text-5xl">
                    {lang === 'en' ? 'Dressed for every season.' : 'Thích hợp cho mọi mùa.'}
                  </p>
                  <div className="mt-7">
                    <Button to="/collection" variant="cream" size="lg" magnetic>
                      {lang === 'en' ? 'Shop now' : 'Mua ngay'}
                    </Button>
                  </div>
                </motion.div>
              </Container>
            </section>
          )}

          {/* ============================================================
              5. CÁC MỤC THEO CATEGORY (4 sản phẩm + Xem thêm)
             ============================================================ */}
          {categories.map((cat, ci) => {
            const prods = (catProducts[cat.slug] || []).slice(0, 4);
            return (
              <section
                key={cat.id}
                id={`cat-${cat.slug}`}
                className={`scroll-mt-24 ${ci % 2 === 0 ? 'bg-parchment/40' : 'bg-cream'}`}
              >
                <Container className="py-16 md:py-20">
                  <div className="mb-10 flex items-end justify-between border-b border-sand pb-6">
                    <div className="flex items-baseline gap-4">
                      <span className="font-heading text-4xl tabular-nums text-clay md:text-5xl">{String(ci + 1).padStart(2, '0')}</span>
                      <h2 className="font-heading text-3xl text-espresso md:text-5xl">{nameOf(cat)}</h2>
                    </div>
                    <Link
                      to={`/collection?category=${cat.slug}`}
                      className="hidden items-center gap-2 text-sm uppercase tracking-[0.2em] text-cocoa transition-colors hover:text-clay sm:flex"
                    >
                      {lang === 'en' ? 'See more' : 'Xem thêm'} <FaArrowRight />
                    </Link>
                  </div>

                  {prods.length > 0 ? (
                    <div className="grid grid-cols-2 gap-x-5 gap-y-10 md:grid-cols-4 md:gap-x-6">
                      {prods.map((product, i) => (
                        <motion.div
                          key={product.id}
                          initial={{ opacity: 0, y: 28 }}
                          whileInView={{ opacity: 1, y: 0 }}
                          viewport={{ once: true, amount: 0.2 }}
                          transition={{ duration: 0.6, delay: (i % 4) * 0.07, ease: EASE }}
                        >
                          <ProductCard product={product} />
                        </motion.div>
                      ))}
                    </div>
                  ) : (
                    <p className="py-8 text-center italic text-muted">
                      {lang === 'en' ? 'Products coming soon.' : 'Sản phẩm đang cập nhật.'}
                    </p>
                  )}

                  <div className="mt-12 text-center">
                    <Button to={`/collection?category=${cat.slug}`} variant="outline" size="lg" magnetic>
                      {lang === 'en' ? 'See more' : 'Xem thêm'}
                    </Button>
                  </div>
                </Container>
              </section>
            );
          })}

          {/* ============================================================
              6. ĐÓNG — ảnh full-bleed parallax + lời mời
             ============================================================ */}
          <section ref={closeRef} className="relative h-[70vh] overflow-hidden bg-cocoa">
            {closingImg && (
              <motion.img
                src={closingImg}
                alt="BROWN"
                style={{ y: parallaxY }}
                className="absolute inset-0 h-[124%] w-full -translate-y-[12%] object-cover"
              />
            )}
            <div className="absolute inset-0 bg-gradient-to-t from-espresso/80 via-espresso/30 to-espresso/20" />
            <Container className="relative z-10 flex h-full flex-col items-center justify-center gap-8 text-center">
              <motion.h2
                initial={{ opacity: 0, y: 24 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true, amount: 0.5 }}
                transition={{ duration: 0.9, ease: EASE }}
                className="max-w-2xl font-heading text-4xl leading-tight text-cream md:text-6xl"
              >
                {lang === 'en' ? (
                  <>Find what stays with you.</>
                ) : (
                  <>Tìm món đồ ở lại cùng bạn.</>
                )}
              </motion.h2>
              <Button to="/collection" variant="cream" size="lg" magnetic>
                {t('home.view_all')}
              </Button>
            </Container>
          </section>
        </>
      )}

      {/* Skeleton khi đang tải phần dưới */}
      {loading && (
        <Container className="py-20">
          <div className="grid grid-cols-2 gap-6 md:grid-cols-4">
            {Array.from({ length: 4 }).map((_, i) => (
              <div key={i} className="animate-pulse">
                <div className="aspect-[3/4] rounded-2xl bg-sand/60" />
                <div className="mt-4 h-4 w-3/4 rounded bg-sand/60" />
              </div>
            ))}
          </div>
        </Container>
      )}
    </>
  );
};

export default Home;
