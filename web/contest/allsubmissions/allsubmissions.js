// contest/allsubmissions/allsubmissions.js — todas as submissões do contest.
// 9 campos: tempo:username:problemid:lang:verdict:epoch:subid:fullname:univ
// admin/chief (FULL): identidade + filtros + multi-seleção -> rejudge ({ids:[...]}).
// .judge/.mon: a API manda os campos de identidade VAZIOS (anônimo) — a UI esconde as
// colunas Usuário/Equipe, o agrupador/filtro por usuário e o rejudge (POST é admin/chief).
import { apiGet, apiGetText, apiPost, getToken } from '/shared/api.js';
import { status } from '/shared/auth.js';
import { el, verdictClass, isPending, fmtDate } from '/shared/ui.js';
import { T } from '/shared/i18n.js';
import { mountChrome } from '/lib/contest-chrome.js';
import { openHtmlReport } from '/shared/submission-links.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
let problems = [];
let subs = [];
let groupBy = 'all';
let selected = new Set();
let FULL = false; // admin/chief = identidade + rejudge; juiz/monitor = lista anônima

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
// abre o report.html do julgamento numa aba nova (openHtmlReport: blob, nunca srcdoc — é o que
// faz as âncoras dos casos de teste rolarem em vez de navegar; ver shared/submission-links.js).
async function openReportAuthed(path) {
  try {
    const r = await fetch('/api/v1' + path, { headers: { 'Authorization': 'Bearer ' + getToken(CONTEST) } });
    openHtmlReport(await r.text());
  } catch { alert(T('Falha ao abrir o report.', 'Failed to open the report.')); }
}

function filteredSubs() {
  const fuEl = document.getElementById('fUser'); // removido no modo anônimo
  const fu = fuEl ? fuEl.value.trim().toLowerCase() : '';
  // ⚠ Problema e veredicto casam por IGUALDADE, não por `includes`. Eram campos de texto que
  // casavam contra o id canônico do pacote (`apc#soma-dos-digitos`), então digitar "a" trazia a
  // letra A e metade da prova junto — relato de juiz, 2026-08-24. Hoje são listas: o valor vem
  // da própria opção, e não há o que digitar errado. O USUÁRIO segue busca livre (é nome).
  const fp = document.getElementById('fProblem').value;
  const fv = document.getElementById('fVerdict').value;
  return subs.filter(s => {
    if (fu && !(s.username || '').toLowerCase().includes(fu)) return false;
    if (fp && s.problem_id !== fp) return false;
    if (fv && vHead(s.verdict) !== fv) return false;
    return true;
  });
}

// head do veredicto: `Accepted,100p` e `Accepted,PE` viram "Accepted"; `Wrong,60p. Pontos | 30 |`
// vira "Wrong". É o mesmo corte que o `by_verdict` das métricas usa (split na vírgula/ponto).
function vHead(v) { return String(v || '').split(',')[0].split('.')[0].trim(); }

// Repovoa os dois seletores preservando a escolha atual (o feed recarrega a cada poll).
// O de problema sai do `/contest/problems` que a página já carrega (letra + título, na ordem da
// prova); o de veredicto, dos valores que REALMENTE aparecem no feed — assim veredicto legado
// ou `Judge Error` entram sozinhos, sem lista fixa para manter.
function fillFilters() {
  const ps = document.getElementById('fProblem'), vs = document.getElementById('fVerdict');
  if (ps) {
    const keep = ps.value;
    ps.innerHTML = '';
    ps.append(el('option', { value: '' }, T('todos os problemas', 'all problems')));
    problems.forEach(p => ps.append(el('option', { value: p.problem_id },
      (p.short_name || p.problem_id) + (p.full_name ? ' · ' + p.full_name : ''))));
    ps.value = keep;
  }
  if (vs) {
    const keep = vs.value;
    const vs_ = [...new Set(subs.map(s => vHead(s.verdict)).filter(Boolean))].sort();
    vs.innerHTML = '';
    vs.append(el('option', { value: '' }, T('todos os veredictos', 'all verdicts')));
    vs_.forEach(v => vs.append(el('option', { value: v }, v)));
    vs.value = keep;
  }
}

function rowTable(items) {
  const head = el('thead', {}, el('tr', {},
    ...(FULL ? [el('th', { style: 'width:1.5rem' }, '')] : []),
    el('th', {}, T('Tempo', 'Time')), el('th', {}, T('Quando', 'When')),
    ...(FULL ? [el('th', {}, T('Usuário', 'User')), el('th', {}, T('Equipe', 'Team'))] : []),
    el('th', {}, T('Problema', 'Problem')), el('th', {}, T('Veredicto', 'Verdict')),
    el('th', {}, T('Arquivo', 'File')), el('th', {}, 'Log')));
  const tb = el('tbody');
  items.forEach(s => {
    const cb = el('input', { type: 'checkbox' });
    cb.checked = selected.has(s.submission_id);
    cb.addEventListener('change', () => { if (cb.checked) selected.add(s.submission_id); else selected.delete(s.submission_id); });
    const pending = isPending(s.verdict);
    tb.append(el('tr', {},
      ...(FULL ? [el('td', {}, cb)] : []),
      el('td', {}, s.sinceStart || ''),
      el('td', {}, el('span', { class: 'small' }, fmtDate(s.epoch))),
      ...(FULL ? [
        el('td', {}, s.username || ''),
        el('td', {}, (s.univ ? `[${s.univ}] ` : '') + (s.fullname || '')),
      ] : []),
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
    document.getElementById('adminContainer').innerHTML = `<span class="error-box">${T('Falha ao carregar (precisa ser admin, juiz-chefe, juiz ou monitor).', 'Failed to load (must be admin, chief judge, judge, or monitor).')}</span>`;
    return;
  }
  subs = txt.split('\n').map(s => s.trim()).filter(Boolean).map(parseLine).filter(Boolean)
    .sort((a, b) => Number(b.epoch) - Number(a.epoch));
  fillFilters();   // o feed recarrega: repovoa as listas preservando a escolha
  render();
}

async function boot() {
  if (!CONTEST) { document.body.innerHTML = `<div class="container"><div class="error-box">${T('Contest não informado (?c=).', 'Contest not specified (?c=).')}</div></div>`; return; }
  let basic;
  try { basic = await apiGet('/contest/basic?contest=' + encodeURIComponent(CONTEST), {}); }
  catch { document.body.innerHTML = `<div class="container"><div class="error-box">${T('Contest não encontrado.', 'Contest not found.')}</div></div>`; return; }

  const st = await status(CONTEST);
  if (!st.logged_in) { location.href = '/contest/?c=' + encodeURIComponent(CONTEST); return; }
  // .mon não vem no /auth/status — mesmo sufixo que o servidor usa; o gate REAL é a API
  const isMon = /\.mon$/.test(st.login || '');
  if (!st.is_admin && !st.is_chief && !st.is_judge && !isMon) { document.body.innerHTML = `<div class="container"><div class="notice">${T('Acesso restrito a administradores, juízes e monitores.', 'Restricted to administrators, judges and monitors.')}</div></div>`; return; }
  FULL = !!(st.is_admin || st.is_chief);

  await mountChrome(CONTEST, basic, { auth: true });

  if (!FULL) {
    // lista anônima: sem usuário/equipe, sem agrupar/filtrar por usuário, sem rejudge
    ['fUser', 'markAll', 'rejudgeBtn', 'rejudgeMsg'].forEach((id) => { const e = document.getElementById(id); if (e) e.remove(); });
    const gu = document.querySelector('[data-group="user"]'); if (gu) gu.remove();
  }

  try {
    const j = await apiGet('/contest/problems?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: true });
    problems = Array.isArray(j) ? j : (j.problems || []);
  } catch {}

  document.querySelectorAll('[data-group]').forEach(btn => btn.addEventListener('click', () => { groupBy = btn.dataset.group; render(); }));
  const fuE = document.getElementById('fUser'); if (fuE) fuE.addEventListener('input', render);
  ['fProblem', 'fVerdict'].forEach(id => { const e = document.getElementById(id); if (e) e.addEventListener('change', render); });
  if (FULL) {
    document.getElementById('markAll').addEventListener('click', () => { filteredSubs().forEach(s => selected.add(s.submission_id)); render(); });
    const clearBtn = el('button', { class: 'btn ghost', onclick: () => { selected.clear(); render(); } }, T('Desmarcar todos', 'Clear selection'));
    document.getElementById('markAll').after(clearBtn);
    document.getElementById('rejudgeBtn').addEventListener('click', doRejudge);
  }

  await loadSubs();
}
boot();
