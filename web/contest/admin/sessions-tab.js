// contest/admin/sessions-tab.js — "Pessoas › Sessões & anomalias": quem está logado, e o que está
// FORA do lugar no uso das máquinas DURANTE a prova — time com 2 sessões vivas em máquinas
// diferentes, máquina com 2 times, submissão vinda de outra máquina, UA fora do esperado da sede,
// sede com menos máquinas que times, trocas de máquina e a trilha da sessão única (revogações).
//
// Tudo vem de GET /contest/admin/anomalies (lib/anomalies.sh). SÓ vale com o gate de UA ligado:
// sem gate o navegador não identifica a máquina, e o painel diz isso e volta a ser a listagem de
// sessões. A chave de máquina é a do UA do mlinux (machine_id/boot_id) ou, sem ela, o IP.
// Ações: deslogar um time (logout-user) e "deslogar UA divergente" (logout-mismatch), como antes.
// Atualiza sozinho a cada 30 s enquanto o painel está visível (idioma do status-tab).
import { el } from '/shared/ui.js';
import { apiGet, apiPost } from '/shared/api.js';
import { fmtDate, fmtClock, todayStr, stamp, toCsv, downloadText } from '/shared/admin-ui.js';
import { T } from '/shared/i18n.js';

const enc = encodeURIComponent;
const REFRESH_MS = 30000;

// rótulos por tipo: fábrica preguiçosa (T() no topo congelaria o idioma antes do LOCALE)
const KINDS = () => ({
  multi_session: { icon: '👥', label: T('2 sessões vivas', '2 live sessions'),
    hint: T('o mesmo time com sessão aberta em duas máquinas diferentes', 'the same team with a session open on two different machines') },
  machine_shared: { icon: '🖥', label: T('máquina compartilhada', 'shared machine'),
    hint: T('dois ou mais times fizeram login na mesma máquina durante a prova', 'two or more teams logged in on the same machine during the contest') },
  sub_other_machine: { icon: '📤', label: T('submissão de outra máquina', 'submission from another machine'),
    hint: T('a submissão veio de uma máquina diferente da que fez o login (sessão levada para outra máquina)', 'the submission came from a machine other than the one that logged in (session carried to another machine)') },
  ua_mismatch: { icon: '🧭', label: T('UA fora da sede', 'UA off-site'),
    hint: T('sessão viva cujo navegador não é o da imagem da sede (entrou antes do gate ou por isenção)', 'live session whose browser is not the site image (logged in before the gate or by exemption)') },
  site_short: { icon: '🏫', label: T('sede sem máquina por time', 'site short of machines'),
    hint: T('na última coleta do nutellaboot a sede tem mais times presentes do que máquinas vistas', 'in the last nutellaboot collection the site has more present teams than machines seen') },
  switched: { icon: '🔁', label: T('trocou de máquina', 'switched machine'),
    hint: T('o time fez login em mais de uma máquina durante a prova (normal quando a máquina falha)', 'the team logged in on more than one machine during the contest (normal when a machine fails)') },
  session_event: { icon: '🧾', label: T('sessão derrubada', 'session ended'),
    hint: T('revogação pela sessão única, deslogar do admin ou deslogar UA divergente', 'revocation by single-session, admin logout or mismatched-UA logout') },
});
const SEV = () => ({ bad: T('grave', 'severe'), warn: T('atenção', 'attention'), info: T('info', 'info') });
const sevPill = (s) => el('span', { class: 'pill ' + (s === 'bad' ? 'bad' : s === 'warn' ? 'warn' : '') }, SEV()[s] || s);
// chave de máquina legível: m:<mid>/<boot> -> "mid…/boot"; ip:x -> "ip x"
const mk = (k) => {
  if (!k) return '—';
  if (k.startsWith('m:')) { const [mid, boot] = k.slice(2).split('/'); return el('code', { title: k }, (mid || '').slice(0, 8) + '…/' + (boot || '')); }
  if (k.startsWith('ip:')) return el('code', { title: k }, 'ip ' + k.slice(3));
  return el('code', {}, k);
};
const mkText = (k) => (k || '').split(' → ').map((x) => x.startsWith('m:') ? x.slice(2, 10) + '…/' + x.split('/')[1] : x.replace(/^ip:/, 'ip ')).join(' → ');

export function makeSessionsTab(CONTEST) {
  const G = { contest: CONTEST, auth: true };
  const panel = el('div', {});
  let DATA = null, timer = null;
  let filterKind = '', filterText = '', showAll = false;

  // --- ações ------------------------------------------------------------------------------
  async function logoutUser(login) {
    if (!confirm(T(`Deslogar ${login} (todas as sessões)?`, `Log out ${login} (all sessions)?`))) return;
    try { await apiPost('/contest/admin/logout-user?contest=' + enc(CONTEST), { login }, G); await load(); }
    catch (e) { alert(e.message || T('falha', 'failed')); }
  }
  async function logoutMismatch() {
    if (!confirm(T('Deslogar todas as sessões cujo UA não bate o esperado da sede?', 'Log out all sessions whose UA does not match the site\'s expected one?'))) return;
    try { const r = await apiPost('/contest/admin/logout-mismatch?contest=' + enc(CONTEST), {}, G); alert(r.sessions_removed + T(' sessão(ões) encerradas.', ' session(s) ended.')); await load(); }
    catch (e) { alert(e.message || T('falha', 'failed')); }
  }

  // --- 1. barra de estado -----------------------------------------------------------------
  function stateBar(d) {
    const g = d.gate || {};
    const on = g.mode === 'enforce';
    const bar = el('div', { class: 'row', style: 'gap:.6rem;flex-wrap:wrap;align-items:center;margin:.2rem 0 .6rem' },
      el('span', { class: 'pill ' + (g.active ? 'ok' : '') }, g.active ? T('gate de UA ativo', 'UA gate active') : on ? T('gate armado sem regra', 'gate armed, no rule') : T('gate desligado', 'gate off')),
      el('span', { class: 'pill ' + (g.single_session && g.active ? 'ok' : '') }, g.single_session ? T('sessão única por time', 'single session per team') : T('sessão única DESLIGADA', 'single session OFF')),
      el('a', { href: '#pessoas/maquinas', class: 'small' }, T('Máquinas & gate →', 'Machines & gate →')),
      el('span', { class: 'small muted' }, T('janela: ', 'window: ') + fmtClock(d.window.start) + ' → ' + fmtClock(d.window.end)
        + ' · ' + T('apurado ', 'computed ') + fmtClock(d.computed_at) + (d.round ? ' · ' + d.round : '')),
      el('button', { class: 'btn ghost', onclick: () => load() }, '↻'));
    if (!g.active) {
      return el('div', {}, bar, el('div', { class: 'alert' },
        T('Gate de UA desligado (ou sem regra que casa): o navegador não identifica a máquina, então as anomalias de máquina não valem. Ligue o gate em Pessoas › Máquinas & gate. Abaixo, só as sessões ativas e o log de acessos.',
          'UA gate off (or no matching rule): the browser does not identify the machine, so machine anomalies do not apply. Enable the gate in People › Machines & gate. Below, only the active sessions and the access log.')));
    }
    return bar;
  }

  // --- 2. cartões -------------------------------------------------------------------------
  function cards(d) {
    const c = d.counts || {}, K = KINDS();
    const card = (val, lbl, kind, warn) => el('div', { class: 'dash-card' + (warn && val > 0 ? ' warn' : ''),
      style: 'cursor:pointer' + (filterKind === kind ? ';outline:2px solid #1e57c4' : ''),
      title: K[kind] ? K[kind].hint : '', onclick: () => { filterKind = (filterKind === kind ? '' : kind); render(); } },
    el('div', { class: 'dash-val' }, String(val)), el('div', { class: 'dash-lbl' }, lbl));
    return el('div', { class: 'dash-cards' },
      el('div', { class: 'dash-card', title: T('sessões vivas de times neste contest', 'live team sessions in this contest') },
        el('div', { class: 'dash-val' }, String(c.sessions || 0)), el('div', { class: 'dash-lbl' }, T('sessões ativas', 'active sessions') + ' · ' + (c.teams_live || 0) + T(' times', ' teams'))),
      card(c.multi_session || 0, K.multi_session.label, 'multi_session', true),
      card(c.machine_shared || 0, K.machine_shared.label, 'machine_shared', true),
      card(c.sub_other_machine || 0, K.sub_other_machine.label, 'sub_other_machine', true),
      card(c.ua_mismatch || 0, K.ua_mismatch.label, 'ua_mismatch', true),
      card(c.site_short || 0, K.site_short.label, 'site_short', true),
      card(c.switched || 0, K.switched.label, 'switched', false),
      card(c.revoked || 0, T('revogações', 'revocations'), 'session_event', false));
  }

  // --- 3. linha do tempo ------------------------------------------------------------------
  function timeline(d) {
    const K = KINDS();
    const box = el('div', { class: 'section' }, el('h2', {}, T('🕒 Linha do tempo', '🕒 Timeline')));
    const items = (d.anomalies || []).concat(d.events || []);
    items.sort((a, b) => (b.at || 0) - (a.at || 0));
    const f = filterText.trim().toLowerCase();
    const rows = items.filter((x) => (!filterKind || x.kind === filterKind)
      && (!f || [x.login, x.name, x.region, x.machine, JSON.stringify(x.detail || {})].join(' ').toLowerCase().includes(f)));
    const fText = el('input', { type: 'search', value: filterText, placeholder: T('time, sede, máquina…', 'team, site, machine…'), style: 'min-width:220px' });
    fText.addEventListener('input', () => { filterText = fText.value; renderBody(); });
    const chips = el('div', { class: 'row', style: 'gap:.3rem;flex-wrap:wrap' },
      ...Object.keys(K).map((k) => el('button', { class: 'btn ghost small' + (filterKind === k ? ' active' : ''),
        style: filterKind === k ? 'outline:2px solid #1e57c4' : '', title: K[k].hint,
        onclick: () => { filterKind = (filterKind === k ? '' : k); render(); } }, K[k].icon + ' ' + K[k].label)));
    const dl = el('button', { class: 'btn ghost', title: T('Baixar (CSV)', 'Download (CSV)'), onclick: () => {
      const out = [['epoch', 'datahora', 'tipo', 'severidade', 'login', 'nome', 'sede', 'maquina', 'detalhe'],
        ...rows.map((x) => [x.at, new Date((x.at || 0) * 1000).toISOString(), x.kind, x.severity, x.login || '', x.name || '', x.region || '', x.machine || '', JSON.stringify(x.detail || {})])];
      downloadText('anomalias-' + CONTEST + '-' + stamp() + '.csv', toCsv(out), 'text/csv');
    } }, '⬇ CSV');
    const body = el('div', {});
    function detailText(x) {
      const dd = x.detail || {};
      switch (x.kind) {
        case 'multi_session': return T(`${dd.sessions} sessões em ${(dd.keys || []).length} máquinas: `, `${dd.sessions} sessions on ${(dd.keys || []).length} machines: `) + (dd.keys || []).map(mkText).join(' · ');
        case 'machine_shared': return (dd.logins || []).map((l) => `${l.login} (${fmtClock(l.first)}${l.n > 1 ? ' ×' + l.n : ''}${l.live ? ' ' + T('vivo', 'live') : ''})`).join(' · ') + (dd.live_both ? ' — ' + T('os dois com sessão viva nela', 'both with a live session on it') : '');
        case 'sub_other_machine': return (dd.reboot ? T('reboot da mesma máquina: ', 'same machine rebooted: ') : T('sessão em ', 'session on ') + mkText(dd.session_key) + T(', requisição de ', ', request from ')) + (dd.reboot ? mkText(dd.request_key) : mkText(dd.request_key)) + ' · sub ' + (dd.subid || '').slice(0, 8);
        case 'ua_mismatch': return T('esperado ', 'expected ') + (dd.expected || '') + T(' · visto: ', ' · seen: ') + (dd.ua || '');
        case 'site_short': return T(`${dd.present ?? dd.teams} times presentes, ${dd.seen} máquinas vistas (${dd.machines_total} cadastradas)`, `${dd.present ?? dd.teams} present teams, ${dd.seen} machines seen (${dd.machines_total} registered)`);
        case 'switched': return (dd.machines || []).map((m) => mkText(m.key) + ' ' + fmtClock(m.first)).join(' → ') + (dd.revoked ? T(` · ${dd.revoked} sessão(ões) revogada(s)`, ` · ${dd.revoked} session(s) revoked`) : '');
        case 'session_event': return ({ revoke: T('revogada pela sessão única (login novo em outra máquina)', 'revoked by single-session (new login on another machine)'), logout: T('deslogado pelo admin', 'logged out by the admin'), 'mismatch-logout': T('deslogar UA divergente', 'mismatched-UA logout') }[dd.event] || dd.event) + (dd.who ? ' · ' + dd.who : '');
        default: return JSON.stringify(dd);
      }
    }
    function renderBody() {
      body.innerHTML = '';
      const rws = items.filter((x) => (!filterKind || x.kind === filterKind)
        && (!filterText.trim() || [x.login, x.name, x.region, x.machine, JSON.stringify(x.detail || {})].join(' ').toLowerCase().includes(filterText.trim().toLowerCase())));
      body.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, rws.length + T(' evento(s).', ' event(s).')));
      if (!rws.length) { body.append(el('div', { class: 'muted' }, T('Nada fora do lugar.', 'Nothing out of place.'))); return; }
      const tb = el('tbody');
      rws.slice(0, 400).forEach((x) => {
        const k = K[x.kind] || { icon: '', label: x.kind };
        tb.append(el('tr', { class: x.severity === 'bad' ? 'flag-row-bad' : '' },
          el('td', { class: 'small' }, fmtDate(x.at)),
          el('td', {}, sevPill(x.severity), ' ', el('span', { class: 'small' }, k.icon + ' ' + k.label)),
          el('td', {}, x.login ? el('span', { class: x.severity === 'bad' ? 'flag-anom' : '' }, x.login) : (x.name || ''), x.name && x.login && x.name !== x.login ? el('div', { class: 'small muted' }, x.name) : null, x.region ? el('div', { class: 'small muted' }, x.region) : null),
          el('td', { class: 'small' }, x.kind === 'switched' || x.kind === 'session_event' ? el('code', {}, mkText(x.machine)) : mk(x.machine)),
          el('td', { class: 'small' }, detailText(x)),
          el('td', {}, x.login && !x.login.includes(',') && x.kind !== 'site_short' ? el('button', { class: 'btn ghost small', onclick: () => logoutUser(x.login) }, T('deslogar', 'log out')) : '')));
      });
      body.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' }, el('thead', {}, el('tr', {},
        el('th', {}, T('Quando', 'When')), el('th', {}, T('Tipo', 'Type')), el('th', {}, T('Time', 'Team')), el('th', {}, T('Máquina', 'Machine')), el('th', {}, T('Detalhe', 'Detail')), el('th', {}, ''))), tb)));
    }
    renderBody();
    box.append(el('div', { class: 'row', style: 'gap:.5rem;flex-wrap:wrap;align-items:center;margin-bottom:.4rem' }, fText, dl), chips, body);
    return box;
  }

  // --- 4. times ----------------------------------------------------------------------------
  function teamsTable(d) {
    const K = KINDS();
    const all = d.teams || [];
    const rows = (showAll ? all : all.filter((t) => (t.flags || []).length)).filter((t) => !filterKind || (t.flags || []).includes(filterKind));
    const box = el('div', { class: 'section' }, el('h2', {}, T('👥 Times', '👥 Teams')));
    const tog = el('label', { class: 'small', style: 'display:inline-flex;gap:.3rem;align-items:center' },
      el('input', { type: 'checkbox', checked: showAll, onchange: (ev) => { showAll = ev.target.checked; render(); } }),
      T('mostrar todos os times com sessão', 'show all teams with a session'));
    const tb = el('tbody');
    rows.forEach((t) => {
      const keys = [...new Set((t.sessions || []).map((s) => s.key))];
      const ls = t.last_sub;
      tb.append(el('tr', {},
        el('td', {}, el('span', { class: (t.flags || []).some((f) => f === 'multi_session' || f === 'sub_other_machine') ? 'flag-anom' : '' }, t.login), t.name && t.name !== t.login ? el('div', { class: 'small muted' }, t.name) : null, t.region ? el('div', { class: 'small muted' }, t.region) : null),
        el('td', { class: 'n' }, String((t.sessions || []).length) + (keys.length > 1 ? ' ' + T('em', 'on') + ' ' + keys.length + ' ' + T('máq.', 'mach.') : '')),
        el('td', { class: 'small' }, ...(t.machines || []).filter((m) => m.in > 0).flatMap((m, i) => [i ? ' → ' : '', mk(m.key), el('span', { class: 'muted' }, ' ' + fmtClock(m.first))])),
        el('td', { class: 'small' }, ls ? [fmtClock(ls.at), ' ', mk(ls.key), ' ', el('span', { class: ls.same_as_session && ls.same_as_login_machine ? 'v-ok' : 'flag-anom' }, ls.same_as_session && ls.same_as_login_machine ? '✓' : '✗')] : '—'),
        el('td', {}, ...(t.flags || []).map((f) => el('span', { class: 'pill small', style: 'margin-right:.2rem', title: K[f] ? K[f].hint : f }, (K[f] || {}).icon + ' ' + ((K[f] || {}).label || f)))),
        el('td', {}, el('button', { class: 'btn ghost small', onclick: () => logoutUser(t.login) }, T('deslogar', 'log out')))));
    });
    box.append(el('div', { class: 'row', style: 'gap:.6rem;align-items:center;margin-bottom:.3rem' }, tog,
      el('span', { class: 'small muted' }, rows.length + T(' time(s).', ' team(s).'))),
    el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' }, el('thead', {}, el('tr', {},
      el('th', {}, T('Time', 'Team')), el('th', { class: 'n' }, T('Sessões', 'Sessions')), el('th', {}, T('Máquinas na prova', 'Machines in contest')),
      el('th', {}, T('Última submissão', 'Last submission')), el('th', {}, T('Anomalias', 'Anomalies')), el('th', {}, ''))), tb)));
    return box;
  }

  // --- 5. sessões ativas + log de acessos (como antes, dobráveis) --------------------------
  function sessionsSection() {
    const box = el('details', { class: 'fgroup', style: 'margin-top:.6rem' }, el('summary', {}, T('🖥 Sessões ativas (lista)', '🖥 Active sessions (list)')));
    const body = el('div', {});
    const uaFilter = el('input', { type: 'search', placeholder: T('filtrar por UA / login / IP…', 'filter by UA / login / IP…'), style: 'min-width:220px' });
    let SESS = [];
    function renderSessions() {
      body.innerHTML = '';
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
          el('td', {}, el('button', { class: 'btn ghost small', onclick: () => logoutUser(s.login) }, T('deslogar', 'log out')))));
      });
      body.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, items.length + T(' de ', ' of ') + SESS.length + T(' sessão(ões).', ' session(s).')),
        el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' }, el('thead', {}, el('tr', {}, el('th', {}, 'Login'), el('th', {}, 'IP'), el('th', {}, T('Máquina', 'Machine')), el('th', {}, T('Navegador (UA)', 'Browser (UA)')), el('th', {}, T('Login em', 'Logged in at')), el('th', {}, ''))), tb)));
    }
    async function loadSessions() {
      let r; try { r = await apiGet('/contest/admin/sessions?contest=' + enc(CONTEST), G); }
      catch { body.innerHTML = ''; body.append(el('div', { class: 'error-box' }, T('Falha.', 'Failed.'))); return; }
      SESS = r.sessions || []; renderSessions();
    }
    uaFilter.addEventListener('input', renderSessions);
    const mismatchBtn = el('button', { class: 'btn danger', title: T('compara cada sessão com o UA esperado da sede daquele time', 'compares each session with the expected UA of that team\'s site'), onclick: logoutMismatch }, T('Deslogar UA divergente', 'Log out mismatched UA'));
    const dlSess = el('button', { class: 'btn ghost', title: T('Baixar sessões (CSV)', 'Download sessions (CSV)'), onclick: () => {
      const rows = [['login', 'ip', 'mkey', 'user_agent', 'login_at', 'login_iso', 'multi_ip', 'multi_ua'],
        ...SESS.map((s) => [s.login || '', s.ip || '', s.mkey || '', s.user_agent || '', s.login_at || '', new Date((s.login_at || 0) * 1000).toISOString(), !!s.multi_ip, !!s.multi_ua])];
      downloadText('sessoes-' + CONTEST + '-' + stamp() + '.csv', toCsv(rows), 'text/csv');
    } }, '⬇ CSV');
    box.append(el('div', { class: 'row', style: 'margin:.3rem 0' }, uaFilter, el('button', { class: 'btn ghost', onclick: () => loadSessions() }, '↻'), mismatchBtn, dlSess), body);
    box.addEventListener('toggle', () => { if (box.open && !SESS.length) loadSessions(); });
    return box;
  }
  function accessSection() {
    const box = el('details', { class: 'fgroup' }, el('summary', {}, T('📝 Log de acessos', '📝 Access log')));
    const dateInp = el('input', { type: 'date', value: todayStr() });
    const body = el('div', {});
    let ACC = [];
    const dl = el('button', { class: 'btn ghost', title: T('Baixar acessos do dia (CSV)', 'Download the day\'s accesses (CSV)'), onclick: () => {
      const rows = [['epoch', 'datahora', 'login', 'ip', 'user_agent'],
        ...ACC.map((x) => [x.time, new Date((x.time || 0) * 1000).toISOString(), x.login || '', x.ip || '', x.user_agent || ''])];
      downloadText('acessos-' + CONTEST + '-' + (dateInp.value || stamp()) + '.csv', toCsv(rows), 'text/csv');
    } }, '⬇ CSV');
    async function loadAccess() {
      body.innerHTML = ''; let r;
      try { r = await apiGet('/contest/admin/access-log?contest=' + enc(CONTEST) + '&day=' + enc(dateInp.value), G); }
      catch { body.append(el('div', { class: 'error-box' }, T('Falha.', 'Failed.'))); return; }
      const e2 = r.entries || []; ACC = e2;
      body.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, e2.length + T(' acesso(s).', ' access(es).')));
      if (!e2.length) { body.append(el('div', { class: 'muted' }, T('Sem acessos.', 'No accesses.'))); return; }
      const tb = el('tbody');
      e2.forEach((x) => tb.append(el('tr', {}, el('td', { class: 'small' }, fmtDate(x.time)), el('td', {}, x.login || ''), el('td', { class: 'ip' }, x.ip || ''), el('td', { class: 'ua' }, x.user_agent || ''))));
      body.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' }, el('thead', {}, el('tr', {}, el('th', {}, T('Data/Hora', 'Date/Time')), el('th', {}, 'Login'), el('th', {}, 'IP'), el('th', {}, T('Navegador (UA)', 'Browser (UA)')))), tb)));
    }
    dateInp.addEventListener('change', loadAccess);
    box.append(el('div', { class: 'row', style: 'margin-bottom:.4rem' }, el('span', { class: 'small muted' }, T('Dia:', 'Day:')), dateInp, el('button', { class: 'btn ghost', onclick: () => loadAccess() }, '↻'), dl), body);
    box.addEventListener('toggle', () => { if (box.open && !ACC.length) loadAccess(); });
    return box;
  }

  // --- 6. como ler --------------------------------------------------------------------------
  function legend() {
    const K = KINDS();
    const li = (k, txt) => el('li', {}, el('b', {}, k + ': '), txt);
    return el('details', { class: 'small', style: 'margin:.5rem 0' }, el('summary', {}, T('Como ler', 'How to read')),
      el('ul', { style: 'margin:.2rem 0 0 1.1rem' },
        li(T('Máquina', 'Machine'), T('a chave vem do navegador do mlinux (machine_id/boot_id). Sem ela, vale o IP. Um reboot muda o boot_id: a mesma máquina aparece como outra.', 'the key comes from the mlinux browser (machine_id/boot_id). Without it, the IP is used. A reboot changes the boot_id: the same machine shows up as another.')),
        li(T('Sessão única', 'Single session'), T('com o gate ligado, um login em outra máquina derruba a sessão anterior do time. Recarregar a página na mesma máquina não derruba nada. Cada queda vira um evento.', 'with the gate on, a login on another machine ends the team\'s previous session. Reloading the page on the same machine ends nothing. Each drop becomes an event.')),
        ...Object.keys(K).map((k) => li(K[k].icon + ' ' + K[k].label, K[k].hint)),
        li(T('Última submissão', 'Last submission'), T('✓ = veio da máquina da sessão e da máquina do último login; ✗ = veio de outra.', '✓ = came from the session\'s machine and the last login machine; ✗ = came from another one.')),
        li(T('Sem gate', 'Without the gate'), T('nada disto vale: o painel mostra só as sessões e o log de acessos.', 'none of this applies: the panel shows only the sessions and the access log.'))));
  }

  // --- render ------------------------------------------------------------------------------
  function render() {
    panel.innerHTML = '';
    if (!DATA) { panel.append(el('p', { class: 'muted' }, T('Carregando…', 'Loading…'))); return; }
    const d = DATA;
    panel.append(el('div', { class: 'section' }, el('h2', {}, T('🛡 Sessões & anomalias', '🛡 Sessions & anomalies')), stateBar(d),
      d.gate && d.gate.active ? cards(d) : null));
    if (d.gate && d.gate.active) { panel.append(timeline(d)); panel.append(teamsTable(d)); }
    panel.append(sessionsSection(), accessSection(), legend());
  }
  async function load() {
    try { DATA = await apiGet('/contest/admin/anomalies?contest=' + enc(CONTEST), G); }
    catch (e) { panel.innerHTML = ''; panel.append(el('div', { class: 'error-box' }, e.message || T('falha ao carregar', 'failed to load'))); return; }
    render();
    if (timer) clearInterval(timer);
    timer = setInterval(async () => {
      if (panel.hidden || !panel.isConnected) return;
      try { DATA = await apiGet('/contest/admin/anomalies?contest=' + enc(CONTEST), G); render(); } catch { /* mantém o último */ }
    }, REFRESH_MS);
  }
  return { panel, load };
}
