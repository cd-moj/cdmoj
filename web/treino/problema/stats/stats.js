// treino/problema/stats/stats.js — estatísticas de um problema do Treino Livre.
import { apiGet } from '/shared/api.js';
import { el, avatarEl, renderAuthArea } from '/shared/ui.js';
import { barChart, pieChart } from '/lib/charts.js';
import { langById } from '/shared/languages.js';
import { editorLabel } from '/shared/editors.js';

const CONTEST = 'treino';
const ID = new URLSearchParams(location.search).get('id') || '';
const langLabel = (l) => (langById(String(l || '').toLowerCase()) || {}).label || l || '?';
const pct = (x) => Math.round((x || 0) * 100) + '%';
const isKnownLang = (l) => l && langById(String(l).toLowerCase());
const langDisplay = (l) => (l === 'outro' ? 'Outros (ext. não reconhecidas)' : langLabel(l));
// junta tokens de linguagem não reconhecidos (olamundo, txt, exe, …) num único "Outros"
function cleanLangs(byLang) {
  const out = []; let other = null;
  (byLang || []).forEach((l) => {
    if (isKnownLang(l.lang)) out.push(l);
    else {
      other = other || { lang: 'outro', submissions: 0, accepted: 0, solvers: 0 };
      other.submissions += l.submissions || 0; other.accepted += l.accepted || 0; other.solvers += l.solvers || 0;
    }
  });
  if (other) out.push(other);
  return out.sort((a, b) => b.submissions - a.submissions);
}

function metric(v, l) { return el('div', { class: 'metric' }, el('div', { class: 'v' }, String(v)), el('div', { class: 'l' }, l)); }
function chartCard(title, node) {
  return el('div', { class: 'subcard' }, el('h3', { class: 'small', style: 'margin:.1rem 0 .6rem;color:var(--blue-dark)' }, title), node);
}
function verdictColor(v) {
  const s = (v || '').toLowerCase();
  if (s.startsWith('accepted')) return '#15803d';
  if (s.startsWith('wrong')) return '#be1241';
  if (s.startsWith('time')) return '#9a6700';
  if (s.startsWith('runtime')) return '#d94f9a';
  if (s.startsWith('compil')) return '#7a5ada';
  return '#94a3b8';
}

async function boot() {
  await renderAuthArea(document.getElementById('authArea'), CONTEST, () => {});
  const content = document.getElementById('content');
  if (!ID) { content.innerHTML = '<div class="notice">Faltou informar ?id=&lt;problema&gt;.</div>'; return; }

  let s;
  try { s = await apiGet('/treino/problem-stats?id=' + encodeURIComponent(ID), { contest: CONTEST }); }
  catch { content.innerHTML = '<div class="error-box">Falha ao carregar as estatísticas.</div>'; return; }
  content.innerHTML = '';

  content.append(el('div', { class: 'section' },
    el('h1', { style: 'margin:0;color:var(--blue-dark)' }, '📊 ', s.title || ID),
    el('p', { class: 'small muted', style: 'margin:.3rem 0 0' }, 'Problema do Treino Livre · ',
      el('a', { href: '/treino/problema/?id=' + encodeURIComponent(ID) }, 'abrir o problema →'))));

  if (!s.total_submissions) {
    content.append(el('div', { class: 'section muted' }, 'Ainda não há submissões para este problema.'));
    return;
  }

  // --- resumo ---
  const ar = s.acceptance_rate || 0;
  const diff = ar >= 0.9 ? 'muito fácil' : ar >= 0.7 ? 'fácil' : ar >= 0.5 ? 'médio' : 'difícil';
  content.append(el('div', { class: 'section' },
    el('h2', {}, 'Resumo'),
    el('div', { class: 'metrics' },
      metric(s.total_submissions, 'submissões'),
      metric(s.distinct_attempted, 'tentaram'),
      metric(s.distinct_solved, 'resolveram'),
      metric(pct(ar), 'taxa de acerto'),
      metric((s.avg_submissions_per_user || 0).toFixed(1), 'subs / usuário'),
      metric(diff, 'dificuldade'))));

  // --- distribuições ---
  const vData = (s.verdicts || []).map((v) => ({ label: v.verdict, value: v.count, color: verdictColor(v.verdict) }));
  const bl = cleanLangs(s.by_language);
  const slData = bl.filter((l) => l.solvers > 0).map((l) => ({ label: langDisplay(l.lang), value: l.solvers }));
  content.append(el('div', { class: 'section' }, el('h2', {}, 'Distribuições'),
    el('div', { class: 'chart-grid' },
      chartCard('Veredictos', pieChart(vData, { size: 240, donut: 0.55 })),
      chartCard('Resolvedores distintos por linguagem',
        barChart(slData, { width: 460, height: 240, color: '#216097', rotateLabels: true })))));

  // --- tabela por linguagem ---
  const tb = el('tbody');
  bl.forEach((l) => tb.append(el('tr', {},
    el('td', {}, langDisplay(l.lang)),
    el('td', {}, String(l.submissions)),
    el('td', {}, String(l.accepted)),
    el('td', {}, l.submissions ? pct(l.accepted / l.submissions) : '-'),
    el('td', {}, String(l.solvers)))));
  content.append(el('div', { class: 'section' }, el('h2', {}, 'Por linguagem'),
    el('p', { class: 'small muted', style: 'margin:0 0 .5rem' }, '"Resolveram" = usuários distintos que acertaram com aquela linguagem.'),
    el('table', { class: 'moj' }, el('thead', {}, el('tr', {},
      el('th', {}, 'Linguagem'), el('th', {}, 'Submissões'), el('th', {}, 'Aceitas'),
      el('th', {}, 'Taxa'), el('th', {}, 'Resolveram'))), tb)));

  // --- editores declarados pelos solvers ---
  if ((s.editors || []).length) {
    const eData = s.editors.map((e) => ({ label: editorLabel(e.editor), value: e.count }));
    content.append(el('div', { class: 'section' }, el('h2', {}, '⌨ Editores de quem resolveu'),
      el('div', { class: 'chart-grid' }, chartCard('Editores declarados', pieChart(eData, { size: 240 })))));
  }

  // --- nuvem de avatares (solvers públicos) ---
  const avs = s.solver_avatars || [];
  if (avs.length) {
    const cloud = el('div', { class: 'avatar-cloud' });
    avs.forEach((a) => cloud.append(
      el('a', { href: '/treino/stat/?user=' + encodeURIComponent(a.login), title: a.name || a.login }, avatarEl(a.login, a.name, 40, a.has_photo))));
    const total = s.solvers_public_count || avs.length;
    const more = total - avs.length;
    content.append(el('div', { class: 'section' },
      el('h2', {}, '👥 Quem resolveu ', el('span', { class: 'small muted' }, `(${total} com perfil público)`)),
      cloud,
      more > 0 ? el('p', { class: 'small muted', style: 'margin-top:.5rem' }, `+${more} outros`) : null));
  }
}
boot();
