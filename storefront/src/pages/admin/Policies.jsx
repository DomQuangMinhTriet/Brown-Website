import { useEffect, useMemo, useState } from 'react';
import axios from 'axios';
import { FaPlus, FaSave, FaTrash } from 'react-icons/fa';
import { toast } from 'react-toastify';
import { useAdminAuth } from '../../context/AdminAuthContext';
import { translations } from '../../utils/translations';
import { getDefaultPolicyContent, normalizePolicy, policyLabels } from '../../utils/policyContent';

const SLUGS = ['return', 'shipping', 'care'];
const emptySection = () => ({ heading: '', body: '', items: [] });

const Policies = () => {
  const { supabase } = useAdminAuth();
  const [slug, setSlug] = useState('return');
  const [language, setLanguage] = useState('vi');
  const [content, setContent] = useState(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const defaults = useMemo(() => Object.fromEntries(['vi', 'en'].map((lang) => {
    const t = (key) => key.split('.').reduce((value, part) => value?.[part], translations[lang]) || key;
    return [lang, getDefaultPolicyContent(t)[slug]];
  })), [slug]);

  useEffect(() => {
    let active = true;
    setLoading(true);
    axios.get(`${import.meta.env.VITE_API_URL}/api/content/policies/${slug}`)
      .then(({ data }) => {
        if (active) setContent({ vi: normalizePolicy(data?.data?.content?.vi || defaults.vi), en: normalizePolicy(data?.data?.content?.en || defaults.en) });
      })
      .catch(() => active && setContent({ vi: normalizePolicy(defaults.vi), en: normalizePolicy(defaults.en) }))
      .finally(() => active && setLoading(false));
    return () => { active = false; };
  }, [slug, defaults]);

  const updatePolicy = (updater) => setContent((previous) => ({ ...previous, [language]: updater(previous[language]) }));
  const updateSection = (index, changes) => updatePolicy((policy) => ({ ...policy, sections: policy.sections.map((section, i) => i === index ? { ...section, ...changes } : section) }));

  const save = async () => {
    try {
      setSaving(true);
      const { data: { session } } = await supabase.auth.getSession();
      if (!session?.access_token) throw new Error('Phiên đăng nhập đã hết hạn.');
      await axios.put(`${import.meta.env.VITE_API_URL}/api/content/policies/${slug}`, { content }, { headers: { Authorization: `Bearer ${session.access_token}` } });
      toast.success('Đã lưu nội dung chính sách.');
    } catch (error) {
      toast.error(error.response?.data?.message || error.message || 'Không thể lưu nội dung.');
    } finally { setSaving(false); }
  };

  const policy = content?.[language];
  return <div className="mx-auto max-w-5xl">
    <div className="mb-6 flex flex-col justify-between gap-4 sm:flex-row sm:items-end"><div><h1 className="text-2xl font-bold text-stone-800">Nội dung chính sách</h1><p className="mt-1 text-sm text-stone-500">Chỉnh sửa nội dung hiển thị trên các trang chính sách của cửa hàng.</p></div><button onClick={save} disabled={loading || saving} className="inline-flex items-center justify-center gap-2 rounded-lg bg-stone-900 px-4 py-2.5 text-sm font-semibold text-white hover:bg-black disabled:opacity-60"><FaSave /> {saving ? 'Đang lưu...' : 'Lưu thay đổi'}</button></div>
    <div className="mb-6 flex flex-wrap gap-2">{SLUGS.map((item) => <button key={item} onClick={() => setSlug(item)} className={`rounded-lg px-4 py-2 text-sm font-medium ${slug === item ? 'bg-stone-900 text-white' : 'bg-white text-stone-600 ring-1 ring-stone-200'}`}>{policyLabels[item]}</button>)}<span className="mx-1 hidden h-9 border-l border-stone-200 sm:block" />{['vi', 'en'].map((item) => <button key={item} onClick={() => setLanguage(item)} className={`rounded-lg px-3 py-2 text-sm font-medium ${language === item ? 'bg-amber-100 text-amber-900' : 'bg-white text-stone-500 ring-1 ring-stone-200'}`}>{item === 'vi' ? 'Tiếng Việt' : 'English'}</button>)}</div>
    {loading || !policy ? <div className="rounded-xl bg-white p-8 text-stone-500">Đang tải nội dung...</div> : <div className="space-y-5 rounded-xl bg-white p-5 shadow-sm ring-1 ring-stone-200 md:p-7">
      <label className="block text-sm font-semibold text-stone-700">Tiêu đề trang<input value={policy.title} onChange={(event) => updatePolicy((current) => ({ ...current, title: event.target.value }))} className="mt-2 w-full rounded-lg border border-stone-300 px-3 py-2.5" /></label>
      {policy.sections.map((section, index) => <div key={index} className="rounded-xl border border-stone-200 p-4"><div className="mb-3 flex items-center justify-between"><span className="font-semibold text-stone-700">Mục {index + 1}</span><button onClick={() => updatePolicy((current) => ({ ...current, sections: current.sections.filter((_, i) => i !== index) }))} className="text-sm text-red-500"><FaTrash /></button></div><label className="block text-sm text-stone-600">Tiêu đề mục<input value={section.heading} onChange={(event) => updateSection(index, { heading: event.target.value })} className="mt-1 w-full rounded-lg border border-stone-300 px-3 py-2" /></label><label className="mt-3 block text-sm text-stone-600">Đoạn nội dung<textarea value={section.body} onChange={(event) => updateSection(index, { body: event.target.value })} rows="3" className="mt-1 w-full rounded-lg border border-stone-300 px-3 py-2" /></label><label className="mt-3 block text-sm text-stone-600">Danh sách gạch đầu dòng <span className="text-stone-400">(mỗi dòng một ý)</span><textarea value={section.items.join('\n')} onChange={(event) => updateSection(index, { items: event.target.value.split('\n').map((item) => item.trim()).filter(Boolean) })} rows="4" className="mt-1 w-full rounded-lg border border-stone-300 px-3 py-2" /></label></div>)}
      <button onClick={() => updatePolicy((current) => ({ ...current, sections: [...current.sections, emptySection()] }))} className="inline-flex items-center gap-2 rounded-lg border border-dashed border-stone-400 px-4 py-2 text-sm font-medium text-stone-600"><FaPlus /> Thêm mục</button>
    </div>}
  </div>;
};

export default Policies;
