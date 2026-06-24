// treino/problemas/problemas.js — gestão de problemas (Meus/Compartilhados/Públicos/Coleções).
// Leitura via /problems/* (Bearer). Detalhe mostra validação + enunciado e dispara
// Validar/Publicar e Calibrar (handlers já existentes). Git fica escondido (Gitea atrás).
import { apiGet, apiPost, ApiError, getToken } from '/shared/api.js';
import { status } from '/shared/auth.js';
import { el, renderAuthArea, fmtDate } from '/shared/ui.js';

async function downloadAuthed(path, filename) {
  try {
    const r = await fetch('/api/v1' + path, { headers: { Authorization: 'Bearer ' + getToken(CONTEST) } });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const b = await r.blob(), a = document.createElement('a');
    a.href = URL.createObjectURL(b); a.download = filename; a.click(); URL.revokeObjectURL(a.href);
  } catch (e) { alert('Falha ao baixar: ' + (e.message || e)); }
}

const CONTEST = 'treino';
const PAGE = 50;
let TAB = 'mine', ROWS = [], COLLS = [], page = 0, loggedIn = false;

const norm = (s) => (s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
const b64ToUtf8 = (b) => { try { return new TextDecoder().decode(Uint8Array.from(atob(b), c => c.charCodeAt(0))); } catch { return ''; } };
const pill = (cls, txt) => el('span', { class: 'pill ' + cls }, txt);

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
    stmt.append(el('h4', { style: 'margin:.4rem 0' }, 'Enunciado'),
      el('iframe', { sandbox: '', srcdoc: html }));
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

async function loadTab(tab) {
  TAB = tab; page = 0; setActiveTab(tab);
  document.getElementById('detail').style.display = 'none';
  const list = document.getElementById('list'); list.innerHTML = '<span class="small muted">Carregando…</span>';
  document.getElementById('toolbar').style.display = (tab === 'collections') ? 'none' : '';
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
  if (canCreate) document.getElementById('toolbar').append(
    el('a', { class: 'btn', href: '/problemas/editar.html?novo=1', style: 'margin-left:auto' }, '+ Novo problema'));
  document.querySelectorAll('#tabs button').forEach(b =>
    b.addEventListener('click', () => loadTab(b.dataset.tab)));
  ['q', 'onlybroken'].forEach(id =>
    document.getElementById(id).addEventListener('input', () => { page = 0; if (!TAB.startsWith('collection')) renderTable(); else renderTable(); }));
  loadTab('mine');
}
boot();
