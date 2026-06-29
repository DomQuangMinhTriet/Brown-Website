import Container from '../ui/Container';

const QuoteBlock = ({ item }) => (
  <section className="bg-parchment/50 py-24 text-center md:py-32">
    <Container>
      <p className="mx-auto max-w-3xl font-heading text-3xl italic leading-snug text-espresso md:text-5xl">
        {item.caption}
      </p>
    </Container>
  </section>
);

export default QuoteBlock;
