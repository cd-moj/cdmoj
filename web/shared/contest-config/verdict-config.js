// shared/contest-config/verdict-config.js — editores reusáveis (chief hub + admin) p/ a config
// do veredicto manual: (1) opções de veredicto {label,verdict}; (2) matriz auto problema×lang×veredicto.
import { apiGet, apiPost } from '/shared/api.js';
import { el } from '/shared/ui.js';

const CANON = ['Accepted', 'Wrong Answer', 'Time Limit Exceeded', 'Runtime Error', 'Compilation Error',
  'Presentation Error', 'Memory Limit Exceeded', 'Output Limit Exceeded', 'Contact staff'];

// ---- Opções de veredicto: lista de {label, verdict} ----
export function makeVerdictOptionsEditor(contest) {
  const G = { contest, auth: true };
  const enc = encodeURIComponent;
  const box = el('div', { class: 'section' }, el('h2', {}, '🏷️ Opções de veredicto'));
  const rows = el('div', {});
  const msg = el('div', { class: 'small' });
  const verdSel = (v) => { const s = el('select', {}, ...CANON.map(c => el('option', { value: c, selected: c === v ? 'selected' : null }, c))); if (v && !CANON.includes(v)) s.append(el('option', { value: v, selected: 'selected' }, v)); return s; };
  function addRow(o) {
    const label = el('input', { value: (o && o.label) || '', placeholder: 'texto (ex.: 5 - NO - Wrong answer)', style: 'width:46%' });
    const verd = verdSel(o && o.verdict);
    const rm = el('button', { class: 'btn ghost', type: 'button', onclick: () => row.remove() }, '✕');
    const row = el('div', { class: 'row', style: 'gap:.4rem; margin:.2rem 0' }, label, el('span', { class: 'small muted' }, '→'), verd, rm);
    row._get = () => ({ label: label.value.trim(), verdict: verd.value });
    rows.append(row);
  }
  const addBtn = el('button', { class: 'btn ghost', type: 'button', onclick: () => addRow() }, '+ opção');
  const save = el('button', { class: 'btn' }, 'Salvar opções');
  save.addEventListener('click', async () => {
    const options = Array.from(rows.children).map(r => r._get()).filter(o => o.label && o.verdict);
    if (!options.length) { msg.className = 'small error-box'; msg.textContent = 'Defina ao menos uma opção.'; return; }
    save.disabled = true; msg.className = 'small'; msg.textContent = 'Salvando…';
    try { await apiPost('/contest/final-verdicts?contest=' + enc(contest), { options }, G); msg.textContent = '✓ salvo'; save.disabled = false; }
    catch (e) { save.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || 'falha'; }
  });
  (async () => {
    let r; try { r = await apiGet('/contest/final-verdicts?contest=' + enc(contest), G); } catch { r = null; }
    (r && r.options || []).forEach(addRow);
    if (!rows.children.length) addRow();
  })();
  box.append(el('p', { class: 'muted small' }, 'O texto é o que o juiz vê; o veredicto é a string canônica enviada ao aluno (o "YES" deve ser Accepted).'),
    rows, el('div', { class: 'row', style: 'margin-top:.5rem' }, addBtn, save, msg));
  return box;
}

// ---- Matriz auto: por (problema, linguagem) marca quais veredictos saem automáticos ----
export function makeAutoVerdictEditor(contest) {
  const G = { contest, auth: true };
  const enc = encodeURIComponent;
  const box = el('div', { class: 'section' }, el('h2', {}, '⚙️ Veredicto automático (problema × linguagem × veredicto)'));
  const body = el('div', {});
  const msg = el('div', { class: 'small' });
  const save = el('button', { class: 'btn' }, 'Salvar matriz');
  let VERDS = CANON, BLOCKS = [];
  function ruleRow(cid, lang, picks) {
    const langInp = el('input', { value: lang || '*', placeholder: 'linguagem (ou *)', style: 'width:120px' });
    const checks = VERDS.map(v => { const c = el('input', { type: 'checkbox' }); c.checked = (picks || []).includes(v); return { v, c }; });
    // "todos": marca/desmarca todas as caixas de veredicto desta regra de uma vez
    const all = el('button', { class: 'btn ghost', type: 'button', title: 'marcar/desmarcar todos os veredictos' }, 'todos');
    all.addEventListener('click', () => { const every = checks.every(x => x.c.checked); checks.forEach(x => { x.c.checked = !every; }); });
    const rm = el('button', { class: 'btn ghost', type: 'button', onclick: () => row.remove() }, '✕');
    const row = el('div', { class: 'row', style: 'gap:.4rem; flex-wrap:wrap; margin:.2rem 0; border-top:1px dashed var(--line); padding-top:.3rem' },
      langInp, all, ...checks.map(ck => el('label', { class: 'small' }, ck.c, ' ' + ck.v)), rm);
    row._get = () => ({ lang: langInp.value.trim().toLowerCase(), verds: checks.filter(x => x.c.checked).map(x => x.v) });
    return row;
  }
  function probBlock(cid, rules) {
    const rdiv = el('div', {});
    const addRule = el('button', { class: 'btn ghost', type: 'button', onclick: () => rdiv.append(ruleRow(cid, '*', [])) }, '+ regra');
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
    save.disabled = true; msg.className = 'small'; msg.textContent = 'Salvando…';
    try { await apiPost('/contest/auto-verdicts?contest=' + enc(contest), { matrix }, G); msg.textContent = '✓ salvo'; save.disabled = false; }
    catch (e) { save.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || 'falha'; }
  });
  (async () => {
    let r; try { r = await apiGet('/contest/auto-verdicts?contest=' + enc(contest), G); } catch { r = null; }
    if (r && r.verdicts && r.verdicts.length) VERDS = r.verdicts;
    const probs = (r && r.problems) || [];
    const matrix = (r && r.matrix) || {};
    if (!probs.length) { body.append(el('div', { class: 'muted' }, 'Sem problemas no contest.')); }
    BLOCKS = probs.map(cid => probBlock(cid, matrix[cid]));
    BLOCKS.forEach(b => body.append(b));
  })();
  box.append(el('p', { class: 'muted small' }, 'Combinações marcadas saem AUTOMÁTICAS ao aluno (no modo veredicto manual). lang = id da linguagem em minúsculo, ou * p/ qualquer.'),
    body, el('div', { class: 'row', style: 'margin-top:.5rem' }, save, msg));
  return box;
}
