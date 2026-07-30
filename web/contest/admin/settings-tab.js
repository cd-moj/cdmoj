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

const enc = encodeURIComponent;

export function makeSettingsTab(CONTEST) {
  const G = { contest: CONTEST, auth: true };
  const panel = el('div', { class: 'section' });

  // rótulo + índices dos filhos do editor (modo admin) + começa aberta?
  const GROUPS = () => [
    { label: T('🕒 Identidade e janela', '🕒 Identity and window'), idx: [0, 1, 2, 3], open: true },
    { label: T('👁 O que o time vê durante a prova', '👁 What the team sees during the contest'), idx: [6, 7, 8, 9, 10, 11, 12] },
    { label: T('⚖️ Julgamento (linguagens, pool, veredicto manual)', '⚖️ Judging (languages, pool, manual verdict)'), idx: [13, 14, 19, 20, 21, 22, 23, 24] },
    { label: T('🏅 Placar, freeze e penalidade', '🏅 Scoreboard, freeze and penalty'), idx: [15, 18, 25, 26, 27] },
    { label: T('🔒 Acesso ao contest', '🔒 Contest access'), idx: [4, 5, 16, 17] },
  ];

  async function load() {
    panel.innerHTML = '';
    panel.append(el('h2', {}, T('⚙️ Todas as configurações', '⚙️ All settings')));
    let s;
    try { s = await apiGet('/contest/admin/settings?contest=' + enc(CONTEST), G); }
    catch (e) { panel.append(el('div', { class: 'error-box' }, T('Falha: ', 'Failed: ') + (e.message || T('erro', 'error')))); return; }

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
        el('summary', {}, T('Outras opções', 'Other options')), ed.el));
    }
    panel.append(el('div', { class: 'small muted', style: 'margin:.4rem 0' },
      T('O "gate de login por substring de UA" fica em Acesso só por compatibilidade: quem configura o gate por sede é Pessoas › Máquinas & gate, que enxerga o esperado × visto de cada time.',
        'The "login gate by UA substring" stays under Access only for compatibility: the per-site gate is configured in People › Machines & gate, which shows expected × seen per team.')));

    const msg = el('div', { class: 'small' });
    const save = el('button', { class: 'btn' }, T('Salvar configurações', 'Save settings'));
    save.addEventListener('click', async () => {
      const v = ed.getValue();
      // DESMARCAR o super secreto exige digitar o id (o contest volta a ser listado e o placar
      // vira público — não pode acontecer sem querer)
      if (s.secret === true && v.secret === false) {
        const typed = prompt(T('O contest deixará de ser SUPER SECRETO: voltará a ser listado na home/arquivo/status e o placar ficará PÚBLICO.\n\nPara confirmar, digite o id do contest (', 'This contest will stop being SUPER SECRET: it goes back to being listed on home/archive/status and the scoreboard becomes PUBLIC.\n\nTo confirm, type the contest id (') + CONTEST + '):');
        if (typed !== CONTEST) { msg.className = 'small error-box'; msg.textContent = T('desmarcação cancelada (id não confere) — nada foi salvo.', 'unmark cancelled (id does not match) — nothing was saved.'); return; }
      }
      save.disabled = true; msg.className = 'small'; msg.textContent = T('Salvando…', 'Saving…');
      try {
        await apiPost('/contest/admin/settings?contest=' + enc(CONTEST), v, G);
        s.secret = v.secret; msg.className = 'small'; msg.textContent = T('✓ salvo', '✓ saved');
      } catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
      save.disabled = false;
    });
    panel.append(el('div', { class: 'row', style: 'margin-top:.7rem' }, save, msg));
    panel.append(await timeOverridesPanel(CONTEST, G));
  }
  return { panel, load };
}

// --- Prorrogação de vigência por sede/grupo (/contest/admin/time-overrides) ---------------
// Regras [{regex, end, reason}] contra o login: a 1ª que casa ESTENDE o fim do contest só
// p/ aquele grupo (caso de uso: queda de energia numa sede -> minutos extras só p/ ela).
export async function timeOverridesPanel(CONTEST, G) {
  const box = el('div', { style: 'margin-top:1.2rem;border-top:1px solid #e3e9f2;padding-top:.8rem' },
    el('h3', {}, T('⏱ Prorrogação por sede/grupo', '⏱ Extension by site/group')),
    el('p', { class: 'muted small' },
      T('Regras regex no login: a primeira que casar define o novo fim SÓ para aquele grupo ', 'Regex rules on the login: the first that matches sets the new end ONLY for that group '),
      T('(só estende — nunca encurta; a penalidade segue contada do início normal). ', '(only extends — never shortens; the penalty is still counted from the normal start). '),
      T('Ex.: queda de energia numa sede.', 'E.g.: power outage at a site.')));
  let data;
  try { data = await apiGet('/contest/admin/time-overrides?contest=' + enc(CONTEST), G); }
  catch (e) { box.append(el('div', { class: 'error-box' }, T('Falha: ', 'Failed: ') + (e.message || T('erro', 'error')))); return box; }
  const rules = Array.isArray(data.rules) ? data.rules.slice() : [];
  const list = el('div', {});
  const msg = el('div', { class: 'small' });
  const render = () => {
    list.innerHTML = '';
    rules.forEach((r, i) => {
      const rx = el('input', { value: r.regex || '', placeholder: '^sede1-', style: 'width:11rem;font-family:var(--mono)' });
      const en = el('input', { type: 'datetime-local', value: r.end ? toLocalDT(r.end) : '' });
      const rs = el('input', { value: r.reason || '', placeholder: T('motivo (ex.: queda de energia)', 'reason (e.g.: power outage)'), style: 'flex:1;min-width:12rem' });
      rx.addEventListener('input', () => { r.regex = rx.value; });
      en.addEventListener('input', () => { r.end = dtToEpoch(en.value); });
      rs.addEventListener('input', () => { r.reason = rs.value; });
      list.append(el('div', { class: 'row', style: 'gap:.4rem;margin:.25rem 0;flex-wrap:wrap' }, rx, en, rs,
        el('button', { class: 'btn danger ghost', title: T('remover', 'remove'), onclick: () => { rules.splice(i, 1); render(); } }, '✕')));
    });
    if (!rules.length) list.append(el('div', { class: 'muted small' }, T('Nenhuma regra ativa (todos seguem o fim normal).', 'No active rule (everyone follows the normal end).')));
  };
  render();
  const add = el('button', { class: 'btn ghost', onclick: () => {
    rules.push({ regex: '', end: (data.contest_end || 0) + 900, reason: '' }); render();
  } }, T('+ adicionar regra (+15 min sobre o fim)', '+ add rule (+15 min over the end)'));
  const save = el('button', { class: 'btn' }, T('Salvar prorrogações', 'Save extensions'));
  save.addEventListener('click', async () => {
    save.disabled = true; msg.className = 'small'; msg.textContent = T('Salvando…', 'Saving…');
    try {
      const r = await apiPost('/contest/admin/time-overrides?contest=' + enc(CONTEST), { rules }, G);
      rules.length = 0; rules.push(...(r.rules || [])); render();
      msg.textContent = '✓ ' + T('salvo', 'saved') + ' (' + rules.length + ' ' + T('regra', 'rule') + (rules.length === 1 ? '' : 's') + ')';
    } catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
    save.disabled = false;
  });
  box.append(list, el('div', { class: 'row', style: 'margin-top:.5rem;gap:.5rem' }, add, save, msg));
  return box;
}
