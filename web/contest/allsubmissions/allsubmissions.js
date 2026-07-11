// contest/allsubmissions/allsubmissions.js — ADMIN: todas as submissões do contest.
// 9 campos: tempo:username:problemid:lang:verdict:epoch:subid:fullname:univ
// Agrupa por usuário/problema, filtros, links cód/log, multi-seleção -> rejudge ({ids:[...]}).
import { apiGet, apiGetText, apiPost, getToken } from '/shared/api.js';
import { status } from '/shared/auth.js';
import { el, verdictClass, isPending, fmtDate } from '/shared/ui.js';
import { T } from '/shared/i18n.js';
import { mountChrome } from '/lib/contest-chrome.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
let problems = [];
let subs = [];
let groupBy = 'all';
let selected = new Set();

function shortOf(pid) { const p = problems.find(x => x.problem_id === pid); return p ? (p.short_name || pid) : pid; }
function fullOf(pid) { const p = problems.find(x => x.problem_id === pid); return p ? (p.full_name || '') : ''; }

function parseLine(line) {
  const v = line.split(':');
  if (v.length < 7) return null;
  return {
    sinceStart: v[0], username: v[1], problem_id: v[2], lang: v[3],
    verdict: v[4], epoch: v[5], submission_id: v[6],
    fullname: v[7] || '', univ: v[8] || '',
  };
}

async function downloadAuthed(path, filename) {
  try {
    const r = await fetch('/api/v1' + path, { headers: { 'Authorization': 'Bearer ' + getToken(CONTEST) } });
    if (!r.ok) throw 0;
    const a = el('a', { href: URL.createObjectURL(await r.blob()), download: filename });
    document.body.append(a); a.click(); a.remove();
  } catch { alert(T('Falha ao baixar.', 'Download failed.')); }
}
async function openLogAuthed(path) {
  try {
    const r = await fetch('/api/v1' + path, { headers: { 'Authorization': 'Bearer ' + getToken(CONTEST) } });
    const w = window.open(); const pre = w.document.createElement('pre');
    pre.style.cssText = 'font-family:monospace;white-space:pre-wrap;padding:1rem'; pre.textContent = await r.text();
    w.document.body.append(pre); w.document.close();
  } catch { alert(T('Falha ao abrir o log.', 'Failed to open the log.')); }
}
// abre o report.html (auto-contido) do julgamento num iframe sandboxed (HTML/CSS sim, JS não).
async function openReportAuthed(path) {
  try {
    const r = await fetch('/api/v1' + path, { headers: { 'Authorization': 'Bearer ' + getToken(CONTEST) } });
    const html = await r.text();
    const w = window.open('', '_blank');
    if (!w) { alert(T('Permita pop-ups para ver o report.', 'Allow pop-ups to view the report.')); return; }
    w.document.title = 'Report'; w.document.body.style.margin = '0';
    const ifr = w.document.createElement('iframe');
    ifr.setAttribute('sandbox', '');
    ifr.srcdoc = html;
    ifr.style.cssText = 'position:fixed;inset:0;border:0;width:100%;height:100%';
    w.document.body.append(ifr);
  } catch { alert(T('Falha ao abrir o report.', 'Failed to open the report.')); }
}

function filteredSubs() {
  const fu = document.getElementById('fUser').value.trim().toLowerCase();
  const fp = document.getElementById('fProblem').value.trim().toLowerCase();
  const fv = document.getElementById('fVerdict').value.trim().toLowerCase();
  return subs.filter(s => {
    if (fu && !(s.username || '').toLowerCase().includes(fu)) return false;
    if (fp) { const sn = shortOf(s.problem_id).toLowerCase(); if (!sn.includes(fp) && !(s.problem_id || '').toLowerCase().includes(fp)) return false; }
    if (fv && !(s.verdict || '').toLowerCase().includes(fv)) return false;
    return true;
  });
}

function rowTable(items) {
  const head = el('thead', {}, el('tr', {},
    el('th', { style: 'width:1.5rem' }, ''),
    el('th', {}, T('Tempo', 'Time')), el('th', {}, T('Quando', 'When')),
    el('th', {}, T('Usuário', 'User')), el('th', {}, T('Equipe', 'Team')),
    el('th', {}, T('Problema', 'Problem')), el('th', {}, T('Veredicto', 'Verdict')),
    el('th', {}, T('Arquivo', 'File')), el('th', {}, 'Log')));
  const tb = el('tbody');
  items.forEach(s => {
    const cb = el('input', { type: 'checkbox' });
    cb.checked = selected.has(s.submission_id);
    cb.addEventListener('change', () => { if (cb.checked) selected.add(s.submission_id); else selected.delete(s.submission_id); });
    const pending = isPending(s.verdict);
    tb.append(el('tr', {},
      el('td', {}, cb),
      el('td', {}, s.sinceStart || ''),
      el('td', {}, el('span', { class: 'small' }, fmtDate(s.epoch))),
      el('td', {}, s.username || ''),
      el('td', {}, (s.univ ? `[${s.univ}] ` : '') + (s.fullname || '')),
      el('td', {}, el('b', {}, shortOf(s.problem_id)), ' ', el('span', { class: 'small muted' }, fullOf(s.problem_id))),
      el('td', {}, el('span', { class: 'verdict ' + verdictClass(s.verdict) }, pending ? el('span', {}, el('span', { class: 'spin' }), ' ' + s.verdict) : s.verdict)),
      el('td', {},
        el('a', { href: '#', title: T('ver código', 'view code'), onclick: (e) => { e.preventDefault(); openLogAuthed(`/submission/source?contest=${encodeURIComponent(CONTEST)}&id=${encodeURIComponent(s.submission_id)}&time=${encodeURIComponent(s.epoch)}`); } }, T('ver', 'view')),
        ' ',
        el('a', { href: '#', title: T('baixar', 'download'), class: 'small muted', onclick: (e) => { e.preventDefault(); downloadAuthed(`/submission/source?contest=${encodeURIComponent(CONTEST)}&id=${encodeURIComponent(s.submission_id)}&time=${encodeURIComponent(s.epoch)}`, s.submission_id + '.' + (s.lang || 'txt').toLowerCase()); } }, '⬇')),
      el('td', {}, el('a', { href: '#', onclick: (e) => { e.preventDefault(); openReportAuthed(`/submission/log?contest=${encodeURIComponent(CONTEST)}&id=${encodeURIComponent(s.submission_id)}&time=${encodeURIComponent(s.epoch)}`); } }, s.submission_id.slice(0, 8)))));
  });
  return el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' }, head, tb));
}

function render() {
  const box = document.getElementById('adminContainer');
  box.innerHTML = '';
  const list = filteredSubs();
  if (!list.length) { box.innerHTML = `<span class="muted">${T('Nenhuma submissão.', 'No submissions.')}</span>`; return; }

  if (groupBy === 'all') { box.append(rowTable(list)); return; }
  const groups = {};
  list.forEach(s => {
    const key = groupBy === 'user' ? (s.username || '?') : shortOf(s.problem_id);
    (groups[key] = groups[key] || []).push(s);
  });
  Object.keys(groups).sort((a, b) => a.localeCompare(b, undefined, { numeric: true })).forEach(k => {
    const label = groupBy === 'user' ? `${T('Usuário: ', 'User: ')}${k}` : `${T('Problema: ', 'Problem: ')}${k} ${fullOf(groups[k][0].problem_id)}`;
    const gitems = groups[k];
    const markG = el('a', { href: '#', class: 'small', style: 'margin-left:.7rem', onclick: (e) => { e.preventDefault(); gitems.forEach(s => selected.add(s.submission_id)); render(); } }, T('☑ marcar grupo', '☑ select group'));
    box.append(el('div', { class: 'group-head' }, label, markG));
    box.append(rowTable(gitems));
  });
}

async function doRejudge() {
  const ids = Array.from(selected);
  const msg = document.getElementById('rejudgeMsg');
  if (!ids.length) { msg.innerHTML = `<span class="error-box">${T('Selecione ao menos uma submissão.', 'Select at least one submission.')}</span>`; return; }
  const btn = document.getElementById('rejudgeBtn');
  btn.disabled = true; msg.textContent = T('Enviando…', 'Sending…');
  try {
    const r = await apiPost('/contest/rejudge?contest=' + encodeURIComponent(CONTEST), { ids }, { contest: CONTEST, auth: true });
    const n = (r && r.count) != null ? r.count : ids.length;
    const sk = (r && r.skipped_count) || 0;
    msg.innerHTML = `✓ ${n}${T(' enviada(s) para rejulgamento', ' sent for rejudge')}`
      + (sk ? ` <span class="error-box">— ${sk}${T(' pulada(s) (sem fonte arquivada): ', ' skipped (no archived source): ')}${(r.skipped || []).join(', ')}</span>` : '.');
    selected.clear(); render();
  } catch (e) {
    msg.innerHTML = '<span class="error-box">' + T('Erro: ', 'Error: ') + (e && e.message ? e.message : T('falha ao rejulgar', 'failed to rejudge')) + '</span>';
  } finally { btn.disabled = false; }
}

async function loadSubs() {
  let txt;
  try { txt = await apiGetText('/contest/allsubmissions?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: true }); }
  catch (e) {
    document.getElementById('adminContainer').innerHTML = `<span class="error-box">${T('Falha ao carregar (precisa ser admin ou juiz-chefe).', 'Failed to load (must be admin or chief judge).')}</span>`;
    return;
  }
  subs = txt.split('\n').map(s => s.trim()).filter(Boolean).map(parseLine).filter(Boolean)
    .sort((a, b) => Number(b.epoch) - Number(a.epoch));
  render();
}

async function boot() {
  if (!CONTEST) { document.body.innerHTML = `<div class="container"><div class="error-box">${T('Contest não informado (?c=).', 'Contest not specified (?c=).')}</div></div>`; return; }
  let basic;
  try { basic = await apiGet('/contest/basic?contest=' + encodeURIComponent(CONTEST), {}); }
  catch { document.body.innerHTML = `<div class="container"><div class="error-box">${T('Contest não encontrado.', 'Contest not found.')}</div></div>`; return; }

  const st = await status(CONTEST);
  if (!st.logged_in) { location.href = '/contest/?c=' + encodeURIComponent(CONTEST); return; }
  if (!st.is_admin && !st.is_chief) { document.body.innerHTML = `<div class="container"><div class="notice">${T('Acesso restrito a administradores e ao juiz-chefe.', 'Restricted to administrators and the chief judge.')}</div></div>`; return; }

  await mountChrome(CONTEST, basic, { auth: true });

  try {
    const j = await apiGet('/contest/problems?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: true });
    problems = Array.isArray(j) ? j : (j.problems || []);
  } catch {}

  document.querySelectorAll('[data-group]').forEach(btn => btn.addEventListener('click', () => { groupBy = btn.dataset.group; render(); }));
  ['fUser', 'fProblem', 'fVerdict'].forEach(id => document.getElementById(id).addEventListener('input', render));
  document.getElementById('markAll').addEventListener('click', () => { filteredSubs().forEach(s => selected.add(s.submission_id)); render(); });
  const clearBtn = el('button', { class: 'btn ghost', onclick: () => { selected.clear(); render(); } }, T('Desmarcar todos', 'Clear selection'));
  document.getElementById('markAll').after(clearBtn);
  document.getElementById('rejudgeBtn').addEventListener('click', doRejudge);

  await loadSubs();
}
boot();
