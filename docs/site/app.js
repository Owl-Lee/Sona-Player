const screenshots = {
  home: {
    src: 'site/assets/screenshots/home.png',
    alt: 'Sona 首页真实截图',
    title: 'Sona · 首页',
  },
  library: {
    src: 'site/assets/screenshots/library.png',
    alt: 'Sona 本地曲库真实截图',
    title: 'Sona · 本地曲库',
  },
  settings: {
    src: 'site/assets/screenshots/settings.png',
    alt: 'Sona 设置页真实截图',
    title: 'Sona · 设置',
  },
};

const header = document.querySelector('[data-header]');
const showcaseImage = document.querySelector('[data-showcase-image]');
const showcaseTitle = document.querySelector('[data-shot-title]');
const tabs = [...document.querySelectorAll('[data-shot]')];

document.querySelector('[data-year]').textContent = new Date().getFullYear();

const updateHeader = () => header?.classList.toggle('scrolled', window.scrollY > 24);
updateHeader();
window.addEventListener('scroll', updateHeader, { passive: true });

const observer = new IntersectionObserver((entries) => {
  entries.forEach((entry) => {
    if (entry.isIntersecting) {
      entry.target.classList.add('visible');
      observer.unobserve(entry.target);
    }
  });
}, { threshold: 0.12 });

document.querySelectorAll('.reveal').forEach((element) => observer.observe(element));

tabs.forEach((tab) => {
  tab.addEventListener('click', () => {
    const next = screenshots[tab.dataset.shot];
    if (!next || tab.classList.contains('active')) return;

    tabs.forEach((item) => {
      const active = item === tab;
      item.classList.toggle('active', active);
      item.setAttribute('aria-selected', String(active));
    });

    showcaseImage.classList.add('switching');
    window.setTimeout(() => {
      showcaseImage.src = next.src;
      showcaseImage.alt = next.alt;
      showcaseTitle.textContent = next.title;
      showcaseImage.classList.remove('switching');
    }, 180);
  });
});
