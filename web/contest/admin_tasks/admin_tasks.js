// contest/admin_tasks/admin_tasks.js — settings do contest (tempos/login/toggles) e
// gestão de problemas (add/remover/reordenar/renomear). Tudo auditado no servidor.
import { apiGet, apiPost } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { initContestShell } from '/shared/contest-shell.js';
import { toLocalDT, dtToEpoch } from '/shared/contest-config/util.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
const app = document.getElementById('app');
const enc = encodeURIComponent;
const G = { contest: CONTEST, auth: true };

function settingsSection(s) {
  const name = el('input', { value: s.name || '' });
  const start = el('input', { type: 'datetime-local', value: s.start ? toLocalDT(s.start) : '' });
  const end = el('input', { type: 'datetime-local', value: s.end ? toLocalDT(s.end) : '' });
  const loginStart = el('input', { type: 'datetime-local', value: s.login_start ? toLocalDT(s.login_start) : '' });
  const freeze = el('input', { type: 'datetime-local', value: s.freeze ? toLocalDT(s.freeze) : '' });
  const locale = el('select', {}, el('option', { value: 'pt' }, 'Português'), el('option', { value: 'en' }, 'English'));
  locale.value = s.locale || 'pt';
  const mk = (v) => { const c = el('input', { type: 'checkbox' }); c.checked = !!v; return c; };
  const loginEnabled = mk(s.login_enabled !== false), showCode = mk(s.show_code),
    showLog = mk(s.show_log !== false), showEditor = mk(s.show_editor !== false), allowLate = mk(s.allow_late);
  const ua = el('input', { value: s.login_ua_substring || '', placeholder: 'substring do UA (vazio = sem gate)' });
  const msg = el('div', { class: 'small' });
  const save = el('button', { class: 'btn' }, 'Salvar configurações');
  save.addEventListener('click', async () => {
    save.disabled = true; msg.className = 'small'; msg.textContent = 'Salvando…';
    const payload = {
      name: name.value.trim() || undefined,
      ...(start.value ? { start: dtToEpoch(start.value) } : {}), ...(end.value ? { end: dtToEpoch(end.value) } : {}),
      ...(loginStart.value ? { login_start: dtToEpoch(loginStart.value) } : {}), ...(freeze.value ? { freeze: dtToEpoch(freeze.value) } : {}),
      locale: locale.value, login_enabled: loginEnabled.checked, show_code: showCode.checked,
      show_log: showLog.checked, show_editor: showEditor.checked, allow_late: allowLate.checked,
      login_ua_substring: ua.value,
    };
    try { await apiPost('/contest/admin/settings?contest=' + enc(CONTEST), payload, G); msg.className = 'small'; msg.textContent = '✓ salvo'; save.disabled = false; }
    catch (e) { save.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || 'falha'; }
  });
  const field = (l, inp) => el('div', { class: 'field' }, el('label', {}, l), inp);
  const chk = (l, c) => el('div', { class: 'field' }, el('label', { style: 'font-weight:400' }, c, ' ' + l));
  return el('div', { class: 'section' }, el('h2', {}, '⚙️ Configurações do contest'),
    field('Nome', name),
    el('div', { class: 'grid2' }, field('Início', start), field('Fim', end)),
    el('div', { class: 'grid2' }, field('Abertura do login (tela de espera)', loginStart), field('Freeze do placar', freeze)),
    field('Idioma', locale),
    chk('Login habilitado', loginEnabled),
    chk('Permitir auto-cadastro de novos usuários (late users)', allowLate),
    chk('Mostrar o código das submissões (a todos)', showCode),
    chk('Usuário pode ver o log de julgamento', showLog),
    chk('Editor de código no browser disponível', showEditor),
    field('Gate de login por substring de UA (só não-privilegiados)', ua),
    el('div', { class: 'row' }, save, msg));
}

function problemsSection() {
  const box = el('div', { class: 'section' }, el('h2', {}, '📚 Problemas'));
  const list = el('div', {}, el('p', { class: 'muted small' }, 'carregando…'));
  const src = el('input', { value: 'cdmoj', style: 'width:90px' }), pid = el('input', { placeholder: 'problem_id (ex.: monitores/ola)' });
  const nm = el('input', { placeholder: 'nome' }), bid = el('input', { placeholder: 'ou bank_id (com #)' });
  const addMsg = el('div', { class: 'small' });
  const add = el('button', { class: 'btn ghost' }, '+ adicionar');
  async function act(payload) { try { await apiPost('/contest/admin/problems?contest=' + enc(CONTEST), payload, G); load(); } catch (e) { alert(e.message || 'falha'); } }
  add.addEventListener('click', async () => {
    const prob = bid.value.trim()
      ? { bank_id: bid.value.trim(), name: nm.value.trim() || undefined }
      : { source: src.value.trim() || 'cdmoj', problem_id: pid.value.trim(), name: nm.value.trim() || undefined };
    if (!prob.bank_id && !prob.problem_id) { pid.focus(); return; }
    addMsg.className = 'small'; addMsg.textContent = '…';
    try { await apiPost('/contest/admin/problems?contest=' + enc(CONTEST), { action: 'add', problem: prob }, G); pid.value = nm.value = bid.value = ''; addMsg.textContent = ''; load(); }
    catch (e) { addMsg.className = 'small error-box'; addMsg.textContent = e.message || 'falha'; }
  });
  async function load() {
    list.innerHTML = ''; let r;
    try { r = await apiGet('/contest/admin/problems?contest=' + enc(CONTEST), G); }
    catch { list.append(el('div', { class: 'error-box' }, 'Falha ao carregar problemas.')); return; }
    const ps = r.problems || [];
    if (!ps.length) { list.append(el('div', { class: 'muted' }, 'Sem problemas. Adicione abaixo.')); return; }
    const letters = ps.map((p) => p.letter);
    const tb = el('tbody');
    ps.forEach((p, i) => {
      const nameInp = el('input', { value: p.name || '', style: 'width:100%' });
      const renameBtn = el('button', { class: 'btn ghost', title: 'renomear', onclick: () => act({ action: 'rename', letter: p.letter, name: nameInp.value }) }, '✓');
      const up = el('button', { class: 'btn ghost', onclick: () => { if (i > 0) { const o = letters.slice(); [o[i - 1], o[i]] = [o[i], o[i - 1]]; act({ action: 'reorder', order: o }); } } }, '↑');
      const dn = el('button', { class: 'btn ghost', onclick: () => { if (i < ps.length - 1) { const o = letters.slice(); [o[i + 1], o[i]] = [o[i], o[i + 1]]; act({ action: 'reorder', order: o }); } } }, '↓');
      const rm = el('button', { class: 'btn danger', onclick: () => { if (confirm('Remover o problema ' + p.letter + '?')) act({ action: 'remove', letter: p.letter }); } }, '✕');
      tb.append(el('tr', {}, el('td', {}, el('b', {}, p.letter)), el('td', {}, nameInp),
        el('td', { class: 'small', style: 'font-family:var(--mono)' }, (p.source || 'cdmoj') + '/' + p.problem_id),
        el('td', {}, el('div', { class: 'row' }, renameBtn, up, dn, rm))));
    });
    list.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, '#'), el('th', {}, 'Nome'), el('th', {}, 'Problema'), el('th', {}, 'Ações'))), tb)));
  }
  load();
  box.append(list, el('h3', { style: 'margin:1rem 0 .3rem' }, 'Adicionar problema'),
    el('div', { class: 'row' }, src, pid, nm, el('span', { class: 'small muted' }, 'ou'), bid, add), addMsg);
  return box;
}

async function boot() {
  if (!CONTEST) { app.innerHTML = '<div class="error-box">Contest não informado.</div>'; return; }
  const { st } = await initContestShell(CONTEST);
  if (!st || !st.logged_in || !st.is_admin) {
    app.innerHTML = '';
    app.append(el('div', { class: 'section' }, el('h2', {}, '🔒 Acesso restrito'),
      el('a', { class: 'btn', href: '/contest/login/?c=' + enc(CONTEST) }, 'Login do contest')));
    return;
  }
  let s;
  try { s = await apiGet('/contest/admin/settings?contest=' + enc(CONTEST), G); }
  catch (e) { app.innerHTML = ''; app.append(el('div', { class: 'error-box' }, 'Falha: ' + (e.message || 'erro'))); return; }
  app.innerHTML = '';
  app.append(settingsSection(s), problemsSection());
}
boot();
