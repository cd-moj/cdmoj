// problemas/editar.js — editor de problemas (autoria keyless; git escondido).
// Enunciado (markdown+imagens), exemplos, testes ocultos, soluções good/slow/wrong/pass
// (editor por arquivo com seletor de linguagem + upload), e baixar/enviar o pacote (.tar.gz).
import { apiGet, apiPost, ApiError, getToken } from '/shared/api.js';
import { status, fileToBase64 } from '/shared/auth.js';
import { el, renderAuthArea } from '/shared/ui.js';
import { createEditor } from '/shared/editor.js';

const CONTEST = 'treino';
let MODE = 'new', ID = '', REPO = '', OWNER = '', EDITABLE = true, REPOS = [], loadedPublic = false;
let enunEd = null;
let solEditors = { good: [], slow: [], wrong: [], pass: [] };
let COLLS = [];
let CAN_CREATE = false;

const qs = () => new URLSearchParams(location.search);
const splitList = (s) => (s || '').split(',').map(x => x.trim()).filter(Boolean);
const $ = (id) => document.getElementById(id);
const setMsg = (t, cls) => { const m = $('msg'); m.textContent = t; m.className = 'small ' + (cls || ''); };
const b64ToUtf8 = (b) => { try { return new TextDecoder().decode(Uint8Array.from(atob(b), c => c.charCodeAt(0))); } catch { return ''; } };
const EXT2CM = { py: 'python', cpp: 'cpp', cc: 'cpp', cxx: 'cpp', c: 'cpp', h: 'cpp', hpp: 'cpp', java: 'java', rs: 'rust', go: 'go', js: 'javascript', md: 'markdown' };
const cmFor = (fn) => EXT2CM[(String(fn).split('.').pop() || '').toLowerCase()] || '';
const LANG_OPTS = [['', 'texto'], ['cpp', 'C/C++'], ['python', 'Python'], ['java', 'Java'], ['rust', 'Rust'], ['go', 'Go'], ['javascript', 'JavaScript'], ['markdown', 'Markdown']];
const SOL_CATS = [['good', 'good — deve ser ACEITA'], ['wrong', 'wrong — deve FALHAR'], ['slow', 'slow — estoura o TEMPO'], ['pass', 'pass — aceitas (não calibram)'], ['upcoming', 'upcoming — em desenvolvimento']];
const DEFNAME = { good: 'sol.cpp', wrong: 'wa.cpp', slow: 'slow.cpp', pass: 'alt.cpp', upcoming: 'wip.cpp' };

// ---- conf (configurações do problema; ver saad-problems/README.org) -----------------------
const confVal = (text, key) => { const e = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); const m = (text || '').match(new RegExp('^\\s*' + e + '\\s*=\\s*(.*)$', 'm')); return m ? m[1].trim().replace(/^"(.*)"$/, '$1').replace(/^'(.*)'$/, '$1') : null; };
function confUpsert(text, key, value) {
  const lines = (text || '').split('\n'), e = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), re = new RegExp('^\\s*' + e + '\\s*=');
  const idx = lines.findIndex(l => re.test(l));
  if (value === null || value === '') { if (idx >= 0) lines.splice(idx, 1); }
  else { const v = /[\s+]/.test(value) ? `"${value}"` : value, line = key + '=' + v; if (idx >= 0) lines[idx] = line; else lines.push(line); }
  return lines.join('\n').replace(/\n{3,}/g, '\n\n');
}
const CF_TEXT = [['cf_calibrafactor', 'TLMOD[calibrafactor]'], ['cf_calibrationtl', 'CALIBRATIONTL'], ['cf_ulimit_u', 'ULIMITS[-u]'], ['cf_ulimit_f', 'ULIMITS[-f]'], ['cf_maxparallel', 'MAXPARALLELTESTS']];
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

// ---- testes ocultos -----------------------------------------------------------------------
function testRow(name = '', input = '', output = '') {
  const nameI = el('input', { type: 'text', value: name, placeholder: 'nome', style: 'max-width:11rem' });
  const inT = el('textarea', { class: 'tin' }, input), outT = el('textarea', { class: 'tout' }, output);
  const li = hiddenFile(false), lo = hiddenFile(false);
  nameI.addEventListener('change', updatePkgInfo);
  li.addEventListener('change', async () => { if (li.files[0]) { inT.value = await li.files[0].text(); if (!nameI.value) nameI.value = li.files[0].name.replace(/\.[^.]*$/, ''); updatePkgInfo(); } });
  lo.addEventListener('change', async () => { if (lo.files[0]) outT.value = await lo.files[0].text(); });
  const row = el('div', { class: 'ex' },
    el('div', { class: 'row', style: 'gap:.5rem;align-items:center' }, el('span', { class: 'small' }, 'teste'), nameI,
      el('button', { class: 'btn ghost', type: 'button', onclick: () => { row.remove(); updatePkgInfo(); } }, 'remover')),
    el('div', { class: 'grid2' },
      el('div', {}, el('label', { class: 'small' }, 'entrada ', el('span', { class: 'linklike', style: 'cursor:pointer', onclick: () => li.click() }, '(carregar)')), inT),
      el('div', {}, el('label', { class: 'small' }, 'saída ', el('span', { class: 'linklike', style: 'cursor:pointer', onclick: () => lo.click() }, '(carregar)')), outT)),
    li, lo);
  return row;
}
const renderTests = (tests) => { $('tests').innerHTML = ''; (tests || []).forEach(t => $('tests').append(testRow(t.name, t.input, t.output))); };
const addTest = () => { $('tests').append(testRow()); updatePkgInfo(); };
const collectTests = () => [...$('tests').querySelectorAll('.ex')].map(r => ({
  name: r.querySelector('input[type=text]').value.trim(), input: r.querySelector('.tin').value, output: r.querySelector('.tout').value })).filter(t => t.input !== '' || t.output !== '');
async function loadTestPairs(files) {
  const map = {};
  for (const f of files) {
    const base = f.name.replace(/\.(in|out|txt|a|ans|sol)$/i, ''); const isOut = /\.(out|ans|a|sol)$/i.test(f.name);
    map[base] = map[base] || { name: base }; map[base][isOut ? 'output' : 'input'] = await f.text();
  }
  Object.values(map).forEach(t => $('tests').append(testRow(t.name, t.input || '', t.output || ''))); updatePkgInfo();
}

// ---- soluções (good/slow/wrong/pass) ------------------------------------------------------
async function renderSols(sols) {
  sols = sols || {}; solEditors = { good: [], slow: [], wrong: [], pass: [] };
  const wrap = $('solsWrap'); wrap.innerHTML = '';
  for (const [cat, label] of SOL_CATS) {
    const rows = el('div', { id: 'sol-' + cat });
    const fi = hiddenFile(true); fi.addEventListener('change', () => loadSolFiles(cat, fi.files));
    wrap.append(el('div', { class: 'solcat', style: 'margin-top:.6rem' },
      el('div', { class: 'row', style: 'justify-content:space-between;align-items:center' }, el('b', {}, label),
        el('div', { class: 'row', style: 'gap:.4rem' },
          el('button', { class: 'btn ghost', type: 'button', onclick: () => addSol(cat, DEFNAME[cat], '') }, '+ arquivo'),
          el('button', { class: 'btn ghost', type: 'button', onclick: () => fi.click() }, '⬆ enviar'), fi)),
      rows));
    for (const s of (sols[cat] || [])) await addSol(cat, s.filename, s.code);
  }
  updatePkgInfo();
}
async function addSol(cat, fn, code) {
  const fnInput = el('input', { type: 'text', value: fn || DEFNAME[cat], style: 'max-width:14rem' });
  const langSel = langSelect(cmFor(fnInput.value)), mount = el('div', { class: 'editor-mount' });
  const row = el('div', { style: 'margin:.4rem 0' },
    el('div', { class: 'row', style: 'gap:.5rem;align-items:center' }, el('span', { class: 'small' }, 'arquivo'), fnInput, langSel,
      el('button', { class: 'btn ghost', type: 'button', onclick: () => { row.remove(); solEditors[cat] = solEditors[cat].filter(x => x.row !== row); updatePkgInfo(); } }, 'remover')),
    mount);
  $('sol-' + cat).append(row);
  let ed = await createEditor(mount, { doc: code || '', cm: langSel.value || null });
  const remount = async () => { const c = ed.getValue(); mount.innerHTML = ''; ed = await createEditor(mount, { doc: c, cm: langSel.value || null }); };
  langSel.addEventListener('change', remount);
  fnInput.addEventListener('change', () => { langSel.value = cmFor(fnInput.value); remount(); updatePkgInfo(); });
  solEditors[cat].push({ row, get: () => ({ filename: fnInput.value.trim(), code: ed.getValue() }) });
  updatePkgInfo();
}
const loadSolFiles = async (cat, files) => { for (const f of files) await addSol(cat, f.name, await f.text()); };
function collectSols() { const o = {}; for (const [cat] of SOL_CATS) o[cat] = solEditors[cat].map(x => x.get()).filter(s => s.filename); return o; }

// ---- árvore do pacote (clicável -> rola até a seção) --------------------------------------
function flash(t) { if (!t) return; t.scrollIntoView({ behavior: 'smooth', block: 'center' }); t.classList.add('flash'); setTimeout(() => t.classList.remove('flash'), 1200); }
const ul = (...kids) => el('ul', {}, ...kids.filter(Boolean));
const leaf = (label, target, opener) => el('li', {}, el('a', { onclick: () => { if (opener) opener(); flash(target); } }, label));
const dirNode = (label, ...kids) => el('li', {}, el('span', { class: 'dir' }, label), ul(...kids.filter(Boolean)));
function buildTree() {
  const exRows = [...$('examples').querySelectorAll('.ex')], tsRows = [...$('tests').querySelectorAll('.ex')];
  const testKids = [];
  if (exRows.length) testKids.push(dirNode('exemplos/', ...exRows.map((r, i) => leaf('sample' + (i + 1), r))));
  if (tsRows.length) testKids.push(dirNode('ocultos/', ...tsRows.map(r => leaf((r.querySelector('input[type=text]').value || 'teste'), r))));
  const solKids = SOL_CATS.map(([c]) => solEditors[c].length ? dirNode(c + '/', ...solEditors[c].map(s => leaf(s.get().filename || '(sem nome)', s.row))) : null).filter(Boolean);
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
  const sc = SOL_CATS.map(([c]) => `${c}:${solEditors[c].length}`).join(' · ');
  $('pkgInfo').textContent = `${ex} exemplo(s) · ${ts} teste(s) oculto(s) · soluções ${sc}`;
  if ($('pkgTree')) { $('pkgTree').innerHTML = ''; $('pkgTree').append(buildTree()); }
}

// ---- montagem / coleta --------------------------------------------------------------------
function fillRepoSelect() {
  const sel = $('repo'); sel.innerHTML = '';
  REPOS.forEach(r => sel.append(el('option', { value: r.repo }, r.repo + (r.mine ? '' : ' (compartilhado)'))));
  if (REPO && !REPOS.some(r => r.repo === REPO)) sel.append(el('option', { value: REPO }, REPO));
  if (REPO) sel.value = REPO; else REPO = sel.value || '';
}
async function renderForm(d) {
  $('ptitle').value = d.title || ''; $('pauthor').value = d.author || '';
  $('ptags').value = (d.tags || []).join(', '); $('pcolls').value = (d.collections || []).join(', ');
  $('enunMount').innerHTML = '';
  enunEd = await createEditor($('enunMount'), { doc: d.enunciado_md || '', cm: 'markdown', images: true });
  $('examples').innerHTML = ''; (d.examples || []).forEach(e => $('examples').append(exampleRow(e.input, e.output)));
  if (!(d.examples || []).length) $('examples').append(exampleRow());
  renderTests(d.tests || []);
  await renderSols(d.sols || { good: [{ filename: 'sol.py', code: '' }] });
  $('confRaw').value = d.conf_text || ''; confToFields($('confRaw').value);
  loadedPublic = !!d.public; $('ppublic').checked = loadedPublic;
  renderCollChips(); renderCollManage(); updatePkgInfo();
  if (d.format && d.format !== 'md') showNote(`Enunciado em <b>${d.format}</b> — ao salvar, considere convertê-lo para o Markdown canônico.`);
}
const collectFields = () => ({
  title: $('ptitle').value.trim(), author: $('pauthor').value.trim(),
  tags: splitList($('ptags').value), collections: splitList($('pcolls').value),
  enunciado_md: enunEd ? enunEd.getValue() : '', examples: collectExamples(),
  tests: collectTests(), sols: collectSols(), conf_text: $('confRaw').value,
});

async function preview() {
  const btn = $('preview'); btn.disabled = true; setMsg('Renderizando…');
  try {
    const j = await apiPost('/problems/preview', { enunciado_md: enunEd ? enunEd.getValue() : '', examples: collectExamples() }, { contest: CONTEST, auth: true });
    $('previewFrame').srcdoc = b64ToUtf8(j.html_b64 || ''); $('previewModal').style.display = ''; setMsg('');
  } catch (e) { setMsg((e instanceof ApiError ? e.message : 'Falha ao renderizar'), 'error'); }
  finally { btn.disabled = false; }
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
  const f = collectFields(); REPO = $('repo').value;
  if (!REPO) { setMsg('Escolha ou crie um diretório.', 'error'); return; }
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
    ['save', 'publish', 'calibrate', 'addex', 'addtest', 'uploadTar'].forEach(b => { if ($(b)) $(b).disabled = true; });
    $('shareBox').style.display = 'none';
  }
}

async function boot() {
  await renderAuthArea($('authArea'), CONTEST, () => location.reload());
  const st = await status(CONTEST);
  if (!st.logged_in) { $('needauth').style.display = ''; return; }
  $('app').style.display = '';
  try { REPOS = (await apiGet('/problems/repos', { contest: CONTEST, auth: true })).repos || []; } catch { REPOS = []; }
  try { CAN_CREATE = !!(await apiGet('/treino/contest-create/permission', { contest: CONTEST, auth: true })).can_create; } catch {}

  const p = qs();
  if (p.get('id')) { MODE = 'edit'; ID = p.get('id'); await loadSource(ID); }
  else {
    MODE = 'new'; REPO = p.get('repo') || ''; fillRepoSelect();
    await renderForm({ enunciado_md: '', author: st.name || st.login || '', tags: [], collections: [],
      examples: [], tests: [], sols: { good: [{ filename: 'sol.py', code: '' }] }, public: false,
      conf_text: 'TLMOD[calibrafactor]=1.35\nULIMITS[-u]=10000\nALLOWPARALLELTEST=y\n' });
  }
  await loadShare();

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
  [...CF_TEXT, ...CF_YN, ...CF_FLAG].forEach(([id]) => $(id).addEventListener('change', syncConfFromFields));
  $('confRaw').addEventListener('change', () => confToFields($('confRaw').value));
  $('newCollBtn').onclick = newColl;
  $('pcolls').addEventListener('change', () => { renderCollChips(); renderCollManage(); });
  // criar pasta/coleção e criar problema novo: só p/ quem pode criar (regra de criar contest)
  if (!CAN_CREATE) ['newdir', 'newCollBtn'].forEach(b => { if ($(b)) $(b).disabled = true; });
  if (MODE === 'new' && !CAN_CREATE) {
    showNote('⚠ Você não tem permissão para criar problemas. Peça a um administrador — é a mesma permissão de criar contests.');
    if ($('save')) $('save').disabled = true;
  } else if (!EDITABLE) { if ($('newCollBtn')) $('newCollBtn').disabled = true; }
  await loadColls();
}
boot();
