// contest/admin/settings-tab.js — "Central › Regras": TODAS as configurações do contest.
//
// O editor é o MESMO do wizard de criação (`makeSettingsEditor`, mode:'admin'): aqui ele só é
// REAGRUPADO em seções dobráveis. O editor devolve uma lista PLANA de filhos e os nós são
// realocados vivos (getValue() continua lendo os mesmos inputs) — por isso o agrupamento é uma
// lista de ÍNDICES na ordem de shared/contest-config/settings-editor.js. Mexeu na ordem de lá?
// Ajuste GROUPS aqui, senão um campo cai na seção errada (ninguém "perde" campo: o que sobrar vai
// para o fim, visível).
import { el } from '/shared/ui.js';
import { apiGet, apiPost } from '/shared/api.js';
import { makeSettingsEditor, toLocalDT, dtToEpoch } from '/shared/contest-config/index.js';
import { T } from '/shared/i18n.js';
import { esqErrorText } from './modules.js';

const enc = encodeURIComponent;

export function makeSettingsTab(CONTEST, opts = {}) {
  const G = { contest: CONTEST, auth: true };
  const has = typeof opts.has === 'function' ? opts.has : () => true;
  const panel = el('div', { class: 'section' });

  // rótulo + índices dos filhos do editor (modo admin) + começa aberta?
  // (2026-09-18: a caixa "mostrar o código a todos" — antigo índice 6 — foi REMOVIDA; tudo acima dele desceu 1)
  // (2026-09-28: a caixa "auto-cadastro (late users)" — antigo índice 5 — foi REMOVIDA; idem, desceu 1.
  //  smoke-settings-groups.gjs.sh confere que cada campo cai na seção certa e nenhum sobra)
  const GROUPS = () => [
    // 26,27,28 = o bloco do FUSO da prova, acrescentado no fim do editor (ver a nota lá:
    // campo novo entra no fim justamente para não deslocar estes índices)
    { label: T('🕒 Identidade e janela', '🕒 Identity and window', '🕒 Identidad y ventana'), idx: [0, 1, 2, 3, 26, 27, 28], open: true },
    { label: T('👁 O que o time vê durante a prova', '👁 What the team sees during the contest', '👁 Lo que el equipo ve durante la competencia'), idx: [5, 6, 7, 8, 9, 10] },
    // 35,36,37 = o bloco da PRIORIDADE no julgamento (01/10/2026), acrescentado no fim do editor
    { label: T('⚖️ Julgamento (linguagens, pool, veredicto manual)', '⚖️ Judging (languages, pool, manual verdict)', '⚖️ Evaluación (lenguajes, pool, veredicto manual)'), idx: [11, 12, 17, 18, 19, 20, 21, 22, 35, 36, 37] },
    // 29,30,31 = o bloco "balões durante o freeze", também acrescentado no fim do editor
    { label: T('🏅 Placar, freeze e penalidade', '🏅 Scoreboard, freeze and penalty', '🏅 Marcador, congelamiento y penalización'), idx: [13, 16, 23, 24, 25, 29, 30, 31, 32, 33, 34] },
    { label: T('🔒 Acesso ao contest', '🔒 Contest access', '🔒 Acceso a la competencia'), idx: [4, 14, 15] },
  ];

  async function load() {
    panel.innerHTML = '';
    panel.append(el('h2', {}, T('⚙️ Todas as configurações', '⚙️ All settings', '⚙️ Todas las configuraciones')));
    let s;
    try { s = await apiGet('/contest/admin/settings?contest=' + enc(CONTEST), G); }
    catch (e) { panel.append(el('div', { class: 'error-box' }, T('Falha: ', 'Failed: ', 'Error: ') + (e.message || T('erro', 'error', 'error')))); return; }

    const ed = makeSettingsEditor({ value: s, mode: 'admin', contestMode: s.mode, apiCtx: G });
    const kids = [...ed.el.children];
    GROUPS().forEach((g) => {
      const d = el('details', { class: 'fgroup' }, el('summary', {}, g.label));
      if (g.open) d.setAttribute('open', '');
      g.idx.forEach((i) => { if (kids[i]) d.append(kids[i]); });
      if (!d.querySelector('.field, h3, p, div')) return;   // grupo vazio não vira caixa vazia
      panel.append(d);
    });
    if (ed.el.children.length) {                            // sobra (editor mudou de ordem)
      panel.append(el('details', { class: 'fgroup', open: true },
        el('summary', {}, T('Outras opções', 'Other options', 'Otras opciones')), ed.el));
    }
    // o campo LEGADO do gate por substring de UA é do módulo `maquinas`: sem ele, nem o campo nem
    // a nota aparecem (o nó fica no editor — getValue() continua lendo o valor salvo)
    const uaField = panel.querySelector('[data-k="login_ua_substring"]');
    if (uaField) uaField.hidden = !has('maquinas');
    if (has('maquinas')) panel.append(el('div', { class: 'small muted', style: 'margin:.4rem 0' },
      T('O "gate de login por substring de UA" fica em Acesso só por compatibilidade: quem configura o gate por sede é Máquinas › Gate & trava, que enxerga o esperado × visto de cada time.',
        'The "login gate by UA substring" stays under Access only for compatibility: the per-site gate is configured in Machines › Gate & lock, which shows expected × seen per team.',
        'El "gate de login por substring de UA" se queda en Acceso solo por compatibilidad: el gate por sede se configura en Máquinas › Gate y bloqueo, que muestra esperado × visto por equipo.')));

    const msg = el('div', { class: 'small' });
    const save = el('button', { class: 'btn' }, T('Salvar configurações', 'Save settings', 'Guardar configuración'));
    save.addEventListener('click', async () => {
      const v = ed.getValue();
      // DESMARCAR o super secreto exige digitar o id (o contest volta a ser listado e o placar
      // vira público — não pode acontecer sem querer)
      if (s.secret === true && v.secret === false) {
        const typed = prompt(T('O contest deixará de ser SUPER SECRETO: voltará a ser listado na home/arquivo/status e o placar ficará PÚBLICO.\n\nPara confirmar, digite o id do contest (', 'This contest will stop being SUPER SECRET: it goes back to being listed on home/archive/status and the scoreboard becomes PUBLIC.\n\nTo confirm, type the contest id (', 'Esta competencia dejará de ser SUPER SECRETA: volverá a aparecer en la home/archivo/estado y el marcador se volverá PÚBLICO.\n\nPara confirmar, escribe el id de la competencia (') + CONTEST + '):');
        if (typed !== CONTEST) { msg.className = 'small error-box'; msg.textContent = T('desmarcação cancelada (id não confere) — nada foi salvo.', 'unmark cancelled (id does not match) — nothing was saved.', 'desmarcación cancelada (el id no coincide) — nada fue guardado.'); return; }
      }
      save.disabled = true; msg.className = 'small'; msg.textContent = T('Salvando…', 'Saving…', 'Guardando…');
      try {
        await apiPost('/contest/admin/settings?contest=' + enc(CONTEST), v, G);
        s.secret = v.secret; msg.className = 'small'; msg.textContent = T('✓ salvo', '✓ saved', '✓ guardado');
      } catch (e) { msg.className = 'small error-box'; msg.textContent = esqErrorText(e); }   // inclui o 409 do módulo esqueletos
      save.disabled = false;
    });
    panel.append(el('div', { class: 'row', style: 'margin-top:.7rem' }, save, msg));
    // (a ⏱ prorrogação por sede/grupo mora em Evento › Sedes & escolas — módulo `sedes`)
  }
  return { panel, load };
}

// --- Prorrogação de vigência por sede/grupo (/contest/admin/time-overrides) ---------------
// Regras [{regex, end, reason}] contra o login: a 1ª que casa ESTENDE o fim do contest só
// p/ aquele grupo (caso de uso: queda de energia numa sede -> minutos extras só p/ ela).
export async function timeOverridesPanel(CONTEST, G) {
  const box = el('div', { style: 'margin-top:1.2rem;border-top:1px solid #e3e9f2;padding-top:.8rem' },
    el('h3', {}, T('⏱ Prorrogação por sede/grupo', '⏱ Extension by site/group', '⏱ Prórroga por sede/grupo')),
    el('p', { class: 'muted small' },
      T('Regras regex no login: a primeira que casar define o novo fim SÓ para aquele grupo ', 'Regex rules on the login: the first that matches sets the new end ONLY for that group ', 'Reglas regex en el login: la primera que coincide define el nuevo fin SOLO para ese grupo '),
      T('(só estende — nunca encurta; a penalidade segue contada do início normal). ', '(only extends — never shortens; the penalty is still counted from the normal start). ', '(solo extiende — nunca acorta; la penalización se sigue contando desde el inicio normal). '),
      T('Ex.: queda de energia numa sede.', 'E.g.: power outage at a site.', 'Ej.: corte de energía en una sede.')));
  let data;
  try { data = await apiGet('/contest/admin/time-overrides?contest=' + enc(CONTEST), G); }
  catch (e) { box.append(el('div', { class: 'error-box' }, T('Falha: ', 'Failed: ', 'Error: ') + (e.message || T('erro', 'error', 'error')))); return box; }
  const rules = Array.isArray(data.rules) ? data.rules.slice() : [];
  const list = el('div', {});
  const msg = el('div', { class: 'small' });
  const render = () => {
    list.innerHTML = '';
    rules.forEach((r, i) => {
      const rx = el('input', { value: r.regex || '', placeholder: '^sede1-', style: 'width:11rem;font-family:var(--mono)' });
      const en = el('input', { type: 'datetime-local', value: r.end ? toLocalDT(r.end) : '' });
      const rs = el('input', { value: r.reason || '', placeholder: T('motivo (ex.: queda de energia)', 'reason (e.g.: power outage)', 'motivo (ej.: corte de energía)'), style: 'flex:1;min-width:12rem' });
      rx.addEventListener('input', () => { r.regex = rx.value; });
      en.addEventListener('input', () => { r.end = dtToEpoch(en.value); });
      rs.addEventListener('input', () => { r.reason = rs.value; });
      list.append(el('div', { class: 'row', style: 'gap:.4rem;margin:.25rem 0;flex-wrap:wrap' }, rx, en, rs,
        el('button', { class: 'btn ghost danger', title: T('remover', 'remove', 'quitar'), onclick: () => { rules.splice(i, 1); render(); } }, '✕')));
    });
    if (!rules.length) list.append(el('div', { class: 'muted small' }, T('Nenhuma regra ativa (todos seguem o fim normal).', 'No active rule (everyone follows the normal end).', 'Ninguna regla activa (todos siguen el fin normal).')));
  };
  render();
  const add = el('button', { class: 'btn ghost', onclick: () => {
    rules.push({ regex: '', end: (data.contest_end || 0) + 900, reason: '' }); render();
  } }, T('+ adicionar regra (+15 min sobre o fim)', '+ add rule (+15 min over the end)', '+ agregar regla (+15 min sobre el fin)'));
  const save = el('button', { class: 'btn' }, T('Salvar prorrogações', 'Save extensions', 'Guardar prórrogas'));
  save.addEventListener('click', async () => {
    save.disabled = true; msg.className = 'small'; msg.textContent = T('Salvando…', 'Saving…', 'Guardando…');
    try {
      const r = await apiPost('/contest/admin/time-overrides?contest=' + enc(CONTEST), { rules }, G);
      rules.length = 0; rules.push(...(r.rules || [])); render();
      msg.textContent = '✓ ' + T('salvo', 'saved', 'guardado') + ' (' + rules.length + ' ' + T('regra', 'rule', 'regla') + (rules.length === 1 ? '' : 's') + ')';
    } catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed', 'fallido'); }
    save.disabled = false;
  });
  box.append(list, el('div', { class: 'row', style: 'margin-top:.5rem;gap:.5rem' }, add, save, msg));
  return box;
}
