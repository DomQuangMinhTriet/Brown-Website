import { useEffect, useRef, useState, useCallback } from 'react';

/**
 * Slider kéo để mix/đổi giữa 2 ảnh (before/after).
 * Kéo tay cầm (hoặc bấm bất kỳ đâu) qua lại để hé lộ ảnh thứ 2.
 * Hỗ trợ chuột + cảm ứng (pointer events) + bàn phím (mũi tên).
 */
const ImageCompareSlider = ({ before, after, beforeLabel, afterLabel, className = '' }) => {
  const ref = useRef(null);
  const dragging = useRef(false);
  const [pos, setPos] = useState(50);

  const update = useCallback((clientX) => {
    const el = ref.current;
    if (!el || clientX == null) return;
    const r = el.getBoundingClientRect();
    const p = ((clientX - r.left) / r.width) * 100;
    setPos(Math.max(0, Math.min(100, p)));
  }, []);

  useEffect(() => {
    const move = (e) => {
      if (!dragging.current) return;
      update(e.clientX ?? e.touches?.[0]?.clientX);
    };
    const up = () => { dragging.current = false; };
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
    return () => {
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
    };
  }, [update]);

  const onPointerDown = (e) => {
    dragging.current = true;
    update(e.clientX);
  };

  const onKey = (e) => {
    if (e.key === 'ArrowLeft') setPos((p) => Math.max(0, p - 4));
    if (e.key === 'ArrowRight') setPos((p) => Math.min(100, p + 4));
  };

  return (
    <div
      ref={ref}
      onPointerDown={onPointerDown}
      className={`relative select-none overflow-hidden rounded-2xl bg-parchment touch-pan-y ${className}`}
    >
      {/* Ảnh nền (sau) — object-contain để không cắt xén nội dung ảnh gốc */}
      <img src={before} alt={beforeLabel || ''} className="block h-full w-full object-contain" draggable={false} />
      {beforeLabel && (
        <span className="absolute bottom-4 left-4 rounded-full bg-espresso/55 px-3 py-1 text-xs uppercase tracking-wider text-cream backdrop-blur-sm">
          {beforeLabel}
        </span>
      )}

      {/* Ảnh phủ (trước) — clip theo vị trí slider */}
      <div className="absolute inset-0" style={{ clipPath: `inset(0 ${100 - pos}% 0 0)` }}>
        <img src={after} alt={afterLabel || ''} className="absolute inset-0 h-full w-full object-contain" draggable={false} />
        {afterLabel && (
          <span className="absolute bottom-4 right-4 rounded-full bg-espresso/55 px-3 py-1 text-xs uppercase tracking-wider text-cream backdrop-blur-sm">
            {afterLabel}
          </span>
        )}
      </div>

      {/* Đường + tay cầm */}
      <div className="pointer-events-none absolute inset-y-0 z-10" style={{ left: `${pos}%` }}>
        <div className="absolute inset-y-0 -left-px w-0.5 bg-cream/90" />
        <button
          type="button"
          aria-label="Kéo để so sánh"
          onKeyDown={onKey}
          className="pointer-events-auto absolute top-1/2 left-1/2 flex h-11 w-11 -translate-x-1/2 -translate-y-1/2 cursor-ew-resize items-center justify-center rounded-full border border-cocoa/20 bg-cream text-cocoa shadow-lg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cocoa/50"
        >
          <span className="text-sm tracking-tighter">‹›</span>
        </button>
      </div>
    </div>
  );
};

export default ImageCompareSlider;
