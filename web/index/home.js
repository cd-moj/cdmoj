// index/home.js — página inicial: notícias, contests, destaques do treino.
import { apiGet } from '/shared/api.js';
import { el, fmtDate, avatarEl, renderAuthArea } from '/shared/ui.js';
import { editorLabel } from '/shared/editors.js';
import { renderCreateContestLink } from '/shared/create-contest-link.js';
import { contestCard } from '/shared/contest-card.js';

const norm = (s) => (s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
let openAll = [], upAll = [], closedAll = [], closedPage = 0, closedTotal = 0; const CPAGE = 12;

function fillGroup(boxId, countId, arr, status) {
  document.getElementById(countId).textContent = arr.length;
  const box = document.getElementById(boxId); box.innerHTML = '';
  if (!arr.length) { box.innerHTML = '<div class="muted small" style="padding:.35rem .2rem">nenhum no momento</div>'; return; }
  arr.forEach((c) => box.append(contestCard(c, status)));
}

function renderContests() {
  const f = norm(document.getElementById('cfilter').value);
  const m = (c) => !f || norm(c.title || c.name || c.id).includes(f);
  fillGroup('c-open', 'n-open', openAll.filter(m), 'open');
  fillGroup('c-upcoming', 'n-upcoming', upAll.filter(m), 'upcoming');

  const closed = closedAll.filter(m);
  // o badge mostra o TOTAL real de encerrados (a home só carrega os 20 mais recentes)
  document.getElementById('n-closed').textContent = (!f && closedTotal) ? closedTotal : closed.length;
  const pages = Math.max(1, Math.ceil(closed.length / CPAGE));
  if (closedPage >= pages) closedPage = 0;
  const cl = document.getElementById('c-closed'); cl.innerHTML = '';
  if (!closed.length) cl.innerHTML = '<div class="muted small" style="padding:.35rem .2rem">nenhum</div>';
  closed.slice(closedPage * CPAGE, closedPage * CPAGE + CPAGE).forEach((c) => cl.append(contestCard(c, 'closed')));
  const pg = document.getElementById('c-pager'); pg.innerHTML = '';
  if (pages > 1) {
    pg.append(
      el('button', { class: 'btn ghost', onclick: () => { if (closedPage > 0) { closedPage--; renderContests(); } } }, '‹ anterior'),
      el('span', { class: 'small muted' }, ` página ${closedPage + 1} de ${pages} `),
      el('button', { class: 'btn ghost', onclick: () => { if (closedPage < pages - 1) { closedPage++; renderContests(); } } }, 'próxima ›'));
  }
  // a home traz só os mais recentes — link p/ o arquivo completo dos encerrados
  if (closedTotal > closedAll.length) {
    pg.append(el('a', { class: 'btn ghost', href: '/contests/', style: 'margin-left:.4rem' },
      `ver todos os ${closedTotal} encerrados →`));
  }
}

async function loadContests() {
  let j;
  try { j = await apiGet('/index/contests', {}); } catch { document.getElementById('contests').classList.add('hidden'); return; }
  openAll = j.open || []; upAll = j.upcoming || [];
  closedAll = (j.closed && j.closed.items) || (Array.isArray(j.closed) ? j.closed : []);
  closedTotal = (j.closed && j.closed.total) || closedAll.length;
  document.getElementById('cfilter').addEventListener('input', () => { closedPage = 0; renderContests(); });
  renderContests();
}

async function loadNews() {
  let j; try { j = await apiGet('/index/news', {}); } catch { document.getElementById('news').classList.add('hidden'); return; }
  const items = j.items || j.news || [];
  const box = document.getElementById('newslist'); box.innerHTML = '';
  if (!items.length) { box.innerHTML = '<span class="muted small">sem notícias</span>'; return; }
  items.forEach(n => box.append(el('div', { style: 'margin:.5rem 0' },
    el('div', {}, el('a', { href: n.url || '#', style: 'font-weight:700' }, n.title || ''),
      ' ', el('span', { class: 'small muted' }, fmtDate(n.date))),
    el('div', { class: 'small' }, n.summary || ''))));
}

async function loadTraining() {
  let j; try { j = await apiGet('/index/open_training', {}); } catch { return; }
  const top = j.top_users || j.top10 || [];
  const recent = j.recent_solved || j.recent || [];
  const t10 = document.getElementById('top10'); t10.innerHTML = '';
  if (!top.length) t10.innerHTML = '<span class="muted small">sem dados ainda</span>';
  top.slice(0, 10).forEach((u, i) => {
    const login = u.username || u.login || u.user || '';
    const nameWrap = el('span', { class: 'rank-name' }, el('span', { class: 'rn-name' }, u.name || login));
    if (u.favorite_editor) nameWrap.append(el('span', { class: 'ed-tag' }, '⌨ ' + editorLabel(u.favorite_editor)));
    t10.append(el('a', { class: 'rank-row r' + (i + 1), href: '/treino/stat/?user=' + encodeURIComponent(login) },
      el('span', { class: 'rank-num' }, String(i + 1)),
      avatarEl(login, u.name, 30),
      nameWrap,
      el('span', { class: 'rank-chip' }, (u.solved_count ?? u.solved ?? u.count ?? 0) + ' ✓')));
  });
  const rc = document.getElementById('recent'); rc.innerHTML = '';
  if (!recent.length) rc.innerHTML = '<span class="muted small">sem dados ainda</span>';
  recent.slice(0, 8).forEach((r) => {
    const pid = r.problem_id || r.id || '';
    const who = (r.user && (r.user.name || r.user.username)) || r.login || '';
    rc.append(el('a', { class: 'recent-row', href: '/treino/problema/?id=' + encodeURIComponent(pid) },
      el('span', { class: 'ttl' }, r.problem_title || r.title || pid),
      el('span', { class: 'who' }, who ? ('por ' + who) : '')));
  });
}

// topbar: mesma sessão do treino livre (avatar/perfil/🛡 admin), inclusive na home
const authMount = document.getElementById('authArea');
const refreshAuth = () => renderAuthArea(authMount, 'treino', refreshAuth)
  .then(() => renderCreateContestLink(authMount));
refreshAuth();

loadContests(); loadNews(); loadTraining();
