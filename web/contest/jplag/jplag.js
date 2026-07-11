// contest/jplag/jplag.js — roda o jplag nas soluções aceitas e mostra a similaridade.
import { apiGet, apiPost, getToken } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { initContestShell } from '/shared/contest-shell.js';
import { T } from '/shared/i18n.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const enc = encodeURIComponent;
const G = { contest: CONTEST, auth: true };
let pollTimer = null;

const simClass = (s) => (s >= 80 ? 'sim-high' : s >= 50 ? 'sim-mid' : 'sim-low');

function openMatch(run, i) {
  fetch('/api/v1/contest/admin/jplag-match?contest=' + enc(CONTEST) + '&run=' + enc(run) + '&i=' + i,
    { headers: { Authorization: 'Bearer ' + getToken(CONTEST) } })
    .then((r) => r.text()).then((html) => { const w = window.open(); if (w) { w.document.write(html); w.document.close(); } })
    .catch(() => alert(T('Falha ao abrir a comparação.', 'Failed to open the comparison.')));
}

function render(data) {
  clearTimeout(pollTimer);
  app.innerHTML = '';
  const st = data.status || {};
  app.append(el('div', { class: 'row', style: 'margin-bottom:.6rem' },
    el('button', { class: 'btn', disabled: !!st.running, onclick: run }, st.running ? T('⏳ rodando…', '⏳ running…') : T('▶ Rodar jplag', '▶ Run jplag')),
    el('button', { class: 'btn ghost', onclick: load }, T('↻ Atualizar', '↻ Refresh')),
    el('span', { class: 'small muted' }, st.message || '')));
  app.append(el('p', { class: 'muted small' }, T('Compara a última solução aceita de cada usuário, por problema e linguagem. Vermelho = similaridade alta.', 'Compares the latest accepted solution of each user, by problem and language. Red = high similarity.')));
  const results = data.results || [];
  if (st.running) { app.append(el('div', { class: 'muted' }, T('Análise em andamento — atualizando…', 'Analysis in progress — refreshing…'))); pollTimer = setTimeout(load, 4000); }
  if (!results.length) { if (!st.running) app.append(el('div', { class: 'muted' }, T('Sem resultados. Clique em “Rodar jplag”.', 'No results. Click "Run jplag".'))); return; }
  results.forEach((r) => {
    const sec = el('div', { class: 'section' }, el('h3', {}, T('Problema ', 'Problem ') + r.problem + ' · ' + r.lang + ' · ' + r.submissions + T(' soluções', ' solutions')));
    if (!r.pairs || !r.pairs.length) { sec.append(el('div', { class: 'muted small' }, T('nenhum par acima do limite.', 'no pairs above the threshold.'))); app.append(sec); return; }
    const tb = el('tbody');
    r.pairs.forEach((p) => tb.append(el('tr', {},
      el('td', {}, p.a), el('td', {}, p.b),
      el('td', { class: 'n ' + simClass(p.similarity) }, (p.similarity || 0).toFixed(1) + '%'),
      el('td', {}, el('a', { href: '#', onclick: (e) => { e.preventDefault(); openMatch(r.run, p.index); } }, T('ver lado-a-lado', 'view side-by-side'))))));
    sec.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, T('Solução A', 'Solution A')), el('th', {}, T('Solução B', 'Solution B')), el('th', {}, T('Similaridade', 'Similarity')), el('th', {}, ''))), tb)));
    app.append(sec);
  });
}

async function load() {
  try { render(await apiGet('/contest/admin/jplag-results?contest=' + enc(CONTEST), G)); }
  catch (e) { app.innerHTML = ''; app.append(el('div', { class: 'error-box' }, T('Falha: ', 'Error: ') + (e.message || T('erro', 'error')))); }
}
async function run() {
  try { await apiPost('/contest/admin/jplag-run?contest=' + enc(CONTEST), {}, G); setTimeout(load, 600); }
  catch (e) { alert(e.message || T('falha', 'failed')); }
}

async function boot() {
  if (!CONTEST) { app.innerHTML = '<div class="error-box">' + T('Contest não informado.', 'Contest not specified.') + '</div>'; return; }
  const { st } = await initContestShell(CONTEST);
  if (!st || !st.logged_in || !st.is_admin) {
    app.innerHTML = '';
    app.append(el('div', { class: 'section' }, el('h2', {}, T('🔒 Acesso restrito', '🔒 Access restricted')),
      el('a', { class: 'btn', href: '/contest/login/?c=' + enc(CONTEST) }, T('Login do contest', 'Contest login'))));
    return;
  }
  load();
}
boot();
