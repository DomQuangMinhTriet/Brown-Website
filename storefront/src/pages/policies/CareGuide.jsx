import { useEffect } from 'react';
import { useLanguage } from '../../context/LanguageContext';

const CareGuide = () => {
  const { t } = useLanguage();

  useEffect(() => {
    window.scrollTo(0, 0);
  }, []);

  const steps = [
    { bold: t('policies.care_step1_bold'), text: t('policies.care_step1_text') },
    { bold: t('policies.care_step2_bold'), text: t('policies.care_step2_text') },
    { bold: t('policies.care_step3_bold'), text: t('policies.care_step3_text') },
    { bold: t('policies.care_step4_bold'), text: t('policies.care_step4_text') },
    {
      bold: t('policies.care_step5_bold'),
      items: [
        t('policies.care_step5_item1'),
        t('policies.care_step5_item2'),
        t('policies.care_step5_item3'),
      ],
    },
  ];

  return (
    <div className="mx-auto min-h-[70vh] max-w-4xl px-6 pb-20 pt-20 leading-relaxed text-ink/80">
      <h1 className="mb-10 text-center font-heading text-4xl text-espresso">
        {t('policies.care_title')}
      </h1>

      <div className="space-y-6">
        {/* Bảng hướng dẫn */}
        <section className="overflow-hidden rounded-2xl border border-sand bg-surface p-6 md:p-8">
          <div className="overflow-x-auto">
            <table className="w-full border-collapse text-left">
              <thead>
                <tr className="border-b border-sand">
                  <th className="w-16 py-3 pr-4 text-sm font-semibold uppercase tracking-wide text-muted">
                    {t('policies.care_col_no')}
                  </th>
                  <th className="py-3 text-sm font-semibold uppercase tracking-wide text-muted">
                    {t('policies.care_col_guide')}
                  </th>
                </tr>
              </thead>
              <tbody>
                {steps.map((step, index) => (
                  <tr key={index} className="border-b border-sand/60 align-top last:border-0">
                    <td className="py-4 pr-4 font-heading text-clay">{index + 1}</td>
                    <td className="py-4 text-ink/75">
                      <span className="font-semibold text-espresso">{step.bold}</span>
                      {step.text && <> {step.text}</>}
                      {step.items && (
                        <ul className="mt-2 list-disc space-y-1.5 pl-5 marker:text-clay">
                          {step.items.map((item, i) => (
                            <li key={i}>{item}</li>
                          ))}
                        </ul>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>

        {/* Lưu ý */}
        <section className="rounded-2xl border border-sand bg-surface p-6 md:p-8">
          <h2 className="mb-4 font-heading text-xl text-espresso">
            {t('policies.care_notes_title')}
          </h2>
          <ul className="list-disc space-y-2 pl-5 text-ink/75 marker:text-clay">
            <li>{t('policies.care_note1')}</li>
            <li>{t('policies.care_note2')}</li>
            <li>{t('policies.care_note3')}</li>
          </ul>
        </section>

        {/* Lời nhắn */}
        <div className="pt-4 text-center">
          <p className="font-sugo text-2xl uppercase tracking-[0.1em] text-cocoa">BROWN</p>
          <p className="mt-3 font-heading italic text-muted">{t('policies.care_quote')}</p>
        </div>
      </div>
    </div>
  );
};

export default CareGuide;
