// contest/admin/anomalies-tab.js — "Máquinas › Anomalias": o que está FORA do lugar no uso das
// máquinas DURANTE a prova — time com 2 sessões vivas em máquinas diferentes, máquina com 2 times,
// submissão vinda de outra máquina, UA fora do esperado da sede, sede com menos máquinas que times,
// trocas de máquina e a trilha da sessão única (revogações) e da trava de sede.
//
// Tudo vem de GET /contest/admin/anomalies (lib/anomalies.sh). SÓ vale com o gate de UA ligado:
// sem gate o navegador não identifica a máquina, e o painel diz isso. A chave de máquina é a do UA
// do mlinux (machine_id/boot_id) ou, sem ela, o IP. Ações: deslogar um time (logout-user) e
// "deslogar UA divergente" (logout-mismatch). Módulo `maquinas`.
//
// ATUALIZAÇÃO EM LUGAR (regra da casa): esqueleto uma vez; a cada 30 s só troca o que mudou
// (assinatura sem computed_at); <details>, filtro e foco ficam nos mesmos nós.
import { el } from '/shared/ui.js';
import { apiGet, apiPost } from '/shared/api.js';
import { fmtDate, fmtClock, stamp, toCsv, downloadText, swap, swapIf, sigOf, everyVisible } from '/shared/admin-ui.js';
import { T } from '/shared/i18n.js';
import { REFRESH_MS, KINDS, sevPill, mk, mkText, makeLogoutUser } from './sessions-common.js';

const enc = encodeURIComponent;

export function makeAnomaliesTab(CONTEST) {
  const G = { contest: CONTEST, auth: true };
  const panel = el('div', {});
  let DATA = null, stopTimer = null;
  let filterKind = '', filterText = '', showAll = false;
  const logoutUser = makeLogoutUser(CONTEST, G, () => load());
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
      el('a', { href: '#maquinas/gate', class: 'small' }, T('Gate & trava →', 'Gate & lock →')),
      el('span', { class: 'small muted' }, T('janela: ', 'window: ') + fmtClock(d.window.start) + ' → ' + fmtClock(d.window.end)
        + ' · ' + T('apurado ', 'computed ') + fmtClock(d.computed_at) + (d.round ? ' · ' + d.round : '')),
      el('button', { class: 'btn ghost', title: T('apurar de novo', 'compute again'), onclick: () => load() }, '↻'),
      g.active ? el('button', { class: 'btn ghost danger', title: T('compara cada sessão com o UA esperado da sede daquele time', 'compares each session with the expected UA of that team\'s site'),
        onclick: logoutMismatch }, T('Deslogar UA divergente', 'Log out mismatched UA')) : null);
    if (!g.active) {
      return el('div', {}, bar, el('div', { class: 'alert' },
        T('Gate de UA desligado (ou sem regra que casa): o navegador não identifica a máquina, então as anomalias de máquina não valem. Ligue o gate em Máquinas › Gate & trava. Sessões ativas e log de acessos ficam em Pessoas › Sessões.',
          'UA gate off (or no matching rule): the browser does not identify the machine, so machine anomalies do not apply. Enable the gate in Machines › Gate & lock. Active sessions and the access log live in People › Sessions.')));
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

  // --- 2. cartões (clicáveis = filtro) ------------------------------------------------------
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

  // --- 3. linha do tempo ------------------------------------------------------------------
  const fText = el('input', { type: 'search', placeholder: T('time, sede, máquina…', 'team, site, machine…'), style: 'min-width:220px' });
  fText.addEventListener('input', () => { filterText = fText.value; if (SK.tlBody) SK.tlBody(); });
  function timeline(d) {
    const K = KINDS();
    const box = el('div', {});
    const items = (d.anomalies || []).concat(d.events || []);
    items.sort((a, b) => (b.at || 0) - (a.at || 0));
    // UMA função de filtro p/ a tabela E p/ o CSV (o CSV fechava sobre uma lista velha e
    // ignorava o filtro de texto — bug de 05/09)
    const filtered = () => {
      const f = filterText.trim().toLowerCase();
      return items.filter((x) => (!filterKind || x.kind === filterKind)
        && (!f || [x.login, x.name, x.region, x.machine, JSON.stringify(x.detail || {})].join(' ').toLowerCase().includes(f)));
    };
    const chips = el('div', { class: 'row', style: 'gap:.3rem;flex-wrap:wrap' },
      ...Object.keys(K).map((k) => el('button', { class: 'btn ghost small' + (filterKind === k ? ' active' : ''),
        style: filterKind === k ? 'outline:2px solid #1e57c4' : '', title: K[k].hint,
        onclick: () => { filterKind = (filterKind === k ? '' : k); render(); } }, K[k].icon + ' ' + K[k].label)));
    const dl = el('button', { class: 'btn ghost', title: T('Baixar (CSV)', 'Download (CSV)'), onclick: () => {
      const out = [['epoch', T('datahora', 'datetime'), T('tipo', 'kind'), T('severidade', 'severity'), 'login', T('nome', 'name'), T('sede', 'site'), T('maquina', 'machine'), T('detalhe', 'detail')],
        ...filtered().map((x) => [x.at, new Date((x.at || 0) * 1000).toISOString(), x.kind, x.severity, x.login || '', x.name || '', x.region || '', x.machine || '', JSON.stringify(x.detail || {})])];
      downloadText('anomalias-' + CONTEST + '-' + stamp() + '.csv', toCsv(out), 'text/csv');
    } }, '⬇ CSV');
    const body = el('div', {});
    function detailText(x) {
      const dd = x.detail || {};
      switch (x.kind) {
        case 'multi_session': return T(`${dd.sessions} sessões em ${(dd.keys || []).length} máquinas: `, `${dd.sessions} sessions on ${(dd.keys || []).length} machines: `) + (dd.keys || []).map(mkText).join(' · ');
        case 'machine_shared': return (dd.logins || []).map((l) => `${l.login} (${fmtClock(l.first)}${l.n > 1 ? ' ×' + l.n : ''}${l.live ? ' ' + T('vivo', 'live') : ''})`).join(' · ') + (dd.live_both ? T(' — ambos com sessão viva', ' — both with a live session') : '');
        case 'sub_other_machine': return (dd.reboot ? T('reboot da mesma máquina: ', 'same machine rebooted: ') : T('sessão em ', 'session on ') + mkText(dd.session_key) + T(', requisição de ', ', request from ')) + mkText(dd.request_key) + (dd.problem ? ' · ' + dd.problem : '');
        case 'ua_mismatch': return T('esperado ', 'expected ') + (dd.expected || '') + T(' · visto: ', ' · seen: ') + (dd.ua || '');
        case 'site_short': return T(`${dd.present ?? dd.teams} times presentes, ${dd.seen} máquinas vistas (${dd.machines_total} cadastradas)`, `${dd.present ?? dd.teams} present teams, ${dd.seen} machines seen (${dd.machines_total} registered)`);
        case 'switched': return (dd.machines || []).map((m) => mkText(m.key) + ' ' + fmtClock(m.first)).join(' → ') + (dd.revoked ? T(` · ${dd.revoked} sessão(ões) revogada(s)`, ` · ${dd.revoked} session(s) revoked`) : '');
        case 'session_event': return ({ revoke: T('revogada pela sessão única (login novo em outra máquina)', 'revoked by single-session (new login on another machine)'), logout: T('deslogado pelo admin', 'logged out by the admin'), 'mismatch-logout': T('deslogado por UA divergente', 'logged out for mismatched UA') }[dd.event] || dd.event || '') + (dd.who ? ' · ' + dd.who : '') + (dd.old ? ' · ' + mkText(dd.old) + (dd.new ? ' → ' + mkText(dd.new) : '') : '');
        case 'site_lock': return dd.event === 'site-lock-block'
          ? T(`BLOQUEADO: pedido a "${dd.target && dd.target !== '-' ? dd.target : 'treino/índice'}" (${dd.route}) de IP preso a este contest`, `BLOCKED: request to "${dd.target && dd.target !== '-' ? dd.target : 'training/index'}" (${dd.route}) from an IP pinned to this contest`)
          : T(`IP preso a este contest até ${fmtClock(+dd.until || 0)}`, `IP pinned to this contest until ${fmtClock(+dd.until || 0)}`);
        default: return JSON.stringify(dd);
      }
    }
    function renderBody() {
      body.innerHTML = '';
      const rws = filtered();
      body.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, rws.length + T(' evento(s).', ' event(s).')));
      if (!rws.length) { body.append(el('div', { class: 'muted' }, T('Nada fora do lugar.', 'Nothing out of place.'))); return; }
      const tb = el('tbody');
      rws.slice(0, 400).forEach((x) => {
        const k = K[x.kind] || { icon: '', label: x.kind };
        tb.append(el('tr', { class: x.severity === 'bad' ? 'flag-row-bad' : '' },
          el('td', { class: 'small' }, fmtDate(x.at)),
          el('td', {}, sevPill(x.severity), ' ', el('span', { class: 'small' }, k.icon + ' ' + k.label)),
          el('td', {}, x.login ? el('span', { class: x.severity === 'bad' ? 'flag-anom' : '' }, x.login) : (x.name || ''), x.name && x.login && x.name !== x.login ? el('div', { class: 'small muted' }, x.name + (x.region ? ' · ' + x.region : '')) : (x.region ? el('div', { class: 'small muted' }, x.region) : '')),
          el('td', { class: 'small' }, x.kind === 'switched' || x.kind === 'session_event' ? el('code', {}, mkText(x.machine)) : x.kind === 'site_lock' ? el('code', {}, (x.machine || '').replace(/^ip:/, 'ip ')) : mk(x.machine)),
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
    const box = el('div', {});
    const tog = el('label', { class: 'small', style: 'display:inline-flex;gap:.3rem;align-items:center' },
      el('input', { type: 'checkbox', checked: showAll, onchange: (ev) => { showAll = ev.target.checked; render(); } }),
      T('mostrar todos os times com sessão', 'show all teams with a session'));
    const tb = el('tbody');
    rows.forEach((t) => {
      const keys = [...new Set((t.sessions || []).map((s) => s.key))];
      const ls = t.last_sub;
      tb.append(el('tr', {},
        el('td', {}, el('span', { class: (t.flags || []).some((f) => f === 'multi_session' || f === 'sub_other_machine') ? 'flag-anom' : '' }, t.login), t.name && t.name !== t.login ? el('div', { class: 'small muted' }, t.name + (t.region ? ' · ' + t.region : '')) : ''),
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

  // --- 5. como ler --------------------------------------------------------------------------
  function legend() {
    const K = KINDS();
    const li = (k, txt) => el('li', {}, el('b', {}, k + ': '), txt);
    return el('details', { class: 'small', style: 'margin:.5rem 0' }, el('summary', {}, T('📖 Como ler', '📖 How to read')),
      el('ul', { style: 'margin:.2rem 0 0 1.1rem' },
        li(T('Máquina', 'Machine'), T('a chave vem do navegador do mlinux (machine_id/boot_id). Um reboot muda o boot_id: a mesma máquina aparece como outra. Login sem essa chave (navegador comum) só tem o IP, que atrás de NAT é a sede inteira — por isso IP nunca conta como máquina.', 'the key comes from the mlinux browser (machine_id/boot_id). A reboot changes the boot_id: the same machine shows up as another. A login without that key (regular browser) only has the IP, which behind NAT is the whole site — so an IP never counts as a machine.')),
        li(T('Sessão única', 'Single session'), T('com o gate ligado, um login em outra máquina derruba a sessão anterior do time. Recarregar a página na mesma máquina não derruba nada. Cada queda vira um evento aqui.', 'with the gate on, a login on another machine ends the team\'s previous session. Reloading the page on the same machine ends nothing. Each drop becomes an event here.')),
        ...Object.keys(K).map((k) => li(K[k].icon + ' ' + K[k].label, K[k].hint)),
        li(T('Última submissão', 'Last submission'), T('✓ = veio da máquina da sessão e da máquina do último login; ✗ = veio de outra.', '✓ = came from the session\'s machine and the last login machine; ✗ = came from another.')),
        li(T('🔒 Trava de sede', '🔒 Site lock'), T('com a trava ligada (Gate & trava), o login de competidor prende o IP de origem a este contest até o fim + folga; daquele IP qualquer outro alvo (treino, outro contest) responde 403 e vira um bloqueio aqui.', 'with the lock on (Gate & lock), a competitor login pins the source IP to this contest until the end + grace; from that IP any other target (training, another contest) answers 403 and becomes a block here.')),
        li(T('Sem gate', 'Without the gate'), T('nada disto vale: veja as sessões e o log em Pessoas › Sessões.', 'none of this applies: see sessions and the log in People › Sessions.'))));
  }

  // --- esqueleto + render em lugar -------------------------------------------------------------
  const SK = {};
  let lastSig = '';
  function skeleton() {
    SK.hdr = el('div', { class: 'section' }, el('h2', {}, T('🛡️ Anomalias de máquina', '🛡️ Machine anomalies')));
    SK.err = el('div', {}); SK.state = el('div', {}); SK.cards = el('div', {}); SK.channels = el('div', {});
    SK.hdr.append(SK.err, SK.state, SK.cards, SK.channels);
    SK.tl = el('div', { class: 'section', hidden: true }, el('h2', {}, T('🕒 Linha do tempo', '🕒 Timeline')), SK.tlBox = el('div', {}));
    SK.teams = el('div', { class: 'section', hidden: true }, el('h2', {}, T('👥 Times', '👥 Teams')), SK.teamsBox = el('div', {}));
    SK.legend = legend();
    panel.innerHTML = '';
    panel.append(SK.hdr, SK.tl, SK.teams, SK.legend);
  }
  function render() {
    if (!DATA) return;
    if (!SK.hdr) skeleton();
    const d = DATA, active = !!(d.gate && d.gate.active);
    swap(SK.state, stateBar(d));
    swap(SK.cards, active ? cards(d) : null);
    swap(SK.channels, channels(d));
    SK.tl.hidden = !active; SK.teams.hidden = !active;
    if (active) { swap(SK.tlBox, timeline(d)); swap(SK.teamsBox, teamsTable(d)); }
  }
  // assinatura do que aparece na tela: computed_at muda a cada 15 s sem nada ter mudado, fica fora
  const sig = () => sigOf(DATA && [DATA.gate, DATA.counts, DATA.anomalies, DATA.events, DATA.teams, DATA.machines, DATA.sites, DATA.channels]);
  async function fetchAll() { DATA = await apiGet('/contest/admin/anomalies?contest=' + enc(CONTEST), G); }
  async function load() {
    if (!SK.hdr) { skeleton(); SK.err.append(el('p', { class: 'muted' }, T('Carregando…', 'Loading…'))); }
    try { await fetchAll(); SK.err.innerHTML = ''; }
    catch (e) { SK.err.innerHTML = ''; SK.err.append(el('div', { class: 'error-box' }, e.message || T('falha ao carregar', 'failed to load'))); return; }
    const sg = sig();
    if (sg !== lastSig) { lastSig = sg; render(); }
    if (stopTimer) stopTimer();
    stopTimer = everyVisible(panel, REFRESH_MS, async () => {
      try { await fetchAll(); } catch { return; }   // mantém o último quadro
      const s2 = sig(); if (s2 === lastSig) return;  // nada mudou: DOM intacto
      lastSig = s2; render();
    });
  }
  return { panel, load };
}
