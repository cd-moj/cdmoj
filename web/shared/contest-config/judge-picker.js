// shared/contest-config/judge-picker.js — seletor de MÁQUINAS de juiz (pool), a partir do
// registro vivo (GET /problems/judges). Compartilhado: aba Configurações/Problemas do admin
// e o wizard de criação. Nenhuma marcada = sem pool (qualquer juiz online julga).
// Host selecionado que sumiu do registro continua marcado (com aviso) — não se perde a
// escolha por um agente reiniciando. Se a API falhar, degrada p/ input de texto livre.
import { el } from '/shared/ui.js';
import { T } from '/shared/i18n.js';
import { apiGet } from '/shared/api.js';

// makeJudgePicker(selectedHosts, apiCtx) -> { el, get() -> [hosts marcados] }
// apiCtx = { contest, auth } (o contexto da página: admin do contest ou sessão do treino).
export function makeJudgePicker(selectedHosts, apiCtx) {
  const sel = new Set((selectedHosts || []).map((h) => String(h).trim()).filter(Boolean));
  const box = el('div', { class: 'lang-grid' }, el('span', { class: 'muted small' }, T('carregando juízes…', 'loading judges…')));
  const boxes = [];           // { host, c }
  let fallback = null;        // input texto (se a API falhar)

  const addBox = (host, note) => {
    const c = el('input', { type: 'checkbox' }); c.checked = sel.has(host);
    boxes.push({ host, c });
    return el('label', { class: 'lang-chip', title: note || '' }, c, ' ' + host + (note ? ' ' + note : ''));
  };

  (async () => {
    try {
      const js = (await apiGet('/problems/judges', apiCtx || {})).judges || [];
      box.replaceChildren();
      js.forEach((j) => box.append(addBox(j.host,
        (j.cpu ? '(' + j.cpu + ')' : '') + (j.online ? '' : ' 🔴 offline'))));
      // selecionados que não estão (mais) no registro: mantém marcado, com aviso
      [...sel].filter((h) => !js.some((j) => j.host === h))
        .forEach((h) => box.append(addBox(h, T('⚠️ não registrado', '⚠️ not registered'))));
      if (!boxes.length) box.append(el('span', { class: 'muted small' }, T('nenhum juiz registrado', 'no judge registered')));
    } catch {
      // degrada p/ texto livre — não bloqueia a criação/edição do contest
      fallback = el('input', { value: [...sel].join(' '), placeholder: T('hosts separados por espaço (vazio = todos)', 'hosts separated by space (empty = all)'), style: 'width:100%' });
      box.replaceChildren(el('span', { class: 'muted small' }, T('não deu para listar os juízes — informe os hosts:', "couldn't list the judges — enter the hosts:")), fallback);
    }
  })();

  return {
    el: box,
    get: () => (fallback
      ? fallback.value.trim().split(/\s+/).filter(Boolean)
      : boxes.filter((b) => b.c.checked).map((b) => b.host)),
  };
}
