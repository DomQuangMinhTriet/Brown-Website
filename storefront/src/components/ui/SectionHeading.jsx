/**
 * Tiêu đề section warm-organic. Eyebrow dùng tiết chế (theo taste-skill:
 * tối đa ~1 eyebrow / 3 section — truyền eyebrow chỉ khi thật cần).
 */
const SectionHeading = ({
  eyebrow,
  title,
  description,
  align = 'center',
  className = '',
}) => {
  const isCenter = align === 'center';
  return (
    <div
      className={`${isCenter ? 'text-center mx-auto' : 'text-left'} max-w-2xl ${
        isCenter ? '' : 'mr-auto'
      } ${className}`}
    >
      {eyebrow && (
        <span className="block text-xs uppercase tracking-[0.32em] text-sage mb-3">
          {eyebrow}
        </span>
      )}
      <h2 className="font-heading text-3xl md:text-4xl lg:text-[2.75rem] leading-[1.1] text-espresso">
        {title}
      </h2>
      {description && (
        <p className="mt-4 text-muted leading-relaxed">{description}</p>
      )}
      <span
        className={`mt-6 block h-px w-16 bg-cocoa/30 ${
          isCenter ? 'mx-auto' : ''
        }`}
      />
    </div>
  );
};

export default SectionHeading;
