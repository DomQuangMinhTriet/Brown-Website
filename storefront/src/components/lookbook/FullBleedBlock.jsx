import { useRef } from 'react';
import { motion, useScroll, useTransform, useReducedMotion } from 'framer-motion';
import Container from '../ui/Container';
import { isVideoUrl } from './blockUtils';

const EASE = [0.16, 1, 0.3, 1];

// Khối ảnh/video tràn viền + parallax nhẹ + caption hiện khi cuộn tới.
const FullBleedBlock = ({ item, height = 'h-[78vh] md:h-screen' }) => {
  const ref = useRef(null);
  const reduce = useReducedMotion();
  const { scrollYProgress } = useScroll({ target: ref, offset: ['start end', 'end start'] });
  const y = useTransform(scrollYProgress, [0, 1], reduce ? ['0%', '0%'] : ['-10%', '10%']);
  const video = isVideoUrl(item.image_url);

  return (
    <section ref={ref} className={`relative overflow-hidden ${height}`}>
      {video ? (
        <video
          src={item.image_url}
          autoPlay loop muted playsInline
          className="absolute inset-0 h-full w-full object-cover"
        />
      ) : (
        <motion.img
          style={{ y }}
          src={item.image_url}
          alt={item.title || 'BROWN Lookbook'}
          className="absolute inset-0 h-[124%] w-full -translate-y-[12%] object-cover"
        />
      )}
      <div className="absolute inset-0 bg-gradient-to-t from-espresso/55 via-transparent to-espresso/10" />
      {(item.title || item.caption) && (
        <Container className="relative z-10 flex h-full flex-col justify-end pb-14 md:pb-20">
          <motion.div
            initial={{ opacity: 0, y: 24 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true, amount: 0.4 }}
            transition={{ duration: 0.9, ease: EASE }}
            className="max-w-xl"
          >
            {item.title && <h2 className="font-heading text-4xl leading-tight text-cream md:text-6xl">{item.title}</h2>}
            {item.caption && <p className="mt-3 text-cream/80">{item.caption}</p>}
          </motion.div>
        </Container>
      )}
    </section>
  );
};

export default FullBleedBlock;
