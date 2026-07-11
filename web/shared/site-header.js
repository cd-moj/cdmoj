// shared/site-header.js — header ÚNICO do site principal (DRY).
// Substitui o conteúdo do <header class="topbar"> da página pelo MESMO topbar em todo
// lugar: brand + nav canônico (só os links UNIVERSAIS) + seletor de idioma sutil + um
// placeholder #authArea que a página preenche (renderAuthArea monta o menu do usuário —
// perfil/admin/gestão de problemas/criar contest/sair). Corrige a inconsistência do topbar.
//
// Uso: basta incluir, ANTES do <script> da página (módulos são deferred e rodam em ordem,
// então este cria #authArea antes do script da página):
//   <script type="module" src="/shared/site-header.js"></script>
// NÃO incluir nas páginas de contest (elas têm um topbar próprio).
import { el } from '/shared/ui.js';
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
  const wrap = el('span', { class: 'lang-toggle', title: T('Idioma da interface', 'Interface language') });
  ['pt', 'en'].forEach((l) => {
    wrap.append(el('button', {
      class: 'lang-opt' + (l === getLang() ? ' active' : ''),
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

  return { host, nav, active };
}

// auto-init: módulos rodam após o parse do DOM, então o <header> já existe.
mountSiteHeader();
