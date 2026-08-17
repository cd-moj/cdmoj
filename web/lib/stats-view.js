// lib/stats-view.js — as SEÇÕES da página de estatísticas, em um lugar só.
//
// Fonte ÚNICA de duas telas que precisam ser iguais: /contest/statistics/ (ao vivo) e o
// statistics.html do RELATÓRIO OFFLINE (report-gen.sh inlina este arquivo, o charts.js e o
// dom.js num <script> e chama statsSections com o statistics.cache.json embutido). Antes o
// relatório tinha 5 tabelas escritas à mão em jq — sem gráfico, sem destaques, sem balões,
// sem matriz de veredictos — e divergia do painel a cada mudança.
//
// Só depende de dom.js (sem rede) e charts.js. Recebe o objeto do
// /contest/statistics (= var/statistics.cache.json) e devolve um ARRAY de elementos.
import { el } from '/shared/dom.js';
import { barChart, hBarChart, lineChart } from '/lib/charts.js';
import { T } from '/shared/i18n.js';

const pct = (x) => Math.round((x || 0) * 100) + '%';

// "Nome do Time (login)" — em estatística NUNCA se mostra só o login: quem lê procura o
// nome. O nome vem do próprio cache (first_solver_name, resolvido no stats-gen).
function who(login, name) {
  if (!login) return '—';
  return name && name !== login ? name + ' (' + login + ')' : login;
}

function expandSolves(dist) { const a = []; (dist || []).forEach((d) => { for (let i = 0; i < d.users; i++) a.push(d.solved); }); return a; }
function quartiles(arr) {
  if (!arr.length) return null;
  const s = arr.slice().sort((a, b) => b - a), at = (p) => s[Math.min(s.length - 1, Math.floor(p * s.length))];
  return { top25: at(0.25), median: at(0.5), bottom25: at(0.75), max: s[0], min: s[s.length - 1], n: s.length };
}

function highlights(s, shortOf) {
  const ps = s.problems || [], ls = s.languages || [], items = [];
  const mostSolved = ps.slice().sort((a, b) => b.solved - a.solved)[0];
  const hardest = ps.filter((p) => p.attempted > 0).slice().sort((a, b) => a.accept_rate - b.accept_rate)[0];
  if (mostSolved) items.push(T('🏆 Mais resolvido: ', '🏆 Most solved: ') + shortOf(mostSolved.problem_id) + ' (' + mostSolved.solved + T(' resolveram)', ' solved it)'));
  if (hardest) items.push(T('🔥 Mais difícil: ', '🔥 Hardest: ') + shortOf(hardest.problem_id) + ' (' + pct(hardest.accept_rate) + T(' de acerto)', ' accept rate)'));
  if (ls[0]) items.push(T('⌨ Linguagem mais usada: ', '⌨ Most used language: ') + ls[0].lang + ' (' + ls[0].submissions + T(' submissões)', ' submissions)'));
  if ((s.totals || {}).submissions) items.push(T('✅ Taxa global de aceitação: ', '✅ Global acceptance rate: ') + pct((s.totals.accepted || 0) / s.totals.submissions));
  if ((s.totals || {}).users) items.push(T('📨 Média de ', '📨 Average of ') + ((s.totals.submissions || 0) / s.totals.users).toFixed(1) + T(' submissões por participante', ' submissions per participant'));
  return items.length ? el('div', { class: 'section' }, el('h2', {}, T('Destaques', 'Highlights')), el('ul', { style: 'margin:.2rem 0 0 1.1rem' }, ...items.map((x) => el('li', {}, x)))) : el('div', {});
}

function totalsCards(t) {
  const card = (big, sub) => el('div', { class: 'stat-card' }, el('div', { class: 'big-num' }, String(big)), el('div', { class: 'big-sub' }, sub));
  return el('div', { class: 'stat-cards' },
    card(t.submissions || 0, T('submissões', 'submissions')), card(t.accepted || 0, T('aceitas', 'accepted')),
    card(t.users || 0, T('participantes ativos', 'active participants')), card(t.problems_solved || 0, T('problemas resolvidos', 'problems solved')));
}

function problemsTable(ps, shortOf) {
  const tb = el('tbody');
  ps.forEach((p) => tb.append(el('tr', {},
    el('td', {}, el('b', {}, p.short_name || shortOf(p.problem_id)), el('div', { class: 'small muted' }, p.full_name || '')),
    el('td', { class: 'n' }, String(p.submissions)),
    el('td', { class: 'n' }, String(p.accepted_subs != null ? p.accepted_subs : '—')),
    el('td', { class: 'n' }, String(p.attempted)),
    el('td', { class: 'n' }, String(p.solved)),
    el('td', { class: 'n' }, pct(p.accept_rate)),
    el('td', { class: 'n' }, p.avg_subs != null ? p.avg_subs.toFixed(1) : '—'),
    el('td', {}, p.first_solver ? (who(p.first_solver, p.first_solver_name) + ' · ' + p.first_minute + 'min' + (p.first_seconds >= 0 ? ' (' + p.first_seconds + 's)' : '')) : '—'))));
  return el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
    el('thead', {}, el('tr', {}, el('th', {}, T('Problema', 'Problem')),
      el('th', { class: 'n' }, 'Subs'), el('th', { class: 'n' }, T('Aceitas', 'Accepted')),
      el('th', { class: 'n' }, T('Tentaram', 'Attempted')), el('th', { class: 'n' }, T('Resolveram', 'Solved')),
      el('th', { class: 'n' }, T('Taxa', 'Rate')), el('th', { class: 'n' }, T('Subs/pessoa', 'Subs/person')),
      el('th', {}, T('1º a resolver', 'First to solve')))), tb));
}

function verdictMatrix(s, shortOf) {
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
    el('thead', {}, el('tr', {}, el('th', {}, T('Problema', 'Problem')), ...cols.map((c) => el('th', { class: 'n' }, c)))), tb));
}

function balloonsSection(ps, shortOf) {
  const solved = (ps || []).filter((p) => p.first_solver).slice()
    .sort((a, b) => (a.first_seconds >= 0 && b.first_seconds >= 0 ? a.first_seconds - b.first_seconds : a.first_minute - b.first_minute));
  if (!solved.length) return el('div', {});
  const ol = el('ol', { style: 'margin:.2rem 0 0 1.2rem' });
  solved.forEach((p) => ol.append(el('li', {}, el('b', {}, shortOf(p.problem_id)), ' — ', who(p.first_solver, p.first_solver_name),
    el('span', { class: 'small muted' }, T(' aos ', ' at ') + p.first_minute + ' min' + (p.first_seconds >= 0 ? ' (' + p.first_seconds + 's)' : '')))));
  return el('div', { class: 'section' }, el('h2', {}, T('🎈 Primeiras resoluções (balões)', '🎈 First solves (balloons)')), ol);
}

function langTable(ls) {
  const tb = el('tbody');
  ls.forEach((l) => tb.append(el('tr', {},
    el('td', {}, l.lang), el('td', { class: 'n' }, String(l.submissions)),
    el('td', { class: 'n' }, String(l.accepted)), el('td', { class: 'n' }, String(l.solvers)))));
  return el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
    el('thead', {}, el('tr', {}, el('th', {}, T('Linguagem', 'Language')), el('th', { class: 'n' }, 'Subs'),
      el('th', { class: 'n' }, T('Aceitas', 'Accepted')), el('th', { class: 'n' }, T('Resolvedores', 'Solvers')))), tb));
}

// statsSections(s, opts) -> [elementos] na ordem da página.
// opts.probMap: {problem_id: letra} opcional (o cache já traz short_name; o mapa só cobre
// contest legado cujo history guarda o offset interno).
export function statsSections(s, opts = {}) {
  const probMap = Object.assign({}, opts.probMap || {});
  (s.problems || []).forEach((p) => { if (p.short_name) probMap[p.problem_id] = p.short_name; });
  const shortOf = (pid) => probMap[pid] || pid;
  const out = [];

  out.push(totalsCards(s.totals || {}));
  out.push(highlights(s, shortOf));

  out.push(el('div', { class: 'section' }, el('h2', {}, T('Por problema', 'By problem')),
    problemsTable(s.problems || [], shortOf),
    el('div', { class: 'two-col', style: 'margin-top:1rem' },
      el('div', {}, el('div', { class: 'chart-title' }, T('Submissões por problema', 'Submissions by problem')),
        barChart((s.problems || []).map((p) => ({ label: shortOf(p.problem_id), value: p.submissions })), { rotateLabels: true })),
      el('div', {}, el('div', { class: 'chart-title' }, T('Resolvedores por problema', 'Solvers by problem')),
        barChart((s.problems || []).map((p) => ({ label: shortOf(p.problem_id), value: p.solved })), { rotateLabels: true })))));

  out.push(balloonsSection(s.problems, shortOf));

  const totSubs = (s.totals || {}).submissions || 0;
  out.push(el('div', { class: 'section' }, el('h2', {}, T('Veredictos e linguagens', 'Verdicts and languages')),
    el('div', { class: 'two-col' },
      el('div', {}, el('div', { class: 'chart-title' }, T('Distribuição de veredictos', 'Verdict distribution')),
        hBarChart((s.verdicts || []).map((v) => ({ label: v.verdict, value: v.count })), { hideZero: true, total: totSubs }),
        el('div', { class: 'small muted', style: 'text-align:center; margin-top:.35rem' }, T('cada barra = % das ', 'each bar = % of the ') + totSubs + T(' submissões', ' submissions'))),
      el('div', {}, el('div', { class: 'chart-title' }, T('Linguagens mais usadas', 'Most used languages')),
        hBarChart((s.languages || []).map((l) => ({ label: l.lang, value: l.submissions })), { hideZero: true, total: totSubs }),
        langTable(s.languages || []))),
    el('h3', { style: 'margin:1.2rem 0 .3rem' }, T('Veredictos por problema', 'Verdicts by problem')), verdictMatrix(s, shortOf)));

  if ((s.timeline || []).length) {
    out.push(el('div', { class: 'section' }, el('h2', {}, T('Linha do tempo', 'Timeline')),
      el('div', { class: 'chart-title' }, T('Submissões ao longo do tempo (por 10 min)', 'Submissions over time (per 10 min)')),
      barChart(s.timeline.map((t) => ({ label: t.minute + 'm', value: t.submissions })), { rotateLabels: true }),
      el('div', { class: 'chart-title', style: 'margin-top:.6rem' }, T('Aceitas ao longo do tempo', 'Accepted over time')),
      barChart(s.timeline.map((t) => ({ label: t.minute + 'm', value: t.accepted })), { rotateLabels: true }),
      el('div', { class: 'chart-title', style: 'margin-top:.6rem' }, T('Aceitas acumuladas', 'Cumulative accepted')),
      lineChart((() => { let c = 0; return s.timeline.map((t) => ({ label: t.minute + 'm', y: (c += t.accepted) })); })())));
  }

  const q = quartiles(expandSolves(s.problems_solved_dist));
  const distSec = el('div', { class: 'section' }, el('h2', {}, T('Distribuição de desempenho', 'Performance distribution')));
  if (q) {
    distSec.append(el('p', { class: 'muted small' }, q.n + T(' participantes. Quartis por nº de problemas resolvidos:', ' participants. Quartiles by number of problems solved:')),
      el('div', { class: 'stat-cards' },
        el('div', { class: 'stat-card' }, el('div', { class: 'big-num' }, '≥' + q.top25), el('div', { class: 'big-sub' }, T('top 25% resolveu', 'top 25% solved'))),
        el('div', { class: 'stat-card' }, el('div', { class: 'big-num' }, String(q.median)), el('div', { class: 'big-sub' }, T('mediana (50%)', 'median (50%)'))),
        el('div', { class: 'stat-card' }, el('div', { class: 'big-num' }, '≥' + q.bottom25), el('div', { class: 'big-sub' }, T('75% resolveu ao menos', '75% solved at least'))),
        el('div', { class: 'stat-card' }, el('div', { class: 'big-num' }, q.max + ' / ' + q.min), el('div', { class: 'big-sub' }, T('máx / mín resolvidos', 'max / min solved')))));
  }
  distSec.append(el('div', { class: 'two-col', style: 'margin-top:.6rem' },
    el('div', {}, el('div', { class: 'chart-title' }, T('Participantes por nº de problemas resolvidos', 'Participants by number of problems solved')),
      barChart((s.problems_solved_dist || []).map((d) => ({ label: String(d.solved), value: d.users })))),
    el('div', {}, el('div', { class: 'chart-title' }, T('Tentativas até resolver', 'Attempts until solved')),
      barChart((s.attempts_dist || []).map((d) => ({ label: String(d.attempts), value: d.count }))))));
  out.push(distSec);
  return out;
}
