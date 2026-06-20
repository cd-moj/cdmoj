// contest/statistics/statistics.js — estatísticas ricas do contest (admin/judge/mon).
// Usa /contest/statistics (agregado no servidor): totais, por problema, por linguagem,
// veredictos e linha do tempo. Gráficos SVG via /lib/charts.js.
import { apiGet } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { mountChrome } from '/lib/contest-chrome.js';
import { barChart, lineChart, hBarChart } from '/lib/charts.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const enc = encodeURIComponent;
let probMap = {};
const shortOf = (pid) => probMap[pid] || pid;
const pct = (x) => Math.round((x || 0) * 100) + '%';

function expandSolves(dist) { const a = []; (dist || []).forEach((d) => { for (let i = 0; i < d.users; i++) a.push(d.solved); }); return a; }
function quartiles(arr) {
  if (!arr.length) return null;
  const s = arr.slice().sort((a, b) => b - a), at = (p) => s[Math.min(s.length - 1, Math.floor(p * s.length))];
  return { top25: at(0.25), median: at(0.5), bottom25: at(0.75), max: s[0], min: s[s.length - 1], n: s.length };
}
function highlights(s) {
  const ps = s.problems || [], ls = s.languages || [], items = [];
  const mostSolved = ps.slice().sort((a, b) => b.solved - a.solved)[0];
  const hardest = ps.filter((p) => p.attempted > 0).slice().sort((a, b) => a.accept_rate - b.accept_rate)[0];
  if (mostSolved) items.push('🏆 Mais resolvido: ' + shortOf(mostSolved.problem_id) + ' (' + mostSolved.solved + ' resolveram)');
  if (hardest) items.push('🔥 Mais difícil: ' + shortOf(hardest.problem_id) + ' (' + pct(hardest.accept_rate) + ' de acerto)');
  if (ls[0]) items.push('⌨ Linguagem mais usada: ' + ls[0].lang + ' (' + ls[0].submissions + ' submissões)');
  if ((s.totals || {}).submissions) items.push('✅ Taxa global de aceitação: ' + pct((s.totals.accepted || 0) / s.totals.submissions));
  if ((s.totals || {}).users) items.push('📨 Média de ' + ((s.totals.submissions || 0) / s.totals.users).toFixed(1) + ' submissões por participante');
  return items.length ? el('div', { class: 'section' }, el('h2', {}, 'Destaques'), el('ul', { style: 'margin:.2rem 0 0 1.1rem' }, ...items.map((x) => el('li', {}, x)))) : el('div', {});
}

function totalsCards(t) {
  const card = (big, sub) => el('div', { class: 'stat-card' }, el('div', { class: 'big-num' }, String(big)), el('div', { class: 'big-sub' }, sub));
  return el('div', { class: 'stat-cards' },
    card(t.submissions || 0, 'submissões'), card(t.accepted || 0, 'aceitas'),
    card(t.users || 0, 'participantes ativos'), card(t.problems_solved || 0, 'problemas resolvidos'));
}

function problemsTable(ps) {
  const tb = el('tbody');
  ps.forEach((p) => tb.append(el('tr', {},
    el('td', {}, el('b', {}, p.short_name || shortOf(p.problem_id)), el('div', { class: 'small muted' }, p.full_name || '')),
    el('td', { class: 'n' }, String(p.submissions)),
    el('td', { class: 'n' }, String(p.accepted_subs != null ? p.accepted_subs : '—')),
    el('td', { class: 'n' }, String(p.attempted)),
    el('td', { class: 'n' }, String(p.solved)),
    el('td', { class: 'n' }, pct(p.accept_rate)),
    el('td', { class: 'n' }, p.avg_subs != null ? p.avg_subs.toFixed(1) : '—'),
    el('td', {}, p.first_solver ? (p.first_solver + ' · ' + p.first_minute + 'min') : '—'))));
  return el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
    el('thead', {}, el('tr', {}, el('th', {}, 'Problema'), el('th', {}, 'Subs'), el('th', {}, 'Aceitas'), el('th', {}, 'Tentaram'),
      el('th', {}, 'Resolveram'), el('th', {}, 'Taxa'), el('th', {}, 'Subs/pessoa'), el('th', {}, '1º a resolver'))), tb));
}

function verdictMatrix(s) {
  const vbp = s.verdict_by_problem || [];
  if (!vbp.length) return el('div', {});
  const gv = {}; vbp.forEach((x) => { gv[x.verdict] = (gv[x.verdict] || 0) + x.count; });
  const cols = Object.keys(gv).sort((a, b) => gv[b] - gv[a]).slice(0, 6);
  const m = {}; vbp.forEach((x) => { (m[x.problem] = m[x.problem] || {})[x.verdict] = x.count; });
  const tb = el('tbody');
  (s.problems || []).forEach((p) => {
    const row = m[p.problem_id] || {}, maxv = Math.max(0, ...cols.map((c) => row[c] || 0));
    tb.append(el('tr', {}, el('td', {}, el('b', {}, shortOf(p.problem_id))),
      ...cols.map((c) => { const v = row[c] || 0; return el('td', { class: 'n' + (v && v === maxv ? ' hot' : '') }, v ? String(v) : '·'); })));
  });
  return el('div', { class: 'chart-wrap' }, el('table', { class: 'moj vp-table' },
    el('thead', {}, el('tr', {}, el('th', {}, 'Problema'), ...cols.map((c) => el('th', {}, c)))), tb));
}

function balloonsSection(ps) {
  const solved = (ps || []).filter((p) => p.first_solver).slice().sort((a, b) => a.first_minute - b.first_minute);
  if (!solved.length) return el('div', {});
  const ol = el('ol', { style: 'margin:.2rem 0 0 1.2rem' });
  solved.forEach((p) => ol.append(el('li', {}, el('b', {}, shortOf(p.problem_id)), ' — ', p.first_solver, el('span', { class: 'small muted' }, ' aos ' + p.first_minute + ' min'))));
  return el('div', { class: 'section' }, el('h2', {}, '🎈 Primeiras resoluções (balões)'), ol);
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
  // o backend já resolve letra/nome (mesmo p/ contests legados onde o history guarda
  // o offset interno) — semeia o mapa p/ que shortOf() funcione na matriz/balões/gráficos
  (s.problems || []).forEach((p) => { if (p.short_name) probMap[p.problem_id] = p.short_name; });
  app.append(totalsCards(s.totals || {}));
  app.append(highlights(s));

  app.append(el('div', { class: 'section' }, el('h2', {}, 'Por problema'),
    problemsTable(s.problems || []),
    el('div', { class: 'two-col', style: 'margin-top:1rem' },
      el('div', {}, el('div', { class: 'chart-title' }, 'Submissões por problema'),
        barChart((s.problems || []).map((p) => ({ label: shortOf(p.problem_id), value: p.submissions })), { rotateLabels: true })),
      el('div', {}, el('div', { class: 'chart-title' }, 'Resolvedores por problema'),
        barChart((s.problems || []).map((p) => ({ label: shortOf(p.problem_id), value: p.solved })), { rotateLabels: true })))));

  app.append(balloonsSection(s.problems));

  const totSubs = (s.totals || {}).submissions || 0;
  app.append(el('div', { class: 'section' }, el('h2', {}, 'Veredictos e linguagens'),
    el('div', { class: 'two-col' },
      el('div', {}, el('div', { class: 'chart-title' }, 'Distribuição de veredictos'),
        hBarChart((s.verdicts || []).map((v) => ({ label: v.verdict, value: v.count })), { hideZero: true, total: totSubs }),
        el('div', { class: 'small muted', style: 'text-align:center; margin-top:.35rem' }, 'cada barra = % das ' + totSubs + ' submissões')),
      el('div', {}, el('div', { class: 'chart-title' }, 'Linguagens mais usadas'),
        hBarChart((s.languages || []).map((l) => ({ label: l.lang, value: l.submissions })), { hideZero: true, total: totSubs }),
        langTable(s.languages || []))),
    el('h3', { style: 'margin:1.2rem 0 .3rem' }, 'Veredictos por problema'), verdictMatrix(s)));

  if ((s.timeline || []).length) {
    app.append(el('div', { class: 'section' }, el('h2', {}, 'Linha do tempo'),
      el('div', { class: 'chart-title' }, 'Submissões ao longo do tempo (por 10 min)'),
      barChart(s.timeline.map((t) => ({ label: t.minute + 'm', value: t.submissions })), { rotateLabels: true }),
      el('div', { class: 'chart-title', style: 'margin-top:.6rem' }, 'Aceitas ao longo do tempo'),
      barChart(s.timeline.map((t) => ({ label: t.minute + 'm', value: t.accepted })), { rotateLabels: true }),
      el('div', { class: 'chart-title', style: 'margin-top:.6rem' }, 'Aceitas acumuladas'),
      lineChart((() => { let c = 0; return s.timeline.map((t) => ({ label: t.minute + 'm', y: (c += t.accepted) })); })())));
  }

  // distribuição de desempenho + quartis
  const solves = expandSolves(s.problems_solved_dist);
  const q = quartiles(solves);
  const distSec = el('div', { class: 'section' }, el('h2', {}, 'Distribuição de desempenho'));
  if (q) {
    distSec.append(el('p', { class: 'muted small' }, q.n + ' participantes. Quartis por nº de problemas resolvidos:'),
      el('div', { class: 'stat-cards' },
        el('div', { class: 'stat-card' }, el('div', { class: 'big-num' }, '≥' + q.top25), el('div', { class: 'big-sub' }, 'top 25% resolveu')),
        el('div', { class: 'stat-card' }, el('div', { class: 'big-num' }, String(q.median)), el('div', { class: 'big-sub' }, 'mediana (50%)')),
        el('div', { class: 'stat-card' }, el('div', { class: 'big-num' }, '≥' + q.bottom25), el('div', { class: 'big-sub' }, '75% resolveu ao menos')),
        el('div', { class: 'stat-card' }, el('div', { class: 'big-num' }, q.max + ' / ' + q.min), el('div', { class: 'big-sub' }, 'máx / mín resolvidos'))));
  }
  distSec.append(el('div', { class: 'two-col', style: 'margin-top:.6rem' },
    el('div', {}, el('div', { class: 'chart-title' }, 'Participantes por nº de problemas resolvidos'),
      barChart((s.problems_solved_dist || []).map((d) => ({ label: String(d.solved), value: d.users })))),
    el('div', {}, el('div', { class: 'chart-title' }, 'Tentativas até resolver'),
      barChart((s.attempts_dist || []).map((d) => ({ label: String(d.attempts), value: d.count }))))));
  app.append(distSec);
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
