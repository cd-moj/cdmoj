// shared/site-header.js — header ÚNICO do site principal (DRY).
// Substitui o conteúdo do <header class="topbar"> da página pelo MESMO topbar em todo
// lugar: brand + nav canônico (+ "Gestão de Problemas" só p/ quem pode criar/gerir) +
// um placeholder #authArea que a própria página preenche (renderAuthArea), preservando
// o onChange de cada página. Corrige a raiz da inconsistência (nav/brand/posição variavam).
//
// Uso: basta incluir, ANTES do <script> da página (módulos são deferred e rodam em ordem,
// então este cria #authArea antes do script da página):
//   <script type="module" src="/shared/site-header.js"></script>
// NÃO incluir nas páginas de contest (elas têm um topbar próprio).
import { el } from '/shared/ui.js';
import { apiGet } from '/shared/api.js';
import { T, getLang, setLang } from '/shared/i18n.js';

const NAV = [
  { key: 'home',     href: '/',          pt: 'Início',       en: 'Home' },
  { key: 'treino',   href: '/treino/',   pt: 'Treino Livre', en: 'Free Training' },
  { key: 'contests', href: '/contests/', pt: 'Contests',     en: 'Contests' },
  { key: 'noticias', href: '/noticias/', pt: 'Notícias',     en: 'News' },
  { key: 'status',   href: '/status/',   pt: 'Status',       en: 'Status' },
  { key: 'docs',     href: '/docs/',     pt: 'Documentação', en: 'Documentation', target: '_blank' },
];

// seletor pt/en (só aparece no header do site principal — nunca dentro de contest, que fixa
// o idioma pelo LOCALE). Escolha do usuário: persiste e vale em todo o site.
function mkLangToggle() {
  const wrap = el('span', { class: 'lang-toggle row', style: 'gap:.15rem', title: T('Idioma da interface', 'Interface language') });
  ['pt', 'en'].forEach((l) => {
    wrap.append(el('button', {
      class: 'btn ghost small' + (l === getLang() ? ' active' : ''),
      'aria-pressed': l === getLang() ? 'true' : 'false',
      onclick: () => { if (l !== getLang()) { setLang(l, { persist: true }); location.reload(); } },
    }, l.toUpperCase()));
  });
  return wrap;
}

function activeFromPath() {
  const p = location.pathname;
  if (p === '/' || p === '/index.html') return 'home';
  if (p.startsWith('/treino')) return 'treino';
  if (p.startsWith('/contests')) return 'contests';
  if (p.startsWith('/noticias')) return 'noticias';
  if (p.startsWith('/status')) return 'status';
  if (p.startsWith('/problemas')) return 'problemas';
  return '';
}

export function mountSiteHeader(opts = {}) {
  const host = opts.mount || document.getElementById('siteHeader') || document.querySelector('header.topbar');
  if (!host) return null;
  const active = opts.active || host.dataset.active || activeFromPath();
  host.classList.add('topbar');
  host.innerHTML = '';

  const bar = el('div', { class: 'bar' });
  const brand = el('a', { class: 'brand', href: '/' });
  brand.append(
    el('img', { src: '/shared/assets/logo_moj.svg', alt: 'MOJ' }),
    document.createTextNode(' MOJ '),
    el('span', { class: 'slogan' }, T('Melhor Online Judge', 'Best Online Judge')),
    document.createTextNode(' '),
    el('span', { class: 'badge-beta' }, 'BETA'),
  );
  bar.append(brand, el('div', { class: 'spacer' }));

  const nav = el('nav', { class: 'navlinks' });
  const mkLink = (n) => {
    const attrs = { href: n.href };
    if (n.target) attrs.target = n.target;
    const a = el('a', attrs, T(n.pt, n.en));
    if (n.key === active) a.classList.add('active');
    return a;
  };
  NAV.forEach((n) => nav.append(mkLink(n)));
  bar.append(nav);

  // seletor de idioma, entre o nav e a área de auth
  bar.append(mkLangToggle());

  // placeholder: a página preenche (chip do usuário / login), como hoje
  bar.append(el('span', { id: 'authArea', class: 'row', style: 'margin-left:.5rem' }));
  host.append(bar);

  // "Gestão de Problemas" só aparece para logado + can_create (mesma permissão de
  // "criar contest"). Inserido após o load da permissão, antes do "Status".
  apiGet('/treino/contest-create/permission', { contest: 'treino', auth: true })
    .then((p) => {
      if (!p || !p.can_create) return;
      const a = mkLink({ key: 'problemas', href: '/problemas/', pt: 'Gestão de Problemas', en: 'Problem Management' });
      const statusLink = [...nav.children].find((c) => c.getAttribute('href') === '/status/');
      nav.insertBefore(a, statusLink || null);
    })
    .catch(() => {});

  return { host, nav, active };
}

// auto-init: módulos rodam após o parse do DOM, então o <header> já existe.
mountSiteHeader();
