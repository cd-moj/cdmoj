// contest/staff/staff.js — área do .staff: fila de tarefas de impressão + modo automático.
// Fluxo: pegar (claim) → imprimir o PDF gerado (capa+doc) → marcar entregue.
// Modo automático: deixe a aba aberta; cada tarefa nova é reservada, impressa e marcada
// como "processada" assim que a impressão dispara (onafterprint / timeout).
import { apiGet, apiPost, getToken } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { initContestShell } from '/shared/contest-shell.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const G = { contest: CONTEST, auth: true };
const enc = encodeURIComponent;
const fmtDate = (e) => new Date((+e || 0) * 1000).toLocaleString('pt-BR');
const AUTOKEY = 'moj_autoprint_' + CONTEST;

const STATUS = {
  pending:   { t: '🕓 pendente',   c: '' },
  printed:   { t: '🖨️ processada', c: 'color:#0a7' },
  delivered: { t: '✅ entregue',    c: 'color:#0a7; font-weight:600' },
};

let queue = [];            // último estado da fila
let autoMode = false;      // modo automático
let busy = false;          // processando uma tarefa (evita diálogos sobrepostos)
const seen = new Set();    // ids já auto-processados nesta sessão (não reimprimir)
let pollT = null;

// busca o PDF combinado (com Bearer) como blob -> URL temporária (sem token na URL)
async function pdfBlobUrl(id) {
  const r = await fetch('/api/v1/contest/staff/print-pdf?contest=' + enc(CONTEST) + '&id=' + enc(id),
    { headers: { 'Authorization': 'Bearer ' + (getToken(CONTEST) || '') } });
  if (!r.ok) throw new Error('HTTP ' + r.status);
  return URL.createObjectURL(await r.blob());
}

// imprime um blob num iframe oculto; resolve quando a impressão dispara (ou após timeout)
function printBlob(url) {
  return new Promise((res) => {
    const ifr = el('iframe', { style: 'position:fixed;right:0;bottom:0;width:1px;height:1px;border:0;visibility:hidden' });
    let done = false;
    const fin = () => { if (done) return; done = true; setTimeout(() => ifr.remove(), 1500); res(); };
    ifr.onload = () => { try { const w = ifr.contentWindow; w.focus(); w.onafterprint = fin; w.print(); setTimeout(fin, 8000); } catch (_) { fin(); } };
    ifr.src = url; document.body.append(ifr);
  });
}

async function action(id, act, extra) {
  return apiPost('/contest/staff/print-action?contest=' + enc(CONTEST), Object.assign({ id, action: act }, extra || {}), G);
}

// imprime uma tarefa (claim implícito) e marca processada. mode: 'auto' | 'manual'.
async function printTask(t, mode) {
  const url = await pdfBlobUrl(t.id);
  try { await printBlob(url); } finally { URL.revokeObjectURL(url); }
  await action(t.id, 'processed', { mode });
}

// passo do modo automático: uma tarefa pendente por vez (reserva antes de imprimir)
async function autoTick() {
  if (!autoMode || busy) return;
  const t = queue.find((x) => x.status === 'pending' && !seen.has(x.id));
  if (!t) return;
  busy = true; seen.add(t.id);
  try {
    await action(t.id, 'claim');              // reserva (409 already_claimed => outra aba pegou)
    await printTask(t, 'auto');
  } catch (e) {
    if (!(e && e.code === 'already_claimed')) seen.delete(t.id);  // erro real: permite retry
  } finally {
    busy = false; await loadQueue();
  }
}

const statusBar = el('div', { class: 'small muted' });
const tbody = el('tbody', {});

function rowActions(t) {
  const r = el('div', { class: 'row' });
  const mkBtn = (label, fn, cls) => { const b = el('button', { class: 'btn ' + (cls || 'ghost'), style: 'padding:.2rem .5rem' }, label);
    b.addEventListener('click', async () => { b.disabled = true; try { await fn(); } catch (e) { alert(e.message || 'falha'); } finally { b.disabled = false; await loadQueue(); } }); return b; };
  if (t.status === 'pending') r.append(mkBtn('Pegar', () => action(t.id, 'claim')));
  if (t.status !== 'delivered') r.append(mkBtn('🖨️ Imprimir', () => printTask(t, 'manual'), ''));
  r.append(mkBtn('Abrir PDF', async () => { const u = await pdfBlobUrl(t.id); window.open(u, '_blank'); setTimeout(() => URL.revokeObjectURL(u), 60000); }));
  if (t.status === 'printed') r.append(mkBtn('✅ Entregue', () => action(t.id, 'delivered'), ''));
  return r;
}

function renderRows() {
  tbody.innerHTML = '';
  if (!queue.length) { tbody.append(el('tr', {}, el('td', { colspan: '6', class: 'muted' }, 'Nenhuma tarefa.'))); return; }
  queue.forEach((t) => {
    const st = STATUS[t.status] || STATUS.pending;
    tbody.append(el('tr', {},
      el('td', {}, el('b', {}, '#' + t.seq)),
      el('td', {}, el('div', {}, t.team || t.fullname || t.login), el('div', { class: 'small muted' }, t.login)),
      el('td', {}, t.filename, el('div', { class: 'small muted' }, (t.mime || '') + (t.size ? ' · ' + Math.max(1, Math.round(t.size / 1024)) + ' KB' : ''))),
      el('td', {}, el('span', { class: 'pr-badge', style: st.c }, st.t),
        (t.claimed_by ? el('div', { class: 'small muted' }, 'por ' + t.claimed_by) : '')),
      el('td', { class: 'small' }, (t.pages > 0 ? t.pages + ' pág.' : '—'), el('div', { class: 'small muted' }, fmtDate(t.time))),
      el('td', {}, rowActions(t))));
  });
}

async function loadQueue() {
  let r;
  try { r = await apiGet('/contest/staff/queue?contest=' + enc(CONTEST), G); }
  catch (e) { statusBar.textContent = 'Falha ao listar: ' + (e.message || 'erro'); return; }
  queue = r.requests || [];
  const np = queue.filter((x) => x.status === 'pending').length;
  statusBar.textContent = queue.length + ' tarefa(s) · ' + np + ' pendente(s)' + (autoMode ? ' · modo automático LIGADO' : '');
  renderRows();
  autoTick();   // dispara o automático se houver pendente
}

function schedulePoll() {
  if (pollT) clearTimeout(pollT);
  pollT = setTimeout(async () => { await loadQueue(); schedulePoll(); }, 5000 + Math.random() * 3000);
}

function render() {
  app.innerHTML = '';
  const autoBox = el('label', { class: 'pr-auto' + (autoMode ? ' on' : '') });
  const cb = el('input', { type: 'checkbox' }); cb.checked = autoMode;
  cb.addEventListener('change', () => {
    autoMode = cb.checked; localStorage.setItem(AUTOKEY, autoMode ? '1' : '0');
    autoBox.className = 'pr-auto' + (autoMode ? ' on' : ''); loadQueue();
  });
  autoBox.append(cb, el('span', {}, el('b', {}, ' Modo impressão automática'),
    el('span', { class: 'small muted' }, ' — imprime cada tarefa nova e marca como processada. Para impressão sem o diálogo do sistema, use o navegador em modo kiosk (--kiosk-printing).')));
  const table = el('table', { class: 'moj' },
    el('thead', {}, el('tr', {}, el('th', {}, '#'), el('th', {}, 'Time / login'), el('th', {}, 'Arquivo'), el('th', {}, 'Status'), el('th', {}, 'Págs / hora'), el('th', {}, 'Ações'))),
    tbody);
  app.append(
    el('div', { class: 'section' }, autoBox,
      el('div', { class: 'row', style: 'margin:.2rem 0' }, statusBar, el('div', { class: 'spacer' }),
        el('button', { class: 'btn ghost', onclick: loadQueue }, '↻ atualizar')),
      el('div', { class: 'chart-wrap' }, table)));
  loadQueue(); schedulePoll();
}

async function boot() {
  if (!CONTEST) { app.innerHTML = '<div class="error-box">Contest não informado.</div>'; return; }
  const { st } = await initContestShell(CONTEST);
  if (!st || !st.logged_in) {
    app.innerHTML = '';
    app.append(el('div', { class: 'section' }, el('h2', {}, '🔒 Entre no contest'),
      el('a', { class: 'btn', href: '/contest/?c=' + enc(CONTEST) }, 'Ir para o contest')));
    return;
  }
  if (!st.is_staff && !st.is_admin) {
    app.innerHTML = '';
    app.append(el('div', { class: 'section' }, el('h2', {}, '🔒 Acesso restrito'),
      el('p', { class: 'muted' }, 'Esta área é da equipe de impressão (.staff).')));
    return;
  }
  autoMode = localStorage.getItem(AUTOKEY) === '1';
  render();
}
boot();
