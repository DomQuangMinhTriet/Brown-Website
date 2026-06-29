import { Link } from 'react-router-dom';
import { motion, useMotionValue, useSpring, useReducedMotion } from 'framer-motion';

const MotionLink = motion.create(Link);

// Mỗi variant TỰ CHỨA màu nền + chữ → không override màu qua className để tránh xung đột.
const VARIANTS = {
  solid:
    'bg-cocoa text-cream border border-cocoa hover:bg-cocoa-deep hover:border-cocoa-deep',
  cream:
    'bg-cream text-cocoa border border-cream hover:bg-[#EADFCD] hover:border-[#EADFCD]',
  outline:
    'bg-transparent text-cocoa border border-cocoa/40 hover:border-cocoa hover:bg-cocoa hover:text-cream',
  ghost:
    'bg-transparent text-ink border border-transparent hover:bg-sand/60',
  clay:
    'bg-clay text-cream border border-clay hover:bg-[#9c4f2f]',
};

const SIZES = {
  sm: 'px-5 py-2 text-xs',
  md: 'px-7 py-3 text-[13px]',
  lg: 'px-9 py-4 text-sm',
};

/**
 * Button warm-organic. `magnetic` = nút hút nhẹ theo con trỏ (desktop, tôn trọng reduced-motion).
 */
const Button = ({
  children,
  variant = 'solid',
  size = 'md',
  to,
  href,
  magnetic = false,
  className = '',
  ...props
}) => {
  const reduce = useReducedMotion();
  const x = useMotionValue(0);
  const y = useMotionValue(0);
  const sx = useSpring(x, { stiffness: 250, damping: 18, mass: 0.6 });
  const sy = useSpring(y, { stiffness: 250, damping: 18, mass: 0.6 });

  const on = magnetic && !reduce;
  const handleMove = (e) => {
    if (!on) return;
    const r = e.currentTarget.getBoundingClientRect();
    x.set((e.clientX - (r.left + r.width / 2)) * 0.35);
    y.set((e.clientY - (r.top + r.height / 2)) * 0.35);
  };
  const handleLeave = () => { x.set(0); y.set(0); };

  const classes =
    `inline-flex items-center justify-center gap-2 rounded-full font-medium uppercase tracking-[0.18em] ` +
    `transition-colors duration-300 focus-visible:outline-none ` +
    `focus-visible:ring-2 focus-visible:ring-cocoa/40 focus-visible:ring-offset-2 focus-visible:ring-offset-cream ` +
    `disabled:opacity-55 disabled:pointer-events-none ` +
    `${VARIANTS[variant]} ${SIZES[size]} ${className}`;

  const mp = on
    ? { style: { x: sx, y: sy }, onMouseMove: handleMove, onMouseLeave: handleLeave }
    : { whileTap: { scale: 0.97 } };

  if (to) return <MotionLink to={to} className={classes} {...mp} {...props}>{children}</MotionLink>;
  if (href) return <motion.a href={href} className={classes} {...mp} {...props}>{children}</motion.a>;
  return <motion.button className={classes} {...mp} {...props}>{children}</motion.button>;
};

export default Button;
