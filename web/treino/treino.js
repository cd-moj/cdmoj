// treino/treino.js — busca de problemas do Treino Livre (tudo local após 1 fetch).
import { apiGet } from '/shared/api.js';
import { status } from '/shared/auth.js';
import { el, renderAuthArea } from '/shared/ui.js';
import { renderCreateContestLink } from '/shared/create-contest-link.js';
import { T } from '/shared/i18n.js';

const CONTEST = 'treino';
const PAGE = 50;
let ALL = [], solved = new Set(), attempted = new Set(), page = 0, showTags = false;

const norm = (s) => (s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
function difficulty(p) {
  const s = p.solved_count || 0, a = p.attempted_count || 0;
  if (a === 0) return { label: T('novo', 'new'), cls: '' };
  const rate = s / a;
  if (rate >= 0.9) return { label: T('muito fácil', 'very easy'), cls: 'diff-easy' };
  if (rate >= 0.7) return { label: T('fácil', 'easy'), cls: 'diff-easy' };
  if (rate >= 0.5) return { label: T('médio', 'medium'), cls: 'diff-med' };
  return { label: T('difícil', 'hard'), cls: 'diff-hard' };
}

function filtered() {
  const q = norm(document.getElementById('q').value);
  const col = norm(document.getElementById('qcol').value).replace(/^#/, '');
  const tag = norm(document.getElementById('qtag').value).replace(/^#/, '');
  const f = document.getElementById('filter').value;
  return ALL.filter(p => {
    if (q && !norm(p.title).includes(q)) return false;
    if (col && !(p.collections || []).some(c => norm(c).includes(col))) return false;
    if (tag && !(p.tags || []).some(t => norm(t).includes(tag))) return false;
    if (f === 'solved' && !solved.has(p.id)) return false;
    if (f === 'attempted' && !(attempted.has(p.id) && !solved.has(p.id))) return false;
    return true;
  });
}

// índice de coleções (client-side): rótulos distintos entre os problemas públicos, clicáveis p/ filtrar.
function renderCollIndex() {
  const box = document.getElementById('collIndex'); if (!box) return;
  const counts = new Map();
  ALL.forEach(p => (p.collections || []).forEach(c => counts.set(c, (counts.get(c) || 0) + 1)));
  const cur = (document.getElementById('qcol').value || '').trim();
  const names = [...counts.keys()].sort((a, b) => a.localeCompare(b, 'pt'));
  box.innerHTML = '';
  if (!names.length) { box.append(el('span', { class: 'muted' }, T('sem coleções.', 'no collections.'))); return; }
  names.forEach(n => box.append(el('a', {
    class: 'collection' + (cur === n ? ' on' : ''), href: '?searchcol=' + encodeURIComponent(n),
    style: 'margin:0 .4rem 0 0',
    onclick: (e) => { e.preventDefault(); document.getElementById('qcol').value = n; page = 0;
      history.replaceState(null, '', '?searchcol=' + encodeURIComponent(n)); render(); renderCollIndex(); }
  }, `${n} (${counts.get(n)})`)));
}
function render() {
  const rows = filtered();
  document.getElementById('count').textContent = `${rows.length} ${T('problema(s)', 'problem(s)')}`;
  const pages = Math.max(1, Math.ceil(rows.length / PAGE));
  if (page >= pages) page = 0;
  const slice = rows.slice(page * PAGE, page * PAGE + PAGE);

  const list = document.getElementById('list');
  list.innerHTML = '';
  const tbl = el('table', { class: 'moj' },
    el('thead', {}, el('tr', {},
      el('th', {}, T('Problema', 'Problem')),
      el('th', {}, T('Coleções', 'Collections')),
      ...(showTags ? [el('th', {}, T('Tags', 'Tags'))] : []),
      el('th', {}, T('Dificuldade (acertos)', 'Difficulty (solves)')),
      el('th', {}, T('Status', 'Status')))));
  const tb = el('tbody');
  slice.forEach(p => {
    const d = difficulty(p);
    const st = solved.has(p.id) ? T('✓ resolvido', '✓ solved') : (attempted.has(p.id) ? T('… tentado', '… attempted') : '');
    const cells = [
      el('td', {}, el('a', { href: '/treino/problema/?id=' + encodeURIComponent(p.id) }, p.title || p.id)),
      el('td', {}, (p.collections || []).map(c =>
        el('a', { class: 'collection', href: '?searchcol=' + encodeURIComponent(String(c)) }, c))),
    ];
    if (showTags) cells.push(el('td', {}, (p.tags || []).map(t =>
      el('a', { class: 'tag', href: '?searchtag=' + encodeURIComponent(String(t).replace(/^#/, '')) }, t))));
    cells.push(el('td', {}, el('span', { class: 'diff ' + d.cls },
      d.label + (p.attempted_count ? ` (${p.solved_count}/${p.attempted_count})` : ''))));
    cells.push(el('td', { class: solved.has(p.id) ? 'v-ok' : '' }, st));
    tb.append(el('tr', {}, ...cells));
  });
  tbl.append(tb); list.append(tbl);

  const pager = document.getElementById('pager'); pager.innerHTML = '';
  if (pages > 1) {
    pager.append(el('button', { class: 'btn ghost', onclick: () => { if (page > 0) { page--; render(); } } }, '‹'));
    pager.append(el('span', { class: 'small' }, ` ${T('página', 'page')} ${page + 1} / ${pages} `));
    pager.append(el('button', { class: 'btn ghost', onclick: () => { if (page < pages - 1) { page++; render(); } } }, '›'));
  }
}

async function loadSolve() {
  const st = await status(CONTEST);
  const fsel = document.getElementById('filter');
  fsel.disabled = !st.logged_in;
  if (!st.logged_in) return;
  try {
    const j = await apiGet('/treino/solvetry', { contest: CONTEST, auth: true });
    solved = new Set(j.solved || []); attempted = new Set(j.attempted || []);
  } catch {}
}

async function boot() {
  const authArea = document.getElementById('authArea');
  await renderAuthArea(authArea, CONTEST, async () => { await loadSolve(); render(); await renderCreateContestLink(authArea); });
  renderCreateContestLink(authArea);
  const sp = new URLSearchParams(location.search);
  if (sp.get('searchtag')) document.getElementById('qtag').value = sp.get('searchtag');
  if (sp.get('searchcol')) document.getElementById('qcol').value = sp.get('searchcol');

  try {
    const j = await apiGet('/treino/problems', { contest: CONTEST });
    ALL = Array.isArray(j) ? j : (j.problems || j.data || []);
  } catch (e) {
    document.getElementById('list').innerHTML = `<span class="error-box">${T('Falha ao carregar problemas.', 'Failed to load problems.')}</span>`;
    return;
  }
  await loadSolve();
  ['q', 'qcol', 'qtag', 'filter'].forEach(id =>
    document.getElementById(id).addEventListener('input', () => { page = 0; render(); }));
  document.getElementById('toggleTags').addEventListener('click', () => {
    showTags = !showTags;
    document.getElementById('toggleTags').textContent = showTags ? T('Ocultar tags', 'Hide tags') : T('Mostrar tags', 'Show tags');
    render();
  });
  renderCollIndex();
  render();
}
boot();
