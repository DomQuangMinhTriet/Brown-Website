import { useEffect, useState } from 'react';

const PRELOADER_KEY = 'brown_preloader_seen';

const Preloader = () => {
  const [gone, setGone] = useState(() => sessionStorage.getItem(PRELOADER_KEY) === '1');
  const [armed, setArmed] = useState(false);

  useEffect(() => {
    if (gone) return undefined;

    let cancelled = false;
    const show = () => { if (!cancelled) setArmed(true); };
    const fontTimeout = setTimeout(show, 120);
    document.fonts?.load?.("400 6rem 'Sugo Classic'").catch(() => {}).finally(show);

    const closeTimeout = setTimeout(() => {
      sessionStorage.setItem(PRELOADER_KEY, '1');
      setGone(true);
    }, window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 0 : 550);

    return () => {
      cancelled = true;
      clearTimeout(fontTimeout);
      clearTimeout(closeTimeout);
    };
  }, [gone]);

  if (gone) return null;
  return (
    <div className={`preloader${armed ? ' is-armed' : ''}`} aria-hidden="true">
      <span className="preloader-word text-6xl uppercase md:text-8xl">BROWN</span>
    </div>
  );
};

export default Preloader;
