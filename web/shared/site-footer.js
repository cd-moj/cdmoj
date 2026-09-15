// shared/site-footer.js — RODAPÉ comum (issue #20, 2026-09-15): versão do deploy, código-fonte,
// onde relatar problema, contato e a atribuição das bandeiras. Monta-se sozinho depois do
// <main> (ou em #siteFooter/footer.sitefoot, se a página já tiver o elemento) — páginas do site
// carregam este módulo direto; as de contest chamam mountSiteFooter() pelo contest-shell/chrome.
// A versão vem de /version.json, escrito pelo `make deploy` (gitignored; sem ele = "dev").
import { el } from '/shared/dom.js';
import { T } from '/shared/i18n.js';

const REPO = 'https://github.com/cd-moj/cdmoj';
let _info = null;
async function versionInfo() {
  if (_info) return _info;
  try { _info = await (await fetch('/version.json', { cache: 'no-cache' })).json(); } catch { _info = {}; }
  return _info;
}

function paint(foot, info) {
  foot.innerHTML = '';
  const version = (info && info.version) || 'dev';
  const contact = (info && info.contact) || '';
  const link = (href, txt) => el('a', { href, target: '_blank', rel: 'noopener' }, txt);
  const parts = [
    el('span', {}, 'MOJ ', el('code', { title: T('versão em produção (git)', 'deployed version (git)') }, version)),
    link(REPO, T('código-fonte', 'source code')),
    link(REPO + '/issues', T('relatar um problema', 'report an issue')),
  ];
  if (contact) parts.push(el('a', { href: /^https?:/.test(contact) ? contact : 'mailto:' + contact }, T('contato', 'contact')));
  const sep = () => el('span', { class: 'muted' }, '·');
  const inner = el('div', { class: 'container sitefoot-in' });
  parts.forEach((p, i) => { if (i) inner.append(sep()); inner.append(p); });
  inner.append(el('span', { class: 'sitefoot-credits' }, T('Bandeiras: ', 'Flags: '),
    link('https://github.com/lipis/flag-icons', 'flag-icons'), ' (MIT) · ',
    link('https://commons.wikimedia.org/', 'Wikimedia Commons')));
  foot.append(inner);
}

export async function mountSiteFooter() {
  let foot = document.getElementById('siteFooter') || document.querySelector('footer.sitefoot');
  if (!foot) {
    const main = document.querySelector('main'); if (!main) return null;
    foot = el('footer', { id: 'siteFooter', class: 'sitefoot' });
    main.after(foot);
  } else if (foot.dataset.mounted) return foot;
  foot.dataset.mounted = '1';
  const info = await versionInfo();
  paint(foot, info);
  document.addEventListener('moj:lang', () => paint(foot, info));
  return foot;
}
// páginas do site: carregar o módulo já monta; nas de contest quem chama é o shell
if (document.currentScript || !document.querySelector('#contestNav')) mountSiteFooter();
