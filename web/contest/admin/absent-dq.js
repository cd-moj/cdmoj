// contest/admin/absent-dq.js — cartão "🚫 Desclassificar quem não logou" de Pessoas › Contas (12/11/2026).
// GET/POST /contest/admin/absent-disqualify (regras em server/api/v1/lib/absent-dq.sh): a prévia não grava nada;
// desclassificar exige o plan_id dela (a lista mudou = 409 plan_changed e o cartão busca a prévia nova); cada lote
// pode ser desfeito (volta só quem ainda tem a marca dele). Sem confirm()/alert(): a confirmação é o próprio botão
// da prévia, que diz quantos times saem.
import { el, fmtDate } from '/shared/ui.js';
import { apiGet, apiPost } from '/shared/api.js';
import { T } from '/shared/i18n.js';

const enc = encodeURIComponent;
const SHOW = 40;   // linhas da prévia antes do "ver todos"

export function makeAbsentDqCard(CONTEST, { onDone } = {}) {
  const G = { contest: CONTEST, auth: true };
  const path = '/contest/admin/absent-disqualify?contest=' + enc(CONTEST);
  const card = el('div', { class: 'section', 'data-card': 'absent-dq', style: 'margin:.4rem 0 .8rem; padding:.7rem .9rem; border:1px solid var(--line, #dde3ea); border-radius:10px' });
  const body = el('div', {});
  const msg = el('div', { class: 'small' });
  const prevBtn = el('button', { class: 'btn ghost', onclick: () => preview() }, T('Ver prévia', 'Preview', 'Ver vista previa'));
  card.append(
    el('b', {}, T('🚫 Desclassificar quem não logou', '🚫 Disqualify who did not log in', '🚫 Descalificar a quien no inició sesión')),
    el('p', { class: 'small muted', style: 'margin:.3rem 0' },
      T('Tira do placar e da estatística, de uma vez, os times sem nenhum login na prova e sem nenhuma submissão. Fica quem está numa classificação publicada. A prévia não grava nada, e o lote pode ser desfeito.',
        'Removes from the scoreboard and the statistics, in one go, the teams with no login during the contest and no submission. Teams in a published classification stay. The preview changes nothing, and the batch can be undone.',
        'Quita del marcador y de la estadística, de una vez, a los equipos sin ningún inicio de sesión en la competencia y sin ningún envío. Se quedan los que están en una clasificación publicada. La vista previa no guarda nada, y el lote se puede deshacer.')),
    el('div', { class: 'row' }, prevBtn), msg, body);

  const when = (e) => (e ? fmtDate(e) : T('nunca', 'never', 'nunca'));
  const fail = (e) => { msg.className = 'small error-box'; msg.textContent = (e && e.message) || T('falha', 'failed', 'fallido'); };

  function batchesEl(batches) {
    if (!batches || !batches.length) return '';
    const rows = batches.slice(0, 10).map((b) => {
      const act = b.undone_at ? el('span', { class: 'muted' }, T('desfeito em ', 'undone on ', 'deshecho el ') + fmtDate(b.undone_at) + ' (' + (b.undone_by || '') + ')')
        : el('button', { class: 'btn ghost', 'data-batch': b.id, onclick: () => undo(b.id) }, T('Desfazer', 'Undo', 'Deshacer'));
      return el('tr', {}, el('td', {}, fmtDate(b.at)), el('td', {}, b.by || ''), el('td', { class: 'n' }, String(b.count)), el('td', {}, act));
    });
    return el('div', { style: 'margin-top:.8rem' },
      el('div', { class: 'small', style: 'font-weight:600' }, T('Lotes anteriores', 'Previous batches', 'Lotes anteriores')),
      el('table', { class: 'moj narrow' }, el('thead', {}, el('tr', {}, el('th', {}, T('quando', 'when', 'cuándo')), el('th', {}, T('por', 'by', 'por')),
        el('th', { class: 'n' }, T('times', 'teams', 'equipos')), el('th', {}, ''))), el('tbody', {}, ...rows)));
  }

  function render(d) {
    const p = d.preview || {}, c = p.counts || {}, cand = p.candidates || [];
    body.innerHTML = '';
    body.append(el('p', { class: 'small', style: 'margin:.5rem 0 .2rem' },
      T('Janela de login considerada: ', 'Login window considered: ', 'Ventana de inicio de sesión considerada: '),
      el('b', {}, fmtDate(p.window.from) + ' → ' + fmtDate(p.window.to)), ' · ',
      c.teams + T(' times', ' teams', ' equipos') + ' · ' + c.logged + T(' logaram', ' logged in', ' iniciaron sesión') + ' · ' +
      c.with_subs + T(' com submissão', ' with submissions', ' con envíos') + ' · ' + c.already_dq + T(' já desclassificados', ' already disqualified', ' ya descalificados')));
    if (p.live) body.append(el('div', { class: 'notice small', style: 'margin:.3rem 0' },
      T('⚠ A prova ainda está rodando: a janela vai até agora. Quem logar depois já estará desclassificado — devolva pelo "Desfazer" ou na lista de contas.',
        '⚠ The contest is still running: the window goes up to now. Whoever logs in later will already be disqualified — bring them back with "Undo" or in the account list.',
        '⚠ La competencia todavía está en curso: la ventana llega hasta ahora. Quien inicie sesión después ya estará descalificado — devuélvelo con "Deshacer" o en la lista de cuentas.')));
    if ((p.kept_classified || []).length) body.append(el('p', { class: 'small muted', style: 'margin:.2rem 0' },
      T('Ficam por estarem classificados: ', 'Kept because they are classified: ', 'Se quedan por estar clasificados: '),
      p.kept_classified.map((k) => k.login + (k.via ? ' (' + k.via + ')' : '')).join(', ')));
    if (!cand.length) {
      body.append(el('p', { class: 'small', style: 'margin:.3rem 0' }, T('Ninguém a desclassificar.', 'Nobody to disqualify.', 'Nadie para descalificar.')));
    } else {
      const tb = el('tbody', {});
      let all = false;
      const paint = () => tb.replaceChildren(...(all ? cand : cand.slice(0, SHOW)).map((u) => el('tr', {},
        el('td', {}, u.login), el('td', {}, u.name || ''), el('td', {}, u.region || ''), el('td', {}, when(u.last_login)))));
      paint();
      const more = cand.length > SHOW ? el('button', { class: 'btn ghost', onclick: () => { all = true; paint(); more.remove(); } },
        T('ver todos (', 'show all (', 'ver todos (') + cand.length + ')') : '';
      const go = el('button', { class: 'btn danger', onclick: () => apply(p.plan_id, go) },
        T('Desclassificar ', 'Disqualify ', 'Descalificar ') + cand.length + T(' times', ' teams', ' equipos'));
      body.append(
        el('div', { style: 'max-height:360px; overflow:auto; margin:.3rem 0' },
          el('table', { class: 'moj narrow' }, el('thead', {}, el('tr', {}, el('th', {}, 'login'), el('th', {}, T('nome', 'name', 'nombre')),
            el('th', {}, T('sede', 'site', 'sede')), el('th', {}, T('último login', 'last login', 'último inicio de sesión')))), tb)),
        more, el('div', { class: 'row', style: 'margin:.4rem 0' }, go));
    }
    body.append(batchesEl(d.batches));
  }

  async function preview(note) {
    prevBtn.disabled = true; msg.className = 'small'; msg.textContent = note || T('Levantando…', 'Checking…', 'Revisando…');
    try { render(await apiGet(path, G)); if (!note) msg.textContent = ''; }
    catch (e) { fail(e); }
    finally { prevBtn.disabled = false; }
  }

  async function apply(planId, btn) {
    btn.disabled = true; msg.className = 'small'; msg.textContent = T('Desclassificando…', 'Disqualifying…', 'Descalificando…');
    try {
      const r = await apiPost(path, { action: 'apply', plan_id: planId }, G);
      await preview('✓ ' + r.count + T(' times desclassificados. O placar e a estatística se refazem sozinhos; se o relatório já foi publicado, republique-o.',
        ' teams disqualified. The scoreboard and the statistics rebuild by themselves; if the report was already published, publish it again.',
        ' equipos descalificados. El marcador y la estadística se rehacen solos; si el informe ya fue publicado, vuelve a publicarlo.'));
      if (onDone) onDone();
    } catch (e) {
      if (e.code === 'plan_changed') { await preview(T('A lista mudou desde a prévia: confira a nova lista e confirme de novo.', 'The list changed since the preview: check the new list and confirm again.', 'La lista cambió desde la vista previa: revisa la nueva lista y confirma de nuevo.')); return; }
      btn.disabled = false; fail(e);
    }
  }

  async function undo(id) {
    msg.className = 'small'; msg.textContent = T('Desfazendo…', 'Undoing…', 'Deshaciendo…');
    try {
      const r = await apiPost(path, { action: 'undo', batch: id }, G);
      await preview('✓ ' + r.restored + T(' times voltaram ao placar.', ' teams are back on the scoreboard.', ' equipos volvieron al marcador.'));
      if (onDone) onDone();
    } catch (e) { fail(e); }
  }

  return { el: card };
}
