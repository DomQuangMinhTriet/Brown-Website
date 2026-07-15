import { useEffect, useState } from 'react';

// Màn intro khi tải trang: chữ BROWN từ viền (trong suốt) tô đầy thành màu nâu, rồi mờ dần.
const Preloader = () => {
  const [gone, setGone] = useState(false);
  const [armed, setArmed] = useState(() => window.matchMedia('(prefers-reduced-motion: reduce)').matches);

  // Chỉ bắt đầu animation SAU KHI font Sugo Classic đã tải xong (hoặc hết 500ms chờ an toàn) —
  // nếu chạy ngay khi mount, lần tải đầu tiên (font chưa cache) chữ sẽ đổi hình dạng
  // (font fallback → Sugo Classic) ngay giữa animation, gây giật/lỗi hình chữ.
  useEffect(() => {
    if (armed) return; // reduced-motion đã armed sẵn ở state ban đầu, không cần đợi font

    let done = false;
    const arm = () => { if (!done) { done = true; setArmed(true); } };

    if (document.fonts?.load) {
      document.fonts.load("400 6rem 'Sugo Classic'").catch(() => {}).finally(arm);
    } else {
      arm();
    }
    const safety = setTimeout(arm, 500);
    return () => clearTimeout(safety);
  }, [armed]);

  useEffect(() => {
    if (!armed) return;
    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    const tid = setTimeout(() => setGone(true), reduce ? 700 : 2600);
    return () => clearTimeout(tid);
  }, [armed]);

  if (gone) return null;

  return (
    <div className={`preloader${armed ? ' is-armed' : ''}`} aria-hidden="true">
      <span className="preloader-word text-6xl uppercase md:text-8xl">BROWN</span>
    </div>
  );
};

export default Preloader;
