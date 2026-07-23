// treino/problema/stats/stats.js — estatísticas de um problema do Treino Livre.
import { apiGet } from '/shared/api.js';
import { el, avatarEl, renderAuthArea } from '/shared/ui.js';
import { barChart, pieChart, hBarChart, lineChart, heatmap, heatmapGrid } from '/lib/charts.js';
import { langById } from '/shared/languages.js';
import { editorLabel } from '/shared/editors.js';
import { T } from '/shared/i18n.js';

const CONTEST = 'treino';
const ID = new URLSearchParams(location.search).get('id') || '';
const LOCALE = T('pt-BR', 'en-US');
const langLabel = (l) => (langById(String(l || '').toLowerCase()) || {}).label || l || '?';
const pct = (x) => Math.round((x || 0) * 100) + '%';
const fdate = (e) => (e ? new Date(e * 1000).toLocaleDateString(LOCALE) : '—');
// 'YYYY-MM-DD' -> data local SEM passar por new Date(string) (parse UTC deslocaria o dia)
const fdateStr = (s) => { const [y, m, d] = String(s).split('-').map(Number); return new Date(y, m - 1, d).toLocaleDateString(LOCALE); };
const fmonth = (m) => { const [y, mo] = String(m).split('-'); return mo + '/' + y.slice(2); };
const fdur = (sec) => {
  if (sec == null) return '—';
  if (sec < 3600) return Math.max(1, Math.round(sec / 60)) + ' min';
  if (sec < 86400) return Math.round(sec / 3600) + ' h';
  return Math.round(sec / 86400) + ' ' + T('dia(s)', 'day(s)');
};
const isKnownLang = (l) => l && langById(String(l).toLowerCase());
const langDisplay = (l) => (l === 'outro' ? T('Outros (ext. não reconhecidas)', 'Others (unrecognized ext.)') : langLabel(l));
// junta tokens de linguagem não reconhecidos (olamundo, txt, exe, …) num único "Outros"
function cleanLangs(byLang) {
  const out = []; let other = null;
  (byLang || []).forEach((l) => {
    if (isKnownLang(l.lang)) out.push(l);
    else {
      other = other || { lang: 'outro', submissions: 0, accepted: 0, solvers: 0 };
      other.submissions += l.submissions || 0; other.accepted += l.accepted || 0; other.solvers += l.solvers || 0;
    }
  });
  if (other) out.push(other);
  return out.sort((a, b) => b.submissions - a.submissions);
}

function metric(v, l) { return el('div', { class: 'metric' }, el('div', { class: 'v' }, String(v)), el('div', { class: 'l' }, l)); }
function chartCard(title, node) {
  return el('div', { class: 'subcard' }, el('h3', { class: 'small', style: 'margin:.1rem 0 .6rem;color:var(--blue-dark)' }, title), node);
}
function verdictColor(v) {
  const s = (v || '').toLowerCase();
  if (s.startsWith('accepted')) return '#15803d';
  if (s.startsWith('wrong')) return '#be1241';
  if (s.startsWith('time')) return '#9a6700';
  if (s.startsWith('runtime')) return '#d94f9a';
  if (s.startsWith('compil')) return '#7a5ada';
  return '#94a3b8';
}

async function boot() {
  await renderAuthArea(document.getElementById('authArea'), CONTEST, () => {});
  const content = document.getElementById('content');
  if (!ID) { content.innerHTML = `<div class="notice">${T('Faltou informar ?id=&lt;problema&gt;.', 'Missing ?id=&lt;problem&gt;.')}</div>`; return; }

  let s;
  try { s = await apiGet('/treino/problem-stats?id=' + encodeURIComponent(ID), { contest: CONTEST }); }
  catch { content.innerHTML = `<div class="error-box">${T('Falha ao carregar as estatísticas.', 'Failed to load statistics.')}</div>`; return; }
  content.innerHTML = '';

  content.append(el('div', { class: 'section' },
    el('h1', { style: 'margin:0;color:var(--blue-dark)' }, '📊 ', s.title || ID),
    el('p', { class: 'small muted', style: 'margin:.3rem 0 0' }, T('Problema do Treino Livre · ', 'Free Training problem · '),
      el('a', { href: '/treino/problema/?id=' + encodeURIComponent(ID) }, T('abrir o problema →', 'open the problem →')),
      ' · ', el('a', { href: '/docs/ESTATISTICAS-PROBLEMA.html', target: '_blank' },
        T('ⓘ como calculamos estas estatísticas', 'ⓘ how these statistics are computed')))));

  if (!s.total_submissions) {
    content.append(el('div', { class: 'section muted' }, T('Ainda não há submissões para este problema.', 'No submissions for this problem yet.')));
    return;
  }

  // --- resumo ---
  const ar = s.acceptance_rate || 0;
  const diff = ar >= 0.9 ? T('muito fácil', 'very easy') : ar >= 0.7 ? T('fácil', 'easy') : ar >= 0.5 ? T('médio', 'medium') : T('difícil', 'hard');
  // percentil contra o acervo: X% dos problemas públicos têm taxa de sucesso por usuário MAIOR
  const dp = s.difficulty_percentile;
  let dpCard = null;
  if (dp && dp.harder_than_pct != null) {
    dpCard = metric(dp.harder_than_pct + '%', T('do acervo é mais fácil que este', 'of the archive is easier than this'));
    dpCard.title = T(`taxa de sucesso por usuário ${Math.round((dp.success_rate || 0) * 100)}%, comparada com ${dp.cohort} problemas públicos com ≥5 tentantes`,
      `per-user success rate ${Math.round((dp.success_rate || 0) * 100)}%, compared with ${dp.cohort} public problems with ≥5 attempters`);
  }
  content.append(el('div', { class: 'section' },
    el('h2', {}, T('Resumo', 'Summary')),
    el('div', { class: 'metrics' },
      metric(s.total_submissions, T('submissões', 'submissions')),
      metric(s.distinct_attempted, T('tentaram', 'attempted')),
      metric(s.distinct_solved, T('resolveram', 'solved')),
      metric(pct(ar), T('taxa de acerto', 'acceptance rate')),
      metric((s.avg_submissions_per_user || 0).toFixed(1), T('subs / usuário', 'subs / user')),
      metric(diff, T('dificuldade', 'difficulty')),
      dpCard)));

  // --- fatos rápidos ---
  const f = s.facts || {};
  const factCard = (v, l) => { const m = metric(v, l); m.querySelector('.v').classList.add('sm'); return m; };
  const fs = f.first_solver;
  const fsName = fs ? (fs.name || fs.login || T('perfil privado', 'private profile')) : null;
  content.append(el('div', { class: 'section' }, el('h2', {}, T('📌 Fatos', '📌 Facts')),
    el('div', { class: 'metrics' },
      factCard(fdate(f.first_sub_epoch), T('primeira submissão', 'first submission')),
      fs ? factCard(fsName + ' · ' + fdate(fs.epoch), T('primeiro a resolver', 'first to solve')) : null,
      f.peak_day ? factCard(fdateStr(f.peak_day.date) + ' (' + f.peak_day.n + ')', T('dia de pico', 'peak day')) : null,
      factCard(fdate(f.last_sub_epoch), T('última submissão', 'last submission')),
      s.tries_median != null ? factCard(String(s.tries_median), T('mediana de tentativas até o aceite', 'median tries until accept')) : null,
      s.t2s_median != null ? factCard(fdur(s.t2s_median), T('tempo mediano até resolver', 'median time to solve')) : null)));

  // --- linha do tempo: histograma mensal completo + curvas de crescimento ---
  const monthly = s.monthly || [];
  if (monthly.length) {
    const mData = monthly.map((m) => ({ label: fmonth(m.m), value: m.subs }));
    const hist = barChart(mData, { width: Math.max(720, monthly.length * 26), height: 240, color: '#216097', rotateLabels: true, maxLabels: 24 });
    const acPts = (s.first_ac_epochs || []).map((e, i) => ({ x: e, y: i + 1, label: fdate(e) }));
    let cum = 0, cumAc = 0;
    const ratePts = monthly.map((m) => { cum += m.subs; cumAc += m.ac; return { x: m.m + '-15', y: Math.round((cumAc / Math.max(1, cum)) * 100), label: fmonth(m.m) }; });
    content.append(el('div', { class: 'section' }, el('h2', {}, T('📈 Linha do tempo', '📈 Timeline')),
      el('div', { class: 'subcard' },
        el('h3', { class: 'small', style: 'margin:.1rem 0 .6rem;color:var(--blue-dark)' }, T('Submissões por mês, desde a primeira', 'Submissions per month, since the first')),
        el('div', { class: 'chart-wrap' }, hist)),
      el('div', { class: 'chart-grid two', style: 'margin-top:1rem' },
        acPts.length ? chartCard(T('Resolvedores acumulados', 'Cumulative solvers'),
          lineChart(acPts, { width: 460, height: 220, color: '#1a7f37' })) : null,
        chartCard(T('Taxa de aceitação acumulada (%)', 'Cumulative acceptance rate (%)'),
          lineChart(ratePts, { width: 460, height: 220, color: '#7a5ada', fill: false })))));
  }

  // --- calendário: heatmap anual (por ano + soma de todos) e punchcard hora×dia ---
  const daily = s.daily || {};
  const years = [...new Set(Object.keys(daily).map((d) => d.slice(0, 4)))].sort();
  if (years.length) {
    const bar = el('div', { class: 'yearbar' });
    const holder = el('div', { class: 'chart-wrap' });
    const note = el('p', { class: 'small muted', style: 'margin:.4rem 0 0' });
    const render = (mode) => {
      holder.innerHTML = ''; note.textContent = '';
      [...bar.children].forEach((b) => b.classList.toggle('on', b.dataset.mode === mode));
      if (mode === 'all') {
        // soma de TODOS os anos por dia-do-ano, projetada num ano bissexto (29/02 aparece)
        const agg = {};
        for (const [d, n] of Object.entries(daily)) { const k = '2024' + d.slice(4); agg[k] = (agg[k] || 0) + n; }
        holder.append(heatmap(agg, { weeks: 53, end: new Date(2024, 11, 31), color: '#216097',
          fmt: (v, tag) => tag.slice(5) + ': ' + v + ' ' + T('subs (todos os anos)', 'subs (all years)') }));
        note.textContent = T('Todos os anos somados, dia a dia — os períodos quentes do calendário letivo saltam aos olhos.',
          'All years summed, day by day — the hot periods of the school calendar stand out.');
      } else {
        const one = {};
        for (const [d, n] of Object.entries(daily)) if (d.startsWith(mode)) one[d] = n;
        holder.append(heatmap(one, { weeks: 53, end: new Date(+mode, 11, 31), color: '#216097' }));
      }
    };
    years.forEach((y) => { const b = el('button', { class: 'btn ghost', 'data-mode': y }, y); b.onclick = () => render(y); bar.append(b); });
    if (years.length > 1) { const b = el('button', { class: 'btn ghost', 'data-mode': 'all' }, T('Σ todos', 'Σ all')); b.onclick = () => render('all'); bar.append(b); }
    const punch = heatmapGrid((s.dow_hour || []).map((c) => ({ dow: c.dow, hour: c.hour, value: c.n, n: c.n })),
      { cell: 13, gap: 3, color: '#216097', fmt: (v) => String(v) });
    content.append(el('div', { class: 'section' }, el('h2', {}, T('🗓 Calendário de atividade', '🗓 Activity calendar')),
      bar, holder, note,
      el('div', { class: 'chart-grid two', style: 'margin-top:1rem' },
        chartCard(T('Hora do dia × dia da semana', 'Hour of day × weekday'), el('div', { class: 'chart-wrap' }, punch)))));
    render(years.length > 1 ? 'all' : years[0]);
  }

  // --- como resolvem: veredictos, linguagens, tentativas, tempo, editores ---
  const vData = (s.verdicts || []).map((v) => ({ label: v.verdict, value: v.count, color: verdictColor(v.verdict) }));
  const bl = cleanLangs(s.by_language);
  const slData = bl.filter((l) => l.solvers > 0).map((l) => ({ label: langDisplay(l.lang), value: l.solvers }));
  const rateData = bl.filter((l) => l.submissions >= 3)
    .map((l) => ({ label: langDisplay(l.lang), value: Math.round((l.accepted / l.submissions) * 100) }))
    .sort((a, b) => b.value - a.value);
  const triesData = (s.tries || []).map((b) => ({ label: b.bucket === '1' ? T('1 (de primeira!)', '1 (first try!)') : b.bucket, value: b.n }));
  const T2SL = { '<1h': T('menos de 1 hora', 'under 1 hour'), '1h-1d': T('1 hora a 1 dia', '1 hour to 1 day'),
    '1d-1sem': T('1 dia a 1 semana', '1 day to 1 week'), '>1sem': T('mais de 1 semana', 'over 1 week') };
  const t2sData = (s.time_to_solve || []).map((b) => ({ label: T2SL[b.bucket] || b.bucket, value: b.n }));
  const eData = (s.editors || []).map((e) => ({ label: editorLabel(e.editor), value: e.count }));
  content.append(el('div', { class: 'section' }, el('h2', {}, T('🧩 Como resolvem', '🧩 How they solve')),
    el('div', { class: 'chart-grid' },
      chartCard(T('Veredictos', 'Verdicts'), pieChart(vData, { size: 240, donut: 0.55 })),
      chartCard(T('Resolvedores distintos por linguagem', 'Distinct solvers by language'),
        barChart(slData, { width: 460, height: 240, color: '#216097', rotateLabels: true })),
      rateData.length ? chartCard(T('Taxa de aceitação por linguagem', 'Acceptance rate by language'),
        hBarChart(rateData, { total: 0, fmt: (v) => v + '%' })) : null,
      triesData.some((d) => d.value) ? chartCard(T('Submissões até o 1º aceite', 'Submissions until first accept'),
        hBarChart(triesData, {})) : null,
      t2sData.some((d) => d.value) ? chartCard(T('Tempo entre a 1ª tentativa e o aceite', 'Time from first try to accept'),
        hBarChart(t2sData, {})) : null,
      eData.length ? chartCard(T('⌨ Editores de quem resolveu', '⌨ Editors of those who solved'),
        pieChart(eData, { size: 240 })) : null)));

  // --- tabela por linguagem ---
  const tb = el('tbody');
  bl.forEach((l) => tb.append(el('tr', {},
    el('td', {}, langDisplay(l.lang)),
    el('td', {}, String(l.submissions)),
    el('td', {}, String(l.accepted)),
    el('td', {}, l.submissions ? pct(l.accepted / l.submissions) : '-'),
    el('td', {}, String(l.solvers)))));
  content.append(el('div', { class: 'section' }, el('h2', {}, T('Por linguagem', 'By language')),
    el('p', { class: 'small muted', style: 'margin:0 0 .5rem' }, T('"Resolveram" = usuários distintos que acertaram com aquela linguagem.', '"Solved" = distinct users who got it accepted with that language.')),
    el('table', { class: 'moj' }, el('thead', {}, el('tr', {},
      el('th', {}, T('Linguagem', 'Language')), el('th', {}, T('Submissões', 'Submissions')), el('th', {}, T('Aceitas', 'Accepted')),
      el('th', {}, T('Taxa', 'Rate')), el('th', {}, T('Resolveram', 'Solved')))), tb)));

  // --- tempo de execução das aceitas (estilo Kattis) ---
  // runtimes = [{lang, t}] onde t = o teste mais LENTO da submissão aceita. Só cobre
  // submissões julgadas na plataforma nova (results/ por submissão) — cresce sozinho.
  const rts = s.runtimes || [];
  if (rts.length) {
    const ts = rts.map((r) => r.t);
    const tmax = Math.max(...ts, 0.01);
    // passo "redondo" (1/2/5 × 10^k) dando ~10 faixas
    const raw = tmax / 10;
    const pow = Math.pow(10, Math.floor(Math.log10(raw)));
    const step = [1, 2, 5, 10].map((m) => m * pow).find((s2) => s2 >= raw) || raw;
    const dec = Math.max(0, -Math.floor(Math.log10(step)));
    const nb = Math.max(1, Math.ceil((tmax + 1e-9) / step));
    const bins = new Array(nb).fill(0);
    ts.forEach((t) => { bins[Math.min(nb - 1, Math.floor(t / step))]++; });
    const hData = bins.map((v, i) => ({ label: (i * step).toFixed(dec) + '–' + ((i + 1) * step).toFixed(dec) + 's', value: v }));
    const fastest = {};
    rts.forEach((r) => { if (fastest[r.lang] == null || r.t < fastest[r.lang]) fastest[r.lang] = r.t; });
    const fData = Object.entries(fastest).map(([l, t]) => ({ label: langDisplay(l), value: t }))
      .sort((a, b) => a.value - b.value);
    content.append(el('div', { class: 'section' },
      el('h2', {}, T('⏱ Tempo de execução (submissões aceitas)', '⏱ Running time (accepted submissions)')),
      el('p', { class: 'small muted', style: 'margin:0 0 .6rem' },
        T(`Tempo do teste mais lento de cada aceita — ${rts.length} submissões julgadas na plataforma atual (submissões antigas migradas não têm medição).`,
          `Slowest-test time of each accepted run — ${rts.length} submissions judged on the current platform (old migrated submissions have no measurement).`)),
      el('div', { class: 'chart-grid two' },
        chartCard(T('Distribuição', 'Distribution'),
          el('div', { class: 'chart-wrap' }, barChart(hData, { width: Math.max(460, nb * 40), height: 220, color: '#0aa', rotateLabels: true }))),
        chartCard(T('Mais rápida por linguagem', 'Fastest by language'),
          hBarChart(fData, { total: 0, fmt: (v) => v.toFixed(2) + 's' })))));
  }

  // --- nuvem de avatares (solvers públicos) ---
  const avs = s.solver_avatars || [];
  if (avs.length) {
    const cloud = el('div', { class: 'avatar-cloud' });
    avs.forEach((a) => cloud.append(
      el('a', { href: '/treino/stat/?user=' + encodeURIComponent(a.login), title: a.name || a.login }, avatarEl(a.login, a.name, 40, a.has_photo))));
    const total = s.solvers_public_count || avs.length;
    const more = total - avs.length;
    content.append(el('div', { class: 'section' },
      el('h2', {}, T('👥 Quem resolveu ', '👥 Who solved '), el('span', { class: 'small muted' }, T(`(${total} com perfil público)`, `(${total} with public profile)`))),
      cloud,
      more > 0 ? el('p', { class: 'small muted', style: 'margin-top:.5rem' }, T(`+${more} outros`, `+${more} others`)) : null));
  }
}
boot();
