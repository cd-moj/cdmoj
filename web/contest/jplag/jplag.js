// contest/jplag/jplag.js — roda o jplag nas soluções aceitas e mostra a similaridade.
import { apiGet, apiPost, getToken } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { initContestShell } from '/shared/contest-shell.js';

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
    .catch(() => alert('Falha ao abrir a comparação.'));
}

function render(data) {
  clearTimeout(pollTimer);
  app.innerHTML = '';
  const st = data.status || {};
  app.append(el('div', { class: 'row', style: 'margin-bottom:.6rem' },
    el('button', { class: 'btn', disabled: !!st.running, onclick: run }, st.running ? '⏳ rodando…' : '▶ Rodar jplag'),
    el('button', { class: 'btn ghost', onclick: load }, '↻ Atualizar'),
    el('span', { class: 'small muted' }, st.message || '')));
  app.append(el('p', { class: 'muted small' }, 'Compara a última solução aceita de cada usuário, por problema e linguagem. Vermelho = similaridade alta.'));
  const results = data.results || [];
  if (st.running) { app.append(el('div', { class: 'muted' }, 'Análise em andamento — atualizando…')); pollTimer = setTimeout(load, 4000); }
  if (!results.length) { if (!st.running) app.append(el('div', { class: 'muted' }, 'Sem resultados. Clique em “Rodar jplag”.')); return; }
  results.forEach((r) => {
    const sec = el('div', { class: 'section' }, el('h3', {}, 'Problema ' + r.problem + ' · ' + r.lang + ' · ' + r.submissions + ' soluções'));
    if (!r.pairs || !r.pairs.length) { sec.append(el('div', { class: 'muted small' }, 'nenhum par acima do limite.')); app.append(sec); return; }
    const tb = el('tbody');
    r.pairs.forEach((p) => tb.append(el('tr', {},
      el('td', {}, p.a), el('td', {}, p.b),
      el('td', { class: 'n ' + simClass(p.similarity) }, (p.similarity || 0).toFixed(1) + '%'),
      el('td', {}, el('a', { href: '#', onclick: (e) => { e.preventDefault(); openMatch(r.run, p.index); } }, 'ver lado-a-lado')))));
    sec.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, 'Solução A'), el('th', {}, 'Solução B'), el('th', {}, 'Similaridade'), el('th', {}, ''))), tb)));
    app.append(sec);
  });
}

async function load() {
  try { render(await apiGet('/contest/admin/jplag-results?contest=' + enc(CONTEST), G)); }
  catch (e) { app.innerHTML = ''; app.append(el('div', { class: 'error-box' }, 'Falha: ' + (e.message || 'erro'))); }
}
async function run() {
  try { await apiPost('/contest/admin/jplag-run?contest=' + enc(CONTEST), {}, G); setTimeout(load, 600); }
  catch (e) { alert(e.message || 'falha'); }
}

async function boot() {
  if (!CONTEST) { app.innerHTML = '<div class="error-box">Contest não informado.</div>'; return; }
  const { st } = await initContestShell(CONTEST);
  if (!st || !st.logged_in || !st.is_admin) {
    app.innerHTML = '';
    app.append(el('div', { class: 'section' }, el('h2', {}, '🔒 Acesso restrito'),
      el('a', { class: 'btn', href: '/contest/login/?c=' + enc(CONTEST) }, 'Login do contest')));
    return;
  }
  load();
}
boot();
