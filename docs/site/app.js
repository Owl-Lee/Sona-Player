const screenshots = {
  home: {
    src: {
      zh: 'site/assets/screenshots/home.png',
      en: 'site/assets/screenshots/home-en.png',
    },
    zh: { alt: 'Sona 首页真实截图', title: 'Sona · 首页' },
    en: { alt: 'Real screenshot of the Sona home screen', title: 'Sona · Home' },
  },
  library: {
    src: {
      zh: 'site/assets/screenshots/library.png',
      en: 'site/assets/screenshots/library-en.png',
    },
    zh: { alt: 'Sona 本地曲库真实截图', title: 'Sona · 本地曲库' },
    en: { alt: 'Real screenshot of the Sona local library', title: 'Sona · Library' },
  },
  settings: {
    src: {
      zh: 'site/assets/screenshots/settings.png',
      en: 'site/assets/screenshots/settings-en.png',
    },
    zh: { alt: 'Sona 设置页真实截图', title: 'Sona · 设置' },
    en: { alt: 'Real screenshot of Sona settings', title: 'Sona · Settings' },
  },
};

const heroScreenshots = {
  zh: {
    src: 'site/assets/screenshots/player.png',
    alt: 'Sona 的沉浸式黑胶播放页，使用青柠软糖主题',
  },
  en: {
    src: 'site/assets/screenshots/player-en.png',
    alt: 'Sona immersive vinyl player in English using the Lime Candy theme',
  },
};

const translations = {
  '跳到正文': 'Skip to content',
  '亮点': 'Highlights',
  '界面': 'Gallery',
  '技术': 'Technology',
  '下载': 'Download',
  '立即体验': 'Try it now',
  'Windows · Android · 公开预览': 'Windows · Android · Public preview',
  '把音乐留在': 'Keep your music',
  '自己手里。': 'in your own hands.',
  'Sona 是一款本地优先、离线可用的音乐播放器。它把音乐、MV、播放队列、智能整理和个性化主题放进同一个安静、顺手的空间。': 'Sona is a local-first music player built to work offline. It brings music, MVs, queues, smart organization and expressive themes into one calm, effortless space.',
  '免费下载': 'Free download',
  '看看真实界面': 'See the real interface',
  '本地优先': 'Local-first',
  '无网也能听': 'Works offline',
  '双端': 'Two platforms',
  '不订阅': 'No subscription',
  '当前预览版免费': 'Free during public preview',
  'Sona · 正在播放': 'Sona · Now playing',
  '离线播放': 'Offline playback',
  '网络断开也不中断': 'Keeps playing without internet',
  '智能整理': 'Smart organization',
  '识别歌名与歌手': 'Identifies titles and artists',
  '为什么是 Sona': 'Why Sona',
  '播放器不该在断网时': 'A music player should not',
  '变成一块空白。': 'go blank when the internet does.',
  'Sona 从一开始就围绕本地文件设计：先让播放可靠，再把云同步当作增强，而不是依赖。你的音乐库保存在本机 SQLite 数据库中，扫描、收藏、歌单和播放记录都能在离线状态继续工作。': 'Sona is designed around local files from day one: reliable playback comes first, while cloud sync remains an enhancement rather than a dependency. Your library lives in a local SQLite database, so scanning, favorites, playlists and listening history keep working offline.',
  '本地播放路径不依赖云端': 'Local playback never depends on the cloud',
  '核心亮点': 'Core highlights',
  '该有的能力，': 'The features you need,',
  '每一项都认真打磨。': 'refined with care.',
  '从导入一首歌，到连续播放、整理、识别、收藏，再到 MV 与完整播放页，Sona 尽量让每一步都像一个完整产品，而不是功能拼盘。': 'From importing a track to continuous playback, organization, identification, favorites, MVs and the full player, every step is designed as part of one coherent product.',
  '无网照常播放': 'Playback that survives offline',
  '本地曲库、播放队列、歌单、收藏与记录不依赖网络。云端不可用时，应用会明确提示，但不会拖垮本地体验。': 'Your local library, queue, playlists, favorites and history do not depend on the network. When the cloud is unavailable, Sona tells you clearly without disrupting local playback.',
  '音乐和 MV 在同一套逻辑里': 'Music and MVs, one consistent system',
  '自动识别媒体类型、关联唱片与 MV，队列切歌时同步更新播放界面。': 'Sona detects media types, links records and MVs, and keeps the player interface in sync as the queue changes.',
  '让杂乱文件重新有名字': 'Turn messy files back into music',
  '结合标签、文件名清理、MusicBrainz，以及可选 Chromaprint / AcoustID 声纹回退，校准歌曲、歌手和专辑信息。': 'Media tags, filename cleanup, MusicBrainz and optional Chromaprint / AcoustID fingerprint fallback work together to refine track, artist and album metadata.',
  '收藏、歌单、最近播放与排行': 'Favorites, playlists, recents and charts',
  '同一首歌在不同入口保持一致的播放、右键与队列逻辑，快速找到真正想听的内容。': 'The same track keeps consistent playback, context-menu and queue behavior across every entry point, so the music you want is always easy to reach.',
  '不止换颜色，而是换一种听歌氛围': 'More than colors—a different listening mood',
  '液态毛玻璃、黑胶唱片、主题色联动与壁纸专属特效共同构成完整皮肤。选中态、文字对比度和控制器会随主题适配。': 'Liquid glass, vinyl playback, adaptive accent colors and wallpaper-specific effects form complete themes. Selection states, text contrast and controls adapt with them.',
  '真实界面': 'Real interface',
  '不是概念图。': 'Not a concept.',
  '就是现在的 Sona。': 'This is Sona today.',
  '以下画面直接采集自 Windows 版本。青柠软糖主题只是其中一种外观，应用内还可以切换多套壁纸、色彩与特效。': 'These screens come directly from the Windows build. Lime Candy is only one look—Sona includes multiple wallpapers, palettes and effects.',
  '首页': 'Home',
  '本地曲库': 'Library',
  '设置': 'Settings',
  '自适应液态玻璃': 'Adaptive liquid glass',
  '高对比文字': 'High-contrast text',
  '完整键鼠交互': 'Complete mouse and keyboard support',
  '简体 / 繁体 / English': 'Simplified / Traditional / English',
  '技术路径': 'Engineering',
  '看得见设计，': 'Design you can see,',
  '也看得见工程底座。': 'engineering you can trust.',
  'Sona 使用 Flutter 构建双端体验，以 SQLite 保存本地资料，通过 SHA-256 去重，并对网络、云端读取与连续切歌做了防抖、取消与失败回退。': 'Sona uses Flutter for a two-platform experience, SQLite for local data, SHA-256 for deduplication, and cancellation, debouncing and graceful fallback for network, cloud and rapid queue operations.',
  '查看公开源代码': 'View public source',
  '歌曲信息识别流程': 'Track metadata pipeline',
  '读取媒体标签': 'Read media tags',
  '最快、完全离线': 'Fastest and fully offline',
  '清理文件名': 'Clean filenames',
  '识别歌手与歌曲语义': 'Infer artist and title semantics',
  '公共音乐资料库': 'Public music databases',
  '补齐专辑与规范名称': 'Complete albums and canonical names',
  '可选音频声纹': 'Optional audio fingerprinting',
  'AcoustID 作为困难样本回退': 'AcoustID fallback for difficult files',
  '隐私与边界': 'Privacy and boundaries',
  '云端是增强，': 'Cloud is an enhancement,',
  '不是使用前提。': 'not a requirement.',
  '本地数据库': 'Local database',
  '音乐文件与核心资料保存在你的设备上。': 'Music files and core metadata stay on your device.',
  '可选识别服务': 'Optional identification services',
  '只有主动识别时才请求公开音乐资料服务。': 'Public music services are contacted only when you request identification.',
  '公开预览': 'Public preview',
  '同步能力仍在持续加强，重要音乐请保留本地备份。': 'Sync is still evolving; keep local backups of important music.',
  '开始使用': 'Get started',
  '现在，把自己的音乐': 'Now bring your music',
  '带回自己的播放器。': 'back to your own player.',
  'Sona 0.4.50 公开预览版。无需订阅，下载即用。': 'Sona 0.4.50 public preview. No subscription—download and listen.',
  '适用于': 'For',
  '64 位便携版 · ZIP': '64-bit portable · ZIP',
  '直接安装 · APK': 'Direct install · APK',
  '当前为公开预览版。Android APK 使用开发签名，系统可能提示“未知来源”；请只从本页面或 GitHub Release 下载。': 'This is a public preview. The Android APK uses a development signature, so your system may warn about an unknown source. Download only from this page or GitHub Releases.',
  '为自己的音乐，做一个真正属于自己的空间。': 'A space that truly belongs to you and your music.',
};

const attributeTranslations = {
  'Sona 首页': 'Sona home',
  '主导航': 'Main navigation',
  '产品特性摘要': 'Product highlights',
  'Sona 的沉浸式黑胶播放页，使用青柠软糖主题': 'Sona immersive vinyl player using the Lime Candy theme',
  '产品界面预览': 'Product interface preview',
  'Sona 首页真实截图': 'Real screenshot of the Sona home screen',
  '歌曲智能识别流程': 'Smart track identification pipeline',
};

const siteMetadata = {
  zh: {
    title: 'Sona — 本地优先的音乐播放器',
    description: 'Sona 是一款本地优先、离线可用的 Windows 与 Android 音乐播放器，支持 MV、智能元数据整理、液态玻璃主题与跨设备同步基础。',
    ogTitle: 'Sona — 把音乐留在自己手里',
    ogDescription: '本地优先、离线可用，兼顾音乐、MV、智能整理与个性化主题。',
  },
  en: {
    title: 'Sona — A local-first music player',
    description: 'Sona is a local-first, offline-ready music player for Windows and Android with MVs, smart metadata, liquid-glass themes and sync foundations.',
    ogTitle: 'Sona — Keep your music in your own hands',
    ogDescription: 'Local-first and offline-ready, with music, MVs, smart organization and expressive themes.',
  },
};

const header = document.querySelector('[data-header]');
const showcaseImage = document.querySelector('[data-showcase-image]');
const showcaseTitle = document.querySelector('[data-shot-title]');
const heroImage = document.querySelector('[data-hero-image]');
const tabs = [...document.querySelectorAll('[data-shot]')];
const languageToggle = document.querySelector('[data-language-toggle]');

const textNodes = [];
const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
let textNode;
while ((textNode = walker.nextNode())) {
  const original = textNode.nodeValue.trim();
  if (translations[original]) textNodes.push({ node: textNode, original });
}

const translatedAttributes = [];
document.querySelectorAll('[aria-label], [alt], [title]').forEach((element) => {
  ['aria-label', 'alt', 'title'].forEach((attribute) => {
    const original = element.getAttribute(attribute);
    if (original && attributeTranslations[original]) translatedAttributes.push({ element, attribute, original });
  });
});

const savedLanguage = (() => {
  const requested = new URLSearchParams(window.location.search).get('lang');
  if (requested === 'en' || requested === 'zh') return requested;
  try { return localStorage.getItem('sona-site-language'); } catch { return null; }
})();
let currentLanguage = savedLanguage === 'en' ? 'en' : 'zh';

const replaceText = (node, value) => {
  const leading = node.nodeValue.match(/^\s*/)?.[0] ?? '';
  const trailing = node.nodeValue.match(/\s*$/)?.[0] ?? '';
  node.nodeValue = `${leading}${value}${trailing}`;
};

const updateShowcaseLanguage = () => {
  const activeKey = tabs.find((tab) => tab.classList.contains('active'))?.dataset.shot || 'home';
  const shot = screenshots[activeKey];
  const copy = shot[currentLanguage];
  showcaseImage.src = shot.src[currentLanguage];
  showcaseImage.alt = copy.alt;
  showcaseTitle.textContent = copy.title;
};

const applyLanguage = (language, persist = true) => {
  currentLanguage = language === 'en' ? 'en' : 'zh';
  document.documentElement.lang = currentLanguage === 'en' ? 'en' : 'zh-CN';
  document.documentElement.dataset.language = currentLanguage;

  textNodes.forEach(({ node, original }) => replaceText(node, currentLanguage === 'en' ? translations[original] : original));
  translatedAttributes.forEach(({ element, attribute, original }) => {
    element.setAttribute(attribute, currentLanguage === 'en' ? attributeTranslations[original] : original);
  });

  const metadata = siteMetadata[currentLanguage];
  document.title = metadata.title;
  document.querySelector('meta[name="description"]')?.setAttribute('content', metadata.description);
  document.querySelector('meta[property="og:title"]')?.setAttribute('content', metadata.ogTitle);
  document.querySelector('meta[property="og:description"]')?.setAttribute('content', metadata.ogDescription);

  languageToggle.textContent = currentLanguage === 'en' ? '中文' : 'EN';
  languageToggle.setAttribute('aria-label', currentLanguage === 'en' ? '切换至中文' : 'Switch to English');
  languageToggle.title = currentLanguage === 'en' ? '切换至中文' : 'Switch to English';
  heroImage.src = heroScreenshots[currentLanguage].src;
  heroImage.alt = heroScreenshots[currentLanguage].alt;
  updateShowcaseLanguage();

  const url = new URL(window.location.href);
  if (currentLanguage === 'en') url.searchParams.set('lang', 'en');
  else url.searchParams.delete('lang');
  history.replaceState(null, '', `${url.pathname}${url.search}${url.hash}`);
  if (persist) {
    try { localStorage.setItem('sona-site-language', currentLanguage); } catch { /* preferences remain optional */ }
  }
};

document.querySelector('[data-year]').textContent = new Date().getFullYear();
languageToggle?.addEventListener('click', () => applyLanguage(currentLanguage === 'zh' ? 'en' : 'zh'));
applyLanguage(currentLanguage, false);

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
      showcaseImage.src = next.src[currentLanguage];
      showcaseImage.alt = next[currentLanguage].alt;
      showcaseTitle.textContent = next[currentLanguage].title;
      showcaseImage.classList.remove('switching');
    }, 180);
  });
});
