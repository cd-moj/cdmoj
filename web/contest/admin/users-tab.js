// contest/admin/users-tab.js — "Pessoas › Contas": criar/resetar/desabilitar/remover contas,
// carga em LOTE (colar ou .txt/.csv, com ou sem cabeçalho) e a troca de senha geral.
// É aqui que nascem as contas de PAPEL (sufixo .admin/.judge/.cjudge/.staff/.cstaff/.mon).
// As sessões e o log de acessos ficaram em Pessoas › Sessões (sessions-tab.js).
import { el } from '/shared/ui.js';
import { apiGet, apiPost } from '/shared/api.js';
import { parseUsers, parseRichCsv, downloadCsv } from '/shared/users-batch.js';
import { mkBool, PRIV_RE as PRIV } from '/shared/admin-ui.js';
import { T } from '/shared/i18n.js';
import { makeConvertCard } from './users-convert.js';

const enc = encodeURIComponent;

// Collator numérico: "aluno2" antes de "aluno10"; sensitivity base ignora caixa e acento
// ("Álvaro" junto de "alvaro").
const COLL = new Intl.Collator('pt', { numeric: true, sensitivity: 'base' });

// Ordena as contas (no lugar) por login/fullname/email. Vazio vai SEMPRE para o fim, nas duas
// direções: muita conta não tem email, e elas não podem tomar o topo quando se inverte a ordem.
// Teste: server/test/smoke-users-sort.gjs.sh.
export function sortUsers(items, key, dir) {
  return items.sort((a, b) => {
    const va = a[key] || '', vb = b[key] || '';
    if (!va && vb) return 1;
    if (va && !vb) return -1;
    return COLL.compare(va, vb) * dir;
  });
}

export function makeUsersTab(CONTEST) {
  const G = { contest: CONTEST, auth: true };
  const panel = el('div', { class: 'section' });
  const list = el('div', {});
  let USERS = [], built = false;
  const call = (path, body) => apiPost('/contest/admin/' + path + '?contest=' + enc(CONTEST), body, G);
  const conv = makeConvertCard(CONTEST, { onDone: () => loadList() });   // contest compartilhado (USERS_FROM)

  // filtros (sobrevivem ao re-render da lista) — essenciais em contest com 1000+ usuários
  const fQ = el('input', { type: 'search', placeholder: T('login / nome / email…', 'login / name / email…', 'login / nombre / email…'), style: 'min-width:200px' });
  const fSel = el('select', {}, el('option', { value: '' }, T('todos', 'all', 'todos')),
    el('option', { value: 'active' }, T('ativos', 'active', 'activos')), el('option', { value: 'disabled' }, T('desabilitados', 'disabled', 'deshabilitados')),
    el('option', { value: 'priv' }, T('privilegiados', 'privileged', 'privilegiados')));
  let showAll = false;
  // Ordenação por coluna: clique no cabeçalho alterna ▲/▼ (mesmo padrão da Gestão de Problemas).
  // key null = ordem do servidor, o comportamento de antes: nada muda para quem não clica.
  let SORT = { key: null, dir: 1 };
  function setSort(key) { if (SORT.key === key) SORT.dir *= -1; else SORT = { key, dir: 1 }; renderList(); }
  fQ.addEventListener('input', () => { showAll = false; renderList(); });
  fSel.addEventListener('change', () => { showAll = false; renderList(); });

  function userRow(u) {
    const acts = el('div', { class: 'row-actions' });
    acts.append(el('button', { class: 'btn ghost', title: T('encerrar sessões', 'end sessions', 'finalizar sesiones'), onclick: async () => { try { await call('logout-user', { login: u.login }); } catch (e) { alert(e.message); } } }, T('deslogar', 'log out', 'cerrar sesión')));
    // compartilhado desabilitado: {undo} apaga o bloqueio e ele volta a entrar com a senha do treino
    // TIME de inscrição desabilitado também reabilita assim (a marca `disabled`; a senha do time nunca foi a dele)
    if ((u.shared || u.is_team) && u.disabled) acts.append(el('button', { class: 'btn ghost', onclick: async () => { try { await call('user-disable', { login: u.login, undo: true }); loadList(); } catch (e) { alert(e.message); } } }, T('reabilitar', 're-enable', 'reactivar')));
    // conta de PAPEL (.judge/.staff/…): o servidor recusa desabilitar/desclassificar (403 privileged) — sem o botão
    const role = u.admin || PRIV.test(u.login || '');
    if (!role && !u.disabled) acts.append(el('button', { class: 'btn ghost', onclick: async () => { if (!confirm(T('Desabilitar ', 'Disable ', 'Deshabilitar ') + u.login + '?')) return; try { await call('user-disable', { login: u.login }); loadList(); } catch (e) { alert(e.message); } } }, T('desabilitar', 'disable', 'deshabilitar')));
    // desclassificar ≠ desabilitar: a conta continua existindo/logando, mas some do
    // placar E da estatística (flag .disqualified — mesma população nas duas telas)
    if (!role) acts.append(el('button', { class: 'btn ghost', onclick: async () => {
      const undo = !!u.disqualified;
      const msg = undo ? T('Reverter a desclassificação de ', 'Undo disqualification of ', '¿Revertir la descalificación de ')
                       : T('Desclassificar ', 'Disqualify ', '¿Descalificar ');
      if (!confirm(msg + u.login + (undo ? '?' : T('? (some do placar e da estatística)', '? (removed from scoreboard and statistics)', '? (eliminado del marcador y de las estadísticas)')))) return;
      try { await call('user-disqualify', { login: u.login, undo }); loadList(); } catch (e) { alert(e.message); }
    } }, u.disqualified ? T('reclassificar', 'requalify', 'reclasificar') : T('desclassificar', 'disqualify', 'descalificar')));
    acts.append(el('button', { class: 'btn danger', onclick: async () => { if (!confirm(T('Remover ', 'Remove ', 'Quitar ') + u.login + '?')) return; try { await call('user-remove', { login: u.login }); loadList(); } catch (e) { alert(e.message); } } }, T('remover', 'remove', 'quitar')));
    return el('tr', {},
      el('td', {}, u.login, u.admin ? el('span', { class: 'small muted' }, ' (admin)') : '',
        u.shared ? el('span', { class: 'small muted', title: T('entra com a conta do Treino Livre', 'logs in with the Free Training account', 'entra con la cuenta de Entrenamiento libre') }, T(' 🔗 treino', ' 🔗 training', ' 🔗 entrenamiento')) : '',
        u.disabled ? el('span', { class: 'flag-anom small' }, T(' (desabilitado)', ' (disabled)', ' (deshabilitado)')) : '',
        u.disqualified ? el('span', { class: 'flag-anom small', style: 'font-weight:600' }, T(' (desclassificado)', ' (disqualified)', ' (descalificado)')) : ''),
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
    // ordena ANTES do corte de CAP: senão "ordenar por nome" num contest com 1000+ contas ordenaria
    // só os 300 da tela, e o primeiro da ordem real ficaria escondido
    if (SORT.key) sortUsers(items, SORT.key, SORT.dir);
    list.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, items.length + T(' de ', ' of ', ' de ') + USERS.length + T(' usuário(s).', ' user(s).', ' usuario(s).')));
    if (!items.length) { list.append(el('div', { class: 'muted' }, T('Nenhum com esses filtros.', 'None with these filters.', 'Ninguno con estos filtros.'))); return; }
    const CAP = 300, shown = showAll ? items : items.slice(0, CAP);
    const tb = el('tbody'); shown.forEach((u) => tb.append(userRow(u)));
    const arrow = (k) => SORT.key === k ? (SORT.dir > 0 ? ' ▲' : ' ▼') : '';
    const th = (label, k) => el('th', { class: 'sortable', title: T('ordenar', 'sort', 'ordenar'), onclick: () => setSort(k) }, label + arrow(k));
    list.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, th('Login', 'login'), th(T('Nome', 'Name', 'Nombre'), 'fullname'), th('Email', 'email'), el('th', {}, T('Ações', 'Actions', 'Acciones')))), tb)));
    if (!showAll && items.length > CAP) list.append(el('div', { style: 'margin:.4rem 0' },
      el('button', { class: 'btn ghost', onclick: () => { showAll = true; renderList(); } }, T('mostrar todos (', 'show all (', 'mostrar todos (') + items.length + ')'),
      el('span', { class: 'small muted' }, T(' — exibindo os ' + CAP + ' primeiros', ' — showing the first ' + CAP, ' — mostrando los primeros ' + CAP))));
  }
  async function loadList() {
    let r;
    try { r = await apiGet('/contest/admin/users?contest=' + enc(CONTEST), G); }
    catch { list.innerHTML = ''; list.append(el('div', { class: 'error-box' }, T('Falha.', 'Failed.', 'Falló.'))); return; }
    conv.show(r.shared || '');
    USERS = r.users || []; renderList();
  }

  // ---- carga em lote (mesma colagem/arquivo da criação; a qualquer momento) ----
  function makeBatchUsers() {
    let staged = [];       // [{login,password,fullname,email, team_name?,country?,region?,…}] da prévia
    let richMode = false;  // true = veio de CSV com cabeçalho (campos de time inclusos)
    const ta = el('textarea', { rows: '5', placeholder: T('Cole aqui (ou envie um arquivo). Formatos por linha:\n  login:senha:nome:email\n  login,nome,email\n  Nome Completo   (login e senha gerados)\nOu CSV COM CABEÇALHO (ordem livre; nome = nome do time; carga única c/ país+sede):\n  login,senha,nome,pais,sede,univ,univ_nome', 'Paste here (or upload a file). Per-line formats:\n  login:senha:nome:email\n  login,nome,email\n  Full Name   (login and password generated)\nOr CSV WITH HEADER (any order; nome = team name; single load w/ country+site):\n  login,senha,nome,pais,sede,univ,univ_nome', 'Pega aquí (o sube un archivo). Formatos por línea:\n  login:senha:nome:email\n  login,nome,email\n  Nombre Completo   (login y contraseña generados)\nO CSV CON ENCABEZADO (orden libre; nome = nombre del equipo; carga única con país+sede):\n  login,senha,nome,pais,sede,univ,univ_nome'), style: 'width:100%' });
    const fileInp = el('input', { type: 'file', accept: '.txt,.csv,text/plain,text/csv', style: 'display:none' });
    fileInp.addEventListener('change', () => { const f = fileInp.files[0]; if (!f) return; const rd = new FileReader(); rd.onload = () => { ta.value = ta.value ? (ta.value.replace(/\s*$/, '') + '\n' + rd.result) : rd.result; }; rd.readAsText(f); fileInp.value = ''; });
    const onExisting = el('select', {}, el('option', { value: 'skip' }, T('pular os que já existem', 'skip existing ones', 'omitir los existentes')), el('option', { value: 'update' }, T('atualizar senha dos existentes', 'update password of existing ones', 'actualizar contraseña de los existentes')));
    const prev = el('div', {}); const msg = el('div', { class: 'small' });
    const parse = (txt) => { const rich = parseRichCsv(txt); richMode = !!rich; return rich || parseUsers(txt); };
    const renderPrev = () => {
      prev.innerHTML = ''; if (!staged.length) return;
      prev.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' },
        staged.length + T(' linha(s) prontas (senhas em branco são geradas no servidor).', ' line(s) ready (blank passwords are generated on the server).', ' línea(s) lista(s) (las contraseñas en blanco se generan en el servidor).') +
        (richMode ? T(' Cabeçalho detectado — os campos de time/país/sede vão junto.', ' Header detected — the team/country/site fields go along.', ' Encabezado detectado — los campos de equipo/país/sede se incluyen.') : '')));
    };
    const proc = el('button', { class: 'btn ghost', onclick: () => { staged = parse(ta.value); msg.textContent = ''; renderPrev(); } }, T('Processar', 'Process', 'Procesar'));
    const send = el('button', { class: 'btn', onclick: async () => {
      if (!staged.length) { staged = parse(ta.value); renderPrev(); }
      const users = staged.filter((u) => u.login || u.fullname).map((u) => ({
        login: u.login || undefined, password: u.password || undefined,
        fullname: u.fullname || undefined, email: u.email || undefined,
        country: u.country || undefined, region: u.region || undefined,
        univ_short: u.univ_short || undefined, univ_full: u.univ_full || undefined,
      }));
      if (!users.length) { msg.className = 'small error-box'; msg.textContent = T('Nada para enviar.', 'Nothing to send.', 'Nada para enviar.'); return; }
      send.disabled = true; msg.className = 'small'; msg.textContent = T('Enviando ', 'Sending ', 'Enviando ') + users.length + '…';
      try {
        const r = await call('users-bulk', { users, on_existing: onExisting.value });
        const c = r.counts || {};
        msg.className = 'small'; msg.innerHTML = '';
        msg.append('✓ ' + (c.created || 0) + T(' criado(s), ', ' created, ', ' creado(s), ') + (c.updated || 0) + T(' atualizado(s), ', ' updated, ', ' actualizado(s), ') + (c.skipped || 0) + T(' pulado(s). ', ' skipped. ', ' omitido(s). '));
        const creds = (r.created || []).concat(r.updated || []);
        if (creds.length) msg.append(el('button', { class: 'btn ghost', onclick: () => downloadCsv(CONTEST + '-credenciais.csv', creds) }, T('⬇ baixar credenciais (CSV)', '⬇ download credentials (CSV)', '⬇ descargar credenciales (CSV)')));
        send.disabled = false; staged = []; ta.value = ''; renderPrev(); loadList();
      } catch (e) { send.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed', 'fallido'); }
    } }, T('Enviar lote', 'Send batch', 'Enviar lote'));
    return el('div', {},
      el('h3', { style: 'margin:1rem 0 .3rem' }, T('📥 Usuários em lote', '📥 Batch users', '📥 Usuarios en lote')),
      el('p', { class: 'muted small' }, T('Suba competidores a qualquer momento (ex.: contest criado só com contas administrativas). Colar ou enviar arquivo .txt/.csv.', 'Upload competitors at any time (e.g.: contest created with only administrative accounts). Paste or upload a .txt/.csv file.', 'Sube competidores en cualquier momento (ej.: competencia creada solo con cuentas administrativas). Pega o sube un archivo .txt/.csv.')),
      ta,
      el('div', { class: 'row', style: 'margin:.4rem 0' },
        el('button', { class: 'btn ghost', onclick: () => fileInp.click() }, T('📎 Enviar arquivo', '📎 Upload file', '📎 Subir archivo')), fileInp,
        proc, el('span', { class: 'small muted' }, T('existentes:', 'existing:', 'existentes:')), onExisting, send),
      prev, msg);
  }

  async function load() {
    if (built) { await loadList(); return; }
    built = true;
    panel.append(el('h2', {}, T('👥 Contas & senhas ', '👥 Accounts & passwords ', '👥 Cuentas y contraseñas '),
      el('a', { class: 'btn ghost', style: 'font-size:.85rem; font-weight:400', target: '_blank',
        href: '/contest/badges/?c=' + enc(CONTEST) }, T('🏷️ Etiquetas de credenciais', '🏷️ Credential badges', '🏷️ Etiquetas de credenciales'))), conv.el);
    panel.append(el('div', { class: 'row', style: 'margin:.3rem 0' }, el('span', { class: 'small muted' }, T('Filtrar:', 'Filter:', 'Filtrar:')), fQ, fSel,
      el('button', { class: 'btn ghost', onclick: () => loadList() }, '↻')), list);
    // add/reset (individual)
    const li = el('input', { placeholder: 'login' }), pw = el('input', { placeholder: T('senha (gerada se vazio)', 'password (generated if empty)', 'contraseña (generada si se deja vacía)') }),
      fn = el('input', { placeholder: T('nome', 'name', 'nombre') }), em = el('input', { placeholder: T('email (opcional)', 'email (optional)', 'email (opcional)') }), amsg = el('div', { class: 'small' });
    const add = el('button', { class: 'btn', onclick: async () => {
      if (!li.value.trim()) { li.focus(); return; }
      add.disabled = true; amsg.className = 'small'; amsg.textContent = T('Salvando…', 'Saving…', 'Guardando…');
      try {
        const r = await call('user-add', { login: li.value.trim(), password: pw.value.trim() || undefined, fullname: fn.value.trim() || undefined, email: em.value.trim() || undefined });
        amsg.className = 'small'; amsg.innerHTML = ''; amsg.append('✓ ' + r.user.login + T(' · senha: ', ' · password: ', ' · contraseña: '), el('span', { class: 'cred' }, r.user.password));
        add.disabled = false; li.value = pw.value = fn.value = em.value = ''; loadList();
      } catch (e) { add.disabled = false; amsg.className = 'small error-box'; amsg.textContent = e.message || T('falha', 'failed', 'fallido'); }
    } }, T('Adicionar / resetar / reabilitar', 'Add / reset / re-enable', 'Agregar / restablecer / reactivar'));
    // troca de senha geral
    const bpw = el('input', { placeholder: T('nova senha única', 'new single password', 'nueva contraseña única'), style: 'width:200px' }), binc = mkBool(false), bmsg = el('div', { class: 'small' });
    const bulk = el('button', { class: 'btn danger', onclick: async () => {
      if (!bpw.value.trim()) { bpw.focus(); return; }
      if (!confirm(T('Trocar a senha de TODOS os usuários não-privilegiados para esta senha?', 'Change the password of ALL non-privileged users to this password?', '¿Cambiar la contraseña de TODOS los usuarios no privilegiados a esta contraseña?'))) return;
      bulk.disabled = true; bmsg.className = 'small'; bmsg.textContent = '…';
      try { const r = await call('users-set-password', { password: bpw.value, include_disabled: binc.checked }); bmsg.className = 'small'; bmsg.textContent = '✓ ' + r.count + T(' usuário(s) atualizados', ' user(s) updated', ' usuario(s) actualizado(s)'); bulk.disabled = false; bpw.value = ''; loadList(); }
      catch (e) { bulk.disabled = false; bmsg.className = 'small error-box'; bmsg.textContent = e.message || T('falha', 'failed', 'fallido'); }
    } }, T('Trocar senha de todos', 'Change everyone\'s password', 'Cambiar la contraseña de todos'));
    panel.append(el('h3', { style: 'margin:1rem 0 .3rem' }, T('➕ Adicionar / resetar senha', '➕ Add / reset password', '➕ Agregar / restablecer contraseña')),
      el('div', { class: 'row' }, li, pw, fn, em, add), amsg,
      makeBatchUsers(),
      el('h3', { style: 'margin:1rem 0 .3rem' }, T('🔑 Troca de senha geral (prova)', '🔑 Bulk password change (contest)', '🔑 Cambio masivo de contraseña (competencia)')),
      el('p', { class: 'muted small' }, T('Define uma senha única para todos os não-privilegiados (após os alunos logarem).', 'Sets a single password for all non-privileged users (after the students log in).', 'Define una contraseña única para todos los usuarios no privilegiados (después de que los estudiantes inicien sesión).')),
      el('div', { class: 'row' }, bpw, el('label', { class: 'small' }, binc, T(' incluir desabilitados', ' include disabled', ' incluir deshabilitados')), bulk), bmsg);
    await loadList();
  }
  return { panel, load };
}
