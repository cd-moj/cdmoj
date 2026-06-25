// lib/contest-chrome.js — cabeçalho comum das páginas internas do contest
// (título, countdown até o fim, quicknav por papel, logout). Build-free.
import { apiGet } from '/shared/api.js';
import { logout, status } from '/shared/auth.js';
import { el } from '/shared/ui.js';
import { mountContestUserChip } from '/shared/contest-shell.js';

function fmtLeft(sec) {
  if (sec < 0) sec = 0;
  const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
  const p = (x) => String(x).padStart(2, '0');
  return h > 0 ? `${p(h)}:${p(m)}:${p(s)}` : `${p(m)}:${p(s)}`;
}

function navHref(contest, url) {
  const c = encodeURIComponent(contest);
  const map = {
    '/': `/contest/?c=${c}`, '/score': `/contest/score/?c=${c}`,
    '/all_submissions': `/contest/allsubmissions/?c=${c}`, '/stats': `/contest/statistics/?c=${c}`,
    '/pending': `/contest/judge/?c=${c}`, '/logout': '#logout',
  };
  if (map[url]) return map[url];
  return url + (url.includes('?') ? '&' : '?') + 'c=' + c;
}

// Monta título + countdown + nav. Espera elementos com ids:
//   #contestTitle, #contestCountdown, #contestNav, #backBtn (opcional)
// Retorna {locale}.
export async function mountChrome(contest, basic, { auth = true } = {}) {
  const locale = basic.locale || 'pt';
  const T = (pt, en) => (locale === 'en' ? en : pt);
  document.title = (basic.contest_name || 'Contest') + ' — MOJ';
  const titleEl = document.getElementById('contestTitle');
  if (titleEl) titleEl.textContent = basic.contest_name || 'Contest';
  const back = document.getElementById('backBtn');
  if (back) back.href = '/contest/?c=' + encodeURIComponent(contest);

  // countdown
  const cdEl = document.getElementById('contestCountdown');
  if (cdEl) {
    const tick = () => {
      const left = (basic.end_time || 0) - Math.floor(Date.now() / 1000);
      if (left > 0) { cdEl.textContent = T('Termina em: ', 'Ends in: ') + fmtLeft(left); setTimeout(tick, 1000); }
      else cdEl.textContent = T('Competição encerrada', 'Contest ended');
    };
    tick();
  }

  // chip do usuário do contest no topbar (consistência com o site principal)
  try { mountContestUserChip(await status(contest)); } catch { /* sem chip */ }

  // nav
  const navEl = document.getElementById('contestNav');
  if (navEl) {
    let buttons = [];
    try {
      const nav = await apiGet('/contest/navbuttons?contest=' + encodeURIComponent(contest), { contest, auth });
      buttons = Array.isArray(nav) ? nav : (nav.buttons || []);
    } catch {}
    navEl.innerHTML = '';
    const here = location.pathname.replace(/\/+$/, '');
    buttons.forEach(b => {
      const href = navHref(contest, b.url);
      if (href === '#logout') {
        navEl.append(el('a', { href: '#', onclick: async (e) => { e.preventDefault(); await logout(contest); location.href = '/contest/?c=' + encodeURIComponent(contest); } }, b.label));
        return;
      }
      const active = href.split('?')[0].replace(/\/+$/, '') === here;
      navEl.append(el('a', { href, class: active ? 'active' : '' }, b.label));
    });
  }
  return { locale, T };
}

export { fmtLeft, navHref };
