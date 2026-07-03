// treino/criar/criar.js — wizard de criação de contest (gate por permissão).
import { apiGet, apiPost, getToken } from '/shared/api.js';
import { el, renderAuthArea } from '/shared/ui.js';
import { renderCreateContestLink } from '/shared/create-contest-link.js';
import { makeColorsEditor, makeTeamsEditor, makeRegionsEditor, makeBasicEditor } from '/shared/contest-config/index.js';

const app = document.getElementById('app');
const authMount = document.getElementById('authArea');
const refreshAuth = () => renderAuthArea(authMount, 'treino', refreshAuth).then(() => renderCreateContestLink(authMount));

const MODE_LABEL = {
  icpc: 'ICPC (tempo + penalidade)', obi: 'OBI (pontos parciais)',
  treino: 'Treino (lista, sem penalidade)', heuristic: 'Heurístico / custom', outro: 'Outro (custom)',
};
const DIFF_LABEL = { any: 'qualquer', easy: 'fáceis (≥50% AC)', medium: 'médios (20–50%)', hard: 'difíceis (<20%)', known: 'com histórico' };
const nowEpoch = () => Math.floor(Date.now() / 1000);
function toLocalDT(epoch) {
  const d = new Date((Number(epoch) || nowEpoch()) * 1000), p = (n) => String(n).padStart(2, '0');
  return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) + 'T' + p(d.getHours()) + ':' + p(d.getMinutes());
}
const dtToEpoch = (s) => { const t = Date.parse(s); return isNaN(t) ? 0 : Math.floor(t / 1000); };
const b64utf8 = (s) => btoa(unescape(encodeURIComponent(s)));
const debounce = (fn, ms) => { let h; return (...a) => { clearTimeout(h); h = setTimeout(() => fn(...a), ms); }; };
const slug = (s) => (s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]+/g, '').slice(0, 24);

const problems = [];          // {kind, source?, problem_id?, bank_id?, name, _letter?, _stmt?}
let userMode = 'own';         // 'own' | 'shared'
let contestUsers = [];        // [{login,password,fullname,email}]
let allTags = [];             // [{tag,count}]
let allCollections = [];      // [{collection,count}]

// ---------- gate / denied / result ----------
function showDenied(p) {
  app.innerHTML = '';
  app.append(el('div', { class: 'section' },
    el('h2', {}, '🔒 Sem permissão para criar contests'),
    el('p', { class: 'muted' }, 'Motivo: ' + ((p && p.reason) || 'não autenticado') + '.'),
    p ? el('p', { class: 'small muted' },
      'Você resolveu ' + (p.solved_count || 0) + ' problemas' +
      (p.threshold > 0 ? (' — o limite automático para liberar é ' + p.threshold) : '') +
      '. Um administrador pode liberar seu acesso na lista de criadores.')
      : el('p', {}, 'Faça login no Treino Livre primeiro.'),
    el('a', { class: 'btn ghost', href: '/treino/' }, '← Voltar ao treino')));
}

function showResult(res) {
  app.innerHTML = '';
  const card = el('div', { class: 'result-card' },
    el('h2', { style: 'margin:.1rem 0 .6rem' }, '✅ Contest criado e no ar!'),
    el('p', {}, 'O contest ', el('b', {}, res.contest_id), ' (', String(res.problems), ' problemas) foi publicado.'),
    el('div', { class: 'warn-box', style: 'margin:.6rem 0' },
      '⚠ Guarde as credenciais abaixo — as senhas só são exibidas agora.'),
    el('p', {}, 'Admin do contest: ', el('span', { class: 'cred' }, res.admin_login),
      res.admin_reused
        ? el('span', { class: 'small muted' }, ' · conta existente reutilizada — use sua senha atual do Treino Livre.')
        : [' · senha: ', el('span', { class: 'cred' }, res.admin_password)]));
  if (res.users_from) card.append(el('p', { class: 'small muted' }, 'Usuários: compartilhados do "' + res.users_from + '" (login com a conta do Treino Livre).'));
  if (res.users && res.users.length > 1) {
    card.append(el('p', {}, res.users.length + ' contas criadas. ',
      el('button', { class: 'btn ghost', onclick: () => downloadCsv(res.contest_id + '-credenciais.csv', res.users) }, '⬇ baixar credenciais (CSV)')));
  }
  card.append(el('div', { class: 'row', style: 'margin-top:.7rem' },
    el('a', { class: 'btn', href: res.url }, 'Abrir contest →'),
    el('a', { class: 'btn ghost', href: res.scoreboard_url }, 'Placar'),
    el('a', { class: 'btn ghost', href: '/treino/criar/' }, 'Criar outro')));
  app.append(card);
}

function downloadCsv(filename, users) {
  const head = 'login,senha,nome,email';
  const esc = (x) => '"' + String(x == null ? '' : x).replace(/"/g, '""') + '"';
  const rows = users.map((u) => [u.login, u.password, u.fullname, u.email].map(esc).join(','));
  const blob = new Blob([head + '\n' + rows.join('\n')], { type: 'text/csv' });
  const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = filename; a.click(); URL.revokeObjectURL(a.href);
}

// ---------- problemas: lista selecionada ----------
function renderProblems(listBox) {
  listBox.innerHTML = '';
  if (!problems.length) { listBox.append(el('p', { class: 'muted small' }, 'Nenhum problema ainda. Busque no banco, sorteie por tag, ou adicione por ID.')); return; }
  problems.forEach((p, i) => {
    const letter = el('input', { class: 'letter', value: p._letter || String.fromCharCode(65 + i), maxlength: '3' });
    letter.addEventListener('input', () => { p._letter = letter.value; });
    const name = el('input', { value: p.name || '', placeholder: 'Nome exibido' });
    name.addEventListener('input', () => { p.name = name.value; });
    const idtxt = p.bank_id ? ('banco: ' + p.bank_id) : ((p.source || 'cdmoj') + ' / ' + p.problem_id);
    const genWarn = (p._private && !p._hasStmt)
      ? el('div', { class: 'small', style: 'color:#b8860b;margin-top:.2rem' }, '⏳ enunciado em geração (aguardando juiz)')
      : '';
    const stmtWrap = el('div', { style: 'margin-top:.35rem' });
    const stmtToggle = el('a', { class: 'small', href: '#', style: 'cursor:pointer' }, '✎ enunciado personalizado');
    stmtToggle.addEventListener('click', (e) => {
      e.preventDefault();
      if (stmtWrap.firstChild) { stmtWrap.innerHTML = ''; return; }
      const ta = el('textarea', { rows: '4', placeholder: 'HTML do enunciado (opcional; sobrescreve o do banco)', style: 'width:100%' });
      ta.value = p._stmt || ''; ta.addEventListener('input', () => { p._stmt = ta.value; });
      stmtWrap.append(ta);
    });
    const up = el('button', { class: 'btn ghost', onclick: () => { if (i > 0) { [problems[i - 1], problems[i]] = [problems[i], problems[i - 1]]; renderProblems(listBox); } } }, '↑');
    const dn = el('button', { class: 'btn ghost', onclick: () => { if (i < problems.length - 1) { [problems[i + 1], problems[i]] = [problems[i], problems[i + 1]]; renderProblems(listBox); } } }, '↓');
    const rm = el('button', { class: 'btn danger', onclick: () => { problems.splice(i, 1); renderProblems(listBox); } }, '✕');
    listBox.append(el('div', { class: 'prob-row' }, letter,
      el('div', {}, name, el('div', { class: 'pid' }, idtxt), genWarn, stmtToggle, stmtWrap),
      el('div', { class: 'row' }, up, dn, rm)));
  });
}
function addProblem(p, listBox) {
  if (p.bank_id && problems.some((x) => x.bank_id === p.bank_id)) return;
  problems.push(p); renderProblems(listBox);
}

// ---------- usuários: prévia editável ----------
function parseUsers(text) {
  const out = [];
  text.split(/\r?\n/).forEach((raw) => {
    const line = raw.trim(); if (!line) return;
    if (line.includes(':')) { const p = line.split(':'); out.push({ login: (p[0] || '').trim(), password: (p[1] || '').trim(), fullname: (p[2] || '').trim(), email: (p[3] || '').trim() }); }
    else if (line.includes('\t') || line.includes(',')) { const p = line.split(/[\t,]/).map((s) => s.trim()); out.push({ login: p[0] || '', password: '', fullname: p[1] || '', email: p[2] || '' }); }
    else out.push({ login: '', password: '', fullname: line, email: '' });
  });
  // gera logins faltantes a partir do nome, garantindo unicidade
  const seen = new Set(out.map((u) => u.login).filter(Boolean));
  out.forEach((u) => {
    if (u.login) return;
    let base = slug(u.fullname) || 'user', cand = base, k = 1;
    while (seen.has(cand)) cand = base + (++k);
    seen.add(cand); u.login = cand;
  });
  return out;
}

function renderUsersTable(box) {
  box.innerHTML = '';
  if (!contestUsers.length) { box.append(el('p', { class: 'muted small' }, 'Cole a lista acima e clique “processar”.')); return; }
  const tb = el('tbody');
  contestUsers.forEach((u, i) => {
    const mk = (key, ph) => { const inp = el('input', { value: u[key] || '', placeholder: ph, style: 'width:100%' }); inp.addEventListener('input', () => { u[key] = inp.value; }); return inp; };
    const rm = el('button', { class: 'btn danger', onclick: () => { contestUsers.splice(i, 1); renderUsersTable(box); } }, '✕');
    tb.append(el('tr', {},
      el('td', {}, mk('login', 'login')), el('td', {}, mk('password', '(gerada)')),
      el('td', {}, mk('fullname', 'nome')), el('td', {}, mk('email', 'email (opcional)')), el('td', {}, rm)));
  });
  box.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
    el('thead', {}, el('tr', {}, el('th', {}, 'Login'), el('th', {}, 'Senha'), el('th', {}, 'Nome'), el('th', {}, 'Email'), el('th', {}, ''))), tb)),
    el('div', { class: 'small muted', style: 'margin-top:.3rem' }, contestUsers.length + ' usuário(s). Senhas em branco são geradas no servidor.'));
}

async function genPasswords(n) {
  try { const r = await apiGet('/treino/contest-create/genpass?n=' + n, { contest: 'treino', auth: true }); return r.passwords || []; } catch { return []; }
}

// ---------- semiautomático: sorteio por tag ----------
function makeDrawPanel(listBox) {
  const selected = [];
  const chips = el('div', { class: 'row', style: 'margin:.3rem 0' });
  const dl = el('datalist', { id: 'tagsDL' }); allTags.forEach((t) => dl.append(el('option', { value: t.tag }, t.tag + ' (' + t.count + ')')));
  const tagInput = el('input', { list: 'tagsDL', placeholder: 'tag (ex.: #lista-encadeada)…', style: 'min-width:220px' });
  const renderChips = () => { chips.innerHTML = ''; selected.forEach((tg, i) => chips.append(el('span', { class: 'tag-chip' }, tg, el('a', { href: '#', onclick: (e) => { e.preventDefault(); selected.splice(i, 1); renderChips(); } }, ' ✕')))); };
  const addTag = (tg) => { tg = (tg || '').trim(); if (tg && !selected.includes(tg)) { selected.push(tg); renderChips(); } tagInput.value = ''; };
  tagInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); addTag(tagInput.value); } });
  tagInput.addEventListener('input', () => { if (allTags.some((t) => t.tag === tagInput.value)) addTag(tagInput.value); });

  // coleções (curadas; casam exato — datalist do banco público)
  const selectedCols = [];
  const colChips = el('div', { class: 'row', style: 'margin:.3rem 0' });
  const cdl = el('datalist', { id: 'colsDL' }); allCollections.forEach((c) => cdl.append(el('option', { value: c.collection }, c.collection + ' (' + c.count + ')')));
  const colInput = el('input', { list: 'colsDL', placeholder: 'coleção (ex.: problemas-apc)…', style: 'min-width:220px' });
  const renderColChips = () => { colChips.innerHTML = ''; selectedCols.forEach((cn, i) => colChips.append(el('span', { class: 'tag-chip' }, cn, el('a', { href: '#', onclick: (e) => { e.preventDefault(); selectedCols.splice(i, 1); renderColChips(); } }, ' ✕')))); };
  const addCol = (cn) => { cn = (cn || '').trim(); if (cn && !selectedCols.includes(cn)) { selectedCols.push(cn); renderColChips(); } colInput.value = ''; };
  colInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); addCol(colInput.value); } });
  colInput.addEventListener('input', () => { if (allCollections.some((c) => c.collection === colInput.value)) addCol(colInput.value); });

  const count = el('input', { type: 'number', min: '1', max: '100', value: '6', style: 'width:70px' });
  const match = el('select', {}, el('option', { value: 'any' }, 'qualquer tag'), el('option', { value: 'all' }, 'todas as tags'));
  const diff = el('select', {}, ...Object.keys(DIFF_LABEL).map((k) => el('option', { value: k }, DIFF_LABEL[k])));
  const out = el('div', {});
  const drawBtn = el('button', { class: 'btn' }, '🎲 Sortear');
  let lastSeed = null;
  async function doDraw(reshuffle) {
    const qs = new URLSearchParams({ tags: selected.join(','), count: count.value || '6', match: match.value, difficulty: diff.value });
    if (selectedCols.length) qs.set('collections', JSON.stringify(selectedCols));
    if (reshuffle) {} else if (lastSeed != null) qs.set('seed', lastSeed);
    out.innerHTML = 'sorteando…';
    try {
      const r = await apiGet('/treino/contest-create/draw?' + qs.toString(), { contest: 'treino', auth: true });
      lastSeed = r.seed;
      out.innerHTML = '';
      if (!r.problems || !r.problems.length) { out.append(el('p', { class: 'muted small' }, 'Nenhum problema encontrado (' + r.candidates + ' candidatos). Ajuste as tags/dificuldade.')); return; }
      out.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' },
        'Sorteados ' + r.drawn + ' de ' + r.candidates + ' candidatos (seed ' + r.seed + '). ',
        el('a', { href: '#', onclick: (e) => { e.preventDefault(); doDraw(true); } }, '↻ sortear de novo'), ' · ',
        el('a', { href: '#', onclick: (e) => { e.preventDefault(); r.problems.forEach((p) => addProblem({ kind: 'bank', bank_id: p.id, name: p.title || p.id }, listBox)); } }, '+ adicionar todos')));
      r.problems.forEach((p) => {
        const add = el('button', { class: 'btn ghost', onclick: () => addProblem({ kind: 'bank', bank_id: p.id, name: p.title || p.id }, listBox) }, '+');
        out.append(el('div', { class: 'bank-item' },
          el('div', {}, el('div', { class: 't' }, p.title || p.id),
            el('div', { class: 'i' }, p.id + ' · ' + p.bucket + (p.total ? (' · ' + Math.round(p.acceptance * 100) + '% AC · ' + p.solvers + ' resolveram') : ' · sem histórico'))), add));
      });
    } catch (e) { out.innerHTML = ''; out.append(el('div', { class: 'small error-box' }, e.message || 'erro')); }
  }
  drawBtn.addEventListener('click', () => { lastSeed = null; doDraw(true); });
  renderChips();
  return el('div', { class: 'section', style: 'background:#fbfdff' },
    el('h3', { style: 'margin:.1rem 0 .4rem' }, '🎲 Sortear por coleção / tag / dificuldade'),
    el('div', { class: 'field' }, el('label', {}, 'Coleções'), colInput, cdl, colChips),
    el('div', { class: 'field' }, el('label', {}, 'Tags'), tagInput, dl, chips),
    el('div', { class: 'row' }, el('span', { class: 'small' }, 'quantos:'), count,
      el('span', { class: 'small' }, 'casar:'), match, el('span', { class: 'small' }, 'dificuldade:'), diff, drawBtn),
    out);
}

// ---------- form principal ----------
function buildForm(perm) {
  app.innerHTML = '';
  const me = perm.login || '';
  const modes = (perm.allowed_modes && perm.allowed_modes.length) ? perm.allowed_modes : ['icpc', 'obi', 'treino', 'heuristic'];

  const name = el('input', { placeholder: 'Ex.: Maratona de Treino 2026' });
  const cid = el('input', { placeholder: '(gerado do nome se vazio) — a-z 0-9 . _ -' });
  const mode = el('select', {}, ...modes.map((m) => el('option', { value: m }, MODE_LABEL[m] || m)));
  const start = el('input', { type: 'datetime-local', value: toLocalDT(nowEpoch()) });
  const end = el('input', { type: 'datetime-local', value: toLocalDT(nowEpoch() + 3 * 3600) });
  const langs = el('input', { placeholder: 'Ex.: C CPP PY3 JAVA — vazio = todas' });
  const showcode = el('input', { type: 'checkbox' });
  const basics = el('div', { class: 'section' },
    el('h2', {}, '1 · Dados do contest'),
    el('div', { class: 'field' }, el('label', {}, 'Nome'), name),
    el('div', { class: 'grid2' },
      el('div', { class: 'field' }, el('label', {}, 'ID (opcional)'), cid),
      el('div', { class: 'field' }, el('label', {}, 'Modo / placar'), mode)),
    el('div', { class: 'grid2' },
      el('div', { class: 'field' }, el('label', {}, 'Início'), start),
      el('div', { class: 'field' }, el('label', {}, 'Fim'), end)),
    el('div', { class: 'grid2' },
      el('div', { class: 'field' }, el('label', {}, 'Linguagens (opcional)'), langs),
      el('div', { class: 'field' }, el('label', {}, ' '), el('label', { style: 'font-weight:400' }, showcode, ' Mostrar código das submissões'))));

  // --- problemas ---
  const listBox = el('div', {});
  const search = el('input', { placeholder: '🔎 Buscar problemas (públicos + os seus privados) — título ou id…' });
  const results = el('div', { class: 'bank-results', style: 'display:none' });
  const accTag = (it) => it.private
    ? el('span', { class: 'tag', style: 'margin-left:.4rem;background:#3d3417;color:#ffe08a' }, it.access === 'shared' ? 'compartilhado' : 'privado')
    : '';
  const doSearch = debounce(async () => {
    const q = search.value.trim();
    try {
      const r = await apiGet('/treino/contest-create/problems?limit=30&q=' + encodeURIComponent(q), { contest: 'treino', auth: true });
      let items = r.problems || [];
      if (!q) items = items.filter((it) => it.private);   // sem busca: mostra só os SEUS (privados/compartilhados)
      results.innerHTML = ''; results.style.display = 'block';
      if (!items.length) { results.append(el('div', { class: 'bank-item' }, el('span', { class: 'muted small' }, q ? 'nada encontrado' : 'você não tem problemas privados — digite para buscar no banco público'))); return; }
      items.forEach((it) => results.append(el('div', { class: 'bank-item' },
        el('div', {}, el('div', { class: 't' }, (it.title || it.id), accTag(it)), el('div', { class: 'i' }, it.id)),
        el('button', { class: 'btn ghost', onclick: () => addProblem({ kind: 'bank', bank_id: it.id, name: it.title || it.id, _private: it.private, _hasStmt: it.has_statement }, listBox) }, '+ adicionar'))));
    } catch (e) { results.style.display = 'block'; results.innerHTML = ''; results.append(el('div', { class: 'bank-item' }, el('span', { class: 'small error-box' }, e.message || 'erro'))); }
  }, 250);
  search.addEventListener('input', doSearch);
  search.addEventListener('focus', doSearch);
  const bySrc = el('input', { value: 'cdmoj', style: 'width:90px' });
  const byPid = el('input', { placeholder: 'id do problema (ex.: secreto/foo)' });
  const byName = el('input', { placeholder: 'nome exibido' });
  const byAdd = el('button', { class: 'btn ghost', onclick: () => { const pid = byPid.value.trim(); if (!pid) { byPid.focus(); return; } addProblem({ kind: 'id', source: bySrc.value.trim() || 'cdmoj', problem_id: pid, name: byName.value.trim() || pid }, listBox); byPid.value = ''; byName.value = ''; } }, '+ por ID');
  const probs = el('div', { class: 'section' },
    el('h2', {}, '2 · Problemas'),
    makeDrawPanel(listBox),
    el('div', { class: 'field' }, el('label', {}, 'Buscar problemas (públicos + seus privados)'), search, results),
    el('div', { class: 'field' }, el('label', {}, 'Adicionar por ID (avançado)'), el('div', { class: 'row' }, bySrc, byPid, byName, byAdd)),
    el('h3', { style: 'margin:.8rem 0 .2rem' }, 'Problemas do contest'), listBox);
  renderProblems(listBox);

  // --- usuários ---
  const sharedRadio = el('input', { type: 'radio', name: 'umode', value: 'shared' });
  const ownRadio = el('input', { type: 'radio', name: 'umode', value: 'own', checked: true });
  const ownBox = el('div', {});
  const paste = el('textarea', { rows: '5', placeholder: 'Cole aqui. Formatos aceitos por linha:\n  login:senha:nome:email\n  login,nome,email\n  Nome Completo   (login e senha gerados)', style: 'width:100%' });
  const prev = el('div', {});
  const procBtn = el('button', { class: 'btn ghost', onclick: () => { contestUsers = parseUsers(paste.value); renderUsersTable(prev); } }, 'Processar lista');
  const addRow = el('button', { class: 'btn ghost', onclick: () => { contestUsers.push({ login: '', password: '', fullname: '', email: '' }); renderUsersTable(prev); } }, '+ linha');
  const genPw = el('button', { class: 'btn ghost', onclick: async () => { const blanks = contestUsers.filter((u) => !u.password); if (!blanks.length) return; const pw = await genPasswords(blanks.length); blanks.forEach((u, i) => { u.password = pw[i] || u.password; }); renderUsersTable(prev); } }, 'Gerar senhas faltantes');
  const dlBtn = el('button', { class: 'btn ghost', onclick: () => { if (contestUsers.length) downloadCsv('credenciais.csv', contestUsers); } }, '⬇ baixar CSV');
  ownBox.append(paste, el('div', { class: 'row', style: 'margin:.4rem 0' }, procBtn, addRow, genPw, dlBtn), prev);
  renderUsersTable(prev);
  const updateUserMode = () => { userMode = ownRadio.checked ? 'own' : 'shared'; ownBox.style.display = userMode === 'own' ? '' : 'none'; };
  ownRadio.addEventListener('change', updateUserMode); sharedRadio.addEventListener('change', updateUserMode);
  const users = el('div', { class: 'section' },
    el('h2', {}, '3 · Usuários'),
    el('div', { class: 'field' }, el('label', { style: 'font-weight:400' }, ownRadio, ' Criar usuários próprios do contest')),
    el('div', { class: 'field' }, el('label', { style: 'font-weight:400' }, sharedRadio, ' Compartilhar usuários do Treino Livre (sem gerência; login com a conta do treino)')),
    ownBox);

  // --- admin (obrigatório) ---
  const aLogin = el('input', { value: me ? (me.endsWith('.admin') ? me : me + '.admin') : '', placeholder: 'login do admin (terá sufixo .admin)' });
  const aPass = el('input', { placeholder: '(gerada se vazio)' });
  const aName = el('input', { value: perm.name || '', placeholder: 'nome do admin' });
  const aGen = el('button', { class: 'btn ghost', onclick: async () => { const pw = await genPasswords(1); if (pw[0]) aPass.value = pw[0]; } }, 'gerar');
  const admin = el('div', { class: 'section' },
    el('h2', {}, '4 · Admin do contest ', el('span', { class: 'small muted' }, '(obrigatório)')),
    el('p', { class: 'muted small' }, 'Conta exclusiva para administrar o contest (sempre criada, mesmo no modo compartilhado).'),
    el('div', { class: 'grid2' },
      el('div', { class: 'field' }, el('label', {}, 'Login'), aLogin),
      el('div', { class: 'field' }, el('label', {}, 'Nome'), aName)),
    el('div', { class: 'field' }, el('label', {}, 'Senha'), el('div', { class: 'row' }, aPass, aGen)));

  // --- visual e placar (editores reaproveitáveis: criação + admin do contest) ---
  const currentLetters = () => problems.map((p, i) => (p._letter && /^[A-Za-z0-9]{1,3}$/.test(p._letter)) ? p._letter : String.fromCharCode(65 + i));
  const colorsEd = makeColorsEditor({ letters: currentLetters() });
  const regionsEd = makeRegionsEditor({});
  const basicEd = makeBasicEditor({});
  let teamsEd = null;
  const teamsMount = el('div', {}, el('p', { class: 'muted small' }, 'carregando seletor de bandeiras…'));
  makeTeamsEditor({}).then((edt) => { teamsEd = edt; teamsMount.innerHTML = ''; teamsMount.append(edt.el); })
    .catch(() => { teamsMount.innerHTML = ''; teamsMount.append(el('p', { class: 'small error-box' }, 'falha ao carregar bandeiras')); });
  const hh = (t) => el('h3', { style: 'margin:1rem 0 .3rem' }, t);
  const visual = el('div', { class: 'section' },
    el('h2', {}, '5 · Visual e placar ', el('span', { class: 'small muted' }, '(opcional)')),
    hh('🎈 Cores dos balões'),
    el('div', {}, el('button', { class: 'btn ghost', style: 'margin-bottom:.3rem', onclick: () => colorsEd.setLetters(currentLetters()) }, '↻ sincronizar com os problemas')),
    colorsEd.el,
    hh('🏳️ Países e escolas (bandeira/sigla por regex no login)'), teamsMount,
    hh('🔎 Filtros de região do placar'), regionsEd.el,
    hh('⚙️ Configurações básicas'), basicEd.el);

  // --- criar ---
  const msg = el('div', { class: 'small', style: 'margin:.5rem 0' });
  function buildSpec(allowEmpty) {
    const colors = colorsEd.getValue();
    const regionsV = regionsEd.getValue();
    const teamsV = teamsEd ? teamsEd.getValue() : [];
    const basicV = basicEd.getValue();
    return {
      id: cid.value.trim() || undefined, name: name.value.trim(), mode: mode.value,
      start: dtToEpoch(start.value), end: dtToEpoch(end.value),
      languages: langs.value.trim() || undefined, showcode: showcode.checked,
      allow_empty: !!allowEmpty,
      admin: { login: aLogin.value.trim() || undefined, password: aPass.value.trim() || undefined, fullname: aName.value.trim() || undefined },
      ...(userMode === 'shared' ? { users_from: 'treino' }
        : { users: contestUsers.filter((u) => u.login || u.fullname).map((u) => ({ login: u.login || undefined, password: u.password || undefined, fullname: u.fullname || undefined, email: u.email || undefined })) }),
      problems: problems.map((p, i) => ({
        ...(p.bank_id ? { bank_id: p.bank_id } : { source: p.source || 'cdmoj', problem_id: p.problem_id }),
        name: p.name, letter: p._letter || String.fromCharCode(65 + i),
        ...(p._stmt ? { statement_b64: b64utf8(p._stmt) } : {}),
      })),
      ...(Object.keys(colors).length ? { colors } : {}),
      ...(regionsV.length ? { regions: regionsV } : {}),
      ...(teamsV.length ? { teams_meta: teamsV } : {}),
      locale: basicV.locale, login_enabled: basicV.login_enabled,
      ...(basicV.login_start ? { login_start: basicV.login_start } : {}),
      ...(basicV.freeze ? { freeze: basicV.freeze } : {}),
    };
  }
  async function submit(allowEmpty) {
    if (!name.value.trim()) { msg.className = 'small error-box'; msg.textContent = 'Informe o nome.'; return; }
    if (!aLogin.value.trim()) { msg.className = 'small error-box'; msg.textContent = 'Defina o login do admin do contest.'; return; }
    if (!allowEmpty && !problems.length) { msg.className = 'small error-box'; msg.textContent = 'Adicione problemas, ou use “Criar vazio”.'; return; }
    msg.className = 'small'; msg.textContent = 'Criando…';
    try { showResult(await apiPost('/treino/contest-create/create', buildSpec(allowEmpty), { contest: 'treino', auth: true })); }
    catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || 'falha ao criar'; }
  }
  const fileInp = el('input', { type: 'file', accept: '.tar.gz,.tgz,application/gzip', style: 'display:none' });
  fileInp.addEventListener('change', async () => {
    const f = fileInp.files[0]; if (!f) return;
    msg.className = 'small'; msg.textContent = 'Importando ' + f.name + '…';
    try {
      const buf = await f.arrayBuffer(); const b = new Uint8Array(buf); let bin = '';
      for (let i = 0; i < b.length; i += 0x8000) bin += String.fromCharCode.apply(null, b.subarray(i, i + 0x8000));
      showResult(await apiPost('/treino/contest-create/import', { tar_b64: btoa(bin) }, { contest: 'treino', auth: true }));
    } catch (e) { msg.className = 'small error-box'; msg.textContent = 'Falha no import: ' + (e.message || 'erro'); }
    fileInp.value = '';
  });
  const create = el('div', { class: 'section' },
    el('h2', {}, '6 · Criar'),
    el('div', { class: 'row' },
      el('button', { class: 'btn', onclick: () => submit(false) }, '🚀 Criar contest'),
      el('button', { class: 'btn ghost', onclick: () => submit(true) }, 'Criar vazio (configuro depois)'),
      el('button', { class: 'btn ghost', onclick: downloadTemplate }, '⬇ Template (JSON)'),
      el('button', { class: 'btn ghost', onclick: () => fileInp.click() }, '⬆ Importar .tar.gz'), fileInp),
    msg,
    el('p', { class: 'muted small', style: 'margin-top:.5rem' }, 'O contest entra no ar imediatamente. Um administrador pode removê-lo depois, se necessário.'));

  app.append(basics, probs, users, admin, visual, create);
}

async function downloadTemplate() {
  try {
    const r = await fetch('/api/v1/treino/contest-create/template', { headers: { Authorization: 'Bearer ' + getToken('treino') } });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const blob = await r.blob(); const a = document.createElement('a');
    a.href = URL.createObjectURL(blob); a.download = 'contest-template.json'; a.click(); URL.revokeObjectURL(a.href);
  } catch { alert('Falha ao baixar o template.'); }
}

async function gate() {
  let p;
  try { p = await apiGet('/treino/contest-create/permission', { contest: 'treino', auth: true }); }
  catch { showDenied(null); return; }
  if (!p || !p.can_create) { showDenied(p); return; }
  try { const t = await apiGet('/treino/contest-create/tags', { contest: 'treino', auth: true }); allTags = t.tags || []; } catch { allTags = []; }
  try { const c = await apiGet('/treino/contest-create/collections', { contest: 'treino', auth: true }); allCollections = c.collections || []; } catch { allCollections = []; }
  buildForm(p);
}

refreshAuth();
gate();
