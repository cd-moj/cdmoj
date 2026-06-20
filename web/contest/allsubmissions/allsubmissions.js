// contest/allsubmissions/allsubmissions.js — ADMIN: todas as submissões do contest.
// 9 campos: tempo:username:problemid:lang:verdict:epoch:subid:fullname:univ
// Agrupa por usuário/problema, filtros, links cód/log, multi-seleção -> rejudge ({ids:[...]}).
import { apiGet, apiGetText, apiPost, getToken } from '/shared/api.js';
import { status } from '/shared/auth.js';
import { el, verdictClass, isPending, fmtDate } from '/shared/ui.js';
import { mountChrome } from '/lib/contest-chrome.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
let problems = [];
let subs = [];
let groupBy = 'all';
let selected = new Set();
let T = (pt) => pt;

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
  } catch { alert('Falha ao baixar.'); }
}
async function openLogAuthed(path) {
  try {
    const r = await fetch('/api/v1' + path, { headers: { 'Authorization': 'Bearer ' + getToken(CONTEST) } });
    const w = window.open(); const pre = w.document.createElement('pre');
    pre.style.cssText = 'font-family:monospace;white-space:pre-wrap;padding:1rem'; pre.textContent = await r.text();
    w.document.body.append(pre); w.document.close();
  } catch { alert('Falha ao abrir o log.'); }
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
    el('th', {}, 'Tempo'), el('th', {}, 'Quando'),
    el('th', {}, 'Usuário'), el('th', {}, 'Equipe'),
    el('th', {}, 'Problema'), el('th', {}, 'Veredicto'),
    el('th', {}, 'Arquivo'), el('th', {}, 'Log')));
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
      el('td', {}, el('a', { href: '#', onclick: (e) => { e.preventDefault(); downloadAuthed(`/submission/source?contest=${encodeURIComponent(CONTEST)}&id=${encodeURIComponent(s.submission_id)}&time=${encodeURIComponent(s.epoch)}`, s.submission_id + '.txt'); } }, 'cód')),
      el('td', {}, el('a', { href: '#', onclick: (e) => { e.preventDefault(); openLogAuthed(`/submission/log?contest=${encodeURIComponent(CONTEST)}&id=${encodeURIComponent(s.submission_id)}&time=${encodeURIComponent(s.epoch)}`); } }, s.submission_id.slice(0, 8)))));
  });
  return el('table', { class: 'moj' }, head, tb);
}

function render() {
  const box = document.getElementById('adminContainer');
  box.innerHTML = '';
  const list = filteredSubs();
  if (!list.length) { box.innerHTML = '<span class="muted">Nenhuma submissão.</span>'; return; }

  if (groupBy === 'all') { box.append(rowTable(list)); return; }
  const groups = {};
  list.forEach(s => {
    const key = groupBy === 'user' ? (s.username || '?') : shortOf(s.problem_id);
    (groups[key] = groups[key] || []).push(s);
  });
  Object.keys(groups).sort((a, b) => a.localeCompare(b, undefined, { numeric: true })).forEach(k => {
    const label = groupBy === 'user' ? `Usuário: ${k}` : `Problema: ${k} ${fullOf(groups[k][0].problem_id)}`;
    box.append(el('div', { class: 'group-head' }, label));
    box.append(rowTable(groups[k]));
  });
}

async function doRejudge() {
  const ids = Array.from(selected);
  const msg = document.getElementById('rejudgeMsg');
  if (!ids.length) { msg.innerHTML = '<span class="error-box">Selecione ao menos uma submissão.</span>'; return; }
  const btn = document.getElementById('rejudgeBtn');
  btn.disabled = true; msg.textContent = 'Enviando…';
  try {
    const r = await apiPost('/contest/rejudge?contest=' + encodeURIComponent(CONTEST), { ids }, { contest: CONTEST, auth: true });
    msg.textContent = `✓ Enfileirado para rejulgamento (${(r && r.count) != null ? r.count : ids.length}).`;
    selected.clear(); render();
  } catch (e) {
    msg.innerHTML = '<span class="error-box">Erro: ' + (e && e.message ? e.message : 'falha ao rejulgar') + '</span>';
  } finally { btn.disabled = false; }
}

async function loadSubs() {
  let txt;
  try { txt = await apiGetText('/contest/allsubmissions?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: true }); }
  catch (e) {
    document.getElementById('adminContainer').innerHTML = '<span class="error-box">Falha ao carregar (precisa ser admin).</span>';
    return;
  }
  subs = txt.split('\n').map(s => s.trim()).filter(Boolean).map(parseLine).filter(Boolean)
    .sort((a, b) => Number(b.epoch) - Number(a.epoch));
  render();
}

async function boot() {
  if (!CONTEST) { document.body.innerHTML = '<div class="container"><div class="error-box">Contest não informado (?c=).</div></div>'; return; }
  let basic;
  try { basic = await apiGet('/contest/basic?contest=' + encodeURIComponent(CONTEST), {}); }
  catch { document.body.innerHTML = '<div class="container"><div class="error-box">Contest não encontrado.</div></div>'; return; }

  const st = await status(CONTEST);
  if (!st.logged_in) { location.href = '/contest/?c=' + encodeURIComponent(CONTEST); return; }
  if (!st.is_admin) { document.body.innerHTML = '<div class="container"><div class="notice">Acesso restrito a administradores.</div></div>'; return; }

  const ch = await mountChrome(CONTEST, basic, { auth: true });
  T = ch.T;

  try {
    const j = await apiGet('/contest/problems?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: true });
    problems = Array.isArray(j) ? j : (j.problems || []);
  } catch {}

  document.querySelectorAll('[data-group]').forEach(btn => btn.addEventListener('click', () => { groupBy = btn.dataset.group; render(); }));
  ['fUser', 'fProblem', 'fVerdict'].forEach(id => document.getElementById(id).addEventListener('input', render));
  document.getElementById('markAll').addEventListener('click', () => { filteredSubs().forEach(s => selected.add(s.submission_id)); render(); });
  document.getElementById('rejudgeBtn').addEventListener('click', doRejudge);

  await loadSubs();
}
boot();
