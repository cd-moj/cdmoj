// treino/problemas/editar.js — editor de problemas (autoria keyless; git escondido).
// Cria/edita um problema num diretório (repo Gitea) do autor; salva via /problems/create|edit,
// publica/calibra, e compartilha o diretório. Sem git, sem chave — só o login do MOJ.
import { apiGet, apiPost, ApiError } from '/shared/api.js';
import { status } from '/shared/auth.js';
import { el, renderAuthArea, fmtDate } from '/shared/ui.js';
import { createEditor } from '/shared/editor.js';

const CONTEST = 'treino';
let MODE = 'new', ID = '', REPO = '', OWNER = '', EDITABLE = true, REPOS = [], loadedPublic = false;
let enunEd = null, solEd = null;

const qs = () => new URLSearchParams(location.search);
const splitList = (s) => (s || '').split(',').map(x => x.trim()).filter(Boolean);
const $ = (id) => document.getElementById(id);
const setMsg = (t, cls) => { const m = $('msg'); m.textContent = t; m.className = 'small ' + (cls || ''); };
const b64ToUtf8 = (b) => { try { return new TextDecoder().decode(Uint8Array.from(atob(b), c => c.charCodeAt(0))); } catch { return ''; } };
const EXT2CM = { py: 'python', cpp: 'cpp', cc: 'cpp', cxx: 'cpp', c: 'cpp', h: 'cpp', hpp: 'cpp', java: 'java', rs: 'rust', go: 'go', js: 'javascript' };
const cmFor = (fn) => EXT2CM[(String(fn).split('.').pop() || '').toLowerCase()] || null;
async function mountEditors(enunDoc, solDoc, solFn) {
  $('enunMount').innerHTML = ''; $('solMount').innerHTML = '';
  enunEd = await createEditor($('enunMount'), { doc: enunDoc || '', cm: 'markdown', images: true });
  solEd = await createEditor($('solMount'), { doc: solDoc || '', cm: cmFor(solFn || 'sol.py') });
}

function exampleRow(input = '', output = '') {
  const row = el('div', { class: 'ex' },
    el('div', { class: 'grid2' },
      el('div', {}, el('label', { class: 'small' }, 'entrada'), el('textarea', { class: 'exin' }, input)),
      el('div', {}, el('label', { class: 'small' }, 'saída'), el('textarea', { class: 'exout' }, output))),
    el('button', { class: 'btn ghost', type: 'button', onclick: () => row.remove() }, 'remover exemplo'));
  return row;
}
function addExample(i = '', o = '') { $('examples').append(exampleRow(i, o)); }
function collectExamples() {
  return [...$('examples').querySelectorAll('.ex')].map(r => ({
    input: r.querySelector('.exin').value, output: r.querySelector('.exout').value,
  })).filter(e => e.input !== '' || e.output !== '');
}

function fillRepoSelect() {
  const sel = $('repo'); sel.innerHTML = '';
  REPOS.forEach(r => sel.append(el('option', { value: r.repo }, r.repo + (r.mine ? '' : ' (compartilhado)'))));
  if (REPO && !REPOS.some(r => r.repo === REPO)) sel.append(el('option', { value: REPO }, REPO));
  if (REPO) sel.value = REPO;
  else REPO = sel.value || '';
}

async function renderForm(d) {
  $('ptitle').value = d.title || '';
  $('pauthor').value = d.author || '';
  $('ptags').value = (d.tags || []).join(', ');
  $('pcolls').value = (d.collections || []).join(', ');
  $('examples').innerHTML = '';
  (d.examples || []).forEach(e => addExample(e.input, e.output));
  if (!(d.examples || []).length) addExample();
  const good = (d.sols && d.sols.good && d.sols.good[0]) || {};
  $('solname').value = good.filename || 'sol.py';
  await mountEditors(d.enunciado_md || '', good.code || '', good.filename || 'sol.py');
  loadedPublic = !!d.public; $('ppublic').checked = loadedPublic;
  if (d.format && d.format !== 'md')
    showNote(`Enunciado em <b>${d.format}</b> — ao salvar, considere convertê-lo para o Markdown canônico.`);
}

async function preview() {
  const btn = $('preview'); btn.disabled = true; setMsg('Renderizando…');
  try {
    const j = await apiPost('/problems/preview',
      { enunciado_md: enunEd ? enunEd.getValue() : '', examples: collectExamples() }, { contest: CONTEST, auth: true });
    $('previewFrame').srcdoc = b64ToUtf8(j.html_b64 || '');
    $('previewModal').style.display = ''; setMsg('');
  } catch (e) { setMsg((e instanceof ApiError ? e.message : 'Falha ao renderizar'), 'error'); }
  finally { btn.disabled = false; }
}
function showNote(html) { const n = $('note'); n.style.display = ''; n.innerHTML = html; }

function collectFields() {
  return {
    title: $('ptitle').value.trim(),
    author: $('pauthor').value.trim(),
    tags: splitList($('ptags').value),
    collections: splitList($('pcolls').value),
    enunciado_md: enunEd ? enunEd.getValue() : '',
    examples: collectExamples(),
    good_sol: { filename: $('solname').value.trim() || 'sol.py', code: solEd ? solEd.getValue() : '' },
  };
}

async function loadShare() {
  const box = $('shareBox'), me = REPOS.find(r => r.repo === REPO);
  const isOwner = me ? me.mine : (OWNER === '' );
  box.style.display = isOwner ? '' : 'none';
  if (!isOwner || !REPO) return;
  try {
    const j = await apiGet('/problems/repo-collaborators?repo=' + encodeURIComponent(REPO), { contest: CONTEST, auth: true });
    renderShareList(j.collaborators || []);
  } catch { $('shareList').textContent = ''; }
}
function renderShareList(list) {
  const box = $('shareList'); box.innerHTML = '';
  if (!list.length) { box.textContent = 'ninguém ainda.'; return; }
  box.append('compartilhado com: ');
  list.forEach(u => box.append(el('span', { class: 'pill mut', style: 'margin-right:.3rem' }, u,
    el('a', { href: '#', style: 'margin-left:.3rem', onclick: async (e) => { e.preventDefault(); await share([], [u]); } }, '×'))));
}
async function share(add, remove) {
  try {
    const j = await apiPost('/problems/repo-collaborators', { repo: REPO, add, remove }, { contest: CONTEST, auth: true });
    renderShareList(j.collaborators || []); setMsg('compartilhamento atualizado ✓', 'v-ok');
  } catch (e) { setMsg(e.message, 'error'); }
}

async function save() {
  const f = collectFields();
  REPO = $('repo').value;
  if (!REPO) { setMsg('Escolha ou crie um diretório.', 'error'); return; }
  $('save').disabled = true; setMsg('Salvando…');
  try {
    if (MODE === 'new') {
      const prob = $('prob').value.trim();
      if (!/^[a-z0-9][a-z0-9._-]*$/.test(prob)) { setMsg('Nome de problema inválido (use [a-z0-9._-]).', 'error'); $('save').disabled = false; return; }
      const j = await apiPost('/problems/create', { repo: REPO, prob, ...f }, { contest: CONTEST, auth: true });
      ID = j.id; MODE = 'edit'; history.replaceState({}, '', '?id=' + encodeURIComponent(ID));
      $('prob').disabled = true; $('title').textContent = 'Editar: ' + ID;
    } else {
      await apiPost('/problems/edit', { id: ID, ...f }, { contest: CONTEST, auth: true });
    }
    if ($('ppublic').checked !== loadedPublic) {
      const r = await apiPost('/problems/set-public', { id: ID, public: $('ppublic').checked }, { contest: CONTEST, auth: true });
      loadedPublic = $('ppublic').checked;
      setMsg('Salvo ✓ ' + (loadedPublic ? '· publicação enfileirada (validação no juiz)' : '· despublicado'), 'v-ok');
    } else setMsg('Salvo ✓', 'v-ok');
  } catch (e) {
    setMsg((e instanceof ApiError ? e.message : 'Falha ao salvar') + (e.code ? ` (${e.code})` : ''), 'error');
  } finally { $('save').disabled = false; }
}

async function act(action, label) {
  if (!ID) { setMsg('Salve o problema primeiro.', 'error'); return; }
  setMsg(label + '…');
  try { const j = await apiPost('/problems/' + action, { id: ID }, { contest: CONTEST, auth: true }); setMsg(label + ' enfileirado ✓ (reqid ' + (j.reqid || '').slice(0, 8) + ')', 'v-ok'); }
  catch (e) { setMsg(e.message, 'error'); }
}

async function newDir() {
  const name = prompt('Nome da nova pasta (diretório) — minúsculas, sem espaço:');
  if (!name) return;
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
  fillRepoSelect();
  await renderForm(j);
  if (!EDITABLE) {
    showNote('⚠ ' + (j.note || 'Somente leitura.') + ' Os botões de salvar estão desativados.');
    ['save', 'publish', 'calibrate', 'addex'].forEach(b => $(b).disabled = true);
    $('shareBox').style.display = 'none';
  }
}

async function boot() {
  await renderAuthArea($('authArea'), CONTEST, () => location.reload());
  const st = await status(CONTEST);
  if (!st.logged_in) { $('needauth').style.display = ''; return; }
  $('app').style.display = '';
  try { REPOS = (await apiGet('/problems/repos', { contest: CONTEST, auth: true })).repos || []; } catch { REPOS = []; }

  const p = qs();
  if (p.get('id')) { MODE = 'edit'; ID = p.get('id'); await loadSource(ID); }
  else {
    MODE = 'new'; REPO = p.get('repo') || '';
    fillRepoSelect();
    await renderForm({ enunciado_md: '', author: st.name || st.login || '', tags: [], collections: [],
      examples: [], sols: { good: [{ filename: 'sol.py', code: '' }] }, public: false });
  }
  await loadShare();

  $('addex').onclick = () => addExample();
  $('save').onclick = save;
  $('publish').onclick = () => act('publish', 'Validar & Publicar');
  $('calibrate').onclick = () => act('request-calibration', 'Calibração');
  $('newdir').onclick = newDir;
  $('preview').onclick = preview;
  $('previewClose').onclick = () => { $('previewModal').style.display = 'none'; $('previewFrame').srcdoc = ''; };
  $('repo').onchange = async () => { REPO = $('repo').value; await loadShare(); };
  $('shareAdd').onclick = async () => { const u = $('shareLogin').value.trim(); if (u) { await share([u], []); $('shareLogin').value = ''; } };
  $('solname').addEventListener('change', async () => {
    if (!solEd) return; const code = solEd.getValue(); $('solMount').innerHTML = '';
    solEd = await createEditor($('solMount'), { doc: code, cm: cmFor($('solname').value) });
  });
}
boot();
