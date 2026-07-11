// status/status.js — página pública de health do MOJ (fila, máquinas, daemons).
import { apiGet } from '/shared/api.js';
import { T } from '/shared/i18n.js';
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
  if (s.alert && s.alert.no_judges) { probs.push(T('Há trabalho na fila e nenhum juiz online.', 'There is work in the queue and no judge online.')); crit = true; }
  else if (!j.online) { probs.push(T('Nenhum juiz conectado no momento.', 'No judge connected right now.')); warn = true; }
  else if (j.total > j.online) { probs.push((j.total - j.online) + T(' juiz(es) offline.', ' judge(s) offline.')); warn = true; }
  if (!d.judged) { probs.push(T('Daemon de julgamento (judged) parado.', 'Judging daemon (judged) stopped.')); warn = true; }
  if ((q.total_pending || 0) > 50) { probs.push(T('Fila grande: ', 'Large queue: ') + q.total_pending + T(' submissões pendentes.', ' pending submissions.')); warn = true; }
  const level = crit ? 'down' : warn ? 'warn' : 'ok';
  const label = crit ? T('Sistema com problemas', 'System with problems') : warn ? T('Operação parcial / degradada', 'Partial / degraded operation') : T('Todos os sistemas operacionais', 'All systems operational');
  app.append(el('div', { class: 'status-banner ' + level },
    el('span', { class: 'status-dot ' + level }),
    el('span', {}, (level === 'ok' ? '🟢 ' : level === 'warn' ? '🟡 ' : '🔴 ') + label)));
  if (probs.length) app.append(el('ul', { class: 'probs' }, ...probs.map((p) => el('li', {}, p))));

  const grid = el('div', { class: 'stat-grid' });

  // --- juízes (modelo pull: registro + heartbeat) ---
  const jc = el('div', { class: 'stat-card' }, el('h3', {}, T('🖥️ Juízes (pull)', '🖥️ Judges (pull)')),
    el('div', { class: 'big-num' }, (j.online || 0) + ' / ' + (j.total || 0)),
    el('div', { class: 'big-sub' }, T('juízes online (heartbeat)', 'judges online (heartbeat)')),
    el('div', { class: 'kv first' }, el('span', {}, T('Ocupados agora', 'Busy now')),
      el('span', { class: 'ind ' + (j.busy ? 'warn' : 'ok') }, String(j.busy || 0))),
    el('div', { class: 'kv' }, el('span', {}, T('CPUs disponíveis', 'CPUs available')), el('span', {}, String(j.cpus_online || 0))));
  if (j.gpus_online) jc.append(el('div', { class: 'kv' }, el('span', {}, T('Juízes com GPU', 'Judges with GPU')), el('span', {}, String(j.gpus_online))));
  grid.append(jc);

  // --- fila ---
  const qc = el('div', { class: 'stat-card' }, el('h3', {}, T('⏳ Fila de submissões', '⏳ Submission queue')),
    el('div', { class: 'big-num' }, String(q.total_pending || 0)),
    el('div', { class: 'big-sub' }, T('submissões pendentes', 'pending submissions')),
    el('div', { class: 'kv first' }, el('span', {}, T('No spool (aguardando daemon)', 'In spool (waiting for daemon)')), el('span', {}, String(q.spool_queued || 0))));
  if (q.lists && q.lists.length) {
    const t = el('table', { class: 'qtable' });
    q.lists.slice(0, 10).forEach((l) => t.append(el('tr', {},
      el('td', {}, l.name || l.contest), el('td', { class: 'n' }, String(l.pending)))));
    qc.append(el('div', { class: 'big-sub', style: 'margin:.7rem 0 0' }, T('Por lista:', 'By list:')), t);
  } else {
    qc.append(el('div', { class: 'muted small', style: 'margin-top:.5rem' }, T('nenhuma submissão na fila 🎉', 'no submissions in the queue 🎉')));
  }
  grid.append(qc);

  // --- daemons ---
  grid.append(el('div', { class: 'stat-card' }, el('h3', {}, T('⚙️ Daemons & serviços', '⚙️ Daemons & services')),
    el('div', { class: 'kv first' }, el('span', {}, T('API web', 'Web API')), el('span', { class: 'ind ok' }, T('✓ no ar', '✓ up'))),
    el('div', { class: 'kv' }, el('span', {}, T('judged (julgamento)', 'judged (judging)')), ind(d.judged, T('rodando', 'running'), T('parado', 'stopped')))));

  app.append(grid);
  const when = s.time ? new Date(s.time * 1000).toLocaleTimeString('pt-BR') : '—';
  app.append(el('div', { class: 'upd' }, T('Atualizado ', 'Updated ') + when + T(' · atualiza a cada 10s', ' · refreshes every 10s')));
}

async function tick() {
  try { render(await apiGet('/index/status', {})); }
  catch (e) {
    app.innerHTML = '';
    app.append(el('div', { class: 'status-banner down' }, el('span', { class: 'status-dot down' }),
      el('span', {}, T('🔴 Não foi possível carregar o status: ', '🔴 Could not load the status: ') + (e.message || T('erro', 'error')))));
  }
}

refreshAuth();
tick();
setInterval(tick, 10000);
