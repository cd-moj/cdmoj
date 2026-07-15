// treino/admin/admin.js — painel administrativo do Treino Livre (.admin apenas).
// Abas: sessões ativas, log de acessos, estatísticas, fila de submissões e
// máquinas de julgamento. Consome a API admin (Bearer + .admin) — não-admin → 403.
//   GET  /treino/admin/sessions    {count, sessions:[{login,name,ip,user_agent,login_at}]}
//   GET  /treino/admin/access-log?day=YYYY-MM-DD  {day, entries:[{time,login,ip,user_agent}]}
//   GET  /treino/admin/queue       {total_pending, spool_queued, calib_pending, calib_inflight, calib_targeted, lists:[{contest,name,pending}]}
//   GET  /treino/admin/judges      {online, busy, machines:[{host,online,busy,tl,cache,current:{kind,problem_id,...}|null,queued_calibrate}], ...}
//   GET  /treino/admin/stats       {users, active_sessions, problems:{total,public,private}, by_author:[{author,total,public,private}], problems_public_by_day:[{day,count}], logins_per_day:[{day,count}], submissions_per_day:[{day,count}]}
//   GET  /treino/admin/response-stats {coverage, overall, per_day, by_dow_hour, subs_per_day:[{day,count}], subs_by_dow_hour:[{dow,hour,n}]}
//   GET  /treino/admin/calib-activity {calib_per_day:[{day,count}], calib_by_dow_hour:[{dow,hour,n}], total}
//   POST /treino/admin/logout-user {login} -> {logged_out, sessions_removed}
//   POST /treino/admin/lock-user   {login} -> {locked, sessions_removed}
import { apiGet, apiPost } from '/shared/api.js';
import { status } from '/shared/auth.js';
import { el, fmtDate, avatarEl, renderAuthArea } from '/shared/ui.js';
import { barChart, hBarChart, lineChart, heatmap, heatmapGrid } from '/lib/charts.js';
import { T } from '/shared/i18n.js';

const CONTEST = 'treino';
const G = (opts) => ({ contest: CONTEST, auth: true, ...opts });

// epoch (s) -> 'YYYY-MM-DD' local (default do <input type=date>)
const pad2 = (n) => String(n).padStart(2, '0');
function todayStr() {
  const d = new Date();
  return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate());
}
// epoch (s) at day start (UTC) -> 'DD/MM' (eixo X dos gráficos)
function ddmm(daySec) {
  const d = new Date(Number(daySec) * 1000);
  return pad2(d.getUTCDate()) + '/' + pad2(d.getUTCMonth() + 1);
}
const num = (v) => (v == null || isNaN(v) ? 0 : Number(v));

// segundos -> duração compacta ("12s", "3min 20s", "1h 05min")
function fmtDur(sec) {
  sec = Math.round(num(sec));
  if (sec < 60) return sec + 's';
  if (sec < 3600) { const m = Math.floor(sec / 60), s = sec % 60; return s ? `${m}min ${s}s` : `${m}min`; }
  const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60);
  return m ? `${h}h ${pad2(m)}min` : `${h}h`;
}
// epoch (s) início-do-dia (UTC) -> 'YYYY-MM-DD' (UTC) — chave do calendário de calor
function ymd(daySec) {
  const d = new Date(num(daySec) * 1000);
  return d.getUTCFullYear() + '-' + pad2(d.getUTCMonth() + 1) + '-' + pad2(d.getUTCDate());
}

function errBox(message) {
  return el('div', { class: 'error-box', style: 'margin:.6rem 0' }, message);
}
function loading() { return el('div', { class: 'muted small' }, T('carregando…', 'loading…')); }

// ============================ aba: Sessões ativas ============================
function makeSessionsTab() {
  const panel = el('div', { class: 'section' });
  const head = el('h2', {}, T('👥 Sessões ativas', '👥 Active sessions'));
  const countBadge = el('span', { class: 'tag' }, '…');
  head.append(countBadge);

  const search = el('input', { type: 'search', placeholder: T('Buscar nome, handle ou IP (aceita regex)…', 'Search name, handle or IP (regex allowed)…'), style: 'min-width:240px' });
  const matchInfo = el('span', { class: 'small muted' });
  const selAll = el('input', { type: 'checkbox', title: T('Selecionar todos os filtrados', 'Select all filtered') });
  const bulkLogout = el('button', { class: 'btn ghost', disabled: true }, T('Deslogar selecionados', 'Log out selected'));
  const bulkLock = el('button', { class: 'btn danger', disabled: true }, T('Travar selecionados', 'Lock selected'));
  const tools = el('div', { class: 'toolbar' },
    search, matchInfo, el('span', { style: 'flex:1' }),
    el('label', { class: 'row', style: 'gap:.3rem' }, selAll, T('todos', 'all')),
    bulkLogout, bulkLock,
    el('button', { class: 'btn ghost', onclick: () => load() }, T('↻ Atualizar', '↻ Refresh')));
  const body = el('div', {}, loading());
  panel.append(head, tools, body);

  let ALL = [];
  const checked = new Set();   // logins selecionados (distintos)

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
    const n = checked.size;
    bulkLogout.disabled = bulkLock.disabled = n === 0;
    bulkLogout.textContent = T('Deslogar selecionados', 'Log out selected') + (n ? ' (' + n + ')' : '');
    bulkLock.textContent = T('Travar selecionados', 'Lock selected') + (n ? ' (' + n + ')' : '');
  }
  function syncSelAll(rows) { selAll.checked = rows.length > 0 && rows.every(s => checked.has(s.login)); }

  function render() {
    const rows = ALL.filter(matcher());
    matchInfo.textContent = rows.length + T(' de ', ' of ') + ALL.length;
    body.innerHTML = '';
    if (!ALL.length) { body.append(el('div', { class: 'muted' }, T('Nenhuma sessão ativa.', 'No active sessions.'))); syncSelAll(rows); updateBulk(); return; }
    if (!rows.length) { body.append(el('div', { class: 'muted' }, T('Nenhuma sessão casa com a busca.', 'No session matches the search.'))); syncSelAll(rows); updateBulk(); return; }

    const tb = el('tbody');
    rows.forEach(s => {
      const cb = el('input', { type: 'checkbox' });
      cb.checked = checked.has(s.login);
      cb.addEventListener('change', () => { cb.checked ? checked.add(s.login) : checked.delete(s.login); syncSelAll(rows); updateBulk(); });
      const deslogarBtn = el('button', { class: 'btn ghost' }, T('Deslogar', 'Log out'));
      deslogarBtn.addEventListener('click', () => actLogout([s.login], deslogarBtn));
      const travarBtn = el('button', { class: 'btn danger' }, T('Travar', 'Lock'));
      travarBtn.addEventListener('click', () => actLock([s.login], travarBtn));
      tb.append(el('tr', {},
        el('td', {}, cb),
        el('td', {}, el('div', { class: 'cell-user' },
          avatarEl(s.login, s.name, 28),
          el('div', {},
            el('div', {}, s.name || s.login || '—'),
            el('div', { class: 'lg' }, '~' + (s.login || '?'))))),
        el('td', { class: 'ip' }, s.ip
          ? el('a', { href: '#', title: T('Deslogar todos deste IP', 'Log out all from this IP'), onclick: (e) => { e.preventDefault(); actLogoutIp(s.ip); } }, s.ip)
          : '—'),
        el('td', { class: 'ua', title: s.user_agent || '' }, s.user_agent || '—'),
        el('td', { class: 'small' }, fmtDate(s.login_at)),
        el('td', {}, el('div', { class: 'row-actions' }, deslogarBtn, travarBtn))));
    });
    body.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {},
        el('th', {}, ''), el('th', {}, T('Usuário', 'User')), el('th', {}, 'IP'), el('th', {}, 'User-Agent'),
        el('th', {}, T('Logado em', 'Logged in at')), el('th', {}, T('Ações', 'Actions')))), tb)));
    syncSelAll(rows); updateBulk();
  }

  selAll.addEventListener('change', () => {
    const rows = ALL.filter(matcher());
    rows.forEach(s => selAll.checked ? checked.add(s.login) : checked.delete(s.login));
    render();
  });
  search.addEventListener('input', render);

  async function load() {
    body.innerHTML = ''; body.append(loading());
    let data;
    try { data = await apiGet('/treino/admin/sessions', G()); }
    catch (e) { body.innerHTML = ''; body.append(errBox(T('Falha ao carregar sessões: ', 'Failed to load sessions: ') + (e.message || T('erro', 'error')))); return; }
    ALL = data.sessions || [];
    countBadge.textContent = ALL.length + ' ' + (ALL.length === 1 ? T('sessão', 'session') : T('sessões', 'sessions'));
    const present = new Set(ALL.map(s => s.login));
    [...checked].forEach(l => { if (!present.has(l)) checked.delete(l); });
    render();
  }

  async function actLogout(logins, btn) {
    if (!logins.length) return;
    if (btn) btn.disabled = true;
    try {
      const r = await apiPost('/treino/admin/logout-user', logins.length === 1 ? { login: logins[0] } : { logins }, G());
      alert(T('Deslogados: ', 'Logged out: ') + num(r.users_count) + T(' usuário(s), ', ' user(s), ') + num(r.sessions_removed) + T(' sessão(ões) removida(s).', ' session(s) removed.'));
    } catch (e) { alert(T('Falha ao deslogar: ', 'Failed to log out: ') + (e.message || T('erro', 'error'))); }
    checked.clear(); await load();
  }
  async function actLock(logins, btn) {
    if (!logins.length) return;
    const who = logins.length === 1 ? '"' + logins[0] + '"' : logins.length + T(' usuário(s)', ' user(s)');
    if (!confirm(T('Travar o acesso de ', 'Lock access for ') + who + T('?\n\nIsto TROCA a senha por uma aleatória (eles não conseguirão mais entrar até a senha ser redefinida) e encerra as sessões.', '?\n\nThis CHANGES the password to a random one (they will no longer be able to log in until the password is reset) and ends the sessions.'))) return;
    if (btn) btn.disabled = true;
    try {
      const r = await apiPost('/treino/admin/lock-user', logins.length === 1 ? { login: logins[0] } : { logins }, G());
      alert(T('Travados: ', 'Locked: ') + num(r.users_count) + T(' usuário(s) (senha trocada), ', ' user(s) (password changed), ') + num(r.sessions_removed) + T(' sessão(ões) removida(s).', ' session(s) removed.'));
    } catch (e) { alert(T('Falha ao travar: ', 'Failed to lock: ') + (e.message || T('erro', 'error'))); }
    checked.clear(); await load();
  }
  async function actLogoutIp(ip) {
    if (!ip) return;
    const n = ALL.filter(s => s.ip === ip).length;
    if (!confirm(T('Deslogar TODAS as ', 'Log out ALL ') + n + T(' sessão(ões) do IP ', ' session(s) from IP ') + ip + '?')) return;
    try {
      const r = await apiPost('/treino/admin/logout-ip', { ip }, G());
      alert('IP ' + ip + ': ' + num(r.sessions_removed) + T(' sessão(ões) removida(s) (', ' session(s) removed (') + num(r.users_count) + T(' usuário(s)).', ' user(s)).'));
    } catch (e) { alert(T('Falha ao deslogar IP: ', 'Failed to log out IP: ') + (e.message || T('erro', 'error'))); }
    await load();
  }
  bulkLogout.addEventListener('click', () => actLogout([...checked], bulkLogout));
  bulkLock.addEventListener('click', () => actLock([...checked], bulkLock));

  return { panel, load };
}

// ============================ aba: Acessos (log) ============================
function makeAccessLogTab() {
  const panel = el('div', { class: 'section' });
  const head = el('h2', {}, T('📝 Acessos (log)', '📝 Access (log)'));
  const dateInput = el('input', { type: 'date', value: todayStr() });
  dateInput.addEventListener('change', () => load());
  const tools = el('div', { class: 'toolbar' },
    el('span', { class: 'small muted' }, T('Dia:', 'Day:')), dateInput,
    el('button', { class: 'btn ghost', onclick: () => load() }, T('↻ Atualizar', '↻ Refresh')));
  const body = el('div', {}, loading());
  panel.append(head, tools, body);

  async function load() {
    body.innerHTML = ''; body.append(loading());
    const day = dateInput.value;
    let data;
    try { data = await apiGet('/treino/admin/access-log?day=' + encodeURIComponent(day), G()); }
    catch (e) { body.innerHTML = ''; body.append(errBox(T('Falha ao carregar o log: ', 'Failed to load the log: ') + (e.message || T('erro', 'error')))); return; }
    const entries = data.entries || [];
    body.innerHTML = '';
    body.append(el('div', { class: 'small muted', style: 'margin-bottom:.5rem' },
      entries.length + ' ' + (entries.length === 1 ? T('acesso', 'access') : T('acessos', 'accesses')) + T(' em ', ' on ') + (data.day || day) + T(' (mais recentes primeiro).', ' (most recent first).')));
    if (!entries.length) { body.append(el('div', { class: 'muted' }, T('Nenhum acesso neste dia.', 'No access on this day.'))); return; }

    const tb = el('tbody');
    entries.forEach(e2 => {
      tb.append(el('tr', {},
        el('td', { class: 'small' }, fmtDate(e2.time)),
        el('td', { class: 'lg', style: 'font-family:var(--mono);font-size:.85rem' }, '~' + (e2.login || '?')),
        el('td', { class: 'ip' }, e2.ip || '—'),
        el('td', { class: 'ua', title: e2.user_agent || '' }, e2.user_agent || '—')));
    });
    const table = el('table', { class: 'moj' },
      el('thead', {}, el('tr', {},
        el('th', {}, T('Data/Hora', 'Date/Time')), el('th', {}, 'Login'), el('th', {}, 'IP'), el('th', {}, 'User-Agent'))),
      tb);
    body.append(el('div', { class: 'chart-wrap' }, table));
  }

  return { panel, load };
}

// ============================ aba: Estatísticas ============================
// Página com TOC + seções: visão geral, problemas por autor, entrada de públicos (mapa de calor),
// atividade (logins/submissões por dia). Fonte: GET /treino/admin/stats.
const card = (v, label, hl) => el('div', { class: 'stat-card' + (hl ? ' hl' : '') },
  el('div', { class: 'n' }, String(v)), el('div', { class: 'lbl' }, label));
// caixa de gráfico de barras por dia (reusada por Estatísticas e Fila>Volume)
function dayBarBox(title, arr, color) {
  const box = el('div', {}, el('div', { class: 'chart-title' }, title));
  if (arr && arr.length) {
    box.append(el('div', { class: 'chart-wrap' },
      barChart(arr.map(d => ({ label: ddmm(d.day), value: num(d.count) })),
        { width: 460, height: 240, color, rotateLabels: true, maxLabels: 15 })));
  } else box.append(el('div', { class: 'muted small center', style: 'padding:1rem' }, T('Sem dados.', 'No data.')));
  return box;
}
// seção com âncora + link no índice (TOC). Devolve {node, link}.
function tocSection(id, title, toc, body) {
  const node = el('div', { id, style: 'scroll-margin-top:.5rem;margin-top:1.1rem' },
    el('h3', { style: 'margin:.2rem 0 .6rem;border-bottom:1px solid var(--line,#e3e8f2);padding-bottom:.2rem' }, title));
  toc.append(el('a', { href: '#' + id, style: 'font-size:.9rem;text-decoration:none',
    onclick: (e) => { e.preventDefault(); document.getElementById(id).scrollIntoView({ behavior: 'smooth', block: 'start' }); } }, title));
  body.append(node);
  return node;
}

function makeStatsTab() {
  const panel = el('div', { class: 'section' });
  const head = el('h2', {}, T('📊 Estatísticas', '📊 Statistics'));
  const tools = el('div', { class: 'toolbar' },
    el('button', { class: 'btn ghost', onclick: () => load() }, T('↻ Atualizar', '↻ Refresh')));
  const toc = el('div', { style: 'display:flex;gap:1rem;flex-wrap:wrap;margin:.2rem 0 .4rem;padding:.4rem .7rem;background:var(--card-bg,#f5f7fb);border-radius:.5rem' });
  const body = el('div', {}, loading());
  panel.append(head, tools, toc, body);

  async function load() {
    body.innerHTML = ''; body.append(loading()); toc.innerHTML = '';
    let data;
    try { data = await apiGet('/treino/admin/stats', G()); }
    catch (e) { body.innerHTML = ''; body.append(errBox(T('Falha ao carregar estatísticas: ', 'Failed to load statistics: ') + (e.message || T('erro', 'error')))); return; }
    body.innerHTML = '';
    const p = data.problems || {};

    // (a) Visão geral
    tocSection('st-geral', T('Visão geral', 'Overview'), toc, body).append(el('div', { class: 'stat-cards' },
      card(num(data.users), T('usuários totais', 'total users'), true),
      card(num(data.active_sessions), T('sessões ativas', 'active sessions'), true),
      card(num(p.total), T('problemas (total)', 'problems (total)'), true),
      card(num(p.public), T('públicos', 'public')),
      card(num(p.private), T('privados', 'private'))));

    // (b) Problemas por autor
    const s2 = tocSection('st-autor', T('Problemas por autor', 'Problems by author'), toc, body);
    const authors = (data.by_author || []).filter(a => num(a.total) > 0);
    if (authors.length) {
      s2.append(el('div', { class: 'chart-wrap' },
        hBarChart(authors.slice(0, 15).map(a => ({ label: a.author || '—', value: num(a.total) })),
          { total: num(p.total), maxRows: 15 })));
      const tb = el('tbody');
      authors.forEach(a => tb.append(el('tr', {},
        el('td', {}, a.author || '—'),
        el('td', {}, el('b', {}, String(num(a.total)))),
        el('td', { class: 'small' }, String(num(a.public)) + T(' públicos', ' public')),
        el('td', { class: 'small muted' }, String(num(a.private)) + T(' privados', ' private')))));
      s2.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, T('Autor', 'Author')), el('th', {}, T('Total', 'Total')), el('th', {}, T('Públicos', 'Public')), el('th', {}, T('Privados', 'Private')))), tb)));
    } else s2.append(el('div', { class: 'muted small' }, T('Sem dados de autoria.', 'No authorship data.')));

    // (c) Entrada de problemas públicos (mapa de calor)
    const s3 = tocSection('st-entrada', T('Entrada de problemas públicos', 'Public problem entry'), toc, body);
    const byDate = {}; (data.problems_public_by_day || []).forEach(d => { byDate[ymd(d.day)] = num(d.count); });
    if (Object.keys(byDate).length) {
      s3.append(el('div', { class: 'muted small', style: 'margin:.1rem 0 .5rem;line-height:1.45' },
        T('Quando cada problema virou público. ⚠ Ressalva: problemas migrados não têm data real de publicação — a maioria aparece concentrada na janela da migração (meados de 2026). Datas de problemas publicados a partir de agora são exatas.', 'When each problem became public. ⚠ Caveat: migrated problems have no real publication date — most appear concentrated in the migration window (mid-2026). Dates of problems published from now on are exact.')));
      s3.append(el('div', { class: 'chart-wrap' },
        heatmap(byDate, { weeks: 30, cell: 13, color: '#1a7f37', fmt: (v, date) => date + ': ' + v + ' ' + (v === 1 ? T('problema público', 'public problem') : T('problemas públicos', 'public problems')) })));
    } else s3.append(el('div', { class: 'muted small' }, T('Sem datas de entrada ainda.', 'No entry dates yet.')));

    // (d) Atividade
    const s4 = tocSection('st-atividade', T('Atividade', 'Activity'), toc, body);
    const logins = (data.logins_per_day || []).slice().sort((a, b) => num(a.day) - num(b.day));
    const subs = (data.submissions_per_day || []).slice().sort((a, b) => num(a.day) - num(b.day));
    const grid = el('div', { class: 'stat-grid two' });
    grid.append(dayBarBox(T('Logins por dia', 'Logins per day'), logins, '#216097'), dayBarBox(T('Submissões por dia', 'Submissions per day'), subs, '#1a7f37'));
    s4.append(grid);
  }

  return { panel, load };
}

// ---- render do TEMPO DE RESPOSTA (movido da antiga aba; agora seção da Fila) ----
// espera (submit->veredito), julgamento (duration_s), fila; geral + por dia + 2 mapas de calor.
// Só submissões com finalized_at (cobertura exibida). Fonte: GET /treino/admin/response-stats.
function renderResponseInto(box, data) {
  const ov = data.overall || {}, cov = data.coverage || {};
  box.append(el('div', { class: 'muted small', style: 'margin:.1rem 0 .8rem' },
    T('Baseado em ', 'Based on ') + num(cov.with_finalized) + T(' de ', ' of ') + num(cov.history_total) + T(' submissões com tempo de veredito registrado (pipeline v2). Horários em UTC.', ' submissions with recorded verdict time (pipeline v2). Times in UTC.')));
  if (!num(ov.n)) {
    box.append(el('div', { class: 'muted small center', style: 'padding:1.2rem' },
      T('Ainda não há submissões com tempo de resposta registrado (preenche conforme novas submissões forem julgadas).', 'There are no submissions with recorded response time yet (fills in as new submissions are judged).')));
    return;
  }
  box.append(el('div', { class: 'stat-cards' },
    card(fmtDur(ov.avg_wait_s), T('espera média (submit→veredito)', 'avg wait (submit→verdict)'), true),
    card(fmtDur(ov.p50_wait_s), T('espera mediana (p50)', 'median wait (p50)')),
    card(fmtDur(ov.p95_wait_s), T('espera p95', 'wait p95')),
    card(fmtDur(ov.max_wait_s), T('espera máxima', 'max wait')),
    card(fmtDur(ov.avg_judge_s), T('julgamento médio (execução)', 'avg judging (execution)')),
    card(fmtDur(ov.avg_queue_s), T('fila média (espera − julgamento)', 'avg queue (wait − judging)'), true),
    card(num(ov.n), T('submissões medidas', 'submissions measured'))));
  const days = (data.per_day || []).slice().sort((a, b) => num(a.day) - num(b.day));
  const lineBox = (title, key, color) => {
    const b = el('div', {}, el('div', { class: 'chart-title' }, title));
    if (days.length) b.append(el('div', { class: 'chart-wrap' }, lineChart(days.map(d => ({ x: num(d.day), y: num(d[key]), label: ddmm(d.day) })), { width: 460, height: 220, color, maxLabels: 7 })));
    else b.append(el('div', { class: 'muted small center', style: 'padding:1rem' }, T('Sem dados.', 'No data.')));
    return b;
  };
  const g1 = el('div', { class: 'stat-grid two' });
  g1.append(lineBox(T('Espera média por dia', 'Avg wait per day'), 'avg_wait_s', '#216097'), lineBox(T('Espera p95 por dia', 'Wait p95 per day'), 'p95_wait_s', '#c4314b'));
  const g2 = el('div', { class: 'stat-grid two' });
  g2.append(lineBox(T('Julgamento médio por dia', 'Avg judging per day'), 'avg_judge_s', '#1a7f37'), lineBox(T('Fila média por dia', 'Avg queue per day'), 'avg_queue_s', '#a66a00'));
  box.append(g1, g2);
  const scaleMax = num(ov.p95_wait_s) || num(ov.avg_wait_s) || 1;   // corta no p95 p/ 1 outlier não lavar o mapa
  const byDate = {}; days.forEach(d => { byDate[ymd(d.day)] = num(d.avg_wait_s); });
  box.append(el('div', {}, el('div', { class: 'chart-title' }, T('Mapa de calor — espera média por dia', 'Heatmap — avg wait per day')),
    el('div', { class: 'chart-wrap' }, heatmap(byDate, { weeks: 26, cell: 18, gap: 4, color: '#216097', scaleMax, fmt: (v, date) => `${date}: ${fmtDur(v)}` }))));
  // heatmapGrid lê c.value (cor/escala); as células trazem a magnitude em avg_wait_s -> mapeia.
  const waitCells = (data.by_dow_hour || []).map(c => ({ dow: num(c.dow), hour: num(c.hour), value: num(c.avg_wait_s), n: num(c.n) }));
  box.append(el('div', {}, el('div', { class: 'chart-title' }, T('Mapa de calor — espera média por dia da semana × hora (UTC)', 'Heatmap — avg wait per weekday × hour (UTC)')),
    el('div', { class: 'chart-wrap' }, heatmapGrid(waitCells, { color: '#c4314b', scaleMax, fmt: (v) => fmtDur(v) }))));
}

// ---- render do VOLUME (submissões + calibrações) — mapas de calor calendário + dow×hora ----
function renderVolumeInto(box, resp, calib) {
  const calMap = (arr) => { const m = {}; (arr || []).forEach(d => { m[ymd(d.day)] = num(d.count); }); return m; };
  const dhCells = (arr) => (arr || []).map(c => ({ dow: num(c.dow), hour: num(c.hour), value: num(c.n), n: num(c.n) }));
  const calHeat = (m, color, unit) => Object.keys(m).length
    ? heatmap(m, { weeks: 40, cell: 13, color, fmt: (v, date) => `${date}: ${v} ${unit}${v === 1 ? '' : 's'}` })
    : el('div', { class: 'muted small' }, T('Sem dados.', 'No data.'));
  const gridHeat = (cells, color, unit) => cells.length
    ? heatmapGrid(cells, { color, fmt: (v) => v + ' ' + unit + (v === 1 ? '' : 's') })
    : el('div', { class: 'muted small' }, T('Sem dados.', 'No data.'));

  box.append(el('div', { class: 'chart-title' }, T('Submissões por dia', 'Submissions per day')),
    el('div', { class: 'chart-wrap' }, calHeat(calMap(resp.subs_per_day), '#1a7f37', T('submissão', 'submission'))));
  box.append(el('div', { class: 'chart-title', style: 'margin-top:.6rem' }, T('Submissões por dia da semana × hora (UTC)', 'Submissions per weekday × hour (UTC)')),
    el('div', { class: 'chart-wrap' }, gridHeat(dhCells(resp.subs_by_dow_hour), '#1a7f37', 'sub')));

  box.append(el('div', { class: 'muted small', style: 'margin:.9rem 0 .3rem;line-height:1.4' },
    T('Calibrações (do log de eventos dos juízes; run/ pode rotacionar → cobertura histórica parcial).', 'Calibrations (from the judges\' event log; run/ may rotate → partial historical coverage).')));
  box.append(el('div', { class: 'chart-title' }, T('Calibrações por dia', 'Calibrations per day')),
    el('div', { class: 'chart-wrap' }, calHeat(calMap(calib.calib_per_day), '#7a5ada', T('calibração', 'calibration'))));
  box.append(el('div', { class: 'chart-title', style: 'margin-top:.6rem' }, T('Calibrações por dia da semana × hora (UTC)', 'Calibrations per weekday × hour (UTC)')),
    el('div', { class: 'chart-wrap' }, gridHeat(dhCells(calib.calib_by_dow_hour), '#7a5ada', 'calib')));
}

// ============================ aba: Fila & tempo de resposta ============================
// Seções (TOC): Agora (contadores + o que cada máquina roda: calibração vs submissão), Tempo de
// resposta (movido da antiga aba) e Volume (mapas de calor de submissões e calibrações).
function makeQueueTab() {
  const panel = el('div', { class: 'section' });
  const head = el('h2', {}, T('⏳ Fila & tempo de resposta', '⏳ Queue & response time'));
  const tools = el('div', { class: 'toolbar' },
    el('button', { class: 'btn ghost', onclick: () => load() }, T('↻ Atualizar', '↻ Refresh')));
  const toc = el('div', { style: 'display:flex;gap:1rem;flex-wrap:wrap;margin:.2rem 0 .4rem;padding:.4rem .7rem;background:var(--card-bg,#f5f7fb);border-radius:.5rem' });
  const body = el('div', {}, loading());
  panel.append(head, tools, toc, body);

  async function load() {
    body.innerHTML = ''; body.append(loading()); toc.innerHTML = '';
    let q, judges, resp, calib;
    try {
      [q, judges, resp, calib] = await Promise.all([
        apiGet('/treino/admin/queue', G()),
        apiGet('/treino/admin/judges', G()).catch(() => ({ machines: [] })),
        apiGet('/treino/admin/response-stats', G()).catch(() => ({})),
        apiGet('/treino/admin/calib-activity', G()).catch(() => ({})),
      ]);
    } catch (e) { body.innerHTML = ''; body.append(errBox(T('Falha ao carregar a fila: ', 'Failed to load the queue: ') + (e.message || T('erro', 'error')))); return; }
    body.innerHTML = '';

    // (a) Agora — contadores + o que cada máquina roda
    const s1 = tocSection('q-agora', T('Agora', 'Now'), toc, body);
    s1.append(el('div', { class: 'stat-cards' },
      card(num(q.total_pending), T('submissões pendentes', 'pending submissions'), true),
      card(num(q.spool_queued), T('na fila (spool)', 'in queue (spool)')),
      card(num(q.calib_pending), T('calibrações na fila', 'calibrations in queue')),
      card(num(q.calib_inflight) + num(q.calib_targeted), T('calibrando agora', 'calibrating now'))));
    const machines = judges.machines || [];
    if (machines.length) {
      const mtb = el('tbody');
      // idade do job (since = assigned_at/claimed_at, EPOCH) — job preso fica óbvio sem conta manual
      const fmtAge = (since) => {
        if (!since) return '';
        const s = Math.max(0, Math.floor(Date.now() / 1000 - since));
        const mm = Math.floor(s / 60);
        return mm >= 1 ? T(' · há ' + mm + 'm', ' · for ' + mm + 'm') : T(' · há ' + s + 's', ' · for ' + s + 's');
      };
      machines.forEach(m => {
        // TODOS os segmentos/slots (current_jobs) — m.current é só o 1º (compat) e escondia o resto
        const jobs = Array.isArray(m.current_jobs) && m.current_jobs.length ? m.current_jobs : (m.current && m.current.kind ? [m.current] : []);
        const jobLine = (cur) => {
          if (!cur || !cur.kind) return null;
          const age = el('span', { class: 'small muted' }, fmtAge(cur.since));
          if (cur.kind === 'submission') return el('div', {}, T('📥 submissão · ', '📥 submission · '), el('b', {}, cur.problem_id || '?'), cur.login ? el('span', { class: 'small muted' }, ' · ' + cur.login) : '', age);
          if (cur.kind === 'calibrate') return el('div', {}, T('⚙ calibração · ', '⚙ calibration · '), el('b', {}, cur.problem_id || '?'), age);
          if (cur.kind === 'index') return el('div', {}, T('🗂 indexação · ', '🗂 indexing · '), el('b', {}, cur.problem_id || '?'), age);
          if (cur.kind === 'draining') return el('div', { class: 'muted small' }, T('⏸ drenando (config nova a aplicar)', '⏸ draining (new config pending)'));
          if (cur.kind === 'disabled') return el('div', { class: 'muted small' }, T('⏸ desabilitada pelo admin', '⏸ disabled by admin'));
          if (cur.kind === 'unknown_busy') return el('div', { class: 'muted small' }, T('⚠ ocupada sem job atribuído — use `moj judges reset`', '⚠ busy with no attributed job — use `moj judges reset`'));
          return el('div', { class: 'muted small' }, T('ocupada (calibração direcionada)', 'busy (targeted calibration)'));
        };
        let job;
        if (!jobs.length) job = el('span', { class: 'muted small' }, m.online ? (m.busy ? T('ocupada', 'busy') : T('livre', 'free')) : 'offline');
        else { job = el('div', {}); jobs.forEach(c => { const l = jobLine(c); if (l) job.append(l); }); }
        const qc = num(m.queued_calibrate);
        const slotsInfo = (m.slots && m.slots.total > 1 && m.slots.free != null)
          ? el('div', { class: 'small muted' }, (m.slots.total - m.slots.free) + '/' + m.slots.total + ' slots') : '';
        mtb.append(el('tr', {},
          el('td', {}, '🖧 ' + (m.host || '?')),
          el('td', {}, m.online ? (m.busy ? T('🟡 ocupada', '🟡 busy') : T('🟢 livre', '🟢 free')) : '🔴 offline', slotsInfo),
          el('td', {}, job),
          el('td', { class: 'small muted' }, qc ? (qc + T(' na fila', ' in queue')) : '—')));
      });
      s1.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, T('Máquina', 'Machine')), el('th', {}, T('Estado', 'State')), el('th', {}, T('Rodando agora', 'Running now')), el('th', {}, T('Calib. direcionada', 'Targeted calib.')))), mtb)));
    }
    const lists = q.lists || [];
    if (lists.length) {
      const tb = el('tbody');
      lists.forEach(l => tb.append(el('tr', {},
        el('td', {}, l.name || l.contest || '—'),
        el('td', { class: 'small', style: 'font-family:var(--mono)' }, l.contest || '—'),
        el('td', {}, el('b', { style: 'color:var(--warn)' }, String(num(l.pending)))))));
      s1.append(el('div', { class: 'chart-title', style: 'margin-top:.6rem' }, T('Pendentes por lista', 'Pending per list')));
      s1.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, T('Lista', 'List')), el('th', {}, 'Contest'), el('th', {}, T('Pendentes', 'Pending')))), tb)));
    }

    // (b) Tempo de resposta   (c) Volume
    renderResponseInto(tocSection('q-resposta', T('Tempo de resposta', 'Response time'), toc, body), resp);
    renderVolumeInto(tocSection('q-volume', T('Volume de submissões e calibrações', 'Submission and calibration volume'), toc, body), resp, calib);
  }

  return { panel, load };
}

// ============================ aba: Máquinas de julgamento ============================
function makeJudgesTab() {
  const panel = el('div', { class: 'section' });
  const head = el('h2', {}, T('🖥️ Máquinas de julgamento', '🖥️ Judging machines'));
  const tools = el('div', { class: 'toolbar' },
    el('button', { class: 'btn ghost', onclick: () => load() }, T('↻ Atualizar', '↻ Refresh')));
  const body = el('div', {}, loading());
  panel.append(head, tools, body);

  async function load() {
    body.innerHTML = ''; body.append(loading());
    let data;
    try { data = await apiGet('/treino/admin/judges', G()); }
    catch (e) { body.innerHTML = ''; body.append(errBox(T('Falha ao carregar o status do juiz: ', 'Failed to load judge status: ') + (e.message || T('erro', 'error')))); return; }
    body.innerHTML = '';

    // status online/offline + ocupado/livre
    const statusLine = el('div', { style: 'font-size:1.15rem;font-weight:700;margin:.2rem 0 .6rem' });
    if (data.online) {
      statusLine.append(el('span', { class: 'judge-dot' }, '🟢 online'));
      statusLine.append(el('span', { class: 'tag', style: data.busy ? 'background:var(--warn-bg);color:var(--warn)' : 'background:var(--ok-bg);color:var(--ok)' },
        data.busy ? T('ocupado', 'busy') : T('livre', 'free')));
    } else {
      statusLine.append(el('span', { class: 'judge-dot' }, T('🔴 juiz inacessível', '🔴 judge unreachable')));
    }
    body.append(statusLine);

    // endereço do master
    body.append(el('div', { class: 'small muted', style: 'margin-bottom:.4rem' },
      data.model === 'pull' ? T('Modelo: pull (registro + heartbeat)', 'Model: pull (registry + heartbeat)')
        : (T('Master (escalonador): ', 'Master (scheduler): ') + (data.master_host || '?') + ':' + (data.master_port != null ? data.master_port : '?'))));

    // specs do master que respondeu
    const m = data.master;
    if (m) {
      const specs = el('div', { class: 'specs' });
      const spec = (k, v) => el('div', { class: 'spec' }, el('div', { class: 'k' }, k), el('div', { class: 'v' }, v));
      if (m.hostname != null) specs.append(spec('hostname', String(m.hostname)));
      if (m.arch != null) specs.append(spec(T('arquitetura', 'architecture'), String(m.arch)));
      if (m.cpu != null) specs.append(spec('CPU', String(m.cpu)));
      if (m.memory != null) {
        const gb = num(m.memory) / 1048576;   // inventário do juiz devolve kB (/proc/meminfo)
        specs.append(spec(T('memória', 'memory'), gb.toFixed(1) + ' GB'));
      }
      body.append(specs);
    } else if (data.online && data.model !== 'pull') {
      body.append(el('div', { class: 'muted small' }, T('O master respondeu, mas não informou especificações.', 'The master responded but reported no specs.')));
    }

    // máquinas: se o master agregou (listmachines), mostra cada uma com estado+specs
    if (data.has_machine_list && (data.machines || []).length) {
      body.append(el('div', { class: 'section-head', style: 'margin-top:1rem' },
        T('Juízes — ', 'Judges — ') + data.machines_online + '/' + data.machines_count + ' online'));
      // célula de SLOTS: partição vigente (do agente) + form da config desejada (o agente
      // drena os jobs em andamento e aplica; 'moj judges config' faz o mesmo pela CLI)
      const slotsCell = (mc) => {
        const cfg = mc.config || {};
        const cur = mc.partition || 'off';
        const wrap = el('div', {});
        wrap.append(el('div', {}, (((mc.slots && mc.slots.total) || 1) + ' slot(s) · ' + cur)
          + (cfg.partition && cfg.partition !== cur ? ' → ' + cfg.partition + T(' (aplicando…)', ' (applying…)') : '')
          + (cfg.disabled ? T(' · ⛔ desabilitado', ' · ⛔ disabled') : '')));
        const sel = el('select', { class: 'small', style: 'max-width:8rem' });
        ['off', 'numa', 'cpus:4', 'cpus:8', 'cpus:16'].forEach(v => sel.append(el('option', { value: v }, v)));
        sel.value = ['off', 'numa', 'cpus:4', 'cpus:8', 'cpus:16'].includes(cfg.partition || cur) ? (cfg.partition || cur) : 'off';
        const res = el('input', { type: 'text', value: String(cfg.reserve || 0), title: T('cpus reservadas p/ o SO (fora dos slots)', 'cpus reserved for the OS (outside the slots)'), style: 'width:3rem' });
        const dis = el('input', { type: 'checkbox', title: T('desabilitar (drena e para de receber trabalho)', 'disable (drains and stops receiving work)') }); dis.checked = !!cfg.disabled;
        const btn = el('button', { class: 'btn ghost', type: 'button', style: 'font-size:.82em;padding:.1rem .5rem' }, T('Aplicar', 'Apply'));
        btn.onclick = async () => {
          btn.disabled = true; btn.textContent = '…';
          try {
            await apiPost('/ops/judge-config', { host: mc.host, partition: sel.value, reserve: parseInt(res.value, 10) || 0, disabled: dis.checked }, G());
            setTimeout(load, 2500);
          } catch (e) { alert(T('Falha na config: ', 'Config failed: ') + e); btn.disabled = false; btn.textContent = T('Aplicar', 'Apply'); }
        };
        wrap.append(el('div', { class: 'row', style: 'gap:.25rem;align-items:center;flex-wrap:wrap;margin-top:.2rem' },
          sel, res, el('label', { class: 'row', style: 'gap:.15rem' }, dis, el('span', { class: 'muted', style: 'font-size:.8em' }, 'off')), btn));
        return wrap;
      };
      const tb = el('tbody');
      data.machines.forEach(mc => {
        const rep = mc.report || {};
        const slots = mc.slots || {};
        const nTot = num(slots.total) || 1, nFree = (slots.free == null) ? (mc.busy ? 0 : nTot) : num(slots.free);
        const st = !mc.online ? '🔴 offline'
          : (mc.status === 'draining' ? T('⏸ drenando', '⏸ draining')
            : (mc.status === 'disabled' ? T('⏸ desabilitada', '⏸ disabled')
              : (nFree === 0 ? T('🟡 ocupada', '🟡 busy') : (nFree < nTot ? `🟡 ${nTot - nFree}/${nTot} slots` : T('🟢 livre', '🟢 free')))));
        const mem = rep.memory != null ? (num(rep.memory) / 1048576).toFixed(1) + ' GB' : '—';
        const langs = mc.langs || [];
        const cage = mc.cage_root ? '📦 rootfs' : '🖥 host';
        const tl = mc.tl || {};
        const tlLangs = tl.langs || [];
        const cache = mc.cache || {};
        const cacheMB = cache.bytes ? (num(cache.bytes) / 1048576).toFixed(0) + ' MB' : '0 MB';
        const clearBtn = el('button', { class: 'btn ghost', type: 'button', title: T('Limpar o cache deste juiz (vai recalibrar sob demanda)', 'Clear this judge\'s cache (will recalibrate on demand)'), style: 'font-size:.82em;padding:.1rem .5rem;margin-top:.2rem' }, T('🗑 Limpar', '🗑 Clear'));
        clearBtn.onclick = async () => {
          if (!confirm(T('Limpar o cache de ', 'Clear the cache of ') + mc.host + T('?\nEle vai re-baixar e recalibrar os problemas sob demanda.', '?\nIt will re-download and recalibrate the problems on demand.'))) return;
          clearBtn.disabled = true; clearBtn.textContent = '…';
          try { await apiPost('/ops/judge-cache', { host: mc.host, action: 'clearcache' }, G()); setTimeout(load, 3000); }
          catch (e) { alert(T('Falha ao limpar cache: ', 'Failed to clear cache: ') + e); clearBtn.disabled = false; clearBtn.textContent = T('🗑 Limpar', '🗑 Clear'); }
        };
        // GPU: o registro só traz .gpu com COMPUTE comprovado (nvidia-smi/rocm-smi)
        const gpu = rep.gpu && rep.gpu.names ? rep.gpu.names : '';
        tb.append(el('tr', {},
          el('td', {}, '🖧 ' + (mc.host || '?')),
          el('td', {}, st),
          el('td', { class: 'small' },
            el('div', {}, rep.cpu ? String(rep.cpu).trim() : '—'),
            gpu ? el('div', { class: 'muted', style: 'font-size:.82em;word-break:break-word;max-width:26ch', title: T('GPU de compute (', 'Compute GPU (') + (rep.gpu.vendor || '') + ')' }, '🎮 ' + gpu) : ''),
          el('td', {}, mem),
          // toolchains: raiz da jaula (host/rootfs) + as linguagens que a máquina roda
          el('td', { class: 'small', title: mc.cage_root ? ('CAGE_ROOT=' + mc.cage_root) : T('raiz do sistema do host', 'host system root') },
            el('div', {}, cage),
            el('div', { class: 'muted', style: 'font-size:.82em;word-break:break-word;max-width:22ch' },
              langs.length ? langs.join(' ') : '—')),
          // time limits: nº de problemas calibrados + as linguagens com TL medido aqui
          el('td', { class: 'small' },
            el('div', {}, (tl.calibrated || 0) + ' ' + ((tl.calibrated === 1) ? T('problema', 'problem') : T('problemas', 'problems'))),
            el('div', { class: 'muted', style: 'font-size:.82em;word-break:break-word;max-width:18ch' },
              tlLangs.length ? ('TL: ' + tlLangs.join(' ')) : T('sem TL ainda', 'no TL yet'))),
          // cache local: nº de problemas em cache + tamanho EM DISCO (não é RAM! — a leitura
          // errada disso custou caro no diagnóstico do incidente 2026-07-15) + limpar
          el('td', { class: 'small', title: T('Cache de pacotes de problema EM DISCO do juiz (não é uso de RAM)', 'Judge\'s problem-package cache ON DISK (not RAM usage)') },
            el('div', {}, T('disco: ', 'disk: ') + (cache.problems || 0) + ' probs · ' + cacheMB),
            clearBtn),
          // SLOTS (particionamento): config fina por juiz — o agente aplica após drenar
          el('td', { class: 'small' }, slotsCell(mc))));
      });
      body.append(el('table', { class: 'moj' }, el('thead', {}, el('tr', {},
        el('th', {}, T('Máquina', 'Machine')), el('th', {}, T('Estado', 'State')),
        el('th', {}, 'CPU'), el('th', {}, T('Memória', 'Memory')),
        el('th', {}, 'Toolchains'), el('th', {}, 'Time limits'), el('th', {}, 'Cache'),
        el('th', { title: T('Particionamento em slots (a máquina corrige N problemas ao mesmo tempo, cada job pinado no seu conjunto de cpus)', 'Slot partitioning (the machine judges N problems at once, each job pinned to its own set of cpus)') }, 'Slots'))), tb));
    } else {
      const workers = data.configured_workers || [];
      body.append(el('div', { class: 'section-head', style: 'margin-top:1rem' }, T('Máquinas configuradas', 'Configured machines')));
      const count = data.configured_count != null ? data.configured_count : workers.length;
      body.append(el('div', { class: 'small', style: 'margin:.3rem 0' },
        el('b', {}, String(count)), ' ' + (count === 1 ? T('máquina configurada', 'machine configured') : T('máquinas configuradas', 'machines configured')) + T(' no escalonador.', ' in the scheduler.')));
      if (workers.length) {
        const wl = el('div', { class: 'worker-list' });
        workers.forEach(w => wl.append(el('div', { class: 'worker' }, '🖧 ' + w)));
        body.append(wl);
      } else {
        body.append(el('div', { class: 'muted small' }, T('Nenhum worker listado na configuração.', 'No worker listed in the configuration.')));
      }
      body.append(el('div', { class: 'small muted', style: 'margin-top:.7rem;line-height:1.45' },
        T('Este master ainda não tem o comando agregado de máquinas — mostrando a lista configurada. ', 'This master does not yet have the aggregated machines command — showing the configured list. ') +
        T('Faça o deploy do job-receiveitor-master.sh atualizado para ver o estado de cada máquina.', 'Deploy the updated job-receiveitor-master.sh to see each machine\'s state.')));
    }
  }

  return { panel, load };
}

// ============================ aba: Notícias ============================
const nowEpoch = () => Math.floor(Date.now() / 1000);
function toLocalDT(epoch) {
  const d = new Date((Number(epoch) || nowEpoch()) * 1000);
  const p = (n) => String(n).padStart(2, '0');
  return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) + 'T' + p(d.getHours()) + ':' + p(d.getMinutes());
}
const dtToEpoch = (s) => { const t = Date.parse(s); return isNaN(t) ? nowEpoch() : Math.floor(t / 1000); };

function makeNewsTab() {
  const panel = el('div', { class: 'section' });
  const head = el('h2', {}, T('📰 Notícias', '📰 News'));
  const tools = el('div', { class: 'toolbar' },
    el('button', { class: 'btn', onclick: () => openForm() }, T('➕ Nova notícia', '➕ New article')),
    el('button', { class: 'btn ghost', onclick: () => load() }, T('↻ Atualizar', '↻ Refresh')));
  const formBox = el('div', {});
  const body = el('div', {}, loading());
  panel.append(head, tools, formBox, body);

  const b64ToText = (b64) => { try { return new TextDecoder().decode(Uint8Array.from(atob(b64 || ''), (c) => c.charCodeAt(0))); } catch { return ''; } };

  function openForm(news) {
    const editing = !!news;
    const title = el('input', { value: editing ? (news.title || '') : '', placeholder: T('Título', 'Title'), style: 'width:100%' });
    const summary = el('input', { value: editing ? (news.summary || '') : '', placeholder: T('Resumo (1 linha, aparece na lista)', 'Summary (1 line, shown in the list)'), style: 'width:100%' });
    const url = el('input', { value: editing ? (news.url || '') : '', placeholder: T('URL externa — vazio = notícia local (texto completo no MOJ)', 'External URL — empty = local article (full text in MOJ)'), style: 'width:100%' });
    const dateI = el('input', { type: 'datetime-local', value: toLocalDT(editing ? news.date : nowEpoch()) });

    // editor de markdown + preview ao vivo (mesmo renderizador do detalhe público)
    const bodyt = el('textarea', { rows: '16', placeholder: T('Texto completo em Markdown…', 'Full text in Markdown…'),
      style: 'width:100%; font-family:var(--mono,monospace); font-size:.9rem; line-height:1.5' });
    bodyt.value = editing ? (news.body || '') : '';
    const preview = el('article', { class: 'news-body',
      style: 'border:1px solid var(--line); border-radius:10px; padding:.7rem 1rem; background:#fff; min-height:8rem; overflow:auto' });
    let pvTimer;
    const schedulePreview = () => { clearTimeout(pvTimer); pvTimer = setTimeout(refreshPreview, 400); };
    async function refreshPreview() {
      try { const r = await apiPost('/treino/admin/news/preview', { body: bodyt.value }, G()); preview.innerHTML = b64ToText(r.html_b64) || T('<span class="muted small">(vazio)</span>', '<span class="muted small">(empty)</span>'); }
      catch { preview.innerHTML = T('<span class="muted small">(não foi possível pré-visualizar)</span>', '<span class="muted small">(could not preview)</span>'); }
    }
    const wrapSel = (before, after) => {
      const t = bodyt, s = t.selectionStart, e = t.selectionEnd, v = t.value;
      t.value = v.slice(0, s) + before + v.slice(s, e) + (after || '') + v.slice(e);
      t.focus(); t.selectionStart = s + before.length; t.selectionEnd = e + before.length;
      schedulePreview();
    };
    const mdBtn = (label, tip, fn) => el('button', { class: 'btn ghost', type: 'button', title: tip, style: 'padding:.2rem .55rem', onclick: fn }, label);
    const toolbar = el('div', { class: 'md-toolbar' },
      mdBtn('B', T('negrito', 'bold'), () => wrapSel('**', '**')),
      mdBtn('i', T('itálico', 'italic'), () => wrapSel('*', '*')),
      mdBtn('H2', T('título', 'heading'), () => wrapSel('## ', '')),
      mdBtn(T('• lista', '• list'), T('lista', 'list'), () => wrapSel('- ', '')),
      mdBtn('< >', T('código', 'code'), () => wrapSel('`', '`')),
      mdBtn('🔗', 'link', () => wrapSel('[', '](https://)')),
      mdBtn('“ ”', T('citação', 'quote'), () => wrapSel('> ', '')));
    bodyt.addEventListener('input', schedulePreview);
    refreshPreview();

    const msg = el('div', { class: 'small', style: 'margin-top:.4rem' });
    const saveBtn = el('button', { class: 'btn' }, editing ? T('Salvar alterações', 'Save changes') : T('Publicar notícia', 'Publish article'));
    saveBtn.addEventListener('click', async () => {
      if (!title.value.trim()) { msg.className = 'small error-box'; msg.textContent = T('Informe o título', 'Enter the title'); return; }
      saveBtn.disabled = true; msg.className = 'small'; msg.textContent = T('Salvando…', 'Saving…');
      const payload = { title: title.value.trim(), summary: summary.value.trim(), url: url.value.trim(), body: bodyt.value, date: dtToEpoch(dateI.value) };
      try {
        if (editing) { payload.key = news.key; await apiPost('/treino/admin/news/update', payload, G()); }
        else { await apiPost('/treino/admin/news', payload, G()); }
        formBox.innerHTML = ''; await load();
      } catch (e) { saveBtn.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
    });

    formBox.innerHTML = '';
    formBox.append(el('div', { class: 'section', style: 'background:#fafcff' },
      el('h3', { style: 'margin:.1rem 0 .6rem' }, editing ? T('Editar notícia', 'Edit article') : T('Nova notícia', 'New article')),
      el('div', { style: 'display:grid; grid-template-columns:2fr 1fr; gap:.8rem' },
        el('div', { class: 'field' }, el('label', {}, T('Título', 'Title')), title),
        el('div', { class: 'field' }, el('label', {}, T('Data/hora', 'Date/time')), dateI)),
      el('div', { class: 'field' }, el('label', {}, T('Resumo', 'Summary')), summary),
      el('div', { class: 'field' }, el('label', {}, T('URL externa (opcional)', 'External URL (optional)')), url),
      el('div', { class: 'field' }, el('label', {}, T('Texto completo (Markdown)', 'Full text (Markdown)')),
        el('div', { class: 'news-editor-split' },
          el('div', {}, toolbar, bodyt),
          el('div', {}, el('div', { class: 'small muted', style: 'margin-bottom:.25rem' }, T('Pré-visualização', 'Preview')), preview))),
      el('div', { class: 'row', style: 'margin-top:.6rem' }, saveBtn,
        el('button', { class: 'btn ghost', onclick: () => { formBox.innerHTML = ''; } }, T('Cancelar', 'Cancel'))),
      msg));
  }

  async function actDelete(news) {
    if (!confirm(T('Remover a notícia "', 'Remove the article "') + (news.title || news.key) + '"?')) return;
    try { await apiPost('/treino/admin/news/delete', { key: news.key }, G()); await load(); }
    catch (e) { alert(T('Falha ao remover: ', 'Failed to remove: ') + (e.message || T('erro', 'error'))); }
  }

  async function load() {
    body.innerHTML = ''; body.append(loading());
    let data;
    try { data = await apiGet('/treino/admin/news', G()); }
    catch (e) { body.innerHTML = ''; body.append(errBox(T('Falha ao carregar notícias: ', 'Failed to load news: ') + (e.message || T('erro', 'error')))); return; }
    const news = data.news || [];
    body.innerHTML = '';
    if (!news.length) { body.append(el('div', { class: 'muted' }, T('Nenhuma notícia. Use "➕ Nova notícia".', 'No news. Use "➕ New article".'))); return; }
    const tb = el('tbody');
    news.forEach((n) => {
      tb.append(el('tr', {},
        el('td', {}, el('b', {}, n.title || T('(sem título)', '(untitled)')), el('div', { class: 'small muted' }, n.summary || '')),
        el('td', { class: 'small' }, fmtDate(n.date)),
        el('td', {}, el('div', { class: 'row-actions' },
          el('button', { class: 'btn ghost', onclick: () => openForm(n) }, T('Editar', 'Edit')),
          el('button', { class: 'btn danger', onclick: () => actDelete(n) }, T('Remover', 'Remove'))))));
    });
    body.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, T('Notícia', 'Article')), el('th', {}, T('Data', 'Date')), el('th', {}, T('Ações', 'Actions')))), tb)));
  }
  return { panel, load };
}

// ============================ aba: Auditoria ============================
function makeAuditTab() {
  const panel = el('div', { class: 'section' });
  const head = el('h2', {}, T('🛡 Auditoria', '🛡 Audit'));
  const dateInput = el('input', { type: 'date', value: todayStr() });
  dateInput.addEventListener('change', () => load());
  const tools = el('div', { class: 'toolbar' },
    el('span', { class: 'small muted' }, T('Dia:', 'Day:')), dateInput,
    el('button', { class: 'btn ghost', onclick: () => load() }, T('↻ Atualizar', '↻ Refresh')));
  const body = el('div', {}, loading());
  panel.append(head, tools, body);
  const ACT = { 'logout-user': T('🚪 deslogou usuário(s)', '🚪 logged out user(s)'), 'logout-ip': T('🚪 deslogou IP', '🚪 logged out IP'), 'lock-user': T('🔒 travou usuário(s)', '🔒 locked user(s)'),
                'news-add': T('📰 criou notícia', '📰 created article'), 'news-edit': T('✏️ editou notícia', '✏️ edited article'), 'news-delete': T('🗑 removeu notícia', '🗑 removed article') };

  async function load() {
    body.innerHTML = ''; body.append(loading());
    const day = dateInput.value;
    let data;
    try { data = await apiGet('/treino/admin/audit-log?day=' + encodeURIComponent(day), G()); }
    catch (e) { body.innerHTML = ''; body.append(errBox(T('Falha ao carregar a auditoria: ', 'Failed to load the audit: ') + (e.message || T('erro', 'error')))); return; }
    const entries = data.entries || [];
    body.innerHTML = '';
    body.append(el('div', { class: 'small muted', style: 'margin-bottom:.5rem' },
      entries.length + T(' ação(ões) em ', ' action(s) on ') + (data.day || day) + T(' (mais recentes primeiro).', ' (most recent first).')));
    if (!entries.length) { body.append(el('div', { class: 'muted' }, T('Nenhuma ação administrativa neste dia.', 'No administrative action on this day.'))); return; }
    const tb = el('tbody');
    entries.forEach((e2) => {
      tb.append(el('tr', {},
        el('td', { class: 'small' }, fmtDate(e2.time)),
        el('td', { class: 'lg', style: 'font-family:var(--mono);font-size:.85rem' }, '~' + (e2.admin || '?')),
        el('td', {}, ACT[e2.action] || e2.action),
        el('td', { class: 'small', style: 'font-family:var(--mono);word-break:break-all' }, e2.details || '')));
    });
    body.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, T('Data/Hora', 'Date/Time')), el('th', {}, 'Admin'), el('th', {}, T('Ação', 'Action')), el('th', {}, T('Detalhes', 'Details')))), tb)));
  }
  return { panel, load };
}

// ============================ aba: Contests ============================
function makeContestsTab() {
  const panel = el('div', { class: 'section' });
  panel.append(el('h2', {}, '🏆 Contests'));

  const thr = el('input', { type: 'number', min: '0', style: 'width:90px' });
  const allow = el('textarea', { rows: '2', placeholder: T('logins separados por espaço ou vírgula', 'logins separated by space or comma'), style: 'width:100%' });
  const deny = el('textarea', { rows: '2', placeholder: T('logins separados por espaço ou vírgula', 'logins separated by space or comma'), style: 'width:100%' });
  const permMsg = el('div', { class: 'small' });
  const saveBtn = el('button', { class: 'btn' }, T('Salvar permissões', 'Save permissions'));
  const parseList = (s) => (s || '').split(/[\s,]+/).map((x) => x.trim()).filter(Boolean);
  saveBtn.addEventListener('click', async () => {
    saveBtn.disabled = true; permMsg.className = 'small'; permMsg.textContent = T('Salvando…', 'Saving…');
    try {
      await apiPost('/treino/admin/contest-perms', { threshold: num(thr.value), allow: parseList(allow.value), deny: parseList(deny.value) }, G());
      permMsg.className = 'small'; permMsg.textContent = T('✓ salvo', '✓ saved'); saveBtn.disabled = false;
    } catch (e) { saveBtn.disabled = false; permMsg.className = 'small error-box'; permMsg.textContent = e.message || T('falha', 'failed'); }
  });
  const permBox = el('div', { class: 'section', style: 'background:#fafcff' },
    el('h3', { style: 'margin:.1rem 0 .5rem' }, T('Quem pode criar contests e problemas', 'Who can create contests and problems')),
    el('p', { class: 'muted small' }, T('Esta mesma permissão controla a criação de contests E a criação de problemas/coleções na Gestão de Problemas. Usuários .admin sempre podem. Além deles: a lista “liberados” OU quem atingir o limite de problemas resolvidos. A lista “bloqueados” impede até quem atingiria o limite.', 'This same permission controls creating contests AND creating problems/collections in Problem Management. .admin users always can. Beyond them: the “allowed” list OR whoever reaches the solved-problems threshold. The “blocked” list stops even those who would reach the threshold.')),
    el('div', { class: 'field' }, el('label', {}, T('Liberar automaticamente quem resolveu ≥', 'Auto-allow whoever solved ≥')), thr, el('span', { class: 'small muted' }, T(' problemas (0 = desativado)', ' problems (0 = disabled)'))),
    el('div', { class: 'field' }, el('label', {}, T('✅ Liberados (allow)', '✅ Allowed (allow)')), allow),
    el('div', { class: 'field' }, el('label', {}, T('⛔ Bloqueados (deny)', '⛔ Blocked (deny)')), deny),
    el('div', { class: 'row' }, saveBtn, permMsg));

  const listBox = el('div', {}, loading());

  async function loadPerms() {
    try {
      const r = await apiGet('/treino/admin/contest-perms', G()); const p = r.perms || {};
      thr.value = p.threshold || 0; allow.value = (p.allow || []).join(' '); deny.value = (p.deny || []).join(' ');
    } catch { permMsg.className = 'small error-box'; permMsg.textContent = T('Falha ao carregar permissões.', 'Failed to load permissions.'); }
  }
  async function loadList() {
    listBox.innerHTML = ''; listBox.append(loading());
    let r; try { r = await apiGet('/treino/admin/contests', G()); }
    catch (e) { listBox.innerHTML = ''; listBox.append(errBox(T('Falha ao carregar: ', 'Failed to load: ') + (e.message || T('erro', 'error')))); return; }
    const cs = r.contests || []; listBox.innerHTML = '';
    if (!cs.length) { listBox.append(el('div', { class: 'muted' }, T('Nenhum contest criado pela interface ainda.', 'No contest created via the interface yet.'))); return; }
    const tb = el('tbody');
    cs.forEach((c) => {
      const rm = el('button', { class: 'btn danger', onclick: async () => {
        if (!confirm(T('Remover o contest "', 'Remove the contest "') + (c.name || c.id) + T('"? (vai para a lixeira, reversível pelo servidor)', '"? (goes to trash, reversible by the server)'))) return;
        try { await apiPost('/treino/admin/contest-remove', { contest: c.id }, G()); loadList(); }
        catch (e) { alert(T('Falha ao remover: ', 'Failed to remove: ') + (e.message || T('erro', 'error'))); }
      } }, T('Remover', 'Remove'));
      tb.append(el('tr', {},
        el('td', {}, el('b', {}, c.name || c.id), el('div', { class: 'small muted' }, c.id)),
        el('td', { class: 'small' }, c.mode || '—'),
        el('td', { class: 'small' }, '~' + (c.owner || '?')),
        el('td', { class: 'small' }, c.created_at ? fmtDate(c.created_at) : '—'),
        el('td', {}, el('div', { class: 'row-actions' },
          el('a', { class: 'btn ghost', href: '/contest/?c=' + encodeURIComponent(c.id), target: '_blank' }, T('Abrir', 'Open')),
          el('a', { class: 'btn ghost', href: '/contest/score/?c=' + encodeURIComponent(c.id), target: '_blank' }, T('Placar', 'Scoreboard')),
          rm))));
    });
    listBox.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, 'Contest'), el('th', {}, T('Modo', 'Mode')), el('th', {}, T('Dono', 'Owner')), el('th', {}, T('Criado', 'Created')), el('th', {}, T('Ações', 'Actions')))), tb)));
  }

  panel.append(permBox, el('h3', { style: 'margin:1rem 0 .3rem' }, T('Contests criados pela interface', 'Contests created via the interface')), listBox);
  function load() { loadPerms(); loadList(); }
  return { panel, load };
}

// ============================ painel + abas ============================
function renderPanel(content) {
  content.innerHTML = '';

  const TABS = [
    { id: 'sessions', label: T('👥 Sessões ativas', '👥 Active sessions'), make: makeSessionsTab },
    { id: 'news', label: T('📰 Notícias', '📰 News'), make: makeNewsTab },
    { id: 'contests', label: '🏆 Contests', make: makeContestsTab },
    { id: 'access', label: T('📝 Acessos (log)', '📝 Access (log)'), make: makeAccessLogTab },
    { id: 'audit', label: T('🛡 Auditoria', '🛡 Audit'), make: makeAuditTab },
    { id: 'stats', label: T('📊 Estatísticas', '📊 Statistics'), make: makeStatsTab },
    { id: 'queue', label: T('⏳ Fila & tempo de resposta', '⏳ Queue & response time'), make: makeQueueTab },
    { id: 'judges', label: T('🖥️ Máquinas de julgamento', '🖥️ Judging machines'), make: makeJudgesTab },
  ];

  const tabsBar = el('div', { class: 'tabs' });
  const panelsWrap = el('div', {});
  const built = {};   // id -> {panel, load, loaded}

  function show(id) {
    TABS.forEach(t => {
      const b = built[t.id];
      const active = t.id === id;
      b.btn.classList.toggle('active', active);
      b.panel.hidden = !active;
    });
    const b = built[id];
    if (!b.loaded) { b.loaded = true; b.load(); }   // carrega sob demanda na 1ª vez
  }

  TABS.forEach((t, i) => {
    const { panel, load } = t.make();
    const btn = el('button', { class: 'btn ghost', onclick: () => show(t.id) }, t.label);
    built[t.id] = { panel, load, btn, loaded: false };
    tabsBar.append(btn);
    panel.hidden = i !== 0;
    panelsWrap.append(panel);
  });

  content.append(tabsBar, panelsWrap);
  show(TABS[0].id);   // primeira aba ativa + carregada
}

// ============================ boot ============================
async function boot() {
  await renderAuthArea(document.getElementById('authArea'), CONTEST, () => location.reload());
  const content = document.getElementById('content');

  const st = await status(CONTEST);
  if (!st.logged_in) {
    content.innerHTML = '';
    content.append(el('div', { class: 'access-restricted' }, T('Entre como administrador.', 'Log in as administrator.')));
    return;
  }
  if (!st.is_admin) {
    content.innerHTML = '';
    content.append(el('div', { class: 'access-restricted' }, T('🚫 Acesso restrito a administradores', '🚫 Access restricted to administrators')));
    return;
  }
  renderPanel(content);
}
boot();
