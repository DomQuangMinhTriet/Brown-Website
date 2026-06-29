import { Link } from 'react-router-dom';
import { useCart } from '../context/CartContext';
import { FaTrash } from 'react-icons/fa';
import { useLanguage } from '../context/LanguageContext';
import { formatPrice } from '../utils/currencyHelper';
import Container from '../components/ui/Container';
import Button from '../components/ui/Button';

const QtyStepper = ({ item, updateQuantity }) => (
  <div className="flex items-center rounded-full border border-sand">
    <button onClick={() => updateQuantity(item.variant_id, item.quantity - 1)} className="px-3 py-1.5 text-muted transition-colors hover:text-cocoa" aria-label="Giảm">−</button>
    <span className="w-10 text-center text-sm font-medium text-ink">{item.quantity}</span>
    <button onClick={() => updateQuantity(item.variant_id, item.quantity + 1)} className="px-3 py-1.5 text-muted transition-colors hover:text-cocoa" aria-label="Tăng">+</button>
  </div>
);

const Cart = () => {
  const { cartItems, removeFromCart, updateQuantity, cartTotal } = useCart();
  const { t, lang } = useLanguage();

  if (cartItems.length === 0) {
    return (
      <div className="flex min-h-[60vh] flex-col items-center justify-center px-4 text-center">
        <h1 className="mb-4 font-heading text-3xl text-espresso">{t('cart.empty_title')}</h1>
        <p className="mb-8 text-muted">{t('cart.empty_desc')}</p>
        <Button to="/" variant="solid" size="lg">{t('cart.shop_now')}</Button>
      </div>
    );
  }

  return (
    <Container className="py-12 md:py-16">
      <h1 className="mb-10 text-center font-heading text-4xl text-espresso">{t('cart.title')}</h1>

      <div className="grid grid-cols-1 gap-12 lg:grid-cols-3">
        {/* DANH SÁCH SẢN PHẨM */}
        <div className="lg:col-span-2">
          <div className="mb-6 hidden grid-cols-12 gap-4 border-b border-sand pb-4 text-xs font-semibold uppercase tracking-wider text-muted md:grid">
            <div className="col-span-6">{t('cart.product')}</div>
            <div className="col-span-3 text-center">{t('cart.quantity')}</div>
            <div className="col-span-3 text-right">{t('cart.price')}</div>
          </div>

          <div className="space-y-8">
            {cartItems.map((item) => (
              <div key={item.variant_id} className="grid grid-cols-12 items-center gap-4 border-b border-sand/60 pb-8 md:border-0 md:pb-0">
                <div className="col-span-12 flex items-center gap-4 md:col-span-6">
                  <button onClick={() => removeFromCart(item.variant_id)} className="text-sand transition-colors hover:text-clay" aria-label="Xóa">
                    <FaTrash />
                  </button>
                  <img src={item.image} alt={item.name} className="h-24 w-20 rounded-xl bg-parchment object-cover" />
                  <div>
                    <Link to={`/product/${item.slug}`} className="font-heading text-lg text-espresso transition-colors hover:text-cocoa line-clamp-1">
                      {item.name}
                    </Link>
                    <p className="mb-2 text-sm text-muted">Size: {item.size} | {t('product.select_color')}: {lang === 'en' && item.color_en ? item.color_en : item.color}</p>
                    <div className="mb-2 font-medium text-cocoa md:hidden">
                      {formatPrice(item.price, lang === 'en' ? 'USD' : 'VND')}
                    </div>
                    <div className="w-max md:hidden">
                      <QtyStepper item={item} updateQuantity={updateQuantity} />
                    </div>
                  </div>
                </div>

                <div className="col-span-4 hidden justify-center md:col-span-3 md:flex">
                  <QtyStepper item={item} updateQuantity={updateQuantity} />
                </div>

                <div className="col-span-4 hidden text-right font-medium text-espresso md:col-span-3 md:block">
                  {formatPrice(item.price * item.quantity, lang === 'en' ? 'USD' : 'VND')}
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* TỔNG TIỀN */}
        <div className="lg:col-span-1">
          <div className="sticky top-24 rounded-2xl border border-sand bg-surface p-6">
            <h2 className="mb-6 font-heading text-xl text-espresso">{t('cart.summary')}</h2>

            <div className="mb-4 flex justify-between text-ink/80">
              <span>{t('cart.subtotal')}</span>
              <span>{formatPrice(cartTotal, lang === 'en' ? 'USD' : 'VND')}</span>
            </div>
            <div className="mb-4 flex justify-between text-ink/80">
              <span>{t('cart.shipping')}</span>
              <span>{formatPrice(20000, lang === 'en' ? 'USD' : 'VND')}</span>
            </div>

            <hr className="my-4 border-sand" />

            <div className="mb-8 flex justify-between text-lg font-semibold text-espresso">
              <span>{t('cart.total')}</span>
              <span>{formatPrice(cartTotal + 20000, lang === 'en' ? 'USD' : 'VND')}</span>
            </div>

            <Button to="/checkout" variant="solid" size="lg" className="w-full">
              {t('cart.checkout')}
            </Button>
          </div>
        </div>
      </div>
    </Container>
  );
};

export default Cart;
