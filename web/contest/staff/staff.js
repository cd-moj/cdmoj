// contest/staff/staff.js — área do .staff: fila de tarefas de impressão + modo automático.
// Fluxo: pegar (claim) → imprimir o PDF gerado (capa+doc) → marcar entregue.
// Modo automático: deixe a aba aberta; cada tarefa nova é reservada, impressa e marcada
// como "processada" assim que a impressão dispara (onafterprint / timeout).
// O .cstaff (chefe de sede) entra em modo SOMENTE LEITURA: acompanha a fila do escopo
// dele sem ações nem automático — a API corta print-action/print-pdf p/ ele (403).
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
let RO = false;            // .cstaff puro: fila somente leitura (sem ações/automático)
let CAN_BADGES = false;    // link de etiquetas: só .cstaff/admin

// busca o PDF combinado (com Bearer) como blob -> URL temporária (sem token na URL)
async function pdfBlobUrl(id) {
  const r = await fetch('/api/v1/contest/staff/print-pdf?contest=' + enc(CONTEST) + '&id=' + enc(id),
    { headers: { 'Authorization': 'Bearer ' + (getToken(CONTEST) || '') } });
  if (!r.ok) throw new Error('HTTP ' + r.status);
  return URL.createObjectURL(await r.blob());
}

// AUTO: imprime um blob num iframe renderizado fora da tela (sem pop-up — o auto não tem
// gesto do usuário). Em modo kiosk (--kiosk-printing) imprime sem diálogo. NÃO usa
// visibility:hidden (o Firefox não imprime iframe escondido). Resolve no onafterprint/timeout.
function printBlobIframe(url) {
  return new Promise((res) => {
    const ifr = el('iframe', { style: 'position:fixed;left:-10000px;top:0;width:800px;height:1100px;border:0' });
    let done = false;
    const fin = () => { if (done) return; done = true; setTimeout(() => ifr.remove(), 2000); res(); };
    ifr.onload = () => { setTimeout(() => { try { const w = ifr.contentWindow; w.focus(); w.onafterprint = fin; w.print(); setTimeout(fin, 8000); } catch (_) { fin(); } }, 600); };
    ifr.src = url; document.body.append(ifr);
  });
}

// MANUAL: abre o PDF numa nova aba e dispara o diálogo de impressão. A janela é aberta
// SINCRONAMENTE dentro do clique (preserva o gesto -> não é bloqueada como pop-up); o blob
// é carregado nela quando o fetch (com Bearer) termina. Em mobile (sem print()), o visor de
// PDF abre e o usuário imprime/compartilha pelo menu. `doPrint` dispara window.print().
function openPdfWindow(id, doPrint) {
  const w = window.open('', '_blank');
  if (!w) { alert('Permita pop-ups para abrir/imprimir o PDF desta sede.'); return null; }
  try { w.document.write('<!doctype html><meta charset="utf-8"><title>Impressão</title><body style="margin:0;font:16px sans-serif;padding:1.2rem">Gerando o PDF…</body>'); } catch (_) {}
  pdfBlobUrl(id).then((url) => {
    w.location.href = url;
    if (doPrint) { const tryPrint = () => { try { w.focus(); w.print(); } catch (_) {} }; setTimeout(tryPrint, 1500); }
    setTimeout(() => URL.revokeObjectURL(url), 120000);
  }).catch((e) => { try { w.document.body.innerHTML = 'Falha ao gerar o PDF: ' + (e.message || 'erro'); } catch (_) {} });
  return w;
}

async function action(id, act, extra) {
  return apiPost('/contest/staff/print-action?contest=' + enc(CONTEST), Object.assign({ id, action: act }, extra || {}), G);
}

// MANUAL (gesto do clique): abre+imprime numa nova aba e marca processada.
function printTaskManual(t) {
  const w = openPdfWindow(t.id, true);       // síncrono no gesto -> sem bloqueio de pop-up
  if (!w) return Promise.resolve();          // pop-up bloqueado: não marca (use "Abrir PDF")
  return action(t.id, 'processed', { mode: 'manual' });
}

// passo do modo automático: uma tarefa pendente por vez (reserva antes de imprimir via iframe)
async function autoTick() {
  if (RO || !autoMode || busy) return;
  const t = queue.find((x) => x.status === 'pending' && !seen.has(x.id));
  if (!t) return;
  busy = true; seen.add(t.id);
  try {
    await action(t.id, 'claim');              // reserva (409 already_claimed => outra aba pegou)
    const url = await pdfBlobUrl(t.id);
    try { await printBlobIframe(url); } finally { setTimeout(() => URL.revokeObjectURL(url), 10000); }
    await action(t.id, 'processed', { mode: 'auto' });
  } catch (e) {
    if (!(e && e.code === 'already_claimed')) seen.delete(t.id);  // erro real: permite retry
  } finally {
    busy = false; await loadQueue();
  }
}

const statusBar = el('div', { class: 'small muted' });
const tbody = el('tbody', {});

function rowActions(t) {
  if (RO) return el('span', { class: 'small muted' }, '—');   // .cstaff só acompanha
  const r = el('div', { class: 'row' });
  const mkBtn = (label, fn, cls) => { const b = el('button', { class: 'btn ' + (cls || 'ghost'), style: 'padding:.2rem .5rem' }, label);
    b.addEventListener('click', async () => { b.disabled = true; try { await fn(); } catch (e) { alert(e.message || 'falha'); } finally { b.disabled = false; await loadQueue(); } }); return b; };
  if (t.status === 'pending') r.append(mkBtn('Pegar', () => action(t.id, 'claim')));
  if (t.status !== 'delivered') r.append(mkBtn('🖨️ Imprimir', () => printTaskManual(t), ''));
  r.append(mkBtn('Abrir PDF', () => { openPdfWindow(t.id, false); }));
  if (t.status === 'printed') r.append(mkBtn('✅ Entregue', () => action(t.id, 'delivered'), ''));
  return r;
}

function renderRows() {
  tbody.innerHTML = '';
  if (!queue.length) { tbody.append(el('tr', {}, el('td', { colspan: '6', class: 'muted' }, 'Nenhuma tarefa.'))); return; }
  queue.forEach((t) => {
    const st = STATUS[t.status] || STATUS.pending;
    const taskCell = t.kind === 'balloon'
      ? el('td', {}, el('b', {}, '🎈 Balão · ' + (t.short || '?')),
          el('div', { class: 'small' },
            el('span', { style: 'display:inline-block;width:.8em;height:.8em;border:1px solid #999;border-radius:50%;vertical-align:middle;background:#' + (t.color_hex || 'cccccc') }),
            ' ' + (t.color_name || '')))
      : el('td', {}, t.filename, el('div', { class: 'small muted' }, (t.mime || '') + (t.size ? ' · ' + Math.max(1, Math.round(t.size / 1024)) + ' KB' : '')));
    tbody.append(el('tr', {},
      el('td', {}, el('b', {}, '#' + t.seq)),
      el('td', {}, el('div', {}, t.team || t.fullname || t.login), el('div', { class: 'small muted' }, t.login + (t.univ ? ' · ' + t.univ : ''))),
      taskCell,
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
  statusBar.textContent = queue.length + ' tarefa(s) · ' + np + ' pendente(s)' +
    (RO ? ' · somente leitura' : (autoMode ? ' · modo automático LIGADO' : ''));
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
    el('div', { class: 'section' }, RO ? '' : autoBox,
      el('div', { class: 'row', style: 'margin:.2rem 0' }, statusBar, el('div', { class: 'spacer' }),
        CAN_BADGES ? el('a', { class: 'btn ghost', href: '/contest/badges/?c=' + enc(CONTEST) }, '🏷️ Etiquetas') : '',
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
  if (!st.is_staff && !st.is_cstaff && !st.is_admin) {
    app.innerHTML = '';
    app.append(el('div', { class: 'section' }, el('h2', {}, '🔒 Acesso restrito'),
      el('p', { class: 'muted' }, 'Esta área é da equipe de impressão (.staff/.cstaff).')));
    return;
  }
  RO = !!st.is_cstaff && !st.is_staff && !st.is_admin;
  CAN_BADGES = !!(st.is_cstaff || st.is_admin);
  autoMode = !RO && localStorage.getItem(AUTOKEY) === '1';
  render();
}
boot();
