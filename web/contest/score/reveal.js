// contest/score/reveal.js — CERIMÔNIA DE REVELAÇÃO nativa (estilo ICPC resolver, sem Java).
// Admin/juiz: carrega o placar CONGELADO (view=public) e o COMPLETO (privilegiado), computa o
// delta por célula e revela de baixo para cima — espaço/→ avança um passo (a célula pendente
// mais à esquerda do time do cursor); quando o time sobe, a linha anima e o cursor fica na
// mesma posição (outro time caiu nela). "Descongelar tudo" publica o placar completo
// (settings freeze=0; só admin). Só faz sentido em modo icpc com FREEZE_TIME configurado.
// .cstaff (chefe de sede): as mesmas duas chamadas levam &scope=mine — a API recorta as
// DUAS visões aos usuários da sede dele (staff-filters) e só libera o full depois que o
// contest termina para TODAS as sedes; a cerimônia local revela só a sede.
import { el } from '/shared/ui.js';
import { apiGet, apiGetText, apiPost, getToken } from '/shared/api.js';
import { status } from '/shared/auth.js';
import { parseICPC } from './score-icpc.js';
import { balloonColorHex, balloonIsDark } from './score-colors.js';
import { flagEl } from '/shared/flags.js';

const CONTEST = new URLSearchParams(location.search).get('c') || '';
const G = { contest: CONTEST, auth: true };
const enc = encodeURIComponent;
const app = document.getElementById('app');

let PEN = 20;                 // PENALTY_MINUTES (settings; fallback 20)
let balloons = {};
let probShorts = [];
let teams = [];               // [{username, teamName, univShort, flag, cells:{sn:v}, fullCells:{sn:v}}]
let cursor = -1;              // índice na ordem ATUAL (de baixo p/ cima)
let finished = false;
let timer = null;

const cellSolvedRe = /^(\d+)\/(\d+)\/?\*?$/;
function cellPenalty(v) {
  const m = cellSolvedRe.exec(v || ''); if (!m) return null;
  return { tries: +m[1], min: +m[2], pen: (+m[1] - 1) * PEN + +m[2] };
}
function standingsSort(list) {
  return list.slice().sort((a, b) => {
    if (b.solved !== a.solved) return b.solved - a.solved;
    if (a.penalty !== b.penalty) return a.penalty - b.penalty;
    return a.username.localeCompare(b.username);
  });
}
function recompute(t) {
  t.solved = 0; t.penalty = 0;
  probShorts.forEach(sn => { const c = cellPenalty(t.cells[sn]); if (c) { t.solved++; t.penalty += c.pen; } });
}
function pendingCells(t) { return probShorts.filter(sn => (t.cells[sn] || '') !== (t.fullCells[sn] || '')); }

function render(highlight) {
  const box = document.getElementById('board'); box.innerHTML = '';
  const ordered = standingsSort(teams);
  const table = el('table', { class: 'score' });
  const hr = el('tr', {}, el('th', {}, '#'), el('th', {}, ''), el('th', {}, 'Equipe'));
  probShorts.forEach(sn => hr.append(el('th', {}, sn)));
  hr.append(el('th', {}, 'Total'), el('th', {}, 'Penal.'));
  table.append(el('thead', {}, hr));
  const tb = el('tbody');
  ordered.forEach((t, i) => {
    const tr = el('tr', {});
    if (i === cursor && !finished) tr.style.outline = '3px solid #1e57c4';
    if (highlight && highlight.user === t.username) tr.classList.add(highlight.up ? 'placing-up' : 'placing-down');
    tr.append(el('td', { class: 'cl-place' }, String(i + 1)));
    const ftd = el('td', {}); if (t.flag) { const fi = flagEl(t.flag, { height: 16 }); if (fi) ftd.append(fi); }
    tr.append(ftd);
    tr.append(el('td', { class: 'team', title: t.univFull || '' },
      (t.univShort ? '[' + t.univShort + '] ' : '') + (t.teamName || t.username)));
    probShorts.forEach(sn => {
      const v = t.cells[sn] || '';
      const pend = (v !== (t.fullCells[sn] || ''));
      const td = el('td', {});
      if (cellSolvedRe.test(v)) {
        const fts = v.endsWith('*');
        td.textContent = (fts ? '★ ' : '') + (fts ? v.slice(0, -1) : v);
        const color = balloonColorHex(balloons, sn);
        td.style.background = color || '#e2ffe9';
        td.style.color = color && balloonIsDark(color) ? '#fff' : '#222';
        td.style.fontWeight = '700';
        if (fts) td.style.boxShadow = 'inset 0 0 0 2px currentColor';
      } else if (pend) {
        td.textContent = (v && v !== ':' ? v.replace(/\/-$/, '') + ' ' : '') + '?';
        td.className = 'prob-wait-cell';
      } else td.textContent = v;
      tr.append(td);
    });
    tr.append(el('td', { style: 'font-weight:800' }, String(t.solved)),
              el('td', {}, String(t.penalty)));
    tb.append(tr);
  });
  table.append(tb);
  box.append(table);
  const st = document.getElementById('status');
  st.textContent = finished ? 'Cerimônia concluída — placar final revelado. 🎉'
    : cursor < 0 ? 'Pronto. Espaço/→ (ou ▶ Auto) para revelar de baixo para cima.'
    : `Revelando: ${ordered[cursor]?.teamName || ordered[cursor]?.username || ''} (${cursor + 1}º)`;
}

// um passo da cerimônia: revela a próxima célula pendente do time do cursor; sem pendências,
// o cursor sobe. Devolve false quando acabou.
function step() {
  if (finished) return false;
  const ordered = standingsSort(teams);
  if (cursor < 0) { cursor = ordered.length - 1; render(); return true; }
  if (cursor >= ordered.length) cursor = ordered.length - 1;
  const t = ordered[cursor];
  const pend = pendingCells(t);
  if (!pend.length) {
    cursor--;
    if (cursor < 0) { finished = true; render(); return false; }
    render(); return true;
  }
  const sn = pend[0];
  const before = ordered.findIndex(x => x.username === t.username);
  t.cells[sn] = t.fullCells[sn] || '';
  recompute(t);
  const after = standingsSort(teams).findIndex(x => x.username === t.username);
  render({ user: t.username, up: after < before });
  return true;
}

async function unfreezeAll() {
  if (!confirm('Descongelar TUDO: o placar público passa a mostrar o resultado completo (freeze desligado). Continuar?')) return;
  try {
    await apiPost('/contest/admin/settings?contest=' + enc(CONTEST), { freeze: 0 }, G);
    document.getElementById('status').textContent = '✓ freeze desligado — o placar público já mostra tudo.';
  } catch (e) { alert(e.message || 'falha (precisa ser admin)'); }
}

async function main() {
  if (!CONTEST) { app.textContent = 'Faltou ?c=<contest>'; return; }
  if (!getToken(CONTEST)) { app.textContent = 'Faça login no contest primeiro (admin/juiz/chefe de sede).'; return; }
  let st = {};
  try { st = await status(CONTEST) || {}; } catch { st = {}; }
  const CSTAFF = !!(st.logged_in && st.is_cstaff && !st.is_judge && !st.is_admin);
  const scopeQ = CSTAFF ? '&scope=mine' : '';
  let frozenTxt, fullTxt;
  try {
    [frozenTxt, fullTxt] = await Promise.all([
      apiGetText('/contest/score?contest=' + enc(CONTEST) + '&view=public' + scopeQ, G),
      apiGetText('/contest/score?contest=' + enc(CONTEST) + scopeQ, G),
    ]);
  } catch (e) { app.textContent = 'Falha ao carregar o placar: ' + (e.message || 'erro'); return; }
  const fl = frozenTxt.split('\n'), ul = fullTxt.split('\n');
  if ((fl[0] || '').trim() !== 'icpc' || (ul[0] || '').trim() !== 'icpc') {
    app.textContent = 'A cerimônia é só para contests em modo icpc.'; return;
  }
  try { balloons = await apiGet('/contest/balloons?contest=' + enc(CONTEST), G); } catch { balloons = {}; }
  if (!CSTAFF) {
    try { const s = await apiGet('/contest/admin/settings?contest=' + enc(CONTEST), G); if (Number.isInteger(s.penalty_minutes)) PEN = s.penalty_minutes; } catch { /* .judge sem settings: PEN=20 */ }
  }
  const frozen = parseICPC(fl.slice(1), balloons), full = parseICPC(ul.slice(1), balloons);
  if (!frozen || !full) { app.textContent = 'Placar vazio.'; return; }
  probShorts = full.probShorts;
  const fmap = {}; full.teams.forEach(t => { fmap[t.username] = t; });
  teams = frozen.teams.map(t => ({
    username: t.username, teamName: t.teamName, univShort: t.univShort, univFull: t.univFull,
    flag: t.flag, cells: { ...t.probs }, fullCells: { ...(fmap[t.username]?.probs || t.probs) },
  }));
  // times que só aparecem no full (ex.: 1ª submissão pós-freeze com placar por atividade)
  full.teams.forEach(t => {
    if (!teams.some(x => x.username === t.username)) {
      teams.push({ username: t.username, teamName: t.teamName, univShort: t.univShort,
        univFull: t.univFull, flag: t.flag, cells: {}, fullCells: { ...t.probs } });
    }
  });
  teams.forEach(recompute);
  const totalPend = teams.reduce((n, t) => n + pendingCells(t).length, 0);

  // cstaff antes do fim-para-todos: a API serviu frozen nas duas chamadas (0 pendências).
  // Conveniência de UX — a garantia é o gate do /contest/score.
  if (CSTAFF && totalPend === 0) {
    try {
      const b = await apiGet('/contest/basic?contest=' + enc(CONTEST), G);
      if ((b.end_time || 0) > Math.floor(Date.now() / 1000)) {
        app.textContent = 'A revelação da sua sede abre quando o contest termina para todas as sedes.';
        return;
      }
    } catch { /* segue: 0 pendências com contest encerrado é cerimônia vazia legítima */ }
  }

  app.innerHTML = '';
  const stepBtn = el('button', { class: 'btn', onclick: () => step() }, '⏭ Passo (espaço)');
  const autoBtn = el('button', { class: 'btn ghost' }, '▶ Auto');
  autoBtn.addEventListener('click', () => {
    if (timer) { clearInterval(timer); timer = null; autoBtn.textContent = '▶ Auto'; return; }
    autoBtn.textContent = '⏸ Pausar';
    timer = setInterval(() => { if (!step()) { clearInterval(timer); timer = null; autoBtn.textContent = '▶ Auto'; } }, 1400);
  });
  // descongelar é POST admin-only — o botão só aparece p/ admin (juiz/cstaff não podem)
  const unfreezeBtn = st.is_admin
    ? el('button', { class: 'btn danger ghost', onclick: unfreezeAll }, '🔓 Descongelar tudo (público)') : '';
  app.append(
    el('div', { class: 'row', style: 'gap:.5rem;align-items:center;margin-bottom:.6rem;flex-wrap:wrap' },
      stepBtn, autoBtn, unfreezeBtn,
      el('span', { class: 'muted small' }, totalPend + ' célula(s) pendente(s)'
        + (CSTAFF ? ' · recorte da sede de ' + (st.login || '') : ''))),
    el('div', { id: 'status', class: 'small', style: 'margin-bottom:.5rem;font-weight:600' }),
    el('div', { id: 'board' }));
  document.addEventListener('keydown', (e) => {
    if (e.code === 'Space' || e.code === 'ArrowRight') { e.preventDefault(); step(); }
  });
  render();
}
main();
