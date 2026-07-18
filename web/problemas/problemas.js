// treino/problemas/problemas.js — gestão de problemas (Meus/Compartilhados/Públicos/Coleções).
// Leitura via /problems/* (Bearer). Detalhe mostra validação + enunciado e dispara
// Validar/Publicar e Calibrar (handlers já existentes). Git fica escondido (repo local por problema).
import { apiGet, apiPost, ApiError, getToken } from '/shared/api.js';
import { status, fileToBase64 } from '/shared/auth.js';
import { el, renderAuthArea, fmtDate } from '/shared/ui.js';
import { hBarChart } from '/lib/charts.js';
import { T } from '/shared/i18n.js';

async function downloadAuthed(path, filename) {
  try {
    const r = await fetch('/api/v1' + path, { headers: { Authorization: 'Bearer ' + getToken(CONTEST) } });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const b = await r.blob(), a = document.createElement('a');
    a.href = URL.createObjectURL(b); a.download = filename; a.click(); URL.revokeObjectURL(a.href);
  } catch (e) { alert(T('Falha ao baixar: ', 'Failed to download: ') + (e.message || e)); }
}
async function doImport(file) {
  if (!file) return;
  let mine = [];
  try { mine = ((await apiGet('/problems/repos', { contest: CONTEST, auth: true })).repos || []).filter(r => r.mine).map(r => r.repo); } catch {}
  const repo = prompt(T('Importar para qual diretório (pasta)?', 'Import into which directory (folder)?') + (mine.length ? T('\nSeus: ', '\nYours: ') + mine.join(', ') : T('\n(crie um primeiro em “+ Novo problema”)', '\n(create one first in “+ New problem”)')), mine[0] || '');
  if (!repo) return;
  try {
    const tar_b64 = await fileToBase64(file);
    const j = await apiPost('/problems/import', { repo: repo.trim(), tar_b64 }, { contest: CONTEST, auth: true });
    location.href = '/problemas/editar.html?id=' + encodeURIComponent(j.id);
  } catch (e) { alert(T('Falha ao importar: ', 'Failed to import: ') + (e instanceof ApiError ? e.message : (e.message || e))); }
}

const CONTEST = 'treino';
const PAGE = 50;
let TAB = 'painel', ROWS = [], COLLS = [], ORGS = [], page = 0, loggedIn = false, CAN_CREATE = false;
let PANEL = null, PANEL_SORT = { key: 'sev', dir: -1 };
let ANALYSIS = null, ANA_SORT = { key: 'attempts', dir: -1 };

const norm = (s) => (s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
const b64ToUtf8 = (b) => { try { return new TextDecoder().decode(Uint8Array.from(atob(b), c => c.charCodeAt(0))); } catch { return ''; } };
const pill = (cls, txt) => el('span', { class: 'pill ' + cls }, txt);

// ---- painel de status (aba "Painel") ----
// filtro por categoria (clicar num card): chave -> predicado sobre a linha do painel
let PANEL_FILTER = null;
const PANEL_PREDS = {
  being_calibrated: (p) => p.being_calibrated,
  validated: (p) => p.validated === 'ok',
  calibrated: (p) => p.calibrated,
  needs_recalibration: (p) => p.needs_recalibration,
  good_sol_no_tl: (p) => p.good_sol_no_tl,
  needs_review: (p) => p.needs_review,
};
const scard = (n, l, hl, fkey) => {
  const a = { class: 'scard' + (hl ? ' hl' : '') + (fkey ? ' clickable' : '') + (fkey && PANEL_FILTER === fkey ? ' on' : '') };
  if (fkey) {
    a.title = T('Clique para ver só estes', 'Click to show only these');
    a.onclick = () => { PANEL_FILTER = (PANEL_FILTER === fkey) ? null : fkey; page = 0; renderPanel(); };
  }
  return el('div', a, el('div', { class: 'n' }, String(n)), el('div', { class: 'l' }, l));
};
const fmtTL = (tl) => { const e = Object.entries(tl || {}).filter(([k]) => k !== 'default'); return e.length ? e.map(([k, v]) => `${k} ${(+v).toFixed(3)}s`).join(' · ') : '—'; };
const sevOf = (p) => p.needs_review ? 3 : p.needs_recalibration ? 2 : p.being_calibrated ? 1 : 0;
const valChip = (p) => p.validated === 'ok' ? pill('ok', T('validado', 'validated')) : p.validated === 'error' ? pill('no', T('reprovado', 'rejected')) : pill('mut', T('não validado', 'not validated'));
const calibChip = (p) => {
  if (p.being_calibrated) return pill('warn', T('calibrando…', 'calibrating…'));
  if (p.needs_recalibration) {
    const c = pill('warn', T('precisa recalibrar', 'needs recalibration'));
    c.title = T('O pacote mudou desde a calibração (conf/testes/soluções-good/scripts). Clique no problema para ver quais commits.',
      'The package changed since calibration (conf/tests/good-solutions/scripts). Click the problem to see which commits.');
    return c;
  }
  return p.calibrated ? pill('ok', T('calibrado', 'calibrated')) : pill('mut', T('sem calibração', 'no calibration'));
};
// chip "precisa revisão": solução good sem TL (falhou em todas as máquinas), público não validado/calibrado
const reviewChip = (p) => {
  if (!p.needs_review) return '';
  const rs = p.review_reasons || [];
  const label = rs.some(r => r.startsWith('good_sol_no_tl')) ? (T('good sem TL: ', 'good without TL: ') + (p.good_sol_missing_langs || []).join(','))
    : rs.includes('public_unvalidated') ? T('público não validado', 'public unvalidated')
    : rs.includes('public_uncalibrated') ? T('público sem calibração', 'public uncalibrated') : T('revisar', 'review');
  return el('span', { class: 'pill no', style: 'margin-left:.35rem', title: rs.join(', ') }, label);
};

function stateBadges(p) {
  const out = [];
  out.push(p.public ? pill('ok', T('público', 'public')) : pill('warn', T('rascunho', 'draft')));
  if (!p.html) out.push(pill('no', T('sem HTML', 'no HTML')));
  return out;
}

function filteredRows() {
  const q = norm(document.getElementById('q').value);
  const onlyBroken = document.getElementById('onlybroken').checked;
  return ROWS.filter(p => {
    if (onlyBroken && p.public) return false;
    if (q) {
      const hay = norm((p.title || '') + ' ' + (p.author || '') + ' ' + (p.id || ''));
      if (!hay.includes(q)) return false;
    }
    return true;
  });
}

function renderTable() {
  const rows = filteredRows();
  const isMine = TAB === 'mine';
  document.getElementById('count').textContent =
    `${rows.length} ${T('problema(s)', 'problem(s)')}` + (isMine ? ` · ${rows.filter(r => r.claimed).length} ${T('reivindicados', 'claimed')}, ${rows.filter(r => !r.claimed).length} ${T('prováveis', 'likely')}` : '');
  const pages = Math.max(1, Math.ceil(rows.length / PAGE));
  if (page >= pages) page = 0;
  const slice = rows.slice(page * PAGE, page * PAGE + PAGE);

  const head = el('tr', {},
    el('th', {}, T('Problema', 'Problem')),
    el('th', {}, T('Autor', 'Author')),
    el('th', {}, T('Coleção', 'Collection')),
    ...(isMine ? [el('th', {}, T('Posse', 'Ownership'))] : []),
    el('th', {}, T('Estado', 'State')),
    el('th', {}, ''));
  const tb = el('tbody');
  slice.forEach(p => {
    const cells = [
      el('td', {}, el('a', { href: '#', onclick: (e) => { e.preventDefault(); openDetail(p.id); } }, p.title || p.prob || p.id),
        el('div', { class: 'small muted2' }, p.id)),
      el('td', { class: 'small' }, p.author || '—'),
      el('td', { class: 'small' }, (p.collections || []).map(c =>
        el('a', { href: '#', class: 'tag', onclick: (e) => { e.preventDefault(); openCollection(c); } }, c))),
    ];
    if (isMine) cells.push(el('td', {}, p.claimed ? pill('ok', T('meu', 'mine')) : pill('mut', T('provável', 'likely'))));
    cells.push(el('td', {}, ...stateBadges(p)));
    cells.push(el('td', { class: 'row', style: 'gap:.3rem' },
      el('button', { class: 'btn ghost', onclick: () => openDetail(p.id) }, T('Ver', 'View')),
      el('a', { class: 'btn ghost', href: '/problemas/editar.html?id=' + encodeURIComponent(p.id) }, T('Editar', 'Edit')),
      (isMine && !p.public) ? el('button', { class: 'btn ghost', title: T('Mover para outra org (só rascunho)', 'Move to another org (draft only)'), onclick: () => moveProblem(p) }, T('Mover', 'Move')) : null));
    tb.append(el('tr', {}, ...cells));
  });

  const list = document.getElementById('list');
  list.innerHTML = '';
  list.append(el('table', { class: 'moj' }, el('thead', {}, head), tb));

  const pager = document.getElementById('pager'); pager.innerHTML = '';
  if (pages > 1) {
    pager.append(el('button', { class: 'btn ghost', onclick: () => { if (page > 0) { page--; renderTable(); } } }, '‹'));
    pager.append(el('span', { class: 'small' }, ` ${T('página', 'page')} ${page + 1} / ${pages} `));
    pager.append(el('button', { class: 'btn ghost', onclick: () => { if (page < pages - 1) { page++; renderTable(); } } }, '›'));
  }
}

// mover um RASCUNHO p/ outra org (muda o id). Alvo = uma das MINHAS orgs (via /problems/repos).
async function moveProblem(p) {
  const cur = String(p.id).split('#')[0];
  let orgs = [];
  try { orgs = ((await apiGet('/problems/repos', { contest: CONTEST, auth: true })).repos || []).map(r => r.repo); }
  catch (e) { alert(T('Falha ao listar suas orgs: ', 'Failed to list your orgs: ') + (e instanceof ApiError ? e.message : (e.message || e))); return; }
  const targets = orgs.filter(n => n !== cur);
  if (!targets.length) { alert(T('Você não tem outra org para onde mover. Crie uma na aba Orgs.', 'You have no other org to move to. Create one in the Orgs tab.')); return; }
  const to = (prompt(`${T('Mover “', 'Move “')}${p.id}${T('” para qual org?', '” to which org?')}\n${T('Suas orgs: ', 'Your orgs: ')}${targets.join(', ')}`, targets[0]) || '').trim();
  if (!to || to === cur) return;
  try {
    const j = await apiPost('/problems/move', { id: p.id, to_org: to }, { contest: CONTEST, auth: true });
    alert(`${T('Movido:', 'Moved:')} ${j.from} → ${j.id}`); loadTab(TAB);
  } catch (e) { alert((e instanceof ApiError ? e.message : T('Falha ao mover', 'Failed to move')) + (e.code ? ` (${e.code})` : '')); }
}

// ── COLEÇÕES = tags de agrupamento (m:n, curadas). Ortogonais à ORG. ─────────────────────────
// 129+ coleções: tabela ORDENÁVEL + busca (#q) + filtro "minhas" — cards não escalavam.
let COLL_SORT = { key: 'count', dir: -1 }, COLL_MINE = false;
function setCollSort(key) {
  COLL_SORT = { key, dir: COLL_SORT.key === key ? -COLL_SORT.dir : (key === 'count' || key === 'public' ? -1 : 1) };
  renderCollections();
}
function collRows() {
  const q = norm(document.getElementById('q').value.trim());
  let rows = COLLS.slice();
  if (COLL_MINE) rows = rows.filter(c => c.mine);
  if (q) rows = rows.filter(c => norm(c.name + ' ' + (c.owner || '')).includes(q));
  const k = COLL_SORT.key, d = COLL_SORT.dir;
  rows.sort((a, b) => {
    const va = a[k], vb = b[k];
    if (typeof va === 'number' || typeof vb === 'number') return ((va || 0) - (vb || 0)) * d;
    return String(va || '').localeCompare(String(vb || '')) * d;
  });
  return rows;
}
function renderCollections() {
  const rows = collRows();
  document.getElementById('count').textContent =
    `${T('mostrando', 'showing')} ${rows.length} ${T('de', 'of')} ${COLLS.length} ${T('coleção(ões)', 'collection(s)')}`;
  document.getElementById('pager').innerHTML = '';
  const list = document.getElementById('list'); list.innerHTML = '';
  list.append(el('div', { class: 'small muted', style: 'margin-bottom:.4rem' },
    T('Coleções são rótulos de agrupamento — um problema pode estar em VÁRIAS (diferente de ORG, que controla acesso). Clique no nome para ver os problemas.', 'Collections are grouping labels — a problem can be in SEVERAL (unlike ORG, which controls access). Click a name to see its problems.')));
  const nc = el('input', { placeholder: T('nova coleção (pode ter espaços)', 'new collection (spaces allowed)'), style: 'padding:.35rem;min-width:16rem' });
  const mineBtn = el('button', { class: 'pill ' + (COLL_MINE ? 'ok' : 'mut'), style: 'cursor:pointer;border:none',
    onclick: () => { COLL_MINE = !COLL_MINE; renderCollections(); } }, T('só minhas', 'mine only'));
  list.append(el('div', { class: 'row', style: 'gap:.4rem;margin-bottom:.7rem;align-items:center' },
    nc, el('button', { class: 'btn', onclick: () => createColl(nc.value.trim(), nc) }, T('+ Coleção', '+ Collection')),
    el('span', { style: 'flex:1' }), mineBtn));

  const arrow = (k) => COLL_SORT.key === k ? (COLL_SORT.dir > 0 ? ' ▲' : ' ▼') : '';
  const th = (label, k) => k
    ? el('th', { class: 'sortable', onclick: () => setCollSort(k) }, label + arrow(k))
    : el('th', {}, label);
  const table = el('table', { class: 'moj', style: 'width:100%' });
  table.append(el('thead', {}, el('tr', {},
    th(T('Coleção', 'Collection'), 'name'), th(T('Dono', 'Owner'), 'owner'),
    th(T('Problemas', 'Problems'), 'count'), th(T('Públicos', 'Public'), 'public'),
    el('th', {}, T('Ações', 'Actions')))));
  const tb = el('tbody');
  rows.forEach(c => {
    const allPub = c.public === c.count;
    const pubPill = c.public === 0 ? pill('no', T('0 públicos', '0 public'))
      : (allPub ? pill('ok', T('todos', 'all')) : pill('warn', `${c.public}/${c.count}`));
    const acts = el('td', {});
    if (c.can_manage) acts.append(
      el('button', { class: 'btn ghost', style: 'padding:.05rem .4rem', title: T('Renomear', 'Rename'),
        onclick: (ev) => { ev.stopPropagation(); renameColl(c); } }, '✏'),
      el('button', { class: 'btn ghost', style: 'padding:.05rem .4rem;margin-left:.25rem', title: T('Excluir', 'Delete'),
        onclick: (ev) => { ev.stopPropagation(); deleteColl(c); } }, '🗑'));
    tb.append(el('tr', { style: 'cursor:pointer', onclick: () => openCollection(c.name) },
      el('td', {}, el('b', {}, c.name), c.mine ? el('span', { class: 'small muted2' }, ' · ' + T('sua', 'yours')) : ''),
      el('td', { class: 'small muted2' }, c.owner || '—'),
      el('td', {}, String(c.count)),
      el('td', {}, pubPill),
      acts));
  });
  table.append(tb);
  list.append(el('div', { style: 'overflow-x:auto' }, table));
}
async function createColl(name, inp) {
  if (!name) return;
  try { await apiPost('/problems/collection-create', { name }, { contest: CONTEST, auth: true }); if (inp) inp.value = ''; loadTab('collections'); }
  catch (e) { alert(e.message); }
}
async function renameColl(c) {
  const to = (prompt(`${T('Renomear a coleção “', 'Rename the collection “')}${c.name}${T('” para:', '” to:')}`, c.name) || '').trim();
  if (!to || to === c.name) return;
  try { const j = await apiPost('/problems/collection-rename', { name: c.name, to }, { contest: CONTEST, auth: true }); alert(T('Renomeada — o re-tag dos problemas roda em segundo plano (alguns minutos em coleções grandes).', 'Renamed — problems are re-tagged in the background (a few minutes for large collections).')); loadTab('collections'); }
  catch (e) { alert(e.message); }
}
async function deleteColl(c) {
  if (!confirm(`${T('Excluir a coleção “', 'Delete the collection “')}${c.name}${T('”? Ela sai de ', '”? It leaves ')}${c.count}${T(' problema(s) (a tag é removida deles).', ' problem(s) (the tag is removed from them).')}`)) return;
  try { const j = await apiPost('/problems/collection-delete', { name: c.name }, { contest: CONTEST, auth: true }); alert(T('Excluída — o untag dos problemas roda em segundo plano (a coleção some do registro ao final).', 'Deleted — problems are untagged in the background (the collection leaves the registry when done).')); loadTab('collections'); }
  catch (e) { alert(e.message); }
}

// ── ORGS = acesso (membros que editam + trava de público). Uma org por problema (prefixo do id). ──
async function loadOrgs() {
  const list = document.getElementById('list');
  try { const j = await apiGet('/orgs/list', { contest: CONTEST, auth: true }); ORGS = j.orgs || []; renderOrgs(); }
  catch (e) { list.innerHTML = `<span class="error-box">${e instanceof ApiError ? e.message : T('Falha ao carregar', 'Failed to load')}</span>`; }
}
// mestre-detalhe: linha compacta por org (membros = só CONTAGEM; a lista de logins vive no
// detalhe expandido como chips removíveis — era o que esticava os cards). Uma aberta por vez.
let ORG_OPEN = null;
function renderOrgs() {
  const q = norm(document.getElementById('q').value.trim());
  const rows = q ? ORGS.filter(o => norm(o.name + ' ' + (o.title || '') + ' ' + (o.members || []).join(' ')).includes(q)) : ORGS;
  document.getElementById('count').textContent =
    `${T('mostrando', 'showing')} ${rows.length} ${T('de', 'of')} ${ORGS.length} org(s)`;
  document.getElementById('pager').innerHTML = '';
  const list = document.getElementById('list'); list.innerHTML = '';
  list.append(el('div', { class: 'small muted', style: 'margin-bottom:.4rem' },
    T('ORG = quem pode editar (membros) + o prefixo do id. Privada por padrão: problemas só ficam públicos se a org permitir. Clique numa linha para gerir. A busca acha org por NOME ou por MEMBRO.', 'ORG = who can edit (members) + the id prefix. Private by default: problems only become public if the org allows it. Click a row to manage. Search finds orgs by NAME or by MEMBER.')));
  if (CAN_CREATE) {
    const no = el('input', { placeholder: T('nova org (minúsculas, sem espaço)', 'new org (lowercase, no spaces)'), style: 'padding:.35rem;min-width:16rem' });
    list.append(el('div', { class: 'row', style: 'gap:.4rem;margin-bottom:.7rem' },
      no, el('button', { class: 'btn', onclick: () => createOrg(no.value.trim(), no) }, '+ Org')));
  }
  const table = el('table', { class: 'moj', style: 'width:100%' });
  table.append(el('thead', {}, el('tr', {},
    el('th', {}, 'Org'), el('th', {}, T('Trava', 'Lock')),
    el('th', {}, T('Problemas', 'Problems')), el('th', {}, T('Membros', 'Members')), el('th', {}, ''))));
  const tb = el('tbody');
  rows.forEach(o => {
    const open = ORG_OPEN === o.name;
    const paChip = o.implicit ? pill('mut', T('privada (própria)', 'private (own)'))
      : o.can_manage
        ? el('button', { class: 'pill ' + (o.public_allowed ? 'ok' : 'no'), style: 'cursor:pointer;border:none',
            title: T('Trava de público (clique p/ alternar)', 'Public lock (click to toggle)'),
            onclick: (ev) => { ev.stopPropagation(); toggleOrgPublic(o); } },
            o.public_allowed ? T('permite público', 'allows public') : T('privada 🔒', 'private 🔒'))
        : pill(o.public_allowed ? 'ok' : 'no', o.public_allowed ? T('permite público', 'allows public') : T('privada 🔒', 'private 🔒'));
    tb.append(el('tr', { class: 'orgrow', onclick: () => { ORG_OPEN = open ? null : o.name; renderOrgs(); } },
      el('td', {}, el('b', {}, o.name),
        o.implicit ? el('span', { class: 'small muted2' }, T(' (sua org)', ' (your org)')) : '',
        (o.title && o.title !== o.name) ? el('div', { class: 'small muted2' }, o.title) : '',
        o.can_manage && !o.implicit ? el('span', { class: 'small muted2' }, ' · ' + T('você administra', 'you manage')) : ''),
      el('td', {}, paChip),
      el('td', {}, `${o.count}`, o.public ? el('span', { class: 'small muted2' }, ` · ${o.public} ${T('públicos', 'public')}`) : ''),
      el('td', {}, `${(o.members || []).length} ${T('membro(s)', 'member(s)')}`),
      el('td', { style: 'width:1.5rem;text-align:center' }, open ? '▾' : '▸')));
    if (open) {
      const box = el('div', {});
      // membros como CHIPS: ⭐ = admin da org; ✕ = remover (só quem administra, org não-implícita)
      const chips = el('div', { style: 'margin:.2rem 0 .4rem' });
      const admins = o.admins || [];
      (o.members || []).forEach(m => {
        const ch = el('span', { class: 'chip', title: admins.includes(m) ? T('admin da org', 'org admin') : '' },
          (admins.includes(m) ? '⭐ ' : '') + m);
        if (o.can_manage && !o.implicit) ch.append(el('span', { class: 'x', title: T('Remover da org', 'Remove from org'),
          onclick: (ev) => { ev.stopPropagation();
            if (confirm(`${T('Remover ', 'Remove ')}${m}${T(' da org ', ' from org ')}${o.name}?`)) orgMember(o, m, false, null); } }, '✕'));
        chips.append(ch);
      });
      if (!(o.members || []).length) chips.append(el('span', { class: 'small muted2' }, '—'));
      box.append(chips);
      if (o.can_manage && !o.implicit) {
        const inp = el('input', { placeholder: T('login do novo membro', 'new member login'), style: 'padding:.3rem;width:13rem' });
        inp.addEventListener('keydown', (ev) => { if (ev.key === 'Enter') orgMember(o, inp.value.trim(), true, inp); });
        const empty = o.count === 0;
        box.append(el('div', { class: 'row', style: 'gap:.3rem;flex-wrap:wrap;align-items:center' },
          inp,
          el('button', { class: 'btn ghost', style: 'padding:.1rem .5rem', onclick: () => orgMember(o, inp.value.trim(), true, inp) }, T('+ membro', '+ member')),
          el('span', { style: 'flex:1' }),
          el('button', {
            class: 'btn ghost', style: 'padding:.1rem .5rem;color:#e66;border-color:#a44',
            disabled: !empty,
            title: empty ? T('Remover esta org vazia', 'Remove this empty org') : T('Esvazie a org (mova/exclua os problemas) antes de removê-la', 'Empty the org (move/delete the problems) before removing it'),
            onclick: empty ? () => deleteOrg(o) : null,
          }, T('excluir org', 'delete org'))));
      } else if (o.implicit) {
        box.append(el('div', { class: 'small muted2' },
          T('Sua org pessoal: sempre privada, só sua — problemas em elaboração vivem aqui.', 'Your personal org: always private, yours only — draft problems live here.')));
      }
      tb.append(el('tr', { class: 'orgdetail' }, el('td', { colspan: '5' }, box)));
    }
  });
  table.append(tb);
  list.append(el('div', { style: 'overflow-x:auto' }, table));
}
async function createOrg(name, inp) {
  if (!name) return;
  if (!/^[a-z0-9][a-z0-9._-]{1,63}$/.test(name)) { alert(T('Nome de org inválido: minúsculas/números/._- (sem espaço), 2–64 caracteres.', 'Invalid org name: lowercase/digits/._- (no spaces), 2–64 characters.')); return; }
  try { await apiPost('/orgs/create', { name }, { contest: CONTEST, auth: true }); if (inp) inp.value = ''; loadTab('orgs'); }
  catch (e) { alert(e.message); }
}
async function deleteOrg(o) {
  if (!confirm(`${T('Remover a org “', 'Remove the org “')}${o.name}${T('”? Ela precisa estar VAZIA (sem problemas). Ação irreversível.', '”? It must be EMPTY (no problems). Irreversible action.')}`)) return;
  try { await apiPost('/orgs/delete', { name: o.name }, { contest: CONTEST, auth: true }); loadTab('orgs'); }
  catch (e) { alert(e.message); }
}
async function orgMember(o, login, add, inp) {
  if (!login) return;
  try {
    const j = await apiPost('/orgs/members', add ? { name: o.name, add: [login] } : { name: o.name, remove: [login] }, { contest: CONTEST, auth: true });
    o.members = j.members; if (inp) inp.value = ''; renderOrgs();
  } catch (e) { alert(e.message); }
}
async function toggleOrgPublic(o) {
  const off = o.public_allowed;
  if (off && o.public > 0 && !confirm(`${T('Tornar “', 'Making “')}${o.name}${T('” PRIVADA vai DESPUBLICAR ', '” PRIVATE will UNPUBLISH ')}${o.public}${T(' problema(s) (saem do treino livre). Continuar?', ' problem(s) (they leave free training). Continue?')}`)) return;
  try {
    const j = await apiPost('/orgs/set-public-allowed', { name: o.name, public_allowed: !o.public_allowed }, { contest: CONTEST, auth: true });
    o.public_allowed = j.public_allowed;
    if (off && j.unpublished) o.public = Math.max(0, o.public - j.unpublished);
    renderOrgs();
  } catch (e) { alert(e.message); }
}

async function openCollection(name) {
  setActiveTab(null);
  document.getElementById('q').value = '';
  const list = document.getElementById('list'); list.innerHTML = `<span class="small muted">${T('Carregando…', 'Loading…')}</span>`;
  try {
    const j = await apiGet('/problems/collection?name=' + encodeURIComponent(name), { contest: CONTEST, auth: true });
    ROWS = j.problems || []; TAB = 'collection:' + name; page = 0;
    document.getElementById('list').scrollIntoView({ behavior: 'smooth', block: 'start' });
    renderTable();
    document.getElementById('count').textContent =
      `${T('coleção', 'collection')} “${name}” · ${ROWS.length} ${T('problemas', 'problems')} · ${ROWS.filter(r => r.public).length} ${T('públicos', 'public')}`;
  } catch (e) { list.innerHTML = `<span class="error-box">${e.message}</span>`; }
}

async function openDetail(id) {
  const d = document.getElementById('detail');
  d.style.display = ''; d.innerHTML = `<span class="small muted">${T('Carregando detalhe…', 'Loading details…')}</span>`;
  d.scrollIntoView({ behavior: 'smooth', block: 'start' });
  let j;
  try { j = await apiGet('/problems/get?id=' + encodeURIComponent(id), { contest: CONTEST, auth: true }); }
  catch (e) { d.innerHTML = `<span class="error-box">${e.message}</span>`; return; }

  const head = el('div', { class: 'row', style: 'justify-content:space-between;align-items:flex-start;gap:1rem' },
    el('div', {},
      el('h3', { style: 'margin:0' }, j.title || j.prob || j.id),
      el('div', { class: 'small muted2' }, j.id),
      el('div', { class: 'small' }, T('autor: ', 'author: '), j.author || '—',
        j.owner ? el('span', {}, T(' · dono: ', ' · owner: '), el('b', {}, j.owner)) : '',
        (j.collaborators && j.collaborators.length) ? el('span', {}, T(' · compartilhado: ', ' · shared: ') + j.collaborators.join(', ')) : ''),
      el('div', { class: 'row', style: 'gap:.4rem;margin-top:.3rem' }, ...stateBadges(j),
        ...(j.tags || []).map(t => el('span', { class: 'tag' }, t)))),
    el('div', { class: 'row', style: 'gap:.4rem' },
      el('a', { class: 'btn ghost', href: '/problemas/editar.html?id=' + encodeURIComponent(id) }, T('Editar', 'Edit')),
      el('button', { class: 'btn', id: 'btnPub', onclick: () => doAction('publish', id) }, T('Validar & Publicar', 'Validate & Publish')),
      el('button', { class: 'btn ghost', id: 'btnCal', onclick: () => doAction('request-calibration', id) }, T('Calibrar', 'Calibrate')),
      el('button', { class: 'btn ghost', title: T('Baixar como pacote ICPC/Kattis', 'Download as ICPC/Kattis package'), onclick: () => downloadAuthed('/problems/export?id=' + encodeURIComponent(id), id.split('#').pop() + '.icpc.tar.gz') }, '⬇ ICPC')));

  const v = j.validation;
  const vbox = el('div', { style: 'margin-top:.6rem' });
  vbox.append(el('h4', { style: 'margin:.4rem 0' }, T('Validação ', 'Validation '),
    v ? (v.ok ? pill('ok', T('aprovado', 'passed')) : pill('no', T('reprovado', 'rejected'))) : pill('mut', T('não validado', 'not validated'))));
  if (v) {
    if (v.at) vbox.append(el('div', { class: 'small muted2' }, T('em ', 'on ') + fmtDate(v.at)));
    const ul = el('ul', { class: 'checks' });
    (v.checks || []).forEach(c => ul.append(el('li', {},
      el('span', { class: 'k' }, (c.ok ? '✓ ' : '✗ ') + c.name), c.detail ? el('span', { class: 'small muted2' }, c.detail) : '')));
    vbox.append(ul);
    if (v.render_warnings) vbox.append(el('div', { class: 'small' }, pill('warn', T('avisos de render', 'render warnings')), ' ' + v.render_warnings));
  } else {
    vbox.append(el('div', { class: 'small muted' }, T('Clique em “Validar & Publicar” para rodar o portão de qualidade num juiz.', 'Click “Validate & Publish” to run the quality gate on a judge.')));
  }

  const stmt = el('div', { style: 'margin-top:.6rem' });
  if (j.statement_html_b64) {
    const html = b64ToUtf8(j.statement_html_b64);
    // mesmo render dos demais lugares: extrai o body e injeta em .statement-content (CSS unificado
    // do tema) — NÃO usa iframe (que mostrava o CSS embutido do pandoc, divergente)
    const sc = el('div', { class: 'statement-content' });
    try { const d = new DOMParser().parseFromString(html, 'text/html'); sc.innerHTML = d.body ? d.body.innerHTML : html; } catch { sc.innerHTML = html; }
    stmt.append(el('h4', { style: 'margin:.4rem 0' }, T('Enunciado', 'Statement')), sc);
  } else {
    stmt.append(el('div', { class: 'small muted' }, T('Sem HTML publicado ainda (não está no treino).', 'No HTML published yet (not in training).')));
  }

  // ⚙ calibração: estado vivo + o PORQUÊ de precisar recalibrar (commits desde a calibração
  // que tocaram conf/tests/input/sols/good/scripts — o que o tl-checksum cobre)
  const calbox = el('div', { style: 'margin-top:.6rem' });
  calbox.append(el('span', { class: 'small muted' }, T('Verificando calibração…', 'Checking calibration…')));
  (async () => {
    try {
      const t = await apiGet('/problems/tl?id=' + encodeURIComponent(id), { contest: CONTEST, auth: true });
      calbox.innerHTML = '';
      if (t.needs_recalibration) {
        calbox.append(el('h4', { style: 'margin:.4rem 0' }, T('⚠ Precisa recalibrar', '⚠ Needs recalibration')));
        calbox.append(el('div', { class: 'small' },
          T('O pacote mudou desde a calibração', 'The package changed since calibration'),
          t.calibrated_at ? T(' de ', ' of ') + fmtDate(t.calibrated_at) : '',
          ' — checksum ', el('code', {}, (t.calibrated_checksum || '').slice(0, 8)), ' → ',
          el('code', {}, (t.checksum || '').slice(0, 8)), '. ',
          T('Mudanças em conf/testes/soluções-good/scripts invalidam o TL medido.',
            'Changes to conf/tests/good-solutions/scripts invalidate the measured TL.')));
        const chs = t.changes || [];
        if (chs.length) {
          const ul = el('ul', { class: 'checks' });
          chs.forEach(ch => ul.append(el('li', {},
            el('code', { class: 'small' }, (ch.sha || '').slice(0, 7)), ' ',
            el('b', {}, ch.subject || '—'), ' ',
            el('span', { class: 'small muted2' }, (ch.author || '?') + (ch.at ? ' · ' + fmtDate(ch.at) : '')))));
          calbox.append(el('div', { class: 'small', style: 'margin-top:.3rem' },
            T('Commits desde a calibração que afetam o TL:', 'Commits since calibration affecting the TL:')), ul);
        }
        if ((t.changed_files || []).length) calbox.append(el('div', { class: 'small muted2' },
          T('Arquivos: ', 'Files: ') + t.changed_files.join(', ')));
        calbox.append(el('div', { class: 'small', style: 'margin-top:.3rem' },
          el('a', { href: '/problemas/editar.html?id=' + encodeURIComponent(id) + '#hist' },
            T('ver histórico completo no editor →', 'see full history in the editor →'))));
      } else if (t.calibrated) {
        calbox.append(el('div', { class: 'small muted2' },
          pill('ok', T('calibração em dia', 'calibration up to date')),
          t.calibrated_at ? ' · ' + fmtDate(t.calibrated_at) : ''));
      }
    } catch { calbox.innerHTML = ''; }
  })();

  d.innerHTML = ''; d.append(head, vbox, calbox, stmt);
}

async function doAction(action, id) {
  const btn = document.getElementById(action === 'publish' ? 'btnPub' : 'btnCal');
  const old = btn.textContent; btn.disabled = true; btn.textContent = T('Enviando…', 'Submitting…');
  try {
    const j = await apiPost('/problems/' + action, { id }, { contest: CONTEST, auth: true });
    btn.textContent = (action === 'publish' ? T('Enfileirado p/ validação', 'Queued for validation') : T('Calibração enfileirada', 'Calibration queued')) + ' ✓';
  } catch (e) {
    btn.textContent = old; btn.disabled = false;
    alert((e instanceof ApiError ? e.message : T('Falha', 'Failed')) + (e.code ? ` (${e.code})` : ''));
  }
}

function setActiveTab(tab) {
  document.querySelectorAll('#tabs button').forEach(b =>
    b.classList.toggle('active', b.dataset.tab === tab));
}

async function loadPanel() {
  const list = document.getElementById('list'); list.innerHTML = `<span class="small muted">${T('Carregando painel…', 'Loading panel…')}</span>`;
  document.getElementById('pager').innerHTML = '';
  try {
    PANEL = await apiGet('/problems/status', { contest: CONTEST, auth: true });
  } catch (e) {
    list.innerHTML = `<span class="error-box">${e instanceof ApiError ? e.message : T('Falha ao carregar', 'Failed to load')}</span>`; return;
  }
  renderPanel();   // NÃO zera page: refresh manual preserva ordenação/filtro/página (renderPanel clampa)
}

// filtra (#q + "só com atenção") e ordena as linhas do painel conforme PANEL_SORT
function panelRows() {
  const q = norm(document.getElementById('q').value);
  const attn = document.getElementById('onlybroken').checked;
  const fpred = PANEL_FILTER ? PANEL_PREDS[PANEL_FILTER] : null;
  const rows = (PANEL?.problems || []).filter(p => {
    if (fpred && !fpred(p)) return false;
    if (attn && !(p.needs_review || p.needs_recalibration)) return false;
    if (q) { const hay = norm((p.title || '') + ' ' + (p.author || '') + ' ' + (p.id || '')); if (!hay.includes(q)) return false; }
    return true;
  });
  const k = PANEL_SORT.key, d = PANEL_SORT.dir;
  const keyOf = (p) => k === 'title' ? norm(p.title || p.id) : k === 'author' ? norm(p.author || '')
    : k === 'validated' ? ({ error: 2, none: 1, ok: 0 }[p.validated] ?? 0)
    : k === 'updated' ? (p.updated_at || 0) : sevOf(p);   // 'sev'/'calibrated' -> severidade
  return rows.slice().sort((a, b) => {
    const va = keyOf(a), vb = keyOf(b);
    if (va < vb) return -d; if (va > vb) return d;
    const ta = norm(a.title || a.id), tb = norm(b.title || b.id); return ta < tb ? -1 : ta > tb ? 1 : 0;
  });
}

function setPanelSort(key) {
  if (PANEL_SORT.key === key) PANEL_SORT.dir *= -1;
  else PANEL_SORT = { key, dir: (key === 'title' || key === 'author') ? 1 : -1 };
  page = 0; renderPanel();
}

function renderPanel() {
  if (!PANEL) return;
  const c = PANEL.counts || {};
  const rows = panelRows();
  document.getElementById('count').textContent = `${PANEL.total} ${T('acessível(is)', 'accessible')} · ${rows.length} ${T('exibido(s)', 'shown')}`;
  const cards = el('div', { class: 'scards' },
    scard(PANEL.total, T('acessíveis', 'accessible')),
    scard(c.being_calibrated || 0, T('calibrando', 'calibrating'), false, 'being_calibrated'),
    scard(c.validated || 0, T('validados', 'validated'), false, 'validated'),
    scard(c.calibrated || 0, T('calibrados', 'calibrated'), false, 'calibrated'),
    scard(c.needs_recalibration || 0, T('precisa recalibrar', 'needs recalibration'), (c.needs_recalibration || 0) > 0, 'needs_recalibration'),
    scard(c.good_sol_no_tl || 0, T('good sem TL', 'good without TL'), (c.good_sol_no_tl || 0) > 0, 'good_sol_no_tl'),
    scard(c.needs_review || 0, T('precisa revisar', 'needs review'), (c.needs_review || 0) > 0, 'needs_review'));
  // 🕘 lote: recalibrar tudo que precisa (dedup/serialização do servidor tornam o lote seguro)
  const nStale = (c.needs_recalibration || 0);
  if (nStale > 0) {
    const btn = el('button', { class: 'btn', type: 'button', style: 'align-self:center' },
      T('⚙ Recalibrar todos (', '⚙ Recalibrate all (') + nStale + ')');
    btn.onclick = async () => {
      if (!confirm(T(nStale + ' calibração(ões) entrarão na fila dos juízes (pedidos duplicados são deduplicados; um problema por vez por juiz). Continuar?',
        nStale + ' calibration(s) will be queued to the judges (duplicates are deduped; one problem at a time per judge). Continue?'))) return;
      btn.disabled = true; btn.textContent = T('Enviando…', 'Submitting…');
      try {
        const ids = (PANEL.problems || []).filter(p => p.needs_recalibration).map(p => p.id);
        const j = await apiPost('/problems/recalibrate-stale', { ids }, { contest: CONTEST, auth: true });
        btn.textContent = T('Enfileiradas: ', 'Queued: ') + (j.count || 0) + ' ✓';
        setTimeout(loadPanel, 2500);
      } catch (e) {
        alert(T('Falha ao enfileirar: ', 'Failed to queue: ') + (e instanceof ApiError ? e.message : e));
        btn.disabled = false; btn.textContent = T('⚙ Recalibrar todos (', '⚙ Recalibrate all (') + nStale + ')';
      }
    };
    cards.append(btn);
  }
  if (PANEL_FILTER) cards.append(el('span', { class: 'small muted', style: 'align-self:center' },
    T('filtro ativo — clique no card de novo para limpar', 'filter active — click the card again to clear')));

  const pages = Math.max(1, Math.ceil(rows.length / PAGE));
  if (page >= pages) page = 0;
  const slice = rows.slice(page * PAGE, page * PAGE + PAGE);

  const arrow = (key) => PANEL_SORT.key === key ? (PANEL_SORT.dir > 0 ? ' ▲' : ' ▼') : '';
  const th = (label, key) => el('th', { class: 'sortable', onclick: () => setPanelSort(key) }, label + arrow(key));
  const head = el('tr', {}, th(T('Problema', 'Problem'), 'title'), th(T('Autor', 'Author'), 'author'),
    th(T('Validação', 'Validation'), 'validated'), th(T('Calibração', 'Calibration'), 'sev'), el('th', {}, 'Time limits'), th(T('Atualizado', 'Updated'), 'updated'));
  const tb = el('tbody');
  slice.forEach(p => tb.append(el('tr', {},
    el('td', {}, el('a', { href: '#', onclick: (e) => { e.preventDefault(); openDetail(p.id); } }, p.title || p.prob || p.id),
      el('div', { class: 'small muted2' }, p.id)),
    el('td', { class: 'small' }, p.author || '—'),
    el('td', {}, valChip(p)),
    el('td', {}, calibChip(p), reviewChip(p)),
    el('td', { class: 'small', style: 'font-family:var(--mono,monospace)' }, fmtTL(p.time_limits)),
    el('td', { class: 'small muted2' }, p.updated_at ? fmtDate(p.updated_at) : '—'))));

  const list = document.getElementById('list'); list.innerHTML = '';
  list.append(cards, el('table', { class: 'moj' }, el('thead', {}, head), tb));

  const pager = document.getElementById('pager'); pager.innerHTML = '';
  if (pages > 1) {
    pager.append(el('button', { class: 'btn ghost', onclick: () => { if (page > 0) { page--; renderPanel(); } } }, '‹'));
    pager.append(el('span', { class: 'small' }, ` ${T('página', 'page')} ${page + 1} / ${pages} `));
    pager.append(el('button', { class: 'btn ghost', onclick: () => { if (page < pages - 1) { page++; renderPanel(); } } }, '›'));
  }
}

// ---- aba "Análise": panorama de submissões dos meus problemas (cross-contest) ----
async function loadAnalysis() {
  const list = document.getElementById('list'); list.innerHTML = `<span class="small muted">${T('Carregando análise…', 'Loading analysis…')}</span>`;
  document.getElementById('pager').innerHTML = '';
  try { ANALYSIS = await apiGet('/problems/my-stats', { contest: CONTEST, auth: true }); }
  catch (e) { list.innerHTML = `<span class="error-box">${e instanceof ApiError ? e.message : T('Falha ao carregar', 'Failed to load')}</span>`; return; }
  renderAnalysis();   // não zera page (refresh manual preserva ordenação/página)
}
function anaRows() {
  const q = norm(document.getElementById('q').value);
  const rows = (ANALYSIS?.problems || []).filter(p => !q || norm((p.title || '') + ' ' + (p.id || '')).includes(q));
  const k = ANA_SORT.key, d = ANA_SORT.dir;
  const val = (p) => k === 'title' ? norm(p.title || p.id) : (p[k] || 0);
  return rows.slice().sort((a, b) => { const va = val(a), vb = val(b); if (va < vb) return -d; if (va > vb) return d; return 0; });
}
function setAnaSort(key) { if (ANA_SORT.key === key) ANA_SORT.dir *= -1; else ANA_SORT = { key, dir: key === 'title' ? 1 : -1 }; page = 0; renderAnalysis(); }
function renderAnalysis() {
  if (!ANALYSIS) return;
  const t = ANALYSIS.totals || {};
  const list = document.getElementById('list'); list.innerHTML = '';
  document.getElementById('count').textContent = `${t.owned || 0} ${T('problemas seus', 'your problems')} · ${t.with_activity || 0} ${T('com submissões', 'with submissions')}`;
  const rate = (t.attempts > 0) ? Math.round((t.accepts / t.attempts) * 100) : 0;
  const parts = [el('div', { class: 'scards' },
    scard(t.with_activity || 0, T('com submissões', 'with submissions')),
    scard(t.attempts || 0, T('tentativas', 'attempts')),
    scard(t.accepts || 0, T('acertos', 'accepted')),
    scard(rate + '%', T('taxa de acerto', 'acceptance rate')),
    scard(t.solvers || 0, T('resolvedores', 'solvers')))];
  const mp = ANALYSIS.most_popular;
  if (mp) parts.push(el('div', { class: 'scard hl', style: 'margin:.2rem 0 1rem' },
    el('div', { class: 'l' }, T('⭐ Mais popular', '⭐ Most popular')),
    el('div', {}, el('b', {}, mp.title || mp.id), ` — ${mp.attempts} ${T('tentativas', 'attempts')}`)));
  const vd = ANALYSIS.overall_verdicts || [], ld = ANALYSIS.overall_languages || [];
  parts.push(el('div', { style: 'display:grid;grid-template-columns:1fr 1fr;gap:1rem;margin:.2rem 0 1rem' },
    el('div', {}, el('div', { class: 'small muted', style: 'margin-bottom:.3rem' }, T('Veredictos (todos os seus problemas)', 'Verdicts (all your problems)')),
      vd.length ? hBarChart(vd.map(v => ({ label: v.verdict, value: v.count })), { hideZero: true }) : el('div', { class: 'muted small' }, '—')),
    el('div', {}, el('div', { class: 'small muted', style: 'margin-bottom:.3rem' }, T('Linguagens', 'Languages')),
      ld.length ? hBarChart(ld.map(l => ({ label: l.lang, value: l.submissions })), { hideZero: true, maxRows: 10 }) : el('div', { class: 'muted small' }, '—'))));

  const rows = anaRows();
  const pages = Math.max(1, Math.ceil(rows.length / PAGE));
  if (page >= pages) page = 0;
  const slice = rows.slice(page * PAGE, page * PAGE + PAGE);
  const arrow = (k) => ANA_SORT.key === k ? (ANA_SORT.dir > 0 ? ' ▲' : ' ▼') : '';
  const th = (label, k) => el('th', { class: 'sortable', onclick: () => setAnaSort(k) }, label + arrow(k));
  const head = el('tr', {}, th(T('Problema', 'Problem'), 'title'), th(T('Tentativas', 'Attempts'), 'attempts'), th(T('Acertos', 'Accepted'), 'accepts'),
    th(T('Erros', 'Wrong'), 'wrong'), th(T('Taxa', 'Rate'), 'acceptance_rate'), th(T('Usuários', 'Users'), 'distinct_users'), th('Contests', 'contests_count'), el('th', {}, T('Erro mais comum', 'Most common error')));
  const tb = el('tbody');
  slice.forEach(p => {
    const topErr = (p.verdicts || []).filter(v => v.verdict !== 'Accepted')[0];
    tb.append(el('tr', {},
      el('td', {}, el('a', { href: '#', onclick: (e) => { e.preventDefault(); openDetail(p.id); } }, p.title || p.id), el('div', { class: 'small muted2' }, p.id)),
      el('td', {}, String(p.attempts)),
      el('td', {}, String(p.accepts)),
      el('td', {}, String(p.wrong)),
      el('td', { class: 'small' }, Math.round((p.acceptance_rate || 0) * 100) + '%'),
      el('td', { class: 'small' }, String(p.distinct_users)),
      el('td', { class: 'small' }, String(p.contests_count)),
      el('td', { class: 'small muted' }, topErr ? `${topErr.verdict} (${topErr.count})` : '—')));
  });
  parts.push(el('table', { class: 'moj' }, el('thead', {}, head), tb));
  list.append(...parts);

  const pager = document.getElementById('pager'); pager.innerHTML = '';
  if (pages > 1) {
    pager.append(el('button', { class: 'btn ghost', onclick: () => { if (page > 0) { page--; renderAnalysis(); } } }, '‹'));
    pager.append(el('span', { class: 'small' }, ` ${T('página', 'page')} ${page + 1} / ${pages} `));
    pager.append(el('button', { class: 'btn ghost', onclick: () => { if (page < pages - 1) { page++; renderAnalysis(); } } }, '›'));
  }
}

async function loadTab(tab) {
  TAB = tab; page = 0; setActiveTab(tab);
  document.getElementById('detail').style.display = 'none';
  const list = document.getElementById('list'); list.innerHTML = `<span class="small muted">${T('Carregando…', 'Loading…')}</span>`;
  // a busca #q vale TAMBÉM em coleções (129+) e orgs; só o checkbox não se aplica lá
  document.getElementById('toolbar').style.display = '';
  document.getElementById('brokenLabelText').textContent = (tab === 'painel') ? T('só com atenção', 'needs attention only') : T('só não-públicos', 'non-public only');
  document.getElementById('brokenLabel').style.display = (tab === 'analise' || tab === 'collections' || tab === 'orgs') ? 'none' : '';
  document.getElementById('btnRefreshPanel').style.display = (tab === 'painel' || tab === 'analise') ? '' : 'none';
  if (tab === 'painel') { loadPanel(); return; }
  if (tab === 'analise') { loadAnalysis(); return; }
  if (tab === 'orgs') { loadOrgs(); return; }
  try {
    if (tab === 'collections') {
      const j = await apiGet('/problems/collections', { contest: CONTEST, auth: true });
      COLLS = j.collections || []; renderCollections(); return;
    }
    const j = await apiGet('/problems/' + tab, { contest: CONTEST, auth: true });
    ROWS = j.problems || []; renderTable();
  } catch (e) {
    list.innerHTML = `<span class="error-box">${e instanceof ApiError ? e.message : T('Falha ao carregar', 'Failed to load')}</span>`;
  }
}

async function boot() {
  await renderAuthArea(document.getElementById('authArea'), CONTEST, () => location.reload());
  const st = await status(CONTEST);
  loggedIn = !!st.logged_in;
  if (!loggedIn) {
    document.getElementById('needauth').style.display = '';
    document.getElementById('list').innerHTML = '';
    document.getElementById('tabs').style.display = 'none';
    document.getElementById('toolbar').style.display = 'none';
    return;
  }
  // o botão de criar só aparece p/ quem pode criar (mesma regra de criar contest)
  try { CAN_CREATE = !!(await apiGet('/treino/contest-create/permission', { contest: CONTEST, auth: true })).can_create; } catch {}
  if (CAN_CREATE) {
    const impFile = el('input', { type: 'file', accept: '.tar,.gz,.tgz,.tar.gz,.bz2,.zst,.zip' }); impFile.hidden = true;
    impFile.addEventListener('change', (e) => { doImport(e.target.files[0]); e.target.value = ''; });
    document.getElementById('toolbar').append(
      el('a', { class: 'btn', href: '/problemas/editar.html?novo=1', style: 'margin-left:auto' }, T('+ Novo problema', '+ New problem')),
      el('label', { class: 'btn ghost', style: 'cursor:pointer', title: T('Importar um pacote ICPC/Kattis', 'Import an ICPC/Kattis package') }, T('⬆ Importar ICPC', '⬆ Import ICPC'), impFile));
  }
  // guia de criação (página própria) — visível a todo logado, criador ou não
  document.getElementById('toolbar').append(
    el('a', { class: 'btn ghost', href: '/problemas/tutorial.html',
      title: T('Guia: como criar um problema (CLI e web)', 'Guide: how to create a problem (CLI and web)') },
      T('📖 Como criar um problema', '📖 How to create a problem')));
  document.querySelectorAll('#tabs button').forEach(b =>
    b.addEventListener('click', () => loadTab(b.dataset.tab)));
  ['q', 'onlybroken'].forEach(id =>
    document.getElementById(id).addEventListener('input', () => { page = 0;
      if (TAB === 'painel') renderPanel(); else if (TAB === 'analise') renderAnalysis();
      else if (TAB === 'collections') renderCollections(); else if (TAB === 'orgs') renderOrgs();
      else renderTable(); }));
  document.getElementById('btnRefreshPanel').addEventListener('click', () => { if (TAB === 'analise') loadAnalysis(); else loadPanel(); });
  loadTab('painel');
}
boot();
