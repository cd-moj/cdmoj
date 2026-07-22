// treino/treino.js — busca de problemas do Treino Livre (tudo local após 1 fetch).
// Navegação por FACETAS client-side: coleções numa ÁRVORE por prefixo (124 nomes viram ~10
// grupos expansíveis — obi → obi2012 → fase2 → junior) e tags num navegador multi-select com
// AND e contagens VIVAS (recalculadas sobre a seleção corrente — o aluno vê o refino real).
import { apiGet } from '/shared/api.js';
import { status } from '/shared/auth.js';
import { el, renderAuthArea } from '/shared/ui.js';
import { T } from '/shared/i18n.js';

const CONTEST = 'treino';
const PAGE = 50;
const TOPTAGS = 24;
let ALL = [], solved = new Set(), attempted = new Set(), page = 0, showTags = false;

// seleção ativa: 1 coleção/grupo (drill-down) + N tags (AND)
let selColl = null;          // {label, colls:Set<nome>|null(substring legado), group:bool}
let selTags = new Set();     // chaves normalizadas (sem #)
let tagShowAll = false;
let TREE = [];               // nós de exibição do topo
let TAGS = new Map();        // chave -> {label, count}
const openNodes = new Set(); // caminhos expandidos da árvore

const norm = (s) => (s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
const tagKey = (t) => norm(t).replace(/^#/, '');
const $ = (id) => document.getElementById(id);

function difficulty(p) {
  const s = p.solved_count || 0, a = p.attempted_count || 0;
  if (a === 0) return { label: T('novo', 'new'), cls: '' };
  const rate = s / a;
  if (rate >= 0.9) return { label: T('muito fácil', 'very easy'), cls: 'diff-easy' };
  if (rate >= 0.7) return { label: T('fácil', 'easy'), cls: 'diff-easy' };
  if (rate >= 0.5) return { label: T('médio', 'medium'), cls: 'diff-med' };
  return { label: T('difícil', 'hard'), cls: 'diff-hard' };
}

// ---- filtro -------------------------------------------------------------------------------
function matchColl(p) {
  if (!selColl) return true;
  const cs = p.collections || [];
  if (selColl.colls) return cs.some((c) => selColl.colls.has(c));
  const sub = norm(selColl.label);                 // legado: ?searchcol= substring digitada
  return cs.some((c) => norm(c).includes(sub));
}
function matchTags(p, except) {
  for (const k of selTags) { if (k === except) continue; if (!p._tk.has(k)) return false; }
  return true;
}
function matchRest(p) {
  const q = norm($('q').value);
  const f = $('filter').value;
  if (q && !norm(p.title).includes(q)) return false;
  if (f === 'solved' && !solved.has(p.id)) return false;
  if (f === 'attempted' && !(attempted.has(p.id) && !solved.has(p.id))) return false;
  return true;
}
const filtered = () => ALL.filter((p) => matchColl(p) && matchTags(p) && matchRest(p));

// ---- árvore de coleções por prefixo -------------------------------------------------------
// tokeniza em -, /, espaço e fronteira letra↔dígito: "obi2012-fase1-junior" -> obi|2012|fase|1|junior
const tokenize = (name) => norm(name).split(/[-\/\s]+/)
  .flatMap((w) => w.split(/(?<=\p{L})(?=\d)|(?<=\d)(?=\p{L})/u)).filter(Boolean);
// corta um nome ORIGINAL no fim do k-ésimo token (rótulo de grupo em fronteira de token,
// preservando caixa/acentos — prefixo por CARACTERES dava "obi20" p/ obi2012..obi2026)
function cutTokens(name, k) {
  let count = 0, i = 0;
  while (i < name.length && count < k) {
    while (i < name.length && /[-\/\s]/.test(name[i])) i++;
    if (i >= name.length) break;
    const dig = /[0-9]/.test(name[i]);
    while (i < name.length && !/[-\/\s]/.test(name[i]) && /[0-9]/.test(name[i]) === dig) i++;
    count++;
  }
  return name.slice(0, i).replace(/[-\/\s]+$/, '');
}
function buildTree() {
  const counts = new Map();                                  // coleção -> nº de problemas
  ALL.forEach((p) => (p.collections || []).forEach((c) => counts.set(c, (counts.get(c) || 0) + 1)));
  const root = { kids: new Map(), colls: [] };
  for (const name of counts.keys()) {
    let cur = root;
    for (const tok of tokenize(name)) {
      if (!cur.kids.has(tok)) cur.kids.set(tok, { kids: new Map(), colls: [] });
      cur = cur.kids.get(tok);
    }
    cur.colls.push(name);
  }
  // problemas distintos de um conjunto de coleções (p/ contagem de grupo = união)
  const probCount = (set) => ALL.reduce((a, p) => a + ((p.collections || []).some((c) => set.has(c)) ? 1 : 0), 0);
  function toDisplay(node, depth) {
    // compressão de caminho: nó de 1 filho sem coleção própria funde com o filho
    while (node.kids.size === 1 && node.colls.length === 0) { node = node.kids.values().next().value; depth++; }
    const kidNodes = [...node.kids.values()].map((k) => toDisplay(k, depth + 1));
    const all = new Set(node.colls);
    kidNodes.forEach((k) => k.colls.forEach((c) => all.add(c)));
    if (all.size === 1) {                                    // subárvore de 1 coleção = folha
      const name = [...all][0];
      return { label: name, colls: all, count: counts.get(name) || 0, kids: [], leaf: true };
    }
    // grupo: rótulo = prefixo do nome mais curto cortado em fronteira de token; filhos =
    // folhas próprias (o "obi2012" que também é coleção) + subgrupos, em ordem natural
    const ownLeaves = node.colls.map((name) => (
      { label: name, colls: new Set([name]), count: counts.get(name) || 0, kids: [], leaf: true }));
    const kids = [...ownLeaves, ...kidNodes]
      .sort((a, b) => a.label.localeCompare(b.label, 'pt', { numeric: true }));
    const sample = [...all].reduce((a, b) => (a.length <= b.length ? a : b));
    return { label: (cutTokens(sample, depth) || sample), colls: all, count: probCount(all), kids, leaf: false };
  }
  const top = toDisplay(root, 0);
  TREE = (top.leaf ? [top] : top.kids).slice()
    .sort((a, b) => b.count - a.count || a.label.localeCompare(b.label, 'pt'));
}
function findNode(pred, nodes = TREE) {
  for (const n of nodes) { if (pred(n)) return n; const k = findNode(pred, n.kids); if (k) return k; }
  return null;
}
function selectNode(n) {
  selColl = { label: n.label, colls: n.colls, group: !n.leaf };
  page = 0; syncURL(); renderAll();
}
function renderTree() {
  const box = $('colTree'); box.innerHTML = '';
  const f = norm($('colFilter').value);
  const matches = (n) => !f || norm(n.label).includes(f) || [...n.colls].some((c) => norm(c).includes(f));
  const isOn = (n) => !!(selColl && selColl.colls && selColl.label === n.label
    && selColl.colls.size === n.colls.size);
  function row(n, path) {
    if (!matches(n)) return null;
    const key = path + '/' + n.label;
    const open = openNodes.has(key) || (f && !norm(n.label).includes(f));  // filtro abre o caminho
    const wrap = el('div', {});
    const caret = n.leaf ? el('span', { class: 'caret' }, ' ')
      : el('span', { class: 'caret', onclick: () => { openNodes.has(key) ? openNodes.delete(key) : openNodes.add(key); renderTree(); } },
          open ? '▾' : '▸');
    const link = el('a', {
      class: 'collection' + (isOn(n) ? ' on' : ''),
      href: '?searchcol=' + encodeURIComponent(n.leaf ? n.label : 'grp:' + n.label),
      title: n.leaf ? n.label : T(`${n.colls.size} coleções`, `${n.colls.size} collections`),
      onclick: (e) => { e.preventDefault(); isOn(n) ? clearColl() : selectNode(n); },
    }, `${n.label} (${n.count})`);
    wrap.append(el('div', { class: 'node' }, caret, link,
      n.leaf ? null : el('span', { class: 'small muted' }, ` ${n.colls.size} ${T('coleções', 'collections')}`)));
    if (!n.leaf && open) {
      const kids = el('div', { class: 'kids' });
      n.kids.forEach((k) => { const r = row(k, key); if (r) kids.append(r); });
      wrap.append(kids);
    }
    return wrap;
  }
  let any = false;
  TREE.forEach((n) => { const r = row(n, ''); if (r) { box.append(r); any = true; } });
  if (!any) box.append(el('span', { class: 'muted' }, T('nenhuma coleção casa com o filtro.', 'no collection matches the filter.')));
}
function clearColl() { selColl = null; page = 0; syncURL(); renderAll(); }

// ---- navegador de tags --------------------------------------------------------------------
function buildTags() {
  TAGS = new Map();
  ALL.forEach((p) => {
    p._tk = new Set((p.tags || []).map(tagKey));
    (p.tags || []).forEach((t) => {
      const k = tagKey(t);
      if (!TAGS.has(k)) TAGS.set(k, { label: String(t), count: 0 });
      TAGS.get(k).count++;
    });
  });
}
function renderTags() {
  const box = $('tagCloud'); box.innerHTML = '';
  const f = norm($('tagFilter').value);
  // contagem VIVA: quantos problemas da seleção corrente têm cada tag (a própria tag não
  // se auto-exclui do AND: com #grafos ativo, #bfs mostra |grafos ∧ bfs| — o refino real)
  const base = ALL.filter((p) => matchColl(p) && matchRest(p));
  const live = new Map();
  base.forEach((p) => { if (!matchTags(p)) return; p._tk.forEach((k) => live.set(k, (live.get(k) || 0) + 1)); });
  const entries = [...TAGS.entries()]
    .filter(([k, v]) => !f || norm(v.label).includes(f) || k.includes(f))
    .map(([k, v]) => ({ k, label: v.label, live: live.get(k) || 0, total: v.count }))
    .sort((a, b) => (b.live - a.live) || (b.total - a.total) || a.label.localeCompare(b.label, 'pt'));
  const selFirst = entries.filter((e) => selTags.has(e.k));
  let rest = entries.filter((e) => !selTags.has(e.k));
  const hasMore = !tagShowAll && rest.length > TOPTAGS;
  if (!tagShowAll) rest = rest.slice(0, TOPTAGS);
  const pill = (e) => el('a', {
    class: 'tag' + (selTags.has(e.k) ? ' on' : '') + (!e.live && !selTags.has(e.k) ? ' dim' : ''),
    href: '?searchtag=' + encodeURIComponent(e.k),
    onclick: (ev) => { ev.preventDefault(); toggleTag(e.k); },
  }, `${e.label} (${e.live})`);
  selFirst.forEach((e) => box.append(pill(e)));
  rest.forEach((e) => box.append(pill(e)));
  if (hasMore) box.append(el('a', {
    class: 'tag', style: 'background:#fff;border:1px dashed var(--line);color:var(--muted)',
    onclick: () => { tagShowAll = true; renderTags(); },
  }, T(`mostrar todas (${entries.length}) ▾`, `show all (${entries.length}) ▾`)));
  else if (tagShowAll && entries.length > TOPTAGS) box.append(el('a', {
    class: 'tag', style: 'background:#fff;border:1px dashed var(--line);color:var(--muted)',
    onclick: () => { tagShowAll = false; renderTags(); },
  }, T('mostrar menos ▴', 'show fewer ▴')));
  if (!entries.length) box.append(el('span', { class: 'muted small' }, T('nenhuma tag casa com o filtro.', 'no tag matches the filter.')));
}
function toggleTag(k) {
  selTags.has(k) ? selTags.delete(k) : selTags.add(k);
  page = 0; syncURL(); renderAll();
}

// ---- chips de filtros ativos + URL --------------------------------------------------------
function renderActive() {
  const box = $('active'); box.innerHTML = '';
  const anyF = selColl || selTags.size || $('q').value.trim();
  if (!anyF) return;
  if (selColl) box.append(el('span', { class: 'collection on', onclick: clearColl },
    `📚 ${selColl.label}`, el('span', { class: 'chip-x' }, '×')));
  selTags.forEach((k) => box.append(el('span', { class: 'tag on', onclick: () => toggleTag(k) },
    (TAGS.get(k) || { label: '#' + k }).label, el('span', { class: 'chip-x' }, '×'))));
  if ($('q').value.trim()) box.append(el('span', { class: 'tag', onclick: () => { $('q').value = ''; page = 0; syncURL(); renderAll(); } },
    `“${$('q').value.trim()}”`, el('span', { class: 'chip-x' }, '×')));
  box.append(el('button', { class: 'btn ghost', style: 'padding:.15rem .6rem;font-size:.8rem', onclick: () => {
    selColl = null; selTags.clear(); $('q').value = ''; $('colFilter').value = ''; $('tagFilter').value = '';
    page = 0; syncURL(); renderAll();
  } }, T('limpar tudo', 'clear all')));
}
function syncURL() {
  const sp = new URLSearchParams();
  if (selColl) sp.set('searchcol', selColl.colls && selColl.group ? 'grp:' + selColl.label : selColl.label);
  if (selTags.size) sp.set('searchtag', [...selTags].join(','));
  if ($('q').value.trim()) sp.set('q', $('q').value.trim());
  history.replaceState(null, '', sp.toString() ? '?' + sp.toString() : location.pathname);
}
function applyURL() {
  const sp = new URLSearchParams(location.search);
  if (sp.get('q')) $('q').value = sp.get('q');
  (sp.get('searchtag') || '').split(',').map(tagKey).filter(Boolean)
    .forEach((k) => { if (TAGS.has(k)) selTags.add(k); });
  const sc = sp.get('searchcol') || '';
  if (sc.startsWith('grp:')) {
    const n = findNode((x) => !x.leaf && x.label === sc.slice(4));
    if (n) selColl = { label: n.label, colls: n.colls, group: true };
  } else if (sc) {
    const n = findNode((x) => x.leaf && x.label === sc);
    if (n) selColl = { label: n.label, colls: n.colls, group: false };
    else selColl = { label: sc, colls: null, group: false };   // legado: substring digitada
  }
}

// ---- tabela -------------------------------------------------------------------------------
function render() {
  const rows = filtered();
  $('count').textContent = `${rows.length} ${T('problema(s)', 'problem(s)')}`;
  const pages = Math.max(1, Math.ceil(rows.length / PAGE));
  if (page >= pages) page = 0;
  const slice = rows.slice(page * PAGE, page * PAGE + PAGE);

  const list = $('list');
  list.innerHTML = '';
  const tbl = el('table', { class: 'moj' },
    el('thead', {}, el('tr', {},
      el('th', {}, T('Problema', 'Problem')),
      el('th', {}, T('Coleções', 'Collections')),
      ...(showTags ? [el('th', {}, T('Tags', 'Tags'))] : []),
      el('th', {}, T('Dificuldade (acertos)', 'Difficulty (solves)')),
      el('th', {}, T('Status', 'Status')))));
  const tb = el('tbody');
  slice.forEach((p) => {
    const d = difficulty(p);
    const st = solved.has(p.id) ? T('✓ resolvido', '✓ solved') : (attempted.has(p.id) ? T('… tentado', '… attempted') : '');
    const cells = [
      el('td', {}, el('a', { href: '/treino/problema/?id=' + encodeURIComponent(p.id) }, p.title || p.id)),
      el('td', {}, (p.collections || []).map((c) => el('a', {
        class: 'collection', href: '?searchcol=' + encodeURIComponent(String(c)),
        onclick: (e) => { e.preventDefault(); const n = findNode((x) => x.leaf && x.label === String(c));
          selColl = n ? { label: n.label, colls: n.colls, group: false } : { label: String(c), colls: new Set([String(c)]), group: false };
          page = 0; syncURL(); renderAll(); },
      }, c))),
    ];
    if (showTags) cells.push(el('td', {}, (p.tags || []).map((t) => el('a', {
      class: 'tag' + (selTags.has(tagKey(t)) ? ' on' : ''),
      href: '?searchtag=' + encodeURIComponent(tagKey(t)),
      onclick: (e) => { e.preventDefault(); toggleTag(tagKey(t)); },
    }, t))));
    cells.push(el('td', {}, el('span', { class: 'diff ' + d.cls },
      d.label + (p.attempted_count ? ` (${p.solved_count}/${p.attempted_count})` : ''))));
    cells.push(el('td', { class: solved.has(p.id) ? 'v-ok' : '' }, st));
    tb.append(el('tr', {}, ...cells));
  });
  tbl.append(tb); list.append(tbl);

  const pager = $('pager'); pager.innerHTML = '';
  if (pages > 1) {
    pager.append(el('button', { class: 'btn ghost', onclick: () => { if (page > 0) { page--; render(); } } }, '‹'));
    pager.append(el('span', { class: 'small' }, ` ${T('página', 'page')} ${page + 1} / ${pages} `));
    pager.append(el('button', { class: 'btn ghost', onclick: () => { if (page < pages - 1) { page++; render(); } } }, '›'));
  }
}
function renderAll() { render(); renderTree(); renderTags(); renderActive(); }

async function loadSolve() {
  const st = await status(CONTEST);
  const fsel = $('filter');
  fsel.disabled = !st.logged_in;
  if (!st.logged_in) return;
  try {
    const j = await apiGet('/treino/solvetry', { contest: CONTEST, auth: true });
    solved = new Set(j.solved || []); attempted = new Set(j.attempted || []);
  } catch {}
}

async function boot() {
  const authArea = $('authArea');
  await renderAuthArea(authArea, CONTEST, async () => { await loadSolve(); renderAll(); });
  if (window.innerWidth <= 820) $('explorer').removeAttribute('open');   // mobile nasce colapsado

  try {
    const j = await apiGet('/treino/problems', { contest: CONTEST });
    ALL = Array.isArray(j) ? j : (j.problems || j.data || []);
  } catch (e) {
    $('list').innerHTML = `<span class="error-box">${T('Falha ao carregar problemas.', 'Failed to load problems.')}</span>`;
    return;
  }
  buildTags(); buildTree(); applyURL();
  await loadSolve();
  $('q').addEventListener('input', () => { page = 0; syncURL(); render(); renderActive(); });
  $('filter').addEventListener('input', () => { page = 0; render(); renderTags(); });
  $('colFilter').addEventListener('input', renderTree);
  $('tagFilter').addEventListener('input', renderTags);
  $('toggleTags').addEventListener('click', () => {
    showTags = !showTags;
    $('toggleTags').textContent = showTags ? T('Ocultar tags', 'Hide tags') : T('Mostrar tags', 'Show tags');
    render();
  });
  renderAll();
}
boot();
