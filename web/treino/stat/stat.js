// treino/stat/stat.js — PERFIL PÚBLICO / dashboard de estatísticas de um usuário do treino.
// Lê ?user=<login>; cabeçalho compacto (avatar, membro desde, editor, último envio) + cartões
// + grade de gráficos (SVG, sem libs) + conquistas + histórico PAGINADO com filtros.
// Tudo calculado no cliente a partir de:
//   GET /treino/history-full?user=  (TXT, 7 campos: time:user:probid:lang:verdict:epoch:subid)
//   GET /treino/problems            (títulos, tags, coleções, contagens p/ dificuldade)
//   GET /treino/profile?user=       (cabeçalho + privacidade + created_at)
//   GET /treino/editors             (ranking do editor favorito)
// O Bearer vai sempre que houver login (não só p/ o dono): o servidor decide o que mostrar —
// é o que permite ao .admin ver perfil privado (privilégio que a API já dava).
import { apiGet, apiGetText } from '/shared/api.js';
import { status } from '/shared/auth.js';
import { el, verdictClass, isPending, renderAuthArea, resumoText, avatarEl, colorFromName } from '/shared/ui.js';
import { editorLabel } from '/shared/editors.js';
import { hBarChart, lineChart, heatmap, heatmapGrid, verdictColor } from '/lib/charts.js';
import { langById } from '/shared/languages.js';
import { logLink, srcLink } from '/shared/submission-links.js';
import { T } from '/shared/i18n.js';

const CONTEST = 'treino';
const HPAGE = 25;
const qs = new URLSearchParams(location.search);
const USER = qs.get('user') || '';

let problemsById = {};
let history = [];
let subSumm = {};               // resumo (testes/pontos) por subid, do /submission/summary
let canLog = false;             // só vê cód/log se for o dono e estiver logado
let isOwner = false;

// estado do histórico paginado
let histPage = 0, histQ = '', histVerd = '', histLang = '';
let sortKey = 'date', sortAsc = false;

// ---- parsing ----------------------------------------------------------------
function normVerdict(s) {
  s = (s || '').trim();
  if (/^accepted/i.test(s)) return 'Accepted';
  if (/^wrong/i.test(s)) return 'Wrong Answer';
  if (/^time limit/i.test(s)) return 'Time Limit Exceeded';
  if (/^(possible runtime|runtime)/i.test(s)) return 'Runtime Error';
  if (/^(compilation error|language)/i.test(s)) return 'Compilation Error';
  return s.replace(/,.*/, '').replace(/\s*\|.*/, '').trim();
}
function parseLine(line) {
  const p = line.split(':');
  if (p.length < 7) return null;
  return {
    min: p[0], login: p[1], probid: p[2], lang: p[3],
    verdict: p.slice(4, p.length - 2).join(':'),
    epoch: parseInt(p[p.length - 2], 10) || 0, subid: p[p.length - 1],
  };
}
const pad2 = (n) => String(n).padStart(2, '0');
const dayTag = (epoch) => { const d = new Date(epoch * 1000); return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()); };
const dayTagD = (d) => d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate());
// rótulo amigável da linguagem a partir da EXTENSÃO gravada no history (py3/cc/bash/…);
// desconhecida fica literal (não usar o fallback generoso do langByExt, que viraria "C")
const LANG_ALIAS = { bash: 'sh', python: 'py', kts: 'kt', cc: 'cpp', cxx: 'cpp', py3: 'py', py2: 'py' };
const langLabel = (id) => {
  const e = String(id || '').toLowerCase();
  return langById(LANG_ALIAS[e] || e).label;
};
const probURL = (pid) => '/treino/problema/?id=' + encodeURIComponent(pid);
const norm = (s) => (s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');

// data compacta: hoje/ontem hh:mm · há N dias · dd/mm/aa hh:mm
function fmtWhen(epoch) {
  const d = new Date(epoch * 1000), now = new Date();
  const d0 = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  const t0 = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const dd = Math.round((t0 - d0) / 86400000);
  const hm = pad2(d.getHours()) + ':' + pad2(d.getMinutes());
  if (dd <= 0) return T('hoje ', 'today ') + hm;
  if (dd === 1) return T('ontem ', 'yesterday ') + hm;
  if (dd < 7) return T(`há ${dd} dias`, `${dd} days ago`);
  return pad2(d.getDate()) + '/' + pad2(d.getMonth() + 1) + '/' + String(d.getFullYear()).slice(2) + ' ' + hm;
}
function fmtAgoDays(epoch) {
  const dd = Math.floor((Date.now() / 1000 - epoch) / 86400);
  if (dd <= 0) return T('hoje', 'today');
  if (dd === 1) return T('ontem', 'yesterday');
  if (dd < 30) return T(`há ${dd} dias`, `${dd} days ago`);
  const m = Math.floor(dd / 30);
  return T(`há ${m} mês(es)`, `${m} month(s) ago`);
}
const MONTHS_PT = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
const MONTHS_EN = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
function fmtMonthYear(epoch) {
  const d = new Date(epoch * 1000);
  return T(MONTHS_PT[d.getMonth()], MONTHS_EN[d.getMonth()]) + '/' + d.getFullYear();
}

// ---- cálculo das estatísticas ----------------------------------------------
function computeStats() {
  const probStats = {}, verdictStats = {}, dayStats = {}, langStats = {};
  const hdStats = Array.from({ length: 7 }, () => new Array(24).fill(0));   // dia × hora
  const resolved = {}, attempted = {}, lastTry = {};
  const byProbAsc = history.slice().sort((a, b) => a.epoch - b.epoch);

  const firstAcOrder = {};   // probid -> nº de submissões até (e incluindo) o 1º AC
  const seenCount = {};      // probid -> submissões vistas até agora
  const solvedAtFirst = {};  // probid -> bool (AC já na 1ª submissão)
  const solvedDate = {};     // probid -> epoch do 1º AC (p/ curva cumulativa)

  byProbAsc.forEach(s => {
    const nv = normVerdict(s.verdict);
    seenCount[s.probid] = (seenCount[s.probid] || 0) + 1;
    if (!probStats[s.probid]) probStats[s.probid] = { tried: 0, accepted: 0 };
    probStats[s.probid].tried++;
    attempted[s.probid] = true;
    lastTry[s.probid] = s;                                   // ascendente -> fica a última
    if (nv === 'Accepted') {
      probStats[s.probid].accepted++;
      if (!resolved[s.probid]) {
        resolved[s.probid] = true;
        firstAcOrder[s.probid] = seenCount[s.probid];
        solvedAtFirst[s.probid] = seenCount[s.probid] === 1;
        solvedDate[s.probid] = s.epoch;
      }
    }
    verdictStats[nv] = (verdictStats[nv] || 0) + 1;
    const dt = dayTag(s.epoch);
    dayStats[dt] = (dayStats[dt] || 0) + 1;
    const d = new Date(s.epoch * 1000);
    hdStats[d.getDay()][d.getHours()]++;
    // linguagem: ignora erros de compilação/linguagem (não refletem skill na linguagem)
    if (!/^(Language|Compilation Error)/i.test(s.verdict)) {
      if (!langStats[s.lang]) langStats[s.lang] = { total: 0, accepted: 0 };
      langStats[s.lang].total++;
      if (nv === 'Accepted') langStats[s.lang].accepted++;
    }
  });

  // tags (cruzando com /treino/problems)
  const tagStats = {};
  Object.keys(attempted).forEach(pid => {
    const p = problemsById[pid];
    if (!p || !p.tags) return;
    p.tags.forEach(raw => {
      const tg = String(raw).replace(/^#+/, '');
      if (!tagStats[tg]) tagStats[tg] = { resolved: 0, attempted: 0 };
      if (resolved[pid]) tagStats[tg].resolved++;
      tagStats[tg].attempted++;
    });
  });

  const distintos = Object.keys(probStats).length;
  const acertos = Object.values(probStats).filter(p => p.accepted > 0).length;
  return {
    probStats, verdictStats, dayStats, langStats, tagStats, hdStats,
    distintos, acertos, firstAcOrder, solvedAtFirst, solvedDate, resolved, attempted, lastTry,
  };
}

// streak de dias consecutivos com >=1 submissão (termina hoje ou ontem)
function computeStreaks(dayStats) {
  const days = Object.keys(dayStats).sort();           // 'YYYY-MM-DD' ascendente
  if (!days.length) return { current: 0, longest: 0 };
  const set = new Set(days);
  let longest = 0, run = 0, prev = null;
  for (const d of days) {
    if (prev && (new Date(d) - new Date(prev)) === 86400000) run++;
    else run = 1;
    longest = Math.max(longest, run);
    prev = d;
  }
  let cur = 0;
  const today = new Date(); today.setHours(0, 0, 0, 0);
  let probe = new Date(today);
  if (!set.has(dayTagD(probe))) probe.setDate(probe.getDate() - 1); // tolera "ainda não enviou hoje"
  while (set.has(dayTagD(probe))) { cur++; probe.setDate(probe.getDate() - 1); }
  return { current: cur, longest };
}

// dificuldade derivada da taxa global do problema (mesmas faixas do /treino)
function diffOf(p) {
  const a = p.attempted_count || 0;
  if (!a) return null;
  const r = (p.solved_count || 0) / a;
  return r >= 0.9 ? 'veasy' : r >= 0.7 ? 'easy' : r >= 0.5 ? 'med' : 'hard';
}
const DIFF_META = {
  veasy: { pt: 'muito fácil', en: 'very easy', color: '#15803d' },
  easy:  { pt: 'fácil', en: 'easy', color: '#4ca464' },
  med:   { pt: 'médio', en: 'medium', color: '#9a6700' },
  hard:  { pt: 'difícil', en: 'hard', color: '#be1241' },
};

// progresso por coleção: nome -> {total, mine}
function collProgress(stats) {
  const m = new Map();
  Object.values(problemsById).forEach(p => {
    (p.collections || []).forEach(c => {
      if (!m.has(c)) m.set(c, { total: 0, mine: 0 });
      const e = m.get(c);
      e.total++;
      if (stats.resolved[p.id]) e.mine++;
    });
  });
  return m;
}

// ---- métricas (cartões) -----------------------------------------------------
function renderQuickStats(stats) {
  const total = history.length;
  const acertos = stats.acertos;
  const aceitas = stats.verdictStats['Accepted'] || 0;
  const taxa = total ? Math.round(100 * aceitas / total) : 0;

  const ords = Object.values(stats.firstAcOrder);
  const mediaTent = ords.length ? (ords.reduce((a, b) => a + b, 0) / ords.length).toFixed(1) : '—';
  const firstTryCount = Object.values(stats.solvedAtFirst).filter(Boolean).length;
  const firstTryPct = acertos ? Math.round(100 * firstTryCount / acertos) : 0;
  const { current: curStreak, longest: maxStreak } = computeStreaks(stats.dayStats);
  const langKeys = Object.keys(stats.langStats);
  const mostUsed = langKeys.slice().sort((a, b) => stats.langStats[b].total - stats.langStats[a].total)[0];

  const box = document.getElementById('quickStats'); box.innerHTML = '';
  const card = (n, label, hl) => el('div', { class: 'stat-card' + (hl ? ' hl' : '') },
    el('div', { class: 'n' }, String(n)), el('div', { class: 'lbl' }, label));
  box.append(
    card(acertos, T('problemas resolvidos', 'problems solved'), true),
    card(total, T('submissões', 'submissions'), true),
    card(taxa + '%', T('taxa de acerto', 'acceptance rate')),
    card(firstTryPct + '%', T('AC na 1ª tentativa', 'AC on first try')),
    card(mediaTent, T('tentativas até resolver', 'attempts to solve')),
    card(curStreak, T('streak atual (dias)', 'current streak (days)')),
    card('🔥 ' + maxStreak, T('maior streak (dias)', 'longest streak (days)')),
    card(mostUsed ? langLabel(mostUsed) : '—', T('linguagem preferida', 'favorite language')),
  );
}

// ---- conquistas -------------------------------------------------------------
function computeAchievements(stats) {
  const acertos = stats.acertos;
  const { longest } = computeStreaks(stats.dayStats);
  const nLangs = Object.keys(stats.langStats).length;
  const oneShots = Object.values(stats.solvedAtFirst).filter(Boolean).length;
  let fullColl = null;
  for (const [name, e] of collProgress(stats)) {
    if (e.total >= 10 && e.mine === e.total) { fullColl = name; break; }
  }
  const missing = (n, goal) => T(`faltam ${goal - n}`, `${goal - n} to go`);
  return [
    { icon: '🌱', label: T('Primeiro AC', 'First AC'), got: acertos >= 1 },
    { icon: '🔥', label: T('Streak 7 dias', '7-day streak'), got: longest >= 7, sub: longest < 7 ? `${longest}/7` : '' },
    { icon: '🔥', label: T('Streak 30 dias', '30-day streak'), got: longest >= 30, sub: longest < 30 ? `${longest}/30` : '' },
    { icon: '💻', label: T('Poliglota (5 linguagens)', 'Polyglot (5 languages)'), got: nLangs >= 5, sub: nLangs < 5 ? `${nLangs}/5` : '' },
    { icon: '🏆', label: fullColl ? T(`Coleção completa: ${fullColl}`, `Collection complete: ${fullColl}`) : T('Coleção completa (≥10)', 'Complete a collection (≥10)'), got: !!fullColl },
    { icon: '🎯', label: T('25 one-shots (AC de primeira)', '25 one-shots (first-try AC)'), got: oneShots >= 25, sub: oneShots < 25 ? `${oneShots}/25` : `×${oneShots}` },
    { icon: '⭐', label: T('Meio-centurião (50 resolvidos)', 'Half-centurion (50 solved)'), got: acertos >= 50, sub: acertos < 50 ? missing(acertos, 50) : '' },
    { icon: '🏅', label: T('Centurião (100 resolvidos)', 'Centurion (100 solved)'), got: acertos >= 100, sub: acertos < 100 ? missing(acertos, 100) : '' },
  ];
}

// ---- dashboard --------------------------------------------------------------
function chartCard(title, ...nodes) {
  return el('div', { class: 'subcard' }, el('h3', {}, title), ...nodes);
}
const wideWrap = (node, minw) => el('div', { class: 'chart-wrap' }, el('div', { style: `min-width:${minw}px;width:max-content;max-width:100%` }, node));

function renderDashboard(stats) {
  const dash = document.getElementById('dashboard');
  dash.innerHTML = '';

  // linha cumulativa | heatmap + punchcard
  const solvedDates = Object.values(stats.solvedDate).sort((a, b) => a - b);
  let lineNode;
  if (solvedDates.length) {
    let acc = 0;
    const pts = solvedDates.map(epoch => ({ x: new Date(epoch * 1000), y: ++acc }));
    pts.push({ x: new Date(), y: acc, label: T('hoje', 'today') });
    lineNode = wideWrap(lineChart(pts, { width: 640, height: 230, color: '#1a7f37', maxLabels: 6 }), 480);
  } else {
    lineNode = el('div', { class: 'muted small' }, T('Nenhum problema resolvido ainda.', 'No problems solved yet.'));
  }
  const punchCells = [];
  stats.hdStats.forEach((row, dow) => row.forEach((n, hour) => { if (n) punchCells.push({ dow, hour, value: n, n }); }));
  dash.append(el('div', { class: 'duo' },
    chartCard(T('📈 Resolvidos ao longo do tempo', '📈 Solved over time'), lineNode),
    chartCard(T('🔥 Atividade (26 semanas)', '🔥 Activity (26 weeks)'),
      el('div', { class: 'chart-wrap' }, heatmap(stats.dayStats, { weeks: 26, color: '#216097' })),
      el('h3', { style: 'margin-top:.8rem' }, T('🕐 Ritmo (dia × hora)', '🕐 Rhythm (day × hour)')),
      el('div', { class: 'chart-wrap' },
        heatmapGrid(punchCells, { cell: 12, gap: 3, color: '#6d5cff', fmt: (v) => v + T(' envios', ' submissions') })))));

  // veredictos | linguagens
  const vEntries = Object.entries(stats.verdictStats).sort((a, b) => b[1] - a[1]);
  const langs = Object.keys(stats.langStats).sort((a, b) => stats.langStats[b].total - stats.langStats[a].total);
  const langTable = (() => {
    if (!langs.length) return el('div', { class: 'muted small' }, T('Sem dados.', 'No data.'));
    const tb = el('tbody');
    langs.forEach(l => {
      const s = stats.langStats[l];
      const rate = Math.round(100 * s.accepted / Math.max(1, s.total));
      tb.append(el('tr', {},
        el('td', {}, langLabel(l)), el('td', {}, String(s.total)), el('td', {}, String(s.accepted)),
        el('td', {}, el('b', { style: 'color:' + (rate >= 60 ? 'var(--ok)' : rate >= 30 ? 'var(--warn)' : 'var(--err)') }, rate + '%'))));
    });
    return el('table', { class: 'moj', style: 'margin-top:.7rem;font-size:.85rem' },
      el('thead', {}, el('tr', {}, el('th', {}, T('Linguagem', 'Language')), el('th', {}, 'Subs'), el('th', {}, 'AC'), el('th', {}, T('Taxa', 'Rate')))), tb);
  })();
  dash.append(el('div', { class: 'duo' },
    chartCard(T('🎯 Veredictos', '🎯 Verdicts'),
      hBarChart(vEntries.map(([k, v]) => ({ label: k, value: v, color: verdictColor(k) })))),
    chartCard(T('💻 Linguagens', '💻 Languages'),
      hBarChart(langs.map(l => ({ label: langLabel(l), value: stats.langStats[l].total, color: '#6d5cff' }))),
      langTable)));

  // dificuldade | coleções
  const dcounts = { veasy: 0, easy: 0, med: 0, hard: 0 };
  Object.keys(stats.resolved).forEach(pid => {
    const p = problemsById[pid]; if (!p) return;
    const k = diffOf(p); if (k) dcounts[k]++;
  });
  // ordena por VOLUME resolvido (percentual primeiro escondia o progresso grande atrás de
  // coleçõezinhas 3/3); completas desempatam na frente
  const collRows = [...collProgress(stats)]
    .filter(([, e]) => e.mine > 0)
    .sort((a, b) => b[1].mine - a[1].mine
      || (b[1].mine === b[1].total ? 1 : 0) - (a[1].mine === a[1].total ? 1 : 0))
    .slice(0, 6);
  const collBox = collRows.length
    ? el('div', { style: 'display:flex;flex-direction:column;gap:.55rem' }, ...collRows.map(([name, e]) => {
        const done = e.mine === e.total;
        return el('div', {},
          el('div', { class: 'row', style: 'justify-content:space-between' },
            el('a', { class: 'collection', href: '/treino/?searchcol=' + encodeURIComponent(name) }, name),
            done ? el('span', { class: 'small', style: 'color:var(--ok);font-weight:700' }, `${e.mine}/${e.total} ✓`)
              : el('span', { class: 'small muted' }, `${e.mine}/${e.total}`)),
          el('div', { class: 'pbar' + (done ? ' done' : '') },
            el('i', { style: `width:${Math.round(100 * e.mine / e.total)}%` })));
      }))
    : el('div', { class: 'muted small' }, T('Nenhuma coleção iniciada.', 'No collection started.'));
  dash.append(el('div', { class: 'duo' },
    chartCard(T('🧗 Dificuldade dos resolvidos', '🧗 Difficulty of solved'),
      el('p', { class: 'small muted', style: 'margin:.1rem 0 .5rem' },
        T('derivada da taxa de acerto de cada problema', 'derived from each problem’s acceptance rate')),
      hBarChart(Object.entries(dcounts).filter(([, v]) => v > 0)
        .map(([k, v]) => ({ label: T(DIFF_META[k].pt, DIFF_META[k].en), value: v, color: DIFF_META[k].color })))),
    chartCard(T('📚 Progresso por coleção', '📚 Progress by collection'), collBox)));

  // tags | em aberto
  const tags = Object.keys(stats.tagStats).filter(t => stats.tagStats[t].resolved > 0)
    .sort((a, b) => stats.tagStats[b].resolved - stats.tagStats[a].resolved || a.localeCompare(b)).slice(0, 12);
  const openPids = Object.keys(stats.attempted).filter(pid => !stats.resolved[pid])
    .sort((a, b) => stats.lastTry[b].epoch - stats.lastTry[a].epoch);
  const openBox = openPids.length
    ? el('div', { style: 'display:flex;flex-direction:column;gap:.3rem' },
        ...openPids.slice(0, 6).map(pid => {
          const s = stats.lastTry[pid];
          return el('div', { class: 'row', style: 'gap:.4rem' },
            el('a', { href: probURL(pid) }, titleOf(pid)),
            el('span', { class: 'small muted' }, `· ${stats.probStats[pid].tried} ${T('tentativa(s)', 'attempt(s)')} · ${fmtAgoDays(s.epoch)}`),
            el('span', { style: 'flex:1' }),
            el('span', { class: 'verdict ' + verdictClass(s.verdict), style: 'font-size:.75rem;padding:.15rem .5rem' }, normVerdict(s.verdict)));
        }),
        openPids.length > 6 ? el('span', { class: 'small muted' },
          T(`…e mais ${openPids.length - 6} em aberto.`, `…and ${openPids.length - 6} more open.`)) : null)
    : el('div', { class: 'muted small' }, T('Nada em aberto — tudo que tentou, resolveu. 👏', 'Nothing open — everything attempted was solved. 👏'));
  dash.append(el('div', { class: 'duo' },
    chartCard(T('🏷️ Forças por tag (resolvidos)', '🏷️ Strengths by tag (solved)'),
      tags.length ? hBarChart(tags.map(t => ({ label: '#' + t, value: stats.tagStats[t].resolved, color: '#216097' })))
        : el('div', { class: 'muted small' }, T('Nenhum resolvido ainda.', 'None solved yet.'))),
    chartCard(T('⏳ Em aberto (tentados sem AC)', '⏳ Open (attempted, unsolved)'), openBox)));

  // conquistas
  const ach = computeAchievements(stats);
  const strip = el('div', { class: 'badge-strip' });
  ach.filter(a => a.got).forEach(a => strip.append(el('span', { class: 'abadge' }, `${a.icon} ${a.label}` + (a.sub ? ` ${a.sub}` : ''))));
  ach.filter(a => !a.got).forEach(a => strip.append(el('span', { class: 'abadge lock' }, `🔒 ${a.label}` + (a.sub ? ` — ${a.sub}` : ''))));
  dash.append(el('div', { class: 'section' }, el('h2', {}, T('🏅 Conquistas', '🏅 Achievements')), strip));

  // histórico paginado
  const sec = el('div', { class: 'section' }, el('h2', {}, T('📜 Histórico de submissões', '📜 Submission history')));
  sec.append(buildHistBar(), el('div', { id: 'histPagerTop', class: 'row', style: 'margin:.4rem 0' }),
    el('div', { id: 'histTable', class: 'chart-wrap' }),
    el('div', { id: 'histPagerBot', class: 'row', style: 'margin-top:.6rem;justify-content:center' }));
  dash.append(sec);
  renderHistory();
}

// ---- histórico paginado + filtros -------------------------------------------
function titleOf(pid) { const p = problemsById[pid]; return (p && (p.title || p.full_name)) || pid; }

function buildHistBar() {
  const verds = [...new Set(history.map(s => normVerdict(s.verdict)))].sort();
  const langs = [...new Set(history.map(s => s.lang))].sort();
  const q = el('input', { placeholder: T('🔎 filtrar por problema…', '🔎 filter by problem…'),
    oninput: () => { histQ = q.value; histPage = 0; renderHistory(); } });
  const sv = el('select', { onchange: () => { histVerd = sv.value; histPage = 0; renderHistory(); } },
    el('option', { value: '' }, T('Veredicto: todos', 'Verdict: all')),
    ...verds.map(v => el('option', { value: v }, v)));
  const sl = el('select', { onchange: () => { histLang = sl.value; histPage = 0; renderHistory(); } },
    el('option', { value: '' }, T('Linguagem: todas', 'Language: all')),
    ...langs.map(l => el('option', { value: l }, langLabel(l))));
  return el('div', { class: 'histbar' }, q, sv, sl, el('span', { id: 'histCount', class: 'small muted' }));
}
function filteredHist() {
  const qn = norm(histQ.trim());
  return history.filter(s =>
    (!qn || norm(titleOf(s.probid)).includes(qn))
    && (!histVerd || normVerdict(s.verdict) === histVerd)
    && (!histLang || s.lang === histLang));
}
function histPager(box, pages) {
  box.innerHTML = '';
  if (pages <= 1) return;
  box.style.justifyContent = 'center';
  box.append(
    el('button', { class: 'btn ghost', onclick: () => { if (histPage > 0) { histPage--; renderHistory(); } } }, '‹'),
    el('span', { class: 'small' }, ` ${T('página', 'page')} ${histPage + 1} / ${pages} `),
    el('button', { class: 'btn ghost', onclick: () => { if (histPage < pages - 1) { histPage++; renderHistory(); } } }, '›'));
}
function renderHistory() {
  const box = document.getElementById('histTable');
  if (!box) return;
  const rows = filteredHist().sort((a, b) => {
    if (sortKey === 'date') return sortAsc ? a.epoch - b.epoch : b.epoch - a.epoch;
    if (sortKey === 'problem') return sortAsc ? titleOf(a.probid).localeCompare(titleOf(b.probid)) : titleOf(b.probid).localeCompare(titleOf(a.probid));
    if (sortKey === 'lang') return sortAsc ? (a.lang || '').localeCompare(b.lang || '') : (b.lang || '').localeCompare(a.lang || '');
    if (sortKey === 'status') return sortAsc ? normVerdict(a.verdict).localeCompare(normVerdict(b.verdict)) : normVerdict(b.verdict).localeCompare(normVerdict(a.verdict));
    return 0;
  });
  const cnt = document.getElementById('histCount');
  if (cnt) cnt.textContent = `${rows.length} ${T('envio(s)', 'submission(s)')}`;
  box.innerHTML = '';
  if (!rows.length) {
    box.innerHTML = '<span class="muted small">' + T('Nenhuma submissão casa com os filtros.', 'No submission matches the filters.') + '</span>';
    histPager(document.getElementById('histPagerTop'), 0);
    histPager(document.getElementById('histPagerBot'), 0);
    return;
  }
  const pages = Math.max(1, Math.ceil(rows.length / HPAGE));
  if (histPage >= pages) histPage = 0;
  const slice = rows.slice(histPage * HPAGE, histPage * HPAGE + HPAGE);

  const arrow = (k) => sortKey === k ? (sortAsc ? ' ▲' : ' ▼') : '';
  const th = (label, k, cls) => el('th', { class: cls || '', onclick: () => { sortAsc = (sortKey === k) ? !sortAsc : false; sortKey = k; renderHistory(); } }, label + arrow(k));
  const head = el('thead', {}, el('tr', {},
    th(T('Quando', 'When'), 'date'), th(T('Problema', 'Problem'), 'problem'),
    th(T('Linguagem', 'Language'), 'lang', 'hide-m'),
    canLog ? el('th', { class: 'hide-m' }, T('Cód/Log', 'Code/Log')) : null,
    th('Status', 'status')));
  const tb = el('tbody');
  slice.forEach(s => {
    const pending = isPending(s.verdict);
    const logTd = canLog ? el('td', { class: 'small hide-m', style: 'white-space:nowrap' },
      srcLink(CONTEST, { id: s.subid, sub_epoch: s.epoch, lang: s.lang }, T('cód', 'code')), ' · ',
      logLink(CONTEST, { id: s.subid, sub_epoch: s.epoch }, 'log')) : null;
    tb.append(el('tr', {},
      el('td', { class: 'small', style: 'white-space:nowrap' }, fmtWhen(s.epoch)),
      el('td', {}, el('a', { href: probURL(s.probid) }, titleOf(s.probid))),
      el('td', { class: 'hide-m' }, langLabel(s.lang)),
      logTd,
      (() => { const rtxt = pending ? '' : resumoText(subSumm[s.subid]);
        return el('td', {}, el('span', { class: 'verdict ' + verdictClass(s.verdict) }, pending ? el('span', {}, el('span', { class: 'spin' }), ' ' + s.verdict) : s.verdict),
          rtxt ? el('div', { class: 'small muted', style: 'margin-top:.15rem' }, rtxt) : ''); })()));
  });
  box.append(el('table', { class: 'moj' }, head, tb));
  histPager(document.getElementById('histPagerTop'), pages);
  histPager(document.getElementById('histPagerBot'), pages);
}

// ---- cabeçalho de perfil ----------------------------------------------------
// ranking do editor favorito a partir de /treino/editors (best-effort, assíncrono)
async function editorRankLine(editorId) {
  if (!editorId) return null;
  let data;
  try { data = await apiGet('/treino/editors', { contest: CONTEST }); } catch { return null; }
  const list = (data && data.editors) || [];
  const label = editorLabel(editorId);
  const idx = list.findIndex(e => e.editor === editorId);
  if (idx < 0) return `💻 ${label}`;
  const rank = idx + 1;
  return `💻 ${label} — ` + T(`${rank}º mais usado`, `#${rank} most used`);
}

function renderProfileHeader(profile) {
  const head = document.getElementById('profileHead');
  head.innerHTML = '';
  const name = profile.name || USER;
  const meta = el('div', { class: 'profile-meta' },
    el('div', { class: 'pname' }, name, ' ', el('span', { class: 'plogin' }, '~' + (profile.login || USER))));
  const parts = [];
  if (profile.university) parts.push('🎓 ' + profile.university);
  if (profile.created_at) parts.push(T('🗓️ membro desde ', '🗓️ member since ') + fmtMonthYear(profile.created_at));
  const pline = el('div', { class: 'pline' }, parts.join(' · '));
  const edSpan = el('span', {});
  const lastSpan = el('span', { id: 'lastSub' });
  pline.append(edSpan, lastSpan);
  meta.append(pline);

  const actions = el('div', { class: 'profile-actions' });
  if (isOwner) actions.append(el('a', { class: 'btn ghost', href: '/treino/perfil/' }, T('✎ Editar perfil', '✎ Edit profile')));
  head.append(avatarEl(profile.login || USER, name, 72, profile.has_photo), meta, actions);

  if (profile.favorite_editor) {
    editorRankLine(profile.favorite_editor).then(line => {
      if (line) edSpan.textContent = (pline.textContent ? ' · ' : '') + line;
    });
  }
}
function fillLastSub() {
  const lastSpan = document.getElementById('lastSub');
  if (!lastSpan || !history.length) return;
  const last = history.reduce((a, s) => Math.max(a, s.epoch), 0);
  lastSpan.textContent = ' · ' + T('⚡ último envio ', '⚡ last submission ') + fmtAgoDays(last);
}

function renderPrivate(profile) {
  document.getElementById('quickStats').innerHTML = '';
  const head = document.getElementById('profileHead');
  head.innerHTML = '';
  head.append(
    el('span', { class: 'avatar-mini ini', style: 'width:72px;height:72px;font-size:1.8rem;background:' + colorFromName(USER) }, '🔒'),
    el('div', { class: 'profile-meta' },
      el('div', { class: 'pname' }, '~' + (profile.login || USER)),
      el('div', { class: 'private-box' }, T('🔒 Este perfil é privado.', '🔒 This profile is private.'))));
  document.getElementById('dashboard').innerHTML = '';
}

// ---- boot -------------------------------------------------------------------
async function boot() {
  await renderAuthArea(document.getElementById('authArea'), CONTEST, () => location.reload());

  if (!USER) {
    document.getElementById('profileHead').innerHTML =
      '<div class="error-box">' + T('Faltou informar <code>?user=&lt;login&gt;</code> na URL.', 'Missing <code>?user=&lt;login&gt;</code> in the URL.') + '</div>';
    return;
  }
  document.title = T('Perfil de ', 'Profile of ') + USER + ' — MOJ';

  const st = await status(CONTEST);
  const logged = !!st.logged_in;
  isOwner = !!(logged && st.login === USER);
  canLog = isOwner;

  // perfil + problemas + histórico EM PARALELO (o Bearer vai sempre que logado: o servidor
  // corta o que o visitante não pode ver; é o que dá ao .admin a visão de perfil privado)
  const [profileR, problemsR, histR] = await Promise.allSettled([
    apiGet('/treino/profile?user=' + encodeURIComponent(USER), { contest: CONTEST, auth: logged }),
    apiGet('/treino/problems', { contest: CONTEST }),
    apiGetText('/treino/history-full?user=' + encodeURIComponent(USER), { contest: CONTEST, auth: logged }),
  ]);

  if (profileR.status === 'rejected') {
    document.getElementById('profileHead').innerHTML =
      '<div class="error-box">' + T('Não foi possível carregar este perfil: ', 'Could not load this profile: ')
      + ((profileR.reason && profileR.reason.message) || T('erro', 'error')) + '</div>';
    return;
  }
  const profile = profileR.value || { login: USER, name: USER, is_public: true };

  if (profile.is_public === false && !isOwner) {
    renderPrivate(profile);
    return;
  }
  renderProfileHeader(profile);

  if (problemsR.status === 'fulfilled') {
    const j = problemsR.value;
    const arr = Array.isArray(j) ? j : (j.problems || j.data || []);
    arr.forEach(p => { problemsById[p.id || p.problem_id] = p; });
  }

  if (histR.status === 'rejected') {
    document.getElementById('dashboard').innerHTML =
      '<div class="section"><span class="error-box">' + T('Falha ao carregar o histórico.', 'Failed to load history.') + '</span></div>';
    return;
  }
  history = histR.value.split('\n').map(s => s.trim()).filter(Boolean).map(parseLine).filter(Boolean);

  if (!history.length) {
    document.getElementById('quickStats').innerHTML = '';
    document.getElementById('dashboard').innerHTML =
      '<div class="section"><span class="muted">' + T('Ainda não há submissões para mostrar estatísticas.', 'No submissions yet to show statistics.') + '</span></div>';
    return;
  }
  fillLastSub();

  const stats = computeStats();
  renderQuickStats(stats);
  renderDashboard(stats);

  // resumo (testes/pontos) das já julgadas — só p/ o dono; 300 mais recentes, lotes de 100
  // (URL curta). DEPOIS do primeiro render (não bloqueia a página); re-render ao chegar.
  if (isOwner) {
    const done = history.filter(s => !isPending(s.verdict)).slice().sort((a, b) => b.epoch - a.epoch).slice(0, 300).map(s => s.subid);
    (async () => {
      let got = false;
      for (let i = 0; i < done.length; i += 100) {
        try {
          Object.assign(subSumm, await apiGet('/submission/summary?contest=' + encodeURIComponent(CONTEST) + '&ids=' + done.slice(i, i + 100).join(','), { contest: CONTEST, auth: true }) || {});
          got = true;
        } catch { /* best-effort */ }
      }
      if (got) renderHistory();
    })();
  }
}
boot();
