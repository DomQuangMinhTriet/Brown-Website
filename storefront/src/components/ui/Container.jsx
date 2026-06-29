// Container — bề ngang chuẩn cho mọi section storefront.
const Container = ({ children, className = '', as: Tag = 'div' }) => (
  <Tag className={`max-w-7xl mx-auto px-5 sm:px-6 lg:px-8 ${className}`}>
    {children}
  </Tag>
);

export default Container;
