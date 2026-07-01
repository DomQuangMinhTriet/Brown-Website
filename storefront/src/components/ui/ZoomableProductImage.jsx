import { useEffect, useRef, useState } from 'react';

const ZOOM_SCALE = 2.4;
const DOUBLE_TAP_MS = 300;   // khoảng cách thời gian tối đa giữa 2 lần chạm để tính là double-tap
const DOUBLE_TAP_DIST = 30;  // px — 2 lần chạm phải gần nhau
const MOVE_THRESHOLD = 6;    // px — kéo quá ngưỡng này mới tính là "kéo xem", không phải "chạm"

const clamp = (v, min, max) => Math.min(max, Math.max(min, v));

/**
 * Ảnh sản phẩm với 2 cách zoom tách biệt theo loại con trỏ (e.pointerType):
 * - Chuột (desktop): rê chuột để zoom theo đúng vị trí con trỏ — hành vi cũ.
 * - Chạm (mobile): chạm 2 lần để zoom vào đúng điểm chạm; trong lúc đang zoom,
 *   giữ và kéo ngón tay để xem sang vị trí khác; chạm 1 lần (không kéo) để
 *   trở về trạng thái ban đầu.
 */
const ZoomableProductImage = ({ src, alt, className = '' }) => {
  const wrapRef = useRef(null);

  const [hoverZoom, setHoverZoom] = useState({ on: false, x: '50%', y: '50%' });
  const [touch, setTouch] = useState({ scale: 1, x: 0, y: 0 });
  const lastTapRef = useRef({ time: 0, x: 0, y: 0 });
  const panRef = useRef({ active: false, startX: 0, startY: 0, originX: 0, originY: 0, moved: false });

  // Đổi ảnh (chuyển sản phẩm/ảnh khác) → luôn về trạng thái chưa zoom
  useEffect(() => {
    setTouch({ scale: 1, x: 0, y: 0 });
    setHoverZoom({ on: false, x: '50%', y: '50%' });
  }, [src]);

  const getPanBounds = (scale) => {
    const rect = wrapRef.current?.getBoundingClientRect();
    if (!rect) return { maxX: 0, maxY: 0 };
    return { maxX: ((scale - 1) * rect.width) / 2, maxY: ((scale - 1) * rect.height) / 2 };
  };

  const zoomAtPoint = (clientX, clientY) => {
    const rect = wrapRef.current?.getBoundingClientRect();
    if (!rect) return;
    const fx = (clientX - rect.left) / rect.width;
    const fy = (clientY - rect.top) / rect.height;
    const { maxX, maxY } = getPanBounds(ZOOM_SCALE);
    setTouch({
      scale: ZOOM_SCALE,
      x: clamp((0.5 - fx) * rect.width * ZOOM_SCALE, -maxX, maxX),
      y: clamp((0.5 - fy) * rect.height * ZOOM_SCALE, -maxY, maxY),
    });
  };

  const handlePointerMove = (e) => {
    if (e.pointerType === 'mouse') {
      const r = e.currentTarget.getBoundingClientRect();
      setHoverZoom({
        on: true,
        x: `${((e.clientX - r.left) / r.width) * 100}%`,
        y: `${((e.clientY - r.top) / r.height) * 100}%`,
      });
      return;
    }
    if (e.pointerType !== 'touch' || !panRef.current.active) return;

    const dx = e.clientX - panRef.current.startX;
    const dy = e.clientY - panRef.current.startY;
    if (Math.abs(dx) > MOVE_THRESHOLD || Math.abs(dy) > MOVE_THRESHOLD) panRef.current.moved = true;

    const { maxX, maxY } = getPanBounds(touch.scale);
    setTouch((prev) => ({
      ...prev,
      x: clamp(panRef.current.originX + dx, -maxX, maxX),
      y: clamp(panRef.current.originY + dy, -maxY, maxY),
    }));
  };

  const handlePointerLeave = (e) => {
    if (e.pointerType === 'mouse') setHoverZoom({ on: false, x: '50%', y: '50%' });
  };

  const handlePointerDown = (e) => {
    if (e.pointerType !== 'touch') return;
    panRef.current = { active: true, startX: e.clientX, startY: e.clientY, originX: touch.x, originY: touch.y, moved: false };
  };

  const handlePointerUp = (e) => {
    if (e.pointerType !== 'touch') return;
    const wasMoved = panRef.current.moved;
    panRef.current.active = false;

    if (wasMoved) return; // vừa kéo xem — không tính là một lần chạm

    if (touch.scale > 1) {
      // Đang zoom, chạm 1 lần (không kéo) → về ban đầu
      setTouch({ scale: 1, x: 0, y: 0 });
      lastTapRef.current = { time: 0, x: 0, y: 0 };
      return;
    }

    // Chưa zoom — kiểm tra có phải double-tap không
    const now = Date.now();
    const last = lastTapRef.current;
    const dist = Math.hypot(e.clientX - last.x, e.clientY - last.y);
    if (now - last.time < DOUBLE_TAP_MS && dist < DOUBLE_TAP_DIST) {
      zoomAtPoint(e.clientX, e.clientY);
      lastTapRef.current = { time: 0, x: 0, y: 0 };
    } else {
      lastTapRef.current = { time: now, x: e.clientX, y: e.clientY };
    }
  };

  const zoomed = touch.scale > 1;

  return (
    <div
      ref={wrapRef}
      className={`relative overflow-hidden ${className}`}
      style={{ touchAction: zoomed ? 'none' : 'manipulation' }}
      onPointerMove={handlePointerMove}
      onPointerLeave={handlePointerLeave}
      onPointerDown={handlePointerDown}
      onPointerUp={handlePointerUp}
      onPointerCancel={handlePointerUp}
    >
      <img
        src={src}
        alt={alt}
        className="h-full w-full cursor-zoom-in object-cover ease-out"
        style={
          zoomed
            ? { transform: `translate(${touch.x}px, ${touch.y}px) scale(${touch.scale})`, transitionDuration: panRef.current.active ? '0ms' : '200ms', transitionProperty: 'transform' }
            : { transformOrigin: `${hoverZoom.x} ${hoverZoom.y}`, transform: hoverZoom.on ? 'scale(1.9)' : 'scale(1)', transitionDuration: '200ms', transitionProperty: 'transform' }
        }
        fetchPriority="high"
      />
    </div>
  );
};

export default ZoomableProductImage;
