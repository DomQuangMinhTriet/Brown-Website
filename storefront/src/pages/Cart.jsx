import { Link } from 'react-router-dom';
import { useCart } from '../context/CartContext';
import { FaTrash, FaArrowRight } from 'react-icons/fa';
import { useLanguage } from '../context/LanguageContext';
import { formatPrice } from '../utils/currencyHelper';

const Cart = () => {
  const { cartItems, removeFromCart, updateQuantity, cartTotal } = useCart();
  const { t, lang } = useLanguage();

  if (cartItems.length === 0) {
    return (
      <div className="min-h-[60vh] flex flex-col items-center justify-center text-center px-4">
        <h2 className="text-2xl font-serif text-stone-800 mb-4">{t('cart.empty_title')}</h2>
        <p className="text-stone-500 mb-8">{t('cart.empty_desc')}</p>
        <Link to="/" className="bg-stone-900 text-white px-8 py-3 uppercase tracking-wider text-sm hover:bg-stone-700">
          {t('cart.shop_now')}
        </Link>
      </div>
    );
  }

  return (
    <div className="max-w-7xl mx-auto px-6 py-10 md:py-16">
      <h1 className="text-3xl font-serif text-stone-900 mb-10 text-center">{t('cart.title')}</h1>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-12">
        {/* DANH SÁCH SẢN PHẨM */}
        <div className="lg:col-span-2">
          <div className="grid grid-cols-12 gap-4 border-b border-stone-200 pb-4 text-xs font-bold text-stone-500 uppercase tracking-wider mb-6">
            <div className="col-span-8 md:col-span-6"><p className="text-left">{t('cart.product')}</p></div>
            <div className="col-span-4 md:col-span-3 hidden md:block"><p className="text-center">{t('cart.quantity')}</p></div>
            <div className="col-span-4 md:col-span-3 hidden md:block"><p className="text-right">{t('cart.price')}</p></div>
          </div>

          <div className="space-y-8">
            {cartItems.map((item) => (
              <div key={item.variant_id} className="grid grid-cols-12 gap-4 items-center">
                <div className="col-span-12 md:col-span-6 flex items-center gap-4">
                  <button onClick={() => removeFromCart(item.variant_id)} className="text-stone-300 hover:text-red-500 transition-colors">
                    <FaTrash />
                  </button>
                  <img src={item.image} alt={item.name} className="w-20 h-24 object-cover rounded bg-stone-100" />
                  <div>
                    <Link to={`/product/${item.slug}`} className="font-bold text-stone-900 hover:text-stone-600 transition-colors line-clamp-1">
                      {item.name}
                    </Link>
                    <p className="text-stone-500 text-sm mb-2">Size: {item.size} | {t('product.select_color')}: {lang === 'en' && item.color_en ? item.color_en : item.color}</p>
                    <div className="md:hidden font-bold text-stone-900 mb-2">
                      {formatPrice(item.price, lang === 'en' ? 'USD' : 'VND')}
                    </div>
                    <div className="flex items-center border border-stone-200 rounded w-max md:hidden">
                      <button onClick={() => updateQuantity(item.variant_id, item.quantity - 1)} className="px-3 py-1 text-stone-500 hover:bg-stone-50">-</button>
                      <span className="px-3 py-1 font-medium text-sm w-10 text-center">{item.quantity}</span>
                      <button onClick={() => updateQuantity(item.variant_id, item.quantity + 1)} className="px-3 py-1 text-stone-500 hover:bg-stone-50">+</button>
                    </div>
                  </div>
                </div>

                <div className="col-span-4 md:col-span-3 hidden md:flex justify-center">
                   <div className="flex items-center border border-stone-200 rounded">
                      <button onClick={() => updateQuantity(item.variant_id, item.quantity - 1)} className="px-3 py-1 text-stone-500 hover:bg-stone-50">-</button>
                      <span className="px-3 py-1 font-medium text-sm w-12 text-center">{item.quantity}</span>
                      <button onClick={() => updateQuantity(item.variant_id, item.quantity + 1)} className="px-3 py-1 text-stone-500 hover:bg-stone-50">+</button>
                    </div>
                </div>

                <div className="col-span-4 md:col-span-3 hidden md:block text-right font-bold text-stone-900">
                  {formatPrice(item.price * item.quantity, lang === 'en' ? 'USD' : 'VND')}
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* TỔNG TIỀN & THANH TOÁN */}
        <div className="lg:col-span-1">
          <div className="bg-stone-50 p-6 rounded-lg sticky top-24">
            <h3 className="font-bold text-stone-900 uppercase tracking-wider mb-6">{t('cart.summary')}</h3>
            
            <div className="flex justify-between mb-4 text-stone-600">
              <span>{t('cart.subtotal')}</span>
              <span>{formatPrice(cartTotal, lang === 'en' ? 'USD' : 'VND')}</span>
            </div>
            <div className="flex justify-between mb-4 text-stone-600">
              <span>{t('cart.shipping')}</span>
              <span>---</span>
            </div>
            
            <hr className="border-stone-200 my-4" />
            
            <div className="flex justify-between mb-8 text-lg font-bold text-stone-900">
              <span>{t('cart.total')}</span>
              <span>{formatPrice(cartTotal, lang === 'en' ? 'USD' : 'VND')}</span>
            </div>

            <Link to="/checkout" className="block w-full bg-stone-900 text-white text-center py-4 uppercase tracking-widest text-sm font-bold hover:bg-stone-800 transition-colors">
              {t('cart.checkout')}
            </Link>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Cart;