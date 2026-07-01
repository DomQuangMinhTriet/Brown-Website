import FullBleedBlock from './FullBleedBlock';
import CompareBlock from './CompareBlock';
import QuoteBlock from './QuoteBlock';

/**
 * Render danh sách block Lookbook theo đúng thứ tự — dùng CHUNG cho trang
 * public /lookbook và khung xem trước (preview) trong admin, để đảm bảo
 * preview khớp 100% với những gì khách sẽ thấy.
 */
const LookbookBlocks = ({ blocks, lang }) => (
  <>
    {blocks.map((b, i) => {
      if (b.type === 'quote') return <QuoteBlock key={i} item={b} />;
      if (b.type === 'compare' && b.image_url_2) return <CompareBlock key={i} item={b} lang={lang} />;
      return <FullBleedBlock key={i} item={b} />;
    })}
  </>
);

export default LookbookBlocks;
