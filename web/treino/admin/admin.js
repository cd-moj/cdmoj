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
function loading() { return el('div', { class: 'muted small' }, 'carregando…'); }

// ============================ aba: Sessões ativas ============================
function makeSessionsTab() {
  const panel = el('div', { class: 'section' });
  const head = el('h2', {}, '👥 Sessões ativas');
  const countBadge = el('span', { class: 'tag' }, '…');
  head.append(countBadge);

  const search = el('input', { type: 'search', placeholder: 'Buscar nome, handle ou IP (aceita regex)…', style: 'min-width:240px' });
  const matchInfo = el('span', { class: 'small muted' });
  const selAll = el('input', { type: 'checkbox', title: 'Selecionar todos os filtrados' });
  const bulkLogout = el('button', { class: 'btn ghost', disabled: true }, 'Deslogar selecionados');
  const bulkLock = el('button', { class: 'btn danger', disabled: true }, 'Travar selecionados');
  const tools = el('div', { class: 'toolbar' },
    search, matchInfo, el('span', { style: 'flex:1' }),
    el('label', { class: 'row', style: 'gap:.3rem' }, selAll, 'todos'),
    bulkLogout, bulkLock,
    el('button', { class: 'btn ghost', onclick: () => load() }, '↻ Atualizar'));
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
    bulkLogout.textContent = 'Deslogar selecionados' + (n ? ' (' + n + ')' : '');
    bulkLock.textContent = 'Travar selecionados' + (n ? ' (' + n + ')' : '');
  }
  function syncSelAll(rows) { selAll.checked = rows.length > 0 && rows.every(s => checked.has(s.login)); }

  function render() {
    const rows = ALL.filter(matcher());
    matchInfo.textContent = rows.length + ' de ' + ALL.length;
    body.innerHTML = '';
    if (!ALL.length) { body.append(el('div', { class: 'muted' }, 'Nenhuma sessão ativa.')); syncSelAll(rows); updateBulk(); return; }
    if (!rows.length) { body.append(el('div', { class: 'muted' }, 'Nenhuma sessão casa com a busca.')); syncSelAll(rows); updateBulk(); return; }

    const tb = el('tbody');
    rows.forEach(s => {
      const cb = el('input', { type: 'checkbox' });
      cb.checked = checked.has(s.login);
      cb.addEventListener('change', () => { cb.checked ? checked.add(s.login) : checked.delete(s.login); syncSelAll(rows); updateBulk(); });
      const deslogarBtn = el('button', { class: 'btn ghost' }, 'Deslogar');
      deslogarBtn.addEventListener('click', () => actLogout([s.login], deslogarBtn));
      const travarBtn = el('button', { class: 'btn danger' }, 'Travar');
      travarBtn.addEventListener('click', () => actLock([s.login], travarBtn));
      tb.append(el('tr', {},
        el('td', {}, cb),
        el('td', {}, el('div', { class: 'cell-user' },
          avatarEl(s.login, s.name, 28),
          el('div', {},
            el('div', {}, s.name || s.login || '—'),
            el('div', { class: 'lg' }, '~' + (s.login || '?'))))),
        el('td', { class: 'ip' }, s.ip
          ? el('a', { href: '#', title: 'Deslogar todos deste IP', onclick: (e) => { e.preventDefault(); actLogoutIp(s.ip); } }, s.ip)
          : '—'),
        el('td', { class: 'ua', title: s.user_agent || '' }, s.user_agent || '—'),
        el('td', { class: 'small' }, fmtDate(s.login_at)),
        el('td', {}, el('div', { class: 'row-actions' }, deslogarBtn, travarBtn))));
    });
    body.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {},
        el('th', {}, ''), el('th', {}, 'Usuário'), el('th', {}, 'IP'), el('th', {}, 'User-Agent'),
        el('th', {}, 'Logado em'), el('th', {}, 'Ações'))), tb)));
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
    catch (e) { body.innerHTML = ''; body.append(errBox('Falha ao carregar sessões: ' + (e.message || 'erro'))); return; }
    ALL = data.sessions || [];
    countBadge.textContent = ALL.length + ' sessã' + (ALL.length === 1 ? 'o' : 'es');
    const present = new Set(ALL.map(s => s.login));
    [...checked].forEach(l => { if (!present.has(l)) checked.delete(l); });
    render();
  }

  async function actLogout(logins, btn) {
    if (!logins.length) return;
    if (btn) btn.disabled = true;
    try {
      const r = await apiPost('/treino/admin/logout-user', logins.length === 1 ? { login: logins[0] } : { logins }, G());
      alert('Deslogados: ' + num(r.users_count) + ' usuário(s), ' + num(r.sessions_removed) + ' sessão(ões) removida(s).');
    } catch (e) { alert('Falha ao deslogar: ' + (e.message || 'erro')); }
    checked.clear(); await load();
  }
  async function actLock(logins, btn) {
    if (!logins.length) return;
    const who = logins.length === 1 ? '"' + logins[0] + '"' : logins.length + ' usuário(s)';
    if (!confirm('Travar o acesso de ' + who + '?\n\nIsto TROCA a senha por uma aleatória (eles não conseguirão mais entrar até a senha ser redefinida) e encerra as sessões.')) return;
    if (btn) btn.disabled = true;
    try {
      const r = await apiPost('/treino/admin/lock-user', logins.length === 1 ? { login: logins[0] } : { logins }, G());
      alert('Travados: ' + num(r.users_count) + ' usuário(s) (senha trocada), ' + num(r.sessions_removed) + ' sessão(ões) removida(s).');
    } catch (e) { alert('Falha ao travar: ' + (e.message || 'erro')); }
    checked.clear(); await load();
  }
  async function actLogoutIp(ip) {
    if (!ip) return;
    const n = ALL.filter(s => s.ip === ip).length;
    if (!confirm('Deslogar TODAS as ' + n + ' sessão(ões) do IP ' + ip + '?')) return;
    try {
      const r = await apiPost('/treino/admin/logout-ip', { ip }, G());
      alert('IP ' + ip + ': ' + num(r.sessions_removed) + ' sessão(ões) removida(s) (' + num(r.users_count) + ' usuário(s)).');
    } catch (e) { alert('Falha ao deslogar IP: ' + (e.message || 'erro')); }
    await load();
  }
  bulkLogout.addEventListener('click', () => actLogout([...checked], bulkLogout));
  bulkLock.addEventListener('click', () => actLock([...checked], bulkLock));

  return { panel, load };
}

// ============================ aba: Acessos (log) ============================
function makeAccessLogTab() {
  const panel = el('div', { class: 'section' });
  const head = el('h2', {}, '📝 Acessos (log)');
  const dateInput = el('input', { type: 'date', value: todayStr() });
  dateInput.addEventListener('change', () => load());
  const tools = el('div', { class: 'toolbar' },
    el('span', { class: 'small muted' }, 'Dia:'), dateInput,
    el('button', { class: 'btn ghost', onclick: () => load() }, '↻ Atualizar'));
  const body = el('div', {}, loading());
  panel.append(head, tools, body);

  async function load() {
    body.innerHTML = ''; body.append(loading());
    const day = dateInput.value;
    let data;
    try { data = await apiGet('/treino/admin/access-log?day=' + encodeURIComponent(day), G()); }
    catch (e) { body.innerHTML = ''; body.append(errBox('Falha ao carregar o log: ' + (e.message || 'erro'))); return; }
    const entries = data.entries || [];
    body.innerHTML = '';
    body.append(el('div', { class: 'small muted', style: 'margin-bottom:.5rem' },
      entries.length + ' acesso' + (entries.length === 1 ? '' : 's') + ' em ' + (data.day || day) + ' (mais recentes primeiro).'));
    if (!entries.length) { body.append(el('div', { class: 'muted' }, 'Nenhum acesso neste dia.')); return; }

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
        el('th', {}, 'Data/Hora'), el('th', {}, 'Login'), el('th', {}, 'IP'), el('th', {}, 'User-Agent'))),
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
  } else box.append(el('div', { class: 'muted small center', style: 'padding:1rem' }, 'Sem dados.'));
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
  const head = el('h2', {}, '📊 Estatísticas');
  const tools = el('div', { class: 'toolbar' },
    el('button', { class: 'btn ghost', onclick: () => load() }, '↻ Atualizar'));
  const toc = el('div', { style: 'display:flex;gap:1rem;flex-wrap:wrap;margin:.2rem 0 .4rem;padding:.4rem .7rem;background:var(--card-bg,#f5f7fb);border-radius:.5rem' });
  const body = el('div', {}, loading());
  panel.append(head, tools, toc, body);

  async function load() {
    body.innerHTML = ''; body.append(loading()); toc.innerHTML = '';
    let data;
    try { data = await apiGet('/treino/admin/stats', G()); }
    catch (e) { body.innerHTML = ''; body.append(errBox('Falha ao carregar estatísticas: ' + (e.message || 'erro'))); return; }
    body.innerHTML = '';
    const p = data.problems || {};

    // (a) Visão geral
    tocSection('st-geral', 'Visão geral', toc, body).append(el('div', { class: 'stat-cards' },
      card(num(data.users), 'usuários totais', true),
      card(num(data.active_sessions), 'sessões ativas', true),
      card(num(p.total), 'problemas (total)', true),
      card(num(p.public), 'públicos'),
      card(num(p.private), 'privados')));

    // (b) Problemas por autor
    const s2 = tocSection('st-autor', 'Problemas por autor', toc, body);
    const authors = (data.by_author || []).filter(a => num(a.total) > 0);
    if (authors.length) {
      s2.append(el('div', { class: 'chart-wrap' },
        hBarChart(authors.slice(0, 15).map(a => ({ label: a.author || '—', value: num(a.total) })),
          { total: num(p.total), maxRows: 15 })));
      const tb = el('tbody');
      authors.forEach(a => tb.append(el('tr', {},
        el('td', {}, a.author || '—'),
        el('td', {}, el('b', {}, String(num(a.total)))),
        el('td', { class: 'small' }, String(num(a.public)) + ' públicos'),
        el('td', { class: 'small muted' }, String(num(a.private)) + ' privados'))));
      s2.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, 'Autor'), el('th', {}, 'Total'), el('th', {}, 'Públicos'), el('th', {}, 'Privados'))), tb)));
    } else s2.append(el('div', { class: 'muted small' }, 'Sem dados de autoria.'));

    // (c) Entrada de problemas públicos (mapa de calor)
    const s3 = tocSection('st-entrada', 'Entrada de problemas públicos', toc, body);
    const byDate = {}; (data.problems_public_by_day || []).forEach(d => { byDate[ymd(d.day)] = num(d.count); });
    if (Object.keys(byDate).length) {
      s3.append(el('div', { class: 'muted small', style: 'margin:.1rem 0 .5rem;line-height:1.45' },
        'Quando cada problema virou público. ⚠ Ressalva: problemas migrados não têm data real de publicação — a maioria aparece concentrada na janela da migração (meados de 2026). Datas de problemas publicados a partir de agora são exatas.'));
      s3.append(el('div', { class: 'chart-wrap' },
        heatmap(byDate, { weeks: 30, cell: 13, color: '#1a7f37', fmt: (v, date) => `${date}: ${v} problema${v === 1 ? '' : 's'} público${v === 1 ? '' : 's'}` })));
    } else s3.append(el('div', { class: 'muted small' }, 'Sem datas de entrada ainda.'));

    // (d) Atividade
    const s4 = tocSection('st-atividade', 'Atividade', toc, body);
    const logins = (data.logins_per_day || []).slice().sort((a, b) => num(a.day) - num(b.day));
    const subs = (data.submissions_per_day || []).slice().sort((a, b) => num(a.day) - num(b.day));
    const grid = el('div', { class: 'stat-grid two' });
    grid.append(dayBarBox('Logins por dia', logins, '#216097'), dayBarBox('Submissões por dia', subs, '#1a7f37'));
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
    `Baseado em ${num(cov.with_finalized)} de ${num(cov.history_total)} submissões com tempo de veredito registrado (pipeline v2). Horários em UTC.`));
  if (!num(ov.n)) {
    box.append(el('div', { class: 'muted small center', style: 'padding:1.2rem' },
      'Ainda não há submissões com tempo de resposta registrado (preenche conforme novas submissões forem julgadas).'));
    return;
  }
  box.append(el('div', { class: 'stat-cards' },
    card(fmtDur(ov.avg_wait_s), 'espera média (submit→veredito)', true),
    card(fmtDur(ov.p50_wait_s), 'espera mediana (p50)'),
    card(fmtDur(ov.p95_wait_s), 'espera p95'),
    card(fmtDur(ov.max_wait_s), 'espera máxima'),
    card(fmtDur(ov.avg_judge_s), 'julgamento médio (execução)'),
    card(fmtDur(ov.avg_queue_s), 'fila média (espera − julgamento)', true),
    card(num(ov.n), 'submissões medidas')));
  const days = (data.per_day || []).slice().sort((a, b) => num(a.day) - num(b.day));
  const lineBox = (title, key, color) => {
    const b = el('div', {}, el('div', { class: 'chart-title' }, title));
    if (days.length) b.append(el('div', { class: 'chart-wrap' }, lineChart(days.map(d => ({ x: num(d.day), y: num(d[key]), label: ddmm(d.day) })), { width: 460, height: 220, color, maxLabels: 7 })));
    else b.append(el('div', { class: 'muted small center', style: 'padding:1rem' }, 'Sem dados.'));
    return b;
  };
  const g1 = el('div', { class: 'stat-grid two' });
  g1.append(lineBox('Espera média por dia', 'avg_wait_s', '#216097'), lineBox('Espera p95 por dia', 'p95_wait_s', '#c4314b'));
  const g2 = el('div', { class: 'stat-grid two' });
  g2.append(lineBox('Julgamento médio por dia', 'avg_judge_s', '#1a7f37'), lineBox('Fila média por dia', 'avg_queue_s', '#a66a00'));
  box.append(g1, g2);
  const scaleMax = num(ov.p95_wait_s) || num(ov.avg_wait_s) || 1;   // corta no p95 p/ 1 outlier não lavar o mapa
  const byDate = {}; days.forEach(d => { byDate[ymd(d.day)] = num(d.avg_wait_s); });
  box.append(el('div', {}, el('div', { class: 'chart-title' }, 'Mapa de calor — espera média por dia'),
    el('div', { class: 'chart-wrap' }, heatmap(byDate, { weeks: 26, cell: 18, gap: 4, color: '#216097', scaleMax, fmt: (v, date) => `${date}: ${fmtDur(v)}` }))));
  // heatmapGrid lê c.value (cor/escala); as células trazem a magnitude em avg_wait_s -> mapeia.
  const waitCells = (data.by_dow_hour || []).map(c => ({ dow: num(c.dow), hour: num(c.hour), value: num(c.avg_wait_s), n: num(c.n) }));
  box.append(el('div', {}, el('div', { class: 'chart-title' }, 'Mapa de calor — espera média por dia da semana × hora (UTC)'),
    el('div', { class: 'chart-wrap' }, heatmapGrid(waitCells, { color: '#c4314b', scaleMax, fmt: (v) => fmtDur(v) }))));
}

// ---- render do VOLUME (submissões + calibrações) — mapas de calor calendário + dow×hora ----
function renderVolumeInto(box, resp, calib) {
  const calMap = (arr) => { const m = {}; (arr || []).forEach(d => { m[ymd(d.day)] = num(d.count); }); return m; };
  const dhCells = (arr) => (arr || []).map(c => ({ dow: num(c.dow), hour: num(c.hour), value: num(c.n), n: num(c.n) }));
  const calHeat = (m, color, unit) => Object.keys(m).length
    ? heatmap(m, { weeks: 40, cell: 13, color, fmt: (v, date) => `${date}: ${v} ${unit}${v === 1 ? '' : 's'}` })
    : el('div', { class: 'muted small' }, 'Sem dados.');
  const gridHeat = (cells, color, unit) => cells.length
    ? heatmapGrid(cells, { color, fmt: (v) => v + ' ' + unit + (v === 1 ? '' : 's') })
    : el('div', { class: 'muted small' }, 'Sem dados.');

  box.append(el('div', { class: 'chart-title' }, 'Submissões por dia'),
    el('div', { class: 'chart-wrap' }, calHeat(calMap(resp.subs_per_day), '#1a7f37', 'submissão')));
  box.append(el('div', { class: 'chart-title', style: 'margin-top:.6rem' }, 'Submissões por dia da semana × hora (UTC)'),
    el('div', { class: 'chart-wrap' }, gridHeat(dhCells(resp.subs_by_dow_hour), '#1a7f37', 'sub')));

  box.append(el('div', { class: 'muted small', style: 'margin:.9rem 0 .3rem;line-height:1.4' },
    'Calibrações (do log de eventos dos juízes; run/ pode rotacionar → cobertura histórica parcial).'));
  box.append(el('div', { class: 'chart-title' }, 'Calibrações por dia'),
    el('div', { class: 'chart-wrap' }, calHeat(calMap(calib.calib_per_day), '#7a5ada', 'calibração')));
  box.append(el('div', { class: 'chart-title', style: 'margin-top:.6rem' }, 'Calibrações por dia da semana × hora (UTC)'),
    el('div', { class: 'chart-wrap' }, gridHeat(dhCells(calib.calib_by_dow_hour), '#7a5ada', 'calib')));
}

// ============================ aba: Fila & tempo de resposta ============================
// Seções (TOC): Agora (contadores + o que cada máquina roda: calibração vs submissão), Tempo de
// resposta (movido da antiga aba) e Volume (mapas de calor de submissões e calibrações).
function makeQueueTab() {
  const panel = el('div', { class: 'section' });
  const head = el('h2', {}, '⏳ Fila & tempo de resposta');
  const tools = el('div', { class: 'toolbar' },
    el('button', { class: 'btn ghost', onclick: () => load() }, '↻ Atualizar'));
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
    } catch (e) { body.innerHTML = ''; body.append(errBox('Falha ao carregar a fila: ' + (e.message || 'erro'))); return; }
    body.innerHTML = '';

    // (a) Agora — contadores + o que cada máquina roda
    const s1 = tocSection('q-agora', 'Agora', toc, body);
    s1.append(el('div', { class: 'stat-cards' },
      card(num(q.total_pending), 'submissões pendentes', true),
      card(num(q.spool_queued), 'na fila (spool)'),
      card(num(q.calib_pending), 'calibrações na fila'),
      card(num(q.calib_inflight) + num(q.calib_targeted), 'calibrando agora')));
    const machines = judges.machines || [];
    if (machines.length) {
      const mtb = el('tbody');
      machines.forEach(m => {
        const cur = m.current || null;
        let job;
        if (!cur || !cur.kind) job = el('span', { class: 'muted small' }, m.online ? (m.busy ? 'ocupada' : 'livre') : 'offline');
        else if (cur.kind === 'submission') job = el('span', {}, '📥 submissão · ', el('b', {}, cur.problem_id || '?'), cur.login ? el('span', { class: 'small muted' }, ' · ' + cur.login) : '');
        else if (cur.kind === 'calibrate') job = el('span', {}, '⚙ calibração · ', el('b', {}, cur.problem_id || '?'));
        else if (cur.kind === 'index') job = el('span', {}, '🗂 indexação · ', el('b', {}, cur.problem_id || '?'));
        else job = el('span', { class: 'muted small' }, 'ocupada (calibração direcionada)');
        const qc = num(m.queued_calibrate);
        mtb.append(el('tr', {},
          el('td', {}, '🖧 ' + (m.host || '?')),
          el('td', {}, m.online ? (m.busy ? '🟡 ocupada' : '🟢 livre') : '🔴 offline'),
          el('td', {}, job),
          el('td', { class: 'small muted' }, qc ? (qc + ' na fila') : '—')));
      });
      s1.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, 'Máquina'), el('th', {}, 'Estado'), el('th', {}, 'Rodando agora'), el('th', {}, 'Calib. direcionada'))), mtb)));
    }
    const lists = q.lists || [];
    if (lists.length) {
      const tb = el('tbody');
      lists.forEach(l => tb.append(el('tr', {},
        el('td', {}, l.name || l.contest || '—'),
        el('td', { class: 'small', style: 'font-family:var(--mono)' }, l.contest || '—'),
        el('td', {}, el('b', { style: 'color:var(--warn)' }, String(num(l.pending)))))));
      s1.append(el('div', { class: 'chart-title', style: 'margin-top:.6rem' }, 'Pendentes por lista'));
      s1.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, 'Lista'), el('th', {}, 'Contest'), el('th', {}, 'Pendentes'))), tb)));
    }

    // (b) Tempo de resposta   (c) Volume
    renderResponseInto(tocSection('q-resposta', 'Tempo de resposta', toc, body), resp);
    renderVolumeInto(tocSection('q-volume', 'Volume de submissões e calibrações', toc, body), resp, calib);
  }

  return { panel, load };
}

// ============================ aba: Máquinas de julgamento ============================
function makeJudgesTab() {
  const panel = el('div', { class: 'section' });
  const head = el('h2', {}, '🖥️ Máquinas de julgamento');
  const tools = el('div', { class: 'toolbar' },
    el('button', { class: 'btn ghost', onclick: () => load() }, '↻ Atualizar'));
  const body = el('div', {}, loading());
  panel.append(head, tools, body);

  async function load() {
    body.innerHTML = ''; body.append(loading());
    let data;
    try { data = await apiGet('/treino/admin/judges', G()); }
    catch (e) { body.innerHTML = ''; body.append(errBox('Falha ao carregar o status do juiz: ' + (e.message || 'erro'))); return; }
    body.innerHTML = '';

    // status online/offline + ocupado/livre
    const statusLine = el('div', { style: 'font-size:1.15rem;font-weight:700;margin:.2rem 0 .6rem' });
    if (data.online) {
      statusLine.append(el('span', { class: 'judge-dot' }, '🟢 online'));
      statusLine.append(el('span', { class: 'tag', style: data.busy ? 'background:var(--warn-bg);color:var(--warn)' : 'background:var(--ok-bg);color:var(--ok)' },
        data.busy ? 'ocupado' : 'livre'));
    } else {
      statusLine.append(el('span', { class: 'judge-dot' }, '🔴 juiz inacessível'));
    }
    body.append(statusLine);

    // endereço do master
    body.append(el('div', { class: 'small muted', style: 'margin-bottom:.4rem' },
      data.model === 'pull' ? 'Modelo: pull (registro + heartbeat)'
        : ('Master (escalonador): ' + (data.master_host || '?') + ':' + (data.master_port != null ? data.master_port : '?'))));

    // specs do master que respondeu
    const m = data.master;
    if (m) {
      const specs = el('div', { class: 'specs' });
      const spec = (k, v) => el('div', { class: 'spec' }, el('div', { class: 'k' }, k), el('div', { class: 'v' }, v));
      if (m.hostname != null) specs.append(spec('hostname', String(m.hostname)));
      if (m.arch != null) specs.append(spec('arquitetura', String(m.arch)));
      if (m.cpu != null) specs.append(spec('CPU', String(m.cpu)));
      if (m.memory != null) {
        const gb = num(m.memory) / 1048576;   // inventário do juiz devolve kB (/proc/meminfo)
        specs.append(spec('memória', gb.toFixed(1) + ' GB'));
      }
      body.append(specs);
    } else if (data.online && data.model !== 'pull') {
      body.append(el('div', { class: 'muted small' }, 'O master respondeu, mas não informou especificações.'));
    }

    // máquinas: se o master agregou (listmachines), mostra cada uma com estado+specs
    if (data.has_machine_list && (data.machines || []).length) {
      body.append(el('div', { class: 'section-head', style: 'margin-top:1rem' },
        `Juízes — ${data.machines_online}/${data.machines_count} online`));
      // célula de SLOTS: partição vigente (do agente) + form da config desejada (o agente
      // drena os jobs em andamento e aplica; 'moj judges config' faz o mesmo pela CLI)
      const slotsCell = (mc) => {
        const cfg = mc.config || {};
        const cur = mc.partition || 'off';
        const wrap = el('div', {});
        wrap.append(el('div', {}, `${(mc.slots && mc.slots.total) || 1} slot(s) · ${cur}`
          + (cfg.partition && cfg.partition !== cur ? ` → ${cfg.partition} (aplicando…)` : '')
          + (cfg.disabled ? ' · ⛔ desabilitado' : '')));
        const sel = el('select', { class: 'small', style: 'max-width:8rem' });
        ['off', 'numa', 'cpus:4', 'cpus:8', 'cpus:16'].forEach(v => sel.append(el('option', { value: v }, v)));
        sel.value = ['off', 'numa', 'cpus:4', 'cpus:8', 'cpus:16'].includes(cfg.partition || cur) ? (cfg.partition || cur) : 'off';
        const res = el('input', { type: 'text', value: String(cfg.reserve || 0), title: 'cpus reservadas p/ o SO (fora dos slots)', style: 'width:3rem' });
        const dis = el('input', { type: 'checkbox', title: 'desabilitar (drena e para de receber trabalho)' }); dis.checked = !!cfg.disabled;
        const btn = el('button', { class: 'btn ghost', type: 'button', style: 'font-size:.82em;padding:.1rem .5rem' }, 'Aplicar');
        btn.onclick = async () => {
          btn.disabled = true; btn.textContent = '…';
          try {
            await apiPost('/ops/judge-config', { host: mc.host, partition: sel.value, reserve: parseInt(res.value, 10) || 0, disabled: dis.checked }, G());
            setTimeout(load, 2500);
          } catch (e) { alert('Falha na config: ' + e); btn.disabled = false; btn.textContent = 'Aplicar'; }
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
          : (nFree === 0 ? '🟡 ocupada' : (nFree < nTot ? `🟡 ${nTot - nFree}/${nTot} slots` : '🟢 livre'));
        const mem = rep.memory != null ? (num(rep.memory) / 1048576).toFixed(1) + ' GB' : '—';
        const langs = mc.langs || [];
        const cage = mc.cage_root ? '📦 rootfs' : '🖥 host';
        const tl = mc.tl || {};
        const tlLangs = tl.langs || [];
        const cache = mc.cache || {};
        const cacheMB = cache.bytes ? (num(cache.bytes) / 1048576).toFixed(0) + ' MB' : '0 MB';
        const clearBtn = el('button', { class: 'btn ghost', type: 'button', title: 'Limpar o cache deste juiz (vai recalibrar sob demanda)', style: 'font-size:.82em;padding:.1rem .5rem;margin-top:.2rem' }, '🗑 Limpar');
        clearBtn.onclick = async () => {
          if (!confirm('Limpar o cache de ' + mc.host + '?\nEle vai re-baixar e recalibrar os problemas sob demanda.')) return;
          clearBtn.disabled = true; clearBtn.textContent = '…';
          try { await apiPost('/ops/judge-cache', { host: mc.host, action: 'clearcache' }, G()); setTimeout(load, 3000); }
          catch (e) { alert('Falha ao limpar cache: ' + e); clearBtn.disabled = false; clearBtn.textContent = '🗑 Limpar'; }
        };
        // GPU: o registro só traz .gpu com COMPUTE comprovado (nvidia-smi/rocm-smi)
        const gpu = rep.gpu && rep.gpu.names ? rep.gpu.names : '';
        tb.append(el('tr', {},
          el('td', {}, '🖧 ' + (mc.host || '?')),
          el('td', {}, st),
          el('td', { class: 'small' },
            el('div', {}, rep.cpu ? String(rep.cpu).trim() : '—'),
            gpu ? el('div', { class: 'muted', style: 'font-size:.82em;word-break:break-word;max-width:26ch', title: 'GPU de compute (' + (rep.gpu.vendor || '') + ')' }, '🎮 ' + gpu) : ''),
          el('td', {}, mem),
          // toolchains: raiz da jaula (host/rootfs) + as linguagens que a máquina roda
          el('td', { class: 'small', title: mc.cage_root ? ('CAGE_ROOT=' + mc.cage_root) : 'raiz do sistema do host' },
            el('div', {}, cage),
            el('div', { class: 'muted', style: 'font-size:.82em;word-break:break-word;max-width:22ch' },
              langs.length ? langs.join(' ') : '—')),
          // time limits: nº de problemas calibrados + as linguagens com TL medido aqui
          el('td', { class: 'small' },
            el('div', {}, (tl.calibrated || 0) + ' problema' + ((tl.calibrated === 1) ? '' : 's')),
            el('div', { class: 'muted', style: 'font-size:.82em;word-break:break-word;max-width:18ch' },
              tlLangs.length ? ('TL: ' + tlLangs.join(' ')) : 'sem TL ainda')),
          // cache local: nº de problemas em cache + tamanho + limpar
          el('td', { class: 'small' },
            el('div', {}, (cache.problems || 0) + ' probs · ' + cacheMB),
            clearBtn),
          // SLOTS (particionamento): config fina por juiz — o agente aplica após drenar
          el('td', { class: 'small' }, slotsCell(mc))));
      });
      body.append(el('table', { class: 'moj' }, el('thead', {}, el('tr', {},
        el('th', {}, 'Máquina'), el('th', {}, 'Estado'),
        el('th', {}, 'CPU'), el('th', {}, 'Memória'),
        el('th', {}, 'Toolchains'), el('th', {}, 'Time limits'), el('th', {}, 'Cache'),
        el('th', { title: 'Particionamento em slots (a máquina corrige N problemas ao mesmo tempo, cada job pinado no seu conjunto de cpus)' }, 'Slots'))), tb));
    } else {
      const workers = data.configured_workers || [];
      body.append(el('div', { class: 'section-head', style: 'margin-top:1rem' }, 'Máquinas configuradas'));
      const count = data.configured_count != null ? data.configured_count : workers.length;
      body.append(el('div', { class: 'small', style: 'margin:.3rem 0' },
        el('b', {}, String(count)), ' máquina' + (count === 1 ? '' : 's') + ' configurada' + (count === 1 ? '' : 's') + ' no escalonador.'));
      if (workers.length) {
        const wl = el('div', { class: 'worker-list' });
        workers.forEach(w => wl.append(el('div', { class: 'worker' }, '🖧 ' + w)));
        body.append(wl);
      } else {
        body.append(el('div', { class: 'muted small' }, 'Nenhum worker listado na configuração.'));
      }
      body.append(el('div', { class: 'small muted', style: 'margin-top:.7rem;line-height:1.45' },
        'Este master ainda não tem o comando agregado de máquinas — mostrando a lista configurada. ' +
        'Faça o deploy do job-receiveitor-master.sh atualizado para ver o estado de cada máquina.'));
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
  const head = el('h2', {}, '📰 Notícias');
  const tools = el('div', { class: 'toolbar' },
    el('button', { class: 'btn', onclick: () => openForm() }, '➕ Nova notícia'),
    el('button', { class: 'btn ghost', onclick: () => load() }, '↻ Atualizar'));
  const formBox = el('div', {});
  const body = el('div', {}, loading());
  panel.append(head, tools, formBox, body);

  const b64ToText = (b64) => { try { return new TextDecoder().decode(Uint8Array.from(atob(b64 || ''), (c) => c.charCodeAt(0))); } catch { return ''; } };

  function openForm(news) {
    const editing = !!news;
    const title = el('input', { value: editing ? (news.title || '') : '', placeholder: 'Título', style: 'width:100%' });
    const summary = el('input', { value: editing ? (news.summary || '') : '', placeholder: 'Resumo (1 linha, aparece na lista)', style: 'width:100%' });
    const url = el('input', { value: editing ? (news.url || '') : '', placeholder: 'URL externa — vazio = notícia local (texto completo no MOJ)', style: 'width:100%' });
    const dateI = el('input', { type: 'datetime-local', value: toLocalDT(editing ? news.date : nowEpoch()) });

    // editor de markdown + preview ao vivo (mesmo renderizador do detalhe público)
    const bodyt = el('textarea', { rows: '16', placeholder: 'Texto completo em Markdown…',
      style: 'width:100%; font-family:var(--mono,monospace); font-size:.9rem; line-height:1.5' });
    bodyt.value = editing ? (news.body || '') : '';
    const preview = el('article', { class: 'news-body',
      style: 'border:1px solid var(--line); border-radius:10px; padding:.7rem 1rem; background:#fff; min-height:8rem; overflow:auto' });
    let pvTimer;
    const schedulePreview = () => { clearTimeout(pvTimer); pvTimer = setTimeout(refreshPreview, 400); };
    async function refreshPreview() {
      try { const r = await apiPost('/treino/admin/news/preview', { body: bodyt.value }, G()); preview.innerHTML = b64ToText(r.html_b64) || '<span class="muted small">(vazio)</span>'; }
      catch { preview.innerHTML = '<span class="muted small">(não foi possível pré-visualizar)</span>'; }
    }
    const wrapSel = (before, after) => {
      const t = bodyt, s = t.selectionStart, e = t.selectionEnd, v = t.value;
      t.value = v.slice(0, s) + before + v.slice(s, e) + (after || '') + v.slice(e);
      t.focus(); t.selectionStart = s + before.length; t.selectionEnd = e + before.length;
      schedulePreview();
    };
    const mdBtn = (label, tip, fn) => el('button', { class: 'btn ghost', type: 'button', title: tip, style: 'padding:.2rem .55rem', onclick: fn }, label);
    const toolbar = el('div', { class: 'md-toolbar' },
      mdBtn('B', 'negrito', () => wrapSel('**', '**')),
      mdBtn('i', 'itálico', () => wrapSel('*', '*')),
      mdBtn('H2', 'título', () => wrapSel('## ', '')),
      mdBtn('• lista', 'lista', () => wrapSel('- ', '')),
      mdBtn('< >', 'código', () => wrapSel('`', '`')),
      mdBtn('🔗', 'link', () => wrapSel('[', '](https://)')),
      mdBtn('“ ”', 'citação', () => wrapSel('> ', '')));
    bodyt.addEventListener('input', schedulePreview);
    refreshPreview();

    const msg = el('div', { class: 'small', style: 'margin-top:.4rem' });
    const saveBtn = el('button', { class: 'btn' }, editing ? 'Salvar alterações' : 'Publicar notícia');
    saveBtn.addEventListener('click', async () => {
      if (!title.value.trim()) { msg.className = 'small error-box'; msg.textContent = 'Informe o título'; return; }
      saveBtn.disabled = true; msg.className = 'small'; msg.textContent = 'Salvando…';
      const payload = { title: title.value.trim(), summary: summary.value.trim(), url: url.value.trim(), body: bodyt.value, date: dtToEpoch(dateI.value) };
      try {
        if (editing) { payload.key = news.key; await apiPost('/treino/admin/news/update', payload, G()); }
        else { await apiPost('/treino/admin/news', payload, G()); }
        formBox.innerHTML = ''; await load();
      } catch (e) { saveBtn.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || 'falha'; }
    });

    formBox.innerHTML = '';
    formBox.append(el('div', { class: 'section', style: 'background:#fafcff' },
      el('h3', { style: 'margin:.1rem 0 .6rem' }, editing ? 'Editar notícia' : 'Nova notícia'),
      el('div', { style: 'display:grid; grid-template-columns:2fr 1fr; gap:.8rem' },
        el('div', { class: 'field' }, el('label', {}, 'Título'), title),
        el('div', { class: 'field' }, el('label', {}, 'Data/hora'), dateI)),
      el('div', { class: 'field' }, el('label', {}, 'Resumo'), summary),
      el('div', { class: 'field' }, el('label', {}, 'URL externa (opcional)'), url),
      el('div', { class: 'field' }, el('label', {}, 'Texto completo (Markdown)'),
        el('div', { class: 'news-editor-split' },
          el('div', {}, toolbar, bodyt),
          el('div', {}, el('div', { class: 'small muted', style: 'margin-bottom:.25rem' }, 'Pré-visualização'), preview))),
      el('div', { class: 'row', style: 'margin-top:.6rem' }, saveBtn,
        el('button', { class: 'btn ghost', onclick: () => { formBox.innerHTML = ''; } }, 'Cancelar')),
      msg));
  }

  async function actDelete(news) {
    if (!confirm('Remover a notícia "' + (news.title || news.key) + '"?')) return;
    try { await apiPost('/treino/admin/news/delete', { key: news.key }, G()); await load(); }
    catch (e) { alert('Falha ao remover: ' + (e.message || 'erro')); }
  }

  async function load() {
    body.innerHTML = ''; body.append(loading());
    let data;
    try { data = await apiGet('/treino/admin/news', G()); }
    catch (e) { body.innerHTML = ''; body.append(errBox('Falha ao carregar notícias: ' + (e.message || 'erro'))); return; }
    const news = data.news || [];
    body.innerHTML = '';
    if (!news.length) { body.append(el('div', { class: 'muted' }, 'Nenhuma notícia. Use "➕ Nova notícia".')); return; }
    const tb = el('tbody');
    news.forEach((n) => {
      tb.append(el('tr', {},
        el('td', {}, el('b', {}, n.title || '(sem título)'), el('div', { class: 'small muted' }, n.summary || '')),
        el('td', { class: 'small' }, fmtDate(n.date)),
        el('td', {}, el('div', { class: 'row-actions' },
          el('button', { class: 'btn ghost', onclick: () => openForm(n) }, 'Editar'),
          el('button', { class: 'btn danger', onclick: () => actDelete(n) }, 'Remover')))));
    });
    body.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, 'Notícia'), el('th', {}, 'Data'), el('th', {}, 'Ações'))), tb)));
  }
  return { panel, load };
}

// ============================ aba: Auditoria ============================
function makeAuditTab() {
  const panel = el('div', { class: 'section' });
  const head = el('h2', {}, '🛡 Auditoria');
  const dateInput = el('input', { type: 'date', value: todayStr() });
  dateInput.addEventListener('change', () => load());
  const tools = el('div', { class: 'toolbar' },
    el('span', { class: 'small muted' }, 'Dia:'), dateInput,
    el('button', { class: 'btn ghost', onclick: () => load() }, '↻ Atualizar'));
  const body = el('div', {}, loading());
  panel.append(head, tools, body);
  const ACT = { 'logout-user': '🚪 deslogou usuário(s)', 'logout-ip': '🚪 deslogou IP', 'lock-user': '🔒 travou usuário(s)',
                'news-add': '📰 criou notícia', 'news-edit': '✏️ editou notícia', 'news-delete': '🗑 removeu notícia' };

  async function load() {
    body.innerHTML = ''; body.append(loading());
    const day = dateInput.value;
    let data;
    try { data = await apiGet('/treino/admin/audit-log?day=' + encodeURIComponent(day), G()); }
    catch (e) { body.innerHTML = ''; body.append(errBox('Falha ao carregar a auditoria: ' + (e.message || 'erro'))); return; }
    const entries = data.entries || [];
    body.innerHTML = '';
    body.append(el('div', { class: 'small muted', style: 'margin-bottom:.5rem' },
      entries.length + ' ação(ões) em ' + (data.day || day) + ' (mais recentes primeiro).'));
    if (!entries.length) { body.append(el('div', { class: 'muted' }, 'Nenhuma ação administrativa neste dia.')); return; }
    const tb = el('tbody');
    entries.forEach((e2) => {
      tb.append(el('tr', {},
        el('td', { class: 'small' }, fmtDate(e2.time)),
        el('td', { class: 'lg', style: 'font-family:var(--mono);font-size:.85rem' }, '~' + (e2.admin || '?')),
        el('td', {}, ACT[e2.action] || e2.action),
        el('td', { class: 'small', style: 'font-family:var(--mono);word-break:break-all' }, e2.details || '')));
    });
    body.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, 'Data/Hora'), el('th', {}, 'Admin'), el('th', {}, 'Ação'), el('th', {}, 'Detalhes'))), tb)));
  }
  return { panel, load };
}

// ============================ aba: Contests ============================
function makeContestsTab() {
  const panel = el('div', { class: 'section' });
  panel.append(el('h2', {}, '🏆 Contests'));

  const thr = el('input', { type: 'number', min: '0', style: 'width:90px' });
  const allow = el('textarea', { rows: '2', placeholder: 'logins separados por espaço ou vírgula', style: 'width:100%' });
  const deny = el('textarea', { rows: '2', placeholder: 'logins separados por espaço ou vírgula', style: 'width:100%' });
  const permMsg = el('div', { class: 'small' });
  const saveBtn = el('button', { class: 'btn' }, 'Salvar permissões');
  const parseList = (s) => (s || '').split(/[\s,]+/).map((x) => x.trim()).filter(Boolean);
  saveBtn.addEventListener('click', async () => {
    saveBtn.disabled = true; permMsg.className = 'small'; permMsg.textContent = 'Salvando…';
    try {
      await apiPost('/treino/admin/contest-perms', { threshold: num(thr.value), allow: parseList(allow.value), deny: parseList(deny.value) }, G());
      permMsg.className = 'small'; permMsg.textContent = '✓ salvo'; saveBtn.disabled = false;
    } catch (e) { saveBtn.disabled = false; permMsg.className = 'small error-box'; permMsg.textContent = e.message || 'falha'; }
  });
  const permBox = el('div', { class: 'section', style: 'background:#fafcff' },
    el('h3', { style: 'margin:.1rem 0 .5rem' }, 'Quem pode criar contests e problemas'),
    el('p', { class: 'muted small' }, 'Esta mesma permissão controla a criação de contests E a criação de problemas/coleções na Gestão de Problemas. Usuários .admin sempre podem. Além deles: a lista “liberados” OU quem atingir o limite de problemas resolvidos. A lista “bloqueados” impede até quem atingiria o limite.'),
    el('div', { class: 'field' }, el('label', {}, 'Liberar automaticamente quem resolveu ≥'), thr, el('span', { class: 'small muted' }, ' problemas (0 = desativado)')),
    el('div', { class: 'field' }, el('label', {}, '✅ Liberados (allow)'), allow),
    el('div', { class: 'field' }, el('label', {}, '⛔ Bloqueados (deny)'), deny),
    el('div', { class: 'row' }, saveBtn, permMsg));

  const listBox = el('div', {}, loading());

  async function loadPerms() {
    try {
      const r = await apiGet('/treino/admin/contest-perms', G()); const p = r.perms || {};
      thr.value = p.threshold || 0; allow.value = (p.allow || []).join(' '); deny.value = (p.deny || []).join(' ');
    } catch { permMsg.className = 'small error-box'; permMsg.textContent = 'Falha ao carregar permissões.'; }
  }
  async function loadList() {
    listBox.innerHTML = ''; listBox.append(loading());
    let r; try { r = await apiGet('/treino/admin/contests', G()); }
    catch (e) { listBox.innerHTML = ''; listBox.append(errBox('Falha ao carregar: ' + (e.message || 'erro'))); return; }
    const cs = r.contests || []; listBox.innerHTML = '';
    if (!cs.length) { listBox.append(el('div', { class: 'muted' }, 'Nenhum contest criado pela interface ainda.')); return; }
    const tb = el('tbody');
    cs.forEach((c) => {
      const rm = el('button', { class: 'btn danger', onclick: async () => {
        if (!confirm('Remover o contest "' + (c.name || c.id) + '"? (vai para a lixeira, reversível pelo servidor)')) return;
        try { await apiPost('/treino/admin/contest-remove', { contest: c.id }, G()); loadList(); }
        catch (e) { alert('Falha ao remover: ' + (e.message || 'erro')); }
      } }, 'Remover');
      tb.append(el('tr', {},
        el('td', {}, el('b', {}, c.name || c.id), el('div', { class: 'small muted' }, c.id)),
        el('td', { class: 'small' }, c.mode || '—'),
        el('td', { class: 'small' }, '~' + (c.owner || '?')),
        el('td', { class: 'small' }, c.created_at ? fmtDate(c.created_at) : '—'),
        el('td', {}, el('div', { class: 'row-actions' },
          el('a', { class: 'btn ghost', href: '/contest/?c=' + encodeURIComponent(c.id), target: '_blank' }, 'Abrir'),
          el('a', { class: 'btn ghost', href: '/contest/score/?c=' + encodeURIComponent(c.id), target: '_blank' }, 'Placar'),
          rm))));
    });
    listBox.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, 'Contest'), el('th', {}, 'Modo'), el('th', {}, 'Dono'), el('th', {}, 'Criado'), el('th', {}, 'Ações'))), tb)));
  }

  panel.append(permBox, el('h3', { style: 'margin:1rem 0 .3rem' }, 'Contests criados pela interface'), listBox);
  function load() { loadPerms(); loadList(); }
  return { panel, load };
}

// ============================ painel + abas ============================
function renderPanel(content) {
  content.innerHTML = '';

  const TABS = [
    { id: 'sessions', label: '👥 Sessões ativas', make: makeSessionsTab },
    { id: 'news', label: '📰 Notícias', make: makeNewsTab },
    { id: 'contests', label: '🏆 Contests', make: makeContestsTab },
    { id: 'access', label: '📝 Acessos (log)', make: makeAccessLogTab },
    { id: 'audit', label: '🛡 Auditoria', make: makeAuditTab },
    { id: 'stats', label: '📊 Estatísticas', make: makeStatsTab },
    { id: 'queue', label: '⏳ Fila & tempo de resposta', make: makeQueueTab },
    { id: 'judges', label: '🖥️ Máquinas de julgamento', make: makeJudgesTab },
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
    content.append(el('div', { class: 'access-restricted' }, 'Entre como administrador.'));
    return;
  }
  if (!st.is_admin) {
    content.innerHTML = '';
    content.append(el('div', { class: 'access-restricted' }, '🚫 Acesso restrito a administradores'));
    return;
  }
  renderPanel(content);
}
boot();
