import { useEffect } from 'react';
import { useLanguage } from '../../context/LanguageContext';

const CareGuide = () => {
  const { t } = useLanguage();

  // FIX LỖI RESPONSIVE: Ép trình duyệt cuộn lên đầu trang khi vào
  useEffect(() => {
    window.scrollTo(0, 0);
  }, []);

  // Danh sách các bước hướng dẫn (phần in đậm + phần mô tả)
  const steps = [
    { bold: t('policies.care_step1_bold'), text: t('policies.care_step1_text') },
    { bold: t('policies.care_step2_bold'), text: t('policies.care_step2_text') },
    { bold: t('policies.care_step3_bold'), text: t('policies.care_step3_text') },
    { bold: t('policies.care_step4_bold'), text: t('policies.care_step4_text') },
  ];

  return (
    <div className="max-w-4xl mx-auto px-6 pt-24 pb-16 text-stone-700 leading-relaxed min-h-[70vh]">
      <h1 className="text-3xl font-serif font-bold text-stone-900 mb-8 text-center uppercase">
        {t('policies.care_title')}
      </h1>

      <div className="space-y-6">
        {/* Bảng hướng dẫn */}
        <section className="bg-stone-50 p-6 rounded-xl border border-stone-100 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse">
              <thead>
                <tr className="border-b border-stone-300">
                  <th className="py-3 pr-4 w-16 text-sm font-bold uppercase tracking-wide text-stone-500">
                    {t('policies.care_col_no')}
                  </th>
                  <th className="py-3 text-sm font-bold uppercase tracking-wide text-stone-500">
                    {t('policies.care_col_guide')}
                  </th>
                </tr>
              </thead>
              <tbody>
                {steps.map((step, index) => (
                  <tr key={index} className="border-b border-stone-200 last:border-0 align-top">
                    <td className="py-4 pr-4 text-stone-500">{index + 1}</td>
                    <td className="py-4 text-stone-600">
                      <span className="font-bold text-stone-900">{step.bold}</span>{' '}
                      {step.text}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>

        {/* Lưu ý */}
        <section className="bg-stone-50 p-6 rounded-xl border border-stone-100">
          <h2 className="font-bold text-lg text-stone-900 mb-4">
            ✱ {t('policies.care_notes_title')}
          </h2>
          <ul className="list-disc pl-5 space-y-2 text-stone-600">
            <li>{t('policies.care_note1')}</li>
            <li>{t('policies.care_note2')}</li>
            <li>{t('policies.care_note3')}</li>
            <li className="font-bold text-stone-900">{t('policies.care_note4')}</li>
          </ul>
        </section>

        {/* Lời nhắn */}
        <div className="text-center pt-2">
          <p className="font-serif font-bold text-stone-900 tracking-widest mb-3">BROWN 🤍</p>
          <p className="italic text-stone-500">{t('policies.care_quote')}</p>
        </div>
      </div>
    </div>
  );
};

export default CareGuide;
