export const policyLabels = {
  return: 'Chính sách đổi hàng',
  shipping: 'Chính sách vận chuyển',
  care: 'Hướng dẫn bảo quản',
};

export const getDefaultPolicyContent = (t) => ({
  return: { title: t('policies.return_title'), sections: [
    { heading: t('policies.return_cond_title'), body: '', items: [t('policies.return_cond_1'), t('policies.return_cond_2'), t('policies.return_cond_3')] },
    { heading: t('policies.return_process_title'), body: t('policies.return_process_desc'), items: [] },
  ] },
  shipping: { title: t('policies.shipping_title'), sections: [
    { heading: t('policies.shipping_fee_title'), body: t('policies.shipping_fee_desc'), items: [] },
    { heading: t('policies.shipping_time_title'), body: t('policies.shipping_time_desc'), items: [] },
  ] },
  care: { title: t('policies.care_title'), sections: [
    { heading: t('policies.care_col_guide'), body: '', items: [
      `${t('policies.care_step1_bold')} ${t('policies.care_step1_text')}`,
      `${t('policies.care_step2_bold')} ${t('policies.care_step2_text')}`,
      `${t('policies.care_step3_bold')} ${t('policies.care_step3_text')}`,
      `${t('policies.care_step4_bold')} ${t('policies.care_step4_text')}`,
      `${t('policies.care_step5_bold')}\n• ${t('policies.care_step5_item1')}\n• ${t('policies.care_step5_item2')}\n• ${t('policies.care_step5_item3')}`,
    ] },
    { heading: t('policies.care_notes_title'), body: '', items: [t('policies.care_note1'), t('policies.care_note2'), t('policies.care_note3')] },
    { heading: '', body: t('policies.care_quote'), items: [] },
  ] },
});

export const normalizePolicy = (policy) => ({
  title: policy?.title || '',
  sections: Array.isArray(policy?.sections) ? policy.sections.map((section) => ({
    heading: section?.heading || '', body: section?.body || '', items: Array.isArray(section?.items) ? section.items : [],
  })) : [],
});
