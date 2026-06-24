// treino/problema/problema.js — página de um problema do Treino Livre.
import { apiGet, apiGetText, apiPost, getToken } from '/shared/api.js';
import { fileToBase64, textToBase64, status } from '/shared/auth.js';
import { el, verdictClass, isPending, fmtDate, renderAuthArea } from '/shared/ui.js';
import { createEditor } from '/shared/editor.js';
import { LANGUAGES, langById } from '/shared/languages.js';

const CONTEST = 'treino';
const qs = new URLSearchParams(location.search);
const ID = qs.get('id') || '';
let pollTimer = null, editorApi = null, editorMount = null, langSel = null, curLangId = 'c', problemTL = {};

const templateFor = (id) => langById(id).template;
const isTemplateContent = (t) => LANGUAGES.some((l) => l.template.trim() === (t || '').trim());

function b64utf8(b64) {
  try {
    const bin = atob(b64 || '');
    return new TextDecoder('utf-8').decode(Uint8Array.from(bin, (c) => c.charCodeAt(0)));
  } catch { return ''; }
}

function fmtTime(v) {
  const n = parseFloat(v);
  if (isNaN(n)) return String(v);
  return n < 1 ? Math.round(n * 1000) + ' ms' : (Math.round(n * 1000) / 1000) + ' s';
}

async function swapEditor(content, langId) {
  curLangId = langId;
  if (langSel) langSel.value = langId;
  if (!editorMount) return;
  editorMount.innerHTML = '';
  editorApi = await createEditor(editorMount, { doc: content, cm: langById(langId).cm });
}

async function loadProblem() {
  if (!ID) { document.getElementById('ptitle').textContent = 'Problema não informado'; return; }
  let p;
  try { p = await apiGet('/treino/problem?id=' + encodeURIComponent(ID), { contest: CONTEST }); }
  catch { document.getElementById('ptitle').textContent = 'Problema não encontrado'; return; }

  document.title = (p.title || ID) + ' — MOJ';
  document.getElementById('ptitle').textContent = p.title || ID;

  const tagsEl = document.getElementById('ptags');
  (p.tags || []).forEach((tg) => {
    const name = String(tg).replace(/^#/, '');
    tagsEl.append(el('a', { class: 'tag', href: '/treino/?searchtag=' + encodeURIComponent(name) }, '#' + name));
  });
  tagsEl.classList.toggle('tags-blur', localStorage.getItem('moj_tags_blur') !== '0');
  document.getElementById('toggleTags').addEventListener('click', (e) => {
    e.preventDefault();
    const now = !tagsEl.classList.contains('tags-blur');
    tagsEl.classList.toggle('tags-blur', now);
    localStorage.setItem('moj_tags_blur', now ? '1' : '0');
  });

  const tl = p.time_limits || {};
  problemTL = tl;
  const ptl = document.getElementById('ptl'); ptl.innerHTML = '';
  const tEntries = Object.entries(tl)
    .sort((a, b) => (a[0] === 'default' ? -1 : b[0] === 'default' ? 1 : a[0].localeCompare(b[0])));
  if (tEntries.length) {
    ptl.append(el('span', { class: 'tl-label' }, '⏱ Tempo limite'));
    tEntries.forEach(([k, v]) => {
      const label = k === 'default' ? 'padrão' : (langById(k).label || k);
      ptl.append(el('span', { class: 'tl-chip' }, el('b', {}, label), el('span', { class: 'tl-time' }, fmtTime(v))));
    });
  }

  document.getElementById('problem-head').append(
    el('div', { style: 'margin-top:.6rem' },
      el('a', { class: 'btn ghost', style: 'padding:.32rem .7rem;font-size:.85rem',
                href: '/treino/problema/stats/?id=' + encodeURIComponent(ID) }, '📊 Estatísticas deste problema')));

  const html = b64utf8(p.statement_html_b64 || '');
  const doc = new DOMParser().parseFromString(html, 'text/html');
  document.getElementById('statement').innerHTML = doc.body ? doc.body.innerHTML : html;
}

async function downloadAuthed(path, filename) {
  const r = await fetch('/api/v1' + path, { headers: { 'Authorization': 'Bearer ' + getToken(CONTEST) } });
  const txt = await r.text();
  const a = el('a', { href: URL.createObjectURL(new Blob([txt], { type: 'text/plain' })), download: filename });
  document.body.append(a); a.click(); a.remove();
}

// abre o report.html (auto-contido) do julgamento num iframe sandboxed: renderiza
// HTML/CSS mas bloqueia JS (defesa em profundidade — o conteúdo já é escapado na origem).
async function openReportAuthed(path) {
  try {
    const r = await fetch('/api/v1' + path, { headers: { 'Authorization': 'Bearer ' + getToken(CONTEST) } });
    const html = await r.text();
    const w = window.open('', '_blank');
    if (!w) { alert('Permita pop-ups para ver o report.'); return; }
    w.document.title = 'Report'; w.document.body.style.margin = '0';
    const ifr = w.document.createElement('iframe');
    ifr.setAttribute('sandbox', '');
    ifr.srcdoc = html;
    ifr.style.cssText = 'position:fixed;inset:0;border:0;width:100%;height:100%';
    w.document.body.append(ifr);
  } catch { alert('Falha ao abrir o report.'); }
}

async function openSubmissionInEditor(subid, time, langField) {
  let txt;
  try {
    txt = await apiGetText(`/submission/source?contest=${CONTEST}&id=${subid}&time=${time}`, { contest: CONTEST, auth: true });
  } catch (e) { alert('Não foi possível abrir o código: ' + (e.message || '')); return; }
  await swapEditor(txt, langById((langField || '').toLowerCase()).id);
  document.getElementById('submitSection').scrollIntoView({ behavior: 'smooth' });
}

function parseHistLine(line) {
  const p = line.split(':');
  if (p.length < 7) return null;
  return { time: p[0], user: p[1], problem: p[2], lang: p[3],
           subid: p[p.length - 1], epoch: p[p.length - 2], verdict: p.slice(4, p.length - 2).join(':') };
}

async function loadHistory() {
  const box = document.getElementById('history');
  if (!getToken(CONTEST)) { box.innerHTML = '<span class="muted small">Entre para ver seu histórico.</span>'; return; }
  let txt;
  try { txt = await apiGetText('/treino/history?id=' + encodeURIComponent(ID), { contest: CONTEST, auth: true }); }
  catch { box.innerHTML = '<span class="muted small">—</span>'; return; }
  const rows = txt.split('\n').map((s) => s.trim()).filter(Boolean).map(parseHistLine).filter(Boolean)
                  .sort((a, b) => Number(b.epoch) - Number(a.epoch));
  box.innerHTML = '';
  if (!rows.length) { box.innerHTML = '<span class="muted small">Nenhuma submissão ainda.</span>'; return; }

  const tbl = el('table', { class: 'moj' },
    el('thead', {}, el('tr', {},
      el('th', {}, 'Data/Hora'), el('th', {}, 'Ações'), el('th', {}, 'Linguagem'), el('th', {}, 'Status'))));
  const tb = el('tbody');
  let anyPending = false;
  rows.forEach((r) => {
    if (isPending(r.verdict)) anyPending = true;
    const ext = (r.lang || 'txt').toLowerCase();
    const acts = el('td', { class: 'small' },
      el('a', { href: '#', title: 'abrir no editor', onclick: (e) => { e.preventDefault(); openSubmissionInEditor(r.subid, r.epoch, r.lang); } }, '✎ editor'),
      ' · ',
      el('a', { href: '#', onclick: (e) => { e.preventDefault(); downloadAuthed(`/submission/source?contest=${CONTEST}&id=${r.subid}&time=${r.epoch}`, r.subid + '.' + ext); } }, 'cód'),
      ' · ',
      el('a', { href: '#', onclick: (e) => { e.preventDefault(); openReportAuthed(`/submission/log?contest=${CONTEST}&id=${r.subid}&time=${r.epoch}`); } }, 'log'));
    const vcell = el('td', {}, el('span', { class: 'verdict ' + verdictClass(r.verdict) },
      isPending(r.verdict) ? el('span', {}, el('span', { class: 'spin' }), ' ' + r.verdict) : r.verdict));
    tb.append(el('tr', {}, el('td', {}, fmtDate(r.epoch)), acts, el('td', {}, r.lang), vcell));
  });
  tbl.append(tb); box.append(tbl);

  clearTimeout(pollTimer);
  if (anyPending) pollTimer = setTimeout(loadHistory, 5000 + Math.random() * 5000);
}

async function renderSubmit() {
  const body = document.getElementById('submitBody');
  body.innerHTML = '';
  const st = await status(CONTEST);
  if (!st.logged_in) {
    editorApi = null; editorMount = null;
    body.append(el('p', { class: 'notice' }, 'Você precisa estar logado para enviar. Use o login no topo da página.'));
    return;
  }
  langSel = el('select', {}, ...LANGUAGES.map((l) => {
    const tlv = problemTL[l.id] ?? problemTL.default;
    return el('option', { value: l.id }, l.label + (tlv != null ? ' — ' + fmtTime(tlv) : ''));
  }));
  langSel.value = curLangId;
  editorMount = el('div');
  const editorBox = el('div', { class: 'editor-box' }, editorMount);
  const fileInput = el('input', { type: 'file' });
  const steps = el('div', { class: 'submit-steps' });
  const btn = el('button', { class: 'btn' }, 'Enviar solução');
  const toggle = el('button', { class: 'btn ghost', type: 'button', onclick: () => {
    const c = editorBox.classList.toggle('collapsed');
    toggle.textContent = c ? '▸ Mostrar editor' : '▾ Ocultar editor';
  } }, '▾ Ocultar editor');

  body.append(
    el('div', { class: 'editor-bar' },
      el('label', {}, 'Linguagem: '), langSel,
      el('span', { class: 'small muted' }, 'ou arquivo:'), fileInput,
      el('span', { style: 'flex:1' }), toggle),
    editorBox, steps, btn);

  editorApi = await createEditor(editorMount, { doc: templateFor(curLangId), cm: langById(curLangId).cm });
  langSel.addEventListener('change', async () => {
    const cur = editorApi ? editorApi.getValue() : '';
    const keep = cur && !isTemplateContent(cur);   // preserva código digitado; só troca template
    await swapEditor(keep ? cur : templateFor(langSel.value), langSel.value);
  });

  btn.addEventListener('click', async () => {
    btn.disabled = true; steps.textContent = 'Preparando…';
    try {
      let filename, code_b64;
      if (fileInput.files && fileInput.files[0]) {
        filename = fileInput.files[0].name;
        code_b64 = await fileToBase64(fileInput.files[0]);
      } else {
        filename = 'solution.' + curLangId;
        code_b64 = textToBase64(editorApi.getValue());
      }
      steps.textContent = 'Enviando…';
      await apiPost('/submit?contest=' + CONTEST, { problem_id: ID, filename, code_b64 }, { contest: CONTEST, auth: true });
      steps.innerHTML = '<span class="v-ok" style="padding:.2rem .5rem;border-radius:6px">✓ Enviado! Acompanhe no histórico abaixo.</span>';
      await loadHistory();
    } catch (e) {
      steps.innerHTML = '<span class="error-box">Erro: ' + (e.message || 'falha ao enviar') + '</span>';
    } finally { btn.disabled = false; }
  });
}

async function boot() {
  await renderAuthArea(document.getElementById('authArea'), CONTEST, async () => { await renderSubmit(); await loadHistory(); });
  await loadProblem();
  await renderSubmit();
  await loadHistory();
}
boot();
