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
  if (!r.ok) { alert('Falha no download (HTTP ' + r.status + ')'); return; }
  const blob = await r.blob(); const url = URL.createObjectURL(blob);
  const a = el('a', { href: url, download: filename }); document.body.append(a); a.click();
  setTimeout(() => { a.remove(); URL.revokeObjectURL(url); }, 0);
}
// ============ Configurações (editor compartilhado — o mesmo do wizard de criação) ============
function settingsTab() {
  const panel = el('div', { class: 'section' });
  async function load() {
    panel.innerHTML = ''; panel.append(el('h2', {}, '⚙️ Configurações'));
    let s; try { s = await apiGet('/contest/admin/settings?contest=' + enc(CONTEST), G); }
    catch (e) { panel.append(el('div', { class: 'error-box' }, 'Falha: ' + (e.message || 'erro'))); return; }
    const ed = makeSettingsEditor({ value: s, mode: 'admin', contestMode: s.mode, apiCtx: G });
    const msg = el('div', { class: 'small' });
    const save = el('button', { class: 'btn' }, 'Salvar configurações');
    save.addEventListener('click', async () => {
      const v = ed.getValue();
      // DESMARCAR o super secreto exige digitar o id (o contest volta a ser listado e o
      // placar vira público — não pode acontecer sem querer)
      if (s.secret === true && v.secret === false) {
        const typed = prompt('O contest deixará de ser SUPER SECRETO: voltará a ser listado na home/arquivo/status e o placar ficará PÚBLICO.\n\nPara confirmar, digite o id do contest (' + CONTEST + '):');
        if (typed !== CONTEST) { msg.className = 'small error-box'; msg.textContent = 'desmarcação cancelada (id não confere) — nada foi salvo.'; return; }
      }
      save.disabled = true; msg.className = 'small'; msg.textContent = 'Salvando…';
      try { await apiPost('/contest/admin/settings?contest=' + enc(CONTEST), v, G); s.secret = v.secret; msg.className = 'small'; msg.textContent = '✓ salvo'; save.disabled = false; }
      catch (e) { save.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || 'falha'; }
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
    el('h3', {}, '⏱ Prorrogação por sede/grupo'),
    el('p', { class: 'muted small' },
      'Regras regex no login: a primeira que casar define o novo fim SÓ para aquele grupo ',
      '(só estende — nunca encurta; a penalidade segue contada do início normal). ',
      'Ex.: queda de energia numa sede.'));
  let data; try { data = await apiGet('/contest/admin/time-overrides?contest=' + enc(CONTEST), G); }
  catch (e) { box.append(el('div', { class: 'error-box' }, 'Falha: ' + (e.message || 'erro'))); return box; }
  const rules = Array.isArray(data.rules) ? data.rules.slice() : [];
  const list = el('div', {});
  const msg = el('div', { class: 'small' });
  const render = () => {
    list.innerHTML = '';
    rules.forEach((r, i) => {
      const rx = el('input', { value: r.regex || '', placeholder: '^sede1-', style: 'width:11rem;font-family:var(--mono)' });
      const en = el('input', { type: 'datetime-local', value: r.end ? toLocalDT(r.end) : '' });
      const rs = el('input', { value: r.reason || '', placeholder: 'motivo (ex.: queda de energia)', style: 'flex:1;min-width:12rem' });
      rx.addEventListener('input', () => { r.regex = rx.value; });
      en.addEventListener('input', () => { r.end = dtToEpoch(en.value); });
      rs.addEventListener('input', () => { r.reason = rs.value; });
      list.append(el('div', { class: 'row', style: 'gap:.4rem;margin:.25rem 0;flex-wrap:wrap' }, rx, en, rs,
        el('button', { class: 'btn danger ghost', title: 'remover', onclick: () => { rules.splice(i, 1); render(); } }, '✕')));
    });
    if (!rules.length) list.append(el('div', { class: 'muted small' }, 'Nenhuma regra ativa (todos seguem o fim normal).'));
  };
  render();
  const add = el('button', { class: 'btn ghost', onclick: () => {
    rules.push({ regex: '', end: (data.contest_end || 0) + 900, reason: '' }); render();
  } }, '+ adicionar regra (+15 min sobre o fim)');
  const save = el('button', { class: 'btn' }, 'Salvar prorrogações');
  save.addEventListener('click', async () => {
    save.disabled = true; msg.className = 'small'; msg.textContent = 'Salvando…';
    try {
      const r = await apiPost('/contest/admin/time-overrides?contest=' + enc(CONTEST), { rules }, G);
      rules.length = 0; rules.push(...(r.rules || [])); render();
      msg.textContent = '✓ salvo (' + rules.length + ' regra' + (rules.length === 1 ? '' : 's') + ')';
    } catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || 'falha'; }
    save.disabled = false;
  });
  box.append(list, el('div', { class: 'row', style: 'margin-top:.5rem;gap:.5rem' }, add, save, msg));
  return box;
}

// ============ Problemas (sanfona: cada problema configura linguagens + enunciado) ============
function problemsTab() {
  const panel = el('div', { class: 'section' }, el('h2', {}, '📚 Problemas'));
  const list = el('div', {});
  async function act(p) { try { await apiPost('/contest/admin/problems?contest=' + enc(CONTEST), p, G); loadList(); } catch (e) { alert(e.message || 'falha'); } }
  async function postProb(payload, msgEl, reload) {
    if (msgEl) { msgEl.className = 'small'; msgEl.textContent = 'Salvando…'; }
    try { await apiPost('/contest/admin/problems?contest=' + enc(CONTEST), payload, G); if (msgEl) msgEl.textContent = '✓ salvo'; if (reload) loadList(); }
    catch (e) { if (msgEl) { msgEl.className = 'small error-box'; msgEl.textContent = e.message || 'falha'; } else alert(e.message || 'falha'); }
  }
  function problemAccordion(p, i, ps, letters) {
    const body = el('div', { class: 'acc-body hidden' });
    const tog = el('span', { class: 'acc-tog' }, '▶');
    const stop = (e) => e.stopPropagation();
    const head = el('div', { class: 'acc-head' },
      tog, el('b', {}, p.letter), ' ', el('span', {}, p.name || ''),
      el('span', { class: 'small muted', style: 'font-family:var(--mono); margin-left:.4rem' }, (p.source || 'cdmoj') + '/' + p.problem_id),
      el('span', { style: 'flex:1' }),
      el('button', { class: 'btn ghost', title: 'subir', onclick: (e) => { stop(e); if (i > 0) { const o = letters.slice(); [o[i - 1], o[i]] = [o[i], o[i - 1]]; act({ action: 'reorder', order: o }); } } }, '↑'),
      el('button', { class: 'btn ghost', title: 'descer', onclick: (e) => { stop(e); if (i < ps.length - 1) { const o = letters.slice(); [o[i + 1], o[i]] = [o[i], o[i + 1]]; act({ action: 'reorder', order: o }); } } }, '↓'),
      el('button', { class: 'btn danger', title: 'remover', onclick: (e) => { stop(e); if (confirm('Remover ' + p.letter + '?')) act({ action: 'remove', letter: p.letter }); } }, '✕'));
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
      el('div', { class: 'row', style: 'margin:.3rem 0' }, el('span', { class: 'small muted' }, 'Nome:'), nameInp,
        el('button', { class: 'btn ghost', onclick: () => postProb({ action: 'rename', letter: p.letter, name: nameInp.value }, rnMsg, true) }, 'Renomear'), rnMsg),
      el('div', { style: 'margin:.5rem 0' }, el('div', { class: 'small muted' }, '💻 Linguagens (nenhuma marcada = herda do contest):'),
        picker.el, el('div', { class: 'row' }, el('button', { class: 'btn', onclick: () => postProb({ action: 'langs', letter: p.letter, languages: picker.get() }, lMsg, false) }, 'Salvar linguagens'), lMsg)),
      el('div', { style: 'margin:.5rem 0' }, el('div', { class: 'small muted' }, '🖥️ Máquinas de juiz deste problema (nenhuma marcada = herda o pool do contest):'),
        jPicker.el, el('div', { class: 'row' }, el('button', { class: 'btn', onclick: () => postProb({ action: 'judges', letter: p.letter, judges: jPicker.get() }, jMsg, false) }, 'Salvar máquinas'), jMsg)),
      el('div', { style: 'margin:.5rem 0' }, el('div', { class: 'small muted' }, '📄 Enunciado:'),
        el('div', { class: 'row', style: 'flex-wrap:wrap; gap:.4rem' },
          el('button', { class: 'btn ghost', title: 'Re-buscar do banco de problemas (regenera o enunciado)', onclick: () => sendStmt({ refresh: true }).then(loadList) }, '↻ Atualizar do banco'),
          el('span', { class: 'small muted' }, 'HTML:'), htmlIn,
          el('button', { class: 'btn ghost', onclick: async () => { if (!htmlIn.files[0]) { sMsg.className = 'small error-box'; sMsg.textContent = 'Escolha um .html'; return; } sendStmt({ html_b64: await fileToBase64(htmlIn.files[0]) }); } }, 'Enviar HTML'),
          el('span', { class: 'small muted' }, 'PDF:'), pdfIn,
          el('button', { class: 'btn ghost', onclick: async () => { if (!pdfIn.files[0]) { sMsg.className = 'small error-box'; sMsg.textContent = 'Escolha um .pdf'; return; } sendStmt({ pdf_b64: await fileToBase64(pdfIn.files[0]) }); } }, 'Enviar PDF')), sMsg));
    return el('div', { class: 'acc-item' }, head, body);
  }

  async function loadList() {
    list.innerHTML = ''; let r;
    try { r = await apiGet('/contest/admin/problems?contest=' + enc(CONTEST), G); } catch { list.append(el('div', { class: 'error-box' }, 'Falha.')); return; }
    const ps = r.problems || [];
    if (!ps.length) { list.append(el('div', { class: 'muted' }, 'Sem problemas.')); return; }
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
    searchLabel: 'Buscar problemas (públicos + os privados do dono do contest)',
    searchPlaceholder: '🔎 Buscar problemas (públicos + privados do dono) — título ou id…',
    noQueryFilter: (items) => items.filter((it) => it.private),
    emptyHint: 'o dono do contest não tem problemas privados — digite para buscar no banco público',
  });

  async function load() {
    panel.append(list,
      el('h3', { style: 'margin:1rem 0 .3rem' }, 'Adicionar do banco'), bank.el);
    await loadList();
  }
  return { panel, load };
}

// ============ Aparência / placar ============
function appearanceTab() {
  const panel = el('div', { class: 'section' });
  async function load() {
    panel.innerHTML = ''; panel.append(el('h2', {}, '🎨 Aparência e placar'));
    let cfg, ur;
    try {
      [cfg, ur] = await Promise.all([
        apiGet('/contest/admin/config?contest=' + enc(CONTEST), G),
        apiGet('/contest/admin/users?contest=' + enc(CONTEST), G).catch(() => null),
      ]);
    } catch (e) { panel.append(el('div', { class: 'error-box' }, 'Falha: ' + (e.message || 'erro'))); return; }
    // logins p/ o preview de matches (só quem entra no placar — sem contas privilegiadas)
    const logins = ((ur && ur.users) || []).map((u) => u.login)
      .filter((l) => !/\.(admin|judge|cjudge|staff|mon)$/.test(l || ''));
    const colorsEd = makeColorsEditor({ letters: cfg.letters || [], initial: cfg.colors || {} });
    const regionsEd = makeRegionsEditor({ initial: cfg.regions || [] });
    const basicEd = makeBasicEditor({ initial: cfg.basic || {} });
    const teamsEd = await makeTeamsEditor({ initial: cfg.teams_meta || [], logins });
    const msg = el('div', { class: 'small', style: 'margin:.5rem 0' });
    const save = el('button', { class: 'btn' }, 'Salvar aparência');
    save.addEventListener('click', async () => {
      save.disabled = true; msg.className = 'small'; msg.textContent = 'Salvando…';
      try { await apiPost('/contest/admin/config?contest=' + enc(CONTEST), { colors: colorsEd.getValue(), regions: regionsEd.getValue(), teams_meta: teamsEd.getValue(), basic: basicEd.getValue() }, G); msg.className = 'small'; msg.textContent = '✓ salvo'; save.disabled = false; }
      catch (e) { save.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || 'falha'; }
    });
    const hh = (t) => el('h3', { style: 'margin:1rem 0 .3rem' }, t);
    panel.append(hh('🎈 Cores dos balões'), colorsEd.el,
      hh('🏳️ Países e escolas (por regex no login)'), teamsEd.el,
      hh('🔎 Filtros de região'), regionsEd.el,
      hh('⚙️ Básico'), basicEd.el,
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
  const panel = el('div', { class: 'section' }, el('h2', {}, '👥 Usuários ',
    el('a', { class: 'btn ghost', style: 'font-size:.85rem; font-weight:400', target: '_blank',
      href: '/contest/badges/?c=' + enc(CONTEST) }, '🏷️ Etiquetas de credenciais')));
  const list = el('div', {});
  let USERS = [];
  const PRIV = /\.(admin|judge|cjudge|staff|mon)$/;
  async function call(path, body) { return apiPost('/contest/admin/' + path + '?contest=' + enc(CONTEST), body, G); }

  // filtros (sobrevivem ao re-render da lista) — essenciais em contest com 1000+ usuários
  const fQ = el('input', { type: 'search', placeholder: 'login / nome / email…', style: 'min-width:200px' });
  const fSel = el('select', {}, el('option', { value: '' }, 'todos'),
    el('option', { value: 'active' }, 'ativos'), el('option', { value: 'disabled' }, 'desabilitados'),
    el('option', { value: 'priv' }, 'privilegiados'));
  let showAll = false;
  fQ.addEventListener('input', () => { showAll = false; renderList(); });
  fSel.addEventListener('change', () => { showAll = false; renderList(); });

  function userRow(u) {
    const acts = el('div', { class: 'row-actions' });
    acts.append(el('button', { class: 'btn ghost', title: 'encerrar sessões', onclick: async () => { try { await call('logout-user', { login: u.login }); } catch (e) { alert(e.message); } } }, 'deslogar'));
    if (!u.admin && !u.disabled) acts.append(el('button', { class: 'btn ghost', onclick: async () => { if (!confirm('Desabilitar ' + u.login + '?')) return; try { await call('user-disable', { login: u.login }); loadList(); } catch (e) { alert(e.message); } } }, 'desabilitar'));
    acts.append(el('button', { class: 'btn danger', onclick: async () => { if (!confirm('Remover ' + u.login + '?')) return; try { await call('user-remove', { login: u.login }); loadList(); } catch (e) { alert(e.message); } } }, 'remover'));
    return el('tr', {},
      el('td', {}, u.login, u.admin ? el('span', { class: 'small muted' }, ' (admin)') : '', u.disabled ? el('span', { class: 'flag-anom small' }, ' (desabilitado)') : ''),
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
    list.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, items.length + ' de ' + USERS.length + ' usuário(s).'));
    if (!items.length) { list.append(el('div', { class: 'muted' }, 'Nenhum com esses filtros.')); return; }
    const CAP = 300, shown = showAll ? items : items.slice(0, CAP);
    const tb = el('tbody'); shown.forEach((u) => tb.append(userRow(u)));
    list.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, 'Login'), el('th', {}, 'Nome'), el('th', {}, 'Email'), el('th', {}, 'Ações'))), tb)));
    if (!showAll && items.length > CAP) list.append(el('div', { style: 'margin:.4rem 0' },
      el('button', { class: 'btn ghost', onclick: () => { showAll = true; renderList(); } }, 'mostrar todos (' + items.length + ')'),
      el('span', { class: 'small muted' }, ' — exibindo os ' + CAP + ' primeiros')));
  }
  async function loadList() {
    let r;
    try { r = await apiGet('/contest/admin/users?contest=' + enc(CONTEST), G); } catch { list.innerHTML = ''; list.append(el('div', { class: 'error-box' }, 'Falha.')); return; }
    panel.querySelectorAll('.shared-note').forEach((n) => n.remove());
    if (r.shared) panel.insertBefore(el('div', { class: 'small muted shared-note', style: 'margin-bottom:.4rem' }, 'Usuários compartilhados de "' + r.shared + '" — só o admin é próprio deste contest.'), list);
    USERS = r.users || []; renderList();
  }

  async function load() {
    panel.append(el('div', { class: 'row', style: 'margin:.3rem 0' }, el('span', { class: 'small muted' }, 'Filtrar:'), fQ, fSel,
      el('button', { class: 'btn ghost', onclick: () => loadList() }, '↻')), list);
    // add/reset (individual)
    const li = el('input', { placeholder: 'login' }), pw = el('input', { placeholder: 'senha (gerada se vazio)' }),
      fn = el('input', { placeholder: 'nome' }), em = el('input', { placeholder: 'email (opcional)' }), amsg = el('div', { class: 'small' });
    const add = el('button', { class: 'btn', onclick: async () => {
      if (!li.value.trim()) { li.focus(); return; }
      add.disabled = true; amsg.className = 'small'; amsg.textContent = 'Salvando…';
      try { const r = await call('user-add', { login: li.value.trim(), password: pw.value.trim() || undefined, fullname: fn.value.trim() || undefined, email: em.value.trim() || undefined });
        amsg.className = 'small'; amsg.innerHTML = ''; amsg.append('✓ ' + r.user.login + ' · senha: ', el('span', { class: 'cred' }, r.user.password));
        add.disabled = false; li.value = pw.value = fn.value = em.value = ''; loadList();
      } catch (e) { add.disabled = false; amsg.className = 'small error-box'; amsg.textContent = e.message || 'falha'; }
    } }, 'Adicionar / resetar / reabilitar');
    // troca de senha geral
    const bpw = el('input', { placeholder: 'nova senha única', style: 'width:200px' }), binc = mkBool(false), bmsg = el('div', { class: 'small' });
    const bulk = el('button', { class: 'btn danger', onclick: async () => {
      if (!bpw.value.trim()) { bpw.focus(); return; }
      if (!confirm('Trocar a senha de TODOS os usuários não-privilegiados para esta senha?')) return;
      bulk.disabled = true; bmsg.className = 'small'; bmsg.textContent = '…';
      try { const r = await call('users-set-password', { password: bpw.value, include_disabled: binc.checked }); bmsg.className = 'small'; bmsg.textContent = '✓ ' + r.count + ' usuário(s) atualizados'; bulk.disabled = false; bpw.value = ''; loadList(); }
      catch (e) { bulk.disabled = false; bmsg.className = 'small error-box'; bmsg.textContent = e.message || 'falha'; }
    } }, 'Trocar senha de todos');
    panel.append(el('h3', { style: 'margin:1rem 0 .3rem' }, 'Adicionar / resetar senha'),
      el('div', { class: 'row' }, li, pw, fn, em, add), amsg,
      makeBatchUsers(),
      el('h3', { style: 'margin:1rem 0 .3rem' }, '🔑 Troca de senha geral (prova)'),
      el('p', { class: 'muted small' }, 'Define uma senha única para todos os não-privilegiados (após os alunos logarem).'),
      el('div', { class: 'row' }, bpw, el('label', { class: 'small' }, binc, ' incluir desabilitados'), bulk), bmsg);
    await loadList();
  }

  // ---- carga em lote (mesma colagem/arquivo da criação; a qualquer momento) ----
  function makeBatchUsers() {
    let staged = [];       // [{login,password,fullname,email, team_name?,country?,region?,…}] da prévia
    let richMode = false;  // true = veio de CSV com cabeçalho (campos de time inclusos)
    const ta = el('textarea', { rows: '5', placeholder: 'Cole aqui (ou envie um arquivo). Formatos por linha:\n  login:senha:nome:email\n  login,nome,email\n  Nome Completo   (login e senha gerados)\nOu CSV COM CABEÇALHO (ordem livre; nome = nome do time; carga única c/ país+sede):\n  login,senha,nome,pais,sede,univ,univ_nome', style: 'width:100%' });
    const fileInp = el('input', { type: 'file', accept: '.txt,.csv,text/plain,text/csv', style: 'display:none' });
    fileInp.addEventListener('change', () => { const f = fileInp.files[0]; if (!f) return; const rd = new FileReader(); rd.onload = () => { ta.value = ta.value ? (ta.value.replace(/\s*$/, '') + '\n' + rd.result) : rd.result; }; rd.readAsText(f); fileInp.value = ''; });
    const onExisting = el('select', {}, el('option', { value: 'skip' }, 'pular os que já existem'), el('option', { value: 'update' }, 'atualizar senha dos existentes'));
    const prev = el('div', {}); const msg = el('div', { class: 'small' });
    const parse = (txt) => { const rich = parseRichCsv(txt); richMode = !!rich; return rich || parseUsers(txt); };
    const renderPrev = () => { prev.innerHTML = ''; if (!staged.length) return;
      prev.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' },
        staged.length + ' linha(s) prontas (senhas em branco são geradas no servidor).' +
        (richMode ? ' Cabeçalho detectado — os campos de time/país/sede vão junto.' : ''))); };
    const proc = el('button', { class: 'btn ghost', onclick: () => { staged = parse(ta.value); msg.textContent = ''; renderPrev(); } }, 'Processar');
    const send = el('button', { class: 'btn', onclick: async () => {
      if (!staged.length) { staged = parse(ta.value); renderPrev(); }
      const users = staged.filter((u) => u.login || u.fullname).map((u) => ({
        login: u.login || undefined, password: u.password || undefined,
        fullname: u.fullname || undefined, email: u.email || undefined,
        country: u.country || undefined, region: u.region || undefined,
        univ_short: u.univ_short || undefined, univ_full: u.univ_full || undefined,
      }));
      if (!users.length) { msg.className = 'small error-box'; msg.textContent = 'Nada para enviar.'; return; }
      send.disabled = true; msg.className = 'small'; msg.textContent = 'Enviando ' + users.length + '…';
      try {
        const r = await call('users-bulk', { users, on_existing: onExisting.value });
        const c = r.counts || {};
        msg.className = 'small'; msg.innerHTML = '';
        msg.append('✓ ' + (c.created || 0) + ' criado(s), ' + (c.updated || 0) + ' atualizado(s), ' + (c.skipped || 0) + ' pulado(s). ');
        const creds = (r.created || []).concat(r.updated || []);
        if (creds.length) msg.append(el('button', { class: 'btn ghost', onclick: () => downloadCsv(CONTEST + '-credenciais.csv', creds) }, '⬇ baixar credenciais (CSV)'));
        send.disabled = false; staged = []; ta.value = ''; renderPrev(); loadList();
      } catch (e) { send.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || 'falha'; }
    } }, 'Enviar lote');
    return el('div', {},
      el('h3', { style: 'margin:1rem 0 .3rem' }, '📥 Usuários em lote'),
      el('p', { class: 'muted small' }, 'Suba competidores a qualquer momento (ex.: contest criado só com contas administrativas). Colar ou enviar arquivo .txt/.csv.'),
      ta,
      el('div', { class: 'row', style: 'margin:.4rem 0' },
        el('button', { class: 'btn ghost', onclick: () => fileInp.click() }, '📎 Enviar arquivo'), fileInp,
        proc, el('span', { class: 'small muted' }, 'existentes:'), onExisting, send),
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
    const sBox = el('div', { class: 'section' }, el('h2', {}, '👥 Sessões ativas'));
    const uaFilter = el('input', { type: 'search', placeholder: 'filtrar por UA / login / IP…', style: 'min-width:220px' });
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
          el('td', {}, el('button', { class: 'btn ghost', onclick: async () => { try { await apiPost('/contest/admin/logout-user?contest=' + enc(CONTEST), { login: s.login }, G); loadSessions(); } catch (e) { alert(e.message); } } }, 'deslogar'))));
      });
      sBody.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, items.length + ' de ' + SESS.length + ' sessão(ões).'),
        el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' }, el('thead', {}, el('tr', {}, el('th', {}, 'Login'), el('th', {}, 'IP'), el('th', {}, 'Navegador (UA)'), el('th', {}, 'Login em'), el('th', {}, ''))), tb)));
    }
    async function loadSessions() {
      let r; try { r = await apiGet('/contest/admin/sessions?contest=' + enc(CONTEST), G); } catch (e) { sBody.innerHTML = ''; sBody.append(el('div', { class: 'error-box' }, 'Falha.')); return; }
      sBox.querySelectorAll('.alert').forEach((n) => n.remove());
      (r.alerts || []).forEach((a) => sBox.insertBefore(el('div', { class: 'alert' }, '⚠ ' + a.login + ' está logado de ' + [a.multi_ip && 'IPs diferentes', a.multi_ua && 'navegadores/máquinas diferentes'].filter(Boolean).join(' e ') + '.'), sBody));
      SESS = r.sessions || []; renderSessions();
    }
    uaFilter.addEventListener('input', renderSessions);
    const mismatchBtn = el('button', { class: 'btn danger', onclick: async () => { if (!confirm('Deslogar todas as sessões cujo UA não bate o esperado?')) return; try { const r = await apiPost('/contest/admin/logout-mismatch?contest=' + enc(CONTEST), {}, G); alert(r.sessions_removed + ' sessão(ões) encerradas.'); loadSessions(); } catch (e) { alert(e.message || 'falha'); } } }, 'Deslogar UA divergente');
    const dlSess = el('button', { class: 'btn ghost', title: 'Baixar sessões (CSV)', onclick: () => {
      const rows = [['login', 'ip', 'user_agent', 'login_at', 'login_iso', 'multi_ip', 'multi_ua'],
        ...SESS.map((s) => [s.login || '', s.ip || '', s.user_agent || '', s.login_at || '', new Date((s.login_at || 0) * 1000).toISOString(), !!s.multi_ip, !!s.multi_ua])];
      downloadText('sessoes-' + CONTEST + '-' + stamp() + '.csv', toCsv(rows), 'text/csv');
    } }, '⬇ CSV');
    sBox.append(el('div', { class: 'row', style: 'margin:.3rem 0' }, uaFilter, el('button', { class: 'btn ghost', onclick: () => loadSessions() }, '↻'), mismatchBtn, dlSess), sBody);

    // log de acessos
    const aBox = el('div', { class: 'section' }, el('h2', {}, '📝 Log de acessos'));
    const dateInp = el('input', { type: 'date', value: todayStr() });
    const aBody = el('div', {});
    let ACC = [];
    const dlAcc = el('button', { class: 'btn ghost', title: 'Baixar acessos do dia (CSV)', onclick: () => {
      const rows = [['epoch', 'datahora', 'login', 'ip', 'user_agent'],
        ...ACC.map((x) => [x.time, new Date((x.time || 0) * 1000).toISOString(), x.login || '', x.ip || '', x.user_agent || ''])];
      downloadText('acessos-' + CONTEST + '-' + (dateInp.value || stamp()) + '.csv', toCsv(rows), 'text/csv');
    } }, '⬇ CSV');
    async function loadAccess() {
      aBody.innerHTML = ''; let r; try { r = await apiGet('/contest/admin/access-log?contest=' + enc(CONTEST) + '&day=' + enc(dateInp.value), G); } catch { aBody.append(el('div', { class: 'error-box' }, 'Falha.')); return; }
      const e2 = r.entries || []; ACC = e2;
      aBody.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, e2.length + ' acesso(s).'));
      if (!e2.length) { aBody.append(el('div', { class: 'muted' }, 'Sem acessos.')); return; }
      const tb = el('tbody');
      e2.forEach((x) => tb.append(el('tr', {}, el('td', { class: 'small' }, fmtDate(x.time)), el('td', {}, x.login || ''), el('td', { class: 'ip' }, x.ip || ''), el('td', { class: 'ua' }, x.user_agent || ''))));
      aBody.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' }, el('thead', {}, el('tr', {}, el('th', {}, 'Data/Hora'), el('th', {}, 'Login'), el('th', {}, 'IP'), el('th', {}, 'Navegador (UA)'))), tb)));
    }
    dateInp.addEventListener('change', loadAccess);
    aBox.append(el('div', { class: 'row', style: 'margin-bottom:.4rem' }, el('span', { class: 'small muted' }, 'Dia:'), dateInp, el('button', { class: 'btn ghost', onclick: () => loadAccess() }, '↻'), dlAcc), aBody);

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
    } catch (e) { panel.innerHTML = ''; panel.append(el('h2', {}, '📊 Situação'), el('div', { class: 'error-box' }, 'Falha: ' + (e.message || 'erro'))); return; }
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
      card('🖨️ impressões pend.', tPend.filter((t) => t.kind !== 'balloon').length, tOld > 600),
      card('🎈 balões pend.', tPend.filter((t) => t.kind === 'balloon').length, tOld > 600),
    ] : [];
    panel.innerHTML = '';
    panel.append(el('h2', {}, '📊 Situação da prova',
        el('a', { href: '/contest/score/reveal.html?c=' + enc(CONTEST), target: '_blank',
                  class: 'btn ghost', style: 'margin-left:.7rem;font-size:.85rem' },
          '🏆 Cerimônia de revelação'),
        // relatório final estático (tar.gz navegável offline: placar aberto, runs,
        // clarifications, estatísticas, tarefas do staff, infra) — GET admin/report
        el('button', { class: 'btn ghost', style: 'margin-left:.5rem;font-size:.85rem',
          onclick: async (ev) => {
            const b = ev.currentTarget, old = b.textContent;
            b.disabled = true; b.textContent = '⏳ gerando…';
            try { await downloadAuthed('/contest/admin/report?contest=' + enc(CONTEST), 'relatorio-' + CONTEST + '.tar.gz'); }
            finally { b.disabled = false; b.textContent = old; }
          } }, '📦 Relatório estático')),
      el('div', { class: 'dash-cards' },
        card('Logados', online),
        card('Juízes online', (j.online || 0) + '/' + (j.total || 0), (j.total || 0) > 0 && (j.online || 0) === 0),
        card('Juízes ocupados', j.busy || 0),
        card('Fila', (j.queue_depth || 0) + (j.assigned ? ' (+' + j.assigned + ' em juiz)' : ''), (j.queue_depth || 0) > 5),
        card('Pendentes', sub.pending || 0, (sub.pending || 0) > 0),
        card('Maior espera', fmtS(sub.max_wait_s), (sub.max_wait_s || 0) > 60),
        card('Resposta média', fmtS(resp.avg_s)),
        card('Resposta p95', fmtS(resp.p95_s), (resp.p95_s || 0) > 120),
        ...taskCards));

    // ⚖️ avaliação manual de veredicto (só aparece quando há fila/conflito)
    const rv = d.review || {};
    if ((rv.pending_total || 0) > 0 || (rv.being_evaluated || 0) > 0 || (rv.conflicts || 0) > 0) {
      const ev = rv.evaluators || [];
      const rtb = el('tbody');
      ev.forEach((e) => rtb.append(el('tr', {},
        el('td', {}, (e.problem_id || '').split('#').pop()),
        el('td', { class: 'small' }, e.computed_verdict || ''),
        el('td', {}, e.conflict ? el('b', { style: 'color:#c00' }, 'conflito') : (e.status || '')),
        el('td', { class: 'small' }, (e.claimants || []).map((c) => c.judge + ' (' + fmtS(c.elapsed_s) + ')').join(', ') || '—'))));
      panel.append(el('div', { style: 'margin-top:.7rem' }, el('h3', {}, '⚖️ Avaliação manual'),
        el('div', { class: 'dash-cards' },
          card('Não avaliadas', rv.not_evaluated || 0, (rv.not_evaluated || 0) > 0),
          card('Sendo avaliadas', rv.being_evaluated || 0),
          card('Conflitos', rv.conflicts || 0, (rv.conflicts || 0) > 0)),
        ev.length ? el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
          el('thead', {}, el('tr', {}, el('th', {}, 'Problema'), el('th', {}, 'Computado'), el('th', {}, 'Status'), el('th', {}, 'Avaliando (tempo)'))), rtb)) : el('p', { class: 'muted small' }, 'ninguém avaliando agora'),
        (rv.conflicts || 0) > 0 ? el('p', { class: 'small' }, '⚠ Resolva conflitos no ', el('a', { href: '/contest/chief/?c=' + enc(CONTEST) }, 'painel do juiz-chefe'), '.') : ''));
    }

    // ações sugeridas (palpáveis): só aparecem quando há algo a fazer
    const actions = [];
    if ((j.total || 0) === 0) actions.push('Nenhum juiz registrado — nada será julgado. Suba um agente de juiz.');
    else if ((j.online || 0) === 0) actions.push('Todos os juízes estão OFFLINE — submissões não serão julgadas. Verifique os agentes.');
    else if (offline > 0) actions.push(offline + ' juiz(es) offline — capacidade reduzida.');
    if (pool.length && poolOnline === 0)
      actions.push('Pool de juízes definido (' + pool.join(', ') + ') mas NENHUM host do pool está online — as submissões ficarão NA FILA até um voltar.');
    else if (pool.length && poolOnline < pool.length)
      actions.push('Pool de juízes com host offline (' + pool.filter((h) => !judges.some((x) => x.host === h && x.online)).join(', ') + ') — capacidade do pool reduzida.');
    if ((sub.pending || 0) > 0 && (j.online || 0) > 0 && (j.busy || 0) === 0 && (sub.max_wait_s || 0) > 60)
      actions.push('Há pendências esperando >1min mas nenhum juiz ocupado — possível problema de fila/roteamento.');
    if ((sub.max_wait_s || 0) > 180) actions.push('Submissão esperando ' + fmtS(sub.max_wait_s) + ' — investigar o juiz/linguagem.');
    if (tOld > 600) actions.push('Tarefa de impressão/balão pendente há ' + fmtS(tOld) + ' — veja a aba Tarefas do staff (você pode agir por lá).');
    alerts.forEach((a) => actions.push(a.login + ' logado de ' + [a.multi_ip && 'IPs', a.multi_ua && 'máquinas/navegadores'].filter(Boolean).join(' e ') + ' diferentes (possível conta compartilhada).'));
    if (actions.length) panel.append(el('div', { class: 'section', style: 'background:#fff7ec;border:1px solid #f3c08e' },
      el('b', {}, '⚠ Atenção'), el('ul', { style: 'margin:.3rem 0 0; padding-left:1.2rem' }, ...actions.map((a) => el('li', {}, a)))));

    // saúde dos juízes (por host); ⭐ = host do pool do contest
    panel.append(el('h3', { style: 'margin:1rem 0 .3rem' }, '🖥️ Juízes (' + judges.length + ')' +
      (pool.length ? ' — pool: ' + pool.join(', ') : '')));
    if (!judges.length) panel.append(el('div', { class: 'flag-anom' }, 'Nenhum juiz registrado.'));
    else {
      const tb = el('tbody');
      judges.forEach((x) => tb.append(el('tr', {},
        el('td', {}, el('span', { class: x.online ? '' : 'flag-anom', title: pool.includes(x.host) ? 'no pool do contest' : '' },
          (pool.includes(x.host) ? '⭐ ' : '') + (x.online ? '🟢 ' : '🔴 ') + x.host)),
        el('td', { class: 'small' }, x.state || '—'),
        el('td', { class: 'small' + (x.online ? '' : ' flag-anom') }, x.online ? 'online' : ('offline há ' + fmtS(x.age_s))),
        el('td', { class: 'small' }, String(x.problems_count || 0) + ' probs'),
        el('td', { class: 'small ua' }, (x.langs || []).join(' ')))));
      panel.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, 'Juiz'), el('th', {}, 'Estado'), el('th', {}, 'Visto'), el('th', {}, 'Cache'), el('th', {}, 'Linguagens'))), tb)));
    }

    // pendentes (ação: quem está esperando, há quanto tempo)
    const pend = sub.pending_list || [];
    panel.append(el('h3', { style: 'margin:1rem 0 .3rem' }, '⏳ Pendentes (' + pend.length + ')'));
    if (!pend.length) panel.append(el('div', { class: 'muted' }, 'Nenhuma submissão aguardando o juiz.'));
    else {
      const tb = el('tbody');
      pend.forEach((p) => tb.append(el('tr', {}, el('td', {}, p.login), el('td', {}, p.problem),
        el('td', { class: 'small' }, fmtClock(p.submitted_at)),
        el('td', { class: p.waiting_s > 120 ? 'flag-anom' : (p.waiting_s > 30 ? 'flag-warn' : '') }, fmtS(p.waiting_s)))));
      panel.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, 'Login'), el('th', {}, 'Prob'), el('th', {}, 'Enviado'), el('th', {}, 'Esperando'))), tb)));
    }

    // atividade por problema
    const pp = (sub.per_problem || []).filter((x) => x.submits > 0);
    if (pp.length) {
      panel.append(el('h3', { style: 'margin:1rem 0 .3rem' }, '📚 Por problema'));
      const tb = el('tbody');
      pp.forEach((x) => tb.append(el('tr', {}, el('td', {}, el('b', {}, x.problem)),
        el('td', {}, String(x.submits)), el('td', { class: x.pending ? 'flag-anom' : '' }, String(x.pending)), el('td', {}, String(x.accepted)))));
      panel.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, 'Prob'), el('th', {}, 'Subs'), el('th', {}, 'Pend'), el('th', {}, 'AC'))), tb)));
    }

    // submissões recentes (feed palpável)
    const recent = sub.recent || [];
    if (recent.length) {
      panel.append(el('h3', { style: 'margin:1rem 0 .3rem' }, '🧾 Submissões recentes'));
      const tb = el('tbody');
      recent.forEach((x) => tb.append(el('tr', {}, el('td', { class: 'small' }, fmtClock(x.at)),
        el('td', {}, x.login), el('td', {}, x.problem),
        el('td', {}, el('span', { class: vClass(x.verdict) }, x.verdict || '—')),
        el('td', { class: 'small' }, x.response_s != null ? fmtS(x.response_s) : (x.pending ? '⏳' : '—')))));
      panel.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, 'Hora'), el('th', {}, 'Login'), el('th', {}, 'Prob'), el('th', {}, 'Veredicto'), el('th', {}, 'Resposta'))), tb)));
    }

    // timeline (submissões/min + espera média), escala correta sobre as barras visíveis
    const tl = sub.timeline || [];
    if (tl.length) {
      const maxS = Math.max(1, ...tl.map((b) => b.submits || 0));
      const maxW = Math.max(1, ...tl.map((b) => b.avg_wait_s || 0));
      panel.append(el('h3', { style: 'margin:1rem 0 .3rem' }, '📈 Atividade (submissões/min e espera média)'));
      const rows = tl.map((b) => {
        const peak = (b.avg_wait_s || 0) >= Math.max(30, maxW * 0.7) && (b.submits || 0) >= Math.max(2, maxS * 0.5);
        return el('div', { class: 'spark-row' + (peak ? ' peak' : '') },
          el('span', { class: 'spark-t small' }, fmtClock(b.t).slice(0, 5)),
          el('span', { class: 'spark-bar', style: 'width:' + Math.round(100 * (b.submits || 0) / maxS) + '%' }),
          el('span', { class: 'small muted' }, (b.submits || 0) + ' sub · espera ~' + fmtS(b.avg_wait_s) + (peak ? ' ⬅ pico' : '')));
      });
      panel.append(el('div', { class: 'spark' }, ...rows),
        el('div', { class: 'small muted', style: 'margin-top:.2rem' }, 'Barra ∝ submissões no minuto (máx visível = ' + maxS + ').'));
    }

    panel.append(el('div', { class: 'small muted', style: 'margin-top:.6rem' },
      'Janela: últimas ' + (d.window || 0) + ' submissões · atualizado ' + fmtClock(d.now) + ' · auto-refresh 12s'));
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
  const KIND = { admin: '🛠️ admin', login: '🔑 login', submit: '📤 submissão', verdict: '⚖️ veredicto' };
  async function load() {
    panel.innerHTML = ''; panel.append(el('h2', {}, '🧾 Auditoria do contest'));
    const fUser = el('input', { type: 'search', placeholder: 'usuário…', style: 'width:140px' });
    const fAction = el('input', { type: 'search', placeholder: 'ação/veredicto…', style: 'width:170px' });
    const fSince = el('input', { type: 'date' });
    const body = el('div', {});
    let lastEvents = [];
    const dl = el('button', { class: 'btn ghost', title: 'Baixar (CSV) para auditoria externa', onclick: () => {
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
      catch (e) { body.append(el('div', { class: 'error-box' }, 'Falha: ' + (e.message || 'erro'))); return; }
      const ev = r.events || []; lastEvents = ev;
      body.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, ev.length + ' evento(s).'));
      if (!ev.length) { body.append(el('div', { class: 'muted' }, 'Nada encontrado.')); return; }
      const tb = el('tbody');
      ev.forEach((x) => tb.append(el('tr', { class: 'audit-' + x.kind },
        el('td', { class: 'small' }, fmtDate(x.time)),
        el('td', { class: 'small' }, KIND[x.kind] || x.kind),
        el('td', {}, x.who || ''),
        el('td', {}, x.action || ''),
        el('td', { class: 'small', style: 'font-family:var(--mono)' }, x.details || ''))));
      body.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, 'Quando'), el('th', {}, 'Tipo'), el('th', {}, 'Quem'), el('th', {}, 'Ação'), el('th', {}, 'Detalhes'))), tb)));
    }
    [fUser, fAction, fSince].forEach((i) => i.addEventListener('change', run));
    panel.append(el('div', { class: 'row', style: 'margin-bottom:.4rem' },
      el('span', { class: 'small muted' }, 'Filtros:'), fUser, fAction, el('span', { class: 'small muted' }, 'desde'), fSince,
      el('button', { class: 'btn ghost', onclick: run }, '↻'), dl), body);
    await run();
  }
  return { panel, load };
}

// ============ backups dos usuários (seção de "Usuários & sessões") ============
function backupsSection() {
  const panel = el('div', { class: 'section' });
  async function load() {
    panel.innerHTML = ''; panel.append(el('h2', {}, '💾 Backups dos usuários'));
    const fUser = el('input', { type: 'search', placeholder: 'usuário…', style: 'width:140px' });
    const fQ = el('input', { type: 'search', placeholder: 'nome do arquivo…', style: 'width:160px' });
    const body = el('div', {});
    async function run() {
      body.innerHTML = '';
      const qp = new URLSearchParams();
      if (fUser.value.trim()) qp.set('user', fUser.value.trim());
      if (fQ.value.trim()) qp.set('q', fQ.value.trim());
      let r;
      try { r = await apiGet('/contest/admin/backups?contest=' + enc(CONTEST) + (qp.toString() ? '&' + qp.toString() : ''), G); }
      catch (e) { body.append(el('div', { class: 'error-box' }, 'Falha: ' + (e.message || 'erro'))); return; }
      const users = r.users || [];
      if (users.length) {
        const ub = el('div', { class: 'row', style: 'flex-wrap:wrap; gap:.5rem; margin:.3rem 0 .6rem' });
        users.forEach((u) => ub.append(el('span', { class: 'dash-card', style: 'min-width:0; padding:.35rem .6rem' },
          el('b', {}, u.login), ' ', el('span', { class: 'small muted' }, u.count + ' arq · ' + Math.max(1, Math.round((u.bytes || 0) / 1024)) + ' KB'), ' ',
          el('a', { href: '#', class: 'small', title: 'Baixar zip com todos os arquivos deste usuário',
            onclick: (e) => { e.preventDefault(); downloadAuthed('/contest/admin/backup-zip?contest=' + enc(CONTEST) + '&login=' + enc(u.login), 'backups-' + u.login + '.zip'); } }, '⬇ ZIP'))));
        body.append(el('div', { style: 'margin-bottom:.3rem' }, el('b', {}, 'Por usuário: '), ub));
      }
      const items = r.backups || [];
      body.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, items.length + ' arquivo(s).'));
      if (!items.length) { body.append(el('div', { class: 'muted' }, 'Nada encontrado.')); return; }
      const tb = el('tbody');
      items.forEach((b) => tb.append(el('tr', {},
        el('td', {}, b.login), el('td', {}, b.name),
        el('td', { class: 'small' }, Math.max(1, Math.round((b.size || 0) / 1024)) + ' KB'),
        el('td', { class: 'small' }, fmtDate(b.time)),
        el('td', {}, el('a', { href: '#', onclick: (e) => { e.preventDefault(); downloadAuthed('/contest/backup-file?contest=' + enc(CONTEST) + '&login=' + enc(b.login) + '&id=' + enc(b.id), b.name); } }, '⬇ baixar')))));
      body.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, 'Usuário'), el('th', {}, 'Arquivo'), el('th', {}, 'Tam.'), el('th', {}, 'Enviado'), el('th', {}, ''))), tb)));
    }
    [fUser, fQ].forEach((i) => i.addEventListener('change', run));
    panel.append(el('div', { class: 'row', style: 'margin-bottom:.4rem' }, el('span', { class: 'small muted' }, 'Filtros:'), fUser, fQ, el('button', { class: 'btn ghost', onclick: run }, '↻')), body);
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
    panel.append(el('h2', {}, '⚖️ Tarefas do judge'),
      el('p', { class: 'muted small' },
        'Fila da correção manual: quem pegou, votos e idade de cada submissão segurada. ',
        '"Decidir/Resolver" libera o veredicto AO ALUNO na hora (override auditado); o fluxo normal de 2 votos fica na ',
        el('a', { href: '/contest/judge/?c=' + enc(CONTEST) }, 'área de avaliação'),
        '. O modo liga/desliga em Configurações; o juiz-chefe tem a mesma fila no ',
        el('a', { href: '/contest/chief/?c=' + enc(CONTEST) }, 'painel do juiz-chefe'), '.'),
      board.el,
      el('h3', { style: 'margin:1.2rem 0 .3rem' }, '⚙️ Configuração do veredicto manual'),
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
    panel.innerHTML = ''; panel.append(el('h2', {}, '✅ Pré-prova'));
    let d; try { d = await apiGet('/contest/admin/preflight?contest=' + enc(CONTEST), G); }
    catch (e) { panel.append(el('div', { class: 'error-box' }, 'Falha: ' + (e.message || 'erro'))); return; }
    const s = d.summary || {};
    panel.append(el('p', { class: s.fail ? 'error-box' : 'muted' },
      s.fail ? `🔴 ${s.fail} item(ns) BLOQUEIAM a prova — resolva antes de começar.`
        : s.warn ? `🟡 ${s.warn} aviso(s); nada bloqueia.` : '🟢 Tudo pronto.'));
    const ul = el('div', {});
    (d.checks || []).forEach((c) => ul.append(
      el('div', { style: 'display:flex;gap:.5rem;align-items:baseline;padding:.3rem 0;border-bottom:1px solid #eef2f7' },
        el('span', {}, ICON[c.level] || '•'),
        el('b', { style: 'min-width:16rem' }, c.label),
        el('span', { class: 'muted small' }, c.detail || ''))));
    panel.append(ul, el('div', { class: 'row', style: 'margin-top:.6rem' },
      el('button', { class: 'btn', onclick: load }, '↻ Rodar de novo')));
  }
  return { panel, load };
}

// ============ framework de abas ============
const TABS = [
  { id: 'dash', label: '📊 Situação', make: dashTab },
  { id: 'preflight', label: '✅ Pré-prova', make: preflightTab },
  { id: 'settings', label: '⚙️ Configurações', make: settingsTab },
  { id: 'problems', label: '📚 Problemas', make: problemsTab },
  { id: 'teams', label: '👥 Times', make: () => makeTeamsTab(CONTEST) },
  { id: 'appearance', label: '🎨 Aparência', make: appearanceTab },
  { id: 'users', label: '👥 Usuários & sessões', make: usersTab },
  { id: 'tasks', label: '🖨️ Tarefas do staff', make: () => makeTasksTab(CONTEST) },
  { id: 'verdict', label: '⚖️ Tarefas do judge', make: verdictTab },
  { id: 'audit', label: '🧾 Auditoria', make: auditTab },
];

async function boot() {
  if (!CONTEST) { app.innerHTML = '<div class="error-box">Contest não informado.</div>'; return; }
  const { st } = await initContestShell(CONTEST);
  if (!st || !st.logged_in || !st.is_admin) {
    app.innerHTML = '';
    app.append(el('div', { class: 'section' }, el('h2', {}, '🔒 Acesso restrito'),
      el('a', { class: 'btn', href: '/contest/login/?c=' + enc(CONTEST) }, 'Login do contest')));
    return;
  }
  app.innerHTML = '';
  const tabbar = el('div', { class: 'tabbar' }), wrap = el('div', {});
  app.append(tabbar, wrap);
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
