import { useEffect, useState } from 'react';

// Màn intro khi tải trang: chữ BROWN từ viền (trong suốt) tô đầy thành màu nâu, rồi mờ dần.
const Preloader = () => {
  const [gone, setGone] = useState(false);

  useEffect(() => {
    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    const tid = setTimeout(() => setGone(true), reduce ? 700 : 2600);
    return () => clearTimeout(tid);
  }, []);

  if (gone) return null;

  return (
    <div className="preloader" aria-hidden="true">
      <span className="preloader-word text-6xl uppercase md:text-8xl">BROWN</span>
    </div>
  );
};

export default Preloader;
