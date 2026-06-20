// contest/statistics/statistics.js — estatísticas do contest (admin).
// Usa o feed /contest/allsubmissions (9 campos) p/ montar pizzas/barras por
// problema, linguagem e veredicto. Gráficos em SVG (sem libs), via /lib/charts.js.
import { apiGet, apiGetText } from '/shared/api.js';
import { status } from '/shared/auth.js';
import { el } from '/shared/ui.js';
import { mountChrome } from '/lib/contest-chrome.js';
import { pieChart } from '/lib/charts.js';

const qs = new URLSearchParams(location.search);
const CONTEST = qs.get('c') || '';
let problems = [];
let subs = [];

function shortOf(pid) { const p = problems.find(x => x.problem_id === pid); return p ? (p.short_name || pid) : pid; }
function normVerdict(s) {
  s = (s || '').trim();
  if (/^accepted/i.test(s)) return 'Accepted';
  if (/^wrong/i.test(s)) return 'Wrong Answer';
  if (/^time limit/i.test(s)) return 'Time Limit Exceeded';
  if (/^(possible runtime|runtime)/i.test(s)) return 'Runtime Error';
  if (/^(compilation error|language)/i.test(s)) return 'Compilation Error';
  if (/(not answered|queue|running)/i.test(s)) return 'Pending';
  return s.replace(/,.*/, '').trim();
}
function parseLine(line) {
  const v = line.split(':');
  if (v.length < 7) return null;
  return { username: v[1], problem_id: v[2], lang: v[3], verdict: v[4], epoch: v[5], submission_id: v[6] };
}

function compute() {
  const byProb = {}, byLang = {}, byVerdict = {};
  subs.forEach(s => {
    const sn = shortOf(s.problem_id);
    if (!byProb[sn]) byProb[sn] = { total: 0, accepted: 0 };
    byProb[sn].total++;
    const v = normVerdict(s.verdict);
    if (v === 'Accepted') byProb[sn].accepted++;
    byLang[s.lang] = (byLang[s.lang] || 0) + 1;
    byVerdict[v] = (byVerdict[v] || 0) + 1;
  });
  return { byProb, byLang, byVerdict };
}

function render() {
  const stats = compute();
  // tabela por problema
  const probKeys = Object.keys(stats.byProb).sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
  const tbl = el('table', { class: 'moj' },
    el('thead', {}, el('tr', {}, el('th', {}, 'Problema'), el('th', {}, 'Submissões'), el('th', {}, 'Accepted'), el('th', {}, 'Taxa (%)'))),
    el('tbody', {}, ...probKeys.map(k => {
      const t = stats.byProb[k].total, a = stats.byProb[k].accepted;
      return el('tr', {}, el('td', {}, k), el('td', {}, String(t)), el('td', {}, String(a)), el('td', {}, t ? ((a / t) * 100).toFixed(1) : '—'));
    })));
  const pt = document.getElementById('problemTable'); pt.innerHTML = '';
  if (!probKeys.length) pt.innerHTML = '<span class="muted">Sem submissões.</span>';
  else pt.append(tbl);

  // pizzas
  const set = (id, data, opts) => { const e = document.getElementById(id); e.innerHTML = ''; e.append(pieChart(data, opts || {})); };
  set('pieSubs', probKeys.map(k => ({ label: k, value: stats.byProb[k].total })));
  set('pieAcc', probKeys.map(k => ({ label: k, value: stats.byProb[k].accepted })));
  set('pieLang', Object.entries(stats.byLang).map(([k, v]) => ({ label: k, value: v })));
  const vColor = (v) => v === 'Accepted' ? '#1a7f37' : v === 'Wrong Answer' ? '#c4314b'
    : v === 'Time Limit Exceeded' ? '#a66a00' : v === 'Runtime Error' ? '#ef8a56'
      : v === 'Compilation Error' ? '#7a5ada' : v === 'Pending' ? '#5b6b7d' : '#23b0de';
  set('pieVerdict', Object.entries(stats.byVerdict).map(([k, v]) => ({ label: k, value: v, color: vColor(k) })), { donut: 0.5 });
}

async function loadSubs() {
  let txt;
  try { txt = await apiGetText('/contest/allsubmissions?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: true }); }
  catch {
    document.getElementById('problemTable').innerHTML = '<span class="error-box">Falha ao carregar (precisa ser admin).</span>';
    return;
  }
  subs = txt.split('\n').map(s => s.trim()).filter(Boolean).map(parseLine).filter(Boolean);
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

  await mountChrome(CONTEST, basic, { auth: true });
  try {
    const j = await apiGet('/contest/problems?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: true });
    problems = Array.isArray(j) ? j : (j.problems || []);
  } catch {}
  await loadSubs();
}
boot();
