import { useEffect, useState } from 'react';
import axios from 'axios';
import { useLanguage } from '../../context/LanguageContext';
import { getDefaultPolicyContent, normalizePolicy } from '../../utils/policyContent';

const PolicyPage = ({ slug }) => {
  const { lang, t } = useLanguage();
  const [remoteContent, setRemoteContent] = useState(null);

  useEffect(() => {
    window.scrollTo(0, 0);
    let active = true;
    axios.get(`${import.meta.env.VITE_API_URL}/api/content/policies/${slug}`)
      .then(({ data }) => { if (active) setRemoteContent(data?.data?.content || null); })
      .catch(() => active && setRemoteContent(null));
    return () => { active = false; };
  }, [slug]);

  const policy = normalizePolicy(remoteContent?.[lang] || getDefaultPolicyContent(t)[slug]);
  return (
    <div className="mx-auto min-h-[70vh] max-w-4xl px-6 pb-20 pt-20 leading-relaxed text-ink/80">
      <h1 className="mb-10 text-center font-heading text-4xl text-espresso">{policy.title}</h1>
      <div className="space-y-6">
        {policy.sections.map((section, sectionIndex) => (
          <section key={sectionIndex} className="rounded-2xl border border-sand bg-surface p-6 md:p-8">
            {section.heading && <h2 className="mb-4 font-heading text-xl text-espresso">{section.heading}</h2>}
            {section.body && <p className="whitespace-pre-line text-ink/75">{section.body}</p>}
            {section.items.length > 0 && <ul className={`${section.body ? 'mt-4 ' : ''}list-disc space-y-2 pl-5 text-ink/75 marker:text-clay`}>
              {section.items.map((item, itemIndex) => <li key={itemIndex} className="whitespace-pre-line">{item}</li>)}
            </ul>}
          </section>
        ))}
      </div>
    </div>
  );
};

export default PolicyPage;
