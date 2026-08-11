import { useEffect, useState } from 'react';
import { useSearchParams, useNavigate } from 'react-router-dom';
import { FaStore, FaShoppingCart } from 'react-icons/fa';
import { useCart } from '../context/CartContext';
import { useLanguage } from '../context/LanguageContext';
import { formatPrice } from '../utils/currencyHelper';
import Container from '../components/ui/Container';
import Button from '../components/ui/Button';
import ProductCard from '../components/ui/ProductCard';
import { cachedGet } from '../utils/apiCache';

const Collection = () => {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const { cartCount, cartTotal } = useCart();
  const { t, lang } = useLanguage();
  const navigate = useNavigate();

  const [searchParams] = useSearchParams();
  const searchQuery = searchParams.get('search');
  const isPosMode = searchParams.get('pos') === 'true';
  const categorySlug = searchParams.get('category');

  const [pageTitle, setPageTitle] = useState(t('collection.all_products'));
  const [visibleCount, setVisibleCount] = useState(12);

  useEffect(() => {
    const fetchCategoryName = async () => {
        if (searchQuery) {
            setPageTitle(`${t('collection.search_result')}: "${searchQuery}"`);
        } else if (categorySlug) {
            try {
                const res = await cachedGet(`${import.meta.env.VITE_API_URL}/api/categories`, 120_000);
                if (res.data.success) {
                    const foundCat = res.data.data.find(c => c.slug === categorySlug);
                    setPageTitle(foundCat ? `${foundCat.name}` : `${categorySlug}`);
                }
            } catch (error) {
                console.error("Lỗi lấy tên danh mục:", error);
                setPageTitle(categorySlug);
            }
        } else {
            setPageTitle(t('collection.all_products'));
        }
    };
    fetchCategoryName();
  }, [categorySlug, searchQuery, t]);

  useEffect(() => {
    const fetchProducts = async () => {
      setLoading(true);
      try {
        let url = `${import.meta.env.VITE_API_URL}/api/products?`;
        const params = ['view=card'];
        if (searchQuery) params.push(`search=${encodeURIComponent(searchQuery)}`);
        if (categorySlug) params.push(`category=${encodeURIComponent(categorySlug)}`);

        const res = await cachedGet(url + params.join('&'), 60_000);
        if (res.data.success) setProducts(res.data.data);
      } catch (error) {
          console.error(error);
          setProducts([]);
      }
      finally { setLoading(false); }
    };
    fetchProducts();
    setVisibleCount(12);
  }, [categorySlug, searchQuery]);

  return (
    <div className={isPosMode ? 'min-h-screen bg-parchment/40 pb-24' : 'bg-cream'}>

      {isPosMode && (
          <div className="sticky top-20 z-40 flex items-center justify-between bg-cocoa p-4 text-cream shadow-md">
             <div className="flex items-center gap-2 text-lg font-medium uppercase">
                <FaStore/> {t('collection.pos_mode')}
             </div>
             <button onClick={() => window.close()} className="text-xs underline opacity-80 hover:opacity-100">
                {t('collection.exit')}
             </button>
          </div>
      )}

      <Container className="py-12 md:py-16">
        <div className="mb-12 text-center">
            <h1 className="font-heading text-4xl text-espresso md:text-5xl">{pageTitle}</h1>
            <span className="mx-auto mt-6 block h-px w-16 bg-cocoa/30" />
        </div>

        {loading ? (
            <div className="grid grid-cols-2 gap-x-5 gap-y-10 md:grid-cols-3 lg:grid-cols-4">
              {Array.from({ length: 8 }).map((_, i) => (
                <div key={i} className="animate-pulse">
                  <div className="aspect-[3/4] rounded-2xl bg-sand/60" />
                  <div className="mt-4 h-4 w-3/4 rounded bg-sand/60" />
                  <div className="mt-2 h-3 w-1/3 rounded bg-sand/40" />
                </div>
              ))}
            </div>
        ) : (
            <>
                <div className="grid grid-cols-2 gap-x-5 gap-y-10 md:grid-cols-3 lg:grid-cols-4 md:gap-x-6 md:gap-y-14">
                {products.slice(0, visibleCount).map(product => (
                    <ProductCard key={product.id} product={product} posMode={isPosMode} />
                ))}
                </div>

                {visibleCount < products.length && (
                    <div className="mt-14 text-center">
                        <Button onClick={() => setVisibleCount(prev => prev + 12)} variant="outline" size="lg">
                            {lang === 'en' ? 'Load more' : 'Xem thêm sản phẩm'}
                        </Button>
                    </div>
                )}
            </>
        )}

        {!loading && products.length === 0 && (
            <div className="py-10 text-center italic text-muted">
                {t('collection.no_products')}
            </div>
        )}
      </Container>

      {isPosMode && (
        <div className="fixed bottom-0 left-0 z-50 flex w-full items-center justify-between border-t border-sand bg-surface p-4 shadow-[0_-5px_20px_-10px_rgba(63,46,38,0.3)]">
            <div className="flex items-center gap-4">
                <div className="relative flex h-12 w-12 items-center justify-center rounded-full bg-cocoa text-xl text-cream">
                    <FaShoppingCart />
                    {cartCount > 0 && <span className="absolute -right-1 -top-1 flex h-5 w-5 items-center justify-center rounded-full border border-cream bg-clay text-xs text-cream">{cartCount}</span>}
                </div>
                <div>
                    <p className="text-xs uppercase text-muted">{t('collection.subtotal')}</p>
                    <p className="text-xl font-semibold text-espresso">{formatPrice(cartTotal, lang === 'en' ? 'USD' : 'VND')}</p>
                </div>
            </div>

            <Button onClick={() => navigate('/checkout?pos=true')} disabled={cartCount === 0} variant="clay" size="lg">
                {t('collection.checkout')}
            </Button>
        </div>
      )}
    </div>
  );
};

export default Collection;
