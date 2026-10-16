// treino/admin/sessions-tab.js — a aba Sessões do painel do treino (16/10/2026).
// O que mudou depois que um clique ("todos" + "Deslogar selecionados", com a busca vazia) deslogou 1.310 contas:
//   · a própria conta e as de papel (.admin, .judge…) NÃO têm caixa de seleção (a própria aparece como "você");
//   · a seleção é LIMPA quando a busca muda — antes ela agia em linhas que o filtro escondia;
//   · deslogar 1 conta pede confirmação; 2 ou mais pedem ao servidor a PRÉVIA e abrem o cartão "digite N"
//     (confirmDanger); o .admin comum vai até 20 de uma vez, o super-admin além disso;
//   · travar e deslogar por IP são só do super-admin (o IP deixou de ser um link fácil de clicar sem querer).
// A regra de verdade é do servidor (lib/admin-bulk.sh); a tela só não oferece o que ele recusaria.
import { apiGet, apiPost } from '/shared/api.js';
import { el, fmtDate, avatarEl } from '/shared/ui.js';
import { T } from '/shared/i18n.js';
import { PRIV_RE, confirmDanger } from '/shared/admin-ui.js';

export const BULK_SMALL = 20;     // = ADMIN_BULK_SMALL do servidor
const G = () => ({ contest: 'treino', auth: true });

// selectable(sessão, meu login) — a linha pode entrar numa ação? Nunca a própria conta nem conta de papel.
export function selectable(s, me) { const l = (s && s.login) || ''; return !!l && l !== me && !PRIV_RE.test(l); }
// bulkBlock(n, super?) -> '' (pode) | o motivo de não poder
export function bulkBlock(n, isSuper) {
  if (n > BULK_SMALL && !isSuper) {
    return T(`Até ${BULK_SMALL} contas por vez. Mais do que isso é com o super-admin da plataforma.`,
      `Up to ${BULK_SMALL} accounts at a time. More than that needs the platform super-admin.`,
      `Hasta ${BULK_SMALL} cuentas por vez. Más que eso requiere al super-admin de la plataforma.`);
  }
  return '';
}

export function makeSessionsTab(ctx) {
  const isSuper = !!(ctx && ctx.isSuper), me = (ctx && ctx.me) || '';
  const panel = el('div', { class: 'section' });
  const countBadge = el('span', { class: 'tag' }, '…');
  panel.append(el('h2', {}, T('👥 Sessões ativas', '👥 Active sessions', '👥 Sesiones activas'), countBadge));
  panel.append(el('p', { class: 'small muted', style: 'margin:.1rem 0 .5rem' }, isSuper
    ? T('A sua conta e as contas de papel (.admin, .judge…) nunca entram numa ação. Duas ou mais contas pedem a prévia e a confirmação.',
      'Your own account and role accounts (.admin, .judge…) never enter an action. Two or more accounts need the preview and the confirmation.',
      'Tu cuenta y las cuentas de rol (.admin, .judge…) nunca entran en una acción. Dos o más cuentas requieren la vista previa y la confirmación.')
    : T(`A sua conta e as contas de papel (.admin, .judge…) nunca entram numa ação. Você desloga até ${BULK_SMALL} alunos por vez; travar e deslogar por IP são do super-admin.`,
      `Your own account and role accounts (.admin, .judge…) never enter an action. You log out up to ${BULK_SMALL} students at a time; locking and logging out by IP belong to the super-admin.`,
      `Tu cuenta y las cuentas de rol (.admin, .judge…) nunca entran en una acción. Cierras la sesión de hasta ${BULK_SMALL} alumnos por vez; bloquear y cerrar por IP son del super-admin.`)));

  const search = el('input', { type: 'search', placeholder: T('Buscar nome, handle ou IP (aceita regex)…', 'Search name, handle or IP (regex allowed)…', 'Buscar nombre, alias o IP (admite regex)…'), style: 'min-width:240px' });
  const matchInfo = el('span', { class: 'small muted' });
  const selAll = el('input', { type: 'checkbox', title: T('Selecionar os alunos visíveis', 'Select the visible students', 'Seleccionar los alumnos visibles') });
  const bulkLogout = el('button', { class: 'btn ghost', disabled: true });
  const bulkLock = isSuper ? el('button', { class: 'btn danger', disabled: true }) : null;
  const blockMsg = el('span', { class: 'small', style: 'color:var(--warn, #9a6700)' });
  panel.append(el('div', { class: 'toolbar' }, search, matchInfo, el('span', { style: 'flex:1' }),
    el('label', { class: 'row', style: 'gap:.3rem' }, selAll, T('visíveis', 'visible', 'visibles')),
    bulkLogout, bulkLock || '', el('button', { class: 'btn ghost', onclick: () => load() }, T('↻ Atualizar', '↻ Refresh', '↻ Actualizar'))));
  const statusLine = el('div', { class: 'small', role: 'status', 'aria-live': 'polite', style: 'margin:.2rem 0' });
  const confirmBox = el('div', {});
  const body = el('div', {}, el('div', { class: 'muted small' }, T('carregando…', 'loading…', 'cargando…')));
  panel.append(blockMsg, statusLine, confirmBox, body);

  let ALL = [];
  const checked = new Set();
  const say = (t) => { statusLine.textContent = t || ''; };

  function matcher() {
    const q = search.value.trim();
    if (!q) return () => true;
    let re = null;
    try { re = new RegExp(q, 'i'); } catch { re = null; }
    const ql = q.toLowerCase();
    return (s) => {
      const name = s.name || '', login = s.login || '', ip = s.ip || '';
      return re ? (re.test(name) || re.test(login) || re.test(ip))
        : (name.toLowerCase().includes(ql) || login.toLowerCase().includes(ql) || ip.toLowerCase().includes(ql));
    };
  }
  function updateBulk() {
    const n = checked.size, why = bulkBlock(n, isSuper);
    bulkLogout.textContent = T('Deslogar selecionados', 'Log out selected', 'Cerrar sesión de los seleccionados') + (n ? ' (' + n + ')' : '');
    bulkLogout.disabled = n === 0 || !!why;
    if (bulkLock) { bulkLock.textContent = T('Travar selecionados', 'Lock selected', 'Bloquear seleccionados') + (n ? ' (' + n + ')' : ''); bulkLock.disabled = n === 0; }
    blockMsg.textContent = why;
  }
  const visibleSelectable = () => ALL.filter(matcher()).filter((s) => selectable(s, me));
  function syncSelAll() { const rows = visibleSelectable(); selAll.checked = rows.length > 0 && rows.every((s) => checked.has(s.login)); }

  function render() {
    const rows = ALL.filter(matcher());
    matchInfo.textContent = rows.length + T(' de ', ' of ', ' de ') + ALL.length;
    body.innerHTML = '';
    if (!ALL.length) { body.append(el('div', { class: 'muted' }, T('Nenhuma sessão ativa.', 'No active sessions.', 'No hay sesiones activas.'))); syncSelAll(); updateBulk(); return; }
    if (!rows.length) { body.append(el('div', { class: 'muted' }, T('Nenhuma sessão casa com a busca.', 'No session matches the search.', 'Ninguna sesión coincide con la búsqueda.'))); syncSelAll(); updateBulk(); return; }
    const tb = el('tbody');
    rows.forEach((s) => {
      const can = selectable(s, me);
      let first;
      if (can) {
        first = el('input', { type: 'checkbox', 'aria-label': T('selecionar ', 'select ', 'seleccionar ') + s.login });
        first.checked = checked.has(s.login);
        first.addEventListener('change', () => { first.checked ? checked.add(s.login) : checked.delete(s.login); syncSelAll(); updateBulk(); });
      } else {
        first = el('span', { class: 'pill', title: T('nunca entra numa ação', 'never enters an action', 'nunca entra en una acción') },
          s.login === me ? T('você', 'you', 'tú') : T('papel', 'role', 'rol'));
      }
      const actions = el('div', { class: 'row-actions' });
      if (can) {
        actions.append(el('button', { class: 'btn ghost', onclick: () => logoutOne(s.login) }, T('Deslogar', 'Log out', 'Cerrar sesión')));
        if (isSuper) actions.append(el('button', { class: 'btn ghost danger', onclick: () => bulk('lock', [s.login]) }, T('Travar', 'Lock', 'Bloquear')));
      }
      const ipCell = el('td', { class: 'ip' }, s.ip || '—');
      if (isSuper && s.ip) {
        ipCell.append(' ', el('button', { class: 'btn ghost small', title: T('Deslogar este IP (com prévia)', 'Log out this IP (with preview)', 'Cerrar sesión de esta IP (con vista previa)'),
          onclick: () => bulk('ip', null, s.ip) }, '⏏'));
      }
      tb.append(el('tr', {},
        el('td', {}, first),
        el('td', {}, el('div', { class: 'cell-user' },
          avatarEl(s.login, s.name, 28, s.has_photo),
          el('div', {}, el('div', {}, s.name || s.login || '—'), el('div', { class: 'lg' }, '~' + (s.login || '?'))))),
        ipCell,
        el('td', { class: 'ua', title: s.user_agent || '' }, s.user_agent || '—'),
        el('td', { class: 'small' }, fmtDate(s.login_at)),
        el('td', {}, actions)));
    });
    body.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {},
        el('th', {}, ''), el('th', {}, T('Usuário', 'User', 'Usuario')), el('th', {}, 'IP'), el('th', {}, 'User-Agent'),
        el('th', {}, T('Logado em', 'Logged in at', 'Inició sesión el')), el('th', {}, T('Ações', 'Actions', 'Acciones')))), tb)));
    syncSelAll(); updateBulk();
  }

  selAll.addEventListener('change', () => {
    visibleSelectable().forEach((s) => (selAll.checked ? checked.add(s.login) : checked.delete(s.login)));
    render();
  });
  // a seleção NÃO sobrevive à busca: o que você selecionou e o filtro escondeu não pode ir junto sem você ver
  search.addEventListener('input', () => { checked.clear(); confirmBox.innerHTML = ''; render(); });

  async function load() {
    body.innerHTML = ''; body.append(el('div', { class: 'muted small' }, T('carregando…', 'loading…', 'cargando…')));
    let data;
    try { data = await apiGet('/treino/admin/sessions', G()); }
    catch (e) { body.innerHTML = ''; body.append(el('div', { class: 'error-box' }, T('Falha ao carregar sessões: ', 'Failed to load sessions: ', 'Error al cargar sesiones: ') + (e.message || ''))); return; }
    ALL = data.sessions || [];
    countBadge.textContent = ALL.length + ' ' + (ALL.length === 1 ? T('sessão', 'session', 'sesión') : T('sessões', 'sessions', 'sesiones'));
    const present = new Set(ALL.filter((s) => selectable(s, me)).map((s) => s.login));
    [...checked].forEach((l) => { if (!present.has(l)) checked.delete(l); });
    render();
  }

  const doneMsg = (r) => T('Feito: ', 'Done: ', 'Hecho: ') + (Number(r.users_count) || 0) + T(' conta(s), ', ' account(s), ', ' cuenta(s), ')
    + (Number(r.sessions_removed) || 0) + T(' sessão(ões) encerrada(s).', ' session(s) ended.', ' sesión(es) cerrada(s).')
    + (Number(r.skipped_count) ? T(' Ficaram de fora: ', ' Left out: ', ' Quedaron fuera: ') + r.skipped_count + '.' : '');

  async function logoutOne(login) {
    if (!confirm(T(`Deslogar ${login}?`, `Log out ${login}?`, `¿Cerrar la sesión de ${login}?`))) return;
    try { const r = await apiPost('/treino/admin/logout-user', { login }, G()); say(doneMsg(r)); }
    catch (e) { say(T('Falha ao deslogar: ', 'Failed to log out: ', 'Error al cerrar sesión: ') + (e.message || '')); }
    await load();
  }

  // bulk(tipo, logins, ip) — pede a PRÉVIA e abre o cartão de confirmação (o servidor decide quem entra)
  async function bulk(kind, logins, ip) {
    const route = kind === 'lock' ? '/treino/admin/lock-user' : kind === 'ip' ? '/treino/admin/logout-ip' : '/treino/admin/logout-user';
    const base = kind === 'ip' ? { ip } : { logins };
    confirmBox.innerHTML = ''; say(T('pedindo a prévia ao servidor…', 'asking the server for the preview…', 'pidiendo la vista previa al servidor…'));
    let pv;
    try { pv = await apiPost(route, { ...base, dry_run: true }, G()); }
    catch (e) { say(T('Recusado: ', 'Refused: ', 'Rechazado: ') + (e.message || '')); return; }
    say('');
    const title = kind === 'lock'
      ? T('Travar contas: a senha é trocada por uma aleatória e as sessões caem', 'Lock accounts: the password is replaced by a random one and the sessions end', 'Bloquear cuentas: la contraseña se cambia por una aleatoria y las sesiones terminan')
      : kind === 'ip' ? T(`Deslogar o IP ${ip}`, `Log out IP ${ip}`, `Cerrar sesión de la IP ${ip}`)
        : T('Deslogar as contas selecionadas', 'Log out the selected accounts', 'Cerrar sesión de las cuentas seleccionadas');
    const verb = kind === 'lock' ? T('Travar', 'Lock', 'Bloquear') : T('Deslogar', 'Log out', 'Cerrar sesión');
    confirmBox.append(confirmDanger({
      title, verb, preview: pv,
      run: (plan_id, n) => apiPost(route, { ...base, plan_id, confirm: n }, G()),
      onDone: async (r) => { say(doneMsg(r)); checked.clear(); await load(); },
      onCancel: () => say(''),
    }));
  }
  bulkLogout.addEventListener('click', () => {
    const l = [...checked];
    if (l.length === 1) logoutOne(l[0]); else if (l.length > 1) bulk('logout', l);
  });
  if (bulkLock) bulkLock.addEventListener('click', () => { const l = [...checked]; if (l.length) bulk('lock', l); });

  return { panel, load };
}
