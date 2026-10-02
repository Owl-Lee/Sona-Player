(()=>{
const reduce=matchMedia('(prefers-reduced-motion: reduce)').matches;
const $=s=>document.querySelector(s), $$=s=>[...document.querySelectorAll(s)];
const fmt=s=>{s=Math.max(0,Math.floor(s));return Math.floor(s/60)+':'+String(s%60).padStart(2,'0')};

/* ---------- i18n ---------- */
const EN={
  skip:'Skip to content',nav1:'Offline',nav2:'Features',nav3:'Interface',nav4:'Technology',nav5:'Download',nav5b:'Download',cta:'Download free',
  eyebrow:'Windows · Android · 0.5.0 public preview',h1:'Keep your music<br><span class="grad-text">in your own hands.</span>',
  lead:'Sona is a local-first music player that works offline. Music, music videos, the play queue, smart tidying and personal themes live together in one calm, easy space.',
  ctaHero:'Download free',ctaUI:'See the real app',p1b:'Local first',p1:'Plays without a connection',p2b:'Two platforms',p3b:'No subscription',p3:'Free during preview',
  winTitle:'Sona · Now playing',n1b:'Offline playback',n1:'Keeps going when the network drops',n2b:'Smart tidying',n2:'Finds song and artist names',hint:'Tap the record ↓',
  k1:'Why Sona',h2off:'A player shouldn’t go blank<br>when the Wi‑Fi does.',
  offP:'Sona is built around local files. Reliable playback comes first, and cloud sync is an extra rather than a requirement. Your library lives in a SQLite database on your device, so scanning, favorites, playlists and history all keep working offline.',
  statTxt:'of the local playback path runs without the cloud',online:'Online',offline:'Offline',network:'Network',artist:'Eason Chan · K歌之王 AIR',
  r1:'Local library · 11 songs',r2:'Queue and playlists',r3:'Favorites and history',r4:'Cloud sync',ok1:'Ready',ok2:'Ready',ok3:'Ready',synced:'Synced',later:'Syncs later',
  tryIt:'Try switching the network off.',offNote:'Network is off. The music keeps playing and everything local still works.',onNote:'Back online. Cloud sync picks up where it left off.',
  k2:'Features',h2feat:'Every essential,<br>carefully finished.',featP:'From importing a song to continuous playback, tidying, recognition, favorites, music videos and the full player, each step feels like part of one product rather than a pile of features.',
  f5tag:'Personal themes',f5h:'Change the mood, not just the color',f5p:'Liquid glass, a spinning record, accent-linked colors and wallpaper effects make a complete skin. Selection states, text contrast and controls adapt to every theme.',
  f1tag:'Local first',f1h:'Plays without a connection',f1p:'Your library, queue, playlists, favorites and history never depend on the network. If the cloud is unavailable, Sona tells you and keeps playing.',
  f2tag:'Audio + video',f2h:'Music and videos, one set of rules',f2p:'Sona detects the media type, links records to their videos and keeps the player in step as the queue moves on.',
  f3tag:'Smart metadata',f3h:'Give messy files their names back',f3p:'Media tags, filename cleanup, MusicBrainz and an optional Chromaprint / AcoustID fingerprint fallback work together to correct titles, artists and albums.',fl1:'Media tags',fl2:'Filename cleanup',
  f4tag:'Your library',f4h:'Favorites, playlists, recent plays and rankings',f4p:'A song behaves the same wherever you find it: same playback, same right‑click menu, same queue.',
  k3:'Real interface',h2ui:'Not a concept.<br>This is Sona today.',uiP:'These screenshots come straight from the Windows app. Lime Jelly is just one theme; the app has more wallpapers, colors and effects to choose from.',
  t1:'Player',t2:'Home',t3:'Library',t4:'Settings',c1:'Adaptive liquid glass',c2:'High‑contrast text',c3:'Full keyboard and mouse support',
  k4:'Technology',h2tech:'Design you can see,<br>engineering you can trust.',techP:'Flutter powers both platforms, SQLite stores your library locally and SHA‑256 removes duplicates. Network calls, cloud reads and rapid skipping are debounced, cancellable and fall back safely.',
  s2:'Local library database',s3:'Fingerprint dedupe',s4:'Open music database',src:'View the source code',pipeT:'Song recognition · example',replay:'Replay ↻',
  st1:'Read media tags',st2:'Clean the filename',st3:'Open music database',st4:'Audio fingerprint',fd1:'Title',fd2:'Artist',fd3:'Album',pipeHint:'Click a step, or let it run.',conf:'Confidence',
  k5:'Privacy',h2priv:'The cloud is an extra,<br>not a requirement.',pv1h:'Local database',pv1:'Your music files and core data stay on your device.',pv2h:'Optional recognition',pv2:'Sona only contacts public music databases when you ask it to identify songs.',pv3h:'Backup and restore',pv3:'Version 0.5.0 can export and restore your full Sona library and the files the app manages.',
  k6:'Get started',h2dl:'Bring your music<br><span class="grad-text">back to your own player.</span>',dlP:'Sona 0.5.0 public preview. No subscription; download and play.',
  for:'For',for2:'For',winMeta:'64‑bit installer · EXE',apkMeta:'Direct install · APK',dl1:'Download',dl2:'Download',portQ:'Prefer a portable build?',portA:'Download the Windows x64 portable ZIP ↗',
  notesT:'Read before installing',notes1:'Official builds use a permanent Android signature from 0.4.51 onward, so the 0.5.0 APK installs over 0.4.51 directly. If you installed the 0.4.50 development build or another signature, export a full backup and keep your media files, uninstall once, then install 0.5.0. Uninstalling removes Sona’s private database, settings and automatic snapshots, but not media in shared folders.',
  notes2:'The Windows installer is not Authenticode‑signed yet, so SmartScreen may show “Unknown publisher”. Only download from this page or GitHub Releases.',
  footTag:'A space for your music that is truly yours.',
  navLabel:'Page navigation',tabsLabel:'Interface screenshots',footLabel:'Footer',
  altPlayer:'Sona’s immersive record player in the Lime Jelly theme',alt0:'Immersive record player',alt1:'Home: library stats and recent plays',alt2:'Local library list',alt3:'Settings'
};
const ZH={online:'在线',offline:'离线',synced:'已同步',later:'稍后同步',tryIt:'试着关掉网络看看。',offNote:'网络已断开。音乐没停，本地的一切照常工作。',onNote:'网络已恢复，云端同步继续。',pipeHint:'点击步骤，或等它自动运行。'};
const CAPS={zh:['沉浸式黑胶播放页，唱片与液态玻璃控件随主题变化。','首页汇总曲库、收藏和已配对的 MV，最近播放一眼可见。','本地曲库支持搜索、筛选和批量管理，音频与视频一目了然。','设置按外观、账号、语言、存储和关于分组，层级清楚。'],
  en:['The immersive player: the record and liquid-glass controls follow your theme.','Home sums up your library, favorites and paired videos, with recent plays at a glance.','The local library supports search, filters and batch actions, with audio and video clearly marked.','Settings are grouped into appearance, account, language, storage and about.']};
const TITLES={zh:['Sona · 正在播放','Sona · 首页','Sona · 本地曲库','Sona · 设置'],en:['Sona · Now playing','Sona · Home','Sona · Library','Sona · Settings']};
$$('[data-i]').forEach(el=>{if(!(el.dataset.i in ZH))ZH[el.dataset.i]=el.innerHTML});
$$('[data-i-alt]').forEach(el=>ZH[el.dataset.iAlt]=el.alt);
$$('[data-i-aria]').forEach(el=>ZH[el.dataset.iAria]=el.getAttribute('aria-label'));
$$('img[data-en-src]').forEach(el=>el.dataset.zhSrc=el.getAttribute('src'));
let lang='zh';
const t=k=>(lang==='en'&&EN[k]!=null)?EN[k]:ZH[k];

/* ---------- reveal ---------- */
const io=new IntersectionObserver(es=>es.forEach(e=>{if(e.isIntersecting){e.target.classList.add('in');io.unobserve(e.target)}}),{rootMargin:'0px 0px -8% 0px'});
$$('[data-reveal]').forEach(el=>io.observe(el));

/* ---------- header ---------- */
const hdr=$('#hdr'), links=$$('.nav a'), secs=links.map(a=>$(a.getAttribute('href')));
function onScroll(){
  hdr.classList.toggle('scrolled',scrollY>10);
  let c=-1; secs.forEach((s,i)=>{if(s.getBoundingClientRect().top<innerHeight*.45)c=i});
  links.forEach((a,i)=>a.setAttribute('aria-current',i===c?'true':'false'));
}
addEventListener('scroll',onScroll,{passive:true}); onScroll();

/* ---------- record: slides out of the sleeve and spins; tap to pause ---------- */
const stage=$('#stage'), vinyl=$('#vinyl'), rb=$('#recordBtn');
let playing=!reduce, ang=0, spd=playing?1:0, last=performance.now();
function updateRecordLabel(){rb.setAttribute('aria-pressed',playing);rb.setAttribute('aria-label',lang==='en'?(playing?'Pause the record':'Play the record'):(playing?'暂停唱片':'播放唱片'))}
stage.classList.toggle('paused',!playing);
rb.addEventListener('click',()=>{playing=!playing;stage.classList.toggle('paused',!playing);updateRecordLabel()});
(function tick(now){
  const dt=Math.min(64,now-last);last=now;
  spd+=((playing?1:0)-spd)*.05; ang+=spd*dt*.2;
  vinyl.style.transform=`rotate(${ang}deg)`;
  requestAnimationFrame(tick);
})(last);

/* ---------- offline demo ---------- */
const sw=$('#netSw'), pl=$('#player');
let online=true, touched=false;
function syncNet(){
  sw.setAttribute('aria-checked',online); pl.classList.toggle('off',!online);
  $('#netTxt').textContent=t(online?'online':'offline');
  $('#cloudBadge').textContent=t(online?'synced':'later');
  $('#pNote').textContent=touched?t(online?'onNote':'offNote'):t('tryIt');
}
sw.addEventListener('click',()=>{online=!online;touched=true;syncNet()});
let ps=30; const pNow=$('#pNow'), pBar=$('#pBar');
const tickP=()=>{pNow.textContent=fmt(ps);pBar.style.width=(ps/281*100)+'%'}; tickP();
if(!reduce)setInterval(()=>{ps=ps>=281?0:ps+1;tickP()},1000);

/* ---------- interface tabs ---------- */
const tabs=$$('.seg [role=tab]'), shots=$$('#shot img'); let curTab=0;
function selTab(i,focus){
  curTab=i;
  tabs.forEach((b,j)=>{b.setAttribute('aria-selected',j===i);b.tabIndex=j===i?0:-1});
  shots.forEach((im,j)=>{im.classList.toggle('on',j===i);if(j===i)im.loading='eager'});
  $('#cap').textContent=CAPS[lang][i]; $('#frameTitle').textContent=TITLES[lang][i];
  if(focus)tabs[i].focus();
}
tabs.forEach((b,i)=>{
  b.addEventListener('click',()=>selTab(i));
  b.addEventListener('keydown',e=>{
    if(e.key==='ArrowRight'){e.preventDefault();selTab((i+1)%tabs.length,true)}
    if(e.key==='ArrowLeft'){e.preventDefault();selTab((i-1+tabs.length)%tabs.length,true)}
  });
});

/* ---------- metadata pipeline ---------- */
const S=[
  {t:['K歌之王air(day ver)','tag'],a:null,b:null,c:22,zh:'标签里只有一个不规范的标题，歌手和专辑都缺失。',en:'The tags only hold a messy title. Artist and album are missing.'},
  {t:['K歌之王 AIR (Day Version)','filename'],a:['chen yi xun','filename'],b:null,c:48,zh:'去掉序号与码率，从文件名里拆出歌手和规范标题。',en:'Track number and bitrate are stripped, and the artist is split out of the filename.'},
  {t:['K歌之王 AIR (Day Version)','MusicBrainz'],a:['陈奕迅','MusicBrainz'],b:['K歌之王 AIR','MusicBrainz'],c:86,zh:'查询公共音乐资料库，补齐规范名称与专辑。',en:'An open music database fills in the canonical names and the album.'},
  {t:['K歌之王 AIR (Day Version)','AcoustID'],a:['陈奕迅','AcoustID'],b:['K歌之王 AIR','AcoustID'],c:97,zh:'声纹比对确认结果。只在困难样本上启用，且完全可选。',en:'An audio fingerprint confirms the match. It only runs on hard cases and is fully optional.'}
];
const SRC={tag:{zh:'标签',en:'Tags'},filename:{zh:'文件名',en:'Filename'}};
const sb=$$('#steps button'), conf=$('#conf'), note=$('#stepNote');
let cur=-1, auto=null;
function go(i,quiet){
  cur=i; const s=S[i];
  sb.forEach((b,j)=>{b.classList.toggle('done',j<i);j===i?b.setAttribute('aria-current','step'):b.removeAttribute('aria-current')});
  ['t','a','b'].forEach(k=>{
    const dd=$(`dd[data-k="${k}"]`), sr=$(`[data-src="${k}"]`), v=s[k], nv=v?v[0]:'—';
    if(dd.textContent!==nv){dd.textContent=nv;if(!quiet&&v){dd.classList.remove('flash');void dd.offsetWidth;dd.classList.add('flash')}}
    dd.classList.toggle('empty',!v); sr.textContent=v?(SRC[v[1]]?SRC[v[1]][lang]:v[1]):'';
  });
  conf.style.width=s.c+'%'; note.textContent=s[lang];
}
function run(){clearInterval(auto);if(reduce){go(3);return}go(0);auto=setInterval(()=>{if(cur>=3){clearInterval(auto);return}go(cur+1)},2000)}
sb.forEach((b,i)=>b.addEventListener('click',()=>{clearInterval(auto);go(i)}));
$('#replay').addEventListener('click',run);
const pio=new IntersectionObserver(es=>{if(es[0].isIntersecting){pio.disconnect();run()}},{threshold:.45});
pio.observe($('#pipe'));

/* ---------- language ---------- */
function applyLang(l,save){
  lang=l==='en'?'en':'zh';
  document.documentElement.lang=lang==='en'?'en':'zh-CN';
  $$('[data-i]').forEach(el=>{const v=t(el.dataset.i);if(v!=null)el.innerHTML=v});
  $$('[data-i-alt]').forEach(el=>el.alt=t(el.dataset.iAlt));
  $$('[data-i-aria]').forEach(el=>el.setAttribute('aria-label',t(el.dataset.iAria)));
  $$('img[data-en-src]').forEach(el=>el.src=lang==='en'?el.dataset.enSrc:el.dataset.zhSrc);
  const b=$('#langBtn');b.textContent=lang==='en'?'中文':'EN';b.setAttribute('aria-label',lang==='en'?'切换到中文':'Switch to English');
  const meta=META[lang];
  document.title=meta.title;
  $('meta[name="description"]')?.setAttribute('content',meta.description);
  $('meta[property="og:title"]')?.setAttribute('content',meta.ogTitle);
  $('meta[property="og:description"]')?.setAttribute('content',meta.ogDescription);
  const canonical=lang==='zh'?'https://sona.yanbaoli.me/?lang=zh':'https://sona.yanbaoli.me/';
  $('link[rel="canonical"]')?.setAttribute('href',canonical);
  $('meta[property="og:url"]')?.setAttribute('content',canonical);
  syncNet(); selTab(curTab); updateRecordLabel();
  if(cur>=0)go(cur,true); else note.textContent=t('pipeHint');
  if(save){
    try{localStorage.setItem('sona-site-language',lang)}catch(e){}
    try{const u=new URL(location.href);if(lang==='zh')u.searchParams.set('lang','zh');else u.searchParams.delete('lang');history.replaceState(null,'',u)}catch(e){}
  }
}
const META={
  en:{title:'Sona — A local-first music player',description:'Sona is a local-first, offline-ready music player for Windows and Android with MVs, smart metadata, liquid-glass themes and sync foundations.',ogTitle:'Sona — Keep your music in your own hands',ogDescription:'Local-first and offline-ready, with music, MVs, smart organization and expressive themes.'},
  zh:{title:'Sona — 本地优先的音乐播放器',description:'Sona 是一款本地优先、离线可用的音乐播放器，支持 Windows 与 Android，带 MV、智能整理、液态玻璃主题和云同步。',ogTitle:'Sona — 把音乐留在自己手里',ogDescription:'本地优先、离线可用，音乐、MV、智能整理和个性化主题都在一起。'}
};
$('#langBtn').addEventListener('click',()=>applyLang(lang==='en'?'zh':'en',true));
// Same rule as the previous site: ?lang= wins, then the saved choice, otherwise English.
let initial='en';
try{
  const q=new URLSearchParams(location.search).get('lang');
  initial=(q==='en'||q==='zh')?q:(localStorage.getItem('sona-site-language')==='zh'?'zh':'en');
}catch(e){}
applyLang(initial,false);
})();
