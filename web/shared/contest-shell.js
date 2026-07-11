// shared/contest-shell.js — topbar + nav + auth comuns às telas internas do contest.
// As novas telas (log, tarefas, clarification, jplag) chamam initContestShell(contest).
import { apiGet } from '/shared/api.js';
import { status, logout } from '/shared/auth.js';
import { el, avatarEl } from '/shared/ui.js';
import { T, setLang } from '/shared/i18n.js';

// chip do usuário logado do contest no topbar (avatar + nome) — consistência com o
// site principal. Inserido à esquerda do botão "Contest"/countdown; idempotente.
export function mountContestUserChip(st) {
  if (!st || !st.logged_in) return;
  if (document.getElementById('contestUserChip')) return;
  const anchor = document.getElementById('backBtn') || document.getElementById('contestCountdown');
  if (!anchor || !anchor.parentNode) return;
  anchor.parentNode.insertBefore(
    el('span', { id: 'contestUserChip', class: 'user-chip small', style: 'margin-right:.3rem', title: st.login },
      avatarEl(st.login, st.name, 22), el('span', {}, st.name || st.login)),
    anchor);
}

// resolve o url do botão de nav -> caminho absoluto com ?c=. Botões já vêm em
// caminhos completos (/contest/...); '/' e '/logout' são especiais.
export function navHref(url, contest) {
  const c = encodeURIComponent(contest);
  if (url === '/') return `/contest/?c=${c}`;
  if (url === '/logout') return '#logout';
  return url + (url.includes('?') ? '&' : '?') + 'c=' + c;
}

function startCountdown(basic) {
  const eln = document.getElementById('contestCountdown'); if (!eln) return;
  const fmt = (s) => { if (s < 0) s = 0; const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), x = s % 60, p = (n) => String(n).padStart(2, '0'); return h > 0 ? `${p(h)}:${p(m)}:${p(x)}` : `${p(m)}:${p(x)}`; };
  const tick = () => { const left = (basic.end_time || 0) - Math.floor(Date.now() / 1000); if (left > 0) { eln.textContent = T('Termina em: ', 'Ends in: ') + fmt(left); setTimeout(tick, 1000); } else eln.textContent = T('Competição encerrada', 'Contest ended'); };
  tick();
}

function renderNav(buttons, contest) {
  const nav = document.getElementById('contestNav'); if (!nav) return; nav.innerHTML = '';
  const here = location.pathname.replace(/\/+$/, '');
  buttons.forEach((b) => {
    const href = navHref(b.url, contest);
    if (href === '#logout') { nav.append(el('a', { href: '#', onclick: async (e) => { e.preventDefault(); await logout(contest); location.href = '/contest/?c=' + encodeURIComponent(contest); } }, b.label)); return; }
    const active = href.split('?')[0].replace(/\/+$/, '') === here;
    nav.append(el('a', { href, class: active ? 'active' : '' }, b.label));
  });
}

// initContestShell(contest) -> {basic, isAuth, st}. Preenche título, countdown, nav.
export async function initContestShell(contest) {
  let basic = null;
  try { basic = await apiGet('/contest/basic?contest=' + encodeURIComponent(contest), {}); } catch { /* segue */ }
  if (basic && basic.locale) setLang(basic.locale, { persist: false });  // LOCALE do contest impõe o idioma
  const titleEl = document.getElementById('contestTitle');
  if (titleEl) titleEl.textContent = (basic && basic.contest_name) || 'Contest';
  document.title = ((basic && basic.contest_name) || 'Contest') + ' — MOJ';
  const back = document.getElementById('backBtn'); if (back) back.href = '/contest/?c=' + encodeURIComponent(contest);
  if (basic) startCountdown(basic);
  const st = await status(contest);
  const isAuth = !!st.logged_in;
  mountContestUserChip(st);
  try {
    const nav = await apiGet('/contest/navbuttons?contest=' + encodeURIComponent(contest), { contest, auth: isAuth });
    renderNav(Array.isArray(nav) ? nav : (nav.buttons || []), contest);
  } catch { /* sem nav */ }
  return { basic, isAuth, st };
}
