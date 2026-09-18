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
  module_off: [T('Módulo ligado', 'Module on'), T('ligue em Central › Módulos', 'turn it on in Home › Modules')],
  secret: [T('Contest não é secreto', 'Contest is not secret'), T('contest secreto nunca vira virtual', 'a secret contest never becomes virtual')],
  type: [T('Modo ICPC', 'ICPC mode'), T('por ora só placar ICPC', 'only the ICPC scoreboard for now')],
  window: [T('Início e fim definidos', 'Start and end set'), T('sem janela não há duração para refazer', 'without a window there is no duration to redo')],
  running: [T('Prova encerrada para todas as sedes', 'Contest over for every site'), T('abre sozinho quando a última prorrogação acabar', 'opens by itself when the last extension ends')],
  frozen: [T('Placar final descongelado', 'Final scoreboard unfrozen'), T('encerre o evento (Central) para publicar o resultado final', 'finish the event (Home) to publish the final result')],
  problems_not_public: [T('Todos os problemas públicos no treino', 'All problems public in training'), T('problema(s) ainda não público(s)', 'problem(s) not public yet')],
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
      ? T('Devolver a tentativa de ' + login + '? A linha gravada some do placar virtual e a conta pode largar de novo neste contest. As submissões continuam no histórico do treino.', 'Give ' + login + ' the attempt back? The recorded row leaves the virtual scoreboard and the account may start again in this contest. The submissions stay in the training history.')
      : action === 'remove'
      ? T('Tirar ' + login + ' do placar virtual? O registro fica guardado e pode ser devolvido.', 'Remove ' + login + ' from the virtual scoreboard? The record is kept and can be restored.')
      : T('Devolver ' + login + ' ao placar virtual?', 'Restore ' + login + ' to the virtual scoreboard?');
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
      el('h2', {}, T('🕹️ Participação virtual', '🕹️ Virtual participation')),
      el('p', { class: 'muted' }, T(
        'Com a prova encerrada e o resultado final público, qualquer conta do treino pode refazer este contest uma vez, competindo contra o placar oficial no próprio tempo. As submissões são do treino; o placar oficial não muda. Ligar este módulo torna o placar final e a lista de problemas visíveis para contas do treino — por isso ele só abre quando todos os problemas já são públicos.',
        'With the contest over and the final result public, any training account can redo this contest once, competing against the official scoreboard in its own time. Submissions belong to training; the official scoreboard does not change. Turning this module on makes the final scoreboard and the problem list visible to training accounts — that is why it only opens when all problems are already public.')),
      d.eligible
        ? el('p', {}, el('span', { class: 'pill ok' }, T('no ar', 'live')), ' ',
            el('a', { href: d.url, target: '_blank', rel: 'noopener' }, T('abrir a página do virtual ↗', 'open the virtual page ↗')))
        : el('p', {}, el('span', { class: 'pill warn' }, T('indisponível', 'unavailable')), ' ',
            el('span', { class: 'muted' }, T('para o público esta prova responde como se o virtual não existisse', 'to the public this contest answers as if virtual did not exist')))));
    swapIf(gate, sigOf(JSON.stringify(d.checks)), () => el('div', {},
      el('h3', {}, T('Condições', 'Conditions')),
      el('ul', { class: 'plain' }, ...(d.checks || []).map((c) => {
        const [name, hint] = C[c.id] || [c.id, ''];
        return el('li', {}, c.ok ? '✅ ' : '⛔ ', name,
          c.ok ? '' : el('span', { class: 'muted' }, ' — ' + hint + (c.detail ? ' (' + c.detail + ')' : '')));
      }))));
    swapIf(runs, sigOf(JSON.stringify(d.virtuals)), () => el('div', {},
      el('h3', {}, T('Participações gravadas', 'Recorded participations') + ' (' + (d.virtuals || []).length + ')'),
      !(d.virtuals || []).length ? el('p', { class: 'muted' }, T('Ninguém terminou uma participação virtual ainda.', 'Nobody has finished a virtual participation yet.'))
        : el('table', { class: 'moj' },
          el('thead', {}, el('tr', {}, el('th', {}, 'login'), el('th', {}, T('nome', 'name')),
            el('th', { class: 'n' }, T('resolvidos', 'solved')), el('th', { class: 'n' }, T('penalidade', 'penalty')),
            el('th', {}, T('largada', 'started')), el('th', {}, ''))),
          el('tbody', {}, ...d.virtuals.map((v) => el('tr', { class: v.removed ? 'muted' : '' },
            el('td', {}, v.login, v.official ? el('span', { class: 'pill', title: T('também competiu oficialmente', 'also competed officially') }, T('oficial', 'official')) : ''),
            el('td', {}, v.name || ''),
            el('td', { class: 'n' }, String(v.solved)), el('td', { class: 'n' }, String(v.penalty)),
            el('td', {}, fmtEpoch(v.start)),
            el('td', {}, v.removed
              ? el('button', { class: 'btn ghost small', onclick: () => act('restore', v.login) }, T('devolver', 'restore'))
              : el('button', { class: 'btn ghost danger small', onclick: () => act('remove', v.login) }, T('tirar do placar', 'remove from board')),
              ' ', el('button', { class: 'btn ghost small', title: T('Apaga a linha e deixa a conta largar de novo (testador, ou quem teve problema)', 'Deletes the row and lets the account start again (tester, or someone who had a problem)'),
                onclick: () => act('reset', v.login) }, T('devolver tentativa', 'give attempt back')))))))));
  }
  return { panel, load };
}
