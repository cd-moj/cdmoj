// contest/admin/anomalies-tab.js — "Máquinas › Anomalias": o que está FORA do lugar no uso das
// máquinas DURANTE a prova — time com 2 sessões vivas em máquinas diferentes, máquina com 2 times,
// submissão vinda de outra máquina, UA fora do esperado da sede, sede com menos máquinas que times,
// trocas de máquina e a trilha da sessão única (revogações) e da trava de sede.
//
// Tudo vem de GET /contest/admin/anomalies (lib/anomalies.sh). Quem identifica a MÁQUINA é o UA do mlinux
// (machine_id/boot_id; sem ele só o IP, que não conta): as anomalias de máquina aparecem com ou sem gate
// (`machines_identified` — TCP 2026, 03/10/2026: sem gate o painel ficava vazio com times em 2–3 máquinas).
// O gate (Barrar ou Observar) acrescenta o "UA fora do esperado". Ações: deslogar um time (logout-user),
// "deslogar UA divergente" (logout-mismatch) e EXPLICAR um caso (POST {action:"explain"}: sai das contagens e
// fica na lista, apagado, com quem/motivo). Módulo `maquinas`.
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
    if (!confirm(T('Deslogar todas as sessões cujo UA não bate o esperado da sede?', 'Log out all sessions whose UA does not match the site\'s expected one?', '¿Desconectar todas las sesiones cuyo UA no coincide con el esperado de la sede?'))) return;
    try { const r = await apiPost('/contest/admin/logout-mismatch?contest=' + enc(CONTEST), {}, G); alert(r.sessions_removed + T(' sessão(ões) encerradas.', ' session(s) ended.', ' sesión(es) terminada(s).')); await load(); }
    catch (e) { alert(e.message || T('falha', 'failed', 'fallido')); }
  }

  // EXPLICAR um caso (troca por defeito confirmada etc.): sai das contagens, fica na lista com quem/motivo
  async function explain(x, undo) {
    let note = '';
    if (!undo) {
      note = prompt(T('Motivo (fica registrado, ex.: "trocou de máquina por defeito, confirmado pela sede"):', 'Reason (it is recorded, e.g. "switched machine after a failure, confirmed by the site"):', 'Motivo (queda registrado, ej.: "cambió de máquina por una falla, confirmado por la sede"):'), '');
      if (note == null || !note.trim()) return;
    }
    try { await apiPost('/contest/admin/anomalies?contest=' + enc(CONTEST), undo ? { action: 'unexplain', id: x.id } : { action: 'explain', id: x.id, note: note.trim() }, G); await load(); }
    catch (e) { alert(e.message || T('falha', 'failed', 'fallido')); }
  }

  // --- 1. barra de estado -----------------------------------------------------------------
  function stateBar(d) {
    const g = d.gate || {};
    const ident = !!d.machines_identified;
    const gateTxt = g.active ? (g.enforcing ? T('gate: barrando', 'gate: blocking', 'gate: bloqueando') : T('gate: só observando (não barra)', 'gate: observing only (no blocking)', 'gate: solo observando (no bloquea)'))
      : T('gate desligado', 'gate off', 'gate apagado');
    const bar = el('div', { class: 'row', style: 'gap:.6rem;flex-wrap:wrap;align-items:center;margin:.2rem 0 .6rem' },
      el('span', { class: 'pill ' + (g.active ? 'ok' : '') }, gateTxt),
      el('span', { class: 'pill ' + (ident ? 'ok' : '') }, ident ? T('máquinas identificadas (MLinux)', 'machines identified (MLinux)', 'máquinas identificadas (MLinux)') : T('nenhuma máquina identificada', 'no machine identified', 'ninguna máquina identificada')),
      el('span', { class: 'pill ' + (g.single_session && g.enforcing ? 'ok' : '') }, g.single_session && g.enforcing ? T('sessão única por time', 'single session per team', 'sesión única por equipo') : T('sessão única não vale', 'single session not in effect', 'sesión única no vale')),
      el('a', { href: '#maquinas/gate', class: 'small' }, T('Gate & trava →', 'Gate & lock →', 'Gate y bloqueo →')),
      el('span', { class: 'small muted' }, T('janela: ', 'window: ', 'ventana: ') + fmtClock(d.window.start) + ' → ' + fmtClock(d.window.end)
        + ' · ' + T('apurado ', 'computed ', 'calculado ') + fmtClock(d.computed_at) + (d.round ? ' · ' + d.round : '')),
      el('button', { class: 'btn ghost', title: T('apurar de novo', 'compute again', 'calcular de nuevo'), onclick: () => load() }, '↻'),
      g.active ? el('button', { class: 'btn ghost danger', title: T('compara cada sessão com o UA esperado da sede daquele time', 'compares each session with the expected UA of that team\'s site', 'compara cada sesión con el UA esperado de la sede de ese equipo'),
        onclick: logoutMismatch }, T('Deslogar UA divergente', 'Log out mismatched UA', 'Desconectar UA divergente')) : null);
    if (!g.active && !ident) {
      return el('div', {}, bar, el('div', { class: 'alert' },
        T('Nenhuma máquina identificada: as anomalias de máquina dependem do navegador do MLinux (que se identifica no User-Agent). Com navegador comum só há o IP, que atrás de NAT é a sede inteira. Sessões ativas e log de acessos ficam em Pessoas › Sessões.',
          'No machine identified: machine anomalies depend on the MLinux browser (which identifies itself in the User-Agent). With a regular browser there is only the IP, which behind NAT is the whole site. Active sessions and the access log live in People › Sessions.',
          'Ninguna máquina identificada: las anomalías de máquina dependen del navegador del MLinux (que se identifica en el User-Agent). Con un navegador común solo hay el IP, que detrás de NAT es la sede entera. Las sesiones activas y el log de accesos están en Personas › Sesiones.')));
    }
    if (!g.active) {
      return el('div', {}, bar, el('div', { class: 'small muted', style: 'margin:-.3rem 0 .5rem' },
        T('Sem gate: o MOJ não barra ninguém. As anomalias de máquina vêm do navegador do MLinux; o "UA fora do esperado" só aparece com o gate em Barrar ou Observar (Máquinas › Gate & trava).',
          'Without the gate: MOJ blocks nobody. Machine anomalies come from the MLinux browser; "UA outside the expected" only shows with the gate in Block or Observe (Machines › Gate & lock).',
          'Sin gate: el MOJ no bloquea a nadie. Las anomalías de máquina vienen del navegador del MLinux; el "UA fuera de lo esperado" solo aparece con el gate en Bloquear u Observar (Máquinas › Gate y bloqueo).')));
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
        T('Canal dos pedidos na prova (pelo User-Agent: a CLI se marca "moj-comp/<build>")', 'Request channel in the contest (by User-Agent: the CLI marks itself "moj-comp/<build>")', 'Canal de los pedidos en la competencia (por User-Agent: la CLI se marca "moj-comp/<build>")')),
      el('div', { class: 'dash-cards' },
        cell(L.web, T('logins web', 'web logins', 'logins web')), cell(L.cli, T('logins CLI', 'CLI logins', 'logins CLI')), cell(L.other, T('logins outros', 'other logins', 'otros logins')),
        cell(S.web, T('submissões web', 'web submissions', 'envíos web')), cell(S.cli, T('submissões CLI', 'CLI submissions', 'envíos CLI')), cell(S.offline, T('pacotes offline', 'offline packets', 'paquetes offline'))));
  }

  // --- 2. cartões (clicáveis = filtro) ------------------------------------------------------
  function cards(d) {
    const c = d.counts || {}, K = KINDS();
    const card = (val, lbl, kind, warn) => el('div', { class: 'dash-card' + (warn && val > 0 ? ' warn' : ''),
      style: 'cursor:pointer' + (filterKind === kind ? ';outline:2px solid #1e57c4' : ''),
      title: K[kind] ? K[kind].hint : '', onclick: () => { filterKind = (filterKind === kind ? '' : kind); render(); } },
    el('div', { class: 'dash-val' }, String(val)), el('div', { class: 'dash-lbl' }, lbl));
    return el('div', { class: 'dash-cards' },
      el('div', { class: 'dash-card', title: T('sessões vivas de times neste contest', 'live team sessions in this contest', 'sesiones vivas de equipos en esta competencia') },
        el('div', { class: 'dash-val' }, String(c.sessions || 0)), el('div', { class: 'dash-lbl' }, T('sessões ativas', 'active sessions', 'sesiones activas') + ' · ' + (c.teams_live || 0) + T(' times', ' teams', ' equipos'))),
      card(c.multi_session || 0, K.multi_session.label, 'multi_session', true),
      card(c.machine_shared || 0, K.machine_shared.label, 'machine_shared', true),
      card(c.sub_other_machine || 0, K.sub_other_machine.label, 'sub_other_machine', true),
      card(c.ua_mismatch || 0, K.ua_mismatch.label, 'ua_mismatch', true),
      card(c.site_short || 0, K.site_short.label, 'site_short', true),
      card(c.switched || 0, K.switched.label, 'switched', false),
      card(c.revoked || 0, T('revogações', 'revocations', 'revocaciones'), 'session_event', false),
      card(c.site_lock_blocks || 0, T('bloqueios da trava', 'lock blocks', 'bloqueos del bloqueo de sede'), 'site_lock', true),
      // só aparece quando o webhook do nutellaboot já entregou algum alerta (contest sem mlinux não ganha cartão vazio)
      (c.machine_alerts ? card(c.machine_alerts, K.machine_alert.label, 'machine_alert', true) : null),
      (c.machine_events ? card(c.machine_events, K.machine_event.label, 'machine_event', false) : null),
      (c.explained ? card(c.explained, T('✓ explicadas', '✓ explained', '✓ explicadas'), 'explained', false) : null));
  }

  // --- 3. linha do tempo ------------------------------------------------------------------
  const fText = el('input', { type: 'search', placeholder: T('time, sede, máquina…', 'team, site, machine…', 'equipo, sede, máquina…'), style: 'min-width:220px' });
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
      return items.filter((x) => (!filterKind || (filterKind === 'explained' ? !!x.explained : x.kind === filterKind))
        && (!f || [x.login, x.name, x.region, x.machine, JSON.stringify(x.detail || {})].join(' ').toLowerCase().includes(f)));
    };
    const chips = el('div', { class: 'row', style: 'gap:.3rem;flex-wrap:wrap' },
      ...Object.keys(K).map((k) => el('button', { class: 'btn ghost small' + (filterKind === k ? ' active' : ''),
        style: filterKind === k ? 'outline:2px solid #1e57c4' : '', title: K[k].hint,
        onclick: () => { filterKind = (filterKind === k ? '' : k); render(); } }, K[k].icon + ' ' + K[k].label)));
    const dl = el('button', { class: 'btn ghost', title: T('Baixar (CSV)', 'Download (CSV)', 'Descargar (CSV)'), onclick: () => {
      const out = [['epoch', T('datahora', 'datetime', 'fechahora'), T('tipo', 'kind', 'tipo'), T('severidade', 'severity', 'severidad'), 'login', T('nome', 'name', 'nombre'), T('sede', 'site', 'sede'), T('maquina', 'machine', 'máquina'), T('detalhe', 'detail', 'detalle')],
        ...filtered().map((x) => [x.at, new Date((x.at || 0) * 1000).toISOString(), x.kind, x.severity, x.login || '', x.name || '', x.region || '', x.machine || '', JSON.stringify(x.detail || {})])];
      downloadText('anomalias-' + CONTEST + '-' + stamp() + '.csv', toCsv(out), 'text/csv');
    } }, '⬇ CSV');
    const body = el('div', {});
    function detailText(x) {
      const dd = x.detail || {};
      switch (x.kind) {
        case 'multi_session': return T(`${dd.sessions} sessões em ${(dd.keys || []).length} máquinas: `, `${dd.sessions} sessions on ${(dd.keys || []).length} machines: `, `${dd.sessions} sesiones en ${(dd.keys || []).length} máquinas: `) + (dd.keys || []).map(mkText).join(' · ');
        case 'machine_shared': return (dd.logins || []).map((l) => `${l.login} (${fmtClock(l.first)}${l.n > 1 ? ' ×' + l.n : ''}${l.live ? ' ' + T('vivo', 'live', 'vivo') : ''})`).join(' · ') + (dd.live_both ? T(' — ambos com sessão viva', ' — both with a live session', ' — ambos con sesión viva') : '');
        case 'sub_other_machine': return (dd.reboot ? T('reboot da mesma máquina: ', 'same machine rebooted: ', 'misma máquina reiniciada: ') : T('sessão em ', 'session on ', 'sesión en ') + mkText(dd.session_key) + T(', requisição de ', ', request from ', ', pedido de ')) + mkText(dd.request_key) + (dd.problem ? ' · ' + dd.problem : '');
        case 'ua_mismatch': return T('esperado ', 'expected ', 'esperado ') + (dd.expected || '') + T(' · visto: ', ' · seen: ', ' · visto: ') + (dd.ua || '');
        case 'site_short': return T(`${dd.present ?? dd.teams} times presentes, ${dd.seen} máquinas vistas (${dd.machines_total} cadastradas)`, `${dd.present ?? dd.teams} present teams, ${dd.seen} machines seen (${dd.machines_total} registered)`, `${dd.present ?? dd.teams} equipos presentes, ${dd.seen} máquinas vistas (${dd.machines_total} registradas)`);
        case 'switched': return (dd.machines || []).map((m) => mkText(m.key) + ' ' + fmtClock(m.first)).join(' → ') + (dd.revoked ? T(` · ${dd.revoked} sessão(ões) revogada(s)`, ` · ${dd.revoked} session(s) revoked`, ` · ${dd.revoked} sesión(es) revocada(s)`) : '');
        case 'session_event': return ({ revoke: T('revogada pela sessão única (login novo em outra máquina)', 'revoked by single-session (new login on another machine)', 'revocada por sesión única (nuevo login en otra máquina)'), logout: T('deslogado pelo admin', 'logged out by the admin', 'desconectado por el admin'), 'mismatch-logout': T('deslogado por UA divergente', 'logged out for mismatched UA', 'desconectado por UA divergente') }[dd.event] || dd.event || '') + (dd.who ? ' · ' + dd.who : '') + (dd.old ? ' · ' + mkText(dd.old) + (dd.new ? ' → ' + mkText(dd.new) : '') : '');
        case 'site_lock': return dd.event === 'site-lock-block'
          ? T(`BLOQUEADO: pedido a "${dd.target && dd.target !== '-' ? dd.target : 'treino/índice'}" (${dd.route}) de IP preso a este contest`, `BLOCKED: request to "${dd.target && dd.target !== '-' ? dd.target : 'training/index'}" (${dd.route}) from an IP pinned to this contest`, `BLOQUEADO: pedido a "${dd.target && dd.target !== '-' ? dd.target : 'entrenamiento/índice'}" (${dd.route}) desde una IP fijada a esta competencia`)
          : T(`IP preso a este contest até ${fmtClock(+dd.until || 0)}`, `IP pinned to this contest until ${fmtClock(+dd.until || 0)}`, `IP fijada a esta competencia hasta ${fmtClock(+dd.until || 0)}`);
        case 'machine_alert': {
          const an = ({ 'usb.storage': T('pendrive ou HD externo', 'USB storage', 'almacenamiento USB'), 'usb.phone': T('celular', 'phone', 'celular'), 'usb.network': T('rede por USB', 'USB network', 'red USB'),
            'usb.other': T('outro dispositivo USB', 'other USB device', 'otro dispositivo USB'), 'identity.duplicate': T('identidade repetida', 'duplicate identity', 'identidad duplicada'),
            'display.multiple': T('mais de um monitor', 'more than one monitor', 'más de un monitor') })[dd.alert] || dd.alert;
          return (dd.event === 'alert.dismissed' ? T('dispensado: ', 'dismissed: ', 'descartado: ') : '') + an + (dd.vendor ? ' (' + dd.vendor + ')' : '') + (dd.text ? ' — ' + dd.text : '')
            + T(` · sede ${dd.image}, máquina ${dd.mac}`, ` · site ${dd.image}, machine ${dd.mac}`, ` · sede ${dd.image}, máquina ${dd.mac}`) + (dd.other_mac ? T(`, igual a ${dd.other_mac}`, `, same as ${dd.other_mac}`, `, igual a ${dd.other_mac}`) : '')
            + (dd.notified ? T(' · avisado por Telegram', ' · notified by Telegram', ' · avisado por Telegram') : '');
        }
        case 'machine_event': {
          const ev = ({ 'machine.rebooted': T('reiniciou', 'rebooted', 'reinició'), 'machine.offline': T('parou de reportar', 'stopped reporting', 'dejó de reportar'), 'machine.online': T('voltou', 'came back', 'volvió') })[dd.event] || dd.event;
          return ev + T(` · sede ${dd.image}, máquina ${dd.mac}`, ` · site ${dd.image}, machine ${dd.mac}`, ` · sede ${dd.image}, máquina ${dd.mac}`)
            + (dd.event === 'machine.rebooted' && dd.boots ? T(` · ${dd.boots}º boot`, ` · boot #${dd.boots}`, ` · boot #${dd.boots}`) : '')
            + (dd.event === 'machine.online' && dd.offline_for ? T(` · ficou ${Math.round(dd.offline_for / 60)} min fora`, ` · was ${Math.round(dd.offline_for / 60)} min away`, ` · estuvo ${Math.round(dd.offline_for / 60)} min fuera`) : '');
        }
        default: return JSON.stringify(dd);
      }
    }
    function renderBody() {
      body.innerHTML = '';
      const rws = filtered();
      body.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, rws.length + T(' evento(s).', ' event(s).', ' evento(s).')));
      if (!rws.length) { body.append(el('div', { class: 'muted' }, T('Nada fora do lugar.', 'Nothing out of place.', 'Nada fuera de lugar.'))); return; }
      const tb = el('tbody');
      rws.slice(0, 400).forEach((x) => {
        const k = K[x.kind] || { icon: '', label: x.kind };
        const xp = x.explained;
        tb.append(el('tr', { class: !xp && x.severity === 'bad' ? 'flag-row-bad' : '', style: xp ? 'opacity:.55' : '' },
          el('td', { class: 'small' }, fmtDate(x.at)),
          el('td', {}, sevPill(x.severity), ' ', el('span', { class: 'small' }, k.icon + ' ' + k.label)),
          el('td', {}, x.login ? el('span', { class: x.severity === 'bad' ? 'flag-anom' : '' }, x.login) : (x.name || ''), x.name && x.login && x.name !== x.login ? el('div', { class: 'small muted' }, x.name + (x.region ? ' · ' + x.region : '')) : (x.region ? el('div', { class: 'small muted' }, x.region) : '')),
          el('td', { class: 'small' }, x.kind === 'switched' || x.kind === 'session_event' ? el('code', {}, mkText(x.machine)) : x.kind === 'site_lock' ? el('code', {}, (x.machine || '').replace(/^ip:/, 'ip ')) : mk(x.machine)),
          el('td', { class: 'small' }, detailText(x),
            xp ? el('div', { class: 'small' }, '✓ ' + T('explicada por ', 'explained by ', 'explicada por ') + (xp.by || '') + ' · ' + fmtClock(xp.at) + (xp.note ? ' — ' + xp.note : '')) : ''),
          el('td', { style: 'white-space:nowrap' },
            x.id ? el('button', { class: 'btn ghost small', title: xp ? T('volta a contar', 'counts again', 'vuelve a contar') : T('registra o motivo e tira das contagens', 'records the reason and removes it from the counts', 'registra el motivo y lo saca de los conteos'),
              onclick: () => explain(x, !!xp) }, xp ? T('desfazer', 'undo', 'deshacer') : T('explicar', 'explain', 'explicar')) : '',
            x.login && !x.login.includes(',') && x.kind !== 'site_short' ? el('button', { class: 'btn ghost small', onclick: () => logoutUser(x.login) }, T('deslogar', 'log out', 'cerrar sesión')) : '')));
      });
      body.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' }, el('thead', {}, el('tr', {},
        el('th', {}, T('Quando', 'When', 'Cuándo')), el('th', {}, T('Tipo', 'Type', 'Tipo')), el('th', {}, T('Time', 'Team', 'Equipo')), el('th', {}, T('Máquina', 'Machine', 'Máquina')), el('th', {}, T('Detalhe', 'Detail', 'Detalle')), el('th', {}, ''))), tb)));
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
      T('mostrar todos os times com sessão', 'show all teams with a session', 'mostrar todos los equipos con sesión'));
    const tb = el('tbody');
    rows.forEach((t) => {
      const keys = [...new Set((t.sessions || []).map((s) => s.key))];
      const ls = t.last_sub;
      tb.append(el('tr', {},
        el('td', {}, el('span', { class: (t.flags || []).some((f) => f === 'multi_session' || f === 'sub_other_machine') ? 'flag-anom' : '' }, t.login), t.name && t.name !== t.login ? el('div', { class: 'small muted' }, t.name + (t.region ? ' · ' + t.region : '')) : ''),
        el('td', { class: 'n' }, String((t.sessions || []).length) + (keys.length > 1 ? ' ' + T('em', 'on', 'en') + ' ' + keys.length + ' ' + T('máq.', 'mach.', 'máq.') : '')),
        el('td', { class: 'small' }, ...(t.machines || []).filter((m) => m.in > 0).flatMap((m, i) => [i ? ' → ' : '', mk(m.key), el('span', { class: 'muted' }, ' ' + fmtClock(m.first))])),
        el('td', { class: 'small' }, ls ? [fmtClock(ls.at), ' ', mk(ls.key), ' ', el('span', { class: ls.same_as_session && ls.same_as_login_machine ? 'v-ok' : 'flag-anom' }, ls.same_as_session && ls.same_as_login_machine ? '✓' : '✗')] : '—'),
        el('td', {}, ...(t.flags || []).map((f) => el('span', { class: 'pill small', style: 'margin-right:.2rem', title: K[f] ? K[f].hint : f }, (K[f] || {}).icon + ' ' + ((K[f] || {}).label || f)))),
        el('td', {}, el('button', { class: 'btn ghost small', onclick: () => logoutUser(t.login) }, T('deslogar', 'log out', 'cerrar sesión')))));
    });
    box.append(el('div', { class: 'row', style: 'gap:.6rem;align-items:center;margin-bottom:.3rem' }, tog,
      el('span', { class: 'small muted' }, rows.length + T(' time(s).', ' team(s).', ' equipo(s).'))),
    el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' }, el('thead', {}, el('tr', {},
      el('th', {}, T('Time', 'Team', 'Equipo')), el('th', { class: 'n' }, T('Sessões', 'Sessions', 'Sesiones')), el('th', {}, T('Máquinas na prova', 'Machines in contest', 'Máquinas en la competencia')),
      el('th', {}, T('Última submissão', 'Last submission', 'Último envío')), el('th', {}, T('Anomalias', 'Anomalies', 'Anomalías')), el('th', {}, ''))), tb)));
    return box;
  }

  // --- 5. como ler --------------------------------------------------------------------------
  function legend() {
    const K = KINDS();
    const li = (k, txt) => el('li', {}, el('b', {}, k + ': '), txt);
    return el('details', { class: 'small', style: 'margin:.5rem 0' }, el('summary', {}, T('📖 Como ler', '📖 How to read', '📖 Cómo leer')),
      el('ul', { style: 'margin:.2rem 0 0 1.1rem' },
        li(T('Máquina', 'Machine', 'Máquina'), T('a chave vem do navegador do mlinux (machine_id/boot_id). Um reboot muda o boot_id: a mesma máquina aparece como outra. Login sem essa chave (navegador comum) só tem o IP, que atrás de NAT é a sede inteira — por isso IP nunca conta como máquina.', 'the key comes from the mlinux browser (machine_id/boot_id). A reboot changes the boot_id: the same machine shows up as another. A login without that key (regular browser) only has the IP, which behind NAT is the whole site — so an IP never counts as a machine.', 'la clave viene del navegador del mlinux (machine_id/boot_id). Un reinicio cambia el boot_id: la misma máquina aparece como otra. Un login sin esa clave (navegador común) solo tiene el IP, que detrás de NAT es la sede entera — por eso un IP nunca cuenta como máquina.')),
        li(T('Sessão única', 'Single session', 'Sesión única'), T('com o gate em Barrar, um login em outra máquina derruba a sessão anterior do time (em Observar, não). Recarregar a página na mesma máquina não derruba nada. Cada queda vira um evento aqui.', 'with the gate in Block, a login on another machine ends the team\'s previous session (in Observe, it does not). Reloading the page on the same machine ends nothing. Each drop becomes an event here.', 'con el gate en Bloquear, un login en otra máquina termina la sesión anterior del equipo (en Observar, no). Recargar la página en la misma máquina no termina nada. Cada caída se vuelve un evento aquí.')),
        li(T('✓ Explicada', '✓ Explained', '✓ Explicada'), T('a organização registrou o motivo (ex.: troca por defeito confirmada): o caso sai das contagens e fica na lista, apagado. Se o caso mudar (outra máquina), ele volta.', 'the organization recorded the reason (e.g. a confirmed switch after a failure): the case leaves the counts and stays in the list, dimmed. If the case changes (another machine), it comes back.', 'la organización registró el motivo (ej.: cambio por falla confirmado): el caso sale de los conteos y queda en la lista, atenuado. Si el caso cambia (otra máquina), vuelve.')),
        ...Object.keys(K).map((k) => li(K[k].icon + ' ' + K[k].label, K[k].hint)),
        li(T('Última submissão', 'Last submission', 'Último envío'), T('✓ = veio da máquina da sessão e da máquina do último login; ✗ = veio de outra.', '✓ = came from the session\'s machine and the last login machine; ✗ = came from another.', '✓ = vino de la máquina de la sesión y de la máquina del último login; ✗ = vino de otra.')),
        li(T('🔒 Trava de sede', '🔒 Site lock', '🔒 Bloqueo de sede'), T('com a trava ligada (Gate & trava), o login de competidor prende o IP de origem a este contest até o fim + folga; daquele IP qualquer outro alvo (treino, outro contest) responde 403 e vira um bloqueio aqui.', 'with the lock on (Gate & lock), a competitor login pins the source IP to this contest until the end + grace; from that IP any other target (training, another contest) answers 403 and becomes a block here.', 'con el bloqueo activo (Gate y bloqueo), un login de competidor fija el IP de origen a esta competencia hasta el fin + margen; desde ese IP cualquier otro destino (entrenamiento, otra competencia) responde 403 y se vuelve un bloqueo aquí.')),
        li(T('Sem gate', 'Without the gate', 'Sin el gate'), T('as anomalias de máquina continuam (vêm do navegador do MLinux); falta só o "UA fora do esperado", que precisa do esperado de cada time.', 'machine anomalies still apply (they come from the MLinux browser); only "UA outside the expected" is missing, because it needs each team\'s expected UA.', 'las anomalías de máquina siguen (vienen del navegador del MLinux); solo falta el "UA fuera de lo esperado", que necesita el esperado de cada equipo.'))));
  }

  // --- esqueleto + render em lugar -------------------------------------------------------------
  const SK = {};
  let lastSig = '';
  function skeleton() {
    SK.hdr = el('div', { class: 'section' }, el('h2', {}, T('🛡️ Anomalias de máquina', '🛡️ Machine anomalies', '🛡️ Anomalías de máquina')));
    SK.err = el('div', {}); SK.state = el('div', {}); SK.cards = el('div', {}); SK.channels = el('div', {});
    SK.hdr.append(SK.err, SK.state, SK.cards, SK.channels);
    SK.tl = el('div', { class: 'section', hidden: true }, el('h2', {}, T('🕒 Linha do tempo', '🕒 Timeline', '🕒 Línea de tiempo')), SK.tlBox = el('div', {}));
    SK.teams = el('div', { class: 'section', hidden: true }, el('h2', {}, T('👥 Times', '👥 Teams', '👥 Equipos')), SK.teamsBox = el('div', {}));
    SK.legend = legend();
    panel.innerHTML = '';
    panel.append(SK.hdr, SK.tl, SK.teams, SK.legend);
  }
  function render() {
    if (!DATA) return;
    if (!SK.hdr) skeleton();
    // a tela vale com o gate (Barrar/Observar) OU com máquina identificada pelo UA do mlinux
    const d = DATA, active = !!((d.gate && d.gate.active) || d.machines_identified);
    swap(SK.state, stateBar(d));
    swap(SK.cards, active ? cards(d) : null);
    swap(SK.channels, channels(d));
    SK.tl.hidden = !active; SK.teams.hidden = !active;
    if (active) { swap(SK.tlBox, timeline(d)); swap(SK.teamsBox, teamsTable(d)); }
  }
  // assinatura do que aparece na tela: computed_at muda a cada 15 s sem nada ter mudado, fica fora
  const sig = () => sigOf(DATA && [DATA.gate, DATA.machines_identified, DATA.counts, DATA.anomalies, DATA.events, DATA.teams, DATA.machines, DATA.sites, DATA.channels]);
  async function fetchAll() { DATA = await apiGet('/contest/admin/anomalies?contest=' + enc(CONTEST), G); }
  async function load() {
    if (!SK.hdr) { skeleton(); SK.err.append(el('p', { class: 'muted' }, T('Carregando…', 'Loading…', 'Cargando…'))); }
    try { await fetchAll(); SK.err.innerHTML = ''; }
    catch (e) { SK.err.innerHTML = ''; SK.err.append(el('div', { class: 'error-box' }, e.message || T('falha ao carregar', 'failed to load', 'falló al cargar'))); return; }
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
