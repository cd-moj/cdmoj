// treino/stat/stat.js — dashboard de estatísticas de um usuário do Treino Livre.
// Lê ?user=<login>; cabeçalho de perfil + métricas + gráficos (SVG, sem libs) +
// histórico. Tudo calculado no cliente a partir de:
//   GET /treino/history-full?user=  (TXT, 7 campos: time:user:probid:lang:verdict:epoch:subid)
//   GET /treino/problems            (títulos + tags)
//   GET /treino/profile?user=       (cabeçalho + privacidade)
//   GET /treino/editors             (ranking do editor favorito)
import { apiGet, apiGetText, getToken } from '/shared/api.js';
import { status } from '/shared/auth.js';
import { el, verdictClass, isPending, fmtDate, renderAuthArea } from '/shared/ui.js';
import { editorLabel } from '/shared/editors.js';
import { barChart, pieChart, lineChart, heatmap } from '/lib/charts.js';

const CONTEST = 'treino';
const qs = new URLSearchParams(location.search);
const USER = qs.get('user') || '';

let problemsById = {};
let history = [];
let sortKey = 'date', sortAsc = false;
let canLog = false;            // só vê cód/log se for o dono e estiver logado
let isOwner = false;

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

// ---- cálculo das estatísticas ----------------------------------------------
function computeStats() {
  const probStats = {}, verdictStats = {}, dayStats = {}, langStats = {}, dowStats = [0, 0, 0, 0, 0, 0, 0];
  const resolved = {}, attempted = {};
  const byProbAsc = history.slice().sort((a, b) => a.epoch - b.epoch);

  // 1ª submissão àquele problema: para "acerto na 1ª tentativa" e ordem de tentativas
  const firstAcOrder = {};   // probid -> nº de submissões até (e incluindo) o 1º AC
  const seenCount = {};      // probid -> submissões vistas até agora
  const solvedAtFirst = {};  // probid -> bool (AC já na 1ª submissão)
  const solvedDate = {};     // probid -> epoch do 1º AC (p/ curva cumulativa)

  byProbAsc.forEach(s => {
    const norm = normVerdict(s.verdict);
    seenCount[s.probid] = (seenCount[s.probid] || 0) + 1;
    if (!probStats[s.probid]) probStats[s.probid] = { tried: 0, accepted: 0 };
    probStats[s.probid].tried++;
    attempted[s.probid] = true;
    if (norm === 'Accepted') {
      probStats[s.probid].accepted++;
      if (!resolved[s.probid]) {
        resolved[s.probid] = true;
        firstAcOrder[s.probid] = seenCount[s.probid];
        solvedAtFirst[s.probid] = seenCount[s.probid] === 1;
        solvedDate[s.probid] = s.epoch;
      }
    }
    verdictStats[norm] = (verdictStats[norm] || 0) + 1;
    const dt = dayTag(s.epoch);
    dayStats[dt] = (dayStats[dt] || 0) + 1;
    dowStats[new Date(s.epoch * 1000).getDay()]++;
    // linguagem: ignora erros de compilação/linguagem (não refletem skill na linguagem)
    if (!/^(Language|Compilation Error)/i.test(s.verdict)) {
      if (!langStats[s.lang]) langStats[s.lang] = { total: 0, accepted: 0 };
      langStats[s.lang].total++;
      if (norm === 'Accepted') langStats[s.lang].accepted++;
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
    probStats, verdictStats, dayStats, langStats, tagStats, dowStats,
    distintos, acertos, firstAcOrder, solvedAtFirst, solvedDate, resolved,
  };
}

// streak de dias consecutivos com >=1 submissão (termina hoje ou ontem)
function computeStreaks(dayStats) {
  const days = Object.keys(dayStats).sort();           // 'YYYY-MM-DD' ascendente
  if (!days.length) return { current: 0, longest: 0 };
  const set = new Set(days);
  // maior streak
  let longest = 0, run = 0, prev = null;
  for (const d of days) {
    if (prev && (new Date(d) - new Date(prev)) === 86400000) run++;
    else run = 1;
    longest = Math.max(longest, run);
    prev = d;
  }
  // streak atual: conta para trás a partir de hoje (ou ontem, se hoje não houve)
  let cur = 0;
  const today = new Date(); today.setHours(0, 0, 0, 0);
  let probe = new Date(today);
  if (!set.has(dayTagD(probe))) probe.setDate(probe.getDate() - 1); // tolera "ainda não enviou hoje"
  while (set.has(dayTagD(probe))) { cur++; probe.setDate(probe.getDate() - 1); }
  return { current: cur, longest };
}

function verdictColor(v) {
  return v === 'Accepted' ? '#1a7f37' : v === 'Wrong Answer' ? '#c4314b'
    : v === 'Time Limit Exceeded' ? '#a66a00' : v === 'Runtime Error' ? '#ef8a56'
      : v === 'Compilation Error' ? '#7a5ada' : '#5b6b7d';
}

const DOW_LABELS = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];

// ---- métricas (cartões) -----------------------------------------------------
function renderQuickStats(stats) {
  const total = history.length;
  const acertos = stats.acertos;
  const aceitas = stats.verdictStats['Accepted'] || 0;
  const taxa = total ? Math.round(100 * aceitas / total) : 0;

  // tentativas médias até resolver (entre os resolvidos)
  const ords = Object.values(stats.firstAcOrder);
  const mediaTent = ords.length ? (ords.reduce((a, b) => a + b, 0) / ords.length).toFixed(2) : '—';

  // acerto na 1ª tentativa (% dos resolvidos)
  const firstTryCount = Object.values(stats.solvedAtFirst).filter(Boolean).length;
  const firstTryPct = acertos ? Math.round(100 * firstTryCount / acertos) : 0;

  const { current: curStreak, longest: maxStreak } = computeStreaks(stats.dayStats);

  // linguagens
  const langKeys = Object.keys(stats.langStats);
  const nLangs = langKeys.length;
  const mostUsed = langKeys.slice().sort((a, b) => stats.langStats[b].total - stats.langStats[a].total)[0];
  // linguagem mais eficaz (>=3 submissões)
  const eff = langKeys.filter(l => stats.langStats[l].total >= 3)
    .map(l => ({ l, r: stats.langStats[l].accepted / stats.langStats[l].total, n: stats.langStats[l].total }))
    .sort((a, b) => b.r - a.r || b.n - a.n)[0];
  const bestLang = eff ? `${eff.l} (${Math.round(eff.r * 100)}%)` : '—';

  // dia mais ativo
  const dayEntries = Object.entries(stats.dayStats);
  let busiest = '—';
  if (dayEntries.length) {
    const [d, n] = dayEntries.sort((a, b) => b[1] - a[1])[0];
    const dt = new Date(d + 'T00:00:00');
    busiest = pad2(dt.getDate()) + '/' + pad2(dt.getMonth() + 1) + '/' + dt.getFullYear() + ` (${n})`;
  }

  const box = document.getElementById('quickStats'); box.innerHTML = '';
  const card = (n, label, hl) => el('div', { class: 'stat-card' + (hl ? ' hl' : '') },
    el('div', { class: 'n' }, String(n)), el('div', { class: 'lbl' }, label));
  box.append(
    card(total, 'submissões', true),
    card(acertos, 'problemas resolvidos', true),
    card(taxa + '%', 'taxa de acerto (AC / total)'),
    card(mediaTent, 'tentativas médias até resolver'),
    card(firstTryPct + '%', 'acerto na 1ª tentativa'),
    card(curStreak + (curStreak === 1 ? ' dia' : ' dias'), 'streak atual'),
    card(maxStreak + (maxStreak === 1 ? ' dia' : ' dias'), 'maior streak'),
    card(nLangs, 'linguagens usadas'),
    card(mostUsed || '—', 'linguagem mais usada'),
    card(bestLang, 'linguagem mais eficaz'),
    card(busiest, 'dia mais ativo'),
  );
}

// ---- gráficos ---------------------------------------------------------------
function sectionCard(titleText) {
  const h = el('h2', {}, titleText);
  const sec = el('div', { class: 'section' }, h);
  return sec;
}

function renderDashboard(stats) {
  const dash = document.getElementById('dashboard');
  dash.innerHTML = '';

  // 1) Curva cumulativa de problemas distintos resolvidos por data
  const solvedDates = Object.values(stats.solvedDate).sort((a, b) => a - b);
  {
    const sec = sectionCard('📈 Desenvolvimento ao longo do tempo');
    sec.append(el('div', { class: 'chart-title' }, 'Problemas distintos resolvidos (acumulado)'));
    if (solvedDates.length) {
      let acc = 0;
      const pts = solvedDates.map(epoch => ({ x: new Date(epoch * 1000), y: ++acc }));
      // garante um ponto "hoje" no fim para a linha alcançar a borda
      pts.push({ x: new Date(), y: acc, label: 'hoje' });
      sec.append(lineChart(pts, { width: 760, height: 240, color: '#1a7f37', maxLabels: 7 }));
    } else {
      sec.append(el('div', { class: 'muted small center' }, 'Nenhum problema resolvido ainda.'));
    }
    dash.append(sec);
  }

  // 2) Heatmap de atividade (~26 semanas)
  {
    const sec = sectionCard('🔥 Atividade diária (últimas 26 semanas)');
    sec.append(el('div', { class: 'muted small', style: 'margin-bottom:.5rem' }, 'Cada quadrado é um dia; quanto mais escuro, mais submissões.'));
    const w = el('div', { class: 'heat-wrap' }, heatmap(stats.dayStats, { weeks: 26, color: '#216097' }));
    sec.append(w);
    dash.append(sec);
  }

  // 3) Submissões por dia (últimos 45) — barras
  {
    const sec = sectionCard('🗓️ Submissões por dia');
    sec.append(el('div', { class: 'chart-title' }, 'Últimos 45 dias'));
    const days = [];
    const now = new Date();
    for (let i = 44; i >= 0; i--) {
      const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i);
      days.push({ label: pad2(d.getDate()) + '/' + pad2(d.getMonth() + 1), value: stats.dayStats[dayTagD(d)] || 0 });
    }
    sec.append(barChart(days, { width: 760, height: 230, color: '#216097', maxLabels: 15, rotateLabels: true }));
    dash.append(sec);
  }

  // 4) Veredictos (pizza) + atividade por dia da semana (barras), lado a lado
  {
    const sec = sectionCard('🎯 Veredictos e ritmo semanal');
    const grid = el('div', { class: 'stat-grid two' });
    // pizza de veredictos
    const vEntries = Object.entries(stats.verdictStats).sort((a, b) => b[1] - a[1]);
    const vBox = el('div', {}, el('div', { class: 'chart-title' }, 'Distribuição de veredictos'));
    vBox.append(pieChart(vEntries.map(([k, v]) => ({ label: k, value: v, color: verdictColor(k) })), { size: 240, donut: 0.55 }));
    // barras por dia da semana (Dom–Sáb)
    const dowBox = el('div', {}, el('div', { class: 'chart-title' }, 'Submissões por dia da semana'));
    dowBox.append(barChart(stats.dowStats.map((v, i) => ({ label: DOW_LABELS[i], value: v })), { width: 360, height: 240, color: '#7a5ada' }));
    grid.append(vBox, dowBox);
    sec.append(grid);
    dash.append(sec);
  }

  // 5) Desempenho por linguagem — tabela + barras (taxa de AC)
  {
    const sec = sectionCard('💻 Desempenho por linguagem');
    const langs = Object.keys(stats.langStats)
      .sort((a, b) => stats.langStats[b].total - stats.langStats[a].total);
    if (!langs.length) {
      sec.append(el('div', { class: 'muted small' }, 'Sem dados de linguagem.'));
    } else {
      sec.append(el('div', { class: 'muted small', style: 'margin-bottom:.5rem' },
        'Onde você mais acerta: taxa de AC por linguagem (mín. 3 submissões em destaque).'));
      const grid = el('div', { class: 'stat-grid two' });

      // tabela
      const tb = el('tbody');
      langs.forEach(l => {
        const s = stats.langStats[l];
        const rate = Math.round(100 * s.accepted / Math.max(1, s.total));
        tb.append(el('tr', {},
          el('td', {}, l),
          el('td', {}, String(s.total)),
          el('td', {}, String(s.accepted)),
          el('td', {}, el('b', { style: 'color:' + (rate >= 60 ? 'var(--ok)' : rate >= 30 ? 'var(--warn)' : 'var(--err)') }, rate + '%'))));
      });
      const table = el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, 'Linguagem'), el('th', {}, 'Subs'), el('th', {}, 'AC'), el('th', {}, 'Taxa AC'))),
        tb);
      grid.append(el('div', {}, el('div', { class: 'chart-title' }, 'Resumo'), table));

      // barras: taxa de AC por linguagem (só >=3 subs para a taxa fazer sentido)
      const rateBars = langs
        .filter(l => stats.langStats[l].total >= 3)
        .map(l => ({ label: l, value: Math.round(100 * stats.langStats[l].accepted / stats.langStats[l].total) }))
        .sort((a, b) => b.value - a.value);
      const barBox = el('div', {}, el('div', { class: 'chart-title' }, 'Taxa de acerto por linguagem (%)'));
      if (rateBars.length) barBox.append(barChart(rateBars, { width: 360, height: 240, color: '#1a7f37' }));
      else barBox.append(el('div', { class: 'muted small center', style: 'padding:1rem' }, 'Poucas submissões para comparar.'));
      grid.append(barBox);

      sec.append(grid);
    }
    dash.append(sec);
  }

  // 6) Forças por tag — top tags por nº de problemas resolvidos
  {
    const sec = sectionCard('🏷️ Forças por tag');
    const tags = Object.keys(stats.tagStats);
    if (!tags.length) {
      sec.append(el('div', { class: 'muted small' }, 'Sem tags (problemas sem metadados de tag).'));
    } else {
      sec.append(el('div', { class: 'muted small', style: 'margin-bottom:.5rem' }, 'Áreas em que você mais resolve problemas (distintos).'));
      const grid = el('div', { class: 'stat-grid two' });
      const topByResolved = tags.filter(t => stats.tagStats[t].resolved > 0)
        .sort((a, b) => stats.tagStats[b].resolved - stats.tagStats[a].resolved || a.localeCompare(b))
        .slice(0, 12);
      const barBox = el('div', {}, el('div', { class: 'chart-title' }, 'Resolvidos por tag (top 12)'));
      if (topByResolved.length) {
        barBox.append(barChart(topByResolved.map(t => ({ label: t, value: stats.tagStats[t].resolved })),
          { width: 360, height: 260, color: '#216097', rotateLabels: true, maxLabels: 12 }));
      } else {
        barBox.append(el('div', { class: 'muted small center', style: 'padding:1rem' }, 'Nenhum resolvido ainda.'));
      }
      const pieBox = el('div', {}, el('div', { class: 'chart-title' }, 'Participação por tag (resolvidos)'));
      pieBox.append(pieChart(topByResolved.map(t => ({ label: t, value: stats.tagStats[t].resolved })), { size: 240 }));
      grid.append(barBox, pieBox);
      sec.append(grid);
    }
    dash.append(sec);
  }

  // 7) Histórico completo (mantém comportamento existente + ordenação)
  {
    const sec = sectionCard('📜 Histórico completo de submissões');
    const box = el('div', { id: 'historyTable' });
    sec.append(box);
    dash.append(sec);
    renderHistory();
  }
}

// ---- downloads autenticados (cód/log) — só dono logado ----------------------
async function downloadAuthed(path, filename) {
  try {
    const r = await fetch('/api/v1' + path, { headers: { 'Authorization': 'Bearer ' + getToken(CONTEST) } });
    if (!r.ok) throw 0;
    const blob = await r.blob();
    const a = el('a', { href: URL.createObjectURL(blob), download: filename });
    document.body.append(a); a.click(); a.remove();
  } catch { alert('Falha ao baixar.'); }
}
async function openLogAuthed(path) {
  try {
    const r = await fetch('/api/v1' + path, { headers: { 'Authorization': 'Bearer ' + getToken(CONTEST) } });
    const txt = await r.text();
    const w = window.open(); const pre = w.document.createElement('pre');
    pre.style.cssText = 'font-family:monospace;white-space:pre-wrap;padding:1rem'; pre.textContent = txt;
    w.document.body.append(pre); w.document.close();
  } catch { alert('Falha ao abrir o log.'); }
}

// abre o report.html (auto-contido) do julgamento num iframe sandboxed: renderiza
// HTML/CSS mas bloqueia JS (defesa em profundidade — o conteúdo já é escapado na origem).
async function openReportAuthed(path) {
  try {
    const r = await fetch('/api/v1' + path, { headers: { 'Authorization': 'Bearer ' + getToken(CONTEST) } });
    const html = await r.text();
    const w = window.open('', '_blank');
    if (!w) { alert('Permita pop-ups para ver o report.'); return; }
    w.document.title = 'Report'; w.document.body.style.margin = '0';
    const ifr = w.document.createElement('iframe');
    ifr.setAttribute('sandbox', '');
    ifr.srcdoc = html;
    ifr.style.cssText = 'position:fixed;inset:0;border:0;width:100%;height:100%';
    w.document.body.append(ifr);
  } catch { alert('Falha ao abrir o report.'); }
}

function titleOf(pid) { const p = problemsById[pid]; return (p && (p.title || p.full_name)) || pid; }

function renderHistory() {
  const box = document.getElementById('historyTable');
  if (!box) return;
  const rows = history.slice().sort((a, b) => {
    if (sortKey === 'date') return sortAsc ? a.epoch - b.epoch : b.epoch - a.epoch;
    if (sortKey === 'problem') return sortAsc ? titleOf(a.probid).localeCompare(titleOf(b.probid)) : titleOf(b.probid).localeCompare(titleOf(a.probid));
    if (sortKey === 'lang') return sortAsc ? (a.lang || '').localeCompare(b.lang || '') : (b.lang || '').localeCompare(a.lang || '');
    if (sortKey === 'status') return sortAsc ? normVerdict(a.verdict).localeCompare(normVerdict(b.verdict)) : normVerdict(b.verdict).localeCompare(normVerdict(a.verdict));
    return 0;
  });
  box.innerHTML = '';
  if (!rows.length) { box.innerHTML = '<span class="muted small">Nenhuma submissão.</span>'; return; }
  const arrow = (k) => sortKey === k ? (sortAsc ? ' ▲' : ' ▼') : '';
  const th = (label, k) => el('th', { onclick: () => { sortAsc = (sortKey === k) ? !sortAsc : false; sortKey = k; renderHistory(); } }, label + arrow(k));
  const head = el('thead', {}, el('tr', {},
    th('Data/Hora', 'date'), th('Problema', 'problem'), th('Linguagem', 'lang'),
    canLog ? el('th', {}, 'Cód/Log') : null, th('Status', 'status')));
  const tb = el('tbody');
  rows.forEach(s => {
    const pending = isPending(s.verdict);
    const logTd = canLog ? el('td', { class: 'small' },
      el('a', { href: '#', onclick: (e) => { e.preventDefault(); downloadAuthed(`/submission/source?contest=${CONTEST}&id=${encodeURIComponent(s.subid)}&time=${encodeURIComponent(s.epoch)}`, s.subid + '.txt'); } }, 'cód'),
      ' · ',
      el('a', { href: '#', onclick: (e) => { e.preventDefault(); openReportAuthed(`/submission/log?contest=${CONTEST}&id=${encodeURIComponent(s.subid)}&time=${encodeURIComponent(s.epoch)}`); } }, 'log')) : null;
    tb.append(el('tr', {},
      el('td', {}, fmtDate(s.epoch)),
      el('td', {}, el('a', { href: '/treino/problema/?id=' + encodeURIComponent(s.probid) }, titleOf(s.probid))),
      el('td', {}, s.lang),
      logTd,
      el('td', {}, el('span', { class: 'verdict ' + verdictClass(s.verdict) }, pending ? el('span', {}, el('span', { class: 'spin' }), ' ' + s.verdict) : s.verdict))));
  });
  box.append(el('table', { class: 'moj' }, head, tb));
}

// ---- cabeçalho de perfil ----------------------------------------------------
// cor estável a partir do login (para o círculo de iniciais)
function colorFromName(s) {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  const hue = h % 360;
  return `hsl(${hue} 55% 42%)`;
}
function initialsOf(name, login) {
  const src = (name || login || '?').replace(/\[[^\]]*\]/g, '').trim() || login || '?';
  const parts = src.split(/\s+/).filter(Boolean);
  const ini = (parts[0] || '?')[0] + (parts.length > 1 ? parts[parts.length - 1][0] : '');
  return ini.toUpperCase();
}
function avatarEl(profile) {
  const name = profile.name || USER, login = profile.login || USER;
  if (profile.has_photo) {
    return el('img', { class: 'avatar', alt: 'foto de ' + login,
      src: '/api/v1/treino/profile/photo?user=' + encodeURIComponent(login) + '&t=' + Date.now() });
  }
  return el('div', { class: 'avatar avatar-ini', style: 'background:' + colorFromName(login) }, initialsOf(name, login));
}

// ranking do editor favorito a partir de /treino/editors
async function editorRankLine(editorId) {
  if (!editorId) return null;
  let data;
  try { data = await apiGet('/treino/editors', { contest: CONTEST }); } catch { return null; }
  const list = (data && data.editors) || [];
  const total = (data && data.total) || list.reduce((a, e) => a + (e.count || 0), 0);
  const label = editorLabel(editorId);
  const idx = list.findIndex(e => e.editor === editorId);
  if (idx < 0) {
    // editor escolhido mas sem ninguém contabilizado para ele (ou lista vazia)
    return `Editor: ${label}`;
  }
  const rank = idx + 1, ppl = list[idx].count || 0;
  return `Editor: ${label} — ${rank}º mais usado (de ${list.length})` +
    `, ${ppl} ${ppl === 1 ? 'pessoa' : 'pessoas'}` + (total ? ` · ${total} no total` : '');
}

async function renderProfileHeader(profile) {
  const head = document.getElementById('profileHead');
  head.innerHTML = '';
  const name = profile.name || USER;
  const meta = el('div', { class: 'profile-meta' },
    el('div', { class: 'pname' }, name),
    el('div', { class: 'plogin' }, '~' + (profile.login || USER)));
  if (profile.university) meta.append(el('div', { class: 'pline' }, el('span', { class: 'lbl' }, 'Universidade: '), profile.university));

  const editorLine = el('div', { class: 'pline' });
  meta.append(editorLine);

  const actions = el('div', { class: 'profile-actions' });
  if (isOwner) actions.append(el('a', { class: 'btn ghost', href: '/treino/perfil/' }, '✎ Editar perfil'));

  head.append(avatarEl(profile), meta, actions);

  // ranking do editor (assíncrono — best-effort)
  if (profile.favorite_editor) {
    const line = await editorRankLine(profile.favorite_editor);
    if (line) editorLine.textContent = line; else editorLine.remove();
  } else {
    editorLine.remove();
  }
}

function renderPrivate(profile) {
  document.getElementById('quickStats').innerHTML = '';
  const head = document.getElementById('profileHead');
  head.innerHTML = '';
  head.append(
    el('div', { class: 'avatar avatar-ini', style: 'background:' + colorFromName(USER) }, '🔒'),
    el('div', { class: 'profile-meta' },
      el('div', { class: 'pname' }, '~' + (profile.login || USER)),
      el('div', { class: 'private-box' }, '🔒 Este perfil é privado.')));
  document.getElementById('dashboard').innerHTML = '';
}

// ---- boot -------------------------------------------------------------------
async function boot() {
  await renderAuthArea(document.getElementById('authArea'), CONTEST, () => location.reload());

  if (!USER) {
    document.getElementById('profileHead').innerHTML =
      '<div class="error-box">Faltou informar <code>?user=&lt;login&gt;</code> na URL.</div>';
    return;
  }
  document.title = 'Estatísticas de ' + USER + ' — MOJ';

  // dono? (vê cód/log e botão "editar perfil")
  const st = await status(CONTEST);
  isOwner = !!(st.logged_in && st.login === USER);
  canLog = isOwner;

  // perfil (cabeçalho + privacidade)
  let profile = { login: USER, name: USER, is_public: true };
  try {
    const j = await apiGet('/treino/profile?user=' + encodeURIComponent(USER), { contest: CONTEST, auth: isOwner });
    profile = j || profile;
  } catch (e) {
    // usuário inexistente, etc.
    document.getElementById('profileHead').innerHTML =
      '<div class="error-box">Não foi possível carregar este perfil: ' + (e.message || 'erro') + '</div>';
    return;
  }

  // privado e não sou o dono → mostra apenas o aviso e para
  if (profile.is_public === false && !isOwner) {
    renderPrivate(profile);
    return;
  }

  await renderProfileHeader(profile);

  // problemas (títulos/tags) — best-effort
  try {
    const j = await apiGet('/treino/problems', { contest: CONTEST });
    const arr = Array.isArray(j) ? j : (j.problems || j.data || []);
    arr.forEach(p => { problemsById[p.id || p.problem_id] = p; });
  } catch {}

  // histórico (com Bearer se for o dono → respeita privacidade no servidor)
  let txt;
  try { txt = await apiGetText('/treino/history-full?user=' + encodeURIComponent(USER), { contest: CONTEST, auth: isOwner }); }
  catch {
    document.getElementById('dashboard').innerHTML =
      '<div class="section"><span class="error-box">Falha ao carregar o histórico.</span></div>';
    return;
  }
  history = txt.split('\n').map(s => s.trim()).filter(Boolean).map(parseLine).filter(Boolean);

  if (!history.length) {
    document.getElementById('quickStats').innerHTML = '';
    document.getElementById('dashboard').innerHTML =
      '<div class="section"><span class="muted">Ainda não há submissões para mostrar estatísticas.</span></div>';
    return;
  }

  const stats = computeStats();
  renderQuickStats(stats);
  renderDashboard(stats);
}
boot();
