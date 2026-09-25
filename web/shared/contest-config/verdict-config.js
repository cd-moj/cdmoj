// shared/contest-config/verdict-config.js — editores reusáveis (chief hub + admin) p/ a config
// do veredicto manual: (1) opções de veredicto {label, verdict (classe), team}; (2) o que vai para
// REVISÃO (grade problema × classe + exceções por linguagem; lib/review-rules.sh). As 6 CLASSES vêm do servidor (GET final-verdicts .classes) — é o
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

// ---- O que vai para REVISÃO: grade problema × classe + exceções por linguagem ----
// Regra (lib/review-rules.sh, v2 OPT-OUT): com o veredicto manual ligado, TUDO sai automático, menos
// o que esta grade marca. Pedidos de 25/09/2026: o Vinícius queria opt-out do automático; o Daniel
// Saad, o título do problema no lugar do id. O arquivo antigo (v1, "sai automático") chega convertido
// do servidor e só muda quando alguém salva. Mudou a grade com itens já retidos que agora sairiam
// automáticos? A tela oferece LIBERAR (não libera sozinha).
const SHORT = { 'Accepted': 'AC', 'Wrong Answer': 'WA', 'Time Limit Exceeded': 'TLE', 'Memory Limit Exceeded': 'MLE', 'Runtime Error': 'RTE', 'Compilation Error': 'CE' };
const RV_CSS = '.rvg{border-collapse:collapse;min-width:100%}'
  + '.rvg th,.rvg td{padding:.3rem .45rem;border-bottom:1px solid var(--line);text-align:center;white-space:nowrap}'
  + '.rvg th.p,.rvg td.p{text-align:left;white-space:normal;min-width:12rem}'
  + '.rvg td.on{background:var(--warn-bg)}'
  + '.rvg tr.all td{background:var(--blue-bg);font-weight:600}'
  + '.rvg input{cursor:pointer;width:1.05rem;height:1.05rem}'
  + '.rvg .id{font-size:.8em;color:var(--muted);margin-left:.35rem}'
  + '.rvx{display:flex;gap:.4rem;flex-wrap:wrap;align-items:center;margin:.3rem 0;padding-top:.3rem;border-top:1px dashed var(--line)}';

export function makeAutoVerdictEditor(contest) {
  const G = { contest, auth: true };
  const enc = encodeURIComponent;
  if (typeof document !== 'undefined' && document.head && !document.getElementById('rvGridCss')) {
    const s = document.createElement('style'); s.id = 'rvGridCss'; s.textContent = RV_CSS; document.head.appendChild(s);
  }
  const box = el('div', { class: 'section' }, el('h2', {}, T('🔎 O que vai para revisão', '🔎 What goes to review')));
  const banner = el('div', {});
  const summary = el('div', { class: 'small muted', style: 'margin:.2rem 0 .5rem' });
  const gridBox = el('div', { style: 'overflow-x:auto' });
  const exList = el('div', {});
  const exSum = el('summary', {});
  const exBox = el('details', { class: 'fgroup', style: 'margin-top:.8rem' }, exSum,
    el('p', { class: 'muted small' }, T('Uma exceção vale para UMA linguagem e vence a tabela. Exemplo: Python · TLE · vai para revisão — o TLE de Python vai para os juízes mesmo que a tabela deixe TLE automático. A exceção de um problema vence a de "todos os problemas".',
      'An exception applies to ONE language and overrides the table. Example: Python · TLE · goes to review — Python TLE goes to the judges even if the table leaves TLE automatic. A problem exception overrides an "all problems" one.')),
    exList);
  const msg = el('span', { class: 'small' });
  const relBox = el('div', {});
  const save = el('button', { class: 'btn' }, T('Salvar', 'Save'));
  let VERDS = CANON, ITEMS = [], LANGS = [];
  let cells = {};          // cells[cid][classe] = checkbox
  const rowAll = {}, colAll = {};

  const setMsg = (t, cls) => { msg.className = cls || 'small'; msg.textContent = t; };
  const dirty = () => setMsg(T('alterações não salvas', 'unsaved changes'), 'small muted');
  const probLabel = (it) => (it.letter ? it.letter + ' — ' : '') + (it.title || it.id);

  function refresh() {        // pinta as células, os "todos" (tri-estado) e o resumo
    let on = 0, tot = 0;
    ITEMS.forEach((it) => {
      const row = cells[it.id]; let n = 0;
      VERDS.forEach((v) => { const c = row[v]; tot++; if (c.checked) { on++; n++; } c.parentNode && (c.parentNode.className = c.checked ? 'on' : ''); });
      const ra = rowAll[it.id]; ra.checked = n === VERDS.length; ra.indeterminate = n > 0 && n < VERDS.length;
    });
    VERDS.forEach((v) => {
      const n = ITEMS.filter((it) => cells[it.id][v].checked).length;
      const ca = colAll[v]; ca.checked = ITEMS.length > 0 && n === ITEMS.length; ca.indeterminate = n > 0 && n < ITEMS.length;
    });
    summary.textContent = on
      ? T(`${on} de ${tot} combinações problema × veredicto vão para revisão; o resto sai automático. Erro do juiz sempre vai para revisão.`,
          `${on} of ${tot} problem × verdict combinations go to review; the rest is automatic. Judge errors always go to review.`)
      : T('Nada marcado: todo veredicto sai automático para o time (só erro do juiz vai para revisão).',
          'Nothing checked: every verdict goes to the team automatically (only judge errors go to review).');
  }
  function setAll(pred, val) { ITEMS.forEach((it) => VERDS.forEach((v) => { if (pred(it, v)) cells[it.id][v].checked = val; })); refresh(); dirty(); }

  function buildGrid(review) {
    cells = {};
    const thead = el('tr', {}, el('th', { class: 'p' }, T('Problema', 'Problem')),
      ...VERDS.map((v) => el('th', { title: v }, SHORT[v] || v)));
    const allRow = el('tr', { class: 'all' }, el('td', { class: 'p' }, T('Todos os problemas', 'All problems')),
      ...VERDS.map((v) => {
        const c = el('input', { type: 'checkbox', title: T('marcar/desmarcar a coluna ', 'check/uncheck the column ') + v });
        c.addEventListener('change', () => setAll((it, vv) => vv === v, c.checked));
        colAll[v] = c; return el('td', {}, c);
      }));
    const rows = ITEMS.map((it) => {
      cells[it.id] = {};
      const ra = el('input', { type: 'checkbox', title: T('marcar/desmarcar a linha', 'check/uncheck the row') });
      ra.addEventListener('change', () => setAll((x) => x.id === it.id, ra.checked));
      rowAll[it.id] = ra;
      const tds = VERDS.map((v) => {
        const c = el('input', { type: 'checkbox', title: probLabel(it) + ' · ' + v });
        c.checked = ((review && review[it.id]) || []).includes(v);
        c.addEventListener('change', () => { refresh(); dirty(); });
        cells[it.id][v] = c;
        return el('td', {}, c);
      });
      return el('tr', {}, el('td', { class: 'p' }, el('label', { style: 'display:flex;gap:.4rem;align-items:center;cursor:pointer' },
        ra, el('span', { title: it.id }, el('b', {}, it.letter || ''), ' ', it.title || it.id,
          it.title ? el('span', { class: 'id' }, it.id.includes('#') ? it.id.slice(it.id.indexOf('#') + 1) : it.id) : null))), ...tds);
    });
    gridBox.innerHTML = '';
    gridBox.append(el('table', { class: 'rvg' }, el('thead', {}, thead), el('tbody', {}, allRow, ...rows)));
    refresh();
  }

  function exRow(x) {
    const langs = LANGS.slice(); if (x && x.lang && !langs.includes(x.lang)) langs.push(x.lang);
    const lang = el('select', {}, ...langs.map((l) => el('option', { value: l, selected: x && x.lang === l ? 'selected' : null }, l)));
    const prob = el('select', { style: 'max-width:16rem' }, el('option', { value: '*' }, T('todos os problemas', 'all problems')),
      ...ITEMS.map((it) => el('option', { value: it.id, selected: x && x.problem === it.id ? 'selected' : null }, probLabel(it))));
    const to = el('select', {},
      el('option', { value: 'review', selected: !x || x.to !== 'auto' ? 'selected' : null }, T('vai para revisão', 'goes to review')),
      el('option', { value: 'auto', selected: x && x.to === 'auto' ? 'selected' : null }, T('sai automático', 'is automatic')));
    const checks = VERDS.map((v) => { const c = el('input', { type: 'checkbox' }); c.checked = !!(x && (x.verdicts || []).includes(v)); c.addEventListener('change', dirty); return { v, c }; });
    [lang, prob, to].forEach((s) => s.addEventListener('change', dirty));
    const rm = el('button', { class: 'btn ghost', type: 'button', title: T('remover', 'remove'), onclick: () => { row.remove(); exCount(); dirty(); } }, '✕');
    const row = el('div', { class: 'rvx' }, lang, el('span', { class: 'small muted' }, '·'),
      ...checks.map((k) => el('label', { class: 'small', title: k.v }, k.c, ' ' + (SHORT[k.v] || k.v))),
      el('span', { class: 'small muted' }, '·'), to, el('span', { class: 'small muted' }, T('em', 'in')), prob, rm);
    row._get = () => ({ lang: lang.value, problem: prob.value, to: to.value, verdicts: checks.filter((k) => k.c.checked).map((k) => k.v) });
    return row;
  }
  function exCount() {
    const n = Array.from(exList.children).filter((r) => r._get).length;
    exSum.textContent = T(`Exceções por linguagem (${n})`, `Per-language exceptions (${n})`);
  }
  const addEx = el('button', { class: 'btn ghost', type: 'button' }, T('+ exceção', '+ exception'));
  addEx.addEventListener('click', () => { exList.insertBefore(exRow(null), addEx); exCount(); dirty(); });

  function showReleasable(n) {
    relBox.innerHTML = '';
    if (!n) return;
    const go = el('button', { class: 'btn' }, T('Liberar agora', 'Release now'));
    const out = el('span', { class: 'small' });
    go.addEventListener('click', async () => {
      if (!confirm(T(`Liberar ${n} submissão(ões) retida(s) com o veredicto da máquina? Só sai o que nenhum juiz votou e o que não está em conflito.`,
        `Release ${n} held submission(s) with the machine verdict? Only what no judge voted on and what is not in conflict goes out.`))) return;
      go.disabled = true; out.textContent = T('⏳ liberando…', '⏳ releasing…');
      try {
        const r = await apiPost('/contest/auto-verdicts?contest=' + enc(contest), { action: 'release' }, G);
        out.textContent = T(`✓ ${r.released || 0} liberada(s); ${r.left || 0} seguem na fila dos juízes.`, `✓ ${r.released || 0} released; ${r.left || 0} remain in the judges' queue.`);
      } catch (e) { go.disabled = false; out.className = 'small error-box'; out.textContent = e.message || T('falha', 'failed'); }
    });
    relBox.append(el('div', { class: 'notice small', style: 'margin-top:.6rem' },
      T(`${n} submissão(ões) retida(s) agora sairiam automáticas pelas regras salvas (nenhum juiz votou nelas ainda). `,
        `${n} held submission(s) would now be automatic under the saved rules (no judge has voted on them yet). `),
      go, ' ', out));
  }

  save.addEventListener('click', async () => {
    const review = {};
    ITEMS.forEach((it) => { const vs = VERDS.filter((v) => cells[it.id][v].checked); if (vs.length) review[it.id] = vs; });
    const langs = Array.from(exList.children).filter((r) => r._get).map((r) => r._get()).filter((x) => x.lang && x.verdicts.length);
    save.disabled = true; setMsg(T('Salvando…', 'Saving…'));
    try {
      const r = await apiPost('/contest/auto-verdicts?contest=' + enc(contest), { rules: { review, langs } }, G);
      save.disabled = false; setMsg(T('✓ salvo', '✓ saved'));
      banner.innerHTML = '';   // o aviso de "formato anterior" / "ilegível" deixa de valer
      showReleasable(r.releasable || 0);
    } catch (e) { save.disabled = false; setMsg(e.message || T('falha', 'failed'), 'small error-box'); }
  });

  (async () => {
    let r; try { r = await apiGet('/contest/auto-verdicts?contest=' + enc(contest), G); } catch (e) { r = null; }
    if (!r) { gridBox.append(el('div', { class: 'error-box small' }, T('Não foi possível carregar as regras.', 'Could not load the rules.'))); return; }
    if (Array.isArray(r.verdicts) && r.verdicts.length) VERDS = r.verdicts;
    ITEMS = Array.isArray(r.items) ? r.items : (r.problems || []).map((id) => ({ id, letter: '', title: '' }));
    LANGS = Array.isArray(r.langs) ? r.langs : [];
    if (r.manual_verdict === false) banner.append(el('div', { class: 'notice small', style: 'margin:.3rem 0' },
      T('O veredicto manual está DESLIGADO neste contest: tudo sai automático e esta tabela só passa a valer quando o admin ligar o veredicto manual (Central › Regras).',
        'Manual verdict is OFF in this contest: everything is automatic, and this table only takes effect once the admin turns manual verdict on (Home › Rules).')));
    if (r.state === 'invalid') banner.append(el('div', { class: 'error-box small', style: 'margin:.3rem 0' },
      T('O arquivo de regras está ilegível, então TUDO está indo para revisão. Salve a tabela para corrigir.',
        'The rules file is unreadable, so EVERYTHING is going to review. Save the table to fix it.')));
    if (r.state === 'v1') banner.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' },
      T('Regras no formato anterior ("o que sai automático"), mostradas aqui convertidas. Nada muda até você salvar; ao salvar, grava o equivalente.',
        'Rules in the previous format ("what is automatic"), shown here converted. Nothing changes until you save; saving writes the equivalent.')));
    if (!ITEMS.length) { gridBox.append(el('div', { class: 'muted' }, T('Sem problemas no contest.', 'No problems in the contest.'))); return; }
    const rules = r.rules || { review: {}, langs: [] };
    buildGrid(rules.review || {});
    (rules.langs || []).forEach((x) => exList.append(exRow(x)));
    exList.append(addEx); exCount();
    if ((rules.langs || []).length) exBox.open = true;
    showReleasable(r.releasable || 0);
  })();

  box.append(
    el('p', { class: 'muted small' }, T('Marque o que os juízes revisam antes de o time ver o resultado. O que não estiver marcado sai automático, direto da máquina. Vale quando o veredicto manual está ligado.',
      'Check what the judges review before the team sees the result. Whatever is not checked goes out automatically, straight from the machine. Applies when manual verdict is on.')),
    banner, summary, gridBox,
    el('div', { class: 'row', style: 'margin-top:.5rem;gap:.4rem' },
      el('button', { class: 'btn ghost', type: 'button', onclick: () => setAll(() => true, true) }, T('Revisar tudo', 'Review everything')),
      el('button', { class: 'btn ghost', type: 'button', onclick: () => setAll(() => true, false) }, T('Nada em revisão', 'Nothing in review'))),
    exBox,
    el('div', { class: 'row', style: 'margin-top:.6rem' }, save, msg), relBox);
  return box;
}
