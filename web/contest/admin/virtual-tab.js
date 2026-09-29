// Painel Evento › Virtual (módulo `virtual`) — a PARTICIPAÇÃO VIRTUAL deste contest: o portão
// aberto em partes (o público só vê 404; o dono vê O QUE falta), o link da página e a moderação
// das linhas gravadas. Rota: /contest/admin/virtual. A garantia de acesso é da API
// (lib/virtual.sh, portão por requisição) — isto é só a vitrine do dono.
import { el } from '/shared/ui.js';
import { apiGet, apiPost } from '/shared/api.js';
import { T } from '/shared/i18n.js';
import { swapIf, sigOf, fmtEpoch } from '/shared/admin-ui.js';

const enc = encodeURIComponent;

// fábrica preguiçosa: T() no topo congelaria o idioma antes do LOCALE do contest
const CHECKS = () => ({
  module_off: [T('Módulo ligado', 'Module on', 'Módulo activado'), T('ligue em Central › Módulos', 'turn it on in Home › Modules', 'actívalo en Central › Módulos')],
  secret: [T('Contest não é secreto', 'Contest is not secret', 'La competencia no es secreta'), T('contest secreto nunca vira virtual', 'a secret contest never becomes virtual', 'una competencia secreta nunca se vuelve virtual')],
  type: [T('Modo ICPC', 'ICPC mode', 'Modo ICPC'), T('por ora só placar ICPC', 'only the ICPC scoreboard for now', 'por ahora solo el marcador ICPC')],
  window: [T('Início e fim definidos', 'Start and end set', 'Inicio y fin definidos'), T('sem janela não há duração para refazer', 'without a window there is no duration to redo', 'sin ventana no hay duración para rehacer')],
  running: [T('Prova encerrada para todas as sedes', 'Contest over for every site', 'Competencia terminada para todas las sedes'), T('abre sozinho quando a última prorrogação acabar', 'opens by itself when the last extension ends', 'se abre solo cuando termina la última prórroga')],
  frozen: [T('Placar final descongelado', 'Final scoreboard unfrozen', 'Marcador final descongelado'), T('encerre o evento (Central) para publicar o resultado final', 'finish the event (Home) to publish the final result', 'termina el evento (Central) para publicar el resultado final')],
  problems_not_public: [T('Todos os problemas públicos no treino', 'All problems public in training', 'Todos los problemas públicos en el entrenamiento'), T('problema(s) ainda não público(s)', 'problem(s) not public yet', 'problema(s) todavía no público(s)')],
});

export function makeVirtualTab(CONTEST) {
  const G = { contest: CONTEST, auth: true };
  const panel = el('div');
  const head = el('div', { class: 'section' });
  const gate = el('div', { class: 'section' });
  const runs = el('div', { class: 'section' });
  panel.append(head, gate, runs);
  let built = false;

  async function act(action, login) {
    const msg = action === 'reset'
      ? T('Devolver a tentativa de ' + login + '? A linha gravada some do placar virtual e a conta pode largar de novo neste contest. As submissões continuam no histórico do treino.', 'Give ' + login + ' the attempt back? The recorded row leaves the virtual scoreboard and the account may start again in this contest. The submissions stay in the training history.', '¿Devolverle el intento a ' + login + '? La fila registrada sale del marcador virtual y la cuenta puede empezar de nuevo en esta competencia. Los envíos siguen en el historial de entrenamiento.')
      : action === 'remove'
      ? T('Tirar ' + login + ' do placar virtual? O registro fica guardado e pode ser devolvido.', 'Remove ' + login + ' from the virtual scoreboard? The record is kept and can be restored.', '¿Quitar a ' + login + ' del marcador virtual? El registro se guarda y puede devolverse.')
      : T('Devolver ' + login + ' ao placar virtual?', 'Restore ' + login + ' to the virtual scoreboard?', '¿Devolver a ' + login + ' al marcador virtual?');
    if (!confirm(msg)) return;
    try { await apiPost('/contest/admin/virtual?contest=' + enc(CONTEST), { action, login }, G); } catch (e) { alert(e.message); }
    load();
  }

  async function load() {
    let d;
    try { d = await apiGet('/contest/admin/virtual?contest=' + enc(CONTEST), G); } catch (e) {
      if (!built) { head.innerHTML = ''; head.append(el('p', { class: 'muted' }, e.message)); }
      return;
    }
    built = true;
    const C = CHECKS();
    swapIf(head, sigOf(d.eligible, d.enabled, d.url), () => el('div', {},
      el('h2', {}, T('🕹️ Participação virtual', '🕹️ Virtual participation', '🕹️ Participación virtual')),
      el('p', { class: 'muted' }, T(
        'Com a prova encerrada e o resultado final público, qualquer conta do treino pode refazer este contest uma vez, competindo contra o placar oficial no próprio tempo. As submissões são do treino; o placar oficial não muda. Ligar este módulo torna o placar final e a lista de problemas visíveis para contas do treino — por isso ele só abre quando todos os problemas já são públicos.',
        'With the contest over and the final result public, any training account can redo this contest once, competing against the official scoreboard in its own time. Submissions belong to training; the official scoreboard does not change. Turning this module on makes the final scoreboard and the problem list visible to training accounts — that is why it only opens when all problems are already public.',
        'Con la competencia terminada y el resultado final público, cualquier cuenta de entrenamiento puede rehacer esta competencia una vez, compitiendo contra el marcador oficial en su propio tiempo. Los envíos son del entrenamiento; el marcador oficial no cambia. Activar este módulo hace visibles el marcador final y la lista de problemas para las cuentas de entrenamiento — por eso solo se abre cuando todos los problemas ya son públicos.')),
      d.eligible
        ? el('p', {}, el('span', { class: 'pill ok' }, T('no ar', 'live', 'en vivo')), ' ',
            el('a', { href: d.url, target: '_blank', rel: 'noopener' }, T('abrir a página do virtual ↗', 'open the virtual page ↗', 'abrir la página del virtual ↗')))
        : el('p', {}, el('span', { class: 'pill warn' }, T('indisponível', 'unavailable', 'no disponible')), ' ',
            el('span', { class: 'muted' }, T('para o público esta prova responde como se o virtual não existisse', 'to the public this contest answers as if virtual did not exist', 'para el público esta competencia responde como si el virtual no existiera')))));
    swapIf(gate, sigOf(JSON.stringify(d.checks)), () => el('div', {},
      el('h3', {}, T('Condições', 'Conditions', 'Condiciones')),
      el('ul', { class: 'plain' }, ...(d.checks || []).map((c) => {
        const [name, hint] = C[c.id] || [c.id, ''];
        return el('li', {}, c.ok ? '✅ ' : '⛔ ', name,
          c.ok ? '' : el('span', { class: 'muted' }, ' — ' + hint + (c.detail ? ' (' + c.detail + ')' : '')));
      }))));
    swapIf(runs, sigOf(JSON.stringify(d.virtuals)), () => el('div', {},
      el('h3', {}, T('Participações gravadas', 'Recorded participations', 'Participaciones registradas') + ' (' + (d.virtuals || []).length + ')'),
      !(d.virtuals || []).length ? el('p', { class: 'muted' }, T('Ninguém terminou uma participação virtual ainda.', 'Nobody has finished a virtual participation yet.', 'Todavía nadie terminó una participación virtual.'))
        : el('table', { class: 'moj' },
          el('thead', {}, el('tr', {}, el('th', {}, 'login'), el('th', {}, T('nome', 'name', 'nombre')),
            el('th', { class: 'n' }, T('resolvidos', 'solved', 'resueltos')), el('th', { class: 'n' }, T('penalidade', 'penalty', 'penalidad')),
            el('th', {}, T('largada', 'started', 'salida')), el('th', {}, ''))),
          el('tbody', {}, ...d.virtuals.map((v) => el('tr', { class: v.removed ? 'muted' : '' },
            el('td', {}, v.login, v.official ? el('span', { class: 'pill', title: T('também competiu oficialmente', 'also competed officially', 'también compitió oficialmente') }, T('oficial', 'official', 'oficial')) : ''),
            el('td', {}, v.name || ''),
            el('td', { class: 'n' }, String(v.solved)), el('td', { class: 'n' }, String(v.penalty)),
            el('td', {}, fmtEpoch(v.start)),
            el('td', {}, v.removed
              ? el('button', { class: 'btn ghost small', onclick: () => act('restore', v.login) }, T('devolver', 'restore', 'restaurar'))
              : el('button', { class: 'btn ghost danger small', onclick: () => act('remove', v.login) }, T('tirar do placar', 'remove from board', 'quitar del marcador')),
              ' ', el('button', { class: 'btn ghost small', title: T('Apaga a linha e deixa a conta largar de novo (testador, ou quem teve problema)', 'Deletes the row and lets the account start again (tester, or someone who had a problem)', 'Elimina la fila y permite que la cuenta empiece de nuevo (probador, o alguien que tuvo un problema)'),
                onclick: () => act('reset', v.login) }, T('devolver tentativa', 'give attempt back', 'devolver intento')))))))));
  }
  return { panel, load };
}
