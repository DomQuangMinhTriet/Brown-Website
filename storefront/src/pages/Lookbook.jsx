import { useEffect, useState } from 'react';
import axios from 'axios';
import { motion } from 'framer-motion';
import SEO from '../components/SEO';
import Container from '../components/ui/Container';
import LookbookBlocks from '../components/lookbook/LookbookBlocks';
import { toLookbookBlock, isVideoUrl } from '../components/lookbook/blockUtils';
import { useLanguage } from '../context/LanguageContext';

const EASE = [0.16, 1, 0.3, 1];

const Lookbook = () => {
  const { t, lang } = useLanguage();
  const [blocks, setBlocks] = useState(null);
  const [cover, setCover] = useState(null);

  useEffect(() => {
    window.scrollTo(0, 0);
    const api = import.meta.env.VITE_API_URL;

    const load = async () => {
      // 1) Thử lấy lookbook thật từ API
      try {
        const res = await axios.get(`${api}/api/content/lookbook`);
        if (res.data?.success && res.data.data?.length) {
          const rows = res.data.data;
          // Bìa dùng ảnh/video của mục ĐẦU TIÊN CÓ MEDIA (khối "trích dẫn" không có ảnh nên bị bỏ qua khi chọn bìa)
          setCover(rows.find((r) => r.image_url) || null);
          // Vẫn hiển thị TẤT CẢ mục bên dưới, không loại bỏ mục nào
          setBlocks(rows.map(toLookbookBlock));
          return;
        }
      } catch { /* chưa có endpoint -> fallback */ }

      // 2) Fallback DEMO: dựng từ ảnh sản phẩm để xem trước hướng thiết kế
      try {
        const r = await axios.get(`${api}/api/products`);
        const imgs = (r.data?.data || []).flatMap((p) => p.images || []).filter(Boolean);
        if (!imgs.length) { setBlocks([]); return; }
        const g = (i) => imgs[i % imgs.length];
        setCover({ image_url: g(0) });
        setBlocks([
          { type: 'full', image_url: g(1), title: lang === 'en' ? 'Worn slow' : 'Mặc chậm', caption: lang === 'en' ? 'Pieces made to last beyond a season.' : 'Những món để mặc bền qua nhiều mùa.' },
          { type: 'compare', image_url: g(2), image_url_2: g(3), title: lang === 'en' ? 'Two ways' : 'Phối đôi' },
          { type: 'quote', caption: lang === 'en' ? 'Honest cloth, quiet colour.' : 'Vải mộc, sắc trầm.' },
          { type: 'full', image_url: g(4), title: lang === 'en' ? 'In the studio' : 'Trong xưởng' },
          { type: 'compare', image_url: g(5), image_url_2: g(6), title: lang === 'en' ? 'Light & shade' : 'Sáng & tối' },
          { type: 'full', image_url: g(7) },
        ]);
      } catch {
        setBlocks([]);
      }
    };
    load();
  }, [lang]);

  return (
    <>
      <SEO title="Lookbook" />

      {/* COVER */}
      <section className="relative flex h-[88vh] items-center justify-center overflow-hidden bg-cocoa md:h-screen">
        {cover?.image_url && (
          isVideoUrl(cover.image_url) ? (
            <video src={cover.image_url} autoPlay loop muted playsInline className="absolute inset-0 h-full w-full object-cover opacity-70" />
          ) : (
            <img src={cover.image_url} alt="BROWN Lookbook" className="absolute inset-0 h-full w-full object-cover opacity-70 animate-ken-burns" />
          )
        )}
        <div className="absolute inset-0 bg-espresso/40" />
        <motion.div initial={{ opacity: 0, y: 30 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 1, ease: EASE }}
          className="relative z-10 px-6 text-center">
          <p className="mb-4 text-xs uppercase tracking-[0.4em] text-cream/70">{lang === 'en' ? 'The Journal' : 'Tập ảnh'}</p>
          <h1 className="font-sugo text-6xl uppercase tracking-[0.06em] text-cream md:text-8xl">Lookbook</h1>
          <p className="mt-4 font-heading text-lg italic text-cream/80">BROWN — 2026</p>
        </motion.div>
      </section>

      {/* BLOCKS */}
      {blocks === null ? (
        <div className="py-24 text-center text-muted">{t('product.loading')}</div>
      ) : blocks.length === 0 ? (
        <Container className="py-24 text-center">
          <p className="font-heading text-2xl text-espresso">{lang === 'en' ? 'Coming soon' : 'Sắp ra mắt'}</p>
        </Container>
      ) : (
        <LookbookBlocks blocks={blocks} lang={lang} />
      )}
    </>
  );
};

export default Lookbook;
