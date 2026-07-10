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
  if (s.alert && s.alert.no_judges) { probs.push('Há trabalho na fila e nenhum juiz online.'); crit = true; }
  else if (!j.online) { probs.push('Nenhum juiz conectado no momento.'); warn = true; }
  else if (j.total > j.online) { probs.push((j.total - j.online) + ' juiz(es) offline.'); warn = true; }
  if (!d.judged) { probs.push('Daemon de julgamento (judged) parado.'); warn = true; }
  if ((q.total_pending || 0) > 50) { probs.push('Fila grande: ' + q.total_pending + ' submissões pendentes.'); warn = true; }
  const level = crit ? 'down' : warn ? 'warn' : 'ok';
  const label = crit ? 'Sistema com problemas' : warn ? 'Operação parcial / degradada' : 'Todos os sistemas operacionais';
  app.append(el('div', { class: 'status-banner ' + level },
    el('span', { class: 'status-dot ' + level }),
    el('span', {}, (level === 'ok' ? '🟢 ' : level === 'warn' ? '🟡 ' : '🔴 ') + label)));
  if (probs.length) app.append(el('ul', { class: 'probs' }, ...probs.map((p) => el('li', {}, p))));

  const grid = el('div', { class: 'stat-grid' });

  // --- juízes (modelo pull: registro + heartbeat) ---
  const jc = el('div', { class: 'stat-card' }, el('h3', {}, '🖥️ Juízes (pull)'),
    el('div', { class: 'big-num' }, (j.online || 0) + ' / ' + (j.total || 0)),
    el('div', { class: 'big-sub' }, 'juízes online (heartbeat)'),
    el('div', { class: 'kv first' }, el('span', {}, 'Ocupados agora'),
      el('span', { class: 'ind ' + (j.busy ? 'warn' : 'ok') }, String(j.busy || 0))),
    el('div', { class: 'kv' }, el('span', {}, 'CPUs disponíveis'), el('span', {}, String(j.cpus_online || 0))));
  if (j.gpus_online) jc.append(el('div', { class: 'kv' }, el('span', {}, 'Juízes com GPU'), el('span', {}, String(j.gpus_online))));
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
    el('div', { class: 'kv' }, el('span', {}, 'judged (julgamento)'), ind(d.judged, 'rodando', 'parado'))));

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
