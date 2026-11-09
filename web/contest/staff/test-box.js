// contest/staff/test-box.js — "🧪 Teste de impressora": TAREFAS DE TESTE da impressão (/contest/staff/test-tasks;
// pedido do Fernando, 09/11/2026). Gera um lote de tarefas falsas na fila para medir a velocidade e o paralelismo
// das impressoras, mostra a MEDIDA (tarefas por minuto, por estação) e apaga o lote. Proibido durante a prova.
// Usado pela página do staff (a própria sede) e pelo painel Operação › Staff do admin (escolhe a sede).
// ATUALIZAÇÃO EM LUGAR: o esqueleto e os campos nascem uma vez; só o resumo e o estado de bloqueio trocam.
import { apiGet, apiPost } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { T } from '/shared/i18n.js';

const enc = encodeURIComponent;
const fmtSpan = (s) => {
  s = Math.max(0, Math.round(+s || 0));
  return s >= 60 ? Math.floor(s / 60) + ' min ' + String(s % 60).padStart(2, '0') + ' s' : s + ' s';
};
const fmtRate = (r) => (r == null ? '—' : String(r).replace('.', T(',', '.', ',')));

export function makeTestBox(CONTEST, { admin = false, onChange } = {}) {
  const G = { contest: CONTEST, auth: true };
  const fN = el('input', { type: 'number', min: '1', max: '200', value: '20', style: 'width:5rem' });
  const fKind = el('select', {},
    el('option', { value: 'print' }, T('🖨️ impressão', '🖨️ print', '🖨️ impresión')),
    el('option', { value: 'balloon' }, T('🎈 balão', '🎈 balloon', '🎈 globo')),
    el('option', { value: 'mixed' }, T('misto (alterna)', 'mixed (alternating)', 'mixto (alterna)')));
  const fPages = el('input', { type: 'number', min: '1', max: '20', value: '3', style: 'width:4rem' });
  const pagesLbl = el('label', { class: 'small' }, T('páginas por impressão ', 'pages per print ', 'páginas por impresión '), fPages);
  fKind.addEventListener('change', () => { pagesLbl.hidden = fKind.value === 'balloon'; });
  const fSite = admin ? el('select', {}, el('option', { value: '' }, T('todas as sedes', 'all sites', 'todas las sedes'))) : null;
  const bGo = el('button', { class: 'btn' }, T('🧪 Gerar', '🧪 Create', '🧪 Generar'));
  const bDel = el('button', { class: 'btn ghost' }, T('🧹 Apagar testes', '🧹 Delete tests', '🧹 Borrar pruebas'));
  const msg = el('div', { class: 'small', style: 'margin-top:.3rem' });
  const blockedNote = el('div', { class: 'alert', hidden: true },
    T('Proibido durante a prova: as tarefas de teste competiriam com as reais na fila. As que sobraram foram apagadas no início.',
      'Not allowed during the contest: test tasks would compete with the real ones in the queue. Leftovers were deleted at the start.',
      'Prohibido durante la competencia: las tareas de prueba competirían con las reales en la cola. Las que sobraron se borraron al inicio.'));
  const scopeNote = el('div', { class: 'small muted' });
  const sumBox = el('div', { style: 'margin-top:.5rem' });

  const det = el('details', { class: 'section' },
    el('summary', {}, el('b', {}, T('🧪 Teste de impressora', '🧪 Printer test', '🧪 Prueba de impresora'))),
    el('p', { class: 'small muted' }, T(
      'Gera tarefas de TESTE na fila da sede para medir as impressoras: deixe as estações em modo automático e gere o lote. As folhas saem com "TESTE — NÃO ENTREGAR" e numeração própria (T1, T2…). Não entram no relatório da prova.',
      'Creates TEST tasks in the site queue to measure the printers: leave the stations in automatic mode and create the batch. The sheets carry "TEST — DO NOT DELIVER" and their own numbering (T1, T2…). They are not in the contest report.',
      'Genera tareas de PRUEBA en la cola de la sede para medir las impresoras: deja las estaciones en modo automático y genera el lote. Las hojas salen con "PRUEBA — NO ENTREGAR" y numeración propia (T1, T2…). No entran en el informe de la competencia.')),
    blockedNote, scopeNote,
    el('div', { class: 'row', style: 'gap:.6rem;flex-wrap:wrap;align-items:center' },
      el('label', { class: 'small' }, T('quantidade ', 'how many ', 'cantidad '), fN),
      el('label', { class: 'small' }, T('tipo ', 'kind ', 'tipo '), fKind),
      pagesLbl,
      fSite ? el('label', { class: 'small' }, T('sede ', 'site ', 'sede '), fSite) : null,
      bGo, bDel),
    msg, sumBox);

  function setBusy(b) { bGo.disabled = b || bGo.dataset.blocked === '1'; bDel.disabled = b; }

  function renderSummary(s) {
    sumBox.innerHTML = '';
    if (!s || !s.total) { sumBox.append(el('div', { class: 'small muted' }, T('Nenhuma tarefa de teste na fila.', 'No test task in the queue.', 'Ninguna tarea de prueba en la cola.'))); return; }
    const done = (s.printed || 0) + (s.delivered || 0);
    const o = s.overall || null;
    sumBox.append(el('div', {},
      el('b', {}, s.total + T(' tarefa(s) de teste', ' test task(s)', ' tarea(s) de prueba')),
      ' · ' + done + T(' impressa(s)', ' printed', ' impresa(s)') + ' · ' + (s.pending || 0) + T(' pendente(s)', ' pending', ' pendiente(s)'),
      o ? ' · ' + fmtRate(o.per_min) + T(' tarefas/min em ', ' tasks/min in ', ' tareas/min en ') + fmtSpan(o.span_s) : '',
      s.max_gap_s != null ? ' · ' + T('maior intervalo ', 'longest gap ', 'mayor intervalo ') + fmtSpan(s.max_gap_s) : ''));
    if ((s.stations || []).length) {
      const tb = el('tbody');
      s.stations.forEach((x) => tb.append(el('tr', {}, el('td', {}, x.by), el('td', { class: 'n' }, String(x.done || 0)),
        el('td', { class: 'n' }, fmtRate(x.per_min)), el('td', { class: 'small muted' }, fmtSpan(x.span_s)))));
      sumBox.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj narrow' },
        el('thead', {}, el('tr', {}, el('th', {}, T('Estação (conta)', 'Station (account)', 'Estación (cuenta)')),
          el('th', { class: 'n' }, T('Impressas', 'Printed', 'Impresas')), el('th', { class: 'n' }, T('Tarefas/min', 'Tasks/min', 'Tareas/min')),
          el('th', {}, T('Tempo', 'Time', 'Tiempo')))), tb)));
    }
    sumBox.append(el('p', { class: 'small muted' }, T(
      'O tempo conta do 1º "pegar" à última impressão e inclui a geração do PDF no servidor: é o caminho real de uma tarefa na prova.',
      'The time runs from the first "claim" to the last print and includes the PDF generation on the server: it is the real path of a task in the contest.',
      'El tiempo va del primer "reservar" a la última impresión e incluye la generación del PDF en el servidor: es el camino real de una tarea en la competencia.')));
  }

  async function refresh() {
    if (!det.open) return;
    let r;
    try { r = await apiGet('/contest/staff/test-tasks?contest=' + enc(CONTEST), G); }
    catch (e) { msg.textContent = T('Falha: ', 'Failed: ', 'Error: ') + (e.message || ''); return; }
    blockedNote.hidden = !r.blocked;
    bGo.dataset.blocked = r.blocked ? '1' : '';
    bGo.disabled = !!r.blocked;
    if (fSite) {
      const want = ['', ...(r.sites || [])];
      const have = [...fSite.options].map((o) => o.value);
      if (want.join('\n') !== have.join('\n')) {
        const cur = fSite.value;
        fSite.replaceChildren(...want.map((v) => el('option', { value: v }, v || T('todas as sedes', 'all sites', 'todas las sedes'))));
        if (want.includes(cur)) fSite.value = cur;
      }
    } else {
      scopeNote.textContent = (r.scope || []).length
        ? T('As tarefas vão para a fila da sua sede: ', 'The tasks go to the queue of your site: ', 'Las tareas van a la cola de tu sede: ') + r.scope.join(', ')
        : T('Sem sede definida: as tarefas vão para a fila de todas as estações.', 'No site set: the tasks go to the queue of every station.', 'Sin sede definida: las tareas van a la cola de todas las estaciones.');
    }
    renderSummary(r.summary);
  }

  bGo.addEventListener('click', async () => {
    setBusy(true);
    try {
      const body = { action: 'create', count: +fN.value, kind: fKind.value, pages: +fPages.value };
      if (fSite) body.site = fSite.value;
      const r = await apiPost('/contest/staff/test-tasks?contest=' + enc(CONTEST), body, G);
      msg.textContent = T('Criadas ', 'Created ', 'Creadas ') + String(r.range || '').replace(' ', '–')
        + T('. Deixe as estações em modo automático.', '. Leave the stations in automatic mode.', '. Deja las estaciones en modo automático.');
      if (onChange) onChange();
    } catch (e) { msg.textContent = T('Falha: ', 'Failed: ', 'Error: ') + (e.message || ''); }
    finally { setBusy(false); refresh(); }
  });
  bDel.addEventListener('click', async () => {
    if (!confirm(T('Apagar as tarefas de teste da fila?', 'Delete the test tasks from the queue?', '¿Borrar las tareas de prueba de la cola?'))) return;
    setBusy(true);
    try {
      const r = await apiPost('/contest/staff/test-tasks?contest=' + enc(CONTEST), { action: 'delete' }, G);
      msg.textContent = (r.deleted || 0) + T(' tarefa(s) de teste apagada(s).', ' test task(s) deleted.', ' tarea(s) de prueba borrada(s).');
      if (onChange) onChange();
    } catch (e) { msg.textContent = T('Falha: ', 'Failed: ', 'Error: ') + (e.message || ''); }
    finally { setBusy(false); refresh(); }
  });
  det.addEventListener('toggle', () => { if (det.open) refresh(); });

  return { el: det, refresh };
}
