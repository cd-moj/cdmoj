// contest/statistics/statistics.js — estatísticas ricas do contest (admin/judge/mon).
// Usa /contest/statistics (agregado no servidor): totais, por problema, por linguagem,
// veredictos e linha do tempo. Gráficos SVG via /lib/charts.js.
import { apiGet } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { mountChrome } from '/lib/contest-chrome.js';
import { barChart, pieChart } from '/lib/charts.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const enc = encodeURIComponent;
let probMap = {};
const shortOf = (pid) => probMap[pid] || pid;
const pct = (x) => Math.round((x || 0) * 100) + '%';

function totalsCards(t) {
  const card = (big, sub) => el('div', { class: 'stat-card' }, el('div', { class: 'big-num' }, String(big)), el('div', { class: 'big-sub' }, sub));
  return el('div', { class: 'stat-cards' },
    card(t.submissions || 0, 'submissões'), card(t.accepted || 0, 'aceitas'),
    card(t.users || 0, 'participantes ativos'), card(t.problems_solved || 0, 'problemas resolvidos'));
}

function problemsTable(ps) {
  const tb = el('tbody');
  ps.forEach((p) => tb.append(el('tr', {},
    el('td', {}, el('b', {}, shortOf(p.problem_id)), el('div', { class: 'small muted' }, p.problem_id)),
    el('td', { class: 'n' }, String(p.submissions)),
    el('td', { class: 'n' }, String(p.attempted)),
    el('td', { class: 'n' }, String(p.solved)),
    el('td', { class: 'n' }, pct(p.accept_rate)),
    el('td', {}, p.first_solver ? (p.first_solver + ' · ' + p.first_minute + 'min') : '—'))));
  return el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
    el('thead', {}, el('tr', {}, el('th', {}, 'Problema'), el('th', {}, 'Subs'), el('th', {}, 'Tentaram'),
      el('th', {}, 'Resolveram'), el('th', {}, 'Taxa'), el('th', {}, '1º a resolver'))), tb));
}

function langTable(ls) {
  const tb = el('tbody');
  ls.forEach((l) => tb.append(el('tr', {},
    el('td', {}, l.lang), el('td', { class: 'n' }, String(l.submissions)),
    el('td', { class: 'n' }, String(l.accepted)), el('td', { class: 'n' }, String(l.solvers)))));
  return el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
    el('thead', {}, el('tr', {}, el('th', {}, 'Linguagem'), el('th', {}, 'Subs'), el('th', {}, 'Aceitas'), el('th', {}, 'Resolvedores'))), tb));
}

function render(s) {
  app.innerHTML = '';
  app.append(totalsCards(s.totals || {}));

  app.append(el('div', { class: 'section' }, el('h2', {}, 'Por problema'),
    problemsTable(s.problems || []),
    el('div', { class: 'two-col', style: 'margin-top:1rem' },
      el('div', {}, el('div', { class: 'chart-title' }, 'Submissões por problema'),
        barChart((s.problems || []).map((p) => ({ label: shortOf(p.problem_id), value: p.submissions })), { rotateLabels: true })),
      el('div', {}, el('div', { class: 'chart-title' }, 'Resolvedores por problema'),
        barChart((s.problems || []).map((p) => ({ label: shortOf(p.problem_id), value: p.solved })), { rotateLabels: true })))));

  app.append(el('div', { class: 'section' }, el('h2', {}, 'Veredictos e linguagens'),
    el('div', { class: 'two-col' },
      el('div', {}, el('div', { class: 'chart-title' }, 'Distribuição de veredictos'),
        pieChart((s.verdicts || []).map((v) => ({ label: v.verdict, value: v.count })))),
      el('div', {}, el('div', { class: 'chart-title' }, 'Linguagens'), langTable(s.languages || [])))));

  if ((s.timeline || []).length) {
    app.append(el('div', { class: 'section' }, el('h2', {}, 'Linha do tempo'),
      el('div', { class: 'chart-title' }, 'Submissões ao longo do tempo (por 10 min)'),
      barChart(s.timeline.map((t) => ({ label: t.minute + 'm', value: t.submissions })), { rotateLabels: true }),
      el('div', { class: 'chart-title', style: 'margin-top:.6rem' }, 'Aceitas ao longo do tempo'),
      barChart(s.timeline.map((t) => ({ label: t.minute + 'm', value: t.accepted })), { rotateLabels: true })));
  }
}

async function boot() {
  if (!CONTEST) { app.innerHTML = '<div class="error-box">Contest não informado.</div>'; return; }
  let basic = null;
  try { basic = await apiGet('/contest/basic?contest=' + enc(CONTEST), {}); } catch { /* segue */ }
  try { await mountChrome(CONTEST, basic); } catch { /* nav opcional */ }
  let s;
  try { s = await apiGet('/contest/statistics?contest=' + enc(CONTEST), { contest: CONTEST, auth: true }); }
  catch (e) {
    app.innerHTML = '';
    app.append(el('div', { class: 'section' }, el('h2', {}, '🔒 Restrito'),
      el('p', { class: 'muted' }, 'Estatísticas são visíveis a admin, juiz ou monitor do contest. (' + (e.message || 'erro') + ')')));
    return;
  }
  try { const pr = await apiGet('/contest/problems?contest=' + enc(CONTEST), { contest: CONTEST, auth: true }); (pr.problems || []).forEach((p) => { probMap[p.problem_id] = p.short_name; }); } catch { /* sem map */ }
  render(s);
}
boot();
