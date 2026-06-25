// problemas/editar.js — editor de problemas (autoria keyless; git escondido).
// Layout em ABAS (Enunciado · Testes & Pontuação · Soluções · Limites · Publicação) com uma
// barra de PRONTIDÃO fixa (o que já está pronto e o que falta). Suporta limite de memória (MEMLIMITMB) e
// PONTUAÇÃO POR GRUPOS (subtasks estilo OBI: cada grupo de testes tem um peso → tests/score).
import { apiGet, apiPost, ApiError, getToken } from '/shared/api.js';
import { status, fileToBase64 } from '/shared/auth.js';
import { el, renderAuthArea, fmtDate } from '/shared/ui.js';
import { createEditor } from '/shared/editor.js';

const CONTEST = 'treino';
let MODE = 'new', ID = '', REPO = '', OWNER = '', EDITABLE = true, REPOS = [], loadedPublic = false;
let enunEd = null;
let COLLS = [];
let CAN_CREATE = false;
let FMT = 'md';                       // formato do enunciado (md|org|tex) — preservado no save
let SCORE = { enabled: false, groups: [] };   // pontuação por grupos (espelho do DOM)
let VAL = { validated: 'na', calibrated: 'na' };   // estado p/ a barra de prontidão

const qs = () => new URLSearchParams(location.search);
const splitList = (s) => (s || '').split(',').map(x => x.trim()).filter(Boolean);
const $ = (id) => document.getElementById(id);
const setMsg = (t, cls) => { const m = $('msg'); m.textContent = t; m.className = 'small ' + (cls || ''); };
const b64ToUtf8 = (b) => { try { return new TextDecoder().decode(Uint8Array.from(atob(b), c => c.charCodeAt(0))); } catch { return ''; } };
// extensão de arquivo -> modo de realce (cobre todas as linguagens aceitas pelo juiz)
const EXT2CM = {
  py: 'python', cpp: 'cpp', cc: 'cpp', cxx: 'cpp', c: 'cpp', h: 'cpp', hpp: 'cpp', java: 'java',
  rs: 'rust', go: 'go', js: 'javascript', md: 'markdown', cs: 'csharp', hs: 'haskell',
  ml: 'ocaml', mli: 'ocaml', pas: 'pascal', p: 'pascal', pp: 'pascal', sh: 'shell', bash: 'shell',
  apl: 'apl', dyalog: 'apl', s: 'gas', asm: 'gas', pl: 'prolog', pro: 'prolog', swipl: 'prolog',
};
const cmFor = (fn) => EXT2CM[(String(fn).split('.').pop() || '').toLowerCase()] || '';
// seletor de linguagem do editor de soluções — uma entrada por linguagem aceita
const LANG_OPTS = [['', 'texto'], ['cpp', 'C / C++'], ['python', 'Python'], ['java', 'Java'],
  ['csharp', 'C#'], ['go', 'Go'], ['rust', 'Rust'], ['haskell', 'Haskell'], ['ocaml', 'OCaml'],
  ['pascal', 'Pascal'], ['prolog', 'Prolog'], ['shell', 'Shell / Bash'], ['apl', 'APL'],
  ['gas', 'Assembly (MIPS / RISC-V)'], ['javascript', 'JavaScript'], ['markdown', 'Markdown']];
const SOL_CATS = [['good', 'good — deve ser ACEITA'], ['wrong', 'wrong — deve FALHAR'], ['slow', 'slow — estoura o TEMPO'], ['pass', 'pass — aceitas (não calibram)'], ['upcoming', 'upcoming — em desenvolvimento']];
const DEFNAME = { good: 'sol.cpp', wrong: 'wa.cpp', slow: 'slow.cpp', pass: 'alt.cpp', upcoming: 'wip.cpp' };
// selo com o resultado que cada categoria de solução deve obter no juiz
const SOL_BADGE = {
  good: ['sb-good', 'devem ser aceitas (Accepted) — definem o tempo-limite do problema'],
  wrong: ['sb-wrong', 'devem falhar (Wrong Answer ou erro de execução)'],
  slow: ['sb-slow', 'devem estourar o tempo (Time Limit Exceeded)'],
  pass: ['sb-pass', 'também são aceitas, mas não entram na calibração do tempo'],
  upcoming: ['sb-upcoming', 'em desenvolvimento — o juiz não as executa'],
};
// DERIVADO de SOL_CATS p/ nunca dessincronizar (a causa do bug que travava a página)
let solEditors = Object.fromEntries(SOL_CATS.map(([c]) => [c, []]));

// ---- conf (configurações do problema) -----------------------------------------------------
const confVal = (text, key) => { const e = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); const m = (text || '').match(new RegExp('^\\s*' + e + '\\s*=\\s*(.*)$', 'm')); return m ? m[1].trim().replace(/^"(.*)"$/, '$1').replace(/^'(.*)'$/, '$1') : null; };
function confUpsert(text, key, value) {
  const lines = (text || '').split('\n'), e = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), re = new RegExp('^\\s*' + e + '\\s*=');
  const idx = lines.findIndex(l => re.test(l));
  if (value === null || value === '') { if (idx >= 0) lines.splice(idx, 1); }
  else { const v = /[\s+]/.test(value) ? `"${value}"` : value, line = key + '=' + v; if (idx >= 0) lines[idx] = line; else lines.push(line); }
  return lines.join('\n').replace(/\n{3,}/g, '\n\n');
}
const CF_TEXT = [['cf_memlimit', 'MEMLIMITMB'], ['cf_calibrafactor', 'TLMOD[calibrafactor]'], ['cf_calibrationtl', 'CALIBRATIONTL'], ['cf_ulimit_u', 'ULIMITS[-u]'], ['cf_ulimit_f', 'ULIMITS[-f]'], ['cf_maxparallel', 'MAXPARALLELTESTS']];
const CF_YN = [['cf_allowparallel', 'ALLOWPARALLELTEST'], ['cf_tlererun', 'TLERERUN'], ['cf_stopwa', 'STOPWHEN_WA'], ['cf_stoptle', 'STOPWHEN_TLE'], ['cf_stopre', 'STOPWHEN_RE']];
const CF_FLAG = [['cf_allowtle', 'ALLOWTLEDURINGCALIBRATION']];   // y ou ausente
function confToFields(text) {
  CF_TEXT.forEach(([id, k]) => { $(id).value = confVal(text, k) || ''; });
  CF_YN.forEach(([id, k]) => { $(id).checked = (confVal(text, k) || '').toLowerCase() === 'y'; });
  CF_FLAG.forEach(([id, k]) => { $(id).checked = (confVal(text, k) || '').toLowerCase() === 'y'; });
}
function syncConfFromFields() {
  let c = $('confRaw').value;
  CF_TEXT.forEach(([id, k]) => { c = confUpsert(c, k, $(id).value.trim()); });
  CF_YN.forEach(([id, k]) => { c = confUpsert(c, k, $(id).checked ? 'y' : 'n'); });
  CF_FLAG.forEach(([id, k]) => { c = confUpsert(c, k, $(id).checked ? 'y' : null); });
  $('confRaw').value = c;
}
const hiddenFile = (multiple) => { const i = el('input', { type: 'file' }); if (multiple) i.multiple = true; i.hidden = true; return i; };
function langSelect(value) { const s = el('select', { class: 'small' }); LANG_OPTS.forEach(([id, l]) => s.append(el('option', { value: id }, l))); s.value = value || ''; return s; }
const showNote = (html) => { const n = $('note'); n.style.display = ''; n.innerHTML = html; };

// ---- abas ---------------------------------------------------------------------------------
function setupTabs() {
  $('tabnav').addEventListener('click', (e) => { const b = e.target.closest('.tab'); if (b) showTab(b.dataset.tab); });
}
function showTab(name) {
  document.querySelectorAll('.tab').forEach(t => t.classList.toggle('on', t.dataset.tab === name));
  document.querySelectorAll('.tabpane').forEach(p => { p.hidden = (p.dataset.pane !== name); });
}

// ---- barra de prontidão -------------------------------------------------------------------
const scoreSum = () => SCORE.groups.reduce((s, g) => s + (g.weight || 0), 0);
function readyItems() {
  const hasEnun = !!(enunEd && enunEd.getValue().trim());
  const nEx = $('examples').querySelectorAll('.ex').length;
  const nTs = $('tests').querySelectorAll('.ex').length;
  const nGood = (solEditors.good || []).length;
  const limOK = !!($('cf_memlimit').value.trim() || $('cf_calibrafactor').value.trim());
  const items = [
    { tab: 'enun', label: 'Enunciado', s: hasEnun ? 'ok' : 'todo' },
    { tab: 'tests', label: 'Exemplos', s: nEx ? 'ok' : 'todo' },
    { tab: 'tests', label: 'Testes', s: nTs ? 'ok' : 'todo' },
    { tab: 'sols', label: 'Solução good', s: nGood ? 'ok' : 'todo' },
  ];
  if (SCORE.enabled) items.push({ tab: 'tests', label: 'Pontuação', s: (SCORE.groups.length && scoreSum() > 0) ? 'ok' : 'todo' });
  items.push({ tab: 'limits', label: 'Limites', s: limOK ? 'ok' : 'na' });
  items.push({ tab: 'pub', label: 'Validado', s: VAL.validated });
  items.push({ tab: 'pub', label: 'Calibrado', s: VAL.calibrated });
  items.push({ tab: 'pub', label: 'Público', s: $('ppublic').checked ? 'ok' : 'na' });
  return items;
}
function updateReady() {
  const box = $('ready'); if (!box) return;
  box.innerHTML = '';
  readyItems().forEach(it => box.append(el('span', { class: 'rdy ' + it.s, title: 'ir para a aba', onclick: () => showTab(it.tab) },
    el('span', { class: 'dot' }), el('span', {}, it.label))));
  const nEx = $('examples').querySelectorAll('.ex').length, nTs = $('tests').querySelectorAll('.ex').length;
  $('tabTestsMini').textContent = (nEx + nTs) ? `(${nEx}+${nTs})` : '';
  const ns = SOL_CATS.reduce((a, [c]) => a + (solEditors[c] || []).length, 0);
  $('tabSolsMini').textContent = ns ? `(${ns})` : '';
}

// ---- exemplos (sample, aparecem no enunciado) --------------------------------------------
function exampleRow(input = '', output = '') {
  const row = el('div', { class: 'ex' },
    el('div', { class: 'grid2' },
      el('div', {}, el('label', { class: 'small' }, 'entrada'), el('textarea', { class: 'exin' }, input)),
      el('div', {}, el('label', { class: 'small' }, 'saída'), el('textarea', { class: 'exout' }, output))),
    el('button', { class: 'btn ghost', type: 'button', onclick: () => { row.remove(); updatePkgInfo(); } }, 'remover exemplo'));
  return row;
}
const addExample = (i = '', o = '') => { $('examples').append(exampleRow(i, o)); updatePkgInfo(); };
const collectExamples = () => [...$('examples').querySelectorAll('.ex')].map(r => ({
  input: r.querySelector('.exin').value, output: r.querySelector('.exout').value })).filter(e => e.input !== '' || e.output !== '');

// ---- pontuação por grupos (subtasks) ------------------------------------------------------
const groupKey = (s) => ((s || '').toLowerCase().replace(/[^a-z0-9]+/g, '') || 'g');
const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const globToRe = (g) => new RegExp('^' + g.split('*').map(escapeRe).join('.*') + '$');
const matchGroups = (name) => SCORE.groups.filter(g => g.glob && globToRe(g.glob).test(name));

function addGroupRow(g = { name: '', weight: '', glob: '' }) {
  const nameI = el('input', { type: 'text', value: g.name || '', placeholder: 'ex: facil' });
  const wI = el('input', { type: 'text', value: (g.weight ?? '') + '', placeholder: '0' });
  const globI = el('input', { type: 'text', value: g.glob || '', placeholder: g.name ? groupKey(g.name) + '_*' : 'nome_*' });
  const tr = el('tr', {},
    el('td', {}, nameI), el('td', { class: 'w' }, wI), el('td', {}, globI),
    el('td', { class: 'act' }, el('a', { href: '#', onclick: (e) => { e.preventDefault(); tr.remove(); syncScore(); } }, '✕')));
  const onName = () => { globI.placeholder = (nameI.value.trim() ? groupKey(nameI.value) + '_*' : 'nome_*'); syncScore(); };
  nameI.addEventListener('input', onName); wI.addEventListener('input', syncScore); globI.addEventListener('input', syncScore);
  tr._get = () => ({ name: nameI.value.trim(), weight: parseInt(wI.value, 10) || 0, glob: globI.value.trim() || (nameI.value.trim() ? groupKey(nameI.value) + '_*' : '') });
  $('scoreGroups').append(tr);
  return tr;
}
const collectGroups = () => [...$('scoreGroups').querySelectorAll('tr')].map(tr => tr._get()).filter(g => g.name);
function syncScore() {
  SCORE.enabled = $('scoreEnabled').checked;
  SCORE.groups = collectGroups();
  $('scoreBox').style.display = SCORE.enabled ? '' : 'none';
  const tot = scoreSum();
  const t = $('scoreTotal');
  t.textContent = tot > 0 ? `o problema vale ${tot} ponto(s) no total` : 'defina os pesos dos grupos';
  t.className = 'small gtotal ' + (tot > 0 ? 'ok' : 'no');
  refreshTestGroupSelects(); updateReady(); updatePkgInfo();
}
function refreshTestGroupSelects() {
  const show = $('scoreEnabled').checked;
  [...$('tests').querySelectorAll('.ex')].forEach(row => {
    const gsel = row._gsel; if (!gsel) return;
    const cur = gsel.value || row._wantGroup || ''; row._wantGroup = '';
    gsel.innerHTML = '';
    gsel.append(el('option', { value: '' }, 'auto (pelo padrão)'));
    SCORE.groups.forEach(g => { if (g.name) gsel.append(el('option', { value: g.name }, g.name)); });
    gsel.value = SCORE.groups.some(g => g.name === cur) ? cur : '';
    if (row._gwrap) row._gwrap.style.display = show ? '' : 'none';
    updateTestHint(row);
  });
}
function updateTestHint(row) {
  const ghint = row._ghint, gsel = row._gsel; if (!ghint) return;
  if (!$('scoreEnabled').checked) { ghint.textContent = ''; return; }
  if (gsel.value) { ghint.textContent = '(fixado)'; ghint.style.color = ''; return; }
  const m = matchGroups((row._nameI ? row._nameI.value : '').trim());
  if (m.length === 1) { ghint.textContent = '→ ' + m[0].name; ghint.style.color = '#7ee2a0'; }
  else if (m.length === 0) { ghint.textContent = '⚠ sem grupo'; ghint.style.color = '#ffd98a'; }
  else { ghint.textContent = '⚠ casa ' + m.length + ' grupos'; ghint.style.color = '#ffd98a'; }
}

// ---- testes ocultos -----------------------------------------------------------------------
function testRow(name = '', input = '', output = '', group = '') {
  const nameI = el('input', { type: 'text', value: name, placeholder: 'nome', style: 'max-width:11rem' });
  const inT = el('textarea', { class: 'tin' }, input), outT = el('textarea', { class: 'tout' }, output);
  const li = hiddenFile(false), lo = hiddenFile(false);
  const gsel = el('select', { class: 'tgroup small' });
  const ghint = el('span', { class: 'tghint small muted' });
  const gwrap = el('span', { class: 'tgwrap row', style: 'gap:.3rem;align-items:center;display:none' },
    el('span', { class: 'small muted' }, 'grupo:'), gsel, ghint);
  const row = el('div', { class: 'ex' },
    el('div', { class: 'row', style: 'gap:.5rem;align-items:center;flex-wrap:wrap' },
      el('span', { class: 'small' }, 'teste'), nameI, gwrap,
      el('button', { class: 'btn ghost', type: 'button', onclick: () => { row.remove(); updatePkgInfo(); } }, 'remover')),
    el('div', { class: 'grid2' },
      el('div', {}, el('label', { class: 'small' }, 'entrada ', el('span', { class: 'linklike', style: 'cursor:pointer', onclick: () => li.click() }, '(carregar)')), inT),
      el('div', {}, el('label', { class: 'small' }, 'saída ', el('span', { class: 'linklike', style: 'cursor:pointer', onclick: () => lo.click() }, '(carregar)')), outT)),
    li, lo);
  row._nameI = nameI; row._gsel = gsel; row._ghint = ghint; row._gwrap = gwrap; row._wantGroup = group;
  nameI.addEventListener('change', () => { updatePkgInfo(); updateTestHint(row); });
  nameI.addEventListener('input', () => updateTestHint(row));
  gsel.addEventListener('change', () => { updateTestHint(row); updateReady(); });
  li.addEventListener('change', async () => { if (li.files[0]) { inT.value = await li.files[0].text(); if (!nameI.value) nameI.value = li.files[0].name.replace(/\.[^.]*$/, ''); updatePkgInfo(); } });
  lo.addEventListener('change', async () => { if (lo.files[0]) outT.value = await lo.files[0].text(); });
  return row;
}
const renderTests = (tests) => { $('tests').innerHTML = ''; (tests || []).forEach(t => $('tests').append(testRow(t.name, t.input, t.output, t.group || ''))); refreshTestGroupSelects(); };
const addTest = () => { $('tests').append(testRow()); refreshTestGroupSelects(); updatePkgInfo(); };
const collectTests = () => [...$('tests').querySelectorAll('.ex')].map(r => {
  const o = { name: (r._nameI ? r._nameI.value : '').trim(), input: r.querySelector('.tin').value, output: r.querySelector('.tout').value };
  if ($('scoreEnabled').checked && r._gsel && r._gsel.value) o.group = r._gsel.value;
  return o;
}).filter(t => t.input !== '' || t.output !== '');
async function loadTestPairs(files) {
  const map = {};
  for (const f of files) {
    const base = f.name.replace(/\.(in|out|txt|a|ans|sol)$/i, ''); const isOut = /\.(out|ans|a|sol)$/i.test(f.name);
    map[base] = map[base] || { name: base }; map[base][isOut ? 'output' : 'input'] = await f.text();
  }
  Object.values(map).forEach(t => $('tests').append(testRow(t.name, t.input || '', t.output || '')));
  refreshTestGroupSelects(); updatePkgInfo();
}

// ---- soluções: sub-abas por categoria + arquivos colapsáveis (editor criado sob demanda) --
let solTab = SOL_CATS[0][0];
function showSolCat(cat) {
  solTab = cat;
  document.querySelectorAll('.subtab').forEach(t => t.classList.toggle('on', t.dataset.cat === cat));
  document.querySelectorAll('.solpanel').forEach(p => { p.hidden = (p.dataset.cat !== cat); });
}
function updateSolCounts() {
  SOL_CATS.forEach(([cat]) => { const e = $('solcount-' + cat); if (e) { const n = (solEditors[cat] || []).length; e.textContent = n ? String(n) : ''; } });
}
async function toggleAllSols(cat, open) { for (const e of (solEditors[cat] || [])) await e.setOpen(open); }
async function renderSols(sols) {
  sols = sols || {}; solEditors = Object.fromEntries(SOL_CATS.map(([c]) => [c, []]));
  const wrap = $('solsWrap'); wrap.innerHTML = '';
  const nav = el('div', { class: 'subtabs' });
  SOL_CATS.forEach(([cat]) => {
    const [bcls] = SOL_BADGE[cat] || ['sb-pass', ''];
    nav.append(el('button', { class: 'subtab', type: 'button', 'data-cat': cat, onclick: () => showSolCat(cat) },
      el('span', { class: 'sol-badge ' + bcls }, cat), el('span', { class: 'subcount', id: 'solcount-' + cat })));
  });
  wrap.append(nav);
  for (const [cat] of SOL_CATS) {
    const [, btxt] = SOL_BADGE[cat] || ['', ''];
    const rows = el('div', { id: 'sol-' + cat });
    const fi = hiddenFile(true); fi.addEventListener('change', () => loadSolFiles(cat, fi.files));
    wrap.append(el('div', { class: 'solpanel', 'data-cat': cat, hidden: true },
      el('p', { class: 'small muted', style: 'margin:.2rem 0 .4rem' }, btxt),
      el('div', { class: 'row', style: 'gap:.4rem;flex-wrap:wrap;align-items:center;margin-bottom:.3rem' },
        el('button', { class: 'btn ghost', type: 'button', onclick: () => addSol(cat, DEFNAME[cat], '', true) }, '+ arquivo'),
        el('button', { class: 'btn ghost', type: 'button', onclick: () => fi.click() }, '⬆ enviar'), fi,
        el('span', { style: 'flex:1' }),
        el('button', { class: 'btn ghost', type: 'button', onclick: () => toggleAllSols(cat, true) }, 'abrir todos'),
        el('button', { class: 'btn ghost', type: 'button', onclick: () => toggleAllSols(cat, false) }, 'fechar todos')),
      rows));
    for (const s of (sols[cat] || [])) await addSol(cat, s.filename, s.code, false);
  }
  showSolCat(solTab); updateSolCounts(); updatePkgInfo();
}
async function addSol(cat, fn, code, expand) {
  const fnInput = el('input', { type: 'text', value: fn || DEFNAME[cat], style: 'max-width:14rem' });
  const langSel = langSelect(cmFor(fnInput.value));
  const mount = el('div', { class: 'editor-mount', style: 'display:none' });
  const expandBtn = el('button', { class: 'btn ghost small', type: 'button', title: 'abrir/fechar editor' }, '▸');
  const entry = { code: code || '', ed: null, row: null, fnInput, langSel, mount };
  const ensureEd = async () => { if (!entry.ed) entry.ed = await createEditor(mount, { doc: entry.code, cm: langSel.value || null }); };
  entry.setOpen = async (open) => { if (open) await ensureEd(); mount.style.display = open ? '' : 'none'; expandBtn.textContent = open ? '▾' : '▸'; };
  entry.get = () => ({ filename: fnInput.value.trim(), code: entry.ed ? entry.ed.getValue() : entry.code });
  expandBtn.onclick = () => entry.setOpen(mount.style.display === 'none');
  const remount = async () => { if (!entry.ed) return; const c = entry.ed.getValue(); mount.innerHTML = ''; entry.ed = null; entry.code = c; if (mount.style.display !== 'none') await ensureEd(); };
  langSel.addEventListener('change', remount);
  fnInput.addEventListener('change', () => { langSel.value = cmFor(fnInput.value); remount(); updatePkgInfo(); });
  const row = el('div', { class: 'solrow' },
    el('div', { class: 'row', style: 'gap:.5rem;align-items:center;flex-wrap:wrap' }, expandBtn, el('span', { class: 'small muted' }, 'arquivo'), fnInput, langSel,
      el('button', { class: 'btn ghost', type: 'button', onclick: () => { row.remove(); solEditors[cat] = (solEditors[cat] || []).filter(x => x !== entry); updateSolCounts(); updatePkgInfo(); } }, 'remover')),
    mount);
  entry.row = row;
  $('sol-' + cat).append(row);
  (solEditors[cat] || (solEditors[cat] = [])).push(entry);
  if (expand) await entry.setOpen(true);
  updateSolCounts(); updatePkgInfo();
}
const loadSolFiles = async (cat, files) => { for (const f of files) await addSol(cat, f.name, await f.text(), false); showSolCat(cat); };
function collectSols() { const o = {}; for (const [cat] of SOL_CATS) o[cat] = (solEditors[cat] || []).map(x => x.get()).filter(s => s.filename); return o; }

// ---- árvore do pacote (clicável -> troca de aba e rola até a seção) ------------------------
function flash(t) {
  if (!t) return;
  const pane = t.closest('.tabpane'); if (pane) showTab(pane.dataset.pane);
  const sp = t.closest('.solpanel'); if (sp) showSolCat(sp.dataset.cat);
  t.scrollIntoView({ behavior: 'smooth', block: 'center' }); t.classList.add('flash'); setTimeout(() => t.classList.remove('flash'), 1200);
}
const ul = (...kids) => el('ul', {}, ...kids.filter(Boolean));
const leaf = (label, target, opener) => el('li', {}, el('a', { onclick: () => { if (opener) opener(); flash(target); } }, label));
const dirNode = (label, ...kids) => el('li', {}, el('span', { class: 'dir' }, label), ul(...kids.filter(Boolean)));
function buildTree() {
  const exRows = [...$('examples').querySelectorAll('.ex')], tsRows = [...$('tests').querySelectorAll('.ex')];
  const testKids = [];
  if (exRows.length) testKids.push(dirNode('exemplos/', ...exRows.map((r, i) => leaf('sample' + (i + 1), r))));
  if (tsRows.length) testKids.push(dirNode('ocultos/', ...tsRows.map(r => leaf(((r._nameI ? r._nameI.value : '') || 'teste'), r))));
  if (SCORE.enabled) testKids.push(leaf('score', $('scoreGroups'), () => showTab('tests')));
  const solKids = SOL_CATS.map(([c]) => (solEditors[c] || []).length ? dirNode(c + '/', ...solEditors[c].map(s => leaf(s.get().filename || '(sem nome)', s.row))) : null).filter(Boolean);
  const tree = ul(
    dirNode('docs/', leaf('enunciado.md', $('enunMount'))),
    leaf('conf', $('confRaw'), () => { const d = $('confRaw').closest('details'); if (d) d.open = true; }),
    leaf('author', $('pauthor')), leaf('tags', $('ptags')),
    testKids.length ? dirNode('tests/', ...testKids) : null,
    solKids.length ? dirNode('sols/', ...solKids) : null);
  return el('div', {}, el('div', { class: 'dir' }, ($('prob').value || 'problema') + '/'), tree);
}
function updatePkgInfo() {
  if (!$('pkgInfo')) return;
  const ex = $('examples').querySelectorAll('.ex').length, ts = $('tests').querySelectorAll('.ex').length;
  const sc = SOL_CATS.map(([c]) => `${c}:${(solEditors[c] || []).length}`).join(' · ');
  $('pkgInfo').textContent = `${ex} exemplo(s) · ${ts} teste(s) oculto(s) · soluções ${sc}` + (SCORE.enabled ? ` · pontuação: ${SCORE.groups.length} grupo(s)/${scoreSum()}p` : '');
  if ($('pkgTree')) { $('pkgTree').innerHTML = ''; $('pkgTree').append(buildTree()); }
  updateReady();
}

// ---- montagem / coleta --------------------------------------------------------------------
function fillRepoSelect() {
  const sel = $('repo'); sel.innerHTML = '';
  if (!REPOS.length && !REPO) sel.append(el('option', { value: '' }, '— nenhuma pasta — clique "+ nova pasta"'));
  REPOS.forEach(r => sel.append(el('option', { value: r.repo }, r.repo + (r.mine ? '' : ' (compartilhado)'))));
  if (REPO && !REPOS.some(r => r.repo === REPO)) sel.append(el('option', { value: REPO }, REPO));
  if (REPO) sel.value = REPO; else REPO = REPOS.length ? (sel.value || '') : '';
  // dica: sem nenhuma pasta não dá p/ salvar — é preciso criar uma antes
  const hint = $('repoHint');
  if (hint) {
    if (!REPOS.length && MODE === 'new') {
      hint.style.display = ''; hint.className = 'small';
      hint.innerHTML = 'Você ainda não tem nenhuma <b>pasta</b>. O problema é salvo <b>dentro de uma pasta</b> — clique <b>“+ nova pasta”</b> ali do lado para criar a primeira (ex.: uma por disciplina ou competição). Só depois o botão <b>Salvar</b> funciona.';
    } else hint.style.display = 'none';
  }
}
async function renderForm(d) {
  $('ptitle').value = d.title || ''; $('pauthor').value = d.author || '';
  $('ptags').value = (d.tags || []).join(', '); $('pcolls').value = (d.collections || []).join(', ');
  $('enunMount').innerHTML = '';
  enunEd = await createEditor($('enunMount'), { doc: d.enunciado_md || '', cm: 'markdown', images: true });
  $('examples').innerHTML = ''; (d.examples || []).forEach(e => $('examples').append(exampleRow(e.input, e.output)));
  if (!(d.examples || []).length) $('examples').append(exampleRow());
  // pontuação (antes dos testes, p/ os seletores de grupo já terem opções)
  $('scoreGroups').innerHTML = '';
  const sc = d.score || { enabled: false, groups: [] };
  (sc.groups || []).forEach(g => addGroupRow(g));
  $('scoreEnabled').checked = !!sc.enabled;
  renderTests(d.tests || []);
  await renderSols(d.sols || { good: [{ filename: 'sol.py', code: '' }] });
  $('confRaw').value = d.conf_text || ''; confToFields($('confRaw').value);
  loadedPublic = !!d.public; $('ppublic').checked = loadedPublic;
  FMT = (d.format === 'org' || d.format === 'tex') ? d.format : 'md';
  syncScore();
  renderCollChips(); renderCollManage(); updatePkgInfo();
  if (FMT !== 'md') showNote(`Enunciado em <b>${FMT === 'org' ? 'Org-mode' : 'LaTeX'}</b> — preservado ao salvar; a pré-visualização renderiza nesse formato.`);
}
const collectFields = () => {
  const enabled = $('scoreEnabled').checked;
  return {
    title: $('ptitle').value.trim(), author: $('pauthor').value.trim(),
    tags: splitList($('ptags').value), collections: splitList($('pcolls').value),
    enunciado_md: enunEd ? enunEd.getValue() : '', enunciado_format: FMT, examples: collectExamples(),
    tests: collectTests(), sols: collectSols(), conf_text: $('confRaw').value,
    score: { enabled, groups: enabled ? collectGroups() : [] },
  };
};

async function preview() {
  const btn = $('preview'); btn.disabled = true; setMsg('Renderizando…');
  try {
    const j = await apiPost('/problems/preview', { enunciado_md: enunEd ? enunEd.getValue() : '', enunciado_format: FMT, examples: collectExamples() }, { contest: CONTEST, auth: true });
    $('previewFrame').srcdoc = b64ToUtf8(j.html_b64 || ''); $('previewModal').style.display = ''; setMsg('');
  } catch (e) { setMsg((e instanceof ApiError ? e.message : 'Falha ao renderizar'), 'error'); }
  finally { btn.disabled = false; }
}

// ---- validação & calibração (painel + prontidão, best-effort) -----------------------------
async function loadValidation() {
  if (!ID) { VAL = { validated: 'na', calibrated: 'na' }; renderVal(null, null, null); updateReady(); return; }
  let val = null, info = null, calib = null;
  try { val = await apiGet('/problems/validation?id=' + encodeURIComponent(ID), { contest: CONTEST, auth: true }); } catch {}
  try { info = await apiGet('/problems/get?id=' + encodeURIComponent(ID), { contest: CONTEST, auth: true }); } catch {}
  try { calib = await apiGet('/problems/calib?id=' + encodeURIComponent(ID), { contest: CONTEST, auth: true }); } catch {}
  VAL.validated = (val && Array.isArray(val.checks) && val.checks.length) ? (val.ok ? 'ok' : 'todo') : 'na';
  VAL.calibrated = ((calib && calib.hosts) || []).length ? 'ok' : 'na';
  renderVal(val, info, calib); updateReady();
}
const tlLine = (tl) => Object.entries(tl || {}).filter(([k]) => k !== 'default').map(([k, v]) => `${k}: ${v}s`).join(' · ');
function renderVal(val, info, calib) {
  const box = $('valpanel'); if (!box) return;
  box.innerHTML = '';
  const hosts = (calib && calib.hosts) || [];
  const checks = (val && Array.isArray(val.checks)) ? val.checks : [];
  if (!ID || (!checks.length && !hosts.length)) { box.style.display = 'none'; return; }
  box.style.display = '';
  box.append(el('h3', {}, 'Validação & calibração'));
  // resultado do quality gate (Validar & Publicar)
  if (checks.length) {
    const list = el('ul', { class: 'checks' });
    checks.forEach(c => list.append(el('li', {}, el('span', { class: 'pill ' + (c.ok ? 'ok' : 'no') }, c.ok ? 'ok' : 'falha'), ' ' + (c.name || '') + (c.detail ? (' — ' + c.detail) : ''))));
    box.append(list);
  }
  // por juiz: tempo-limite calibrado + quando + log (como cada solução se comportou)
  if (hosts.length) {
    box.append(el('div', { class: 'small muted', style: 'margin:.5rem 0 .2rem' }, `Calibrado em ${hosts.length} juiz(es) — abra "ver log" para o comportamento de cada solução:`));
    hosts.forEach(h => {
      const det = el('div', { style: 'display:none;margin-top:.3rem' });
      det.append(h.log ? el('pre', { class: 'caliblog' }, h.log) : el('p', { class: 'small muted' }, 'sem log deste juiz ainda.'));
      const toggle = el('a', { href: '#', class: 'small', onclick: (e) => { e.preventDefault(); det.style.display = det.style.display === 'none' ? '' : 'none'; } }, 'ver log');
      const head = el('div', { class: 'row', style: 'gap:.5rem;align-items:center;flex-wrap:wrap' },
        el('b', {}, h.host), el('span', { class: 'small muted' }, tlLine(h.tl) || 'sem TL'),
        h.at ? el('span', { class: 'small muted' }, '· ' + fmtDate(h.at)) : null,
        el('span', { style: 'flex:1' }), toggle);
      box.append(el('div', { class: 'judgecard' }, head, det));
    });
  }
  // tempo-limite efetivamente usado na correção (máx entre juízes)
  const served = info && (info.time_limits || info.tl);
  if (served && Object.keys(served).length) box.append(el('div', { class: 'small', style: 'margin-top:.4rem' }, 'Tempo-limite usado na correção (máx entre juízes): ' + tlLine(served)));
}

// ---- pacote: baixar / enviar tar ----------------------------------------------------------
async function download() {
  if (!ID) { setMsg('Salve o problema antes de baixar.', 'error'); return; }
  try {
    const r = await fetch('/api/v1/problems/download?id=' + encodeURIComponent(ID), { headers: { Authorization: 'Bearer ' + getToken(CONTEST) } });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const blob = await r.blob(), a = document.createElement('a');
    a.href = URL.createObjectURL(blob); a.download = ID.split('#').pop() + '.tar.gz'; a.click(); URL.revokeObjectURL(a.href);
  } catch (e) { setMsg('Falha ao baixar: ' + e.message, 'error'); }
}
async function uploadTar(file) {
  if (!file) return;
  let body;
  if (ID) body = { id: ID };
  else {
    const prob = $('prob').value.trim(); REPO = $('repo').value;
    if (!REPO || !/^[a-z0-9][a-z0-9._-]*$/.test(prob)) { setMsg('Para enviar um .tar novo, escolha o diretório e o nome do problema.', 'error'); return; }
    body = { repo: REPO, prob };
  }
  setMsg('Enviando pacote…');
  try {
    body.tar_b64 = await fileToBase64(file);
    const j = await apiPost('/problems/upload', body, { contest: CONTEST, auth: true });
    ID = j.id; MODE = 'edit'; history.replaceState({}, '', '?id=' + encodeURIComponent(ID));
    $('prob').disabled = true; $('title').textContent = 'Editar: ' + ID;
    await loadSource(ID); setMsg('Pacote enviado e recarregado ✓', 'v-ok');
  } catch (e) { setMsg((e instanceof ApiError ? e.message : 'Falha no upload') + (e.code ? ` (${e.code})` : ''), 'error'); }
}

// ---- compartilhamento ---------------------------------------------------------------------
async function loadShare() {
  const box = $('shareBox'), me = REPOS.find(r => r.repo === REPO), isOwner = me ? me.mine : (OWNER === '');
  box.style.display = isOwner ? '' : 'none';
  if (!isOwner || !REPO) return;
  try { renderShareList((await apiGet('/problems/repo-collaborators?repo=' + encodeURIComponent(REPO), { contest: CONTEST, auth: true })).collaborators || []); }
  catch { $('shareList').textContent = ''; }
}
function renderShareList(list) {
  const box = $('shareList'); box.innerHTML = '';
  if (!list.length) { box.textContent = 'ninguém ainda.'; return; }
  box.append('compartilhado com: ');
  list.forEach(u => box.append(el('span', { class: 'pill mut', style: 'margin-right:.3rem' }, u,
    el('a', { href: '#', style: 'margin-left:.3rem', onclick: async (e) => { e.preventDefault(); await share([], [u]); } }, '×'))));
}
async function share(add, remove) {
  try { const j = await apiPost('/problems/repo-collaborators', { repo: REPO, add, remove }, { contest: CONTEST, auth: true });
    renderShareList(j.collaborators || []); setMsg('compartilhamento atualizado ✓', 'v-ok');
  } catch (e) { setMsg(e.message, 'error'); }
}

// ---- coleções & setters -------------------------------------------------------------------
const currentColls = () => splitList($('pcolls').value);
function setColls(list) { $('pcolls').value = [...new Set(list)].join(', '); renderCollChips(); renderCollManage(); }
async function loadColls() {
  try { COLLS = (await apiGet('/problems/collections', { contest: CONTEST, auth: true })).collections || []; } catch { COLLS = []; }
  renderCollChips(); renderCollManage();
}
function renderCollChips() {
  const box = $('myColls'); if (!box) return; box.innerHTML = '';
  const cur = currentColls();
  const names = [...new Set([...COLLS.filter(c => c.owner).map(c => c.name), ...cur])];
  if (!names.length) { box.append(el('span', { class: 'small muted' }, 'sem coleções ainda — crie uma abaixo.')); return; }
  names.forEach(n => { const on = cur.includes(n);
    box.append(el('span', { class: 'collchip' + (on ? ' on' : ''), onclick: () => { const c = currentColls(); on ? setColls(c.filter(x => x !== n)) : setColls([...c, n]); } }, (on ? '✓ ' : '') + n)); });
}
const collChip = (u, onx) => el('span', { class: 'pill mut', style: 'margin-right:.3rem' }, u,
  el('a', { href: '#', style: 'margin-left:.3rem', onclick: async (e) => { e.preventDefault(); await onx(); } }, '×'));
function renderCollManage() {
  const box = $('collManage'); if (!box) return; box.innerHTML = '';
  currentColls().forEach(n => {
    const c = COLLS.find(x => x.name === n); if (!c || !c.can_manage) return;
    const sList = el('span', { class: 'small' }), aList = el('span', { class: 'small' });
    const sInp = el('input', { type: 'text', placeholder: 'login', style: 'max-width:12rem' });
    const aInp = el('input', { type: 'text', placeholder: 'login', style: 'max-width:12rem' });
    const draw = () => {
      sList.innerHTML = ''; sList.append('setters: '); (c.members || []).forEach(u => sList.append(collChip(u, () => collUpdate(n, { remove: [u] }))));
      aList.innerHTML = ''; aList.append('co-admins: '); (c.admins || []).forEach(u => aList.append(collChip(u, () => collUpdate(n, { admins_remove: [u] }))));
    };
    c._draw = draw; draw();
    box.append(el('div', { style: 'border:1px solid var(--border,#2a2a2a);border-radius:.5rem;padding:.4rem .6rem;margin:.3rem 0' },
      el('div', {}, el('b', {}, '⚙ ' + n), el('span', { class: 'small muted' }, c.mine ? '  (você é dono)' : '  (você é co-admin)')),
      el('div', { class: 'row', style: 'gap:.4rem;align-items:center;margin:.2rem 0;flex-wrap:wrap' }, sInp,
        el('button', { class: 'btn ghost', type: 'button', onclick: () => { const u = sInp.value.trim(); if (u) { collUpdate(n, { add: [u] }); sInp.value = ''; } } }, '+ setter'), sList),
      el('div', { class: 'row', style: 'gap:.4rem;align-items:center;margin:.2rem 0;flex-wrap:wrap' }, aInp,
        el('button', { class: 'btn ghost', type: 'button', onclick: () => { const u = aInp.value.trim(); if (u) { collUpdate(n, { admins_add: [u] }); aInp.value = ''; } } }, '+ co-admin'), aList)));
  });
}
async function collUpdate(name, patch) {
  try {
    const j = await apiPost('/problems/collection-members', { name, ...patch }, { contest: CONTEST, auth: true });
    const c = COLLS.find(x => x.name === name); if (c) { c.members = j.members; c.admins = j.admins; if (c._draw) c._draw(); }
    setMsg('coleção atualizada ✓', 'v-ok');
  } catch (e) { setMsg(e.message, 'error'); }
}
async function newColl() {
  const name = $('newCollName').value.trim();
  if (!/^[a-z0-9][a-z0-9._-]{1,63}$/.test(name)) { setMsg('Nome de coleção inválido (use [a-z0-9._-]).', 'error'); return; }
  const members = splitList($('newCollMembers').value);
  try {
    const j = await apiPost('/problems/collection-create', { name, members }, { contest: CONTEST, auth: true });
    COLLS.push({ name: j.name, owner: j.owner, members: j.members, mine: true, count: 0 });
    setColls([...currentColls(), j.name]); $('newCollName').value = ''; $('newCollMembers').value = '';
    setMsg('Coleção criada ✓ — salve o problema para os setters ganharem acesso.', 'v-ok');
  } catch (e) { setMsg(e.message, 'error'); }
}

// ---- salvar / ações -----------------------------------------------------------------------
async function save() {
  REPO = $('repo').value;
  if (!REPO) {
    showTab('enun'); const fld = $('repo'); if (fld) flash(fld.closest('.field') || fld);
    setMsg(REPOS.length ? 'Escolha um diretório (pasta) no topo da aba Enunciado.'
                        : 'Crie um diretório primeiro: clique “+ nova pasta” (topo da aba Enunciado).', 'error');
    return;
  }
  let f; try { f = collectFields(); }
  catch (e) { setMsg('Erro ao preparar os dados do problema: ' + (e && e.message || e), 'error'); return; }
  $('save').disabled = true; setMsg('Salvando…');
  try {
    if (MODE === 'new') {
      const prob = $('prob').value.trim();
      if (!/^[a-z0-9][a-z0-9._-]*$/.test(prob)) { setMsg('Nome de problema inválido (use [a-z0-9._-]).', 'error'); $('save').disabled = false; return; }
      const j = await apiPost('/problems/create', { repo: REPO, prob, ...f }, { contest: CONTEST, auth: true });
      ID = j.id; MODE = 'edit'; history.replaceState({}, '', '?id=' + encodeURIComponent(ID));
      $('prob').disabled = true; $('title').textContent = 'Editar: ' + ID;
    } else await apiPost('/problems/edit', { id: ID, ...f }, { contest: CONTEST, auth: true });
    if ($('ppublic').checked !== loadedPublic) {
      await apiPost('/problems/set-public', { id: ID, public: $('ppublic').checked }, { contest: CONTEST, auth: true });
      loadedPublic = $('ppublic').checked;
      setMsg('Salvo ✓ ' + (loadedPublic ? '· publicação enfileirada (validação no juiz)' : '· despublicado'), 'v-ok');
    } else setMsg('Salvo ✓', 'v-ok');
  } catch (e) { setMsg((e instanceof ApiError ? e.message : 'Falha ao salvar') + (e.code ? ` (${e.code})` : ''), 'error'); }
  finally { $('save').disabled = false; }
}
async function act(action, label) {
  if (!ID) { setMsg('Salve o problema primeiro.', 'error'); return; }
  setMsg(label + '…');
  try { const j = await apiPost('/problems/' + action, { id: ID }, { contest: CONTEST, auth: true }); setMsg(label + ' enfileirado ✓ (reqid ' + (j.reqid || '').slice(0, 8) + ')', 'v-ok'); }
  catch (e) { setMsg(e.message, 'error'); }
}
async function newDir() {
  const name = prompt('Nome da nova pasta (diretório) — minúsculas, sem espaço:'); if (!name) return;
  try {
    const j = await apiPost('/problems/repo-create', { repo: name.trim() }, { contest: CONTEST, auth: true });
    REPOS.push({ repo: j.repo, owner: j.owner, mine: true, collaborators: [], collections: j.collections || [] });
    REPO = j.repo; fillRepoSelect(); await loadShare(); setMsg('Pasta criada ✓', 'v-ok');
  } catch (e) { setMsg(e.message, 'error'); }
}

async function loadSource(id) {
  const j = await apiGet('/problems/source?id=' + encodeURIComponent(id), { contest: CONTEST, auth: true });
  EDITABLE = j.editable; OWNER = j.owner || ''; REPO = id.split('#')[0];
  $('title').textContent = 'Editar: ' + id;
  $('prob').value = id.split('#').slice(1).join('#'); $('prob').disabled = true;
  fillRepoSelect(); await renderForm(j);
  if (!EDITABLE) {
    showNote('⚠ ' + (j.note || 'Somente leitura.') + ' Os botões de salvar estão desativados (mas dá p/ baixar o pacote).');
    ['save', 'publish', 'calibrate', 'addex', 'addtest', 'uploadTar', 'scoreEnabled', 'addGroup'].forEach(b => { if ($(b)) $(b).disabled = true; });
    $('shareBox').style.display = 'none';
  }
}

// ---- ligação de eventos (SEMPRE antes do carregamento async; uma falha de load nunca
//      desliga os botões — era a causa do "nenhum botão faz nada") ---------------------------
function bindHandlers() {
  $('addex').onclick = () => addExample();
  $('addtest').onclick = addTest;
  $('testpair').addEventListener('change', (e) => loadTestPairs(e.target.files));
  $('save').onclick = save;
  $('publish').onclick = () => act('publish', 'Validar & Publicar');
  $('calibrate').onclick = () => act('request-calibration', 'Calibração');
  $('newdir').onclick = newDir;
  $('preview').onclick = preview;
  $('previewClose').onclick = () => { $('previewModal').style.display = 'none'; $('previewFrame').srcdoc = ''; };
  $('download').onclick = download;
  $('uploadTar').addEventListener('change', (e) => { uploadTar(e.target.files[0]); e.target.value = ''; });
  $('repo').onchange = async () => { REPO = $('repo').value; await loadShare(); };
  $('shareAdd').onclick = async () => { const u = $('shareLogin').value.trim(); if (u) { await share([u], []); $('shareLogin').value = ''; } };
  [...CF_TEXT, ...CF_YN, ...CF_FLAG].forEach(([id]) => $(id).addEventListener('change', () => { syncConfFromFields(); updateReady(); }));
  $('confRaw').addEventListener('change', () => { confToFields($('confRaw').value); updateReady(); });
  $('newCollBtn').onclick = newColl;
  $('pcolls').addEventListener('change', () => { renderCollChips(); renderCollManage(); });
  $('enunMount').addEventListener('input', updateReady);
  $('ppublic').addEventListener('change', updateReady);
  // pontuação por grupos
  $('scoreEnabled').addEventListener('change', () => { if ($('scoreEnabled').checked && !$('scoreGroups').children.length) addGroupRow(); syncScore(); });
  $('addGroup').onclick = () => { addGroupRow(); syncScore(); };
}

async function boot() {
  await renderAuthArea($('authArea'), CONTEST, () => location.reload());
  const st = await status(CONTEST);
  if (!st.logged_in) { $('needauth').style.display = ''; return; }
  $('app').style.display = '';

  bindHandlers();           // 1) liga TUDO antes de qualquer await de dados
  setupTabs();
  updateReady();

  try { REPOS = (await apiGet('/problems/repos', { contest: CONTEST, auth: true })).repos || []; } catch { REPOS = []; }
  try { CAN_CREATE = !!(await apiGet('/treino/contest-create/permission', { contest: CONTEST, auth: true })).can_create; } catch {}

  const p = qs();
  try {
    if (p.get('id')) { MODE = 'edit'; ID = p.get('id'); await loadSource(ID); }
    else {
      MODE = 'new'; REPO = p.get('repo') || ''; fillRepoSelect();
      await renderForm({ enunciado_md: '', author: st.name || st.login || '', tags: [], collections: [],
        examples: [], tests: [], sols: { good: [{ filename: 'sol.py', code: '' }] }, public: false,
        score: { enabled: false, groups: [] },
        conf_text: 'TLMOD[calibrafactor]=1.35\nULIMITS[-u]=10000\nALLOWPARALLELTEST=y\n' });
    }
    await loadShare();
    await loadColls();
  } catch (e) {
    setMsg('Falha ao carregar o problema: ' + (e instanceof ApiError ? e.message : (e && e.message || e)), 'error');
  }

  // criar pasta/coleção e criar problema novo: só p/ quem pode criar (regra de criar contest)
  if (!CAN_CREATE) ['newdir', 'newCollBtn'].forEach(b => { if ($(b)) $(b).disabled = true; });
  if (MODE === 'new' && !CAN_CREATE) {
    showNote('⚠ Você não tem permissão para criar problemas. Peça a um administrador — é a mesma permissão de criar contests.');
    if ($('save')) $('save').disabled = true;
  } else if (!EDITABLE) { if ($('newCollBtn')) $('newCollBtn').disabled = true; }

  updateReady();
  loadValidation();         // best-effort: painel de validação/calibração + prontidão
}
boot();
