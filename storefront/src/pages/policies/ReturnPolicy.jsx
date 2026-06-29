import { useEffect } from 'react';
import { useLanguage } from '../../context/LanguageContext';

const ReturnPolicy = () => {
  const { t } = useLanguage();

  useEffect(() => {
    window.scrollTo(0, 0);
  }, []);

  return (
    <div className="mx-auto min-h-[70vh] max-w-4xl px-6 pb-20 pt-20 leading-relaxed text-ink/80">
      <h1 className="mb-10 text-center font-heading text-4xl text-espresso">
        {t('policies.return_title')}
      </h1>

      <div className="space-y-6">
        <section className="rounded-2xl border border-sand bg-surface p-6 md:p-8">
          <h2 className="mb-4 font-heading text-xl text-espresso">{t('policies.return_cond_title')}</h2>
          <ul className="list-disc space-y-2 pl-5 text-ink/75 marker:text-clay">
            <li>{t('policies.return_cond_1')}</li>
            <li>{t('policies.return_cond_2')}</li>
            <li>{t('policies.return_cond_3')}</li>
          </ul>
        </section>

        <section className="rounded-2xl border border-sand bg-surface p-6 md:p-8">
          <h2 className="mb-4 font-heading text-xl text-espresso">{t('policies.return_process_title')}</h2>
          <p className="text-ink/75">{t('policies.return_process_desc')}</p>
        </section>
      </div>
    </div>
  );
};

export default ReturnPolicy;
