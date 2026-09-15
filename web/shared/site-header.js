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
import { T, getLang } from '/shared/i18n.js';
import { mkLangToggle } from '/shared/lang-toggle.js';

const NAV = [
  { key: 'home',     href: '/',          pt: 'Início',       en: 'Home' },
  { key: 'treino',   href: '/treino/',   pt: 'Treino Livre', en: 'Free Training' },
  { key: 'contests', href: '/contests/', pt: 'Contests',     en: 'Contests' },
  { key: 'noticias', href: '/noticias/', pt: 'Notícias',     en: 'News' },
  { key: 'status',   href: '/status/',   pt: 'Status',       en: 'Status' },
  // Docs = o site de documentação (/docs/ serve o HTML renderizado de docs/html/ — manuais,
  // API, formato de pacote, gestão de orgs/coleções). A ajuda do ALUNO (como enviar: E/S,
  // extensões, templates) segue viva nos links contextuais (hero, página do problema, contest).
  { key: 'docs',     href: '/docs/',     pt: 'Docs',         en: 'Docs' },
];

// seletor pt/en: shared/lang-toggle.js (fonte única; aqui RECARREGA, porque os módulos leem LANG no import)

function activeFromPath() {
  const p = location.pathname;
  if (p === '/' || p === '/index.html') return 'home';
  if (p.startsWith('/treino/ajuda')) return 'ajuda';   // antes de /treino, senão acenderia "Treino Livre"
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
