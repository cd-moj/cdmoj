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
  site_lock: { icon: '🔒', label: T('trava de sede', 'site lock'),
    hint: T('IP da sede preso a este contest (reivindicação no login) ou pedido daquele IP a outro alvo bloqueado (403 site_locked)', 'site IP pinned to this contest (claim at login) or a request from that IP to another target blocked (403 site_locked)') },
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
  let DATA = null, SLOCK = null, LOGALL = null, timer = null;
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

  // --- 1b. canais: web × CLI × offline na janela (vale mesmo sem gate) ----------------------
  function channels(d) {
    const c = d.channels; if (!c) return null;
    const L = c.logins || {}, S = c.submissions || {};
    const cell = (v, lbl) => el('div', { class: 'dash-card' }, el('div', { class: 'dash-val' }, String(v || 0)), el('div', { class: 'dash-lbl' }, lbl));
    return el('div', {},
      el('div', { class: 'small muted', style: 'margin:.4rem 0 .1rem' },
        T('Canal dos pedidos na prova (pelo User-Agent: a CLI se marca "moj-comp/<build>")', 'Request channel in the contest (by User-Agent: the CLI marks itself "moj-comp/<build>")')),
      el('div', { class: 'dash-cards' },
        cell(L.web, T('logins web', 'web logins')), cell(L.cli, T('logins CLI', 'CLI logins')), cell(L.other, T('logins outros', 'other logins')),
        cell(S.web, T('submissões web', 'web submissions')), cell(S.cli, T('submissões CLI', 'CLI submissions')), cell(S.offline, T('pacotes offline', 'offline packets'))));
  }

  // --- 1c. sair em massa + trava de login (troca de rodada) --------------------------------
  function massLogout(d) {
    const st = Object.assign({}, LOGALL || {}, { sessions: (d && d.session_classes) || (LOGALL && LOGALL.sessions) || {} });
    const box = el('div', { class: 'subcard', style: 'margin:.6rem 0' });
    const open = st.login_enabled !== false;
    const msg = el('span', { class: 'small' });
    const closeChk = el('input', { type: 'checkbox', checked: true });
    const run = async (body, label) => {
      if (!confirm(label)) return;
      msg.textContent = '…';
      try {
        const r = await apiPost('/contest/admin/logout-all?contest=' + enc(CONTEST), body, G);
        msg.textContent = T(`✓ ${r.competitors || 0} competidor(es) e ${r.staff || 0} staff deslogado(s); login ${r.login_enabled ? 'aberto' : 'FECHADO'}`,
          `✓ ${r.competitors || 0} competitor(s) and ${r.staff || 0} staff logged out; login ${r.login_enabled ? 'open' : 'CLOSED'}`);
        await load();
      } catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
    };
    const scopeBtn = (scope, label, hint) => el('button', { class: 'btn danger', title: hint, onclick: () => run(
      Object.assign({ scope }, closeChk.checked ? { close_login: true } : {}),
      T(`Deslogar ${label} agora${closeChk.checked ? ' e FECHAR o login' : ''}? Eles voltam só quando o login estiver aberto.`,
        `Log out ${label} now${closeChk.checked ? ' and CLOSE login' : ''}? They come back only once login is open.`)) }, label);
    box.append(el('h3', { style: 'margin:.1rem 0 .3rem' }, T('🚪 Sair em massa e trava de login', '🚪 Mass logout and login lock')),
      el('p', { class: 'small muted', style: 'margin:.1rem 0 .4rem' },
        T('A troca de rodada: feche o login, derrube todo mundo, promova a rodada (Prova › Rodadas) e reabra quando os times puderem entrar. Nunca derruba admin, juízes, chefe, monitor nem telão. Cada sessão derrubada vira evento; a ação vai ao audit.',
          'The round switch: close login, log everyone out, promote the round (Contest › Rounds) and reopen once teams may enter. Never logs out admin, judges, chief, monitor or the big screen. Each dropped session becomes an event; the action goes to the audit.')),
      el('div', { class: 'row', style: 'gap:.6rem;align-items:center;flex-wrap:wrap' },
        el('span', { class: 'pill ' + (open ? 'ok' : 'bad') }, open ? T('login ABERTO', 'login OPEN') : T('login FECHADO', 'login CLOSED')),
        el('span', { class: 'small muted' }, T(`sessões: ${(st.sessions || {}).competitors || 0} competidores · ${(st.sessions || {}).staff || 0} staff/cstaff · ${(st.sessions || {}).privileged || 0} organização`,
          `sessions: ${(st.sessions || {}).competitors || 0} competitors · ${(st.sessions || {}).staff || 0} staff/cstaff · ${(st.sessions || {}).privileged || 0} organization`)),
        open ? el('button', { class: 'btn ghost', onclick: () => run({ close_login: true }, T('Fechar o login (sem derrubar ninguém)?', 'Close login (without logging anyone out)?')) }, T('🔒 Fechar login', '🔒 Close login'))
          : el('button', { class: 'btn', onclick: () => run({ open_login: true }, T('Reabrir o login para os times?', 'Reopen login for the teams?')) }, T('🔓 Reabrir login', '🔓 Reopen login'))),
      el('div', { class: 'row', style: 'gap:.6rem;align-items:center;flex-wrap:wrap;margin-top:.4rem' },
        scopeBtn('competitors', T('competidores', 'competitors'), T('toda conta que não é de papel', 'every non-role account')),
        scopeBtn('staff', T('staff e chefes de sede', 'staff and site chiefs'), '.staff + .cstaff'),
        scopeBtn('all', T('competidores + staff', 'competitors + staff'), ''),
        el('label', { class: 'small', style: 'display:inline-flex;gap:.3rem;align-items:center' }, closeChk, T('e fechar o login junto', 'and close login as well')),
        msg));
    return box;
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
      card(c.revoked || 0, T('revogações', 'revocations'), 'session_event', false),
      card(c.site_lock_blocks || 0, T('bloqueios da trava', 'lock blocks'), 'site_lock', true));
  }

  // --- 2b. trava de sede por IP (GET /contest/admin/site-lock) — vale sem gate --------------
  function siteLockSection() {
    const sl = SLOCK; if (!sl) return null;
    const claims = sl.claims || [], blocks = sl.blocks || [];
    if (!sl.enabled && !claims.length && !blocks.length) return null;
    const box = el('div', { class: 'section' }, el('h2', {}, T('🔒 Trava de sede por IP', '🔒 Per-site IP lock')));
    box.append(el('p', { class: 'ml-note' },
      sl.enabled
        ? T(`Ligada: cada login de competidor prende o IP de origem a este contest até o fim + ${sl.grace}s. Daquele IP, treino, índice e outros contests respondem 403 site_locked. Toda reivindicação e todo bloqueio estão no audit; abaixo, o resumo.`,
          `On: each competitor login pins the source IP to this contest until the end + ${sl.grace}s. From that IP, training, index and other contests answer 403 site_locked. Every claim and every block is in the audit; the summary is below.`)
        : T('Desligada (ligue em Máquinas & gate › 🔒). IPs presos anteriormente continuam até vencer.', 'Off (turn on in Machines & gate › 🔒). Previously pinned IPs stay until they expire.')));
    const msg = el('span', { class: 'small' });
    const actions = el('div', { class: 'row', style: 'gap:.5rem;align-items:center;margin:.3rem 0' },
      sl.enabled ? el('button', { class: 'btn ghost', title: T('prende desde já os IPs de competidores vistos na janela da rodada (aquecimento incluso)', 'pins right away the competitor IPs seen in the round window (warm-up included)'),
        onclick: async () => {
          if (!confirm(T('Prender agora todos os IPs de competidores vistos nesta rodada?', 'Pin now every competitor IP seen in this round?'))) return;
          try { const r = await apiPost('/contest/admin/site-lock?contest=' + enc(CONTEST), { action: 'claim-seen' }, G); msg.textContent = T(`✓ ${r.claimed} IP(s) novo(s) preso(s)`, `✓ ${r.claimed} new IP(s) pinned`); await load(); }
          catch (e) { msg.textContent = e.message || T('falha', 'failed'); }
        } }, T('🔒 Prender IPs já vistos', '🔒 Pin IPs already seen')) : null,
      msg);
    const tb = el('tbody');
    claims.forEach((c) => tb.append(el('tr', { class: c.blocked ? 'flag-row-bad' : '' },
      el('td', {}, el('code', {}, c.ip), c.active ? '' : el('span', { class: 'small muted' }, ' ' + T('(vencida)', '(expired)'))),
      el('td', { class: 'small' }, fmtClock(c.first) + ' → ' + fmtClock(c.last)),
      el('td', { class: 'n' }, String(c.logins)),
      el('td', { class: 'n' }, el('span', { class: c.blocked ? 'flag-anom' : '' }, String(c.blocked))),
      el('td', { class: 'small' }, c.blocked ? fmtClock(c.last_block) + (c.last_target && c.last_target !== '-' ? ' → ' + c.last_target : ' → ' + T('treino/índice', 'training/index')) : '—'),
      el('td', { class: 'small' }, fmtDate(c.until)),
      el('td', {}, el('button', { class: 'btn ghost small', onclick: async () => {
        if (!confirm(T(`Soltar ${c.ip}? Daquele IP o treino e outros contests voltam a responder.`, `Release ${c.ip}? From that IP training and other contests answer again.`))) return;
        try { await apiPost('/contest/admin/site-lock?contest=' + enc(CONTEST), { action: 'release', ip: c.ip }, G); await load(); } catch (e) { alert(e.message); }
      } }, T('soltar', 'release'))))));
    box.append(actions, el('div', { class: 'small muted' }, claims.length + T(' IP(s) preso(s).', ' pinned IP(s).')),
      el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' }, el('thead', {}, el('tr', {},
        el('th', {}, 'IP'), el('th', {}, T('Logins (1º → último)', 'Logins (first → last)')), el('th', { class: 'n' }, T('Logins', 'Logins')),
        el('th', { class: 'n' }, T('Bloqueios', 'Blocks')), el('th', {}, T('Último bloqueio', 'Last block')), el('th', {}, T('Preso até', 'Pinned until')), el('th', {}, ''))), tb)));
    if (blocks.length) {
      const tb2 = el('tbody');
      blocks.slice(0, 100).forEach((b) => tb2.append(el('tr', { class: 'flag-row-bad' },
        el('td', { class: 'small' }, fmtDate(b.at)), el('td', {}, el('code', {}, b.ip)),
        el('td', {}, b.target && b.target !== '-' ? b.target : el('span', { class: 'muted' }, T('treino/índice', 'training/index'))),
        el('td', { class: 'small' }, el('code', {}, b.route)), el('td', {}, b.login && b.login !== '-' ? b.login : el('span', { class: 'muted' }, T('sem sessão', 'no session'))))));
      box.append(el('h3', {}, T(`Bloqueios registrados (${blocks.length}; 1 linha por IP e alvo a cada 5 min)`, `Recorded blocks (${blocks.length}; 1 line per IP and target every 5 min)`)),
        el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' }, el('thead', {}, el('tr', {},
          el('th', {}, T('Quando', 'When')), el('th', {}, 'IP'), el('th', {}, T('Alvo', 'Target')), el('th', {}, T('Rota', 'Route')), el('th', {}, T('Sessão', 'Session')))), tb2)));
    }
    return box;
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
    if (!SK.fText) {
      SK.fText = el('input', { type: 'search', value: filterText, placeholder: T('time, sede, máquina…', 'team, site, machine…'), style: 'min-width:220px' });
      SK.fText.addEventListener('input', () => { filterText = SK.fText.value; if (SK.tlBody) SK.tlBody(); });
    }
    const fText = SK.fText;
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
      case 'site_lock': return dd.event === 'site-lock-block'
        ? T(`BLOQUEADO: pedido a "${dd.target && dd.target !== '-' ? dd.target : 'treino/índice'}" (${dd.route}) de IP preso a este contest`, `BLOCKED: request to "${dd.target && dd.target !== '-' ? dd.target : 'training/index'}" (${dd.route}) from an IP pinned to this contest`)
        : T(`IP preso a este contest até ${fmtClock(+dd.until || 0)}`, `IP pinned to this contest until ${fmtClock(+dd.until || 0)}`);
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
          el('td', { class: 'small' }, x.kind === 'switched' || x.kind === 'session_event' ? el('code', {}, mkText(x.machine)) : x.kind === 'site_lock' ? el('code', {}, (x.machine || '').replace(/^ip:/, '')) : mk(x.machine)),
          el('td', { class: 'small' }, detailText(x)),
          el('td', {}, x.login && !x.login.includes(',') && x.kind !== 'site_short' ? el('button', { class: 'btn ghost small', onclick: () => logoutUser(x.login) }, T('deslogar', 'log out')) : '')));
      });
      body.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' }, el('thead', {}, el('tr', {},
        el('th', {}, T('Quando', 'When')), el('th', {}, T('Tipo', 'Type')), el('th', {}, T('Time', 'Team')), el('th', {}, T('Máquina', 'Machine')), el('th', {}, T('Detalhe', 'Detail')), el('th', {}, ''))), tb)));
    }
    renderBody(); SK.tlBody = renderBody;
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
        li(T('Máquina', 'Machine'), T('a chave vem do navegador do mlinux (machine_id/boot_id). Um reboot muda o boot_id: a mesma máquina aparece como outra. Login sem essa chave (navegador comum) fica de fora das anomalias de máquina: atrás de NAT o IP é a sede inteira, não uma máquina.', 'the key comes from the mlinux browser (machine_id/boot_id). A reboot changes the boot_id: the same machine shows up as another. Logins without that key (a regular browser) stay out of the machine anomalies: behind NAT the IP is the whole site, not a machine.')),
        li(T('Sessão única', 'Single session'), T('com o gate ligado, um login em outra máquina derruba a sessão anterior do time. Recarregar a página na mesma máquina não derruba nada. Cada queda vira um evento.', 'with the gate on, a login on another machine ends the team\'s previous session. Reloading the page on the same machine ends nothing. Each drop becomes an event.')),
        ...Object.keys(K).map((k) => li(K[k].icon + ' ' + K[k].label, K[k].hint)),
        li(T('Última submissão', 'Last submission'), T('✓ = veio da máquina da sessão e da máquina do último login; ✗ = veio de outra.', '✓ = came from the session\'s machine and the last login machine; ✗ = came from another one.')),
        li(T('🔒 Trava de sede', '🔒 Site lock'), T('com a trava ligada (Máquinas & gate), o login de competidor prende o IP de origem a este contest até o fim + folga; daquele IP qualquer outro alvo leva 403 site_locked. Reivindicações e bloqueios ficam no audit e aqui.', 'with the lock on (Machines & gate), a competitor login pins the source IP to this contest until the end + grace; from that IP any other target gets 403 site_locked. Claims and blocks are in the audit and here.')),
        li(T('Sem gate', 'Without the gate'), T('nada disto vale: o painel mostra só as sessões e o log de acessos.', 'none of this applies: the panel shows only the sessions and the access log.'))));
  }

  // --- render ------------------------------------------------------------------------------
  // ATUALIZAÇÃO EM LUGAR (regra da casa, cdmoj/CLAUDE.md › Frontend): o esqueleto do painel é
  // construído UMA vez; cada tick de 30 s só troca o conteúdo dos contêineres dinâmicos, e só
  // quando o dado mudou. Refazer o painel inteiro a cada tick fechava os <details> (sessões,
  // log, "como ler"), zerava filtro e foco e dava a impressão de página recarregando.
  const SK = {};            // esqueleto: nós persistentes
  let lastSig = '';
  function skeleton() {
    SK.hdr = el('div', { class: 'section' }, el('h2', {}, T('🛡 Sessões & anomalias', '🛡 Sessions & anomalies')));
    SK.state = el('div', {}); SK.cards = el('div', {}); SK.channels = el('div', {}); SK.mass = el('div', {});
    SK.hdr.append(SK.state, SK.cards, SK.channels, SK.mass);
    SK.tl = el('div', { class: 'section', hidden: true }); SK.teams = el('div', { class: 'section', hidden: true });
    SK.sl = el('div', {});
    SK.sess = sessionsSection(); SK.acc = accessSection(); SK.legend = legend();   // estáticos: uma vez
    panel.innerHTML = '';
    panel.append(SK.hdr, SK.tl, SK.teams, SK.sl, SK.sess, SK.acc, SK.legend);
  }
  const swap = (box, node) => { box.innerHTML = ''; if (node) box.append(node); };
  function render() {
    if (!DATA) return;
    if (!SK.hdr) skeleton();
    const d = DATA, active = !!(d.gate && d.gate.active);
    swap(SK.state, stateBar(d));
    swap(SK.cards, active ? cards(d) : null);
    swap(SK.channels, channels(d));
    swap(SK.mass, massLogout(d));
    SK.tl.hidden = !active; SK.teams.hidden = !active;
    if (active) { swap(SK.tl, timeline(d)); swap(SK.teams, teamsTable(d)); }
    swap(SK.sl, siteLockSection());
  }
  // assinatura do que aparece na tela: computed_at muda a cada 15 s sem nada ter mudado, fica fora
  const sig = () => JSON.stringify([DATA && [DATA.gate, DATA.counts, DATA.anomalies, DATA.events, DATA.teams, DATA.machines, DATA.sites, DATA.channels, DATA.session_classes],
    SLOCK && [SLOCK.enabled, SLOCK.grace, SLOCK.claims, SLOCK.blocks], LOGALL && LOGALL.login_enabled]);
  async function fetchAll() {
    [DATA, SLOCK, LOGALL] = await Promise.all([
      apiGet('/contest/admin/anomalies?contest=' + enc(CONTEST), G),
      apiGet('/contest/admin/site-lock?contest=' + enc(CONTEST), G).catch(() => null),
      apiGet('/contest/admin/logout-all?contest=' + enc(CONTEST), G).catch(() => null),
    ]);
  }
  async function load() {
    if (!SK.hdr) { panel.innerHTML = ''; panel.append(el('p', { class: 'muted' }, T('Carregando…', 'Loading…'))); }
    try { await fetchAll(); }
    catch (e) { if (!SK.hdr) { panel.innerHTML = ''; panel.append(el('div', { class: 'error-box' }, e.message || T('falha ao carregar', 'failed to load'))); } return; }
    const sg = sig();
    if (sg !== lastSig || !SK.hdr) { lastSig = sg; render(); }
    if (timer) clearInterval(timer);
    timer = setInterval(async () => {
      if (panel.hidden || !panel.isConnected) return;
      try { await fetchAll(); } catch { return; }   // mantém o último quadro
      const s2 = sig(); if (s2 === lastSig) return;  // nada mudou: DOM intacto
      lastSig = s2; render();
    }, REFRESH_MS);
  }
  return { panel, load };
}
