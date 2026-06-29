export const isVideoUrl = (url) => !!url && /\.(mp4|webm|ogg|mov)$/i.test(url);

// Chuẩn hoá 1 row từ DB (hoặc demo) thành block render được.
export const toLookbookBlock = (r) => ({
  type: r.block_type || (r.image_url_2 ? 'compare' : 'full'),
  image_url: r.image_url,
  image_url_2: r.image_url_2,
  title: r.title,
  caption: r.caption,
});
