// treino/problemas/problemas.js — gestão de problemas (Meus/Compartilhados/Públicos/Coleções).
// Leitura via /problems/* (Bearer). Detalhe mostra validação + enunciado e dispara
// Validar/Publicar e Calibrar (handlers já existentes). Git fica escondido (Gitea atrás).
import { apiGet, apiPost, ApiError, getToken } from '/shared/api.js';
import { status, fileToBase64 } from '/shared/auth.js';
import { el, renderAuthArea, fmtDate } from '/shared/ui.js';
import { hBarChart } from '/lib/charts.js';

async function downloadAuthed(path, filename) {
  try {
    const r = await fetch('/api/v1' + path, { headers: { Authorization: 'Bearer ' + getToken(CONTEST) } });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const b = await r.blob(), a = document.createElement('a');
    a.href = URL.createObjectURL(b); a.download = filename; a.click(); URL.revokeObjectURL(a.href);
  } catch (e) { alert('Falha ao baixar: ' + (e.message || e)); }
}
async function doImport(file) {
  if (!file) return;
  let mine = [];
  try { mine = ((await apiGet('/problems/repos', { contest: CONTEST, auth: true })).repos || []).filter(r => r.mine).map(r => r.repo); } catch {}
  const repo = prompt('Importar para qual diretório (pasta)?' + (mine.length ? '\nSeus: ' + mine.join(', ') : '\n(crie um primeiro em “+ Novo problema”)'), mine[0] || '');
  if (!repo) return;
  try {
    const tar_b64 = await fileToBase64(file);
    const j = await apiPost('/problems/import', { repo: repo.trim(), tar_b64 }, { contest: CONTEST, auth: true });
    location.href = '/problemas/editar.html?id=' + encodeURIComponent(j.id);
  } catch (e) { alert('Falha ao importar: ' + (e instanceof ApiError ? e.message : (e.message || e))); }
}

const CONTEST = 'treino';
const PAGE = 50;
let TAB = 'painel', ROWS = [], COLLS = [], page = 0, loggedIn = false;
let PANEL = null, PANEL_SORT = { key: 'sev', dir: -1 };
let ANALYSIS = null, ANA_SORT = { key: 'attempts', dir: -1 };

const norm = (s) => (s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
const b64ToUtf8 = (b) => { try { return new TextDecoder().decode(Uint8Array.from(atob(b), c => c.charCodeAt(0))); } catch { return ''; } };
const pill = (cls, txt) => el('span', { class: 'pill ' + cls }, txt);

// ---- painel de status (aba "Painel") ----
const scard = (n, l, hl) => el('div', { class: 'scard' + (hl ? ' hl' : '') }, el('div', { class: 'n' }, String(n)), el('div', { class: 'l' }, l));
const fmtTL = (tl) => { const e = Object.entries(tl || {}).filter(([k]) => k !== 'default'); return e.length ? e.map(([k, v]) => `${k} ${(+v).toFixed(3)}s`).join(' · ') : '—'; };
const sevOf = (p) => p.error ? 3 : p.needs_recalibration ? 2 : p.being_calibrated ? 1 : 0;
const valChip = (p) => p.validated === 'ok' ? pill('ok', 'validado') : p.validated === 'error' ? pill('no', 'reprovado') : pill('mut', 'não validado');
const calibChip = (p) => p.being_calibrated ? pill('warn', 'calibrando…') : p.needs_recalibration ? pill('warn', 'precisa recalibrar') : p.calibrated ? pill('ok', 'calibrado') : pill('mut', 'sem calibração');

function stateBadges(p) {
  const out = [];
  out.push(p.public ? pill('ok', 'público') : pill('warn', 'rascunho'));
  if (!p.html) out.push(pill('no', 'sem HTML'));
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
    `${rows.length} problema(s)` + (isMine ? ` · ${rows.filter(r => r.claimed).length} reivindicados, ${rows.filter(r => !r.claimed).length} prováveis` : '');
  const pages = Math.max(1, Math.ceil(rows.length / PAGE));
  if (page >= pages) page = 0;
  const slice = rows.slice(page * PAGE, page * PAGE + PAGE);

  const head = el('tr', {},
    el('th', {}, 'Problema'),
    el('th', {}, 'Autor'),
    el('th', {}, 'Coleção'),
    ...(isMine ? [el('th', {}, 'Posse')] : []),
    el('th', {}, 'Estado'),
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
    if (isMine) cells.push(el('td', {}, p.claimed ? pill('ok', 'meu') : pill('mut', 'provável')));
    cells.push(el('td', {}, ...stateBadges(p)));
    cells.push(el('td', { class: 'row', style: 'gap:.3rem' },
      el('button', { class: 'btn ghost', onclick: () => openDetail(p.id) }, 'Ver'),
      el('a', { class: 'btn ghost', href: '/problemas/editar.html?id=' + encodeURIComponent(p.id) }, 'Editar')));
    tb.append(el('tr', {}, ...cells));
  });

  const list = document.getElementById('list');
  list.innerHTML = '';
  list.append(el('table', { class: 'moj' }, el('thead', {}, head), tb));

  const pager = document.getElementById('pager'); pager.innerHTML = '';
  if (pages > 1) {
    pager.append(el('button', { class: 'btn ghost', onclick: () => { if (page > 0) { page--; renderTable(); } } }, '‹'));
    pager.append(el('span', { class: 'small' }, ` página ${page + 1} / ${pages} `));
    pager.append(el('button', { class: 'btn ghost', onclick: () => { if (page < pages - 1) { page++; renderTable(); } } }, '›'));
  }
}

function renderCollections() {
  document.getElementById('count').textContent = `${COLLS.length} coleção(ões)`;
  document.getElementById('pager').innerHTML = '';
  const wrap = el('div', { class: 'colls' });
  COLLS.forEach(c => {
    const allPub = c.public === c.count;
    wrap.append(el('div', { class: 'coll', onclick: () => openCollection(c.name) },
      el('b', {}, c.name),
      el('span', { class: 'small' }, `${c.count} problemas · `),
      c.public === 0 ? pill('no', '0 públicos') : (allPub ? pill('ok', 'todos públicos') : pill('warn', `${c.public}/${c.count} públicos`))));
  });
  const list = document.getElementById('list'); list.innerHTML = ''; list.append(wrap);
}

async function openCollection(name) {
  setActiveTab(null);
  document.getElementById('q').value = '';
  const list = document.getElementById('list'); list.innerHTML = '<span class="small muted">Carregando…</span>';
  try {
    const j = await apiGet('/problems/collection?name=' + encodeURIComponent(name), { contest: CONTEST, auth: true });
    ROWS = j.problems || []; TAB = 'collection:' + name; page = 0;
    document.getElementById('list').scrollIntoView({ behavior: 'smooth', block: 'start' });
    renderTable();
    document.getElementById('count').textContent =
      `coleção “${name}” · ${ROWS.length} problemas · ${ROWS.filter(r => r.public).length} públicos`;
  } catch (e) { list.innerHTML = `<span class="error-box">${e.message}</span>`; }
}

async function openDetail(id) {
  const d = document.getElementById('detail');
  d.style.display = ''; d.innerHTML = '<span class="small muted">Carregando detalhe…</span>';
  d.scrollIntoView({ behavior: 'smooth', block: 'start' });
  let j;
  try { j = await apiGet('/problems/get?id=' + encodeURIComponent(id), { contest: CONTEST, auth: true }); }
  catch (e) { d.innerHTML = `<span class="error-box">${e.message}</span>`; return; }

  const head = el('div', { class: 'row', style: 'justify-content:space-between;align-items:flex-start;gap:1rem' },
    el('div', {},
      el('h3', { style: 'margin:0' }, j.title || j.prob || j.id),
      el('div', { class: 'small muted2' }, j.id),
      el('div', { class: 'small' }, 'autor: ', j.author || '—',
        j.owner ? el('span', {}, ' · dono: ', el('b', {}, j.owner)) : '',
        (j.collaborators && j.collaborators.length) ? el('span', {}, ' · compartilhado: ' + j.collaborators.join(', ')) : ''),
      el('div', { class: 'row', style: 'gap:.4rem;margin-top:.3rem' }, ...stateBadges(j),
        ...(j.tags || []).map(t => el('span', { class: 'tag' }, t)))),
    el('div', { class: 'row', style: 'gap:.4rem' },
      el('a', { class: 'btn ghost', href: '/problemas/editar.html?id=' + encodeURIComponent(id) }, 'Editar'),
      el('button', { class: 'btn', id: 'btnPub', onclick: () => doAction('publish', id) }, 'Validar & Publicar'),
      el('button', { class: 'btn ghost', id: 'btnCal', onclick: () => doAction('request-calibration', id) }, 'Calibrar'),
      el('button', { class: 'btn ghost', title: 'Baixar como pacote ICPC/Kattis', onclick: () => downloadAuthed('/problems/export?id=' + encodeURIComponent(id), id.split('#').pop() + '.icpc.tar.gz') }, '⬇ ICPC')));

  const v = j.validation;
  const vbox = el('div', { style: 'margin-top:.6rem' });
  vbox.append(el('h4', { style: 'margin:.4rem 0' }, 'Validação ',
    v ? (v.ok ? pill('ok', 'aprovado') : pill('no', 'reprovado')) : pill('mut', 'não validado')));
  if (v) {
    if (v.at) vbox.append(el('div', { class: 'small muted2' }, 'em ' + fmtDate(v.at)));
    const ul = el('ul', { class: 'checks' });
    (v.checks || []).forEach(c => ul.append(el('li', {},
      el('span', { class: 'k' }, (c.ok ? '✓ ' : '✗ ') + c.name), c.detail ? el('span', { class: 'small muted2' }, c.detail) : '')));
    vbox.append(ul);
    if (v.render_warnings) vbox.append(el('div', { class: 'small' }, pill('warn', 'avisos de render'), ' ' + v.render_warnings));
  } else {
    vbox.append(el('div', { class: 'small muted' }, 'Clique em “Validar & Publicar” para rodar o portão de qualidade num juiz.'));
  }

  const stmt = el('div', { style: 'margin-top:.6rem' });
  if (j.statement_html_b64) {
    const html = b64ToUtf8(j.statement_html_b64);
    // mesmo render dos demais lugares: extrai o body e injeta em .statement-content (CSS unificado
    // do tema) — NÃO usa iframe (que mostrava o CSS embutido do pandoc, divergente)
    const sc = el('div', { class: 'statement-content' });
    try { const d = new DOMParser().parseFromString(html, 'text/html'); sc.innerHTML = d.body ? d.body.innerHTML : html; } catch { sc.innerHTML = html; }
    stmt.append(el('h4', { style: 'margin:.4rem 0' }, 'Enunciado'), sc);
  } else {
    stmt.append(el('div', { class: 'small muted' }, 'Sem HTML publicado ainda (não está no treino).'));
  }

  d.innerHTML = ''; d.append(head, vbox, stmt);
}

async function doAction(action, id) {
  const btn = document.getElementById(action === 'publish' ? 'btnPub' : 'btnCal');
  const old = btn.textContent; btn.disabled = true; btn.textContent = 'Enviando…';
  try {
    const j = await apiPost('/problems/' + action, { id }, { contest: CONTEST, auth: true });
    btn.textContent = (action === 'publish' ? 'Enfileirado p/ validação' : 'Calibração enfileirada') + ' ✓';
  } catch (e) {
    btn.textContent = old; btn.disabled = false;
    alert((e instanceof ApiError ? e.message : 'Falha') + (e.code ? ` (${e.code})` : ''));
  }
}

function setActiveTab(tab) {
  document.querySelectorAll('#tabs button').forEach(b =>
    b.classList.toggle('active', b.dataset.tab === tab));
}

async function loadPanel() {
  const list = document.getElementById('list'); list.innerHTML = '<span class="small muted">Carregando painel…</span>';
  document.getElementById('pager').innerHTML = '';
  try {
    PANEL = await apiGet('/problems/status', { contest: CONTEST, auth: true });
  } catch (e) {
    list.innerHTML = `<span class="error-box">${e instanceof ApiError ? e.message : 'Falha ao carregar'}</span>`; return;
  }
  renderPanel();   // NÃO zera page: refresh manual preserva ordenação/filtro/página (renderPanel clampa)
}

// filtra (#q + "só com atenção") e ordena as linhas do painel conforme PANEL_SORT
function panelRows() {
  const q = norm(document.getElementById('q').value);
  const attn = document.getElementById('onlybroken').checked;
  const rows = (PANEL?.problems || []).filter(p => {
    if (attn && !(p.error || p.needs_recalibration)) return false;
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
  document.getElementById('count').textContent = `${PANEL.total} acessível(is) · ${rows.length} exibido(s)`;
  const cards = el('div', { class: 'scards' },
    scard(PANEL.total, 'acessíveis'),
    scard(c.being_calibrated || 0, 'calibrando'),
    scard(c.validated || 0, 'validados'),
    scard(c.calibrated || 0, 'calibrados'),
    scard(c.needs_recalibration || 0, 'precisa recalibrar', (c.needs_recalibration || 0) > 0),
    scard(c.errors || 0, 'com erro', (c.errors || 0) > 0));

  const pages = Math.max(1, Math.ceil(rows.length / PAGE));
  if (page >= pages) page = 0;
  const slice = rows.slice(page * PAGE, page * PAGE + PAGE);

  const arrow = (key) => PANEL_SORT.key === key ? (PANEL_SORT.dir > 0 ? ' ▲' : ' ▼') : '';
  const th = (label, key) => el('th', { class: 'sortable', onclick: () => setPanelSort(key) }, label + arrow(key));
  const head = el('tr', {}, th('Problema', 'title'), th('Autor', 'author'),
    th('Validação', 'validated'), th('Calibração', 'sev'), el('th', {}, 'Time limits'), th('Atualizado', 'updated'));
  const tb = el('tbody');
  slice.forEach(p => tb.append(el('tr', {},
    el('td', {}, el('a', { href: '#', onclick: (e) => { e.preventDefault(); openDetail(p.id); } }, p.title || p.prob || p.id),
      el('div', { class: 'small muted2' }, p.id)),
    el('td', { class: 'small' }, p.author || '—'),
    el('td', {}, valChip(p)),
    el('td', {}, calibChip(p), ...(p.error && (p.error_reasons || []).length ? [el('span', { class: 'small muted2', style: 'margin-left:.35rem' }, p.error_reasons.join(', '))] : [])),
    el('td', { class: 'small', style: 'font-family:var(--mono,monospace)' }, fmtTL(p.time_limits)),
    el('td', { class: 'small muted2' }, p.updated_at ? fmtDate(p.updated_at) : '—'))));

  const list = document.getElementById('list'); list.innerHTML = '';
  list.append(cards, el('table', { class: 'moj' }, el('thead', {}, head), tb));

  const pager = document.getElementById('pager'); pager.innerHTML = '';
  if (pages > 1) {
    pager.append(el('button', { class: 'btn ghost', onclick: () => { if (page > 0) { page--; renderPanel(); } } }, '‹'));
    pager.append(el('span', { class: 'small' }, ` página ${page + 1} / ${pages} `));
    pager.append(el('button', { class: 'btn ghost', onclick: () => { if (page < pages - 1) { page++; renderPanel(); } } }, '›'));
  }
}

// ---- aba "Análise": panorama de submissões dos meus problemas (cross-contest) ----
async function loadAnalysis() {
  const list = document.getElementById('list'); list.innerHTML = '<span class="small muted">Carregando análise…</span>';
  document.getElementById('pager').innerHTML = '';
  try { ANALYSIS = await apiGet('/problems/my-stats', { contest: CONTEST, auth: true }); }
  catch (e) { list.innerHTML = `<span class="error-box">${e instanceof ApiError ? e.message : 'Falha ao carregar'}</span>`; return; }
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
  document.getElementById('count').textContent = `${t.owned || 0} problemas seus · ${t.with_activity || 0} com submissões`;
  const rate = (t.attempts > 0) ? Math.round((t.accepts / t.attempts) * 100) : 0;
  const parts = [el('div', { class: 'scards' },
    scard(t.with_activity || 0, 'com submissões'),
    scard(t.attempts || 0, 'tentativas'),
    scard(t.accepts || 0, 'acertos'),
    scard(rate + '%', 'taxa de acerto'),
    scard(t.solvers || 0, 'resolvedores'))];
  const mp = ANALYSIS.most_popular;
  if (mp) parts.push(el('div', { class: 'scard hl', style: 'margin:.2rem 0 1rem' },
    el('div', { class: 'l' }, '⭐ Mais popular'),
    el('div', {}, el('b', {}, mp.title || mp.id), ` — ${mp.attempts} tentativas`)));
  const vd = ANALYSIS.overall_verdicts || [], ld = ANALYSIS.overall_languages || [];
  parts.push(el('div', { style: 'display:grid;grid-template-columns:1fr 1fr;gap:1rem;margin:.2rem 0 1rem' },
    el('div', {}, el('div', { class: 'small muted', style: 'margin-bottom:.3rem' }, 'Veredictos (todos os seus problemas)'),
      vd.length ? hBarChart(vd.map(v => ({ label: v.verdict, value: v.count })), { hideZero: true }) : el('div', { class: 'muted small' }, '—')),
    el('div', {}, el('div', { class: 'small muted', style: 'margin-bottom:.3rem' }, 'Linguagens'),
      ld.length ? hBarChart(ld.map(l => ({ label: l.lang, value: l.submissions })), { hideZero: true, maxRows: 10 }) : el('div', { class: 'muted small' }, '—'))));

  const rows = anaRows();
  const pages = Math.max(1, Math.ceil(rows.length / PAGE));
  if (page >= pages) page = 0;
  const slice = rows.slice(page * PAGE, page * PAGE + PAGE);
  const arrow = (k) => ANA_SORT.key === k ? (ANA_SORT.dir > 0 ? ' ▲' : ' ▼') : '';
  const th = (label, k) => el('th', { class: 'sortable', onclick: () => setAnaSort(k) }, label + arrow(k));
  const head = el('tr', {}, th('Problema', 'title'), th('Tentativas', 'attempts'), th('Acertos', 'accepts'),
    th('Erros', 'wrong'), th('Taxa', 'acceptance_rate'), th('Usuários', 'distinct_users'), th('Contests', 'contests_count'), el('th', {}, 'Erro mais comum'));
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
    pager.append(el('span', { class: 'small' }, ` página ${page + 1} / ${pages} `));
    pager.append(el('button', { class: 'btn ghost', onclick: () => { if (page < pages - 1) { page++; renderAnalysis(); } } }, '›'));
  }
}

async function loadTab(tab) {
  TAB = tab; page = 0; setActiveTab(tab);
  document.getElementById('detail').style.display = 'none';
  const list = document.getElementById('list'); list.innerHTML = '<span class="small muted">Carregando…</span>';
  document.getElementById('toolbar').style.display = (tab === 'collections') ? 'none' : '';
  document.getElementById('brokenLabelText').textContent = (tab === 'painel') ? 'só com atenção' : 'só não-públicos';
  document.getElementById('brokenLabel').style.display = (tab === 'analise') ? 'none' : '';
  document.getElementById('btnRefreshPanel').style.display = (tab === 'painel' || tab === 'analise') ? '' : 'none';
  if (tab === 'painel') { loadPanel(); return; }
  if (tab === 'analise') { loadAnalysis(); return; }
  try {
    if (tab === 'collections') {
      const j = await apiGet('/problems/collections', { contest: CONTEST, auth: true });
      COLLS = j.collections || []; renderCollections(); return;
    }
    const j = await apiGet('/problems/' + tab, { contest: CONTEST, auth: true });
    ROWS = j.problems || []; renderTable();
  } catch (e) {
    list.innerHTML = `<span class="error-box">${e instanceof ApiError ? e.message : 'Falha ao carregar'}</span>`;
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
  let canCreate = false;
  try { canCreate = !!(await apiGet('/treino/contest-create/permission', { contest: CONTEST, auth: true })).can_create; } catch {}
  if (canCreate) {
    const impFile = el('input', { type: 'file', accept: '.tar,.gz,.tgz,.tar.gz,.bz2,.zst,.zip' }); impFile.hidden = true;
    impFile.addEventListener('change', (e) => { doImport(e.target.files[0]); e.target.value = ''; });
    document.getElementById('toolbar').append(
      el('a', { class: 'btn', href: '/problemas/editar.html?novo=1', style: 'margin-left:auto' }, '+ Novo problema'),
      el('label', { class: 'btn ghost', style: 'cursor:pointer', title: 'Importar um pacote ICPC/Kattis' }, '⬆ Importar ICPC', impFile));
  }
  document.querySelectorAll('#tabs button').forEach(b =>
    b.addEventListener('click', () => loadTab(b.dataset.tab)));
  ['q', 'onlybroken'].forEach(id =>
    document.getElementById(id).addEventListener('input', () => { page = 0; if (TAB === 'painel') renderPanel(); else if (TAB === 'analise') renderAnalysis(); else renderTable(); }));
  document.getElementById('btnRefreshPanel').addEventListener('click', () => { if (TAB === 'analise') loadAnalysis(); else loadPanel(); });
  loadTab('painel');
}
boot();
