// contest/statistics/statistics.js — estatísticas ricas do contest (admin/juiz/monitor).
// As SEÇÕES moram em /lib/stats-view.js: o relatório offline (server/score/report-gen.sh)
// inlina o mesmo módulo, então as duas telas não podem divergir.
import { apiGet } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { mountChrome } from '/lib/contest-chrome.js';
import { statsSections } from '/lib/stats-view.js';
import { T } from '/shared/i18n.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const enc = encodeURIComponent;
let probMap = {};

function render(s) {
  app.innerHTML = '';
  statsSections(s, { probMap }).forEach((sec) => app.append(sec));
}

async function boot() {
  if (!CONTEST) { app.innerHTML = '<div class="error-box">' + T('Contest não informado.', 'Contest not specified.') + '</div>'; return; }
  let basic = null;
  try { basic = await apiGet('/contest/basic?contest=' + enc(CONTEST), {}); } catch { /* segue */ }
  try { await mountChrome(CONTEST, basic); } catch { /* nav opcional */ }
  let s;
  try { s = await apiGet('/contest/statistics?contest=' + enc(CONTEST), { contest: CONTEST, auth: true }); }
  catch (e) {
    app.innerHTML = '';
    app.append(el('div', { class: 'section' }, el('h2', {}, T('🔒 Restrito', '🔒 Restricted')),
      el('p', { class: 'muted' }, T('Estatísticas são visíveis a admin, juiz ou monitor do contest. (', 'Statistics are visible to the contest admin, judge or monitor. (') + (e.message || T('erro', 'error')) + ')')));
    return;
  }
  try { const pr = await apiGet('/contest/problems?contest=' + enc(CONTEST), { contest: CONTEST, auth: true }); (pr.problems || []).forEach((p) => { probMap[p.problem_id] = p.short_name; }); } catch { /* sem map */ }
  render(s);
}
boot();
