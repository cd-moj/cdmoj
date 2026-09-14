// shared/contest-config/verdict-config.js — editores reusáveis (chief hub + admin) p/ a config
// do veredicto manual: (1) opções de veredicto {label, verdict (classe), team}; (2) matriz auto
// problema×lang×classe. As 6 CLASSES vêm do servidor (GET final-verdicts .classes) — é o
// vocabulário de lib/verdict.sh: a classe pontua/penaliza/colore; o texto do time é livre.
import { apiGet, apiPost } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { T } from '/shared/i18n.js';

const CANON = ['Accepted', 'Wrong Answer', 'Time Limit Exceeded', 'Memory Limit Exceeded', 'Runtime Error', 'Compilation Error'];

// ---- Opções de veredicto: lista de {label, verdict, team} ----
export function makeVerdictOptionsEditor(contest) {
  const G = { contest, auth: true };
  const enc = encodeURIComponent;
  const box = el('div', { class: 'section' }, el('h2', {}, T('🏷️ Opções de veredicto', '🏷️ Verdict options')));
  const rows = el('div', {});
  const msg = el('div', { class: 'small' });
  let CLASSES = CANON;
  const verdSel = (v) => el('select', {}, ...CLASSES.map(c => el('option', { value: c, selected: c === v ? 'selected' : null }, c)));
  function addRow(o) {
    const label = el('input', { value: (o && o.label) || '', placeholder: T('o juiz escolhe (ex.: 5 - NO - Wrong answer)', 'the judge picks (e.g. 5 - NO - Wrong answer)'), style: 'width:30%' });
    const verd = verdSel((o && o.verdict) || 'Wrong Answer');
    const team = el('input', { value: (o && o.team) || '', placeholder: T('o time vê (vazio = a classe)', 'the team sees (empty = the class)'), style: 'width:30%' });
    const sync = () => { team.disabled = verd.value === 'Accepted'; if (team.disabled) team.value = ''; };
    verd.addEventListener('change', sync); sync();
    const rm = el('button', { class: 'btn ghost danger', type: 'button', title: T('remover', 'remove'), onclick: () => row.remove() }, '✕');
    const row = el('div', { class: 'row', style: 'gap:.4rem; margin:.2rem 0; flex-wrap:wrap' }, label, el('span', { class: 'small muted' }, '→'), verd, el('span', { class: 'small muted' }, '→'), team, rm);
    row._get = () => ({ label: label.value.trim(), verdict: verd.value, team: team.value.trim() });
    rows.append(row);
  }
  const addBtn = el('button', { class: 'btn ghost', type: 'button', onclick: () => addRow() }, T('+ opção', '+ option'));
  const save = el('button', { class: 'btn' }, T('Salvar opções', 'Save options'));
  save.addEventListener('click', async () => {
    const options = Array.from(rows.children).map(r => r._get()).filter(o => o.label && o.verdict);
    if (!options.length) { msg.className = 'small error-box'; msg.textContent = T('Defina ao menos uma opção.', 'Define at least one option.'); return; }
    save.disabled = true; msg.className = 'small'; msg.textContent = T('Salvando…', 'Saving…');
    try { await apiPost('/contest/final-verdicts?contest=' + enc(contest), { options }, G); msg.textContent = T('✓ salvo', '✓ saved'); save.disabled = false; }
    catch (e) { save.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
  });
  (async () => {
    let r; try { r = await apiGet('/contest/final-verdicts?contest=' + enc(contest), G); } catch { r = null; }
    if (r && Array.isArray(r.classes) && r.classes.length) CLASSES = r.classes;
    (r && r.options || []).forEach(addRow);
    if (!rows.children.length) addRow();
  })();
  box.append(el('p', { class: 'muted small' },
    T('Cada opção tem três campos. O primeiro é o que o juiz escolhe. O segundo é a classe: uma das seis classes canônicas. A classe define a pontuação, a penalidade e a cor no placar. O terceiro é o texto que o time vê. Deixe o texto vazio para mostrar a classe. A classe Accepted não tem texto próprio.',
      'Each option has three fields. The first is what the judge picks. The second is the class: one of the six canonical classes. The class sets the score, the penalty and the colour on the scoreboard. The third is the text the team sees. Leave the text empty to show the class. The Accepted class has no custom text.')),
    el('div', { class: 'row small muted', style: 'gap:.4rem' }, el('span', { style: 'width:30%' }, T('juiz vê', 'judge sees')), el('span', {}, ' '), el('span', {}, T('classe', 'class')), el('span', {}, ' '), el('span', { style: 'width:30%' }, T('time vê', 'team sees'))),
    rows, el('div', { class: 'row', style: 'margin-top:.5rem' }, addBtn, save, msg));
  return box;
}

// ---- Matriz auto: por (problema, linguagem) marca quais veredictos saem automáticos ----
export function makeAutoVerdictEditor(contest) {
  const G = { contest, auth: true };
  const enc = encodeURIComponent;
  const box = el('div', { class: 'section' }, el('h2', {}, T('⚙️ Veredicto automático (problema × linguagem × veredicto)', '⚙️ Automatic verdict (problem × language × verdict)')));
  const body = el('div', {});
  const msg = el('div', { class: 'small' });
  const save = el('button', { class: 'btn' }, T('Salvar matriz', 'Save matrix'));
  let VERDS = CANON, BLOCKS = [];
  function ruleRow(cid, lang, picks) {
    const langInp = el('input', { value: lang || '*', placeholder: T('linguagem (ou *)', 'language (or *)'), style: 'width:120px' });
    const checks = VERDS.map(v => { const c = el('input', { type: 'checkbox' }); c.checked = (picks || []).includes(v); return { v, c }; });
    // "todos": marca/desmarca todas as caixas de veredicto desta regra de uma vez
    const all = el('button', { class: 'btn ghost', type: 'button', title: T('marcar/desmarcar todos os veredictos', 'check/uncheck all verdicts') }, T('todos', 'all'));
    all.addEventListener('click', () => { const every = checks.every(x => x.c.checked); checks.forEach(x => { x.c.checked = !every; }); });
    const rm = el('button', { class: 'btn ghost', type: 'button', onclick: () => row.remove() }, '✕');
    const row = el('div', { class: 'row', style: 'gap:.4rem; flex-wrap:wrap; margin:.2rem 0; border-top:1px dashed var(--line); padding-top:.3rem' },
      langInp, all, ...checks.map(ck => el('label', { class: 'small' }, ck.c, ' ' + ck.v)), rm);
    row._get = () => ({ lang: langInp.value.trim().toLowerCase(), verds: checks.filter(x => x.c.checked).map(x => x.v) });
    return row;
  }
  function probBlock(cid, rules) {
    const rdiv = el('div', {});
    const addRule = el('button', { class: 'btn ghost', type: 'button', onclick: () => rdiv.append(ruleRow(cid, '*', [])) }, T('+ regra', '+ rule'));
    Object.entries(rules || {}).forEach(([lang, picks]) => rdiv.append(ruleRow(cid, lang, picks)));
    const blk = el('div', { class: 'field', style: 'border:1px solid var(--line); border-radius:.5rem; padding:.4rem .6rem; margin:.3rem 0' },
      el('label', {}, el('b', {}, cid)), rdiv, addRule);
    blk._cid = cid; blk._rules = rdiv;
    return blk;
  }
  save.addEventListener('click', async () => {
    const matrix = {};
    BLOCKS.forEach(blk => {
      const m = {};
      Array.from(blk._rules.children).forEach(row => { if (!row._get) return; const g = row._get(); if (g.lang && g.verds.length) m[g.lang] = g.verds; });
      if (Object.keys(m).length) matrix[blk._cid] = m;
    });
    save.disabled = true; msg.className = 'small'; msg.textContent = T('Salvando…', 'Saving…');
    try { await apiPost('/contest/auto-verdicts?contest=' + enc(contest), { matrix }, G); msg.textContent = T('✓ salvo', '✓ saved'); save.disabled = false; }
    catch (e) { save.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
  });
  (async () => {
    let r; try { r = await apiGet('/contest/auto-verdicts?contest=' + enc(contest), G); } catch { r = null; }
    if (r && r.verdicts && r.verdicts.length) VERDS = r.verdicts;
    const probs = (r && r.problems) || [];
    const matrix = (r && r.matrix) || {};
    if (!probs.length) { body.append(el('div', { class: 'muted' }, T('Sem problemas no contest.', 'No problems in the contest.'))); }
    BLOCKS = probs.map(cid => probBlock(cid, matrix[cid]));
    BLOCKS.forEach(b => body.append(b));
  })();
  box.append(el('p', { class: 'muted small' }, T('Combinações marcadas saem AUTOMÁTICAS ao aluno (no modo veredicto manual). lang = id da linguagem em minúsculo, ou * p/ qualquer.', 'Checked combinations are sent AUTOMATICALLY to the student (in manual verdict mode). lang = lowercase language id, or * for any.')),
    body, el('div', { class: 'row', style: 'margin-top:.5rem' }, save, msg));
  return box;
}
