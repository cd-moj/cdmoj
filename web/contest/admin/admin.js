// contest/admin/admin.js — HUB de administração do contest (.admin) com sub-abas:
// Configurações, Problemas, Aparência/placar, Usuários, Log & sessões. Tudo auditado.
import { apiGet, apiPost, getToken } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { fileToBase64 } from '/shared/auth.js';
import { initContestShell } from '/shared/contest-shell.js';
import { makeColorsEditor, makeTeamsEditor, makeRegionsEditor, makeBasicEditor, makeSettingsEditor, makeLangPicker, makeJudgePicker, makeBankPanel, toLocalDT, dtToEpoch } from '/shared/contest-config/index.js';
import { makeVerdictOptionsEditor, makeAutoVerdictEditor } from '/shared/contest-config/verdict-config.js';
import { makeTasksTab } from './tasks.js';
import { makeTeamsTab } from './teams-tab.js';
import { makeReviewBoard } from '/shared/review-board.js';
import { parseUsers, parseRichCsv, downloadCsv } from '/shared/users-batch.js';
import { T } from '/shared/i18n.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const enc = encodeURIComponent;
const G = { contest: CONTEST, auth: true };
const pad2 = (n) => String(n).padStart(2, '0');
const fmtDate = (e) => new Date((+e || 0) * 1000).toLocaleString('pt-BR');
const todayStr = () => { const d = new Date(); return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()); };
const field = (l, inp) => el('div', { class: 'field' }, el('label', {}, l), inp);
const chk = (l, c) => el('div', { class: 'field' }, el('label', { style: 'font-weight:400' }, c, ' ' + l));
const mkBool = (v) => { const c = el('input', { type: 'checkbox' }); c.checked = !!v; return c; };
// download de dados p/ auditoria externa (CSV)
function downloadText(filename, text, mime) {
  const blob = new Blob([text], { type: (mime || 'text/plain') + ';charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = el('a', { href: url, download: filename }); document.body.append(a); a.click();
  setTimeout(() => { a.remove(); URL.revokeObjectURL(url); }, 0);
}
const csvCell = (v) => { const s = String(v == null ? '' : v); return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
const toCsv = (rows) => rows.map((r) => r.map(csvCell).join(',')).join('\r\n') + '\r\n';
const stamp = () => new Date().toISOString().slice(0, 19).replace(/[:T]/g, '-');
// download autenticado (com Bearer) -> blob -> arquivo (p/ baixar backups/zip)
async function downloadAuthed(path, filename) {
  const r = await fetch('/api/v1' + path, { headers: { 'Authorization': 'Bearer ' + (getToken(CONTEST) || '') } });
  if (!r.ok) { alert(T('Falha no download (HTTP ', 'Download failed (HTTP ') + r.status + ')'); return; }
  const blob = await r.blob(); const url = URL.createObjectURL(blob);
  const a = el('a', { href: url, download: filename }); document.body.append(a); a.click();
  setTimeout(() => { a.remove(); URL.revokeObjectURL(url); }, 0);
}
// ============ Configurações (editor compartilhado — o mesmo do wizard de criação) ============
function settingsTab() {
  const panel = el('div', { class: 'section' });
  async function load() {
    panel.innerHTML = ''; panel.append(el('h2', {}, T('⚙️ Configurações', '⚙️ Settings')));
    let s; try { s = await apiGet('/contest/admin/settings?contest=' + enc(CONTEST), G); }
    catch (e) { panel.append(el('div', { class: 'error-box' }, T('Falha: ', 'Failed: ') + (e.message || T('erro', 'error')))); return; }
    const ed = makeSettingsEditor({ value: s, mode: 'admin', contestMode: s.mode, apiCtx: G });
    const msg = el('div', { class: 'small' });
    const save = el('button', { class: 'btn' }, T('Salvar configurações', 'Save settings'));
    save.addEventListener('click', async () => {
      const v = ed.getValue();
      // DESMARCAR o super secreto exige digitar o id (o contest volta a ser listado e o
      // placar vira público — não pode acontecer sem querer)
      if (s.secret === true && v.secret === false) {
        const typed = prompt(T('O contest deixará de ser SUPER SECRETO: voltará a ser listado na home/arquivo/status e o placar ficará PÚBLICO.\n\nPara confirmar, digite o id do contest (', 'This contest will stop being SUPER SECRET: it goes back to being listed on home/archive/status and the scoreboard becomes PUBLIC.\n\nTo confirm, type the contest id (') + CONTEST + '):');
        if (typed !== CONTEST) { msg.className = 'small error-box'; msg.textContent = T('desmarcação cancelada (id não confere) — nada foi salvo.', 'unmark cancelled (id does not match) — nothing was saved.'); return; }
      }
      save.disabled = true; msg.className = 'small'; msg.textContent = T('Salvando…', 'Saving…');
      try { await apiPost('/contest/admin/settings?contest=' + enc(CONTEST), v, G); s.secret = v.secret; msg.className = 'small'; msg.textContent = T('✓ salvo', '✓ saved'); save.disabled = false; }
      catch (e) { save.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
    });
    panel.append(ed.el, el('div', { class: 'row', style: 'margin-top:.7rem' }, save, msg));
    panel.append(await timeOverridesPanel());
  }
  return { panel, load };
}

// --- Prorrogação de vigência por sede/grupo (/contest/admin/time-overrides) ---------------
// Regras [{regex, end, reason}] contra o login: a 1ª que casa ESTENDE o fim do contest só
// p/ aquele grupo (caso de uso: queda de energia numa sede -> minutos extras só p/ ela).
async function timeOverridesPanel() {
  const box = el('div', { style: 'margin-top:1.2rem;border-top:1px solid #e3e9f2;padding-top:.8rem' },
    el('h3', {}, T('⏱ Prorrogação por sede/grupo', '⏱ Extension by site/group')),
    el('p', { class: 'muted small' },
      T('Regras regex no login: a primeira que casar define o novo fim SÓ para aquele grupo ', 'Regex rules on the login: the first that matches sets the new end ONLY for that group '),
      T('(só estende — nunca encurta; a penalidade segue contada do início normal). ', '(only extends — never shortens; the penalty is still counted from the normal start). '),
      T('Ex.: queda de energia numa sede.', 'E.g.: power outage at a site.')));
  let data; try { data = await apiGet('/contest/admin/time-overrides?contest=' + enc(CONTEST), G); }
  catch (e) { box.append(el('div', { class: 'error-box' }, T('Falha: ', 'Failed: ') + (e.message || T('erro', 'error')))); return box; }
  const rules = Array.isArray(data.rules) ? data.rules.slice() : [];
  const list = el('div', {});
  const msg = el('div', { class: 'small' });
  const render = () => {
    list.innerHTML = '';
    rules.forEach((r, i) => {
      const rx = el('input', { value: r.regex || '', placeholder: '^sede1-', style: 'width:11rem;font-family:var(--mono)' });
      const en = el('input', { type: 'datetime-local', value: r.end ? toLocalDT(r.end) : '' });
      const rs = el('input', { value: r.reason || '', placeholder: T('motivo (ex.: queda de energia)', 'reason (e.g.: power outage)'), style: 'flex:1;min-width:12rem' });
      rx.addEventListener('input', () => { r.regex = rx.value; });
      en.addEventListener('input', () => { r.end = dtToEpoch(en.value); });
      rs.addEventListener('input', () => { r.reason = rs.value; });
      list.append(el('div', { class: 'row', style: 'gap:.4rem;margin:.25rem 0;flex-wrap:wrap' }, rx, en, rs,
        el('button', { class: 'btn danger ghost', title: T('remover', 'remove'), onclick: () => { rules.splice(i, 1); render(); } }, '✕')));
    });
    if (!rules.length) list.append(el('div', { class: 'muted small' }, T('Nenhuma regra ativa (todos seguem o fim normal).', 'No active rule (everyone follows the normal end).')));
  };
  render();
  const add = el('button', { class: 'btn ghost', onclick: () => {
    rules.push({ regex: '', end: (data.contest_end || 0) + 900, reason: '' }); render();
  } }, T('+ adicionar regra (+15 min sobre o fim)', '+ add rule (+15 min over the end)'));
  const save = el('button', { class: 'btn' }, T('Salvar prorrogações', 'Save extensions'));
  save.addEventListener('click', async () => {
    save.disabled = true; msg.className = 'small'; msg.textContent = T('Salvando…', 'Saving…');
    try {
      const r = await apiPost('/contest/admin/time-overrides?contest=' + enc(CONTEST), { rules }, G);
      rules.length = 0; rules.push(...(r.rules || [])); render();
      msg.textContent = '✓ ' + T('salvo', 'saved') + ' (' + rules.length + ' ' + T('regra', 'rule') + (rules.length === 1 ? '' : 's') + ')';
    } catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
    save.disabled = false;
  });
  box.append(list, el('div', { class: 'row', style: 'margin-top:.5rem;gap:.5rem' }, add, save, msg));
  return box;
}

// ============ Problemas (sanfona: cada problema configura linguagens + enunciado) ============
function problemsTab() {
  const panel = el('div', { class: 'section' }, el('h2', {}, T('📚 Problemas', '📚 Problems')));
  const list = el('div', {});
  async function act(p) { try { await apiPost('/contest/admin/problems?contest=' + enc(CONTEST), p, G); loadList(); } catch (e) { alert(e.message || T('falha', 'failed')); } }
  async function postProb(payload, msgEl, reload) {
    if (msgEl) { msgEl.className = 'small'; msgEl.textContent = T('Salvando…', 'Saving…'); }
    try { await apiPost('/contest/admin/problems?contest=' + enc(CONTEST), payload, G); if (msgEl) msgEl.textContent = T('✓ salvo', '✓ saved'); if (reload) loadList(); }
    catch (e) { if (msgEl) { msgEl.className = 'small error-box'; msgEl.textContent = e.message || T('falha', 'failed'); } else alert(e.message || T('falha', 'failed')); }
  }
  function problemAccordion(p, i, ps, letters) {
    const body = el('div', { class: 'acc-body hidden' });
    const tog = el('span', { class: 'acc-tog' }, '▶');
    const stop = (e) => e.stopPropagation();
    const head = el('div', { class: 'acc-head' },
      tog, el('b', {}, p.letter), ' ', el('span', {}, p.name || ''),
      el('span', { class: 'small muted', style: 'font-family:var(--mono); margin-left:.4rem' }, (p.source || 'cdmoj') + '/' + p.problem_id),
      el('span', { style: 'flex:1' }),
      el('button', { class: 'btn ghost', title: T('subir', 'move up'), onclick: (e) => { stop(e); if (i > 0) { const o = letters.slice(); [o[i - 1], o[i]] = [o[i], o[i - 1]]; act({ action: 'reorder', order: o }); } } }, '↑'),
      el('button', { class: 'btn ghost', title: T('descer', 'move down'), onclick: (e) => { stop(e); if (i < ps.length - 1) { const o = letters.slice(); [o[i + 1], o[i]] = [o[i], o[i + 1]]; act({ action: 'reorder', order: o }); } } }, '↓'),
      el('button', { class: 'btn danger', title: T('remover', 'remove'), onclick: (e) => { stop(e); if (confirm(T('Remover ', 'Remove ') + p.letter + '?')) act({ action: 'remove', letter: p.letter }); } }, '✕'));
    head.addEventListener('click', () => { const hid = body.classList.toggle('hidden'); tog.textContent = hid ? '▶' : '▼'; });

    // --- renomear ---
    const nameInp = el('input', { value: p.name || '', style: 'max-width:280px' });
    const rnMsg = el('div', { class: 'small' });
    // --- linguagens (inline) ---
    const picker = makeLangPicker(p.languages || []);
    const lMsg = el('div', { class: 'small' });
    // --- pool de juízes (inline) ---
    const jPicker = makeJudgePicker(p.judges || [], G);
    const jMsg = el('div', { class: 'small' });
    // --- enunciado: atualizar do banco / enviar HTML / enviar PDF ---
    const sMsg = el('div', { class: 'small' });
    const htmlIn = el('input', { type: 'file', accept: '.html,.htm,text/html', style: 'max-width:200px' });
    const pdfIn = el('input', { type: 'file', accept: '.pdf,application/pdf', style: 'max-width:200px' });
    const sendStmt = async (payload) => postProb({ action: 'statement', letter: p.letter, ...payload }, sMsg, false);

    body.append(
      el('div', { class: 'row', style: 'margin:.3rem 0' }, el('span', { class: 'small muted' }, T('Nome:', 'Name:')), nameInp,
        el('button', { class: 'btn ghost', onclick: () => postProb({ action: 'rename', letter: p.letter, name: nameInp.value }, rnMsg, true) }, T('Renomear', 'Rename')), rnMsg),
      el('div', { style: 'margin:.5rem 0' }, el('div', { class: 'small muted' }, T('💻 Linguagens (nenhuma marcada = herda do contest):', '💻 Languages (none checked = inherits from contest):')),
        picker.el, el('div', { class: 'row' }, el('button', { class: 'btn', onclick: () => postProb({ action: 'langs', letter: p.letter, languages: picker.get() }, lMsg, false) }, T('Salvar linguagens', 'Save languages')), lMsg)),
      el('div', { style: 'margin:.5rem 0' }, el('div', { class: 'small muted' }, T('🖥️ Máquinas de juiz deste problema (nenhuma marcada = herda o pool do contest):', '🖥️ Judge machines for this problem (none checked = inherits the contest pool):')),
        jPicker.el, el('div', { class: 'row' }, el('button', { class: 'btn', onclick: () => postProb({ action: 'judges', letter: p.letter, judges: jPicker.get() }, jMsg, false) }, T('Salvar máquinas', 'Save machines')), jMsg)),
      el('div', { style: 'margin:.5rem 0' }, el('div', { class: 'small muted' }, T('📄 Enunciado:', '📄 Statement:')),
        el('div', { class: 'row', style: 'flex-wrap:wrap; gap:.4rem' },
          el('button', { class: 'btn ghost', title: T('Re-buscar do banco de problemas (regenera o enunciado)', 'Re-fetch from the problem bank (regenerates the statement)'), onclick: () => sendStmt({ refresh: true }).then(loadList) }, T('↻ Atualizar do banco', '↻ Refresh from bank')),
          el('span', { class: 'small muted' }, 'HTML:'), htmlIn,
          el('button', { class: 'btn ghost', onclick: async () => { if (!htmlIn.files[0]) { sMsg.className = 'small error-box'; sMsg.textContent = T('Escolha um .html', 'Choose a .html'); return; } sendStmt({ html_b64: await fileToBase64(htmlIn.files[0]) }); } }, T('Enviar HTML', 'Send HTML')),
          el('span', { class: 'small muted' }, 'PDF:'), pdfIn,
          el('button', { class: 'btn ghost', onclick: async () => { if (!pdfIn.files[0]) { sMsg.className = 'small error-box'; sMsg.textContent = T('Escolha um .pdf', 'Choose a .pdf'); return; } sendStmt({ pdf_b64: await fileToBase64(pdfIn.files[0]) }); } }, T('Enviar PDF', 'Send PDF'))), sMsg));
    return el('div', { class: 'acc-item' }, head, body);
  }

  async function loadList() {
    list.innerHTML = ''; let r;
    try { r = await apiGet('/contest/admin/problems?contest=' + enc(CONTEST), G); } catch { list.append(el('div', { class: 'error-box' }, T('Falha.', 'Failed.'))); return; }
    const ps = r.problems || [];
    if (!ps.length) { list.append(el('div', { class: 'muted' }, T('Sem problemas.', 'No problems.'))); return; }
    const letters = ps.map((p) => p.letter);
    ps.forEach((p, i) => list.append(problemAccordion(p, i, ps, letters)));
  }
  // painel compartilhado de busca+sorteio: busca = públicos + PRIVADOS do dono do contest
  // (mesmo sujeito do gate de add — a busca lista exatamente o que pode entrar)
  const bankApi = {
    meta: () => apiGet('/contest/admin/bank?contest=' + enc(CONTEST) + '&meta=1', G),
    draw: (p) => apiGet('/contest/admin/draw?contest=' + enc(CONTEST) + '&' + new URLSearchParams(p).toString(), G),
    search: (q) => apiGet('/contest/admin/bank?contest=' + enc(CONTEST) + '&limit=30&q=' + enc(q), G),
  };
  const bank = makeBankPanel({
    api: bankApi,
    onAdd: (it) => act({ action: 'add', problem: { bank_id: it.id, name: it.title || it.id } }),
    searchLabel: T('Buscar problemas (públicos + os privados do dono do contest)', 'Search problems (public + the contest owner\'s private ones)'),
    searchPlaceholder: T('🔎 Buscar problemas (públicos + privados do dono) — título ou id…', '🔎 Search problems (public + owner\'s private) — title or id…'),
    noQueryFilter: (items) => items.filter((it) => it.private),
    emptyHint: T('o dono do contest não tem problemas privados — digite para buscar no banco público', 'the contest owner has no private problems — type to search the public bank'),
  });

  async function load() {
    panel.append(list,
      el('h3', { style: 'margin:1rem 0 .3rem' }, T('Adicionar do banco', 'Add from bank')), bank.el);
    await loadList();
  }
  return { panel, load };
}

// ============ Aparência / placar ============
function appearanceTab() {
  const panel = el('div', { class: 'section' });
  async function load() {
    panel.innerHTML = ''; panel.append(el('h2', {}, T('🎨 Aparência e placar', '🎨 Appearance and scoreboard')));
    let cfg, ur;
    try {
      [cfg, ur] = await Promise.all([
        apiGet('/contest/admin/config?contest=' + enc(CONTEST), G),
        apiGet('/contest/admin/users?contest=' + enc(CONTEST), G).catch(() => null),
      ]);
    } catch (e) { panel.append(el('div', { class: 'error-box' }, T('Falha: ', 'Failed: ') + (e.message || T('erro', 'error')))); return; }
    // logins p/ o preview de matches (só quem entra no placar — sem contas privilegiadas)
    const logins = ((ur && ur.users) || []).map((u) => u.login)
      .filter((l) => !/\.(admin|judge|cjudge|staff|mon)$/.test(l || ''));
    const colorsEd = makeColorsEditor({ letters: cfg.letters || [], initial: cfg.colors || {} });
    const regionsEd = makeRegionsEditor({ initial: cfg.regions || [] });
    const basicEd = makeBasicEditor({ initial: cfg.basic || {} });
    const teamsEd = await makeTeamsEditor({ initial: cfg.teams_meta || [], logins });
    const msg = el('div', { class: 'small', style: 'margin:.5rem 0' });
    const save = el('button', { class: 'btn' }, T('Salvar aparência', 'Save appearance'));
    save.addEventListener('click', async () => {
      save.disabled = true; msg.className = 'small'; msg.textContent = T('Salvando…', 'Saving…');
      try { await apiPost('/contest/admin/config?contest=' + enc(CONTEST), { colors: colorsEd.getValue(), regions: regionsEd.getValue(), teams_meta: teamsEd.getValue(), basic: basicEd.getValue() }, G); msg.className = 'small'; msg.textContent = T('✓ salvo', '✓ saved'); save.disabled = false; }
      catch (e) { save.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
    });
    const hh = (t) => el('h3', { style: 'margin:1rem 0 .3rem' }, t);
    panel.append(hh(T('🎈 Cores dos balões', '🎈 Balloon colors')), colorsEd.el,
      hh(T('🏳️ Países e escolas (por regex no login)', '🏳️ Countries and schools (by regex on the login)')), teamsEd.el,
      hh(T('🔎 Filtros de região', '🔎 Region filters')), regionsEd.el,
      hh(T('⚙️ Básico', '⚙️ Basic')), basicEd.el,
      el('div', { class: 'row', style: 'margin-top:.7rem' }, save, msg));
  }
  return { panel, load };
}

// ============ Usuários & sessões (usuários + sessões/acessos + backups) ============
function usersTab() {
  const users = usersSection(), log = logSection(), backups = backupsSection();
  const panel = el('div', {}, users.panel, log.panel, backups.panel);
  async function load() { await Promise.all([users.load(), log.load(), backups.load()]); }
  return { panel, load };
}

function usersSection() {
  const panel = el('div', { class: 'section' }, el('h2', {}, T('👥 Usuários ', '👥 Users '),
    el('a', { class: 'btn ghost', style: 'font-size:.85rem; font-weight:400', target: '_blank',
      href: '/contest/badges/?c=' + enc(CONTEST) }, T('🏷️ Etiquetas de credenciais', '🏷️ Credential badges'))));
  const list = el('div', {});
  let USERS = [];
  const PRIV = /\.(admin|judge|cjudge|staff|mon)$/;
  async function call(path, body) { return apiPost('/contest/admin/' + path + '?contest=' + enc(CONTEST), body, G); }

  // filtros (sobrevivem ao re-render da lista) — essenciais em contest com 1000+ usuários
  const fQ = el('input', { type: 'search', placeholder: T('login / nome / email…', 'login / name / email…'), style: 'min-width:200px' });
  const fSel = el('select', {}, el('option', { value: '' }, T('todos', 'all')),
    el('option', { value: 'active' }, T('ativos', 'active')), el('option', { value: 'disabled' }, T('desabilitados', 'disabled')),
    el('option', { value: 'priv' }, T('privilegiados', 'privileged')));
  let showAll = false;
  fQ.addEventListener('input', () => { showAll = false; renderList(); });
  fSel.addEventListener('change', () => { showAll = false; renderList(); });

  function userRow(u) {
    const acts = el('div', { class: 'row-actions' });
    acts.append(el('button', { class: 'btn ghost', title: T('encerrar sessões', 'end sessions'), onclick: async () => { try { await call('logout-user', { login: u.login }); } catch (e) { alert(e.message); } } }, T('deslogar', 'log out')));
    if (!u.admin && !u.disabled) acts.append(el('button', { class: 'btn ghost', onclick: async () => { if (!confirm(T('Desabilitar ', 'Disable ') + u.login + '?')) return; try { await call('user-disable', { login: u.login }); loadList(); } catch (e) { alert(e.message); } } }, T('desabilitar', 'disable')));
    acts.append(el('button', { class: 'btn danger', onclick: async () => { if (!confirm(T('Remover ', 'Remove ') + u.login + '?')) return; try { await call('user-remove', { login: u.login }); loadList(); } catch (e) { alert(e.message); } } }, T('remover', 'remove')));
    return el('tr', {},
      el('td', {}, u.login, u.admin ? el('span', { class: 'small muted' }, ' (admin)') : '', u.disabled ? el('span', { class: 'flag-anom small' }, T(' (desabilitado)', ' (disabled)')) : ''),
      el('td', {}, u.fullname || ''), el('td', { class: 'small' }, u.email || ''), el('td', {}, acts));
  }
  function renderList() {
    list.innerHTML = '';
    const q = fQ.value.trim().toLowerCase(), sel = fSel.value;
    const items = USERS.filter((u) => {
      if (sel === 'active' && u.disabled) return false;
      if (sel === 'disabled' && !u.disabled) return false;
      if (sel === 'priv' && !(u.admin || PRIV.test(u.login || ''))) return false;
      return !q || [u.login, u.fullname, u.email].some((x) => (x || '').toLowerCase().includes(q));
    });
    list.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, items.length + T(' de ', ' of ') + USERS.length + T(' usuário(s).', ' user(s).')));
    if (!items.length) { list.append(el('div', { class: 'muted' }, T('Nenhum com esses filtros.', 'None with these filters.'))); return; }
    const CAP = 300, shown = showAll ? items : items.slice(0, CAP);
    const tb = el('tbody'); shown.forEach((u) => tb.append(userRow(u)));
    list.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, 'Login'), el('th', {}, T('Nome', 'Name')), el('th', {}, 'Email'), el('th', {}, T('Ações', 'Actions')))), tb)));
    if (!showAll && items.length > CAP) list.append(el('div', { style: 'margin:.4rem 0' },
      el('button', { class: 'btn ghost', onclick: () => { showAll = true; renderList(); } }, T('mostrar todos (', 'show all (') + items.length + ')'),
      el('span', { class: 'small muted' }, T(' — exibindo os ' + CAP + ' primeiros', ' — showing the first ' + CAP))));
  }
  async function loadList() {
    let r;
    try { r = await apiGet('/contest/admin/users?contest=' + enc(CONTEST), G); } catch { list.innerHTML = ''; list.append(el('div', { class: 'error-box' }, T('Falha.', 'Failed.'))); return; }
    panel.querySelectorAll('.shared-note').forEach((n) => n.remove());
    if (r.shared) panel.insertBefore(el('div', { class: 'small muted shared-note', style: 'margin-bottom:.4rem' }, T('Usuários compartilhados de "', 'Users shared from "') + r.shared + T('" — só o admin é próprio deste contest.', '" — only the admin is specific to this contest.')), list);
    USERS = r.users || []; renderList();
  }

  async function load() {
    panel.append(el('div', { class: 'row', style: 'margin:.3rem 0' }, el('span', { class: 'small muted' }, T('Filtrar:', 'Filter:')), fQ, fSel,
      el('button', { class: 'btn ghost', onclick: () => loadList() }, '↻')), list);
    // add/reset (individual)
    const li = el('input', { placeholder: 'login' }), pw = el('input', { placeholder: T('senha (gerada se vazio)', 'password (generated if empty)') }),
      fn = el('input', { placeholder: T('nome', 'name') }), em = el('input', { placeholder: T('email (opcional)', 'email (optional)') }), amsg = el('div', { class: 'small' });
    const add = el('button', { class: 'btn', onclick: async () => {
      if (!li.value.trim()) { li.focus(); return; }
      add.disabled = true; amsg.className = 'small'; amsg.textContent = T('Salvando…', 'Saving…');
      try { const r = await call('user-add', { login: li.value.trim(), password: pw.value.trim() || undefined, fullname: fn.value.trim() || undefined, email: em.value.trim() || undefined });
        amsg.className = 'small'; amsg.innerHTML = ''; amsg.append('✓ ' + r.user.login + T(' · senha: ', ' · password: '), el('span', { class: 'cred' }, r.user.password));
        add.disabled = false; li.value = pw.value = fn.value = em.value = ''; loadList();
      } catch (e) { add.disabled = false; amsg.className = 'small error-box'; amsg.textContent = e.message || T('falha', 'failed'); }
    } }, T('Adicionar / resetar / reabilitar', 'Add / reset / re-enable'));
    // troca de senha geral
    const bpw = el('input', { placeholder: T('nova senha única', 'new single password'), style: 'width:200px' }), binc = mkBool(false), bmsg = el('div', { class: 'small' });
    const bulk = el('button', { class: 'btn danger', onclick: async () => {
      if (!bpw.value.trim()) { bpw.focus(); return; }
      if (!confirm(T('Trocar a senha de TODOS os usuários não-privilegiados para esta senha?', 'Change the password of ALL non-privileged users to this password?'))) return;
      bulk.disabled = true; bmsg.className = 'small'; bmsg.textContent = '…';
      try { const r = await call('users-set-password', { password: bpw.value, include_disabled: binc.checked }); bmsg.className = 'small'; bmsg.textContent = '✓ ' + r.count + T(' usuário(s) atualizados', ' user(s) updated'); bulk.disabled = false; bpw.value = ''; loadList(); }
      catch (e) { bulk.disabled = false; bmsg.className = 'small error-box'; bmsg.textContent = e.message || T('falha', 'failed'); }
    } }, T('Trocar senha de todos', 'Change everyone\'s password'));
    panel.append(el('h3', { style: 'margin:1rem 0 .3rem' }, T('Adicionar / resetar senha', 'Add / reset password')),
      el('div', { class: 'row' }, li, pw, fn, em, add), amsg,
      makeBatchUsers(),
      el('h3', { style: 'margin:1rem 0 .3rem' }, T('🔑 Troca de senha geral (prova)', '🔑 Bulk password change (contest)')),
      el('p', { class: 'muted small' }, T('Define uma senha única para todos os não-privilegiados (após os alunos logarem).', 'Sets a single password for all non-privileged users (after the students log in).')),
      el('div', { class: 'row' }, bpw, el('label', { class: 'small' }, binc, T(' incluir desabilitados', ' include disabled')), bulk), bmsg);
    await loadList();
  }

  // ---- carga em lote (mesma colagem/arquivo da criação; a qualquer momento) ----
  function makeBatchUsers() {
    let staged = [];       // [{login,password,fullname,email, team_name?,country?,region?,…}] da prévia
    let richMode = false;  // true = veio de CSV com cabeçalho (campos de time inclusos)
    const ta = el('textarea', { rows: '5', placeholder: T('Cole aqui (ou envie um arquivo). Formatos por linha:\n  login:senha:nome:email\n  login,nome,email\n  Nome Completo   (login e senha gerados)\nOu CSV COM CABEÇALHO (ordem livre; nome = nome do time; carga única c/ país+sede):\n  login,senha,nome,pais,sede,univ,univ_nome', 'Paste here (or upload a file). Per-line formats:\n  login:senha:nome:email\n  login,nome,email\n  Full Name   (login and password generated)\nOr CSV WITH HEADER (any order; nome = team name; single load w/ country+site):\n  login,senha,nome,pais,sede,univ,univ_nome'), style: 'width:100%' });
    const fileInp = el('input', { type: 'file', accept: '.txt,.csv,text/plain,text/csv', style: 'display:none' });
    fileInp.addEventListener('change', () => { const f = fileInp.files[0]; if (!f) return; const rd = new FileReader(); rd.onload = () => { ta.value = ta.value ? (ta.value.replace(/\s*$/, '') + '\n' + rd.result) : rd.result; }; rd.readAsText(f); fileInp.value = ''; });
    const onExisting = el('select', {}, el('option', { value: 'skip' }, T('pular os que já existem', 'skip existing ones')), el('option', { value: 'update' }, T('atualizar senha dos existentes', 'update password of existing ones')));
    const prev = el('div', {}); const msg = el('div', { class: 'small' });
    const parse = (txt) => { const rich = parseRichCsv(txt); richMode = !!rich; return rich || parseUsers(txt); };
    const renderPrev = () => { prev.innerHTML = ''; if (!staged.length) return;
      prev.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' },
        staged.length + T(' linha(s) prontas (senhas em branco são geradas no servidor).', ' line(s) ready (blank passwords are generated on the server).') +
        (richMode ? T(' Cabeçalho detectado — os campos de time/país/sede vão junto.', ' Header detected — the team/country/site fields go along.') : ''))); };
    const proc = el('button', { class: 'btn ghost', onclick: () => { staged = parse(ta.value); msg.textContent = ''; renderPrev(); } }, T('Processar', 'Process'));
    const send = el('button', { class: 'btn', onclick: async () => {
      if (!staged.length) { staged = parse(ta.value); renderPrev(); }
      const users = staged.filter((u) => u.login || u.fullname).map((u) => ({
        login: u.login || undefined, password: u.password || undefined,
        fullname: u.fullname || undefined, email: u.email || undefined,
        country: u.country || undefined, region: u.region || undefined,
        univ_short: u.univ_short || undefined, univ_full: u.univ_full || undefined,
      }));
      if (!users.length) { msg.className = 'small error-box'; msg.textContent = T('Nada para enviar.', 'Nothing to send.'); return; }
      send.disabled = true; msg.className = 'small'; msg.textContent = T('Enviando ', 'Sending ') + users.length + '…';
      try {
        const r = await call('users-bulk', { users, on_existing: onExisting.value });
        const c = r.counts || {};
        msg.className = 'small'; msg.innerHTML = '';
        msg.append('✓ ' + (c.created || 0) + T(' criado(s), ', ' created, ') + (c.updated || 0) + T(' atualizado(s), ', ' updated, ') + (c.skipped || 0) + T(' pulado(s). ', ' skipped. '));
        const creds = (r.created || []).concat(r.updated || []);
        if (creds.length) msg.append(el('button', { class: 'btn ghost', onclick: () => downloadCsv(CONTEST + '-credenciais.csv', creds) }, T('⬇ baixar credenciais (CSV)', '⬇ download credentials (CSV)')));
        send.disabled = false; staged = []; ta.value = ''; renderPrev(); loadList();
      } catch (e) { send.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
    } }, T('Enviar lote', 'Send batch'));
    return el('div', {},
      el('h3', { style: 'margin:1rem 0 .3rem' }, T('📥 Usuários em lote', '📥 Batch users')),
      el('p', { class: 'muted small' }, T('Suba competidores a qualquer momento (ex.: contest criado só com contas administrativas). Colar ou enviar arquivo .txt/.csv.', 'Upload competitors at any time (e.g.: contest created with only administrative accounts). Paste or upload a .txt/.csv file.')),
      ta,
      el('div', { class: 'row', style: 'margin:.4rem 0' },
        el('button', { class: 'btn ghost', onclick: () => fileInp.click() }, T('📎 Enviar arquivo', '📎 Upload file')), fileInp,
        proc, el('span', { class: 'small muted' }, T('existentes:', 'existing:')), onExisting, send),
      prev, msg);
  }

  return { panel, load };
}

// ============ sessões + log de acessos (seção de "Usuários & sessões") ============
function logSection() {
  const panel = el('div', {});
  async function load() {
    panel.innerHTML = '';
    // sessões
    const sBox = el('div', { class: 'section' }, el('h2', {}, T('👥 Sessões ativas', '👥 Active sessions')));
    const uaFilter = el('input', { type: 'search', placeholder: T('filtrar por UA / login / IP…', 'filter by UA / login / IP…'), style: 'min-width:220px' });
    const sBody = el('div', {});
    let SESS = [];
    function renderSessions() {
      sBody.innerHTML = '';
      const f = uaFilter.value.trim().toLowerCase();
      const items = SESS.filter((s) => !f || (s.user_agent || '').toLowerCase().includes(f) || (s.login || '').toLowerCase().includes(f) || (s.ip || '').toLowerCase().includes(f));
      const tb = el('tbody');
      items.forEach((s) => {
        const anom = s.multi_ip || s.multi_ua;
        tb.append(el('tr', {},
          el('td', {}, el('span', { class: anom ? 'flag-anom' : '' }, (anom ? '⚠ ' : '') + s.login)),
          el('td', { class: 'ip' + (s.multi_ip ? ' flag-anom' : '') }, s.ip || ''),
          el('td', { class: 'ua' + (s.multi_ua ? ' flag-anom' : '') }, s.user_agent || ''),
          el('td', { class: 'small' }, fmtDate(s.login_at)),
          el('td', {}, el('button', { class: 'btn ghost', onclick: async () => { try { await apiPost('/contest/admin/logout-user?contest=' + enc(CONTEST), { login: s.login }, G); loadSessions(); } catch (e) { alert(e.message); } } }, T('deslogar', 'log out')))));
      });
      sBody.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, items.length + T(' de ', ' of ') + SESS.length + T(' sessão(ões).', ' session(s).')),
        el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' }, el('thead', {}, el('tr', {}, el('th', {}, 'Login'), el('th', {}, 'IP'), el('th', {}, T('Navegador (UA)', 'Browser (UA)')), el('th', {}, T('Login em', 'Logged in at')), el('th', {}, ''))), tb)));
    }
    async function loadSessions() {
      let r; try { r = await apiGet('/contest/admin/sessions?contest=' + enc(CONTEST), G); } catch (e) { sBody.innerHTML = ''; sBody.append(el('div', { class: 'error-box' }, T('Falha.', 'Failed.'))); return; }
      sBox.querySelectorAll('.alert').forEach((n) => n.remove());
      (r.alerts || []).forEach((a) => sBox.insertBefore(el('div', { class: 'alert' }, '⚠ ' + a.login + T(' está logado de ', ' is logged in from ') + [a.multi_ip && T('IPs diferentes', 'different IPs'), a.multi_ua && T('navegadores/máquinas diferentes', 'different browsers/machines')].filter(Boolean).join(T(' e ', ' and ')) + '.'), sBody));
      SESS = r.sessions || []; renderSessions();
    }
    uaFilter.addEventListener('input', renderSessions);
    const mismatchBtn = el('button', { class: 'btn danger', onclick: async () => { if (!confirm(T('Deslogar todas as sessões cujo UA não bate o esperado?', 'Log out all sessions whose UA does not match the expected one?'))) return; try { const r = await apiPost('/contest/admin/logout-mismatch?contest=' + enc(CONTEST), {}, G); alert(r.sessions_removed + T(' sessão(ões) encerradas.', ' session(s) ended.')); loadSessions(); } catch (e) { alert(e.message || T('falha', 'failed')); } } }, T('Deslogar UA divergente', 'Log out mismatched UA'));
    const dlSess = el('button', { class: 'btn ghost', title: T('Baixar sessões (CSV)', 'Download sessions (CSV)'), onclick: () => {
      const rows = [['login', 'ip', 'user_agent', 'login_at', 'login_iso', 'multi_ip', 'multi_ua'],
        ...SESS.map((s) => [s.login || '', s.ip || '', s.user_agent || '', s.login_at || '', new Date((s.login_at || 0) * 1000).toISOString(), !!s.multi_ip, !!s.multi_ua])];
      downloadText('sessoes-' + CONTEST + '-' + stamp() + '.csv', toCsv(rows), 'text/csv');
    } }, '⬇ CSV');
    sBox.append(el('div', { class: 'row', style: 'margin:.3rem 0' }, uaFilter, el('button', { class: 'btn ghost', onclick: () => loadSessions() }, '↻'), mismatchBtn, dlSess), sBody);

    // log de acessos
    const aBox = el('div', { class: 'section' }, el('h2', {}, T('📝 Log de acessos', '📝 Access log')));
    const dateInp = el('input', { type: 'date', value: todayStr() });
    const aBody = el('div', {});
    let ACC = [];
    const dlAcc = el('button', { class: 'btn ghost', title: T('Baixar acessos do dia (CSV)', 'Download the day\'s accesses (CSV)'), onclick: () => {
      const rows = [['epoch', 'datahora', 'login', 'ip', 'user_agent'],
        ...ACC.map((x) => [x.time, new Date((x.time || 0) * 1000).toISOString(), x.login || '', x.ip || '', x.user_agent || ''])];
      downloadText('acessos-' + CONTEST + '-' + (dateInp.value || stamp()) + '.csv', toCsv(rows), 'text/csv');
    } }, '⬇ CSV');
    async function loadAccess() {
      aBody.innerHTML = ''; let r; try { r = await apiGet('/contest/admin/access-log?contest=' + enc(CONTEST) + '&day=' + enc(dateInp.value), G); } catch { aBody.append(el('div', { class: 'error-box' }, T('Falha.', 'Failed.'))); return; }
      const e2 = r.entries || []; ACC = e2;
      aBody.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, e2.length + T(' acesso(s).', ' access(es).')));
      if (!e2.length) { aBody.append(el('div', { class: 'muted' }, T('Sem acessos.', 'No accesses.'))); return; }
      const tb = el('tbody');
      e2.forEach((x) => tb.append(el('tr', {}, el('td', { class: 'small' }, fmtDate(x.time)), el('td', {}, x.login || ''), el('td', { class: 'ip' }, x.ip || ''), el('td', { class: 'ua' }, x.user_agent || ''))));
      aBody.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' }, el('thead', {}, el('tr', {}, el('th', {}, T('Data/Hora', 'Date/Time')), el('th', {}, 'Login'), el('th', {}, 'IP'), el('th', {}, T('Navegador (UA)', 'Browser (UA)')))), tb)));
    }
    dateInp.addEventListener('change', loadAccess);
    aBox.append(el('div', { class: 'row', style: 'margin-bottom:.4rem' }, el('span', { class: 'small muted' }, T('Dia:', 'Day:')), dateInp, el('button', { class: 'btn ghost', onclick: () => loadAccess() }, '↻'), dlAcc), aBody);

    panel.append(sBox, aBox);
    await loadSessions(); await loadAccess();
  }
  return { panel, load };
}

// ============ Situação (dashboard ao vivo) ============
const fmtS = (s) => { s = Math.max(0, Math.round(+s || 0)); if (s < 60) return s + 's'; const m = Math.floor(s / 60); return m + 'min' + (s % 60 ? ' ' + (s % 60) + 's' : ''); };
const fmtClock = (e) => new Date((+e || 0) * 1000).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
const vClass = (v) => /accepted/i.test(v || '') ? 'v-ok' : (/(not answered|queue|running)/i.test(v || '') ? '' : 'flag-anom');
function dashTab() {
  const panel = el('div', { class: 'section' });
  let timer = null;
  const card = (label, val, warn) => el('div', { class: 'dash-card' + (warn ? ' warn' : '') },
    el('div', { class: 'dash-val' }, String(val)), el('div', { class: 'dash-lbl' }, label));
  async function refresh() {
    let d, sess, tq;
    try {
      [d, sess, tq] = await Promise.all([
        apiGet('/contest/admin/dashboard?contest=' + enc(CONTEST), G),
        apiGet('/contest/admin/sessions?contest=' + enc(CONTEST), G).catch(() => null),
        apiGet('/contest/staff/queue?contest=' + enc(CONTEST), G).catch(() => null),
      ]);
    } catch (e) { panel.innerHTML = ''; panel.append(el('h2', {}, T('📊 Situação', '📊 Status')), el('div', { class: 'error-box' }, T('Falha: ', 'Failed: ') + (e.message || T('erro', 'error')))); return; }
    const sub = d.submissions || {}, resp = sub.response || {}, j = d.judges || {};
    const judges = j.list || [];
    const offline = judges.filter((x) => !x.online).length;
    // pool de juízes do contest (CONTEST_JUDGES; modelo ESTRITO — pool offline segura a fila)
    const pool = Array.isArray(j.pool) ? j.pool : [];
    const poolOnline = pool.filter((h) => judges.some((x) => x.host === h && x.online)).length;
    const online = sess ? (sess.sessions || []).length : '—', alerts = sess ? (sess.alerts || []) : [];
    // tarefas do staff (impressão+balões): só quando existem
    const tasks = (tq && tq.requests) || [];
    const tPend = tasks.filter((t) => t.status === 'pending');
    const tOld = tPend.length ? Math.max(...tPend.map((t) => Math.floor(Date.now() / 1000) - (t.time || 0))) : 0;
    const taskCards = tasks.length ? [
      card(T('🖨️ impressões pend.', '🖨️ pending prints'), tPend.filter((t) => t.kind !== 'balloon').length, tOld > 600),
      card(T('🎈 balões pend.', '🎈 pending balloons'), tPend.filter((t) => t.kind === 'balloon').length, tOld > 600),
    ] : [];
    panel.innerHTML = '';
    panel.append(el('h2', {}, T('📊 Situação da prova', '📊 Contest status'),
        el('a', { href: '/contest/score/reveal.html?c=' + enc(CONTEST), target: '_blank',
                  class: 'btn ghost', style: 'margin-left:.7rem;font-size:.85rem' },
          T('🏆 Cerimônia de revelação', '🏆 Reveal ceremony')),
        // relatório final estático (tar.gz navegável offline: placar aberto, runs,
        // clarifications, estatísticas, tarefas do staff, infra) — GET admin/report
        el('button', { class: 'btn ghost', style: 'margin-left:.5rem;font-size:.85rem',
          onclick: async (ev) => {
            const b = ev.currentTarget, old = b.textContent;
            b.disabled = true; b.textContent = T('⏳ gerando…', '⏳ generating…');
            try { await downloadAuthed('/contest/admin/report?contest=' + enc(CONTEST), 'relatorio-' + CONTEST + '.tar.gz'); }
            finally { b.disabled = false; b.textContent = old; }
          } }, T('📦 Relatório estático', '📦 Static report'))),
      el('div', { class: 'dash-cards' },
        card(T('Logados', 'Logged in'), online),
        card(T('Juízes online', 'Judges online'), (j.online || 0) + '/' + (j.total || 0), (j.total || 0) > 0 && (j.online || 0) === 0),
        card(T('Juízes ocupados', 'Judges busy'), j.busy || 0),
        card(T('Fila', 'Queue'), (j.queue_depth || 0) + (j.assigned ? ' (+' + j.assigned + T(' em juiz)', ' in judge)') : ''), (j.queue_depth || 0) > 5),
        card(T('Pendentes', 'Pending'), sub.pending || 0, (sub.pending || 0) > 0),
        card(T('Maior espera', 'Longest wait'), fmtS(sub.max_wait_s), (sub.max_wait_s || 0) > 60),
        card(T('Resposta média', 'Avg response'), fmtS(resp.avg_s)),
        card(T('Resposta p95', 'p95 response'), fmtS(resp.p95_s), (resp.p95_s || 0) > 120),
        ...taskCards));

    // ⚖️ avaliação manual de veredicto (só aparece quando há fila/conflito)
    const rv = d.review || {};
    if ((rv.pending_total || 0) > 0 || (rv.being_evaluated || 0) > 0 || (rv.conflicts || 0) > 0) {
      const ev = rv.evaluators || [];
      const rtb = el('tbody');
      ev.forEach((e) => rtb.append(el('tr', {},
        el('td', {}, (e.problem_id || '').split('#').pop()),
        el('td', { class: 'small' }, e.computed_verdict || ''),
        el('td', {}, e.conflict ? el('b', { style: 'color:#c00' }, T('conflito', 'conflict')) : (e.status || '')),
        el('td', { class: 'small' }, (e.claimants || []).map((c) => c.judge + ' (' + fmtS(c.elapsed_s) + ')').join(', ') || '—'))));
      panel.append(el('div', { style: 'margin-top:.7rem' }, el('h3', {}, T('⚖️ Avaliação manual', '⚖️ Manual evaluation')),
        el('div', { class: 'dash-cards' },
          card(T('Não avaliadas', 'Not evaluated'), rv.not_evaluated || 0, (rv.not_evaluated || 0) > 0),
          card(T('Sendo avaliadas', 'Being evaluated'), rv.being_evaluated || 0),
          card(T('Conflitos', 'Conflicts'), rv.conflicts || 0, (rv.conflicts || 0) > 0)),
        ev.length ? el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
          el('thead', {}, el('tr', {}, el('th', {}, T('Problema', 'Problem')), el('th', {}, T('Computado', 'Computed')), el('th', {}, 'Status'), el('th', {}, T('Avaliando (tempo)', 'Evaluating (time)')))), rtb)) : el('p', { class: 'muted small' }, T('ninguém avaliando agora', 'nobody evaluating right now')),
        (rv.conflicts || 0) > 0 ? el('p', { class: 'small' }, T('⚠ Resolva conflitos no ', '⚠ Resolve conflicts in the '), el('a', { href: '/contest/chief/?c=' + enc(CONTEST) }, T('painel do juiz-chefe', 'chief judge panel')), '.') : ''));
    }

    // ações sugeridas (palpáveis): só aparecem quando há algo a fazer
    const actions = [];
    if ((j.total || 0) === 0) actions.push(T('Nenhum juiz registrado — nada será julgado. Suba um agente de juiz.', 'No judge registered — nothing will be judged. Bring up a judge agent.'));
    else if ((j.online || 0) === 0) actions.push(T('Todos os juízes estão OFFLINE — submissões não serão julgadas. Verifique os agentes.', 'All judges are OFFLINE — submissions will not be judged. Check the agents.'));
    else if (offline > 0) actions.push(offline + T(' juiz(es) offline — capacidade reduzida.', ' judge(s) offline — reduced capacity.'));
    if (pool.length && poolOnline === 0)
      actions.push(T('Pool de juízes definido (', 'Judge pool defined (') + pool.join(', ') + T(') mas NENHUM host do pool está online — as submissões ficarão NA FILA até um voltar.', ') but NO pool host is online — submissions will stay QUEUED until one returns.'));
    else if (pool.length && poolOnline < pool.length)
      actions.push(T('Pool de juízes com host offline (', 'Judge pool with offline host (') + pool.filter((h) => !judges.some((x) => x.host === h && x.online)).join(', ') + T(') — capacidade do pool reduzida.', ') — reduced pool capacity.'));
    if ((sub.pending || 0) > 0 && (j.online || 0) > 0 && (j.busy || 0) === 0 && (sub.max_wait_s || 0) > 60)
      actions.push(T('Há pendências esperando >1min mas nenhum juiz ocupado — possível problema de fila/roteamento.', 'There are pending items waiting >1min but no judge busy — possible queue/routing problem.'));
    if ((sub.max_wait_s || 0) > 180) actions.push(T('Submissão esperando ', 'Submission waiting ') + fmtS(sub.max_wait_s) + T(' — investigar o juiz/linguagem.', ' — investigate the judge/language.'));
    if (tOld > 600) actions.push(T('Tarefa de impressão/balão pendente há ', 'Print/balloon task pending for ') + fmtS(tOld) + T(' — veja a aba Tarefas do staff (você pode agir por lá).', ' — see the Staff tasks tab (you can act there).'));
    alerts.forEach((a) => actions.push(a.login + T(' logado de ', ' logged in from ') + [a.multi_ip && 'IPs', a.multi_ua && T('máquinas/navegadores', 'machines/browsers')].filter(Boolean).join(T(' e ', ' and ')) + T(' diferentes (possível conta compartilhada).', ' (different — possibly a shared account).')));
    if (actions.length) panel.append(el('div', { class: 'section', style: 'background:#fff7ec;border:1px solid #f3c08e' },
      el('b', {}, T('⚠ Atenção', '⚠ Attention')), el('ul', { style: 'margin:.3rem 0 0; padding-left:1.2rem' }, ...actions.map((a) => el('li', {}, a)))));

    // saúde dos juízes (por host); ⭐ = host do pool do contest
    panel.append(el('h3', { style: 'margin:1rem 0 .3rem' }, T('🖥️ Juízes (', '🖥️ Judges (') + judges.length + ')' +
      (pool.length ? ' — pool: ' + pool.join(', ') : '')));
    if (!judges.length) panel.append(el('div', { class: 'flag-anom' }, T('Nenhum juiz registrado.', 'No judge registered.')));
    else {
      const tb = el('tbody');
      judges.forEach((x) => tb.append(el('tr', {},
        el('td', {}, el('span', { class: x.online ? '' : 'flag-anom', title: pool.includes(x.host) ? T('no pool do contest', 'in the contest pool') : '' },
          (pool.includes(x.host) ? '⭐ ' : '') + (x.online ? '🟢 ' : '🔴 ') + x.host)),
        el('td', { class: 'small' }, x.state || '—'),
        el('td', { class: 'small' + (x.online ? '' : ' flag-anom') }, x.online ? 'online' : (T('offline há ', 'offline for ') + fmtS(x.age_s))),
        el('td', { class: 'small' }, String(x.problems_count || 0) + ' probs'),
        el('td', { class: 'small ua' }, (x.langs || []).join(' ')))));
      panel.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, T('Juiz', 'Judge')), el('th', {}, T('Estado', 'State')), el('th', {}, T('Visto', 'Seen')), el('th', {}, 'Cache'), el('th', {}, T('Linguagens', 'Languages')))), tb)));
    }

    // pendentes (ação: quem está esperando, há quanto tempo)
    const pend = sub.pending_list || [];
    panel.append(el('h3', { style: 'margin:1rem 0 .3rem' }, T('⏳ Pendentes (', '⏳ Pending (') + pend.length + ')'));
    if (!pend.length) panel.append(el('div', { class: 'muted' }, T('Nenhuma submissão aguardando o juiz.', 'No submission waiting for the judge.')));
    else {
      const tb = el('tbody');
      pend.forEach((p) => tb.append(el('tr', {}, el('td', {}, p.login), el('td', {}, p.problem),
        el('td', { class: 'small' }, fmtClock(p.submitted_at)),
        el('td', { class: p.waiting_s > 120 ? 'flag-anom' : (p.waiting_s > 30 ? 'flag-warn' : '') }, fmtS(p.waiting_s)))));
      panel.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, 'Login'), el('th', {}, 'Prob'), el('th', {}, T('Enviado', 'Sent')), el('th', {}, T('Esperando', 'Waiting')))), tb)));
    }

    // atividade por problema
    const pp = (sub.per_problem || []).filter((x) => x.submits > 0);
    if (pp.length) {
      panel.append(el('h3', { style: 'margin:1rem 0 .3rem' }, T('📚 Por problema', '📚 By problem')));
      const tb = el('tbody');
      pp.forEach((x) => tb.append(el('tr', {}, el('td', {}, el('b', {}, x.problem)),
        el('td', {}, String(x.submits)), el('td', { class: x.pending ? 'flag-anom' : '' }, String(x.pending)), el('td', {}, String(x.accepted)))));
      panel.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, 'Prob'), el('th', {}, 'Subs'), el('th', {}, 'Pend'), el('th', {}, 'AC'))), tb)));
    }

    // submissões recentes (feed palpável)
    const recent = sub.recent || [];
    if (recent.length) {
      panel.append(el('h3', { style: 'margin:1rem 0 .3rem' }, T('🧾 Submissões recentes', '🧾 Recent submissions')));
      const tb = el('tbody');
      recent.forEach((x) => tb.append(el('tr', {}, el('td', { class: 'small' }, fmtClock(x.at)),
        el('td', {}, x.login), el('td', {}, x.problem),
        el('td', {}, el('span', { class: vClass(x.verdict) }, x.verdict || '—')),
        el('td', { class: 'small' }, x.response_s != null ? fmtS(x.response_s) : (x.pending ? '⏳' : '—')))));
      panel.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, T('Hora', 'Time')), el('th', {}, 'Login'), el('th', {}, 'Prob'), el('th', {}, T('Veredicto', 'Verdict')), el('th', {}, T('Resposta', 'Response')))), tb)));
    }

    // timeline (submissões/min + espera média), escala correta sobre as barras visíveis
    const tl = sub.timeline || [];
    if (tl.length) {
      const maxS = Math.max(1, ...tl.map((b) => b.submits || 0));
      const maxW = Math.max(1, ...tl.map((b) => b.avg_wait_s || 0));
      panel.append(el('h3', { style: 'margin:1rem 0 .3rem' }, T('📈 Atividade (submissões/min e espera média)', '📈 Activity (submissions/min and average wait)')));
      const rows = tl.map((b) => {
        const peak = (b.avg_wait_s || 0) >= Math.max(30, maxW * 0.7) && (b.submits || 0) >= Math.max(2, maxS * 0.5);
        return el('div', { class: 'spark-row' + (peak ? ' peak' : '') },
          el('span', { class: 'spark-t small' }, fmtClock(b.t).slice(0, 5)),
          el('span', { class: 'spark-bar', style: 'width:' + Math.round(100 * (b.submits || 0) / maxS) + '%' }),
          el('span', { class: 'small muted' }, (b.submits || 0) + T(' sub · espera ~', ' sub · wait ~') + fmtS(b.avg_wait_s) + (peak ? T(' ⬅ pico', ' ⬅ peak') : '')));
      });
      panel.append(el('div', { class: 'spark' }, ...rows),
        el('div', { class: 'small muted', style: 'margin-top:.2rem' }, T('Barra ∝ submissões no minuto (máx visível = ', 'Bar ∝ submissions per minute (max visible = ') + maxS + ')'));
    }

    panel.append(el('div', { class: 'small muted', style: 'margin-top:.6rem' },
      T('Janela: últimas ', 'Window: last ') + (d.window || 0) + T(' submissões · atualizado ', ' submissions · updated ') + fmtClock(d.now) + ' · auto-refresh 12s'));
  }
  async function load() {
    await refresh();
    clearInterval(timer); timer = setInterval(() => { if (!panel.hidden) refresh(); }, 12000);
  }
  return { panel, load };
}

// ============ Auditoria (feed unificado) ============
function auditTab() {
  const panel = el('div', { class: 'section' });
  const KIND = { admin: '🛠️ admin', login: '🔑 login', submit: T('📤 submissão', '📤 submission'), verdict: T('⚖️ veredicto', '⚖️ verdict') };
  async function load() {
    panel.innerHTML = ''; panel.append(el('h2', {}, T('🧾 Auditoria do contest', '🧾 Contest audit')));
    const fUser = el('input', { type: 'search', placeholder: T('usuário…', 'user…'), style: 'width:140px' });
    const fAction = el('input', { type: 'search', placeholder: T('ação/veredicto…', 'action/verdict…'), style: 'width:170px' });
    const fSince = el('input', { type: 'date' });
    const body = el('div', {});
    let lastEvents = [];
    const dl = el('button', { class: 'btn ghost', title: T('Baixar (CSV) para auditoria externa', 'Download (CSV) for external audit'), onclick: () => {
      const rows = [['epoch', 'datahora', 'tipo', 'quem', 'acao', 'detalhes'],
        ...lastEvents.map((x) => [x.time, new Date(x.time * 1000).toISOString(), x.kind, x.who || '', x.action || '', x.details || ''])];
      downloadText('auditoria-' + CONTEST + '-' + stamp() + '.csv', toCsv(rows), 'text/csv');
    } }, '⬇ CSV');
    async function run() {
      body.innerHTML = '';
      const qp = new URLSearchParams();
      if (fUser.value.trim()) qp.set('user', fUser.value.trim());
      if (fAction.value.trim()) qp.set('action', fAction.value.trim());
      if (fSince.value) { const e = Math.floor(new Date(fSince.value + 'T00:00:00').getTime() / 1000); if (e) qp.set('since', String(e)); }
      let r;
      try { r = await apiGet('/contest/admin/audit-log?contest=' + enc(CONTEST) + (qp.toString() ? '&' + qp.toString() : ''), G); }
      catch (e) { body.append(el('div', { class: 'error-box' }, T('Falha: ', 'Failed: ') + (e.message || T('erro', 'error')))); return; }
      const ev = r.events || []; lastEvents = ev;
      body.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, ev.length + T(' evento(s).', ' event(s).')));
      if (!ev.length) { body.append(el('div', { class: 'muted' }, T('Nada encontrado.', 'Nothing found.'))); return; }
      const tb = el('tbody');
      ev.forEach((x) => tb.append(el('tr', { class: 'audit-' + x.kind },
        el('td', { class: 'small' }, fmtDate(x.time)),
        el('td', { class: 'small' }, KIND[x.kind] || x.kind),
        el('td', {}, x.who || ''),
        el('td', {}, x.action || ''),
        el('td', { class: 'small', style: 'font-family:var(--mono)' }, x.details || ''))));
      body.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, T('Quando', 'When')), el('th', {}, T('Tipo', 'Type')), el('th', {}, T('Quem', 'Who')), el('th', {}, T('Ação', 'Action')), el('th', {}, T('Detalhes', 'Details')))), tb)));
    }
    [fUser, fAction, fSince].forEach((i) => i.addEventListener('change', run));
    panel.append(el('div', { class: 'row', style: 'margin-bottom:.4rem' },
      el('span', { class: 'small muted' }, T('Filtros:', 'Filters:')), fUser, fAction, el('span', { class: 'small muted' }, T('desde', 'since')), fSince,
      el('button', { class: 'btn ghost', onclick: run }, '↻'), dl), body);
    await run();
  }
  return { panel, load };
}

// ============ backups dos usuários (seção de "Usuários & sessões") ============
function backupsSection() {
  const panel = el('div', { class: 'section' });
  async function load() {
    panel.innerHTML = ''; panel.append(el('h2', {}, T('💾 Backups dos usuários', '💾 User backups')));
    const fUser = el('input', { type: 'search', placeholder: T('usuário…', 'user…'), style: 'width:140px' });
    const fQ = el('input', { type: 'search', placeholder: T('nome do arquivo…', 'file name…'), style: 'width:160px' });
    const body = el('div', {});
    async function run() {
      body.innerHTML = '';
      const qp = new URLSearchParams();
      if (fUser.value.trim()) qp.set('user', fUser.value.trim());
      if (fQ.value.trim()) qp.set('q', fQ.value.trim());
      let r;
      try { r = await apiGet('/contest/admin/backups?contest=' + enc(CONTEST) + (qp.toString() ? '&' + qp.toString() : ''), G); }
      catch (e) { body.append(el('div', { class: 'error-box' }, T('Falha: ', 'Failed: ') + (e.message || T('erro', 'error')))); return; }
      const users = r.users || [];
      if (users.length) {
        const ub = el('div', { class: 'row', style: 'flex-wrap:wrap; gap:.5rem; margin:.3rem 0 .6rem' });
        users.forEach((u) => ub.append(el('span', { class: 'dash-card', style: 'min-width:0; padding:.35rem .6rem' },
          el('b', {}, u.login), ' ', el('span', { class: 'small muted' }, u.count + T(' arq · ', ' files · ') + Math.max(1, Math.round((u.bytes || 0) / 1024)) + ' KB'), ' ',
          el('a', { href: '#', class: 'small', title: T('Baixar zip com todos os arquivos deste usuário', 'Download a zip with all files of this user'),
            onclick: (e) => { e.preventDefault(); downloadAuthed('/contest/admin/backup-zip?contest=' + enc(CONTEST) + '&login=' + enc(u.login), 'backups-' + u.login + '.zip'); } }, '⬇ ZIP'))));
        body.append(el('div', { style: 'margin-bottom:.3rem' }, el('b', {}, T('Por usuário: ', 'Per user: ')), ub));
      }
      const items = r.backups || [];
      body.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, items.length + T(' arquivo(s).', ' file(s).')));
      if (!items.length) { body.append(el('div', { class: 'muted' }, T('Nada encontrado.', 'Nothing found.'))); return; }
      const tb = el('tbody');
      items.forEach((b) => tb.append(el('tr', {},
        el('td', {}, b.login), el('td', {}, b.name),
        el('td', { class: 'small' }, Math.max(1, Math.round((b.size || 0) / 1024)) + ' KB'),
        el('td', { class: 'small' }, fmtDate(b.time)),
        el('td', {}, el('a', { href: '#', onclick: (e) => { e.preventDefault(); downloadAuthed('/contest/backup-file?contest=' + enc(CONTEST) + '&login=' + enc(b.login) + '&id=' + enc(b.id), b.name); } }, T('⬇ baixar', '⬇ download'))))));
      body.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, T('Usuário', 'User')), el('th', {}, T('Arquivo', 'File')), el('th', {}, T('Tam.', 'Size')), el('th', {}, T('Enviado', 'Uploaded')), el('th', {}, ''))), tb)));
    }
    [fUser, fQ].forEach((i) => i.addEventListener('change', run));
    panel.append(el('div', { class: 'row', style: 'margin-bottom:.4rem' }, el('span', { class: 'small muted' }, T('Filtros:', 'Filters:')), fUser, fQ, el('button', { class: 'btn ghost', onclick: run }, '↻')), body);
    await run();
  }
  return { panel, load };
}

// ============ Tarefas do judge (fila da correção manual + config) ============
function verdictTab() {
  const panel = el('div', { class: 'section' });
  const board = makeReviewBoard({ contest: CONTEST });
  let timer = null;
  async function load() {
    panel.innerHTML = '';
    panel.append(el('h2', {}, T('⚖️ Tarefas do judge', '⚖️ Judge tasks')),
      el('p', { class: 'muted small' },
        T('Fila da correção manual: quem pegou, votos e idade de cada submissão segurada. ', 'Manual grading queue: who claimed, votes and age of each held submission. '),
        T('"Decidir/Resolver" libera o veredicto AO ALUNO na hora (override auditado); o fluxo normal de votos fica na ', '"Decide/Resolve" releases the verdict TO THE STUDENT right away (audited override); the normal voting flow is in the '),
        el('a', { href: '/contest/judge/?c=' + enc(CONTEST) }, T('área de avaliação', 'evaluation area')),
        T('. O modo e o nº de juízes que validam (1–5) ficam em Configurações; o juiz-chefe tem a mesma fila no ', '. The mode and how many judges validate (1–5) live in Settings; the chief judge has the same queue in the '),
        el('a', { href: '/contest/chief/?c=' + enc(CONTEST) }, T('painel do juiz-chefe', 'chief judge panel')),
        T('. Papéis, quórum e quantas pessoas você precisa: ', '. Roles, quorum and how many people you need: '),
        el('a', { href: '/docs/MANUAL-ADMIN.html', target: '_blank' }, T('manual do organizador', "organizer's manual")), '.'),
      board.el,
      el('h3', { style: 'margin:1.2rem 0 .3rem' }, T('⚙️ Configuração do veredicto manual', '⚙️ Manual verdict configuration')),
      makeVerdictOptionsEditor(CONTEST), makeAutoVerdictEditor(CONTEST));
    await board.load();
    clearInterval(timer); timer = setInterval(() => { if (!panel.hidden) board.load(); }, 12000);
  }
  return { panel, load };
}

// ============ Pré-prova (checklist verde/amarelo/vermelho — /contest/admin/preflight) ============
function preflightTab() {
  const panel = el('div', { class: 'section' });
  const ICON = { ok: '🟢', warn: '🟡', fail: '🔴' };
  async function load() {
    panel.innerHTML = ''; panel.append(el('h2', {}, T('✅ Pré-prova', '✅ Pre-contest')));
    let d; try { d = await apiGet('/contest/admin/preflight?contest=' + enc(CONTEST), G); }
    catch (e) { panel.append(el('div', { class: 'error-box' }, T('Falha: ', 'Failed: ') + (e.message || T('erro', 'error')))); return; }
    const s = d.summary || {};
    panel.append(el('p', { class: s.fail ? 'error-box' : 'muted' },
      s.fail ? '🔴 ' + s.fail + T(' item(ns) BLOQUEIAM a prova — resolva antes de começar.', ' item(s) BLOCK the contest — resolve before starting.')
        : s.warn ? '🟡 ' + s.warn + T(' aviso(s); nada bloqueia.', ' warning(s); nothing blocks.') : T('🟢 Tudo pronto.', '🟢 All ready.')));
    const ul = el('div', {});
    (d.checks || []).forEach((c) => ul.append(
      el('div', { style: 'display:flex;gap:.5rem;align-items:baseline;padding:.3rem 0;border-bottom:1px solid #eef2f7' },
        el('span', {}, ICON[c.level] || '•'),
        el('b', { style: 'min-width:16rem' }, c.label),
        el('span', { class: 'muted small' }, c.detail || ''))));
    panel.append(ul, el('div', { class: 'row', style: 'margin-top:.6rem' },
      el('button', { class: 'btn', onclick: load }, T('↻ Rodar de novo', '↻ Run again'))));
  }
  return { panel, load };
}

// ============ framework de abas ============
const TABS = [
  { id: 'dash', label: T('📊 Situação', '📊 Status'), make: dashTab },
  { id: 'preflight', label: T('✅ Pré-prova', '✅ Pre-contest'), make: preflightTab },
  { id: 'settings', label: T('⚙️ Configurações', '⚙️ Settings'), make: settingsTab },
  { id: 'problems', label: T('📚 Problemas', '📚 Problems'), make: problemsTab },
  { id: 'teams', label: T('👥 Times', '👥 Teams'), make: () => makeTeamsTab(CONTEST) },
  { id: 'appearance', label: T('🎨 Aparência', '🎨 Appearance'), make: appearanceTab },
  { id: 'users', label: T('👥 Usuários & sessões', '👥 Users & sessions'), make: usersTab },
  { id: 'tasks', label: T('🖨️ Tarefas do staff', '🖨️ Staff tasks'), make: () => makeTasksTab(CONTEST) },
  { id: 'verdict', label: T('⚖️ Tarefas do judge', '⚖️ Judge tasks'), make: verdictTab },
  { id: 'audit', label: T('🧾 Auditoria', '🧾 Audit'), make: auditTab },
];

async function boot() {
  if (!CONTEST) { app.innerHTML = '<div class="error-box">' + T('Contest não informado.', 'Contest not provided.') + '</div>'; return; }
  const { st } = await initContestShell(CONTEST);
  if (!st || !st.logged_in || !st.is_admin) {
    app.innerHTML = '';
    app.append(el('div', { class: 'section' }, el('h2', {}, T('🔒 Acesso restrito', '🔒 Restricted access')),
      el('a', { class: 'btn', href: '/contest/login/?c=' + enc(CONTEST) }, T('Login do contest', 'Contest login'))));
    return;
  }
  app.innerHTML = '';
  const tabbar = el('div', { class: 'tabbar' }), wrap = el('div', {});
  app.append(tabbar, wrap);
  // manual do organizador sempre à mão (abre em outra aba; explica cada opção e os papéis)
  tabbar.append(el('a', { class: 'btn ghost', style: 'margin-left:auto', target: '_blank',
    href: '/docs/MANUAL-ADMIN.html' }, T('📖 Manual do organizador', "📖 Organizer's manual")));
  const built = {}, btn = {};
  async function show(id) {
    TABS.forEach((t) => { if (built[t.id]) built[t.id].panel.hidden = (t.id !== id); btn[t.id].classList.toggle('active', t.id === id); });
    if (!built[id]) { const t = TABS.find((x) => x.id === id); const inst = t.make(); built[id] = inst; wrap.append(inst.panel); if (inst.load) await inst.load(); }
    history.replaceState(null, '', location.pathname + '?c=' + enc(CONTEST) + '#' + id);
  }
  TABS.forEach((t) => { btn[t.id] = el('button', { onclick: () => show(t.id) }, t.label); tabbar.append(btn[t.id]); });
  // aliases de abas antigas (links salvos não quebram)
  const ALIAS = { staff: 'tasks', log: 'users', backups: 'users' };
  let want = (location.hash || '').replace('#', '');
  want = ALIAS[want] || want;
  show(TABS.some((t) => t.id === want) ? want : 'settings');
}
boot();
