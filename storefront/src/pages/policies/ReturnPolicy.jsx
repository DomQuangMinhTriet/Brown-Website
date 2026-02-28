import { useEffect } from 'react';
import { useLanguage } from '../../context/LanguageContext';

const ReturnPolicy = () => {
  const { t } = useLanguage();

  // FIX LỖI RESPONSIVE: Ép trình duyệt cuộn lên đầu trang khi vào
  useEffect(() => {
    window.scrollTo(0, 0);
  }, []);

  return (
    <div className="max-w-4xl mx-auto px-6 pt-24 pb-16 text-stone-700 leading-relaxed min-h-[70vh]">
      <h1 className="text-3xl font-serif font-bold text-stone-900 mb-8 text-center uppercase">
        {t('policies.return_title')}
      </h1>
      
      <div className="space-y-6">
        <section className="bg-stone-50 p-6 rounded-xl border border-stone-100">
          <h2 className="font-bold text-lg text-stone-900 mb-4">{t('policies.return_cond_title')}</h2>
          <ul className="list-disc pl-5 space-y-2 text-stone-600">
            <li>{t('policies.return_cond_1')}</li>
            <li>{t('policies.return_cond_2')}</li>
            <li>{t('policies.return_cond_3')}</li>
          </ul>
        </section>

        <section className="bg-stone-50 p-6 rounded-xl border border-stone-100">
          <h2 className="font-bold text-lg text-stone-900 mb-4">{t('policies.return_process_title')}</h2>
          <p className="text-stone-600">{t('policies.return_process_desc')}</p>
        </section>
      </div>
    </div>
  );
};

export default ReturnPolicy;