// problemas/editar.js — editor de problemas (autoria keyless; git escondido).
// Layout em ABAS (Enunciado · Testes & Pontuação · Soluções · Limites · Publicação) com uma
// barra de PRONTIDÃO fixa (o que já está pronto e o que falta). Suporta limite de memória (MEMLIMITMB) e
// PONTUAÇÃO POR GRUPOS (subtasks estilo OBI: cada grupo de testes tem um peso → tests/score).
import { apiGet, apiPost, ApiError, getToken } from '/shared/api.js';
import { status, fileToBase64, textToBase64 } from '/shared/auth.js';
import { el, renderAuthArea, fmtDate } from '/shared/ui.js';
import { createEditor } from '/shared/editor.js';

const CONTEST = 'treino';
let MODE = 'new', ID = '', REPO = '', OWNER = '', EDITABLE = true, REPOS = [], loadedPublic = false;
let enunEd = null, editEd = null;                            // enunciado (modo single) + resolução/editorial
let descEd = null, entEd = null, saiEd = null, obsEd = null;  // editores modulares (lazy, modo "separado")
let stmtMode = 'single';                                      // 'single' | 'modular'
let PENDING_EDITORIAL = '';                                  // editorial carregado, aplicado quando a aba Resolução abre
let scrEntries = [];   // scripts/ (correção especial) — EDITÁVEL na sub-aba "⚙ correção" (Soluções & Correção) via `scripts_files` (round-trip completo: conteúdo/exec/symlink; binário preservado)
let SCR_TEMPLATES = null;   // cache de GET /problems/script-templates (carrega 1x)
let COLLS = [];
let collFilter = { q: '', mine: false, manage: false, course: false };  // filtro dos chips de coleção
let CAN_CREATE = false;
let FMT = 'md';                       // formato do enunciado (md|org|tex) — preservado no save
let SCORE = { enabled: false, groups: [] };   // pontuação por grupos (espelho do DOM)
let VAL = { validated: 'na', calibrated: 'na' };   // estado p/ a barra de prontidão
let LASTVAL = null, LASTINFO = null, LASTCALIB = null;   // últimos dados de validação/calibração
let RUNNING = '';                                        // '', 'calibrate' ou 'publish' — em execução no juiz
let calibTimer = null, calibPrevMax = 0;                 // polling do resultado (atualiza sozinho)
let JUDGES = [];                                          // juízes do registro (calibração direcionada)
const OPEN_LOGS = new Set();                              // hosts com "ver log" aberto (sobrevive ao re-render do polling)
let LAST_RENDER_SIG = '';                                 // assinatura do painel: só reconstrói quando MUDA (não a cada poll)
const CALIB_SCROLL = {};                                  // scrollTop do log de cada juiz, p/ restaurar no re-render

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
const CF_TEXT = [['cf_memlimit', 'MEMLIMITMB'], ['cf_stack', 'STACKLIMITMB'], ['cf_calibrafactor', 'TLMOD[calibrafactor]'], ['cf_calibrationtl', 'CALIBRATIONTL'], ['cf_ulimit_u', 'ULIMITS[-u]'], ['cf_ulimit_f', 'ULIMITS[-f]'], ['cf_maxparallel', 'MAXPARALLELTESTS']];
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
  if (name === 'resol') ensureEditorial();   // editor da resolução é carregado ao abrir a aba
}

// ---- enunciado: um editor só (padrão) ou seções separadas (opt-in) ------------------------
// Template de problema NOVO: já vem com as seções esperadas pelo portão de validação.
const STMT_TEMPLATE = '(descreva o problema)\n\n## Entrada\n\n(descreva a entrada)\n\n## Saída\n\n(descreva a saída)\n\n## Observações\n\n(restrições e limites)\n';
const noAccent = (s) => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '');
// divide um enunciado em {descrição, entrada, saída, observações} por cabeçalhos `## ` reconhecidos
function splitStatement(md) {
  md = String(md || '').replace(/^\s*%[^\n]*\n?/, '');     // remove "% Título" legado
  const sec = { descricao: [], entrada: [], saida: [], observacoes: [] };
  let cur = 'descricao';
  for (const line of md.split('\n')) {
    const m = line.match(/^#{1,3}\s+(.+?)\s*$/);
    if (m) {
      const t = noAccent(m[1]).toLowerCase();
      let k = null;
      if (/^(entrada|input)\b/.test(t)) k = 'entrada';
      else if (/^(saida|output)\b/.test(t)) k = 'saida';
      else if (/^(observ|notas|restri|note|constraint)/.test(t)) k = 'observacoes';
      if (k) { cur = k; continue; }    // cabeçalho reconhecido troca de seção (descarta a linha do '##')
    }
    sec[cur].push(line);               // '##' não reconhecido fica onde está (nada se perde)
  }
  const j = (a) => a.join('\n').replace(/^\n+|\n+$/g, '');
  return { descricao: j(sec.descricao), entrada: j(sec.entrada), saida: j(sec.saida), observacoes: j(sec.observacoes) };
}
// recombina os 4 campos num enunciado canônico (omite seções vazias; SEM `% Título`)
function combineStatement(s) {
  const p = [];
  if ((s.descricao || '').trim()) p.push(s.descricao.trim());
  if ((s.entrada || '').trim()) p.push('## Entrada\n\n' + s.entrada.trim());
  if ((s.saida || '').trim()) p.push('## Saída\n\n' + s.saida.trim());
  if ((s.observacoes || '').trim()) p.push('## Observações\n\n' + s.observacoes.trim());
  return p.length ? p.join('\n\n') + '\n' : '';
}
// enunciado atual conforme o modo — fonte única p/ save, preview e prontidão
const currentStatement = () => stmtMode === 'modular'
  ? combineStatement({ descricao: descEd ? descEd.getValue() : '', entrada: entEd ? entEd.getValue() : '',
                       saida: saiEd ? saiEd.getValue() : '', observacoes: obsEd ? obsEd.getValue() : '' })
  : (enunEd ? enunEd.getValue() : '');
async function ensureModularEditors() {
  if (!descEd) descEd = await createEditor($('descMount'), { doc: '', cm: 'markdown', images: true });
  if (!entEd) entEd = await createEditor($('entMount'), { doc: '', cm: 'markdown' });
  if (!saiEd) saiEd = await createEditor($('saiMount'), { doc: '', cm: 'markdown' });
  if (!obsEd) obsEd = await createEditor($('obsMount'), { doc: '', cm: 'markdown' });
  ['descMount', 'entMount', 'saiMount', 'obsMount'].forEach(id => $(id).addEventListener('input', updateReady));
}
async function toggleStmtMode() {
  const btn = $('stmtToggle');
  if (stmtMode === 'single') {
    await ensureModularEditors();
    const s = splitStatement(enunEd ? enunEd.getValue() : '');
    descEd.setValue(s.descricao); entEd.setValue(s.entrada); saiEd.setValue(s.saida); obsEd.setValue(s.observacoes);
    $('enunMount').style.display = 'none'; $('enunModular').style.display = '';
    stmtMode = 'modular'; if (btn) btn.textContent = '⊟ Juntar num só';
  } else {
    if (enunEd) enunEd.setValue(currentStatement());   // ainda modo modular -> combina os 4
    $('enunModular').style.display = 'none'; $('enunMount').style.display = '';
    stmtMode = 'single'; if (btn) btn.textContent = '✂ Separar em seções';
  }
  updateReady();
}
async function ensureEditorial() {
  if (!editEd) editEd = await createEditor($('editMount'), { doc: PENDING_EDITORIAL || '', cm: 'markdown', images: true });
}

// ---- barra de prontidão -------------------------------------------------------------------
const scoreSum = () => SCORE.groups.reduce((s, g) => s + (g.weight || 0), 0);
function readyItems() {
  const hasEnun = !!currentStatement().trim();
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
  items.push({ tab: 'pub', label: 'Público', s: loadedPublic ? 'ok' : 'na' });
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
function exampleRow(input = '', output = '', explanation = '') {
  const row = el('div', { class: 'ex' },
    el('div', { class: 'grid2' },
      el('div', {}, el('label', { class: 'small' }, 'entrada'), el('textarea', { class: 'exin' }, input)),
      el('div', {}, el('label', { class: 'small' }, 'saída'), el('textarea', { class: 'exout' }, output))),
    el('div', {}, el('label', { class: 'small' }, 'explicação (opcional, Markdown — aparece logo após o exemplo no enunciado)'),
      el('textarea', { class: 'exexpl', oninput: updateReady }, explanation)),
    el('button', { class: 'btn ghost', type: 'button', onclick: () => { row.remove(); updatePkgInfo(); } }, 'remover exemplo'));
  return row;
}
const addExample = (i = '', o = '', x = '') => { $('examples').append(exampleRow(i, o, x)); updatePkgInfo(); };
const collectExamples = () => [...$('examples').querySelectorAll('.ex')].map(r => ({
  input: r.querySelector('.exin').value, output: r.querySelector('.exout').value,
  explanation: r.querySelector('.exexpl') ? r.querySelector('.exexpl').value : '' })).filter(e => e.input !== '' || e.output !== '');

// ---- pontuação por grupos (subtasks) ------------------------------------------------------
const groupKey = (s) => ((s || '').toLowerCase().replace(/[^a-z0-9]+/g, '') || 'g');
const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const globToRe = (g) => new RegExp('^' + g.split('*').map(escapeRe).join('.*') + '$');
// um grupo pode ter VÁRIOS globs separados por vírgula (ex.: "a_*, b_*"); casa se QUALQUER um bate
const splitGlobs = (g) => (g || '').split(',').map(s => s.trim()).filter(Boolean);
const matchGroups = (name) => SCORE.groups.filter(g => splitGlobs(g.glob).some(gl => globToRe(gl).test(name)));

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
  const s = $('solcount-scr'); if (s) s.textContent = scrEntries.length ? String(scrEntries.length) : '';
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
  // sub-aba do MODO DE CORREÇÃO (correção especial, scripts/): mesmo mecanismo das categorias —
  // o painel (#scrPanel, data-cat="scr") vive FORA do wrap p/ sobreviver ao re-render
  nav.append(el('span', { class: 'subsep' }, '·'),
    el('button', { class: 'subtab', type: 'button', 'data-cat': 'scr', title: 'modo de correção: checker, comparador, interativo… (scripts/ do pacote)', onclick: () => showSolCat('scr') },
      el('span', { class: 'sol-badge sb-scr' }, '⚙ correção'), el('span', { class: 'subcount', id: 'solcount-scr' })));
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

// ---- correção especial (scripts/) — lista editável + templates ------------------------------
// Cada entrada espelha um item de `scripts_files`: {path,content_b64,exec} ou {path,symlink}.
// Texto ganha editor CodeMirror (lazy); binário (b64 que não é UTF-8) fica preservado sem editor.
const b64ToUtf8Strict = (b) => { try { return new TextDecoder('utf-8', { fatal: true }).decode(Uint8Array.from(atob(b || ''), c => c.charCodeAt(0))); } catch { return null; } };
function addScript(f, expand) {
  const isLink = !!f.symlink;
  const text = isLink ? null : b64ToUtf8Strict(f.content_b64 || '');
  const isBin = !isLink && text === null;
  const pathInput = el('input', { type: 'text', value: f.path || '', placeholder: 'ex: compare.sh · c/compile.sh', style: 'max-width:16rem' });
  const entry = { pathInput, symlink: f.symlink || null, b64: f.content_b64 || '', code: text || '', isBin, ed: null };
  let row;
  if (isLink) {
    row = el('div', { class: 'solrow' }, el('div', { class: 'row', style: 'gap:.5rem;align-items:center;flex-wrap:wrap' },
      el('span', { class: 'small muted' }, '🔗'), pathInput, el('span', { class: 'small muted' }, '→ ' + f.symlink),
      el('button', { class: 'btn ghost', type: 'button', onclick: () => { row.remove(); scrEntries = scrEntries.filter(x => x !== entry); updateSolCounts(); updatePkgInfo(); } }, 'remover')));
  } else {
    const execCb = el('input', { type: 'checkbox' }); execCb.checked = !!f.exec;
    entry.execCb = execCb;
    const mount = el('div', { class: 'editor-mount', style: 'display:none' });
    const expandBtn = el('button', { class: 'btn ghost small', type: 'button', title: 'abrir/fechar editor' }, '▸');
    const ensureEd = async () => { if (!entry.ed) entry.ed = await createEditor(mount, { doc: entry.code, cm: cmFor(pathInput.value) || 'shell' }); };
    entry.setOpen = async (open) => { if (open) await ensureEd(); mount.style.display = open ? '' : 'none'; expandBtn.textContent = open ? '▾' : '▸'; };
    expandBtn.onclick = () => entry.setOpen(mount.style.display === 'none');
    if (isBin) { expandBtn.disabled = true; expandBtn.title = 'binário — preservado como está'; }
    row = el('div', { class: 'solrow' }, el('div', { class: 'row', style: 'gap:.5rem;align-items:center;flex-wrap:wrap' },
      expandBtn, el('span', { class: 'small muted' }, 'arquivo'), pathInput,
      isBin ? el('span', { class: 'small muted' }, `(binário, ${Math.round((entry.b64.length * 3) / 4)} bytes)`) : '',
      el('label', { class: 'row small', style: 'gap:.3rem' }, execCb, 'executável'),
      el('button', { class: 'btn ghost', type: 'button', onclick: () => { row.remove(); scrEntries = scrEntries.filter(x => x !== entry); updateSolCounts(); updatePkgInfo(); } }, 'remover')),
      mount);
    if (expand) entry.setOpen(true);
  }
  entry.row = row;
  entry.get = () => {
    const p = pathInput.value.trim(); if (!p) return null;
    if (entry.symlink) return { path: p, symlink: entry.symlink };
    if (entry.isBin) return { path: p, content_b64: entry.b64, exec: entry.execCb.checked };
    return { path: p, content_b64: textToBase64(entry.ed ? entry.ed.getValue() : entry.code), exec: entry.execCb.checked };
  };
  pathInput.addEventListener('change', updatePkgInfo);
  $('scrRows').append(row);
  scrEntries.push(entry);
  updateSolCounts(); updatePkgInfo();
}
function renderScripts(files) { scrEntries = []; $('scrRows').innerHTML = ''; (files || []).forEach(f => addScript(f, false)); updateSolCounts(); }
const collectScripts = () => scrEntries.map(e => e.get()).filter(Boolean);
async function loadScriptTemplates() {
  if (SCR_TEMPLATES) return SCR_TEMPLATES;
  try {
    const j = await apiGet('/problems/script-templates', { contest: CONTEST, auth: true });
    SCR_TEMPLATES = j.templates || [];
  } catch { SCR_TEMPLATES = []; }
  const sel = $('scrTplSel');
  SCR_TEMPLATES.forEach(t => sel.append(el('option', { value: t.key }, t.name)));
  return SCR_TEMPLATES;
}
async function applyScriptTemplate() {
  const key = $('scrTplSel').value; if (!key) return;
  const t = (SCR_TEMPLATES || []).find(x => x.key === key); if (!t) return;
  if (scrEntries.length && !confirm(`Aplicar o template "${t.name}" SUBSTITUI os ${scrEntries.length} arquivo(s) atuais de scripts/. Continuar?`)) return;
  renderScripts(t.files || []);
  const hint = $('scrTplHint');
  hint.style.display = '';
  hint.textContent = (t.description ? t.description + ' ' : '') + (t.conf_hints ? '💡 ' + t.conf_hints : '');
  setMsg('Template aplicado — revise os arquivos (o exemplo é um ponto de partida) e salve.', '');
}

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
  // scripts/ (correção especial) — editável na sub-aba ⚙ de Soluções & Correção; agrupa por subpasta
  let scrNode = null;
  const scrItems = scrEntries.map(e => ({ p: e.pathInput.value.trim(), row: e.row })).filter(x => x.p);
  if (scrItems.length) {
    const byDir = {}, rootFiles = [];
    for (const it of scrItems) {
      const i = it.p.indexOf('/');
      if (i < 0) rootFiles.push({ ...it, label: it.p });
      else (byDir[it.p.slice(0, i)] || (byDir[it.p.slice(0, i)] = [])).push({ ...it, label: it.p.slice(i + 1) });
    }
    const scrKids = [
      ...Object.keys(byDir).sort().map(dir => dirNode(dir + '/', ...byDir[dir].map(it => leaf(it.label, it.row)))),
      ...rootFiles.map(it => leaf(it.label, it.row)),
    ];
    scrNode = dirNode('scripts/', ...scrKids);
  }
  const docsKids = [leaf('enunciado.md', stmtMode === 'modular' ? $('descMount') : $('enunMount'))];
  if (exRows.some(r => r.querySelector('.exexpl') && r.querySelector('.exexpl').value.trim())) docsKids.push(leaf('sample-notes.json', $('examples'), () => showTab('tests')));
  if (editEd ? editEd.getValue().trim() : (PENDING_EDITORIAL || '').trim()) docsKids.push(leaf('solucao.md', $('editMount'), () => showTab('resol')));
  const tree = ul(
    dirNode('docs/', ...docsKids),
    leaf('conf', $('confRaw'), () => { const d = $('confRaw').closest('details'); if (d) d.open = true; }),
    leaf('author', $('pauthor')), leaf('tags', $('ptags')),
    testKids.length ? dirNode('tests/', ...testKids) : null,
    solKids.length ? dirNode('sols/', ...solKids) : null,
    scrNode);
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
const selectedOrg = () => REPOS.find(r => r.repo === REPO) || null;
const orgIsPrivate = () => { const o = selectedOrg(); return !!(o && o.public_allowed === false); };
// dica sob o seletor de org: sem nenhuma org não dá p/ salvar; org privada não deixa publicar
function updateRepoHint() {
  const hint = $('repoHint'); if (!hint) return;
  if (!REPOS.length && MODE === 'new') {
    hint.style.display = ''; hint.className = 'small'; hint.style.color = '#ffd98a';
    hint.innerHTML = 'Você ainda não tem nenhuma <b>org</b>. O problema é salvo <b>dentro de uma org</b> — clique <b>“+ nova org”</b> ali do lado para criar a primeira (ex.: uma por disciplina ou competição). Só depois o botão <b>Salvar</b> funciona.';
  } else if (orgIsPrivate()) {
    hint.style.display = ''; hint.className = 'small'; hint.style.color = '#ffd98a';
    hint.innerHTML = '🔒 A org <b>' + REPO + '</b> é <b>privada</b> — problemas nela não podem ficar públicos (anti-vazamento de prova). Um admin da org libera em Gestão de Problemas › Orgs.';
  } else hint.style.display = 'none';
}
function fillRepoSelect() {
  const sel = $('repo'); sel.innerHTML = '';
  if (!REPOS.length && !REPO) sel.append(el('option', { value: '' }, '— nenhuma org — clique "+ nova org"'));
  REPOS.forEach(r => sel.append(el('option', { value: r.repo }, r.repo + (r.mine ? '' : ' (compartilhado)'))));
  if (REPO && !REPOS.some(r => r.repo === REPO)) sel.append(el('option', { value: REPO }, REPO));
  if (REPO) sel.value = REPO; else REPO = REPOS.length ? (sel.value || '') : '';
  // a org é o prefixo do id: imutável na edição (selo fixo). Só no modo "novo" dá p/ escolher/criar.
  const editing = MODE === 'edit';
  sel.disabled = editing;
  if ($('newdir')) $('newdir').style.display = editing ? 'none' : '';
  updateRepoHint();
}
async function renderForm(d) {
  $('ptitle').value = d.title || ''; $('pauthor').value = d.author || '';
  $('ptags').value = (d.tags || []).join(', '); $('pcolls').value = (d.collections || []).join(', ');
  // enunciado: volta sempre p/ o modo "um editor só"; problema NOVO já vem com o template de seções
  stmtMode = 'single';
  $('enunMount').style.display = ''; $('enunModular').style.display = 'none';
  if ($('stmtToggle')) $('stmtToggle').textContent = '✂ Separar em seções';
  ['descMount', 'entMount', 'saiMount', 'obsMount'].forEach(id => { $(id).innerHTML = ''; });
  descEd = entEd = saiEd = obsEd = null;
  const initMd = (d.enunciado_md && d.enunciado_md.trim()) ? d.enunciado_md : (MODE === 'new' ? STMT_TEMPLATE : '');
  $('enunMount').innerHTML = '';
  enunEd = await createEditor($('enunMount'), { doc: initMd, cm: 'markdown', images: true });
  // resolução (editorial): guarda; o editor é criado ao abrir a aba (e atualizado se já existir)
  PENDING_EDITORIAL = d.editorial_md || '';
  renderScripts(d.scripts_files || []);
  $('editMount').innerHTML = ''; editEd = null;
  $('examples').innerHTML = ''; (d.examples || []).forEach(e => $('examples').append(exampleRow(e.input, e.output, e.explanation)));
  if (!(d.examples || []).length) $('examples').append(exampleRow());
  // pontuação (antes dos testes, p/ os seletores de grupo já terem opções)
  $('scoreGroups').innerHTML = '';
  const sc = d.score || { enabled: false, groups: [] };
  (sc.groups || []).forEach(g => addGroupRow(g));
  $('scoreEnabled').checked = !!sc.enabled;
  renderTests(d.tests || []);
  await renderSols(d.sols || { good: [{ filename: 'sol.py', code: '' }] });
  $('confRaw').value = d.conf_text || ''; confToFields($('confRaw').value);
  loadedPublic = !!d.public; renderPubState();
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
    enunciado_md: currentStatement(), enunciado_format: FMT, examples: collectExamples(),
    editorial_md: editEd ? editEd.getValue() : PENDING_EDITORIAL,
    tests: collectTests(), sols: collectSols(), conf_text: $('confRaw').value,
    score: { enabled, groups: enabled ? collectGroups() : [] },
    scripts_files: collectScripts(),   // correção especial — substitui scripts/ inteiro (round-trip)
  };
};

async function preview() {
  const btn = $('preview'); btn.disabled = true; setMsg('Renderizando…');
  try {
    const j = await apiPost('/problems/preview', { enunciado_md: currentStatement(), enunciado_format: FMT, examples: collectExamples(), title: $('ptitle').value.trim() }, { contest: CONTEST, auth: true });
    const html = b64ToUtf8(j.html_b64 || ''); const pb = $('previewBody');   // .statement-content (CSS unificado), não iframe
    try { const d = new DOMParser().parseFromString(html, 'text/html'); pb.innerHTML = d.body ? d.body.innerHTML : html; } catch { pb.innerHTML = html; }
    $('previewModal').style.display = ''; setMsg('');
  } catch (e) { setMsg((e instanceof ApiError ? e.message : 'Falha ao renderizar'), 'error'); }
  finally { btn.disabled = false; }
}

// ---- validação & calibração (painel + prontidão, best-effort) -----------------------------
async function loadValidation() {
  if (!ID) { VAL = { validated: 'na', calibrated: 'na' }; LASTVAL = LASTINFO = LASTCALIB = null; renderVal(); updateReady(); return; }
  const g = (pfx) => apiGet(pfx + encodeURIComponent(ID), { contest: CONTEST, auth: true }).catch(() => null);
  const [val, info, calib] = await Promise.all([     // 3 GETs em paralelo (antes era sequencial)
    g('/problems/validation?id='), g('/problems/get?id='), g('/problems/calib?id='),
  ]);
  LASTVAL = val; LASTINFO = info; LASTCALIB = calib;
  const nHosts = ((calib && calib.hosts) || []).length;
  VAL.validated = (RUNNING === 'publish') ? 'run' : ((val && Array.isArray(val.checks) && val.checks.length) ? (val.ok ? 'ok' : 'todo') : 'na');
  VAL.calibrated = RUNNING ? 'run' : (nHosts ? 'ok' : 'na');
  maybeRenderVal(); updateReady();   // só reconstrói o painel se algo mudou (não a cada poll)
}
// dispara Calibrar/Validar e fica buscando o resultado sozinho (a calibração roda no juiz).
// "pronto" = algum juiz reportou DEPOIS do disparo (independe do relógio do cliente).
const maxCalibAt = () => Math.max(0, ...(((LASTCALIB && LASTCALIB.hosts) || []).map(h => h.at || 0)));
function startPolling() {
  if (calibTimer) { clearInterval(calibTimer); calibTimer = null; }
  let tries = 0;
  calibTimer = setInterval(async () => {
    tries++;
    await loadValidation();   // atualiza o painel ao vivo
    const fresh = maxCalibAt() > calibPrevMax;
    const validated = RUNNING === 'publish' && LASTVAL && Array.isArray(LASTVAL.checks) && LASTVAL.checks.length;
    if (RUNNING && (fresh || validated)) { RUNNING = ''; updateReady(); renderVal(); setMsg('Resultado chegou ✓', 'v-ok'); }
    if (tries >= 20) {        // ~80s: para de buscar (segue refrescando até lá p/ pegar todos os juízes)
      clearInterval(calibTimer); calibTimer = null;
      if (RUNNING) { RUNNING = ''; await loadValidation(); setMsg('Ainda processando — recarregue se faltar algum juiz.', ''); }
    }
  }, 4000);
}
const tlLine = (tl) => Object.entries(tl || {}).filter(([k]) => k !== 'default').map(([k, v]) => `${k}: ${v}s`).join(' · ');
// abre o report.html (rico) de uma solução, gerado na calibração daquele juiz, numa nova aba
async function openCalibReport(host, name) {
  try {
    const r = await fetch('/api/v1/problems/calib-report?id=' + encodeURIComponent(ID) + '&host=' + encodeURIComponent(host) + '&name=' + encodeURIComponent(name),
      { headers: { Authorization: 'Bearer ' + getToken(CONTEST) } });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const url = URL.createObjectURL(new Blob([await r.text()], { type: 'text/html' }));
    window.open(url, '_blank'); setTimeout(() => URL.revokeObjectURL(url), 60000);
  } catch (e) { setMsg('Falha ao abrir o report: ' + e.message, 'error'); }
}
// nome amigável das linguagens (as chaves de TL são códigos curtos do juiz: c, cpp, py, …)
const TL_LANG_NAME = { c: 'C', cpp: 'C++', cc: 'C++', cxx: 'C++', py: 'Python', python: 'Python',
  py3: 'Python 3 (legado)', py2: 'Python 2 (legado)',
  java: 'Java', pas: 'Pascal', pascal: 'Pascal', hs: 'Haskell', go: 'Go', rs: 'Rust', js: 'JavaScript',
  cs: 'C#', ml: 'OCaml', sh: 'Shell', bash: 'Shell', apl: 'APL', pl: 'Prolog', prolog: 'Prolog',
  asm: 'Assembly', gas: 'Assembly', default: 'default (demais)' };
const tlLangName = (k) => TL_LANG_NAME[k] || k;
const tlSecs = (v) => { if (v == null || v === '') return '—'; const n = +v; return (Number.isFinite(n) ? +n.toFixed(4) : v) + 's'; };
// quadro-resumo: tempo-limite por linguagem em cada juiz; o "servido" (o que o aluno vê) em negrito
function tlSummaryTable(hosts, served) {
  const langs = [...new Set([...Object.keys(served || {}), ...hosts.flatMap(h => Object.keys(h.tl || {}))])];
  if (!langs.length) return null;
  langs.sort((a, b) => (a === 'default') - (b === 'default') || a.localeCompare(b));   // 'default' por último
  const cpuOf = {}; JUDGES.forEach(j => { cpuOf[j.host] = j.cpu; });
  const servedOf = (lang) => {
    if (served && served[lang] != null) return served[lang];
    const vals = hosts.map(h => +((h.tl || {})[lang])).filter(Number.isFinite);
    return vals.length ? Math.max(...vals) : null;   // ainda não indexado: usa o máx entre juízes
  };
  const thead = el('tr', {}, el('th', {}, 'linguagem'), el('th', { class: 'served' }, 'servido (aluno)'),
    ...hosts.map(h => el('th', {}, h.host, cpuOf[h.host] ? el('div', { class: 'cpu' }, cpuOf[h.host]) : null)));
  const body = langs.map(lang => el('tr', {},
    el('td', {}, tlLangName(lang)),
    el('td', { class: 'served' }, el('b', {}, tlSecs(servedOf(lang)))),
    ...hosts.map(h => el('td', {}, tlSecs((h.tl || {})[lang])))));
  return el('div', { class: 'tlsummary-wrap' },
    el('div', { class: 'small muted', style: 'margin:.3rem 0 .2rem' }, 'Resumo por linguagem — em negrito o tempo-limite que o estudante vê no enunciado:'),
    el('table', { class: 'tlsummary' }, el('thead', {}, thead), el('tbody', {}, ...body)));
}
// assinatura do que o painel mostra: só reconstrói quando MUDA — senão o polling (a cada 4s)
// destruía o DOM e o scroll do log "voltava pro topo" / o botão de fechar brigava com o re-render.
function valRenderSig() {
  const hosts = (LASTCALIB && LASTCALIB.hosts) || [];
  const checks = (LASTVAL && LASTVAL.checks) || [];
  const served = (LASTINFO && (LASTINFO.time_limits || LASTINFO.tl)) || {};
  return JSON.stringify({
    run: RUNNING,
    checks: checks.map(c => `${c.name}:${c.ok}:${c.detail || ''}`),
    hosts: hosts.map(h => `${h.host}|${h.at}|${(h.log || '').length}|${(h.reports || []).length}|${tlLine(h.tl)}`),
    served: Object.entries(served).map(([k, v]) => `${k}=${v}`),
  });
}
function maybeRenderVal() { if (valRenderSig() !== LAST_RENDER_SIG) renderVal(); }   // re-render só quando algo muda
function renderVal() {
  const box = $('valpanel'); if (!box) return;
  box.querySelectorAll('.caliblog').forEach(p => { CALIB_SCROLL[p.dataset.host] = p.scrollTop; });   // preserva o scroll do log
  box.innerHTML = '';
  const val = LASTVAL, info = LASTINFO, calib = LASTCALIB;
  const hosts = (calib && calib.hosts) || [];
  const served = (info && (info.time_limits || info.tl)) || {};   // o que o aluno vê (json servido)
  const checks = (val && Array.isArray(val.checks)) ? val.checks : [];
  if (!ID || (!checks.length && !hosts.length && !RUNNING)) { box.style.display = 'none'; return; }
  box.style.display = '';
  box.append(el('h3', {}, 'Validação & calibração'));
  if (RUNNING) box.append(el('div', { class: 'running' }, el('span', { class: 'spin' }),
    el('span', {}, (RUNNING === 'publish' ? 'Validando e calibrando no juiz…' : 'Calibrando no juiz…') + ' a página atualiza sozinha quando terminar.')));
  // resultado do quality gate (botão Validar)
  if (checks.length) {
    const list = el('ul', { class: 'checks' });
    checks.forEach(c => list.append(el('li', {}, el('span', { class: 'pill ' + (c.ok ? 'ok' : 'no') }, c.ok ? 'ok' : 'falha'), ' ' + (c.name || '') + (c.detail ? (' — ' + c.detail) : ''))));
    box.append(list);
  }
  // por juiz: tempo-limite calibrado + quando + log (como cada solução se comportou)
  if (hosts.length) {
    const sum = tlSummaryTable(hosts, served);   // quadro-resumo por linguagem (antes dos cards de cada juiz)
    if (sum) box.append(sum);
    box.append(el('div', { class: 'small muted', style: 'margin:.5rem 0 .2rem' }, `Calibrado em ${hosts.length} juiz(es) — abra "ver log" para o comportamento de cada solução:`));
    hosts.forEach(h => {
      const isOpen = OPEN_LOGS.has(h.host);
      const det = el('div', { style: 'margin-top:.3rem;display:' + (isOpen ? '' : 'none') });
      det.append(h.log ? el('pre', { class: 'caliblog', 'data-host': h.host }, h.log) : el('p', { class: 'small muted' }, 'sem log deste juiz ainda.'));
      const toggle = el('a', { href: '#', class: 'small', onclick: (e) => {
        e.preventDefault();
        const open = !OPEN_LOGS.has(h.host);
        if (open) OPEN_LOGS.add(h.host); else OPEN_LOGS.delete(h.host);
        det.style.display = open ? '' : 'none'; toggle.textContent = open ? 'ocultar log' : 'ver log';
      } }, isOpen ? 'ocultar log' : 'ver log');
      const head = el('div', { class: 'row', style: 'gap:.5rem;align-items:center;flex-wrap:wrap' },
        el('b', {}, h.host), el('span', { class: 'small muted' }, tlLine(h.tl) || 'sem TL'),
        h.at ? el('span', { class: 'small muted' }, '· ' + fmtDate(h.at)) : null,
        el('span', { style: 'flex:1' }), toggle);
      const reps = el('div', { class: 'small', style: 'margin-top:.25rem' });
      if ((h.reports || []).length) {
        reps.append(el('span', { class: 'muted' }, 'report por solução: '));
        h.reports.forEach(rn => reps.append(el('a', { href: '#', style: 'margin-right:.7rem;white-space:nowrap', onclick: (e) => { e.preventDefault(); openCalibReport(h.host, rn); } }, '📄 ' + rn)));
      }
      box.append(el('div', { class: 'judgecard' }, head, reps, det));
    });
  } else if (!RUNNING) box.append(el('p', { class: 'small muted' }, 'Ainda não calibrado — clique “Calibrar” na barra de baixo.'));
  // sem juízes calibrados mas com TL servido (legado): mostra o tempo-limite usado na correção
  if (!hosts.length && Object.keys(served).length) box.append(el('div', { class: 'small', style: 'margin-top:.4rem' }, 'Tempo-limite usado na correção: ' + tlLine(served)));
  box.querySelectorAll('.caliblog').forEach(p => { if (CALIB_SCROLL[p.dataset.host]) p.scrollTop = CALIB_SCROLL[p.dataset.host]; });   // restaura o scroll
  LAST_RENDER_SIG = valRenderSig();
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
  box.append('membros: ');
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
  let names = [...new Set([...COLLS.filter(c => c.owner).map(c => c.name), ...cur])];
  const q = noAccent(collFilter.q).toLowerCase().trim();
  const active = q || collFilter.mine || collFilter.manage || collFilter.course;
  if (active) {
    names = names.filter(n => {
      if (cur.includes(n)) return true;                 // selecionada: sempre visível
      const c = COLLS.find(x => x.name === n);
      if (collFilter.mine   && !(c && c.mine))        return false;
      if (collFilter.manage && !(c && c.can_manage))  return false;
      if (collFilter.course && !(c && c.repo_course)) return false;
      if (!q) return true;
      const hay = noAccent(n + ' ' + ((c && c.title) || '') + ' ' + ((c && c.owner) || '')).toLowerCase();
      return hay.includes(q);
    });
  }
  if (!names.length) {
    box.append(el('span', { class: 'small muted' },
      active ? 'nenhuma coleção corresponde ao filtro.' : 'sem coleções ainda — crie uma abaixo.'));
    return;
  }
  names.forEach(n => { const on = cur.includes(n);
    box.append(el('span', { class: 'collchip' + (on ? ' on' : ''), onclick: () => { const c = currentColls(); on ? setColls(c.filter(x => x !== n)) : setColls([...c, n]); } }, (on ? '✓ ' : '') + n)); });
}
const collChip = (u, onx) => el('span', { class: 'pill mut', style: 'margin-right:.3rem' }, u,
  el('a', { href: '#', style: 'margin-left:.3rem', onclick: async (e) => { e.preventDefault(); await onx(); } }, '×'));
// Coleções são só TAGS de agrupamento (m:n). A gestão de ACESSO (membros da org + trava de público)
// NÃO é aqui — fica na aba "Orgs" da gestão de problemas. Este painel só marca o problema em coleções.
function renderCollManage() {
  const box = $('collManage'); if (!box) return; box.innerHTML = '';
  box.append(el('span', { class: 'small muted' },
    'Coleções são rótulos de agrupamento (um problema pode estar em várias) e não dão acesso. Quem pode EDITAR o problema é a sua ORG — gerencie membros e a trava de público em '),
    el('a', { href: '/problemas/#orgs' }, 'Gestão de Problemas › Orgs'), el('span', { class: 'small muted' }, '.'));
}
async function newColl() {
  const name = $('newCollName').value.trim();
  if (!name || name.length > 80) { setMsg('Nome de coleção inválido (1–80 caracteres; pode ter espaços).', 'error'); return; }
  try {
    const j = await apiPost('/problems/collection-create', { name }, { contest: CONTEST, auth: true });
    COLLS.push({ name: j.name, owner: j.owner, mine: true, can_manage: true, count: 0 });
    setColls([...currentColls(), j.name]); $('newCollName').value = '';
    setMsg('Coleção criada ✓ — marque o problema nela e salve.', 'v-ok');
  } catch (e) { setMsg(e.message, 'error'); }
}

// ---- visibilidade (público) — AÇÃO EXPLÍCITA, separada do salvar -------------------------
function renderPubState() {
  const st = $('pubState'), btn = $('pubToggle'); if (!st || !btn) return;
  if (loadedPublic) { st.textContent = '🌐 PÚBLICO (treino livre)'; st.style.color = '#1a7f37'; btn.textContent = 'tornar privado'; }
  else { st.textContent = '🔒 privado (rascunho)'; st.style.color = ''; btn.textContent = 'tornar público'; }
  // trava de público da ORG: se a org é privada, não dá p/ publicar (set-public devolve 403)
  const ph = $('pubOrgHint');
  if (ph) {
    if (!loadedPublic && orgIsPrivate()) {
      ph.style.display = '';
      ph.innerHTML = '🔒 A org <b>' + REPO + '</b> é <b>privada</b> — não é possível tornar público até um admin liberar o público da org em Gestão de Problemas › Orgs.';
    } else ph.style.display = 'none';
  }
  // "Mover para outra org" só faz sentido em problema salvo e RASCUNHO (mover mudaria o id de um público em uso)
  const mv = $('moveorg');
  if (mv) mv.style.display = (MODE === 'edit' && ID && !loadedPublic) ? '' : 'none';
}
async function togglePublic() {
  if (MODE !== 'edit' || !ID) { setMsg('Salve o problema primeiro para poder publicar.', 'error'); return; }
  const makePublic = !loadedPublic;
  if (makePublic && !confirm('⚠ TORNAR PÚBLICO publica "' + ID + '" no TREINO LIVRE — fica visível a TODOS.\n\nProblemas de prova devem ficar PRIVADOS até a prova passar. Confirmar a publicação?')) return;
  const btn = $('pubToggle'); btn.disabled = true;
  try {
    await apiPost('/problems/set-public', { id: ID, public: makePublic }, { contest: CONTEST, auth: true });
    loadedPublic = makePublic; renderPubState(); updateReady();
    setMsg(makePublic ? 'Publicado no treino livre ✓ (validação no juiz)' : 'Tornado privado ✓ (saiu do treino)', 'v-ok');
  } catch (e) { setMsg((e instanceof ApiError ? e.message : 'Falha ao mudar a visibilidade'), 'error'); }
  finally { btn.disabled = false; }
}

// ---- salvar / ações -----------------------------------------------------------------------
async function save() {
  REPO = $('repo').value;
  if (!REPO) {
    showTab('enun'); const fld = $('repo'); if (fld) flash(fld.closest('.field') || fld);
    setMsg(REPOS.length ? 'Escolha uma org no topo da aba Enunciado.'
                        : 'Crie uma org primeiro: clique “+ nova org” (topo da aba Enunciado).', 'error');
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
      fillRepoSelect();   // criado: a org vira selo fixo (parte do id) e "+ nova org" some
    } else await apiPost('/problems/edit', { id: ID, ...f }, { contest: CONTEST, auth: true });
    setMsg('Salvo ✓', 'v-ok');   // SALVAR não mexe em público — publicar é ação explícita (botão na aba Publicação)
  } catch (e) { setMsg((e instanceof ApiError ? e.message : 'Falha ao salvar') + (e.code ? ` (${e.code})` : ''), 'error'); }
  finally { $('save').disabled = false; }
}
async function act(action, label) {
  if (!ID) { setMsg('Salve o problema primeiro.', 'error'); return; }
  setMsg(label + '…');
  try {
    await apiPost('/problems/' + action, { id: ID }, { contest: CONTEST, auth: true });
    RUNNING = (action === 'publish') ? 'publish' : 'calibrate';
    calibPrevMax = maxCalibAt();
    setMsg(label + ' iniciado ✓ — veja o andamento em “Validação & calibração” (aba Publicação).', 'v-ok');
    showTab('pub'); renderVal(); updateReady(); startPolling();
  } catch (e) { setMsg(e.message, 'error'); }
}

// ---- calibração direcionada (escolher os juízes; 1 por processador; todos) -----------------
async function loadJudges() {
  try { JUDGES = (await apiGet('/problems/judges', { contest: CONTEST, auth: true })).judges || []; } catch { JUDGES = []; }
  renderJudges();
}
function renderJudges() {
  const box = $('judgePick'); if (!box) return; box.innerHTML = '';
  if (!JUDGES.length) { box.append(el('span', { class: 'small muted' }, 'nenhum juiz no registro.')); return; }
  const byCpu = {}; JUDGES.forEach(j => { (byCpu[j.cpu || '?'] = byCpu[j.cpu || '?'] || []).push(j); });
  Object.entries(byCpu).forEach(([cpu, js]) => {
    const grp = el('div', { class: 'cpugrp' }, el('div', { class: 'small muted' }, '🖥 ' + (cpu || 'CPU desconhecida')));
    js.forEach(j => {
      const cb = el('input', { type: 'checkbox', value: j.host }); cb.checked = j.online; cb.disabled = !j.online;
      grp.append(el('label', { class: 'jcheck' + (j.online ? '' : ' off'), style: 'margin-left:.6rem' }, cb, ' ' + j.host + (j.online ? '' : ' (offline)')));
    });
    box.append(grp);
  });
}
const checkedHosts = () => [...$('judgePick').querySelectorAll('input[type=checkbox]:checked')].map(c => c.value);
const onePerCpu = () => Object.values(JUDGES.filter(j => j.online).reduce((a, j) => { a[j.cpu] = a[j.cpu] || j.host; return a; }, {}));
async function calibrateHosts(hosts) {
  if (!ID) { setMsg('Salve o problema primeiro.', 'error'); return; }
  hosts = [...new Set((hosts || []).filter(Boolean))];
  if (!hosts.length) { setMsg('Escolha ao menos um juiz online.', 'error'); return; }
  setMsg('Calibrando em ' + hosts.length + ' juiz(es)…');
  try {
    await apiPost('/problems/request-calibration', { id: ID, hosts }, { contest: CONTEST, auth: true });
    RUNNING = 'calibrate'; calibPrevMax = maxCalibAt();
    setMsg('Calibração disparada em ' + hosts.length + ' juiz(es) — acompanhe abaixo.', 'v-ok');
    showTab('pub'); renderVal(); updateReady(); startPolling();
  } catch (e) { setMsg(e.message, 'error'); }
}
async function newDir() {
  const name = prompt('Nome da nova org — minúsculas, sem espaço:'); if (!name) return;
  try {
    const j = await apiPost('/problems/repo-create', { repo: name.trim() }, { contest: CONTEST, auth: true });
    REPOS.push({ repo: j.repo, owner: j.owner, mine: true, collaborators: [], collections: j.collections || [], public_allowed: j.public_allowed === true });
    REPO = j.repo; fillRepoSelect(); renderPubState(); await loadShare(); setMsg('Org criada ✓', 'v-ok');
  } catch (e) { setMsg(e.message, 'error'); }
}
// mover um RASCUNHO p/ outra org (muda o id) — alvo entre as MINHAS orgs (REPOS). Público não move.
async function moveProblem() {
  if (MODE !== 'edit' || !ID) { setMsg('Salve o problema primeiro para poder mover.', 'error'); return; }
  if (loadedPublic) { setMsg('Problema público está em uso — torne privado antes de mover.', 'error'); return; }
  const cur = ID.split('#')[0];
  const targets = REPOS.map(r => r.repo).filter(n => n !== cur);
  if (!targets.length) { setMsg('Você não tem outra org para onde mover. Crie uma primeiro.', 'error'); return; }
  const to = (prompt(`Mover “${ID}” para qual org?\nSuas orgs: ${targets.join(', ')}`, targets[0]) || '').trim();
  if (!to || to === cur) return;
  setMsg('Movendo…');
  try {
    const j = await apiPost('/problems/move', { id: ID, to_org: to }, { contest: CONTEST, auth: true });
    setMsg('Movido ✓ — recarregando…', 'v-ok');
    location.href = 'editar.html?id=' + encodeURIComponent(j.id);
  } catch (e) { setMsg((e instanceof ApiError ? e.message : 'Falha ao mover') + (e.code ? ` (${e.code})` : ''), 'error'); }
}

async function delProblem() {
  if (MODE !== 'edit' || !ID) return;
  const typed = prompt('Remover é IRREVERSÍVEL (apaga do treino e do repositório do problema). Digite o id para confirmar: ' + ID);
  if (typed === null) return;
  if (typed !== ID) { setMsg('Confirmação não bateu — nada foi removido.', 'error'); return; }
  if ($('delprob')) $('delprob').disabled = true;
  try {
    await apiPost('/problems/delete', { id: ID, confirm: typed }, { contest: CONTEST, auth: true });
    setMsg('Problema removido ✓', 'v-ok');
    setTimeout(() => { location.href = './'; }, 800);
  } catch (e) { setMsg(e.message, 'error'); if ($('delprob')) $('delprob').disabled = false; }
}

async function loadSource(id, j) {
  if (!j) j = await apiGet('/problems/source?id=' + encodeURIComponent(id), { contest: CONTEST, auth: true });
  EDITABLE = j.editable; OWNER = j.owner || ''; REPO = id.split('#')[0];
  $('title').textContent = 'Editar: ' + id;
  $('prob').value = id.split('#').slice(1).join('#'); $('prob').disabled = true;
  fillRepoSelect(); await renderForm(j);
  if ($('delprob')) $('delprob').style.display = EDITABLE ? '' : 'none';   // remover só p/ quem pode editar
  if (!EDITABLE) {
    showNote('⚠ ' + (j.note || 'Somente leitura.') + ' Os botões de salvar estão desativados (mas dá p/ baixar o pacote).');
    ['save', 'publish', 'calibrate', 'pubToggle', 'delprob', 'moveorg', 'addex', 'addtest', 'uploadTar', 'scoreEnabled', 'addGroup'].forEach(b => { if ($(b)) $(b).disabled = true; });
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
  if ($('delprob')) $('delprob').onclick = delProblem;
  $('publish').onclick = () => act('publish', 'Validar');
  $('calibrate').onclick = () => act('request-calibration', 'Calibração');
  $('newdir').onclick = newDir;
  if ($('moveorg')) $('moveorg').onclick = moveProblem;
  $('preview').onclick = preview;
  $('previewClose').onclick = () => { $('previewModal').style.display = 'none'; $('previewBody').innerHTML = ''; };
  $('download').onclick = download;
  $('uploadTar').addEventListener('change', (e) => { uploadTar(e.target.files[0]); e.target.value = ''; });
  $('repo').onchange = async () => { REPO = $('repo').value; updateRepoHint(); renderPubState(); await loadShare(); };
  $('shareAdd').onclick = async () => { const u = $('shareLogin').value.trim(); if (u) { await share([u], []); $('shareLogin').value = ''; } };
  [...CF_TEXT, ...CF_YN, ...CF_FLAG].forEach(([id]) => $(id).addEventListener('change', () => { syncConfFromFields(); updateReady(); }));
  $('confRaw').addEventListener('change', () => { confToFields($('confRaw').value); updateReady(); });
  $('newCollBtn').onclick = newColl;
  $('pcolls').addEventListener('change', () => { renderCollChips(); renderCollManage(); });
  $('collFilter').addEventListener('input', () => { collFilter.q = $('collFilter').value; renderCollChips(); });
  const bindTog = (id, key) => $(id).addEventListener('click', () => {
    collFilter[key] = !collFilter[key]; $(id).classList.toggle('on', collFilter[key]); renderCollChips();
  });
  bindTog('collFilterMine', 'mine'); bindTog('collFilterManage', 'manage'); bindTog('collFilterCourse', 'course');
  $('enunMount').addEventListener('input', updateReady);
  $('stmtToggle').onclick = toggleStmtMode;
  $('pubToggle').onclick = togglePublic;
  // pontuação por grupos
  $('scoreEnabled').addEventListener('change', () => { if ($('scoreEnabled').checked && !$('scoreGroups').children.length) addGroupRow(); syncScore(); });
  $('addGroup').onclick = () => { addGroupRow(); syncScore(); };
  // calibração direcionada
  $('calibSel').onclick = () => calibrateHosts(checkedHosts());
  $('calibPerCpu').onclick = () => calibrateHosts(onePerCpu());
  $('calibAll').onclick = () => calibrateHosts(JUDGES.filter(j => j.online).map(j => j.host));
  // correção especial (scripts/)
  $('scrAdd').onclick = () => addScript({ path: '', content_b64: '', exec: true }, true);
  const scrFi = hiddenFile(true);
  scrFi.addEventListener('change', async () => { for (const f of scrFi.files) addScript({ path: f.name, content_b64: await fileToBase64(f), exec: /\.(sh|py|pl)$/.test(f.name) }, false); scrFi.value = ''; });
  $('scrUpload').onclick = () => scrFi.click(); $('scrUpload').after(scrFi);
  $('scrTplSel').addEventListener('focus', loadScriptTemplates, { once: true });
  $('scrTplApply').onclick = applyScriptTemplate;
}

async function boot() {
  await renderAuthArea($('authArea'), CONTEST, () => location.reload());
  const st = await status(CONTEST);
  if (!st.logged_in) { $('needauth').style.display = ''; return; }
  $('app').style.display = '';

  bindHandlers();           // 1) liga TUDO antes de qualquer await de dados
  setupTabs();
  updateReady();

  // dispara em PARALELO o que é independente (antes era uma cadeia de awaits — lenta pelo túnel):
  // repos + permissão + a SOURCE do problema vão juntos; depois share + coleções idem.
  const p = qs(), pid = p.get('id');
  const pRepos = apiGet('/problems/repos', { contest: CONTEST, auth: true }).then(r => r.repos || []).catch(() => []);
  const pPerm  = apiGet('/treino/contest-create/permission', { contest: CONTEST, auth: true }).then(r => !!r.can_create).catch(() => false);
  const pSrc   = pid ? apiGet('/problems/source?id=' + encodeURIComponent(pid), { contest: CONTEST, auth: true }) : Promise.resolve(null);
  try {
    const [repos, src] = await Promise.all([pRepos, pSrc]);
    REPOS = repos;
    if (src) { MODE = 'edit'; ID = pid; await loadSource(ID, src); }
    else {
      MODE = 'new'; REPO = p.get('repo') || ''; fillRepoSelect();
      await renderForm({ enunciado_md: '', author: st.name || st.login || '', tags: [], collections: [],
        examples: [], tests: [], sols: { good: [{ filename: 'sol.py', code: '' }] }, public: false,
        score: { enabled: false, groups: [] },
        conf_text: 'TLMOD[calibrafactor]=1.35\nULIMITS[-u]=10000\nALLOWPARALLELTEST=y\n' });
    }
    await Promise.all([loadShare(), loadColls()]);
  } catch (e) {
    setMsg('Falha ao carregar o problema: ' + (e instanceof ApiError ? e.message : (e && e.message || e)), 'error');
  }
  CAN_CREATE = await pPerm;

  // criar org/coleção e criar problema novo: só p/ quem pode criar (regra de criar contest)
  if (!CAN_CREATE) ['newdir', 'newCollBtn'].forEach(b => { if ($(b)) $(b).disabled = true; });
  if (MODE === 'new' && !CAN_CREATE) {
    showNote('⚠ Você não tem permissão para criar problemas. Peça a um administrador — é a mesma permissão de criar contests.');
    if ($('save')) $('save').disabled = true;
  } else if (!EDITABLE) { if ($('newCollBtn')) $('newCollBtn').disabled = true; }

  updateReady();
  loadValidation();         // best-effort: painel de validação/calibração + prontidão
  loadJudges();             // lista de juízes p/ a calibração direcionada
}
boot();
