import { useEffect, useState } from 'react';
import axios from 'axios';
// eslint-disable-next-line no-unused-vars -- motion được dùng trong JSX.
import { motion } from 'framer-motion';
import SEO from '../components/SEO';
import Container from '../components/ui/Container';
import LookbookBlocks from '../components/lookbook/LookbookBlocks';
import { toLookbookBlock } from '../components/lookbook/blockUtils';
import { useLanguage } from '../context/LanguageContext';

const EASE = [0.16, 1, 0.3, 1];

const Lookbook = () => {
  const { t, lang } = useLanguage();
  const [blocks, setBlocks] = useState(null);

  useEffect(() => {
    window.scrollTo(0, 0);
    const api = import.meta.env.VITE_API_URL;

    const load = async () => {
      // 1) Thử lấy lookbook thật từ API
      try {
        const res = await axios.get(`${api}/api/content/lookbook`);
        if (res.data?.success && res.data.data?.length) {
          setBlocks(res.data.data.map(toLookbookBlock));
          return;
        }
      } catch { /* chưa có endpoint -> fallback */ }

      // 2) Fallback DEMO: dựng từ ảnh sản phẩm để xem trước hướng thiết kế
      try {
        const r = await axios.get(`${api}/api/products`);
        const imgs = (r.data?.data || []).flatMap((p) => p.images || []).filter(Boolean);
        if (!imgs.length) { setBlocks([]); return; }
        const g = (i) => imgs[i % imgs.length];
        setBlocks([
          { type: 'full', image_url: g(0), title: lang === 'en' ? 'Worn slow' : 'Mặc chậm', caption: lang === 'en' ? 'Pieces made to last beyond a season.' : 'Những món để mặc bền qua nhiều mùa.' },
          { type: 'compare', image_url: g(1), image_url_2: g(2), title: lang === 'en' ? 'Two ways' : 'Phối đôi' },
          { type: 'quote', caption: lang === 'en' ? 'Honest cloth, quiet colour.' : 'Vải mộc, sắc trầm.' },
          { type: 'full', image_url: g(3), title: lang === 'en' ? 'In the studio' : 'Trong xưởng' },
          { type: 'compare', image_url: g(4), image_url_2: g(5), title: lang === 'en' ? 'Light & shade' : 'Sáng & tối' },
          { type: 'full', image_url: g(6) },
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

      {/* HEADER — chỉ chữ, không ảnh (mọi ảnh/video hiển thị nguyên khối bên dưới) */}
      <section className="bg-cocoa py-20 text-center md:py-28">
        <motion.div initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.8, ease: EASE }}>
          <p className="mb-4 text-xs uppercase tracking-[0.4em] text-cream/60">{lang === 'en' ? 'The Journal' : 'Tập ảnh'}</p>
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
