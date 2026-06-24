// contest/judge/judge.js — JUDGE: escolher veredicto final e enviar.
// POST /contest/set-verdict body {problem_id, verdict, username}  (contrato verificado).
// Feed de submissões: /contest/allsubmissions (9 campos) — disponível p/ admin;
// juízes sem admin veem aviso amigável. Veredictos: /contest/final-verdicts {verdicts:[]}.
import { apiGet, apiGetText, apiPost, getToken } from '/shared/api.js';
import { status } from '/shared/auth.js';
import { el, verdictClass, isPending, fmtDate } from '/shared/ui.js';
import { mountChrome } from '/lib/contest-chrome.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
let problems = [];
let subs = [];
let finalVerdicts = [];

function shortOf(pid) { const p = problems.find(x => x.problem_id === pid); return p ? (p.short_name || pid) : pid; }
function fullOf(pid) { const p = problems.find(x => x.problem_id === pid); return p ? (p.full_name || '') : ''; }

function parseLine(line) {
  const v = line.split(':');
  if (v.length < 7) return null;
  return { sinceStart: v[0], username: v[1], problem_id: v[2], lang: v[3], verdict: v[4], epoch: v[5], submission_id: v[6], fullname: v[7] || '', univ: v[8] || '' };
}

async function downloadAuthed(path, filename) {
  try {
    const r = await fetch('/api/v1' + path, { headers: { 'Authorization': 'Bearer ' + getToken(CONTEST) } });
    if (!r.ok) throw 0;
    const a = el('a', { href: URL.createObjectURL(await r.blob()), download: filename }); document.body.append(a); a.click(); a.remove();
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
// abre o report.html (auto-contido) do julgamento num iframe sandboxed (HTML/CSS sim, JS não).
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

function filtered() {
  const fu = document.getElementById('fUser').value.trim().toLowerCase();
  const fp = document.getElementById('fProblem').value.trim().toLowerCase();
  const onlyP = document.getElementById('onlyPending').checked;
  return subs.filter(s => {
    if (onlyP && !isPending(s.verdict)) return false;
    if (fu && !(s.username || '').toLowerCase().includes(fu)) return false;
    if (fp) { const sn = shortOf(s.problem_id).toLowerCase(); if (!sn.includes(fp) && !(s.problem_id || '').toLowerCase().includes(fp)) return false; }
    return true;
  });
}

function render() {
  const box = document.getElementById('judgeContainer');
  box.innerHTML = '';
  const list = filtered();
  if (!list.length) { box.innerHTML = '<span class="muted">Nenhuma submissão.</span>'; return; }

  const head = el('thead', {}, el('tr', {},
    el('th', {}, 'Quando'), el('th', {}, 'Usuário'), el('th', {}, 'Problema'),
    el('th', {}, 'Veredicto inicial'), el('th', {}, 'Veredicto final'),
    el('th', {}, 'Enviar'), el('th', {}, 'Arquivo'), el('th', {}, 'Log')));
  const tb = el('tbody');

  list.forEach(s => {
    const sel = el('select', {}, el('option', { value: '' }, '-- escolha --'),
      ...finalVerdicts.map(v => el('option', { value: v }, v)));
    const btn = el('button', { class: 'btn', type: 'button', disabled: 'disabled' }, 'Enviar');
    const msg = el('span', { class: 'submit-steps' });
    sel.addEventListener('change', () => { btn.disabled = !sel.value; });
    btn.addEventListener('click', async () => {
      btn.disabled = true; msg.textContent = 'Enviando…';
      try {
        await apiPost('/contest/set-verdict?contest=' + encodeURIComponent(CONTEST),
          { problem_id: s.problem_id, verdict: sel.value, username: s.username }, { contest: CONTEST, auth: true });
        msg.textContent = '✓ Enviado!';
      } catch (e) {
        msg.innerHTML = '<span class="error-box">Erro: ' + (e && e.message ? e.message : 'falha') + '</span>';
        btn.disabled = false;
      }
    });

    const pending = isPending(s.verdict);
    tb.append(el('tr', {},
      el('td', {}, el('span', { class: 'small' }, fmtDate(s.epoch))),
      el('td', {}, s.username || '', s.fullname ? el('div', { class: 'small muted' }, s.fullname) : null),
      el('td', {}, el('b', {}, shortOf(s.problem_id)), ' ', el('span', { class: 'small muted' }, fullOf(s.problem_id))),
      el('td', {}, el('span', { class: 'verdict ' + verdictClass(s.verdict) }, pending ? el('span', {}, el('span', { class: 'spin' }), ' ' + s.verdict) : s.verdict)),
      el('td', {}, sel),
      el('td', {}, btn, ' ', msg),
      el('td', {}, el('a', { href: '#', onclick: (e) => { e.preventDefault(); downloadAuthed(`/submission/source?contest=${encodeURIComponent(CONTEST)}&id=${encodeURIComponent(s.submission_id)}&time=${encodeURIComponent(s.epoch)}`, s.submission_id + '.txt'); } }, 'cód')),
      el('td', {}, el('a', { href: '#', onclick: (e) => { e.preventDefault(); openReportAuthed(`/submission/log?contest=${encodeURIComponent(CONTEST)}&id=${encodeURIComponent(s.submission_id)}&time=${encodeURIComponent(s.epoch)}`); } }, s.submission_id.slice(0, 8)))));
  });
  box.append(el('table', { class: 'moj' }, head, tb));
}

async function loadSubs() {
  let txt;
  try { txt = await apiGetText('/contest/allsubmissions?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: true }); }
  catch {
    document.getElementById('judgeContainer').innerHTML =
      '<div class="notice">Não foi possível obter a lista de submissões (o feed completo requer perfil de administrador). ' +
      'O envio de veredicto final continua disponível por problema+usuário via API.</div>';
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
  if (!st.is_judge && !st.is_admin) { document.body.innerHTML = '<div class="container"><div class="notice">Acesso restrito a juízes.</div></div>'; return; }

  await mountChrome(CONTEST, basic, { auth: true });

  const [pj, fv] = await Promise.all([
    apiGet('/contest/problems?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: true }).catch(() => null),
    apiGet('/contest/final-verdicts?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: true }).catch(() => null),
  ]);
  problems = pj ? (Array.isArray(pj) ? pj : (pj.problems || [])) : [];
  finalVerdicts = fv ? (Array.isArray(fv) ? fv : (fv.verdicts || [])) : [];

  ['fUser', 'fProblem'].forEach(id => document.getElementById(id).addEventListener('input', render));
  document.getElementById('onlyPending').addEventListener('change', render);
  document.getElementById('refreshBtn').addEventListener('click', loadSubs);

  await loadSubs();
}
boot();
