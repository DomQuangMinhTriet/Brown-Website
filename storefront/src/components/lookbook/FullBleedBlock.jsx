import Container from '../ui/Container';
import { isVideoUrl } from './blockUtils';

/**
 * Khối ảnh/video hiển thị ĐẦY ĐỦ kích thước gốc — không cắt xén
 * (không dùng object-cover ép chiều cao cố định). Chiều rộng lấp đầy
 * khung trang, chiều cao tự động theo đúng tỉ lệ ảnh/video thật, nên
 * luôn khớp với giao diện trên cả desktop và mobile.
 */
const FullBleedBlock = ({ item }) => {
  const video = isVideoUrl(item.image_url);

  return (
    <section className="bg-parchment">
      {video ? (
        <video
          src={item.image_url}
          autoPlay loop muted playsInline
          className="block h-auto w-full"
        />
      ) : (
        <img
          src={item.image_url}
          alt={item.title || 'BROWN Lookbook'}
          loading="lazy"
          className="block h-auto w-full"
        />
      )}
      {(item.title || item.caption) && (
        <Container className="py-8 md:py-10">
          {item.title && <h2 className="font-heading text-2xl text-espresso md:text-4xl">{item.title}</h2>}
          {item.caption && <p className="mt-2 text-muted">{item.caption}</p>}
        </Container>
      )}
    </section>
  );
};

export default FullBleedBlock;
