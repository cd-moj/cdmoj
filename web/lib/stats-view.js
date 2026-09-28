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
import { barChart, hBarChart, lineChart, multiLineChart } from '/lib/charts.js';
import { T } from '/shared/i18n.js';
import { diffLabel, diffClass, diffKeyFromRate, dirtTone } from '/shared/difficulty.js';

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
  // cada destaque DIZ a métrica que usa (feedback 01/09); texto curto e direto (STE)
  const ps = s.problems || [], ls = s.languages || [], items = [];
  const mostSolved = ps.slice().sort((a, b) => b.solved - a.solved)[0];
  const leastSolved = ps.filter((p) => p.attempted > 0).slice().sort((a, b) => a.solved - b.solved)[0];
  const dirtiest = ps.filter((p) => p.dirt != null).slice().sort((a, b) => b.dirt - a.dirt)[0];
  const latest = ps.filter((p) => p.avg_ac_min != null).slice().sort((a, b) => b.avg_ac_min - a.avg_ac_min)[0];
  if (mostSolved) items.push(T('🏆 Mais resolvido: ', '🏆 Most solved: ', '🏆 Más resuelto: ') + shortOf(mostSolved.problem_id) +
    ' (' + mostSolved.solved + T(' times resolveram', ' teams solved it', ' equipos lo resolvieron') + ')');
  if (leastSolved) items.push(T('🧊 Menos resolvido: ', '🧊 Least solved: ', '🧊 Menos resuelto: ') + shortOf(leastSolved.problem_id) +
    ' (' + leastSolved.solved + T(' times resolveram', ' teams solved it', ' equipos lo resolvieron') + ')');
  if (dirtiest) items.push(T('🧹 Maior dirt: ', '🧹 Highest dirt: ', '🧹 Mayor dirt: ') + shortOf(dirtiest.problem_id) +
    ' (' + pct(dirtiest.dirt) + T(' das submissões de quem resolveu eram erradas', ' of the solvers\u2019 submissions were wrong', ' de los envíos de quienes lo resolvieron eran incorrectos') + ')');
  if (latest) items.push(T('🕘 AC médio mais tardio: ', '🕘 Latest average AC: ', '🕘 AC promedio más tardío: ') + shortOf(latest.problem_id) +
    ' (' + T('minuto ', 'minute ', 'minuto ') + latest.avg_ac_min + ')');
  if (ls[0]) items.push(T('⌨ Linguagem mais usada: ', '⌨ Most used language: ', '⌨ Lenguaje más usado: ') + ls[0].lang +
    ' (' + ls[0].submissions + T(' submissões', ' submissions', ' envíos') + ')');
  if ((s.totals || {}).submissions) items.push(T('✅ Aceitação global: ', '✅ Global acceptance: ', '✅ Aceptación global: ') +
    pct((s.totals.accepted || 0) / s.totals.submissions) + T(' das submissões', ' of all submissions', ' de todos los envíos'));
  return items.length ? el('div', { class: 'section' }, el('h2', {}, T('Destaques', 'Highlights', 'Destacados')), el('ul', { style: 'margin:.2rem 0 0 1.1rem' }, ...items.map((x) => el('li', {}, x)))) : el('div', {});
}

function totalsCards(t) {
  const card = (big, sub) => el('div', { class: 'stat-card' }, el('div', { class: 'big-num' }, String(big)), el('div', { class: 'big-sub' }, sub));
  // enrolled/absent (2026-08-31): a página contava só quem SUBMETEU e os zeros do placar
  // "sumiam" (relato da LATAM). Cache novo traz inscritos + ausentes; cache antigo (sem os
  // campos) mantém os 4 cartões de sempre.
  const extra = (t.enrolled != null)
    ? [card(t.enrolled || 0, T('inscritos', 'enrolled', 'inscritos')),
       card(t.absent || 0, T('ausentes (sem submissão)', 'absent (no submissions)', 'ausentes (sin envíos)'))]
    : [];
  return el('div', { class: 'stat-cards' },
    ...extra,
    card(t.users || 0, T('participantes ativos', 'active participants', 'participantes activos')),
    card(t.submissions || 0, T('submissões', 'submissions', 'envíos')), card(t.accepted || 0, T('aceitas', 'accepted', 'aceptados')),
    card(t.problems_solved || 0, T('problemas resolvidos', 'problems solved', 'problemas resueltos')));
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
    // dificuldade = mesmo vocabulário do treino (shared/difficulty.js): rótulo pela taxa por time
    (() => { const k = p.difficulty || (p.attempted ? diffKeyFromRate(p.accept_rate) : 'new'); return el('td', { class: 'diff ' + diffClass(k) }, diffLabel(k)); })(),
    el('td', { class: 'n' }, p.avg_subs != null ? p.avg_subs.toFixed(1) : '—'),
    el('td', { class: 'n' }, p.avg_ac_min != null ? p.avg_ac_min + 'm' : '—'),
    el('td', { class: 'n' }, p.tries_per_ac != null ? String(p.tries_per_ac) : '—'),
    el('td', { class: 'n ' + dirtTone(p.dirt) }, p.dirt != null ? pct(p.dirt) : '—'),
    el('td', { class: 'small' }, (() => {
      const l = Object.entries(p.ac_langs || {}).sort((a, b) => b[1] - a[1]);
      if (!l.length) return '—';
      return l.slice(0, 2).map(([k, n]) => k + '×' + n).join(' ') + (l.length > 2 ? ' …' : '');
    })()),
    el('td', {}, p.first_solver ? (who(p.first_solver, p.first_solver_name) + ' · ' + p.first_minute + 'min' + (p.first_seconds >= 0 ? ' (' + p.first_seconds + 's)' : '')) : '—'))));
  return el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
    el('thead', {}, el('tr', {}, el('th', {}, T('Problema', 'Problem', 'Problema')),
      el('th', { class: 'n' }, 'Subs'), el('th', { class: 'n' }, T('Aceitas', 'Accepted', 'Aceptados')),
      el('th', { class: 'n' }, T('Tentaram', 'Attempted', 'Intentaron')), el('th', { class: 'n' }, T('Resolveram', 'Solved', 'Resolvieron')),
      el('th', { class: 'n' }, T('Taxa', 'Rate', 'Tasa')),
      el('th', { title: T('rótulo pela taxa: ≥90% muito fácil · ≥70% fácil · ≥50% médio · <50% difícil (o mesmo do treino)', 'label by the rate: ≥90% very easy · ≥70% easy · ≥50% medium · <50% hard (same as the practice area)', 'etiqueta por la tasa: ≥90% muy fácil · ≥70% fácil · ≥50% medio · <50% difícil (igual que el área de práctica)') }, T('Dificuldade', 'Difficulty', 'Dificultad')),
      el('th', { class: 'n' }, T('Subs/pessoa', 'Subs/person', 'Envíos/persona')),
      el('th', { class: 'n', title: T('minuto médio do AC', 'average AC minute', 'minuto promedio del AC') }, T('AC médio', 'Avg AC', 'AC prom.')),
      el('th', { class: 'n', title: T('submissões até o AC (média de quem resolveu)', 'submissions until AC (avg of solvers)', 'envíos hasta el AC (promedio de quienes resolvieron)') }, T('Tent./AC', 'Tries/AC', 'Intentos/AC')),
      el('th', { class: 'n', title: T('parte das submissões de quem resolveu que estava errada (métrica do resolver ICPC)', 'the part of the solvers\u2019 submissions that was wrong (ICPC resolver metric)', 'la parte de los envíos de quienes resolvieron que fue incorrecta (métrica del resolver ICPC)') }, 'Dirt'),
      el('th', { title: T('linguagem dos ACs', 'language of the ACs', 'lenguaje de los AC') }, T('Língua', 'Language', 'Lenguaje')),
      el('th', {}, T('1º a resolver', 'First to solve', 'Primero en resolver')))), tb));
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
    el('thead', {}, el('tr', {}, el('th', {}, T('Problema', 'Problem', 'Problema')), ...cols.map((c) => el('th', { class: 'n' }, c)))), tb));
}

function balloonsSection(ps, shortOf) {
  const solved = (ps || []).filter((p) => p.first_solver).slice()
    .sort((a, b) => (a.first_seconds >= 0 && b.first_seconds >= 0 ? a.first_seconds - b.first_seconds : a.first_minute - b.first_minute));
  if (!solved.length) return el('div', {});
  const ol = el('ol', { style: 'margin:.2rem 0 0 1.2rem' });
  solved.forEach((p) => ol.append(el('li', {}, el('b', {}, shortOf(p.problem_id)), ' · ', who(p.first_solver, p.first_solver_name),
    el('span', { class: 'small muted' }, T(' aos ', ' at ', ' a los ') + p.first_minute + ' min' + (p.first_seconds >= 0 ? ' (' + p.first_seconds + 's)' : '')))));
  return el('div', { class: 'section' }, el('h2', {}, T('🎈 Primeiras resoluções (balões)', '🎈 First solves (balloons)', '🎈 Primeras resoluciones (globos)')), ol);
}

function langTable(ls) {
  const tb = el('tbody');
  ls.forEach((l) => tb.append(el('tr', {},
    el('td', {}, l.lang), el('td', { class: 'n' }, String(l.submissions)),
    el('td', { class: 'n' }, String(l.accepted)), el('td', { class: 'n' }, String(l.solvers)))));
  return el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
    el('thead', {}, el('tr', {}, el('th', {}, T('Linguagem', 'Language', 'Lenguaje')), el('th', { class: 'n' }, 'Subs'),
      el('th', { class: 'n' }, T('Aceitas', 'Accepted', 'Aceptados')), el('th', { class: 'n' }, T('Resolvedores', 'Solvers', 'Resolvedores')))), tb));
}

// ---- Estatísticas 2.0: corrida, comparação e desempenho POR RECORTE (01/09) -----------
// As três seções computam dos ac_events GLOBAIS, filtrados pela seleção corrente.
// opts.analytics = {events, idx, pen, unrankedRe, filter} vem do chamador; sem ele, o
// objeto global serve de fonte (filter nulo). idx: {login:{n,c,r}} (tolera string antiga).
const MIN_RANK_TEAMS = 30;   // ranking/desempenho só com 30+ times com AC na seleção
function idxName(idx, lg) { const v = idx && idx[lg]; return typeof v === 'string' ? v : (v && v.n) || lg; }
function anFrom(s, opts) {
  if (opts && opts.analytics) return opts.analytics;
  if (!s.ac_events) return null;
  let unr = null; try { unr = s.unranked_regex ? new RegExp(s.unranked_regex) : null; } catch (e) { unr = null; }
  return { events: s.ac_events, idx: s.teams_idx || {}, pen: s.penalty_minutes || 20, unrankedRe: unr, filter: null };
}
function anEvents(an) { return an.filter ? an.events.filter((e) => an.filter(e[0])) : an.events; }
function contestDur(s, ev) {
  return Math.max(1, ...((s.timeline || []).map((t) => t.minute)), ...(ev.map((e) => e[2])));
}
// 🏁 ACs acumulados por problema (curva de progressão do ICPC), na seleção corrente
function problemRace(s, shortOf, an) {
  if (!an) return null;
  const ev = anEvents(an);
  if (!ev.length) return null;
  const by = {};
  ev.forEach((e) => { (by[e[1]] = by[e[1]] || []).push(e[2]); });
  const series = Object.keys(by).sort((a, b) => shortOf(a).localeCompare(shortOf(b))).map((pid) => {
    let c = 0;
    return { label: shortOf(pid), points: by[pid].sort((x, y) => x - y).map((m) => ({ x: m, y: ++c })) };
  });
  return el('div', { class: 'section' },
    el('h2', {}, T('🏁 Corrida dos problemas', '🏁 Problem race', '🏁 Carrera de problemas')),
    el('p', { class: 'muted small' }, T('Cada linha mostra os ACs acumulados de um problema. A curva mostra a ordem real de dificuldade.',
      'Each line shows the cumulative ACs of one problem. The curve shows the real difficulty order.',
      'Cada línea muestra los AC acumulados de un problema. La curva muestra el orden real de dificultad.')),
    multiLineChart(series, { xMax: contestDur(s, ev) }));
}
// 🆚 comparação de times (resolvidos × minuto, degraus), na seleção corrente
function teamCompare(s, an) {
  if (!an) return null;
  const ev = anEvents(an), idx = an.idx;
  if (!ev.length) return null;
  const byTeam = {};
  ev.forEach((e) => { (byTeam[e[0]] = byTeam[e[0]] || []).push({ m: e[2], tries: e[3] }); });
  const box = el('div', { class: 'section' });
  const chartBox = el('div', {});
  const chosen = [];
  const chips = el('div', { style: 'display:flex;flex-wrap:wrap;gap:.3rem;margin:.3rem 0' });
  const dlid = 'cmp-teams-' + Math.floor(Math.random() * 1e6);
  const dl = el('datalist', { id: dlid });
  Object.keys(byTeam).forEach((lg) => dl.append(el('option', { value: who(lg, idxName(idx, lg)) })));
  const inp = el('input', { list: dlid, placeholder: T('adicione um time (nome ou login)', 'add a team (name or login)', 'agregar un equipo (nombre o usuario)'), style: 'min-width:240px' });
  function loginOf(text) {
    const t = String(text || '').trim();
    if (byTeam[t]) return t;
    const m = t.match(/\(([^)]+)\)\s*$/); if (m && byTeam[m[1]]) return m[1];
    const lower = t.toLowerCase();
    return Object.keys(byTeam).find((lg) => idxName(idx, lg).toLowerCase() === lower) || null;
  }
  const tops = rankTeams(an).slice(0, 15);
  function render() {
    chips.innerHTML = ''; chartBox.innerHTML = '';
    chosen.forEach((lg, i) => chips.append(el('span', { class: 'small', style: 'padding:.15em .5em;border:1px solid var(--line,#c9d2e0);border-radius:1em;cursor:pointer', title: T('remover', 'remove', 'quitar'),
      onclick: () => { chosen.splice(i, 1); render(); } }, who(lg, idxName(idx, lg)) + ' ✕')));
    if (!chosen.length) { chartBox.append(el('p', { class: 'muted small' }, T('Escolha times acima ou use um preset.', 'Choose teams above or use a preset.', 'Elige equipos arriba o usa un preajuste.'))); return; }
    const series = chosen.map((lg) => {
      let c = 0;
      const pts = byTeam[lg].slice().sort((a, b) => a.m - b.m).map((e) => ({ x: e.m, y: ++c }));
      return { label: who(lg, idxName(idx, lg)), points: pts };
    });
    chartBox.append(multiLineChart(series, { xMax: contestDur(s, ev) }));
  }
  function preset(n) { chosen.length = 0; tops.slice(0, n).forEach((t) => chosen.push(t.login)); render(); }
  inp.addEventListener('change', () => { const lg = loginOf(inp.value); if (lg) { inp.value = ''; if (chosen.indexOf(lg) < 0) { chosen.push(lg); render(); } } });
  box.append(el('h2', {}, T('🆚 Comparar times na prova', '🆚 Compare teams in the contest', '🆚 Comparar equipos en la competencia')),
    el('p', { class: 'muted small' }, T('O gráfico mostra os problemas resolvidos de cada time, minuto a minuto.',
      'The chart shows the solved problems of each team, minute by minute.',
      'El gráfico muestra los problemas resueltos de cada equipo, minuto a minuto.')),
    el('div', { class: 'toolbar' }, inp,
      el('button', { class: 'btn ghost', onclick: () => preset(3) }, 'top 3'),
      el('button', { class: 'btn ghost', onclick: () => preset(10) }, 'top 10'),
      el('button', { class: 'btn ghost', onclick: () => { chosen.length = 0; render(); } }, T('limpar', 'clear', 'limpiar'))),
    dl, chips, chartBox);
  render();
  return box;
}
// ranking oficial da seleção: solved/penalty por time, convidado (unranked) fora
function rankTeams(an) {
  const per = {};
  anEvents(an).forEach((e) => {
    const lg = e[0];
    if (an.unrankedRe && an.unrankedRe.test(lg)) return;
    const t = per[lg] || (per[lg] = { login: lg, solved: 0, penalty: 0, first: Infinity });
    t.solved++; t.penalty += e[2] + an.pen * (e[3] - 1);
    if (e[2] < t.first) t.first = e[2];
  });
  return Object.values(per).sort((a, b) => (b.solved - a.solved) || (a.penalty - b.penalty));
}
function pctlOf(arr, q) { return arr.length ? arr[Math.floor((arr.length - 1) * q)] : null; }
// 🏆 desempenho + top 15 da SELEÇÃO (com card explicativo quando a amostra é pequena)
function performanceSection(s, an) {
  if (!an) return null;
  const teams = rankTeams(an);
  const sec = el('div', { class: 'section' }, el('h2', {}, T('🏆 Desempenho e top teams', '🏆 Performance and top teams', '🏆 Desempeño y mejores equipos')));
  if (!teams.length) return null;
  if (teams.length < MIN_RANK_TEAMS) {
    sec.append(el('p', { class: 'muted' },
      T('Esta seleção tem ' + teams.length + ' time(s) com AC. Este quadro aparece com ' + MIN_RANK_TEAMS + ' ou mais times. Use o placar com o filtro de sede para ver poucos times.',
        'This selection has ' + teams.length + ' team(s) with an AC. This panel needs ' + MIN_RANK_TEAMS + ' or more teams. Use the scoreboard with the site filter to see few teams.',
        'Esta selección tiene ' + teams.length + ' equipo(s) con AC. Este cuadro aparece con ' + MIN_RANK_TEAMS + ' o más equipos. Usa el marcador con el filtro de sede para ver pocos equipos.')));
    return sec;
  }
  const so = teams.map((t) => t.solved).sort((a, b) => a - b);
  const pe = teams.map((t) => t.penalty).sort((a, b) => a - b);
  const fa = teams.map((t) => t.first).sort((a, b) => a - b);
  const mean = (a) => Math.round((a.reduce((x, y) => x + y, 0) / a.length) * 100) / 100;
  const card = (big, sub) => el('div', { class: 'stat-card' }, el('div', { class: 'big-num' }, String(big)), el('div', { class: 'big-sub' }, sub));
  sec.append(el('div', { class: 'stat-cards' },
    card(teams.length, T('times com AC na seleção', 'teams with an AC in the selection', 'equipos con un AC en el recorte')),
    card(mean(so), T('média de resolvidos', 'average solved', 'promedio de resueltos')),
    card(pctlOf(so, 0.5) + ' · ' + pctlOf(so, 0.25) + '–' + pctlOf(so, 0.75), T('mediana · quartis (resolvidos)', 'median · quartiles (solved)', 'mediana · cuartiles (resueltos)')),
    card('≥' + pctlOf(so, 0.9), T('o top 10% resolveu', 'the top 10% solved', 'el 10% superior resolvió')),
    card(pctlOf(pe, 0.5), T('penalidade mediana', 'median penalty', 'penalidad mediana')),
    card(pctlOf(fa, 0.5) + 'm', T('minuto mediano do 1º AC', 'median minute of the first AC', 'minuto mediano del primer AC'))));
  const tb = el('tbody');
  teams.slice(0, 15).forEach((t, i) => tb.append(el('tr', {},
    el('td', { class: 'n' }, String(i + 1)),
    el('td', {}, who(t.login, idxName(an.idx, t.login))),
    el('td', { class: 'n' }, String(t.solved)),
    el('td', { class: 'n' }, String(t.penalty)))));
  sec.append(el('div', { class: 'chart-title', style: 'margin-top:.5rem' }, T('Top 15 da seleção', 'Top 15 of the selection', 'Top 15 del recorte')),
    el('div', { class: 'chart-wrap' }, el('table', { class: 'moj narrow' },
      el('thead', {}, el('tr', {}, el('th', { class: 'n' }, '#'), el('th', {}, T('Time', 'Team', 'Equipo')),
        el('th', { class: 'n' }, T('Resolvidos', 'Solved', 'Resueltos')), el('th', { class: 'n' }, T('Penalidade', 'Penalty', 'Penalidad')))), tb)),
    el('p', { class: 'muted small' },
      T('Convidados (coorte extra-oficial) não entram neste quadro. A penalidade usa a regra ICPC.',
        'Guest teams (unranked cohort) are not in this panel. The penalty uses the ICPC rule.',
        'Los equipos invitados (cohorte extraoficial) no están en este panel. La penalidad usa la regla ICPC.')));
  return sec;
}
// legenda da tabela por problema (o que cada coluna significa)
function problemsLegend() {
  const li = (k, txt) => el('li', {}, el('b', {}, k + ': '), txt);
  return el('details', { class: 'small', style: 'margin:.3rem 0 .6rem' },
    el('summary', {}, T('Como ler a tabela', 'How to read the table', 'Cómo leer la tabla')),
    el('ul', { style: 'margin:.2rem 0 0 1.1rem' },
      li(T('Taxa', 'Rate', 'Tasa'), T('times que resolveram dividido por times que tentaram.', 'teams that solved divided by teams that tried.', 'equipos que resolvieron dividido por equipos que lo intentaron.')),
      li(T('Dificuldade', 'Difficulty', 'Dificultad'), T('rótulo pela Taxa: ≥90% muito fácil, ≥70% fácil, ≥50% médio, <50% difícil. É a mesma escala do Treino Livre.', 'label by the Rate: ≥90% very easy, ≥70% easy, ≥50% medium, <50% hard. It is the same scale as the practice area.', 'etiqueta por la Tasa: ≥90% muy fácil, ≥70% fácil, ≥50% medio, <50% difícil. Es la misma escala que el área de práctica.')),
      li(T('Subs/pessoa', 'Subs/person', 'Envíos/persona'), T('submissões por time que tentou.', 'submissions per team that tried.', 'envíos por equipo que lo intentó.')),
      li(T('AC médio', 'Avg AC', 'AC prom.'), T('minuto médio do primeiro AC de cada time.', 'average minute of the first AC of each team.', 'minuto promedio del primer AC de cada equipo.')),
      li(T('Tent./AC', 'Tries/AC', 'Intentos/AC'), T('submissões até o AC, na média de quem resolveu.', 'submissions until the AC, on average, for solvers.', 'envíos hasta el AC, en promedio, para quienes resolvieron.')),
      li('Dirt', T('parte das submissões de quem RESOLVEU que estava errada. É a métrica do resolver do ICPC. Dirt alto: o problema pune erros. Dirt baixo com poucos ACs: o problema é difícil de pensar.',
        'the part of the SOLVERS\u2019 submissions that was wrong. This is the ICPC resolver metric. High dirt: the problem punishes mistakes. Low dirt with few ACs: the problem is hard to think.',
        'la parte de los envíos de QUIENES RESOLVIERON que fue incorrecta. Esta es la métrica del resolver ICPC. Dirt alto: el problema castiga los errores. Dirt bajo con pocos AC: el problema es difícil de pensar.')),
      li(T('Língua', 'Language', 'Lenguaje'), T('linguagens dos ACs.', 'languages of the ACs.', 'lenguajes de los AC.'))));
}

// statsSections(s, opts) -> [elementos] na ordem da página.
// opts.probMap: {problem_id: letra} opcional (o cache já traz short_name; o mapa só cobre
// contest legado cujo history guarda o offset interno).
export function statsSections(s, opts = {}) {
  const probMap = Object.assign({}, opts.probMap || {});
  (s.problems || []).forEach((p) => { if (p.short_name) probMap[p.problem_id] = p.short_name; });
  const shortOf = (pid) => probMap[pid] || pid;
  const out = [];

  // fatia de RECORTE (view:true no regions.json — supersede/femininos): sobrepõe as sedes
  // de propósito; quem soma fatia a fatia contaria times em dobro. O aviso viaja com o
  // módulo (página de estatísticas E relatório offline).
  if (s.view) {
    out.push(el('div', { class: 'section', style: 'background:var(--card-bg,#f5f7fb);border-left:4px solid var(--warn,#a66a00);padding:.5rem .8rem' },
      el('b', {}, T('◈ Recorte sobreposto', '◈ Overlapping view', '◈ Recorte superpuesto')),
      el('span', { class: 'small' },
        T(': esta fatia agrega times que também aparecem nas sedes. Não some fatias com sedes. Os times contariam duas vezes.',
          ': this slice aggregates teams that also appear under their sites. Do not add slices to sites. The teams would count twice.',
          ': esta porción agrega equipos que también aparecen bajo sus sedes. No sumes porciones a las sedes. Los equipos contarían dos veces.'))));
  }
  out.push(totalsCards(s.totals || {}));
  out.push(highlights(s, shortOf));

  out.push(el('div', { class: 'section' }, el('h2', {}, T('Por problema', 'By problem', 'Por problema')),
    problemsTable(s.problems || [], shortOf),
    problemsLegend(),
    el('div', { class: 'two-col', style: 'margin-top:1rem' },
      el('div', {}, el('div', { class: 'chart-title' }, T('Submissões por problema', 'Submissions by problem', 'Envíos por problema')),
        barChart((s.problems || []).map((p) => ({ label: shortOf(p.problem_id), value: p.submissions })), { rotateLabels: true })),
      el('div', {}, el('div', { class: 'chart-title' }, T('Resolvedores por problema', 'Solvers by problem', 'Resolvedores por problema')),
        barChart((s.problems || []).map((p) => ({ label: shortOf(p.problem_id), value: p.solved })), { rotateLabels: true })))));

  const AN = anFrom(s, opts);
  const race = problemRace(s, shortOf, AN); if (race) out.push(race);
  out.push(balloonsSection(s.problems, shortOf));

  const totSubs = (s.totals || {}).submissions || 0;
  out.push(el('div', { class: 'section' }, el('h2', {}, T('Veredictos e linguagens', 'Verdicts and languages', 'Veredictos y lenguajes')),
    el('div', { class: 'two-col' },
      el('div', {}, el('div', { class: 'chart-title' }, T('Distribuição de veredictos', 'Verdict distribution', 'Distribución de veredictos')),
        hBarChart((s.verdicts || []).map((v) => ({ label: v.verdict, value: v.count })), { hideZero: true, total: totSubs }),
        el('div', { class: 'small muted', style: 'text-align:center; margin-top:.35rem' }, T('cada barra = % das ', 'each bar = % of the ', 'cada barra = % de los ') + totSubs + T(' submissões', ' submissions', ' envíos'))),
      el('div', {}, el('div', { class: 'chart-title' }, T('Linguagens mais usadas', 'Most used languages', 'Lenguajes más usados')),
        hBarChart((s.languages || []).map((l) => ({ label: l.lang, value: l.submissions })), { hideZero: true, total: totSubs }),
        langTable(s.languages || []))),
    el('h3', { style: 'margin:1.2rem 0 .3rem' }, T('Veredictos por problema', 'Verdicts by problem', 'Veredictos por problema')), verdictMatrix(s, shortOf)));

  if ((s.timeline || []).length) {
    out.push(el('div', { class: 'section' }, el('h2', {}, T('Linha do tempo', 'Timeline', 'Línea de tiempo')),
      el('div', { class: 'chart-title' }, T('Submissões ao longo do tempo (por 10 min)', 'Submissions over time (per 10 min)', 'Envíos a lo largo del tiempo (cada 10 min)')),
      barChart(s.timeline.map((t) => ({ label: t.minute + 'm', value: t.submissions })), { rotateLabels: true }),
      el('div', { class: 'chart-title', style: 'margin-top:.6rem' }, T('Aceitas ao longo do tempo', 'Accepted over time', 'Aceptados a lo largo del tiempo')),
      barChart(s.timeline.map((t) => ({ label: t.minute + 'm', value: t.accepted })), { rotateLabels: true }),
      el('div', { class: 'chart-title', style: 'margin-top:.6rem' }, T('Aceitas acumuladas', 'Cumulative accepted', 'Aceptadas acumuladas')),
      lineChart((() => { let c = 0; return s.timeline.map((t) => ({ label: t.minute + 'm', y: (c += t.accepted) })); })())));
  }

  const q = quartiles(expandSolves(s.problems_solved_dist));
  const distSec = el('div', { class: 'section' }, el('h2', {}, T('Distribuição de desempenho', 'Performance distribution', 'Distribución de desempeño')));
  if (q) {
    distSec.append(el('p', { class: 'muted small' }, q.n + T(' participantes. Quartis por nº de problemas resolvidos:', ' participants. Quartiles by number of problems solved:', ' participantes. Cuartiles por cantidad de problemas resueltos:')),
      el('div', { class: 'stat-cards' },
        el('div', { class: 'stat-card' }, el('div', { class: 'big-num' }, '≥' + q.top25), el('div', { class: 'big-sub' }, T('top 25% resolveu', 'top 25% solved', 'top 25% resolvió'))),
        el('div', { class: 'stat-card' }, el('div', { class: 'big-num' }, String(q.median)), el('div', { class: 'big-sub' }, T('mediana (50%)', 'median (50%)', 'mediana (50%)'))),
        el('div', { class: 'stat-card' }, el('div', { class: 'big-num' }, '≥' + q.bottom25), el('div', { class: 'big-sub' }, T('75% resolveu ao menos', '75% solved at least', '75% resolvió al menos'))),
        el('div', { class: 'stat-card' }, el('div', { class: 'big-num' }, q.max + ' / ' + q.min), el('div', { class: 'big-sub' }, T('máx / mín resolvidos', 'max / min solved', 'máx. / mín. resueltos')))));
  }
  distSec.append(el('div', { class: 'two-col', style: 'margin-top:.6rem' },
    el('div', {}, el('div', { class: 'chart-title' }, T('Participantes por nº de problemas resolvidos', 'Participants by number of problems solved', 'Participantes por cantidad de problemas resueltos')),
      barChart((s.problems_solved_dist || []).map((d) => ({ label: String(d.solved), value: d.users })))),
    el('div', {}, el('div', { class: 'chart-title' }, T('Tentativas até resolver', 'Attempts until solved', 'Intentos hasta resolver')),
      barChart((s.attempts_dist || []).map((d) => ({ label: String(d.attempts), value: d.count }))))));
  out.push(distSec);
  const cmp = teamCompare(s, AN); if (cmp) out.push(cmp);
  const perf = performanceSection(s, AN); if (perf) out.push(perf);
  return out;
}
