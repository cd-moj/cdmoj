// contest/staff/staff.js — área do .staff: fila de tarefas de impressão + modo automático.
// Fluxo: pegar (claim) → imprimir o PDF gerado (capa+doc) → marcar entregue.
// Modo automático: deixe a aba aberta; cada tarefa nova é reservada, impressa e marcada
// como "processada" assim que a impressão dispara (onafterprint / timeout).
// O .cstaff (chefe de sede) entra em modo SOMENTE LEITURA: acompanha a fila do escopo
// dele sem ações nem automático — a API corta print-action/print-pdf p/ ele (403).
import { apiGet, apiPost, getToken } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { initContestShell } from '/shared/contest-shell.js';
import { T, uiLocale } from '/shared/i18n.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const G = { contest: CONTEST, auth: true };
const enc = encodeURIComponent;
const fmtDate = (e) => new Date((+e || 0) * 1000).toLocaleString(uiLocale());
const AUTOKEY = 'moj_autoprint_' + CONTEST;

// fábrica: T() no topo do módulo congelaria o idioma antes do setLang(LOCALE) do contest
const STATUS = () => ({
  pending:   { t: T('🕓 pendente', '🕓 pending', '🕓 pendiente'),     c: '' },
  printed:   { t: T('🖨️ processada', '🖨️ processed', '🖨️ procesada'), c: 'color:#0a7' },
  delivered: { t: T('✅ entregue', '✅ delivered', '✅ entregada'),    c: 'color:#0a7; font-weight:600' },
});

let queue = [];            // último estado da fila
const MLINUX_LINK = el('span', {});   // vira o link 🖥 quando o nutellaboot está configurado
let autoMode = false;      // modo automático
let busy = false;          // processando uma tarefa (evita diálogos sobrepostos)
const seen = new Set();    // ids já auto-processados nesta sessão (não reimprimir)
let pollT = null;
let RO = false;            // .cstaff puro: fila somente leitura (sem ações/automático)
let CAN_BADGES = false;    // link de etiquetas: só .cstaff/admin
let BASIC = null;          // /contest/basic (freeze e política de balão no freeze)
// faixa do CONGELAMENTO: com o freeze em vigor, acerto a partir dele NÃO vira balão (o balão andando pela sala
// conta o que o placar congelado esconde — print.sh). Sem aviso, a fila silenciosa na última hora parecia defeito
// (TCP 2026, 03/10/2026). SEM número de retidos: a contagem diria ao staff quantos times acertaram no freeze —
// ela fica com o admin (Situação). Atualizada EM LUGAR a cada volta da fila.
const freezeNote = el('div', { class: 'notice', style: 'display:none;margin:.3rem 0' });
function syncFreezeNote() {
  const b = BASIC || {};
  const fz = +b.freeze_time || 0;
  const on = fz > 0 && !b.balloons_during_freeze && (b.modules || []).includes('baloes');
  const now = Math.floor(Date.now() / 1000);
  const hh = on ? new Date(fz * 1000).toLocaleTimeString(uiLocale(), { hour: '2-digit', minute: '2-digit' }) : '';
  const txt = !on ? '' : now >= fz
    ? T('🧊 Placar congelado desde ' + hh + ': acertos a partir desse horário NÃO viram balão — o balão revelaria o placar congelado. É o padrão da prova; só o admin muda (Regras › balões durante o congelamento).',
        '🧊 Scoreboard frozen since ' + hh + ': accepted runs from that time on do NOT become balloons — a balloon would reveal the frozen scoreboard. This is the contest default; only the admin can change it (Rules › balloons during the freeze).',
        '🧊 Marcador congelado desde las ' + hh + ': los aciertos a partir de esa hora NO generan globo — el globo revelaría el marcador congelado. Es el valor por defecto de la competencia; solo el admin lo cambia (Reglas › globos durante el congelamiento).')
    : T('🧊 Às ' + hh + ' o placar congela: a partir daí, acertos NÃO viram balão (o balão revelaria o placar congelado).',
        '🧊 At ' + hh + ' the scoreboard freezes: from then on, accepted runs do NOT become balloons (a balloon would reveal the frozen scoreboard).',
        '🧊 A las ' + hh + ' el marcador se congela: desde entonces, los aciertos NO generan globo (el globo revelaría el marcador congelado).');
  if (freezeNote.textContent !== txt) freezeNote.textContent = txt;
  freezeNote.style.display = txt ? '' : 'none';
}

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
  if (!w) { alert(T('Permita pop-ups para abrir/imprimir o PDF desta sede.', 'Allow pop-ups to open/print this site\'s PDF.', 'Permite las ventanas emergentes para abrir/imprimir el PDF de esta sede.')); return null; }
  try { w.document.write(T('<!doctype html><meta charset="utf-8"><title>Impressão</title><body style="margin:0;font:16px sans-serif;padding:1.2rem">Gerando o PDF…</body>', '<!doctype html><meta charset="utf-8"><title>Printing</title><body style="margin:0;font:16px sans-serif;padding:1.2rem">Generating the PDF…</body>', '<!doctype html><meta charset="utf-8"><title>Impresión</title><body style="margin:0;font:16px sans-serif;padding:1.2rem">Generando el PDF…</body>')); } catch (_) {}
  pdfBlobUrl(id).then((url) => {
    w.location.href = url;
    if (doPrint) { const tryPrint = () => { try { w.focus(); w.print(); } catch (_) {} }; setTimeout(tryPrint, 1500); }
    setTimeout(() => URL.revokeObjectURL(url), 120000);
  }).catch((e) => { try { w.document.body.innerHTML = T('Falha ao gerar o PDF: ', 'Failed to generate the PDF: ', 'Error al generar el PDF: ') + (e.message || T('erro', 'error', 'error')); } catch (_) {} });
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
    b.addEventListener('click', async () => { b.disabled = true; try { await fn(); } catch (e) { alert(e.message || T('falha', 'failed', 'fallido')); } finally { b.disabled = false; await loadQueue(); } }); return b; };
  if (t.status === 'pending') r.append(mkBtn(T('Pegar', 'Claim', 'Reservar'), () => action(t.id, 'claim')));
  if (t.status !== 'delivered') r.append(mkBtn(T('🖨️ Imprimir', '🖨️ Print', '🖨️ Imprimir'), () => printTaskManual(t), ''));
  r.append(mkBtn(T('Abrir PDF', 'Open PDF', 'Abrir PDF'), () => { openPdfWindow(t.id, false); }));
  if (t.status === 'printed') r.append(mkBtn(T('✅ Entregue', '✅ Delivered', '✅ Entregado'), () => action(t.id, 'delivered'), ''));
  return r;
}

function renderRows() {
  tbody.innerHTML = '';
  if (!queue.length) { tbody.append(el('tr', {}, el('td', { colspan: '6', class: 'muted' }, T('Nenhuma tarefa.', 'No tasks.', 'Sin tareas.')))); return; }
  queue.forEach((t) => {
    const S = STATUS(), st = S[t.status] || S.pending;
    const taskCell = t.kind === 'balloon'
      ? el('td', {}, el('b', {}, T('🎈 Balão · ', '🎈 Balloon · ', '🎈 Globo · ') + (t.short || '?')),
          el('div', { class: 'small' },
            el('span', { style: 'display:inline-block;width:.8em;height:.8em;border:1px solid #999;border-radius:50%;vertical-align:middle;background:#' + (t.color_hex || 'cccccc') }),
            ' ' + (t.color_name || '')),
          // PRIMEIRO DA SEDE: o servidor só manda `true` depois de ter CERTEZA (nenhuma run mais
          // antiga da sede, no mesmo problema, por julgar) — ver pr_reconcile_balloons. A folha
          // impressa leva a mesma faixa, então o que o staff anuncia bate com o que ele carrega.
          t.first_site
            ? el('div', { class: 'small', style: 'color:#7A5C00;font-weight:700;margin-top:.15rem' },
                '★ ' + T('primeiro da sede', 'first to solve at this site', 'primero en resolver en esta sede'))
            : null)
      : el('td', {}, t.filename, el('div', { class: 'small muted' }, (t.mime || '') + (t.size ? ' · ' + Math.max(1, Math.round(t.size / 1024)) + ' KB' : '')));
    tbody.append(el('tr', {},
      el('td', {}, el('b', {}, '#' + t.seq)),
      el('td', {}, el('div', {}, t.team || t.fullname || t.login), el('div', { class: 'small muted' }, t.login + (t.univ ? ' · ' + t.univ : ''))),
      taskCell,
      el('td', {}, el('span', { class: 'pr-badge', style: st.c }, st.t),
        (t.claimed_by ? el('div', { class: 'small muted' }, T('por ', 'by ', 'por ') + t.claimed_by) : '')),
      // ⚠ build_ok===false: a conversão do documento falhou e o PDF é SÓ a folha de rosto.
      // Antes disso a coluna mostrava um '—' mudo e a sala só descobria no papel impresso.
      el('td', { class: 'small' },
        (t.build_ok === false
          ? el('span', { style: 'color:var(--warn,#b45309); font-weight:600' },
              T('⚠ não converteu', '⚠ not converted', '⚠ no convertido'))
          : (t.pages > 0 ? t.pages + T(' pág.', ' pg', ' pág.') : '—')),
        el('div', { class: 'small muted' },
          t.build_ok === false ? T('baixe o arquivo cru', 'download the raw file', 'descargar el archivo original') : fmtDate(t.time))),
      el('td', {}, rowActions(t))));
  });
}

async function loadQueue() {
  let r;
  try { r = await apiGet('/contest/staff/queue?contest=' + enc(CONTEST), G); }
  catch (e) { statusBar.textContent = T('Falha ao listar: ', 'Failed to list: ', 'No se pudo listar: ') + (e.message || T('erro', 'error', 'error')); return; }
  queue = r.requests || [];
  const np = queue.filter((x) => x.status === 'pending').length;
  statusBar.textContent = queue.length + T(' tarefa(s) · ', ' task(s) · ', ' tarea(s) · ') + np + T(' pendente(s)', ' pending', ' pendiente(s)') +
    (RO ? T(' · somente leitura', ' · read-only', ' · solo lectura') : (autoMode ? T(' · modo automático LIGADO', ' · auto mode ON', ' · modo automático ACTIVADO') : ''));
  renderRows();
  syncFreezeNote();
  autoTick();   // dispara o automático se houver pendente
}

// Ritmo do poll (2026-08-25, diagnóstico de carga): a fila do staff era 40% de TODO o tempo de
// servidor da manhã, vinda de meia dúzia de abas polando a cada 5–8 s — e no sábado são 550.
// Regras: modo AUTOMÁTICO (a estação que imprime) mantém o ritmo rápido, porque ali latência é
// papel na mão; quem só OLHA pola a cada 15–20 s (com jitter, para as 550 abas não baterem
// juntas); e ABA ESCONDIDA não pola — volta com refresh imediato no visibilitychange.
function schedulePoll() {
  if (pollT) clearTimeout(pollT);
  const iv = autoMode ? 8000 + Math.random() * 4000 : 15000 + Math.random() * 5000;
  pollT = setTimeout(async () => {
    if (!document.hidden) await loadQueue();
    schedulePoll();
  }, iv);
}
document.addEventListener('visibilitychange', () => {
  // só depois que a página armou o poll (pollT) — antes do boot não há sessão nem tabela
  if (!document.hidden && !busy && pollT) loadQueue().catch(() => {});
});

function render() {
  app.innerHTML = '';
  const autoBox = el('label', { class: 'pr-auto' + (autoMode ? ' on' : '') });
  const cb = el('input', { type: 'checkbox' }); cb.checked = autoMode;
  cb.addEventListener('change', () => {
    autoMode = cb.checked; localStorage.setItem(AUTOKEY, autoMode ? '1' : '0');
    autoBox.className = 'pr-auto' + (autoMode ? ' on' : ''); loadQueue();
  });
  autoBox.append(cb, el('span', {}, el('b', {}, T(' Modo impressão automática', ' Automatic printing mode', ' Modo de impresión automática')),
    el('span', { class: 'small muted' }, T(' — imprime cada tarefa nova e marca como processada. Para impressão sem o diálogo do sistema, use o navegador em modo kiosk (--kiosk-printing).', ' — prints each new task and marks it processed. To print without the system dialog, run the browser in kiosk mode (--kiosk-printing).', ' — imprime cada tarea nueva y la marca como procesada. Para imprimir sin el diálogo del sistema, ejecuta el navegador en modo kiosco (--kiosk-printing).'))));
  const table = el('table', { class: 'moj' },
    el('thead', {}, el('tr', {}, el('th', {}, '#'), el('th', {}, T('Time / login', 'Team / login', 'Equipo / login')), el('th', {}, T('Arquivo', 'File', 'Archivo')), el('th', {}, T('Status', 'Status', 'Estado')), el('th', {}, T('Págs / hora', 'Pages / time', 'Páginas / hora')), el('th', {}, T('Ações', 'Actions', 'Acciones')))),
    tbody);
  app.append(
    el('div', { class: 'section' }, RO ? '' : autoBox, freezeNote,
      el('div', { class: 'row', style: 'margin:.2rem 0' }, statusBar, el('div', { class: 'spacer' }),
        CAN_BADGES ? el('a', { class: 'btn ghost', href: '/contest/badges/?c=' + enc(CONTEST) }, T('🏷️ Etiquetas', '🏷️ Badges', '🏷️ Etiquetas')) : '',
        MLINUX_LINK, // preenchido quando a integração nutellaboot está configurada
        el('button', { class: 'btn ghost', onclick: loadQueue }, T('↻ atualizar', '↻ refresh', '↻ actualizar'))),
      el('div', { class: 'chart-wrap' }, table)));
  loadQueue(); schedulePoll();
}

async function boot() {
  if (!CONTEST) { app.innerHTML = '<div class="error-box">' + T('Contest não informado.', 'Contest not specified.', 'Competencia no especificada.') + '</div>'; return; }
  const { st, basic } = await initContestShell(CONTEST);
  BASIC = basic || null;
  if (!st || !st.logged_in) {
    app.innerHTML = '';
    app.append(el('div', { class: 'section' }, el('h2', {}, T('🔒 Entre no contest', '🔒 Log in to the contest', '🔒 Inicia sesión en la competencia')),
      el('a', { class: 'btn', href: '/contest/?c=' + enc(CONTEST) }, T('Ir para o contest', 'Go to the contest', 'Ir a la competencia'))));
    return;
  }
  if (!st.is_staff && !st.is_cstaff && !st.is_admin) {
    app.innerHTML = '';
    app.append(el('div', { class: 'section' }, el('h2', {}, T('🔒 Acesso restrito', '🔒 Restricted access', '🔒 Acceso restringido')),
      el('p', { class: 'muted' }, T('Esta área é da equipe de impressão (.staff/.cstaff).', 'This area is for the printing team (.staff/.cstaff).', 'Esta área es del equipo de impresión (.staff/.cstaff).'))));
    return;
  }
  RO = !!st.is_cstaff && !st.is_staff && !st.is_admin;
  CAN_BADGES = !!(st.is_cstaff || st.is_admin);
  autoMode = !RO && localStorage.getItem(AUTOKEY) === '1';
  render();
  // link p/ o panorama/comandos das máquinas mlinux — só quando a integração existe
  // (sonda barata; a página avulsa se linka daqui, doutrina do animeitor)
  apiGet('/contest/nutella?contest=' + enc(CONTEST), G).then((r) => {
    if (r && r.configured) {
      MLINUX_LINK.append(el('a', { class: 'btn ghost', href: '/contest/mlinux/?c=' + enc(CONTEST) },
        T('🖥 Máquinas', '🖥 Machines', '🖥 Máquinas')));
    }
  }).catch(() => { /* sem integração/permissão: sem link */ });
}
boot();
