// treino/editores/editores.js — estatísticas gerais dos editores DECLARADOS pelos
// usuários do treino (campo favorite_editor dos perfis). Lê /treino/editor-stats.
import { apiGet } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { editorLabel } from '/shared/editors.js';
import { hBarChart } from '/lib/charts.js';
import { T } from '/shared/i18n.js';

const app = document.getElementById('app');

function statCard(big, sub) {
  return el('div', { class: 'stat-card' }, el('div', { class: 'big-num' }, String(big)), el('div', { class: 'big-sub' }, sub));
}

async function boot() {
  let s;
  try { s = await apiGet('/treino/editor-stats', {}); }
  catch { app.innerHTML = `<div class="error-box">${T('Não foi possível carregar as estatísticas.', 'Could not load statistics.', 'No se pudieron cargar las estadísticas.')}</div>`; return; }
  const ranking = (s.ranking || []).filter((r) => r.count > 0);
  const declared = s.declared || 0, total = s.total_users || 0;
  document.getElementById('ed-sub').textContent = declared
    ? T(`${declared} de ${total} usuários declararam um editor favorito (${total ? Math.round((declared / total) * 100) : 0}%).`,
        `${declared} of ${total} users declared a favorite editor (${total ? Math.round((declared / total) * 100) : 0}%).`,
        `${declared} de ${total} usuarios declararon un editor favorito (${total ? Math.round((declared / total) * 100) : 0}%).`)
    : T('Ninguém declarou um editor favorito ainda.', 'No one has declared a favorite editor yet.', 'Nadie declaró un editor favorito todavía.');
  app.innerHTML = '';
  if (!ranking.length) {
    app.innerHTML = T('Nenhum editor declarado ainda — seja o primeiro no seu <a href="/treino/perfil/">perfil</a>.', 'No editor declared yet — be the first on your <a href="/treino/perfil/">profile</a>.', 'Ningún editor declarado todavía — sé el primero en tu <a href="/treino/perfil/">perfil</a>.');
    app.className = 'muted'; return;
  }

  const top = ranking[0];
  app.append(el('div', { class: 'stat-cards' },
    statCard(declared, T('declararam', 'declared', 'declararon')),
    statCard(ranking.length, ranking.length === 1 ? T('editor distinto', 'distinct editor', 'editor distinto') : T('editores distintos', 'distinct editors', 'editores distintos')),
    statCard(editorLabel(top.editor), T('mais popular', 'most popular', 'más popular'))));

  // distribuição (barras horizontais — boas p/ nomes de editor longos)
  app.append(el('div', { class: 'section' }, el('h2', {}, T('Distribuição', 'Distribution', 'Distribución')),
    hBarChart(ranking.map((r) => ({ label: editorLabel(r.editor), value: r.count })), { hideZero: true, total: declared })));

  // ranking detalhado
  const tb = el('tbody');
  ranking.forEach((r, i) => tb.append(el('tr', {},
    el('td', { class: 'n' }, String(i + 1)),
    el('td', {}, editorLabel(r.editor)),
    el('td', { class: 'n' }, String(r.count)),
    el('td', { class: 'n' }, (declared ? Math.round((r.count / declared) * 100) : 0) + '%'))));
  app.append(el('div', { class: 'section' }, el('h2', {}, T('Ranking', 'Ranking', 'Ranking')),
    el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', { class: 'n' }, '#'), el('th', {}, T('Editor', 'Editor', 'Editor')), el('th', { class: 'n' }, T('Usuários', 'Users', 'Usuarios')), el('th', { class: 'n' }, '%'))),
      tb))));
}

boot();
