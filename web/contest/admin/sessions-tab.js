// contest/admin/sessions-tab.js — "Pessoas › Sessões": quem está logado neste contest e o
// controle de entrada: 🚪 sair em massa + trava de login (fechar/reabrir), a lista de sessões
// ativas (com deslogar) e o log de acessos do dia. Vale p/ QUALQUER contest — o fim de uma prova
// de sala é exatamente "fecha o login, derruba todo mundo".
// As ANOMALIAS de uso de máquina (gate de UA, sessão única, máquina compartilhada, trava de sede)
// são do módulo `maquinas` e moram em Máquinas › Anomalias (anomalies-tab.js).
//
// ATUALIZAÇÃO EM LUGAR (regra da casa): esqueleto uma vez; a cada 30 s só troca o que mudou
// (assinatura); o filtro de UA e o dia do log são nós persistentes.
import { el } from '/shared/ui.js';
import { apiGet, apiPost } from '/shared/api.js';
import { fmtDate, todayStr, stamp, toCsv, downloadText, swapIf, sigOf, everyVisible } from '/shared/admin-ui.js';
import { T, uiLocale } from '/shared/i18n.js';
import { REFRESH_MS, mk, makeLogoutUser } from './sessions-common.js';

const enc = encodeURIComponent;

export function makeSessionsTab(CONTEST, opts = {}) {
  const G = { contest: CONTEST, auth: true };
  const has = typeof opts.has === 'function' ? opts.has : () => true;
  const panel = el('div', {});
  let LOGALL = null, SESS = [], stopTimer = null;
  const logoutUser = makeLogoutUser(CONTEST, G, () => load());

  // --- 1. sair em massa + trava de login ------------------------------------------------------
  function massLogout() {
    const st = LOGALL || {};
    const box = el('div', {});
    // "aberto" de verdade = ligado E já passou da abertura do login (servidor antigo: só o ligado)
    const open = ('login_open_now' in st) ? st.login_open_now === true : st.login_enabled !== false;
    const waitsStart = st.login_enabled !== false && !open;
    const msg = el('span', { class: 'small' });
    const closeChk = el('input', { type: 'checkbox', checked: true });
    const run = async (body, label) => {
      if (!confirm(label)) return;
      msg.textContent = '…';
      try {
        const r = await apiPost('/contest/admin/logout-all?contest=' + enc(CONTEST), body, G);
        msg.textContent = T(`✓ ${r.competitors || 0} competidor(es) e ${r.staff || 0} staff deslogado(s); login ${r.login_enabled ? 'aberto' : 'FECHADO'}`,
          `✓ ${r.competitors || 0} competitor(s) and ${r.staff || 0} staff logged out; login ${r.login_enabled ? 'open' : 'CLOSED'}`,
          `✓ ${r.competitors || 0} competidor(es) y ${r.staff || 0} staff desconectados; login ${r.login_enabled ? 'abierto' : 'CERRADO'}`);
        await load();
      } catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed', 'fallido'); }
    };
    const scopeBtn = (scope, label, hint) => el('button', { class: 'btn danger', title: hint, onclick: () => run(
      Object.assign({ scope }, closeChk.checked ? { close_login: true } : {}),
      T(`Deslogar ${label} agora${closeChk.checked ? ' e FECHAR o login' : ''}? Eles voltam só quando o login estiver aberto.`,
        `Log out ${label} now${closeChk.checked ? ' and CLOSE login' : ''}? They come back only once login is open.`,
        `¿Desconectar a ${label} ahora${closeChk.checked ? ' y CERRAR login' : ''}? Vuelven solo cuando el login esté abierto.`)) }, label);
    const s = st.sessions || {};
    box.append(
      el('p', { class: 'small muted', style: 'margin:.1rem 0 .4rem' },
        T('Feche o login, derrube todo mundo e reabra quando os times puderem entrar. ', 'Close login, log everyone out and reopen once teams may enter. ', 'Cierra el login, desconecta a todos y reabre cuando los equipos puedan entrar. ')
        + (has('rodadas') ? T('É a troca de rodada: entre os dois passos, promova a rodada em Evento › Rodadas. ', 'That is the round switch: between the two steps, promote the round in Event › Rounds. ', 'Ese es el cambio de ronda: entre los dos pasos, promueve la ronda en Evento › Rondas. ') : '')
        + T('Nunca derruba admin, juízes, chefe, monitor nem telão.', 'Never logs out admin, judges, chief, monitor or the big screen.', 'Nunca desconecta a admin, jueces, jefe, monitor ni pantalla.')),
      el('div', { class: 'row', style: 'gap:.6rem;align-items:center;flex-wrap:wrap' },
        el('span', { class: 'pill ' + (open ? 'ok' : 'bad') }, open ? T('login ABERTO', 'login OPEN', 'login ABIERTO')
          : waitsStart ? T('login abre ', 'login opens ', 'el login abre ') + new Date(st.login_start * 1000).toLocaleString(uiLocale())
          : T('login FECHADO', 'login CLOSED', 'login CERRADO')),
        el('span', { class: 'small muted' }, T(`sessões: ${s.competitors || 0} competidores · ${s.staff || 0} staff/cstaff · ${s.privileged || 0} organização`,
          `sessions: ${s.competitors || 0} competitors · ${s.staff || 0} staff/cstaff · ${s.privileged || 0} organization`,
          `sesiones: ${s.competitors || 0} competidores · ${s.staff || 0} staff/cstaff · ${s.privileged || 0} organización`)),
        open ? el('button', { class: 'btn ghost', onclick: () => run({ close_login: true }, T('Fechar o login (sem derrubar ninguém)?', 'Close login (without logging anyone out)?', '¿Cerrar login (sin desconectar a nadie)?')) }, T('🔒 Fechar login', '🔒 Close login', '🔒 Cerrar login'))
          : el('button', { class: 'btn', onclick: () => run({ open_login: true }, T('Reabrir o login para os times?', 'Reopen login for the teams?', '¿Reabrir login para los equipos?')) }, T('🔓 Reabrir login', '🔓 Reopen login', '🔓 Reabrir login'))),
      el('div', { class: 'row', style: 'gap:.6rem;align-items:center;flex-wrap:wrap;margin-top:.4rem' },
        scopeBtn('competitors', T('competidores', 'competitors', 'competidores'), T('toda conta que não é de papel', 'every non-role account', 'toda cuenta que no es de rol')),
        scopeBtn('staff', T('staff e chefes de sede', 'staff and site chiefs', 'staff y jefes de sede'), '.staff + .cstaff'),
        scopeBtn('all', T('competidores + staff', 'competitors + staff', 'competidores + staff'), ''),
        el('label', { class: 'small', style: 'display:inline-flex;gap:.3rem;align-items:center' }, closeChk, T('e fechar o login junto', 'and close login as well', 'y cerrar login también')),
        msg));
    return box;
  }

  // --- 2. sessões ativas (lista) ---------------------------------------------------------------
  const uaFilter = el('input', { type: 'search', placeholder: T('filtrar por UA / login / IP…', 'filter by UA / login / IP…', 'filtrar por UA / login / IP…'), style: 'min-width:220px' });
  const listBox = el('div', {});
  function sessionsTable() {
    const box = el('div', {});
    const f = uaFilter.value.trim().toLowerCase();
    const items = SESS.filter((s) => !f || [s.user_agent, s.login, s.ip].join(' ').toLowerCase().includes(f));
    const tb = el('tbody');
    items.forEach((s) => {
      const anom = s.multi_ip || s.multi_ua;
      tb.append(el('tr', {},
        el('td', {}, el('span', { class: anom ? 'flag-anom' : '' }, (anom ? '⚠ ' : '') + s.login)),
        el('td', { class: 'ip' + (s.multi_ip ? ' flag-anom' : '') }, s.ip || ''),
        el('td', { class: 'small' }, mk(s.mkey)),
        el('td', { class: 'ua' + (s.multi_ua ? ' flag-anom' : '') }, s.user_agent || ''),
        el('td', { class: 'small' }, fmtDate(s.login_at)),
        el('td', {}, el('button', { class: 'btn ghost small', onclick: () => logoutUser(s.login) }, T('deslogar', 'log out', 'cerrar sesión')))));
    });
    box.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, items.length + T(' de ', ' of ', ' de ') + SESS.length + T(' sessão(ões).', ' session(s).', ' sesión(es).')),
      el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' }, el('thead', {}, el('tr', {}, el('th', {}, 'Login'), el('th', {}, 'IP'), el('th', {}, T('Máquina', 'Machine', 'Máquina')), el('th', {}, T('Navegador', 'Browser', 'Navegador')), el('th', {}, T('Login em', 'Logged in at', 'Conectado en')), el('th', {}, ''))), tb)));
    return box;
  }
  function renderSessions() { swapIf(listBox, sigOf(SESS.map((s) => [s.login, s.ip, s.mkey, s.user_agent, s.login_at, !!s.multi_ip, !!s.multi_ua]), uaFilter.value), sessionsTable); }
  uaFilter.addEventListener('input', renderSessions);
  const dlSess = el('button', { class: 'btn ghost', title: T('Baixar sessões (CSV)', 'Download sessions (CSV)', 'Descargar sesiones (CSV)'), onclick: () => {
    const rows = [['login', 'ip', T('chave_maquina', 'machine_key', 'clave_maquina'), 'user_agent', 'login_at', 'login_iso', 'multi_ip', 'multi_ua'],
      ...SESS.map((s) => [s.login || '', s.ip || '', s.mkey || '', s.user_agent || '', s.login_at || '', new Date((s.login_at || 0) * 1000).toISOString(), !!s.multi_ip, !!s.multi_ua])];
    downloadText('sessoes-' + CONTEST + '-' + stamp() + '.csv', toCsv(rows), 'text/csv');
  } }, '⬇ CSV');

  // --- 3. log de acessos (dobrável; carrega ao abrir) ----------------------------------------
  function accessSection() {
    const box = el('details', { class: 'fgroup' }, el('summary', {}, T('📝 Log de acessos', '📝 Access log', '📝 Log de accesos')));
    const dateInp = el('input', { type: 'date', value: todayStr() });
    const body = el('div', {});
    let ACC = [];
    const dl = el('button', { class: 'btn ghost', title: T('Baixar acessos do dia (CSV)', 'Download the day\'s accesses (CSV)', 'Descargar los accesos del día (CSV)'), onclick: () => {
      const rows = [['epoch', T('datahora', 'datetime', 'fechahora'), 'login', 'ip', 'user_agent'],
        ...ACC.map((x) => [x.time, new Date((x.time || 0) * 1000).toISOString(), x.login || '', x.ip || '', x.user_agent || ''])];
      downloadText('acessos-' + CONTEST + '-' + (dateInp.value || stamp()) + '.csv', toCsv(rows), 'text/csv');
    } }, '⬇ CSV');
    async function loadAccess() {
      body.innerHTML = ''; let r;
      try { r = await apiGet('/contest/admin/access-log?contest=' + enc(CONTEST) + '&day=' + enc(dateInp.value), G); }
      catch { body.append(el('div', { class: 'error-box' }, T('Falha.', 'Failed.', 'Falló.'))); return; }
      const e2 = r.entries || []; ACC = e2;
      body.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, e2.length + T(' acesso(s).', ' access(es).', ' acceso(s).')));
      if (!e2.length) { body.append(el('div', { class: 'muted' }, T('Sem acessos.', 'No accesses.', 'Sin accesos.'))); return; }
      const tb = el('tbody');
      e2.forEach((x) => tb.append(el('tr', {}, el('td', { class: 'small' }, fmtDate(x.time)), el('td', {}, x.login || ''), el('td', { class: 'ip' }, x.ip || ''), el('td', { class: 'ua' }, x.user_agent || ''))));
      body.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' }, el('thead', {}, el('tr', {}, el('th', {}, T('Data/Hora', 'Date/Time', 'Fecha/Hora')), el('th', {}, 'Login'), el('th', {}, 'IP'), el('th', {}, T('Navegador', 'Browser', 'Navegador')))), tb)));
    }
    dateInp.addEventListener('change', loadAccess);
    box.append(el('div', { class: 'row', style: 'margin-bottom:.4rem' }, el('span', { class: 'small muted' }, T('Dia:', 'Day:', 'Día:')), dateInp, el('button', { class: 'btn ghost', onclick: () => loadAccess() }, '↻'), dl), body);
    box.addEventListener('toggle', () => { if (box.open && !ACC.length) loadAccess(); });
    return box;
  }

  // --- esqueleto + render em lugar -------------------------------------------------------------
  const SK = {};
  function skeleton() {
    SK.mass = el('div', {}); SK.err = el('div', {});
    panel.innerHTML = '';
    panel.append(
      el('div', { class: 'section' }, el('h2', {}, T('🖥️ Sessões', '🖥️ Sessions', '🖥️ Sesiones')), SK.err,
        el('h3', { style: 'margin:.4rem 0 .3rem' }, T('🚪 Sair em massa e trava de login', '🚪 Mass logout and login lock', '🚪 Salir en masa y bloqueo de login')), SK.mass),
      el('div', { class: 'section' }, el('h2', {}, T('🖥️ Sessões ativas', '🖥️ Active sessions', '🖥️ Sesiones activas')),
        el('div', { class: 'row', style: 'margin:.3rem 0' }, uaFilter, el('button', { class: 'btn ghost', onclick: () => load() }, '↻'), dlSess),
        listBox),
      accessSection());
  }
  function render() {
    swapIf(SK.mass, sigOf(LOGALL && LOGALL.login_enabled, LOGALL && LOGALL.login_open_now, LOGALL && LOGALL.sessions, has('rodadas')), massLogout);
    renderSessions();
  }
  async function fetchAll() {
    const [la, se] = await Promise.all([
      apiGet('/contest/admin/logout-all?contest=' + enc(CONTEST), G).catch(() => null),
      apiGet('/contest/admin/sessions?contest=' + enc(CONTEST), G),
    ]);
    LOGALL = la; SESS = (se && se.sessions) || [];
  }
  async function load() {
    if (!SK.mass) skeleton();
    try { await fetchAll(); SK.err.innerHTML = ''; }
    catch (e) { SK.err.innerHTML = ''; SK.err.append(el('div', { class: 'error-box' }, e.message || T('falha ao carregar', 'failed to load', 'falló al cargar'))); return; }
    render();
    if (stopTimer) stopTimer();
    stopTimer = everyVisible(panel, REFRESH_MS, async () => { try { await fetchAll(); } catch { return; } render(); });
  }
  return { panel, load };
}
