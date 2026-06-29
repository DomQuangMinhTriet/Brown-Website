import { useEffect } from 'react';
import { useLanguage } from '../../context/LanguageContext';

const ShippingPolicy = () => {
  const { t } = useLanguage();

  useEffect(() => {
    window.scrollTo(0, 0);
  }, []);

  return (
    <div className="mx-auto min-h-[70vh] max-w-4xl px-6 pb-20 pt-20 leading-relaxed text-ink/80">
      <h1 className="mb-10 text-center font-heading text-4xl text-espresso">
        {t('policies.shipping_title')}
      </h1>

      <div className="space-y-6">
        <section className="rounded-2xl border border-sand bg-surface p-6 md:p-8">
          <h2 className="mb-4 font-heading text-xl text-espresso">{t('policies.shipping_fee_title')}</h2>
          <p className="text-ink/75">{t('policies.shipping_fee_desc')}</p>
        </section>

        <section className="rounded-2xl border border-sand bg-surface p-6 md:p-8">
          <h2 className="mb-4 font-heading text-xl text-espresso">{t('policies.shipping_time_title')}</h2>
          <p className="text-ink/75">{t('policies.shipping_time_desc')}</p>
        </section>
      </div>
    </div>
  );
};

export default ShippingPolicy;
