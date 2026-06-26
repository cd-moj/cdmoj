// index/home.js — página inicial: notícias, contests, destaques do treino.
import { apiGet } from '/shared/api.js';
import { el, fmtDate, avatarEl, renderAuthArea } from '/shared/ui.js';
import { editorLabel } from '/shared/editors.js';
import { renderCreateContestLink } from '/shared/create-contest-link.js';
import { contestCard, relTime } from '/shared/contest-card.js';

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

// notícia LOCAL (sem url) abre o detalhe em /noticias/?id=<key>; externa aponta p/ fora
function newsHref(n) { return (n.is_local || !n.url) ? ('/noticias/?id=' + encodeURIComponent(n.key || n.id || '')) : n.url; }
function newsTarget(n) { return (n.is_local || !n.url) ? {} : { target: '_blank', rel: 'noopener' }; }

async function loadNews() {
  const fn = document.getElementById('featuredNews');
  let j;
  try { j = await apiGet('/index/news', {}); }
  catch { document.getElementById('news').classList.add('hidden'); if (fn) fn.innerHTML = '<div class="muted small">sem notícias</div>'; return; }
  const items = j.news || j.items || [];
  // destaque: a notícia mais recente, num card no topo (no lugar do hero gigante)
  if (fn) {
    fn.innerHTML = '';
    if (!items.length) fn.innerHTML = '<div class="muted small">sem notícias no momento</div>';
    else {
      const n = items[0];
      fn.append(
        el('span', { class: 'fn-tag' }, '📰 Em destaque'),
        el('a', { class: 'fn-title', href: newsHref(n), ...newsTarget(n) }, n.title || ''),
        el('span', { class: 'fn-date small muted' }, fmtDate(n.date)),
        el('div', { class: 'fn-sum' }, n.summary || ''),
        el('a', { class: 'small', href: '/noticias/', style: 'margin-top:.45rem; font-weight:600' }, 'ver todas as notícias →'));
    }
  }
  // demais notícias na seção de baixo (sem repetir a destacada)
  const rest = items.slice(1);
  const box = document.getElementById('newslist'); box.innerHTML = '';
  if (!rest.length) { box.innerHTML = '<span class="muted small">sem outras notícias — <a href="/noticias/">ver todas</a></span>'; return; }
  rest.forEach(n => box.append(el('div', { style: 'margin:.5rem 0' },
    el('div', {}, el('a', { href: newsHref(n), ...newsTarget(n), style: 'font-weight:700' }, n.title || ''),
      ' ', el('span', { class: 'small muted' }, fmtDate(n.date))),
    el('div', { class: 'small' }, n.summary || ''))));
  box.append(el('div', { style: 'margin-top:.6rem' }, el('a', { class: 'small', href: '/noticias/', style: 'font-weight:600' }, 'ver todas as notícias →')));
}

async function loadTraining() {
  let j; try { j = await apiGet('/index/open_training', {}); } catch { return; }
  const top = j.top_users || j.top10 || [];
  const recent = j.recent_solved || j.recent || [];
  const weekPrev = j.most_solved_prev_week || [];
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
  // mais resolvidos na semana passada (ranking de problemas)
  const wk = document.getElementById('weekprev');
  if (wk) {
    wk.innerHTML = '';
    if (!weekPrev.length) wk.innerHTML = '<span class="muted small">sem resolvidos na semana passada</span>';
    weekPrev.slice(0, 5).forEach((p, i) => {
      const pid = p.problem_id || p.id || '';
      wk.append(el('a', { class: 'week-row', href: p.url || ('/treino/problema/?id=' + encodeURIComponent(pid)) },
        el('span', { class: 'wk-rank' }, String(i + 1)),
        el('span', { class: 'wk-ttl' }, p.problem_title || p.title || pid),
        el('span', { class: 'rank-chip' }, (p.solved_count ?? 0) + ' ✓')));
    });
  }

  // editor mais usado na semana passada (web vs editor declarado), por % das aceitas
  const ed = j.most_used_editor_prev_week || { ranking: [], total: 0, top: null };
  const ew = document.getElementById('editorweek');
  if (ew) {
    ew.innerHTML = '';
    const rk = ed.ranking || [];
    if (!rk.length || !ed.total) ew.innerHTML = '<span class="muted small">sem dados ainda</span>';
    else rk.slice(0, 3).forEach((e, i) => {
      const pct = ed.total ? Math.round((e.count / ed.total) * 100) : 0;
      ew.append(el('div', { class: 'week-row' + (i === 0 ? ' editor-top' : '') },
        el('span', { class: 'wk-rank' }, String(i + 1)),
        el('span', { class: 'wk-ttl' }, editorLabel(e.editor)),
        el('span', { class: 'rank-chip' }, pct + '%')));
    });
  }

  // resolvidos recentemente (feed: problema + quem resolveu + quando)
  const rc = document.getElementById('recent'); rc.innerHTML = '';
  if (!recent.length) rc.innerHTML = '<span class="muted small">sem dados ainda</span>';
  recent.slice(0, 8).forEach((r) => {
    const pid = r.problem_id || r.id || '';
    const login = (r.user && (r.user.username || r.user.login)) || r.login || '';
    const who = (r.user && (r.user.name || r.user.username)) || r.login || '';
    const sub = el('span', { class: 'feed-sub' });
    if (login) sub.append(avatarEl(login, who, 18));
    sub.append(el('span', { class: 'feed-who' }, who || '—'));
    if (r.solved_at) sub.append(el('span', { class: 'feed-time' }, relTime(r.solved_at)));
    rc.append(el('a', { class: 'feed-item', href: r.url || ('/treino/problema/?id=' + encodeURIComponent(pid)) },
      el('span', { class: 'feed-ic' }, '✅'),
      el('span', { class: 'feed-body' },
        el('span', { class: 'feed-ttl' }, r.problem_title || r.title || pid), sub)));
  });
}

// "Gestão de Problemas" (seção #problemas + CTA do hero) só p/ logado + can_create
async function gateProblemManagement() {
  let can = false;
  try { can = !!(await apiGet('/treino/contest-create/permission', { contest: 'treino', auth: true })).can_create; }
  catch { /* sem permissão / sem login */ }
  document.querySelectorAll('#problemas, .gp-cta').forEach((n) => n.classList.toggle('hidden', !can));
}

// topbar: mesma sessão do treino livre (avatar/perfil/🛡 admin), inclusive na home.
// O #authArea é criado pelo header compartilhado (site-header.js); aqui só preenchemos.
const authMount = document.getElementById('authArea');
const refreshAuth = () => renderAuthArea(authMount, 'treino', refreshAuth)
  .then(() => renderCreateContestLink(authMount))
  .then(() => gateProblemManagement());
refreshAuth();

loadContests(); loadNews(); loadTraining();
