// contest/jplag/jplag.js — roda o jplag nas soluções aceitas e mostra a similaridade.
//
// Quem vê: juiz, juiz-chefe e admin (o servidor corta em /contest/admin/jplag-results; o juiz
// comum recebe os pares só com o login). Quem dispara: chefe e admin (`can_run` da resposta).
//
// A tela (2026-09-14): antes empilhava TODAS as combinações problema×linguagem numa tripa —
// com 22 problemas era rolar sem fim p/ achar uma. Agora há uma barra de filtro: PROBLEMA e
// LINGUAGEM (selects, só o que existe) e LIMIAR de similaridade (0-100, default 50); a lista
// mostra só os pares que passam, numa tabela única ordenada pela similaridade. A escolha
// persiste em localStorage (por contest). Atualização EM LUGAR: o poll de 4 s durante a
// execução troca só a barra de status e a lista — nunca recria a página inteira (regra do
// auto-refresh em lugar: seleção e rolagem do juiz não somem).
import { apiGet, apiPost, getToken } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { initContestShell } from '/shared/contest-shell.js';
import { T } from '/shared/i18n.js';
import { swapIf, sigOf } from '/shared/admin-ui.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const enc = encodeURIComponent;
const G = { contest: CONTEST, auth: true };
const LS = 'moj.jplag.' + CONTEST;
const MAX_ROWS = 400;                 // teto de linhas na tabela (o resto vira "e mais N")
let pollTimer = null;
let DATA = { status: {}, results: [], can_run: false };
let F = { prob: '', lang: '', thr: 50 };   // filtro corrente
let ui = null;                        // nós fixos da página (montados uma vez)
let optKey = '';                      // assinatura das opções dos selects (problemas×langs)

const simClass = (s) => (s >= 80 ? 'sim-high' : s >= 50 ? 'sim-mid' : 'sim-low');
// "[UNIV] Time (login)" quando o run traz os campos (chefe/admin); juiz comum cai no login
const who = (name, login, univ) =>
  (name ? (univ ? '[' + univ + '] ' : '') + name + ' (' + login + ')' : login);

function loadFilter() {
  try { const j = JSON.parse(localStorage.getItem(LS) || 'null'); if (j && typeof j === 'object') F = { ...F, ...j }; } catch { /* sem storage */ }
  F.thr = Math.min(100, Math.max(0, +F.thr || 0));
}
function saveFilter() { try { localStorage.setItem(LS, JSON.stringify(F)); } catch { /* sem storage */ } }

function openMatch(run, i) {
  fetch('/api/v1/contest/admin/jplag-match?contest=' + enc(CONTEST) + '&run=' + enc(run) + '&i=' + i,
    { headers: { Authorization: 'Bearer ' + getToken(CONTEST) } })
    .then((r) => r.text()).then((html) => { const w = window.open(); if (w) { w.document.write(html); w.document.close(); } })
    .catch(() => alert(T('Falha ao abrir a comparação.', 'Failed to open the comparison.')));
}

// ---- derivados do filtro ----
const problems = () => [...new Set((DATA.results || []).map((r) => r.problem))].sort();
const langsFor = (p) => [...new Set((DATA.results || []).filter((r) => !p || r.problem === p).map((r) => r.lang))].sort();
// pares que passam no limiar, de todos os grupos que casam com (problema, linguagem)
function visiblePairs() {
  const out = [];
  (DATA.results || []).forEach((r) => {
    if (F.prob && r.problem !== F.prob) return;
    if (F.lang && r.lang !== F.lang) return;
    (r.pairs || []).forEach((p) => { if ((p.similarity || 0) >= F.thr) out.push({ ...p, problem: r.problem, lang: r.lang, run: r.run }); });
  });
  out.sort((a, b) => (b.similarity || 0) - (a.similarity || 0));
  return out;
}
const countAbove = (pred) => (DATA.results || []).filter(pred)
  .reduce((n, r) => n + (r.pairs || []).filter((p) => (p.similarity || 0) >= F.thr).length, 0);

// ---- montagem única ----
function mount() {
  const runBtn = el('button', { class: 'btn', onclick: run }, T('▶ Rodar jplag', '▶ Run jplag'));
  const refreshBtn = el('button', { class: 'btn ghost', onclick: load }, T('↻ Atualizar', '↻ Refresh'));
  const statusTxt = el('span', { class: 'small muted' });
  const progress = el('div', { class: 'muted small', hidden: true }, T('Análise em andamento — atualizando…', 'Analysis in progress — refreshing…'));
  const selProb = el('select', { class: 'jp-sel' });
  const selLang = el('select', { class: 'jp-sel' });
  const thrRange = el('input', { type: 'range', min: '0', max: '100', step: '1', value: String(F.thr), class: 'jp-range' });
  const thrNum = el('input', { type: 'number', min: '0', max: '100', step: '1', value: String(F.thr), class: 'jp-num' });
  const count = el('span', { class: 'small', style: 'font-weight:700' });
  const list = el('div');
  selProb.addEventListener('change', () => { F.prob = selProb.value; if (!langsFor(F.prob).includes(F.lang)) F.lang = ''; saveFilter(); renderFilters(true); renderList(); });
  selLang.addEventListener('change', () => { F.lang = selLang.value; saveFilter(); renderFilters(true); renderList(); });
  const setThr = (v) => { F.thr = Math.min(100, Math.max(0, +v || 0)); thrRange.value = String(F.thr); thrNum.value = String(F.thr); saveFilter(); renderFilters(true); renderList(); };
  thrRange.addEventListener('input', () => setThr(thrRange.value));
  thrNum.addEventListener('change', () => setThr(thrNum.value));
  const fld = (l, ...i) => el('label', { class: 'jp-fld' }, el('span', { class: 'small muted' }, l), ...i);
  app.innerHTML = '';
  app.append(
    el('div', { class: 'row', style: 'gap:.5rem;align-items:center;margin-bottom:.4rem;flex-wrap:wrap' }, runBtn, refreshBtn, statusTxt),
    el('p', { class: 'muted small', style: 'margin:.2rem 0 .6rem' },
      T('Compara a última solução aceita de cada usuário, por problema e linguagem. Vermelho = similaridade alta. Escolha o problema, a linguagem e o limiar: a lista mostra só os pares acima do limiar.',
        'Compares the latest accepted solution of each user, by problem and language. Red = high similarity. Pick the problem, the language and the threshold: the list shows only the pairs above the threshold.')),
    progress,
    el('div', { class: 'jp-bar' },
      fld(T('problema', 'problem'), selProb), fld(T('linguagem', 'language'), selLang),
      fld(T('limiar de similaridade', 'similarity threshold'), thrRange, thrNum, el('span', { class: 'small' }, '%')),
      count),
    list);
  ui = { runBtn, refreshBtn, statusTxt, progress, selProb, selLang, thrRange, thrNum, count, list };
}

function renderStatus() {
  const st = DATA.status || {};
  ui.runBtn.hidden = !DATA.can_run;
  ui.runBtn.disabled = !!st.running;
  ui.runBtn.textContent = st.running ? T('⏳ rodando…', '⏳ running…') : T('▶ Rodar jplag', '▶ Run jplag');
  ui.statusTxt.textContent = st.message || '';
  ui.progress.hidden = !st.running;
  clearTimeout(pollTimer); pollTimer = null;
  if (st.running) pollTimer = setTimeout(load, 4000);
}

// selects: reconstrói as opções só quando o CONJUNTO muda (ou quando as contagens mudam com o
// limiar — `force`); manter o mesmo <select> preserva o foco do juiz durante o poll
function renderFilters(force) {
  const ps = problems(); const ls = langsFor(F.prob);
  const key = ps.join('|') + '#' + ls.join('|') + '#' + F.thr + '#' + F.prob + '#' + F.lang;
  if (!force && key === optKey) return;
  optKey = key;
  if (F.prob && !ps.includes(F.prob)) F.prob = '';
  if (F.lang && !ls.includes(F.lang)) F.lang = '';
  ui.selProb.innerHTML = '';
  ui.selProb.append(el('option', { value: '' }, T('todos os problemas', 'all problems') + ' (' + countAbove(() => true) + ')'));
  ps.forEach((p) => ui.selProb.append(el('option', { value: p, selected: F.prob === p }, p + ' (' + countAbove((r) => r.problem === p) + ')')));
  ui.selProb.value = F.prob;
  ui.selLang.innerHTML = '';
  ui.selLang.append(el('option', { value: '' }, T('todas as linguagens', 'all languages')));
  ls.forEach((l) => ui.selLang.append(el('option', { value: l, selected: F.lang === l },
    l + ' (' + countAbove((r) => (!F.prob || r.problem === F.prob) && r.lang === l) + ')')));
  ui.selLang.value = F.lang;
}

// EM LUGAR: durante a análise o poll de 4 s só refaz a tabela de pares quando o CONJUNTO
// visível muda (assinatura: filtros + pares) — o scroll e o foco do juiz ficam
function renderList() {
  const st = DATA.status || {};
  const results = DATA.results || [];
  const pairs = results.length ? visiblePairs() : [];
  const sig = sigOf(F.prob, F.lang, F.thr, !!st.running, !!DATA.can_run, results.length,
    pairs.slice(0, MAX_ROWS).map((p) => [p.run, p.index, p.similarity, p.a, p.b]));
  swapIf(ui.list, sig, () => listBuild(st, results, pairs));
}
function listBuild(st, results, pairs) {
  const wrap = el('div', {});
  if (!results.length) {
    ui.count.textContent = '';
    wrap.append(el('div', { class: 'muted' }, st.running
      ? T('Sem resultados ainda.', 'No results yet.')
      : (DATA.can_run ? T('Sem resultados. Clique em “Rodar jplag”.', 'No results. Click "Run jplag".')
        : T('Sem resultados. O admin ou o juiz-chefe precisa rodar o jplag.', 'No results. The admin or the chief judge has to run jplag.'))));
    return wrap;
  }
  const total = (DATA.results || []).filter((r) => (!F.prob || r.problem === F.prob) && (!F.lang || r.lang === F.lang))
    .reduce((n, r) => n + (r.pairs || []).length, 0);
  ui.count.textContent = T(`${pairs.length} par(es) ≥ ${F.thr}% (de ${total})`, `${pairs.length} pair(s) ≥ ${F.thr}% (of ${total})`);
  if (!pairs.length) {
    wrap.append(el('div', { class: 'muted small', style: 'margin:.5rem 0' },
      T('Nenhum par acima do limiar. Baixe o limiar para ver mais.', 'No pair above the threshold. Lower the threshold to see more.')));
    return wrap;
  }
  const showProb = !F.prob, showLang = !F.lang;
  const tb = el('tbody');
  pairs.slice(0, MAX_ROWS).forEach((p) => tb.append(el('tr', {},
    showProb ? el('td', { class: 'jp-prob' }, p.problem) : null,
    showLang ? el('td', { class: 'small muted' }, p.lang) : null,
    el('td', {}, who(p.a_name, p.a_login || p.a, p.a_univ)),
    el('td', {}, who(p.b_name, p.b_login || p.b, p.b_univ)),
    el('td', { class: 'n ' + simClass(p.similarity) }, (p.similarity || 0).toFixed(1) + '%'),
    el('td', {}, el('a', { href: '#', onclick: (e) => { e.preventDefault(); openMatch(p.run, p.index); } }, T('ver lado-a-lado', 'view side-by-side'))))));
  wrap.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
    el('thead', {}, el('tr', {},
      showProb ? el('th', {}, T('Problema', 'Problem')) : null,
      showLang ? el('th', {}, T('Ling.', 'Lang.')) : null,
      el('th', {}, T('Solução A', 'Solution A')), el('th', {}, T('Solução B', 'Solution B')),
      el('th', { class: 'n' }, T('Similaridade', 'Similarity')), el('th', {}, ''))), tb)));
  if (pairs.length > MAX_ROWS) wrap.append(el('div', { class: 'small muted', style: 'margin:.4rem 0' },
    T(`mostrando ${MAX_ROWS} de ${pairs.length} — suba o limiar ou escolha um problema para ver o resto`,
      `showing ${MAX_ROWS} of ${pairs.length} — raise the threshold or pick a problem to see the rest`)));
  return wrap;
}

function render() { renderStatus(); renderFilters(false); renderList(); }

async function load() {
  try {
    const d = await apiGet('/contest/admin/jplag-results?contest=' + enc(CONTEST), G);
    DATA = { status: d.status || {}, results: d.results || [], can_run: d.can_run === true };
    render();
  } catch (e) {
    ui.list.innerHTML = ''; ui.list.append(el('div', { class: 'error-box' }, T('Falha: ', 'Error: ') + (e.message || T('erro', 'error'))));
  }
}
async function run() {
  try { await apiPost('/contest/admin/jplag-run?contest=' + enc(CONTEST), {}, G); setTimeout(load, 600); }
  catch (e) { alert(e.message || T('falha', 'failed')); }
}

async function boot() {
  if (!CONTEST) { app.innerHTML = '<div class="error-box">' + T('Contest não informado.', 'Contest not specified.') + '</div>'; return; }
  const { st } = await initContestShell(CONTEST);
  if (!st || !st.logged_in || !(st.is_judge || st.is_admin)) {
    app.innerHTML = '';
    app.append(el('div', { class: 'section' }, el('h2', {}, T('🔒 Acesso restrito', '🔒 Access restricted')),
      el('p', { class: 'small muted' }, T('Esta página é do juiz, do juiz-chefe e do admin.', 'This page is for the judge, the chief judge and the admin.')),
      el('a', { class: 'btn', href: '/contest/login/?c=' + enc(CONTEST) }, T('Login do contest', 'Contest login'))));
    return;
  }
  loadFilter();
  mount();
  load();
}
boot();
