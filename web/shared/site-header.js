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

const NAV = [
  { key: 'home',     href: '/',          label: 'Início' },
  { key: 'treino',   href: '/treino/',   label: 'Treino Livre' },
  { key: 'contests', href: '/contests/', label: 'Contests' },
  { key: 'status',   href: '/status/',   label: 'Status' },
  { key: 'docs',     href: '/docs/',     label: 'Documentação', target: '_blank' },
];

function activeFromPath() {
  const p = location.pathname;
  if (p === '/' || p === '/index.html') return 'home';
  if (p.startsWith('/treino')) return 'treino';
  if (p.startsWith('/contests')) return 'contests';
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
    el('span', { class: 'slogan' }, 'Melhor Online Judge'),
    document.createTextNode(' '),
    el('span', { class: 'badge-beta' }, 'BETA'),
  );
  bar.append(brand, el('div', { class: 'spacer' }));

  const nav = el('nav', { class: 'navlinks' });
  const mkLink = (n) => {
    const attrs = { href: n.href };
    if (n.target) attrs.target = n.target;
    const a = el('a', attrs, n.label);
    if (n.key === active) a.classList.add('active');
    return a;
  };
  NAV.forEach((n) => nav.append(mkLink(n)));
  bar.append(nav);

  // placeholder: a página preenche (chip do usuário / login), como hoje
  bar.append(el('span', { id: 'authArea', class: 'row', style: 'margin-left:.5rem' }));
  host.append(bar);

  // "Gestão de Problemas" só aparece para logado + can_create (mesma permissão de
  // "criar contest"). Inserido após o load da permissão, antes do "Status".
  apiGet('/treino/contest-create/permission', { contest: 'treino', auth: true })
    .then((p) => {
      if (!p || !p.can_create) return;
      const a = mkLink({ key: 'problemas', href: '/problemas/', label: 'Gestão de Problemas' });
      const statusLink = [...nav.children].find((c) => c.getAttribute('href') === '/status/');
      nav.insertBefore(a, statusLink || null);
    })
    .catch(() => {});

  return { host, nav, active };
}

// auto-init: módulos rodam após o parse do DOM, então o <header> já existe.
mountSiteHeader();
