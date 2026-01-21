import { Helmet } from 'react-helmet-async';

const SEO = ({ title, description, image, url }) => {
  // Cấu hình mặc định nếu không truyền vào
  const defaultTitle = 'BROWN - Thời trang tối giản & Thanh lịch';
  const defaultDesc = 'Thương hiệu thời trang thiết kế cao cấp, phong cách tối giản dành cho người hiện đại.';
  const defaultImage = 'https://your-domain.com/banner-default.jpg'; // Bạn nên thay bằng link ảnh banner thật
  const siteUrl = 'https://brownfashion.vn'; // Domain thật của bạn sau này

  return (
    <Helmet>
      {/* 1. Thẻ cơ bản */}
      <title>{title ? `${title} | BROWN` : defaultTitle}</title>
      <meta name="description" content={description || defaultDesc} />

      {/* 2. Thẻ Facebook / Zalo (Open Graph) */}
      <meta property="og:type" content="website" />
      <meta property="og:title" content={title || defaultTitle} />
      <meta property="og:description" content={description || defaultDesc} />
      <meta property="og:image" content={image || defaultImage} />
      <meta property="og:url" content={url ? `${siteUrl}${url}` : siteUrl} />

      {/* 3. Thẻ Twitter */}
      <meta name="twitter:card" content="summary_large_image" />
      <meta name="twitter:title" content={title || defaultTitle} />
      <meta name="twitter:description" content={description || defaultDesc} />
      <meta name="twitter:image" content={image || defaultImage} />
    </Helmet>
  );
};

export default SEO;
