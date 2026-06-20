// contest/admin/admin.js — HUB de administração do contest (.admin) com sub-abas:
// Configurações, Problemas, Aparência/placar, Usuários, Log & sessões. Tudo auditado.
import { apiGet, apiPost } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { initContestShell } from '/shared/contest-shell.js';
import { makeColorsEditor, makeTeamsEditor, makeRegionsEditor, makeBasicEditor, toLocalDT, dtToEpoch } from '/shared/contest-config/index.js';

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

// ============ Configurações ============
function settingsTab() {
  const panel = el('div', { class: 'section' });
  async function load() {
    panel.innerHTML = ''; panel.append(el('h2', {}, '⚙️ Configurações'));
    let s; try { s = await apiGet('/contest/admin/settings?contest=' + enc(CONTEST), G); }
    catch (e) { panel.append(el('div', { class: 'error-box' }, 'Falha: ' + (e.message || 'erro'))); return; }
    const name = el('input', { value: s.name || '' });
    const start = el('input', { type: 'datetime-local', value: s.start ? toLocalDT(s.start) : '' });
    const end = el('input', { type: 'datetime-local', value: s.end ? toLocalDT(s.end) : '' });
    const loginStart = el('input', { type: 'datetime-local', value: s.login_start ? toLocalDT(s.login_start) : '' });
    const freeze = el('input', { type: 'datetime-local', value: s.freeze ? toLocalDT(s.freeze) : '' });
    const locale = el('select', {}, el('option', { value: 'pt' }, 'Português'), el('option', { value: 'en' }, 'English')); locale.value = s.locale || 'pt';
    const loginEnabled = mkBool(s.login_enabled !== false), showCode = mkBool(s.show_code), showLog = mkBool(s.show_log !== false),
      showEditor = mkBool(s.show_editor !== false), allowLate = mkBool(s.allow_late), scoreAnon = mkBool(s.score_anon);
    const ua = el('input', { value: s.login_ua_substring || '', placeholder: 'substring do UA (vazio = sem gate)' });
    const msg = el('div', { class: 'small' });
    const save = el('button', { class: 'btn' }, 'Salvar configurações');
    save.addEventListener('click', async () => {
      save.disabled = true; msg.className = 'small'; msg.textContent = 'Salvando…';
      const p = { name: name.value.trim() || undefined,
        ...(start.value ? { start: dtToEpoch(start.value) } : {}), ...(end.value ? { end: dtToEpoch(end.value) } : {}),
        ...(loginStart.value ? { login_start: dtToEpoch(loginStart.value) } : {}), ...(freeze.value ? { freeze: dtToEpoch(freeze.value) } : {}),
        locale: locale.value, login_enabled: loginEnabled.checked, show_code: showCode.checked, show_log: showLog.checked,
        show_editor: showEditor.checked, allow_late: allowLate.checked, score_anon: scoreAnon.checked, login_ua_substring: ua.value };
      try { await apiPost('/contest/admin/settings?contest=' + enc(CONTEST), p, G); msg.className = 'small'; msg.textContent = '✓ salvo'; save.disabled = false; }
      catch (e) { save.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || 'falha'; }
    });
    panel.append(field('Nome', name),
      el('div', { class: 'grid2' }, field('Início', start), field('Fim', end)),
      el('div', { class: 'grid2' }, field('Abertura do login (tela de espera)', loginStart), field('Freeze do placar', freeze)),
      field('Idioma', locale),
      chk('Login habilitado', loginEnabled),
      chk('Permitir auto-cadastro de novos usuários (late users)', allowLate),
      chk('Mostrar o código das submissões (a todos)', showCode),
      chk('Usuário pode ver o log de julgamento', showLog),
      chk('Editor de código no browser disponível', showEditor),
      chk('Placar anônimo (esconde desempenho individual)', scoreAnon),
      field('Gate de login por substring de UA (só não-privilegiados)', ua),
      el('div', { class: 'row' }, save, msg));
  }
  return { panel, load };
}

// ============ Problemas ============
function problemsTab() {
  const panel = el('div', { class: 'section' }, el('h2', {}, '📚 Problemas'));
  const list = el('div', {});
  const src = el('input', { value: 'cdmoj', style: 'width:90px' }), pid = el('input', { placeholder: 'problem_id' }),
    nm = el('input', { placeholder: 'nome' }), bid = el('input', { placeholder: 'ou bank_id (#)' }), addMsg = el('div', { class: 'small' });
  async function act(p) { try { await apiPost('/contest/admin/problems?contest=' + enc(CONTEST), p, G); loadList(); } catch (e) { alert(e.message || 'falha'); } }
  const add = el('button', { class: 'btn ghost', onclick: async () => {
    const prob = bid.value.trim() ? { bank_id: bid.value.trim(), name: nm.value.trim() || undefined } : { source: src.value.trim() || 'cdmoj', problem_id: pid.value.trim(), name: nm.value.trim() || undefined };
    if (!prob.bank_id && !prob.problem_id) { pid.focus(); return; }
    addMsg.className = 'small'; addMsg.textContent = '…';
    try { await apiPost('/contest/admin/problems?contest=' + enc(CONTEST), { action: 'add', problem: prob }, G); pid.value = nm.value = bid.value = ''; addMsg.textContent = ''; loadList(); }
    catch (e) { addMsg.className = 'small error-box'; addMsg.textContent = e.message || 'falha'; }
  } }, '+ adicionar');
  async function loadList() {
    list.innerHTML = ''; let r;
    try { r = await apiGet('/contest/admin/problems?contest=' + enc(CONTEST), G); } catch { list.append(el('div', { class: 'error-box' }, 'Falha.')); return; }
    const ps = r.problems || [];
    if (!ps.length) { list.append(el('div', { class: 'muted' }, 'Sem problemas.')); return; }
    const letters = ps.map((p) => p.letter), tb = el('tbody');
    ps.forEach((p, i) => {
      const nameInp = el('input', { value: p.name || '', style: 'width:100%' });
      tb.append(el('tr', {}, el('td', {}, el('b', {}, p.letter)), el('td', {}, nameInp),
        el('td', { class: 'small', style: 'font-family:var(--mono)' }, (p.source || 'cdmoj') + '/' + p.problem_id),
        el('td', {}, el('div', { class: 'row-actions' },
          el('button', { class: 'btn ghost', title: 'renomear', onclick: () => act({ action: 'rename', letter: p.letter, name: nameInp.value }) }, '✓'),
          el('button', { class: 'btn ghost', onclick: () => { if (i > 0) { const o = letters.slice(); [o[i - 1], o[i]] = [o[i], o[i - 1]]; act({ action: 'reorder', order: o }); } } }, '↑'),
          el('button', { class: 'btn ghost', onclick: () => { if (i < ps.length - 1) { const o = letters.slice(); [o[i + 1], o[i]] = [o[i], o[i + 1]]; act({ action: 'reorder', order: o }); } } }, '↓'),
          el('button', { class: 'btn danger', onclick: () => { if (confirm('Remover ' + p.letter + '?')) act({ action: 'remove', letter: p.letter }); } }, '✕')))));
    });
    list.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, '#'), el('th', {}, 'Nome'), el('th', {}, 'Problema'), el('th', {}, 'Ações'))), tb)));
  }
  async function load() { panel.append(list, el('h3', { style: 'margin:1rem 0 .3rem' }, 'Adicionar'),
    el('div', { class: 'row' }, src, pid, nm, el('span', { class: 'small muted' }, 'ou'), bid, add), addMsg); await loadList(); }
  return { panel, load };
}

// ============ Aparência / placar ============
function appearanceTab() {
  const panel = el('div', { class: 'section' });
  async function load() {
    panel.innerHTML = ''; panel.append(el('h2', {}, '🎨 Aparência e placar'));
    let cfg; try { cfg = await apiGet('/contest/admin/config?contest=' + enc(CONTEST), G); } catch (e) { panel.append(el('div', { class: 'error-box' }, 'Falha: ' + (e.message || 'erro'))); return; }
    const colorsEd = makeColorsEditor({ letters: cfg.letters || [], initial: cfg.colors || {} });
    const regionsEd = makeRegionsEditor({ initial: cfg.regions || [] });
    const basicEd = makeBasicEditor({ initial: cfg.basic || {} });
    const teamsEd = await makeTeamsEditor({ initial: cfg.teams_meta || [] });
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

// ============ Usuários ============
function usersTab() {
  const panel = el('div', { class: 'section' }, el('h2', {}, '👥 Usuários'));
  const list = el('div', {});
  async function call(path, body) { return apiPost('/contest/admin/' + path + '?contest=' + enc(CONTEST), body, G); }
  async function loadList() {
    list.innerHTML = ''; let r;
    try { r = await apiGet('/contest/admin/users?contest=' + enc(CONTEST), G); } catch { list.append(el('div', { class: 'error-box' }, 'Falha.')); return; }
    if (r.shared) list.append(el('div', { class: 'small muted', style: 'margin-bottom:.4rem' }, 'Usuários compartilhados de "' + r.shared + '" — só o admin é próprio deste contest.'));
    const tb = el('tbody');
    (r.users || []).forEach((u) => {
      const acts = el('div', { class: 'row-actions' });
      acts.append(el('button', { class: 'btn ghost', title: 'encerrar sessões', onclick: async () => { try { await call('logout-user', { login: u.login }); } catch (e) { alert(e.message); } } }, 'deslogar'));
      if (!u.admin && !u.disabled) acts.append(el('button', { class: 'btn ghost', onclick: async () => { if (!confirm('Desabilitar ' + u.login + '?')) return; try { await call('user-disable', { login: u.login }); loadList(); } catch (e) { alert(e.message); } } }, 'desabilitar'));
      acts.append(el('button', { class: 'btn danger', onclick: async () => { if (!confirm('Remover ' + u.login + '?')) return; try { await call('user-remove', { login: u.login }); loadList(); } catch (e) { alert(e.message); } } }, 'remover'));
      tb.append(el('tr', {},
        el('td', {}, u.login, u.admin ? el('span', { class: 'small muted' }, ' (admin)') : '', u.disabled ? el('span', { class: 'flag-anom small' }, ' (desabilitado)') : ''),
        el('td', {}, u.fullname || ''), el('td', { class: 'small' }, u.email || ''), el('td', {}, acts)));
    });
    list.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, 'Login'), el('th', {}, 'Nome'), el('th', {}, 'Email'), el('th', {}, 'Ações'))), tb)));
  }
  async function load() {
    panel.append(list);
    // add/reset
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
      el('h3', { style: 'margin:1rem 0 .3rem' }, '🔑 Troca de senha geral (prova)'),
      el('p', { class: 'muted small' }, 'Define uma senha única para todos os não-privilegiados (após os alunos logarem).'),
      el('div', { class: 'row' }, bpw, el('label', { class: 'small' }, binc, ' incluir desabilitados'), bulk), bmsg);
    await loadList();
  }
  return { panel, load };
}

// ============ Log & sessões ============
function logTab() {
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
    sBox.append(el('div', { class: 'row', style: 'margin:.3rem 0' }, uaFilter, el('button', { class: 'btn ghost', onclick: () => loadSessions() }, '↻'), mismatchBtn), sBody);

    // log de acessos
    const aBox = el('div', { class: 'section' }, el('h2', {}, '📝 Log de acessos'));
    const dateInp = el('input', { type: 'date', value: todayStr() });
    const aBody = el('div', {});
    async function loadAccess() {
      aBody.innerHTML = ''; let r; try { r = await apiGet('/contest/admin/access-log?contest=' + enc(CONTEST) + '&day=' + enc(dateInp.value), G); } catch { aBody.append(el('div', { class: 'error-box' }, 'Falha.')); return; }
      const e2 = r.entries || [];
      aBody.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, e2.length + ' acesso(s).'));
      if (!e2.length) { aBody.append(el('div', { class: 'muted' }, 'Sem acessos.')); return; }
      const tb = el('tbody');
      e2.forEach((x) => tb.append(el('tr', {}, el('td', { class: 'small' }, fmtDate(x.time)), el('td', {}, x.login || ''), el('td', { class: 'ip' }, x.ip || ''), el('td', { class: 'ua' }, x.user_agent || ''))));
      aBody.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' }, el('thead', {}, el('tr', {}, el('th', {}, 'Data/Hora'), el('th', {}, 'Login'), el('th', {}, 'IP'), el('th', {}, 'Navegador (UA)'))), tb)));
    }
    dateInp.addEventListener('change', loadAccess);
    aBox.append(el('div', { class: 'row', style: 'margin-bottom:.4rem' }, el('span', { class: 'small muted' }, 'Dia:'), dateInp, el('button', { class: 'btn ghost', onclick: () => loadAccess() }, '↻')), aBody);

    panel.append(sBox, aBox);
    await loadSessions(); await loadAccess();
  }
  return { panel, load };
}

// ============ framework de abas ============
const TABS = [
  { id: 'settings', label: '⚙️ Configurações', make: settingsTab },
  { id: 'problems', label: '📚 Problemas', make: problemsTab },
  { id: 'appearance', label: '🎨 Aparência', make: appearanceTab },
  { id: 'users', label: '👥 Usuários', make: usersTab },
  { id: 'log', label: '📋 Log & sessões', make: logTab },
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
  const want = (location.hash || '').replace('#', '');
  show(TABS.some((t) => t.id === want) ? want : 'settings');
}
boot();
