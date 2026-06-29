import Container from '../ui/Container';
import ImageCompareSlider from '../ui/ImageCompareSlider';

const CompareBlock = ({ item, lang }) => (
  <section className="bg-cream py-16 md:py-24">
    <Container>
      <div className="mb-8 text-center">
        <h2 className="font-heading text-3xl text-espresso md:text-5xl">
          {item.title || (lang === 'en' ? 'Two ways' : 'Phối đôi')}
        </h2>
        <p className="mt-2 text-sm uppercase tracking-[0.2em] text-muted">
          {lang === 'en' ? 'Drag to compare' : 'Kéo để xem'}
        </p>
        {item.caption && <p className="mt-3 text-muted">{item.caption}</p>}
      </div>
      <ImageCompareSlider
        before={item.image_url}
        after={item.image_url_2}
        beforeLabel="01"
        afterLabel="02"
        className="mx-auto aspect-[4/5] max-w-3xl sm:aspect-[16/10]"
      />
    </Container>
  </section>
);

export default CompareBlock;
