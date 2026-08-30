// contest/statistics/statistics.js — estatísticas ricas do contest (admin/juiz/monitor).
// As SEÇÕES moram em /lib/stats-view.js: o relatório offline (server/score/report-gen.sh)
// inlina o mesmo módulo, então as duas telas não podem divergir.
// R2 (2026-08-30): recorte por SEDE ou PAÍS — dois selects mutuamente exclusivos. O
// servidor já entrega tudo pronto (by_region/by_country no cache do stats-gen, mesmo
// shape do global); aqui só se escolhe qual sub-objeto renderizar.
import { apiGet } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { mountChrome } from '/lib/contest-chrome.js';
import { statsSections } from '/lib/stats-view.js';
import { T } from '/shared/i18n.js';
import { flagManifest } from '/shared/flags.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const enc = encodeURIComponent;
let probMap = {};
let statsAll = null;
let flagNames = {};
let regionsTree = [];              // árvore do regions.json — MESMA curadoria do placar
let dim = { kind: '', key: '' };   // ''=global, 'r'=sede, 'c'=país

function flagLabel(c) { return flagNames[String(c).toLowerCase()] || String(c).toUpperCase(); }

// opções de Sede = a ÁRVORE do regions.json (mesma ordem e indentação do seletor do
// placar: país › região/supersede › sede), só com os nós que TÊM recorte computado
// (by_region — o stats-gen agrega os nós de cima por regex, como o regionMatch), mais as
// sedes do .team.region que não estão na árvore (depth 0, no fim, como no placar).
function regionOpts() {
  const have = statsAll.by_region || {};
  const out = [];
  const walk = (list, depth) => (list || []).forEach((r) => {
    if (r.name && Object.prototype.hasOwnProperty.call(have, r.name)) out.push({ name: r.name, depth });
    if (Array.isArray(r.subregions) && r.subregions.length) walk(r.subregions, depth + 1);
  });
  walk(regionsTree, 0);
  const seen = new Set(out.map((o) => o.name.toLowerCase()));
  Object.keys(have).sort((a, b) => a.localeCompare(b)).forEach((n) => {
    if (!seen.has(n.toLowerCase())) out.push({ name: n, depth: 0 });
  });
  return out;
}

function currentStats() {
  if (dim.kind === 'r') return (statsAll.by_region || {})[dim.key] || statsAll;
  if (dim.kind === 'c') return (statsAll.by_country || {})[dim.key] || statsAll;
  return statsAll;
}

// mesma gramática da barra do placar (fRegion/fFlag): sede filtra por nome, país pela
// chave de bandeira. Escolher um zera o outro — o recorte é UM, nunca a interseção.
function filterBar() {
  const regs = regionOpts();
  const ctys = Object.keys(statsAll.by_country || {})
    .sort((a, b) => flagLabel(a).localeCompare(flagLabel(b)));
  if (!regs.length && !ctys.length) return null;
  const bar = el('div', { class: 'fbar' });
  let selR = null; let selC = null;
  if (regs.length) {
    selR = el('select', { id: 'fRegion' }, el('option', { value: '' }, T('todas', 'all')),
      ...regs.map((r) => el('option', { value: r.name }, '  '.repeat(r.depth) + r.name)));
    selR.value = dim.kind === 'r' ? dim.key : '';
    selR.addEventListener('change', () => {
      dim = selR.value ? { kind: 'r', key: selR.value } : { kind: '', key: '' };
      render();
    });
    bar.append(el('label', {}, T('Sede:', 'Site:'), selR));
  }
  if (ctys.length) {
    selC = el('select', { id: 'fFlag' }, el('option', { value: '' }, T('todos', 'all')),
      ...ctys.map((c) => el('option', { value: c }, flagLabel(c))));
    selC.value = dim.kind === 'c' ? dim.key : '';
    selC.addEventListener('change', () => {
      dim = selC.value ? { kind: 'c', key: selC.value } : { kind: '', key: '' };
      render();
    });
    bar.append(el('label', {}, T('País:', 'Country:'), selC));
  }
  const note = el('span', { class: 'fcount', id: 'fCount' });
  if (dim.kind) {
    const s = currentStats();
    const nm = dim.kind === 'c' ? flagLabel(dim.key) : dim.key;
    note.textContent = T(`Recorte: ${nm} — ${s.totals.users} de ${statsAll.totals.users} participantes`,
      `Selection: ${nm} — ${s.totals.users} of ${statsAll.totals.users} participants`);
    bar.append(el('button', { type: 'button', onclick: () => { dim = { kind: '', key: '' }; render(); } },
      T('limpar', 'clear')));
  } else {
    note.textContent = T(`${statsAll.totals.users} participantes`, `${statsAll.totals.users} participants`);
  }
  bar.append(note);
  return bar;
}

function render() {
  app.innerHTML = '';
  const bar = filterBar();
  if (bar) app.append(bar);
  statsSections(currentStats(), { probMap }).forEach((sec) => app.append(sec));
}

async function boot() {
  if (!CONTEST) { app.innerHTML = '<div class="error-box">' + T('Contest não informado.', 'Contest not specified.') + '</div>'; return; }
  let basic = null;
  try { basic = await apiGet('/contest/basic?contest=' + enc(CONTEST), {}); } catch { /* segue */ }
  try { await mountChrome(CONTEST, basic); } catch { /* nav opcional */ }
  let s;
  try { s = await apiGet('/contest/statistics?contest=' + enc(CONTEST), { contest: CONTEST, auth: true }); }
  catch (e) {
    app.innerHTML = '';
    app.append(el('div', { class: 'section' }, el('h2', {}, T('🔒 Restrito', '🔒 Restricted')),
      el('p', { class: 'muted' }, T('Estatísticas são visíveis a admin, juiz ou monitor do contest. (', 'Statistics are visible to the contest admin, judge or monitor. (') + (e.message || T('erro', 'error')) + ')')));
    return;
  }
  try { const pr = await apiGet('/contest/problems?contest=' + enc(CONTEST), { contest: CONTEST, auth: true }); (pr.problems || []).forEach((p) => { probMap[p.problem_id] = p.short_name; }); } catch { /* sem map */ }
  try {
    const mani = await flagManifest();
    (mani.countries || []).forEach((c) => { flagNames[c.code] = c.name; });
    (mani.br_states || []).forEach((st) => { flagNames['br-' + st.code] = st.name; });
  } catch { /* rótulo cai no código */ }
  try {
    const rg = await apiGet('/contest/regions?contest=' + enc(CONTEST), { contest: CONTEST, auth: true });
    regionsTree = rg ? (Array.isArray(rg) ? rg : (rg.regions || [])) : [];
  } catch { /* sem árvore: as sedes saem ordenadas, como antes */ }
  statsAll = s;
  render();
}
boot();
