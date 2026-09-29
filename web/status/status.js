// status/status.js — página pública de health do MOJ (fila, máquinas, daemons).
import { apiGet } from '/shared/api.js';
import { T, uiLocale } from '/shared/i18n.js';
import { el, renderAuthArea } from '/shared/ui.js';

const app = document.getElementById('app');
const authMount = document.getElementById('authArea');
const refreshAuth = () => renderAuthArea(authMount, 'treino', refreshAuth);

function ind(ok, okText, downText) {
  return el('span', { class: 'ind ' + (ok ? 'ok' : 'down') }, ok ? ('✓ ' + okText) : ('✗ ' + downText));
}

function render(s) {
  app.innerHTML = '';
  const j = s.judge || {}, q = s.queue || {}, d = s.daemons || {};

  // --- saúde geral ---
  const probs = []; let crit = false, warn = false;
  if (s.alert && s.alert.no_judges) { probs.push(T('Há trabalho na fila e nenhum juiz online.', 'There is work in the queue and no judge online.', 'Hay trabajo en la cola y ningún juez en línea.')); crit = true; }
  else if (!j.online) { probs.push(T('Nenhum juiz conectado no momento.', 'No judge connected right now.', 'Ningún juez conectado en este momento.')); warn = true; }
  else if (j.total > j.online) { probs.push((j.total - j.online) + T(' juiz(es) offline.', ' judge(s) offline.', ' juez(es) fuera de línea.')); warn = true; }
  if (!d.judged) { probs.push(T('Daemon de julgamento (judged) parado.', 'Judging daemon (judged) stopped.', 'Demonio de evaluación (judged) detenido.')); warn = true; }
  // bot de alertas: null = instalação sem bot (não é problema); alive:false = o carteiro caiu
  if (s.bot && s.bot.alive === false) { probs.push(T('Bot de alertas (mojinho) sem poll há ' + Math.round((s.bot.last_poll_age_s || 0) / 60) + ' min.', 'Alert bot (mojinho) has not polled for ' + Math.round((s.bot.last_poll_age_s || 0) / 60) + ' min.', 'El bot de alertas (mojinho) no consulta hace ' + Math.round((s.bot.last_poll_age_s || 0) / 60) + ' min.')); warn = true; }
  if ((q.total_pending || 0) > 50) { probs.push(T('Fila grande: ', 'Large queue: ', 'Cola grande: ') + q.total_pending + T(' submissões pendentes.', ' pending submissions.', ' envíos pendientes.')); warn = true; }
  const level = crit ? 'down' : warn ? 'warn' : 'ok';
  const label = crit ? T('Sistema com problemas', 'System with problems', 'Sistema con problemas') : warn ? T('Operação parcial / degradada', 'Partial / degraded operation', 'Operación parcial / degradada') : T('Todos os sistemas operacionais', 'All systems operational', 'Todos los sistemas en funcionamiento');
  app.append(el('div', { class: 'status-banner ' + level },
    el('span', { class: 'status-dot ' + level }),
    el('span', {}, (level === 'ok' ? '🟢 ' : level === 'warn' ? '🟡 ' : '🔴 ') + label)));
  if (probs.length) app.append(el('ul', { class: 'probs' }, ...probs.map((p) => el('li', {}, p))));

  const grid = el('div', { class: 'stat-grid' });

  // --- juízes (modelo pull: registro + heartbeat) ---
  const jc = el('div', { class: 'stat-card' }, el('h3', {}, T('🖥️ Juízes (pull)', '🖥️ Judges (pull)', '🖥️ Jueces (pull)')),
    el('div', { class: 'big-num' }, (j.online || 0) + ' / ' + (j.total || 0)),
    el('div', { class: 'big-sub' }, T('juízes online (heartbeat)', 'judges online (heartbeat)', 'jueces en línea (heartbeat)')),
    el('div', { class: 'kv first' }, el('span', {}, T('Ocupados agora', 'Busy now', 'Ocupados ahora')),
      el('span', { class: 'ind ' + (j.busy ? 'warn' : 'ok') }, String(j.busy || 0))),
    el('div', { class: 'kv' }, el('span', {}, T('CPUs disponíveis', 'CPUs available', 'CPUs disponibles')), el('span', {}, String(j.cpus_online || 0))));
  if (j.gpus_online) jc.append(el('div', { class: 'kv' }, el('span', {}, T('Juízes com GPU', 'Judges with GPU', 'Jueces con GPU')), el('span', {}, String(j.gpus_online))));
  grid.append(jc);

  // --- fila ---
  const qc = el('div', { class: 'stat-card' }, el('h3', {}, T('⏳ Fila de submissões', '⏳ Submission queue', '⏳ Cola de envíos')),
    el('div', { class: 'big-num' }, String(q.total_pending || 0)),
    el('div', { class: 'big-sub' }, T('submissões pendentes', 'pending submissions', 'envíos pendientes')),
    el('div', { class: 'kv first' }, el('span', {}, T('No spool (aguardando daemon)', 'In spool (waiting for daemon)', 'En spool (esperando al demonio)')), el('span', {}, String(q.spool_queued || 0))));
  if (q.lists && q.lists.length) {
    const t = el('table', { class: 'qtable' });
    q.lists.slice(0, 10).forEach((l) => t.append(el('tr', {},
      el('td', {}, l.name || l.contest), el('td', { class: 'n' }, String(l.pending)))));
    qc.append(el('div', { class: 'big-sub', style: 'margin:.7rem 0 0' }, T('Por lista:', 'By list:', 'Por lista:')), t);
  } else {
    qc.append(el('div', { class: 'muted small', style: 'margin-top:.5rem' }, T('nenhuma submissão na fila 🎉', 'no submissions in the queue 🎉', 'no hay envíos en la cola 🎉')));
  }
  grid.append(qc);

  // --- daemons ---
  grid.append(el('div', { class: 'stat-card' }, el('h3', {}, T('⚙️ Daemons & serviços', '⚙️ Daemons & services', '⚙️ Demonios y servicios')),
    el('div', { class: 'kv first' }, el('span', {}, T('API web', 'Web API', 'API web')), el('span', { class: 'ind ok' }, T('✓ no ar', '✓ up', '✓ activo'))),
    el('div', { class: 'kv' }, el('span', {}, T('judged (julgamento)', 'judged (judging)', 'judged (evaluación)')), ind(d.judged, T('rodando', 'running', 'en ejecución'), T('parado', 'stopped', 'detenido'))),
    s.bot ? el('div', { class: 'kv' }, el('span', {}, T('🤖 bot de alertas (mojinho)', '🤖 alert bot (mojinho)', '🤖 bot de alertas (mojinho)')),
      ind(s.bot.alive, T('polando', 'polling', 'consultando'), T('sem poll há ' + Math.round((s.bot.last_poll_age_s || 0) / 60) + ' min', 'no poll for ' + Math.round((s.bot.last_poll_age_s || 0) / 60) + ' min', 'sin consultar hace ' + Math.round((s.bot.last_poll_age_s || 0) / 60) + ' min'))) : ''));

  app.append(grid);
  const when = s.time ? new Date(s.time * 1000).toLocaleTimeString(uiLocale()) : '—';
  app.append(el('div', { class: 'upd' }, T('Atualizado ', 'Updated ', 'Actualizado ') + when + T(' · atualiza a cada 10s', ' · refreshes every 10s', ' · se actualiza cada 10s')));
}

async function tick() {
  try { render(await apiGet('/index/status', {})); }
  catch (e) {
    app.innerHTML = '';
    app.append(el('div', { class: 'status-banner down' }, el('span', { class: 'status-dot down' }),
      el('span', {}, T('🔴 Não foi possível carregar o status: ', '🔴 Could not load the status: ', '🔴 No se pudo cargar el estado: ') + (e.message || T('erro', 'error', 'error')))));
  }
}

refreshAuth();
tick();
setInterval(tick, 10000);
