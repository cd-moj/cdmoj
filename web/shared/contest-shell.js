// shared/contest-shell.js — topbar + nav + auth comuns às telas internas do contest.
// As novas telas (log, tarefas, clarification, jplag) chamam initContestShell(contest).
import { apiGet } from '/shared/api.js';
import { status, logout } from '/shared/auth.js';
import { el } from '/shared/ui.js';

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
  const T = (pt, en) => (basic.locale === 'en' ? en : pt);
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
  const titleEl = document.getElementById('contestTitle');
  if (titleEl) titleEl.textContent = (basic && basic.contest_name) || 'Contest';
  document.title = ((basic && basic.contest_name) || 'Contest') + ' — MOJ';
  const back = document.getElementById('backBtn'); if (back) back.href = '/contest/?c=' + encodeURIComponent(contest);
  if (basic) startCountdown(basic);
  const st = await status(contest);
  const isAuth = !!st.logged_in;
  try {
    const nav = await apiGet('/contest/navbuttons?contest=' + encodeURIComponent(contest), { contest, auth: isAuth });
    renderNav(Array.isArray(nav) ? nav : (nav.buttons || []), contest);
  } catch { /* sem nav */ }
  return { basic, isAuth, st };
}
