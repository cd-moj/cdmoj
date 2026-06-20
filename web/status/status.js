// status/status.js — página pública de health do MOJ (fila, máquinas, daemons).
import { apiGet } from '/shared/api.js';
import { el, renderAuthArea } from '/shared/ui.js';
import { renderCreateContestLink } from '/shared/create-contest-link.js';

const app = document.getElementById('app');
const authMount = document.getElementById('authArea');
const refreshAuth = () => renderAuthArea(authMount, 'treino', refreshAuth)
  .then(() => renderCreateContestLink(authMount));

function ind(ok, okText, downText) {
  return el('span', { class: 'ind ' + (ok ? 'ok' : 'down') }, ok ? ('✓ ' + okText) : ('✗ ' + downText));
}

function render(s) {
  app.innerHTML = '';
  const j = s.judge || {}, q = s.queue || {}, d = s.daemons || {};

  // --- saúde geral ---
  const probs = []; let crit = false, warn = false;
  if (!j.master_up) { probs.push('Escalonador de julgamento (:27000) fora do ar.'); crit = true; }
  else if (!j.machines_online) { probs.push('Nenhuma máquina julgando no momento.'); crit = true; }
  else if (j.machines_total > j.machines_online) { probs.push((j.machines_total - j.machines_online) + ' máquina(s) de julgamento offline.'); warn = true; }
  if (!d.judged) { probs.push('Daemon de julgamento (judged) parado.'); warn = true; }
  if ((q.total_pending || 0) > 50) { probs.push('Fila grande: ' + q.total_pending + ' submissões pendentes.'); warn = true; }
  const level = crit ? 'down' : warn ? 'warn' : 'ok';
  const label = crit ? 'Sistema com problemas' : warn ? 'Operação parcial / degradada' : 'Todos os sistemas operacionais';
  app.append(el('div', { class: 'status-banner ' + level },
    el('span', { class: 'status-dot ' + level }),
    el('span', {}, (level === 'ok' ? '🟢 ' : level === 'warn' ? '🟡 ' : '🔴 ') + label)));
  if (probs.length) app.append(el('ul', { class: 'probs' }, ...probs.map((p) => el('li', {}, p))));

  const grid = el('div', { class: 'stat-grid' });

  // --- máquinas / escalonador ---
  const jc = el('div', { class: 'stat-card' }, el('h3', {}, '🖥️ Máquinas de julgamento'),
    el('div', { class: 'big-num' }, (j.machines_online || 0) + ' / ' + (j.machines_total || 0)),
    el('div', { class: 'big-sub' }, 'máquinas julgando'),
    el('div', { class: 'kv first' }, el('span', {}, 'Escalonador (:27000)'), ind(j.master_up, 'no ar', 'fora do ar')),
    el('div', { class: 'kv' }, el('span', {}, 'Estado'),
      el('span', { class: 'ind ' + (j.busy ? 'warn' : 'ok') }, j.busy ? 'ocupado' : 'livre')));
  if (j.workers_registered) jc.append(el('div', { class: 'kv' },
    el('span', {}, 'Workers registrados (push)'), el('span', {}, String(j.workers_registered))));
  grid.append(jc);

  // --- fila ---
  const qc = el('div', { class: 'stat-card' }, el('h3', {}, '⏳ Fila de submissões'),
    el('div', { class: 'big-num' }, String(q.total_pending || 0)),
    el('div', { class: 'big-sub' }, 'submissões pendentes'),
    el('div', { class: 'kv first' }, el('span', {}, 'No spool (aguardando daemon)'), el('span', {}, String(q.spool_queued || 0))));
  if (q.lists && q.lists.length) {
    const t = el('table', { class: 'qtable' });
    q.lists.slice(0, 10).forEach((l) => t.append(el('tr', {},
      el('td', {}, l.name || l.contest), el('td', { class: 'n' }, String(l.pending)))));
    qc.append(el('div', { class: 'big-sub', style: 'margin:.7rem 0 0' }, 'Por lista:'), t);
  } else {
    qc.append(el('div', { class: 'muted small', style: 'margin-top:.5rem' }, 'nenhuma submissão na fila 🎉'));
  }
  grid.append(qc);

  // --- daemons ---
  grid.append(el('div', { class: 'stat-card' }, el('h3', {}, '⚙️ Daemons & serviços'),
    el('div', { class: 'kv first' }, el('span', {}, 'API web'), el('span', { class: 'ind ok' }, '✓ no ar')),
    el('div', { class: 'kv' }, el('span', {}, 'judged (julgamento)'), ind(d.judged, 'rodando', 'parado')),
    el('div', { class: 'kv' }, el('span', {}, 'result-sink (resultados)'), ind(d.result_sink, 'rodando', 'parado'))));

  app.append(grid);
  const when = s.time ? new Date(s.time * 1000).toLocaleTimeString('pt-BR') : '—';
  app.append(el('div', { class: 'upd' }, 'Atualizado ' + when + ' · atualiza a cada 10s'));
}

async function tick() {
  try { render(await apiGet('/index/status', {})); }
  catch (e) {
    app.innerHTML = '';
    app.append(el('div', { class: 'status-banner down' }, el('span', { class: 'status-dot down' }),
      el('span', {}, '🔴 Não foi possível carregar o status: ' + (e.message || 'erro'))));
  }
}

refreshAuth();
tick();
setInterval(tick, 10000);
