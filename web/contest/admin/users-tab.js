// contest/admin/users-tab.js — "Pessoas › Contas": criar/resetar/desabilitar/remover contas,
// carga em LOTE (colar ou .txt/.csv, com ou sem cabeçalho) e a troca de senha geral.
// É aqui que nascem as contas de PAPEL (sufixo .admin/.judge/.cjudge/.staff/.cstaff/.mon).
// As sessões e o log de acessos ficaram em Pessoas › Sessões (sessions-tab.js).
import { el } from '/shared/ui.js';
import { apiGet, apiPost } from '/shared/api.js';
import { parseUsers, parseRichCsv, downloadCsv } from '/shared/users-batch.js';
import { mkBool } from '/shared/admin-ui.js';
import { T } from '/shared/i18n.js';

const enc = encodeURIComponent;
const PRIV = /\.(admin|judge|cjudge|staff|cstaff|mon|animeitor)$/;

export function makeUsersTab(CONTEST) {
  const G = { contest: CONTEST, auth: true };
  const panel = el('div', { class: 'section' });
  const list = el('div', {});
  let USERS = [], built = false;
  const call = (path, body) => apiPost('/contest/admin/' + path + '?contest=' + enc(CONTEST), body, G);

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
    try { r = await apiGet('/contest/admin/users?contest=' + enc(CONTEST), G); }
    catch { list.innerHTML = ''; list.append(el('div', { class: 'error-box' }, T('Falha.', 'Failed.'))); return; }
    panel.querySelectorAll('.shared-note').forEach((n) => n.remove());
    if (r.shared) panel.insertBefore(el('div', { class: 'small muted shared-note', style: 'margin-bottom:.4rem' }, T('Usuários compartilhados de "', 'Users shared from "') + r.shared + T('" — só o admin é próprio deste contest.', '" — only the admin is specific to this contest.')), list);
    USERS = r.users || []; renderList();
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
    const renderPrev = () => {
      prev.innerHTML = ''; if (!staged.length) return;
      prev.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' },
        staged.length + T(' linha(s) prontas (senhas em branco são geradas no servidor).', ' line(s) ready (blank passwords are generated on the server).') +
        (richMode ? T(' Cabeçalho detectado — os campos de time/país/sede vão junto.', ' Header detected — the team/country/site fields go along.') : '')));
    };
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

  async function load() {
    if (built) { await loadList(); return; }
    built = true;
    panel.append(el('h2', {}, T('👥 Contas & senhas ', '👥 Accounts & passwords '),
      el('a', { class: 'btn ghost', style: 'font-size:.85rem; font-weight:400', target: '_blank',
        href: '/contest/badges/?c=' + enc(CONTEST) }, T('🏷️ Etiquetas de credenciais', '🏷️ Credential badges'))));
    panel.append(el('div', { class: 'row', style: 'margin:.3rem 0' }, el('span', { class: 'small muted' }, T('Filtrar:', 'Filter:')), fQ, fSel,
      el('button', { class: 'btn ghost', onclick: () => loadList() }, '↻')), list);
    // add/reset (individual)
    const li = el('input', { placeholder: 'login' }), pw = el('input', { placeholder: T('senha (gerada se vazio)', 'password (generated if empty)') }),
      fn = el('input', { placeholder: T('nome', 'name') }), em = el('input', { placeholder: T('email (opcional)', 'email (optional)') }), amsg = el('div', { class: 'small' });
    const add = el('button', { class: 'btn', onclick: async () => {
      if (!li.value.trim()) { li.focus(); return; }
      add.disabled = true; amsg.className = 'small'; amsg.textContent = T('Salvando…', 'Saving…');
      try {
        const r = await call('user-add', { login: li.value.trim(), password: pw.value.trim() || undefined, fullname: fn.value.trim() || undefined, email: em.value.trim() || undefined });
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
  return { panel, load };
}
