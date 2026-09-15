// contest/submissions/submissions.js — página própria "Minhas submissões" (issue #26): a MESMA
// tabela da seção do fim da página do contest (contest/submissions-table.js), sem os problemas
// em cima empurrando-a para fora da tela. Competidor logado; quem não está vai ao login.
import { apiGet } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { initContestShell } from '/shared/contest-shell.js';
import { makeSubmissionsTable } from '/contest/submissions-table.js';
import { T } from '/shared/i18n.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const enc = encodeURIComponent;
const G = { contest: CONTEST, auth: true };

async function boot() {
  const tableEl = document.getElementById('submissionsTable');
  if (!CONTEST) { tableEl.innerHTML = '<div class="error-box">' + T('Contest não informado.', 'Contest not specified.') + '</div>'; return; }
  const { basic, st } = await initContestShell(CONTEST);
  if (!st || !st.logged_in) { location.href = '/contest/?c=' + enc(CONTEST); return; }
  const [pr, ui] = await Promise.all([
    apiGet('/contest/problems?contest=' + enc(CONTEST), G).catch(() => null),
    apiGet('/contest/userinfo?contest=' + enc(CONTEST), G).catch(() => null),
  ]);
  const problems = pr ? (Array.isArray(pr) ? pr : (pr.problems || [])) : [];
  const table = makeSubmissionsTable({ contest: CONTEST, basic, problems, userinfo: ui,
    filterEl: document.getElementById('subFilter'), tableEl });
  await table.load();
  if (!table.submissions.length) tableEl.append(el('p', { class: 'small muted' },
    T('Para enviar uma solução, use a página do contest.', 'To submit a solution, use the contest page.')));
  window.addEventListener('pagehide', () => table.stop());
}
boot();
