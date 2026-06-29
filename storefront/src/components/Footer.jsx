import { Link } from 'react-router-dom';
import { FaInstagram } from 'react-icons/fa';
import { useLanguage } from '../context/LanguageContext';
import Container from './ui/Container';

const Footer = () => {
  const { t } = useLanguage();

  return (
    <footer className="mt-24 bg-cocoa text-cream/80">
      {/* Dải thương hiệu lớn */}
      <Container className="pt-16 pb-10">
        <div className="flex flex-col gap-10 lg:flex-row lg:items-end lg:justify-between border-b border-cream/15 pb-12">
          <div>
            <Link
              to="/"
              className="font-sugo text-5xl md:text-6xl uppercase tracking-[0.08em] text-cream"
            >
              BROWN
            </Link>
            <p className="mt-4 max-w-sm text-sm leading-relaxed text-cream/60">
              {t('footer.desc') || 'Thời trang thiết kế, mộc mạc và bền vững — làm thủ công tại Việt Nam.'}
            </p>
          </div>
          <a
            href="https://instagram.com/brown.vn"
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-2 self-start rounded-full border border-cream/30 px-6 py-3 text-xs uppercase tracking-[0.2em] text-cream transition-colors hover:bg-cream hover:text-cocoa"
          >
            <FaInstagram /> Instagram
          </a>
        </div>

        {/* 3 cột thông tin */}
        <div className="grid grid-cols-1 gap-10 pt-12 text-sm md:grid-cols-3">
          <div>
            <h3 className="mb-4 font-heading text-base uppercase tracking-[0.18em] text-cream">
              {t('footer.about')}
            </h3>
            <p className="font-medium uppercase text-cream/80">Hộ Kinh Doanh BROWNVN</p>
            <p className="mt-1 text-xs text-cream/55">Mã số HKD: 089300017764</p>
            <p className="text-xs text-cream/55">Cấp ngày: 11/03/2026</p>
            <p className="text-xs text-cream/55">Nơi cấp: UBND Phường Tân Sơn Nhì</p>
          </div>

          <div>
            <h3 className="mb-4 font-heading text-base uppercase tracking-[0.18em] text-cream">
              {t('footer.contact')}
            </h3>
            <p className="text-cream/65">Hotline: 090.695.4860</p>
            <p className="text-cream/65">Email: brownvn25@gmail.com</p>
            <p className="text-cream/65">Hồ Chí Minh, Việt Nam</p>
          </div>

          <div>
            <h3 className="mb-4 font-heading text-base uppercase tracking-[0.18em] text-cream">
              {t('footer.support')}
            </h3>
            <nav className="flex flex-col gap-2 text-cream/65">
              <Link to="/policy/return" className="transition-colors hover:text-cream">
                {t('nav.return_policy')}
              </Link>
              <Link to="/policy/shipping" className="transition-colors hover:text-cream">
                {t('nav.shipping_policy')}
              </Link>
              <Link to="/policy/care" className="transition-colors hover:text-cream">
                {t('nav.care_guide')}
              </Link>
            </nav>
          </div>
        </div>
      </Container>

      <div className="border-t border-cream/15 py-6 text-center text-xs text-cream/50">
        © 2026 {t('footer.rights')}
      </div>
    </footer>
  );
};

export default Footer;
