// treino/admin/admin.js — painel administrativo do Treino Livre (.admin apenas).
// Abas: sessões ativas, log de acessos, estatísticas, fila de submissões e
// máquinas de julgamento. Consome a API admin (Bearer + .admin) — não-admin → 403.
//   GET  /treino/admin/sessions    {count, sessions:[{login,name,ip,user_agent,login_at}]}
//   GET  /treino/admin/access-log?day=YYYY-MM-DD  {day, entries:[{time,login,ip,user_agent}]}
//   GET  /treino/admin/queue       {total_pending, spool_queued, lists:[{contest,name,pending}]}
//   GET  /treino/admin/judges      {online, busy, master, master_host, master_port, configured_workers, configured_count}
//   GET  /treino/admin/stats       {users, active_sessions, logins_per_day:[{day,count}], submissions_per_day:[{day,count}]}
//   POST /treino/admin/logout-user {login} -> {logged_out, sessions_removed}
//   POST /treino/admin/lock-user   {login} -> {locked, sessions_removed}
import { apiGet, apiPost } from '/shared/api.js';
import { status } from '/shared/auth.js';
import { el, fmtDate, avatarEl, renderAuthArea } from '/shared/ui.js';
import { barChart } from '/lib/charts.js';

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
function makeStatsTab() {
  const panel = el('div', { class: 'section' });
  const head = el('h2', {}, '📊 Estatísticas');
  const tools = el('div', { class: 'toolbar' },
    el('button', { class: 'btn ghost', onclick: () => load() }, '↻ Atualizar'));
  const body = el('div', {}, loading());
  panel.append(head, tools, body);

  function card(n, label, hl) {
    return el('div', { class: 'stat-card' + (hl ? ' hl' : '') },
      el('div', { class: 'n' }, String(n)), el('div', { class: 'lbl' }, label));
  }

  async function load() {
    body.innerHTML = ''; body.append(loading());
    let data;
    try { data = await apiGet('/treino/admin/stats', G()); }
    catch (e) { body.innerHTML = ''; body.append(errBox('Falha ao carregar estatísticas: ' + (e.message || 'erro'))); return; }
    body.innerHTML = '';

    body.append(el('div', { class: 'stat-cards' },
      card(num(data.users), 'usuários totais', true),
      card(num(data.active_sessions), 'sessões ativas', true)));

    const logins = (data.logins_per_day || []).slice().sort((a, b) => num(a.day) - num(b.day));
    const subs = (data.submissions_per_day || []).slice().sort((a, b) => num(a.day) - num(b.day));

    const grid = el('div', { class: 'stat-grid two' });

    const loginsBox = el('div', {}, el('div', { class: 'chart-title' }, 'Logins por dia'));
    if (logins.length) {
      loginsBox.append(el('div', { class: 'chart-wrap' },
        barChart(logins.map(d => ({ label: ddmm(d.day), value: num(d.count) })),
          { width: 460, height: 240, color: '#216097', rotateLabels: true, maxLabels: 15 })));
    } else {
      loginsBox.append(el('div', { class: 'muted small center', style: 'padding:1rem' }, 'Sem dados.'));
    }

    const subsBox = el('div', {}, el('div', { class: 'chart-title' }, 'Submissões por dia'));
    if (subs.length) {
      subsBox.append(el('div', { class: 'chart-wrap' },
        barChart(subs.map(d => ({ label: ddmm(d.day), value: num(d.count) })),
          { width: 460, height: 240, color: '#1a7f37', rotateLabels: true, maxLabels: 15 })));
    } else {
      subsBox.append(el('div', { class: 'muted small center', style: 'padding:1rem' }, 'Sem dados.'));
    }

    grid.append(loginsBox, subsBox);
    body.append(grid);
  }

  return { panel, load };
}

// ============================ aba: Fila de submissões ============================
function makeQueueTab() {
  const panel = el('div', { class: 'section' });
  const head = el('h2', {}, '⏳ Fila de submissões');
  const tools = el('div', { class: 'toolbar' },
    el('button', { class: 'btn ghost', onclick: () => load() }, '↻ Atualizar'));
  const body = el('div', {}, loading());
  panel.append(head, tools, body);

  function card(n, label, hl) {
    return el('div', { class: 'stat-card' + (hl ? ' hl' : '') },
      el('div', { class: 'n' }, String(n)), el('div', { class: 'lbl' }, label));
  }

  async function load() {
    body.innerHTML = ''; body.append(loading());
    let data;
    try { data = await apiGet('/treino/admin/queue', G()); }
    catch (e) { body.innerHTML = ''; body.append(errBox('Falha ao carregar a fila: ' + (e.message || 'erro'))); return; }
    body.innerHTML = '';

    body.append(el('div', { class: 'stat-cards' },
      card(num(data.total_pending), 'total pendente', true),
      card(num(data.spool_queued), 'na fila (spool)')));

    const lists = data.lists || [];
    if (!lists.length) {
      body.append(el('div', { class: 'muted' }, 'Nenhuma submissão pendente.'));
      return;
    }
    const tb = el('tbody');
    lists.forEach(l => {
      tb.append(el('tr', {},
        el('td', {}, l.name || l.contest || '—'),
        el('td', { class: 'small', style: 'font-family:var(--mono)' }, l.contest || '—'),
        el('td', {}, el('b', { style: 'color:var(--warn)' }, String(num(l.pending))))));
    });
    const table = el('table', { class: 'moj' },
      el('thead', {}, el('tr', {},
        el('th', {}, 'Lista'), el('th', {}, 'Contest'), el('th', {}, 'Pendentes'))),
      tb);
    body.append(el('div', { class: 'chart-wrap' }, table));
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
        const gb = num(m.memory) / 1048576;   // reportmachine devolve kB (/proc/meminfo)
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
      const tb = el('tbody');
      data.machines.forEach(mc => {
        const rep = mc.report || {};
        const st = !mc.online ? '🔴 offline' : (mc.busy ? '🟡 ocupada' : '🟢 livre');
        const mem = rep.memory != null ? (num(rep.memory) / 1048576).toFixed(1) + ' GB' : '—';
        tb.append(el('tr', {},
          el('td', {}, '🖧 ' + (mc.host || '?') + ':' + (mc.port != null ? mc.port : '?')),
          el('td', {}, st),
          el('td', {}, rep.hostname || '—'),
          el('td', { class: 'small' }, rep.cpu ? String(rep.cpu).trim() : '—'),
          el('td', {}, mem)));
      });
      body.append(el('table', { class: 'moj' }, el('thead', {}, el('tr', {},
        el('th', {}, 'Endereço'), el('th', {}, 'Estado'), el('th', {}, 'Hostname'),
        el('th', {}, 'CPU'), el('th', {}, 'Memória'))), tb));
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

  function openForm(news) {
    const editing = !!news;
    const title = el('input', { value: editing ? (news.title || '') : '', placeholder: 'Título', style: 'width:100%' });
    const summary = el('input', { value: editing ? (news.summary || '') : '', placeholder: 'Resumo (1 linha)', style: 'width:100%' });
    const url = el('input', { value: editing ? (news.url || '') : '', placeholder: 'URL da notícia completa (opcional)', style: 'width:100%' });
    const bodyt = el('textarea', { rows: '4', placeholder: 'Texto completo (opcional)', style: 'width:100%' });
    bodyt.value = editing ? (news.body || '') : '';
    const dateI = el('input', { type: 'datetime-local', value: toLocalDT(editing ? news.date : nowEpoch()) });
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
      el('div', { class: 'field' }, el('label', {}, 'Título'), title),
      el('div', { class: 'field' }, el('label', {}, 'Resumo'), summary),
      el('div', { class: 'field' }, el('label', {}, 'URL (opcional)'), url),
      el('div', { class: 'field' }, el('label', {}, 'Texto completo (opcional)'), bodyt),
      el('div', { class: 'field' }, el('label', {}, 'Data/hora'), dateI),
      el('div', { class: 'row' }, saveBtn,
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
    { id: 'queue', label: '⏳ Fila de submissões', make: makeQueueTab },
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
