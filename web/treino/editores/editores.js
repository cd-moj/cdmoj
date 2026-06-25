// treino/editores/editores.js — estatísticas gerais dos editores DECLARADOS pelos
// usuários do treino (campo favorite_editor dos perfis). Lê /treino/editor-stats.
import { apiGet } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { editorLabel } from '/shared/editors.js';
import { hBarChart } from '/lib/charts.js';

const app = document.getElementById('app');

function statCard(big, sub) {
  return el('div', { class: 'stat-card' }, el('div', { class: 'big-num' }, String(big)), el('div', { class: 'big-sub' }, sub));
}

async function boot() {
  let s;
  try { s = await apiGet('/treino/editor-stats', {}); }
  catch { app.innerHTML = '<div class="error-box">Não foi possível carregar as estatísticas.</div>'; return; }
  const ranking = (s.ranking || []).filter((r) => r.count > 0);
  const declared = s.declared || 0, total = s.total_users || 0;
  document.getElementById('ed-sub').textContent = declared
    ? `${declared} de ${total} usuários declararam um editor favorito (${total ? Math.round((declared / total) * 100) : 0}%).`
    : 'Ninguém declarou um editor favorito ainda.';
  app.innerHTML = '';
  if (!ranking.length) {
    app.innerHTML = 'Nenhum editor declarado ainda — seja o primeiro no seu <a href="/treino/perfil/">perfil</a>.';
    app.className = 'muted'; return;
  }

  const top = ranking[0];
  app.append(el('div', { class: 'stat-cards' },
    statCard(declared, 'declararam'),
    statCard(ranking.length, ranking.length === 1 ? 'editor distinto' : 'editores distintos'),
    statCard(editorLabel(top.editor), 'mais popular')));

  // distribuição (barras horizontais — boas p/ nomes de editor longos)
  app.append(el('div', { class: 'section' }, el('h2', {}, 'Distribuição'),
    hBarChart(ranking.map((r) => ({ label: editorLabel(r.editor), value: r.count })), { hideZero: true, total: declared })));

  // ranking detalhado
  const tb = el('tbody');
  ranking.forEach((r, i) => tb.append(el('tr', {},
    el('td', { class: 'n' }, String(i + 1)),
    el('td', {}, editorLabel(r.editor)),
    el('td', { class: 'n' }, String(r.count)),
    el('td', { class: 'n' }, (declared ? Math.round((r.count / declared) * 100) : 0) + '%'))));
  app.append(el('div', { class: 'section' }, el('h2', {}, 'Ranking'),
    el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', { class: 'n' }, '#'), el('th', {}, 'Editor'), el('th', { class: 'n' }, 'Usuários'), el('th', { class: 'n' }, '%'))),
      tb))));
}

boot();
