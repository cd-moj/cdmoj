// treino/treino.js — Treino Livre em DOIS estados client-side (tudo local após 1 fetch):
//   HUB (default): omnibusca com sugestões agrupadas + "Para você" (continue/sugestão) +
//     carrossel de coleções em destaque + "mais enviados na semana".
//   BUSCA AVANÇADA (?browse=1 ou qualquer filtro): trilho de facetas (status, dificuldade,
//     árvore de coleções com MULTI-seleção/checkbox, tags AND com contagens vivas) + tabela
//     sempre visível com ordenação e paginação.
// Coleções: seleção é um CONJUNTO (OR entre coleções; grupo marca a subárvore inteira).
// A URL ?searchcol= aceita CSV (itens URI-encoded); link antigo de 1 coleção segue valendo.
import { apiGet, apiGetText } from '/shared/api.js';
import { status } from '/shared/auth.js';
import { el, renderAuthArea } from '/shared/ui.js';
import { T } from '/shared/i18n.js';

const CONTEST = 'treino';
const PAGE = 50;
const TOPTAGS = 20;
const CAROUSEL_N = 12;
let ALL = [], solved = new Set(), attempted = new Set(), page = 0, showTags = false;
let LOGGED = false;
let HIST = null;             // history-full parseado (só logado): [{probid, verdict, epoch}]
let MODE = 'hub';            // 'hub' | 'browse'
let BROWSE_FLAG = false;     // browse aberto sem nenhum filtro (?browse=1)

// seleção ativa (multi-facetas)
let selColls = new Map();    // key -> {label, colls:Set<nome>|null(substring legado), group}
let selTags = new Set();     // chaves normalizadas (sem #)
let selDiffs = new Set();    // chaves de dificuldade: veasy easy med hard new
let FSTATUS = 'all';         // all | unsolved | solved | attempted
let SORT = 'solved';         // solved (mais resolvidos) | az | diff
let tagShowAll = false;
let TREE = [];               // nós de exibição do topo
let TAGS = new Map();        // chave -> {label, count}
let COLLN = 0;               // nº de coleções distintas
const openNodes = new Set(); // caminhos expandidos da árvore
let TRENDING = null;         // top-N por submissões na semana (null=carregando; []=vazio/falha)

const hasFilter = () => !!(selColls.size || selTags.size || selDiffs.size
  || $('q').value.trim() || FSTATUS !== 'all');

const norm = (s) => (s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
const tagKey = (t) => norm(t).replace(/^#/, '');
const $ = (id) => document.getElementById(id);

// ---- dificuldade (derivada da taxa de acerto; sem attempted = "novo") ---------------------
const DIFFS = [
  { key: 'veasy', pt: 'muito fácil', en: 'very easy', cls: 'diff-easy' },
  { key: 'easy',  pt: 'fácil',       en: 'easy',      cls: 'diff-easy' },
  { key: 'med',   pt: 'médio',       en: 'medium',    cls: 'diff-med' },
  { key: 'hard',  pt: 'difícil',     en: 'hard',      cls: 'diff-hard' },
  { key: 'new',   pt: 'novo',        en: 'new',       cls: '' },
];
const diffByKey = (k) => DIFFS.find((d) => d.key === k);
function diffKey(p) {
  const s = p.solved_count || 0, a = p.attempted_count || 0;
  if (a === 0) return 'new';
  const rate = s / a;
  return rate >= 0.9 ? 'veasy' : rate >= 0.7 ? 'easy' : rate >= 0.5 ? 'med' : 'hard';
}
function difficulty(p) {
  const d = diffByKey(diffKey(p));
  return { key: d.key, label: T(d.pt, d.en), cls: d.cls };
}

// ---- filtros ------------------------------------------------------------------------------
function matchColl(p) {
  if (!selColls.size) return true;
  const cs = p.collections || [];
  for (const e of selColls.values()) {
    if (e.colls) { if (cs.some((c) => e.colls.has(c))) return true; }
    else { const sub = norm(e.label); if (cs.some((c) => norm(c).includes(sub))) return true; }
  }
  return false;
}
function matchTags(p) {
  for (const k of selTags) if (!p._tk.has(k)) return false;
  return true;
}
const matchDiff = (p) => !selDiffs.size || selDiffs.has(diffKey(p));
function matchStatus(p) {
  if (FSTATUS === 'solved') return solved.has(p.id);
  if (FSTATUS === 'attempted') return attempted.has(p.id) && !solved.has(p.id);
  if (FSTATUS === 'unsolved') return !solved.has(p.id);
  return true;
}
function matchQ(p) {
  const q = norm($('q').value);
  return !q || norm(p.title).includes(q);
}
const filtered = () => ALL.filter((p) => matchColl(p) && matchTags(p) && matchDiff(p) && matchStatus(p) && matchQ(p));

// ---- ordenação ----------------------------------------------------------------------------
const SORTS = [
  { key: 'solved', pt: 'Mais resolvidos', en: 'Most solved' },
  { key: 'az', pt: 'A–Z', en: 'A–Z' },
  { key: 'diff', pt: 'Dificuldade', en: 'Difficulty' },
  { key: 'new', pt: 'Novidades', en: 'Newest' },       // exige public_at na lista (fase 2)
];
const byTitle = (a, b) => (a.title || a.id).localeCompare(b.title || b.id, 'pt', { numeric: true, sensitivity: 'base' });
function sortRows(rows) {
  if (SORT === 'az') return rows.sort(byTitle);
  if (SORT === 'new') return rows.sort((a, b) => (b.public_at || 0) - (a.public_at || 0) || byTitle(a, b));
  if (SORT === 'diff') return rows.sort((a, b) => {
    const aa = a.attempted_count || 0, ba = b.attempted_count || 0;
    if (!aa !== !ba) return aa ? -1 : 1;                     // "novo" (sem dados) por último
    const r = (ba ? b.solved_count / ba : 0) - (aa ? a.solved_count / aa : 0);
    return r || byTitle(a, b);
  });
  return rows.sort((a, b) => (b.solved_count || 0) - (a.solved_count || 0) || byTitle(a, b));
}

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
  COLLN = counts.size;
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
// progresso pessoal num conjunto de coleções (usado na árvore e no carrossel)
function solvedIn(colls) {
  if (!LOGGED || !solved.size) return 0;
  return ALL.reduce((a, p) => a + ((solved.has(p.id) && (p.collections || []).some((c) => colls.has(c))) ? 1 : 0), 0);
}

// ---- multi-seleção de coleções ------------------------------------------------------------
const nodeKey = (n) => (n.leaf ? '' : 'grp:') + n.label;
function toggleNode(n) {
  const key = nodeKey(n);
  if (selColls.has(key)) selColls.delete(key);
  else selColls.set(key, { label: n.label, colls: n.colls, group: !n.leaf });
  page = 0; enterBrowse(); syncURL(); renderAll();
}
function selectOnly(n) {                                     // carrossel/célula: substitui a seleção
  selColls = new Map([[nodeKey(n), { label: n.label, colls: n.colls, group: !n.leaf }]]);
  page = 0; enterBrowse(); syncURL(); renderAll();
}
function addCollByName(name) {
  const n = findNode((x) => x.leaf && x.label === String(name));
  const e = n ? { label: n.label, colls: n.colls, group: false }
    : { label: String(name), colls: new Set([String(name)]), group: false };
  selColls.set((n ? nodeKey(n) : String(name)), e);
  page = 0; enterBrowse(); syncURL(); renderAll();
}

function renderTree() {
  const box = $('colTree'); box.innerHTML = '';
  const f = norm($('colFilter').value);
  const matches = (n) => !f || norm(n.label).includes(f) || [...n.colls].some((c) => norm(c).includes(f));
  const isOn = (n) => selColls.has(nodeKey(n));
  function row(n, path) {
    if (!matches(n)) return null;
    const key = path + '/' + n.label;
    const open = openNodes.has(key) || (f && !norm(n.label).includes(f));  // filtro abre o caminho
    const wrap = el('div', {});
    const caret = n.leaf ? el('span', { class: 'caret' }, ' ')
      : el('span', { class: 'caret', onclick: () => { openNodes.has(key) ? openNodes.delete(key) : openNodes.add(key); renderTree(); } },
          open ? '▾' : '▸');
    const check = el('input', { type: 'checkbox', onclick: (e) => { e.preventDefault(); toggleNode(n); } });
    check.checked = isOn(n);
    const link = el('a', {
      class: 'collection' + (isOn(n) ? ' on' : ''),
      href: '?searchcol=' + encodeURIComponent(n.leaf ? n.label : 'grp:' + n.label),
      title: n.leaf ? n.label : T(`${n.colls.size} coleções`, `${n.colls.size} collections`),
      onclick: (e) => { e.preventDefault(); toggleNode(n); },
    }, `${n.label} (${n.count})`);
    const me = LOGGED ? (() => {
      const s = solvedIn(n.colls);
      return el('span', { class: 'me' + (s && s === n.count ? ' full' : '') },
        s === n.count && s ? `${s}/${n.count} ✓` : `${s}/${n.count}`);
    })() : null;
    wrap.append(el('div', { class: 'node' }, caret, check, link, me));
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
  const base = ALL.filter((p) => matchColl(p) && matchDiff(p) && matchStatus(p) && matchQ(p));
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
  page = 0; enterBrowse(); syncURL(); renderAll();
}

// ---- facetas de status e dificuldade (trilho) ---------------------------------------------
function renderRail() {
  // status (some p/ anônimo)
  $('fStatusGrp').classList.toggle('hidden', !LOGGED);
  if (LOGGED) {
    const base = ALL.filter((p) => matchColl(p) && matchTags(p) && matchDiff(p) && matchQ(p));
    const counts = {
      all: base.length,
      unsolved: base.filter((p) => !solved.has(p.id)).length,
      solved: base.filter((p) => solved.has(p.id)).length,
      attempted: base.filter((p) => attempted.has(p.id) && !solved.has(p.id)).length,
    };
    const OPTS = [
      { key: 'all', pt: 'Todos', en: 'All' },
      { key: 'unsolved', pt: 'A resolver', en: 'To solve' },
      { key: 'solved', pt: '✓ Resolvidos', en: '✓ Solved' },
      { key: 'attempted', pt: '… Tentados', en: '… Attempted' },
    ];
    const box = $('fStatus'); box.innerHTML = '';
    OPTS.forEach((o) => {
      const inp = el('input', { type: 'radio', name: 'fstatus',
        onchange: () => { FSTATUS = o.key; page = 0; syncURL(); renderAll(); } });
      inp.checked = FSTATUS === o.key;
      box.append(el('label', { class: 'fitem' }, inp, T(o.pt, o.en),
        el('span', { class: 'cnt2' }, String(counts[o.key]))));
    });
  }
  // dificuldade (contagem viva ignorando a própria faceta)
  const base = ALL.filter((p) => matchColl(p) && matchTags(p) && matchStatus(p) && matchQ(p));
  const counts = new Map();
  base.forEach((p) => { const k = diffKey(p); counts.set(k, (counts.get(k) || 0) + 1); });
  const box = $('fDiff'); box.innerHTML = '';
  DIFFS.forEach((d) => {
    const inp = el('input', { type: 'checkbox', onchange: () => {
      selDiffs.has(d.key) ? selDiffs.delete(d.key) : selDiffs.add(d.key);
      page = 0; syncURL(); renderAll();
    } });
    inp.checked = selDiffs.has(d.key);
    box.append(el('label', { class: 'fitem' }, inp,
      el('span', { class: 'diff ' + d.cls }, T(d.pt, d.en)),
      el('span', { class: 'cnt2' }, String(counts.get(d.key) || 0))));
  });
}

// ---- chips de filtros ativos + URL --------------------------------------------------------
function clearFilters() {
  selColls.clear(); selTags.clear(); selDiffs.clear(); FSTATUS = 'all';
  $('q').value = ''; $('mq').value = ''; $('colFilter').value = ''; $('tagFilter').value = '';
  page = 0;
}
function renderActive() {
  const box = $('active'); box.innerHTML = '';
  if (!hasFilter()) return;
  selColls.forEach((e, key) => box.append(el('span', { class: 'collection on',
    onclick: () => { selColls.delete(key); page = 0; syncURL(); renderAll(); } },
    `📚 ${e.label}`, el('span', { class: 'chip-x' }, '×'))));
  selTags.forEach((k) => box.append(el('span', { class: 'tag on', onclick: () => toggleTag(k) },
    (TAGS.get(k) || { label: '#' + k }).label, el('span', { class: 'chip-x' }, '×'))));
  selDiffs.forEach((k) => { const d = diffByKey(k); if (d) box.append(el('span', { class: 'fchip on',
    style: 'font-size:.75rem', onclick: () => { selDiffs.delete(k); page = 0; syncURL(); renderAll(); } },
    T(d.pt, d.en), el('span', { class: 'chip-x' }, '×'))); });
  if (FSTATUS !== 'all') box.append(el('span', { class: 'fchip on', style: 'font-size:.75rem',
    onclick: () => { FSTATUS = 'all'; page = 0; syncURL(); renderAll(); } },
    FSTATUS === 'solved' ? T('resolvidos', 'solved') : FSTATUS === 'attempted' ? T('tentados', 'attempted') : T('a resolver', 'to solve'),
    el('span', { class: 'chip-x' }, '×')));
  if ($('q').value.trim()) box.append(el('span', { class: 'tag',
    onclick: () => { $('q').value = ''; $('mq').value = ''; page = 0; syncURL(); renderAll(); } },
    `“${$('q').value.trim()}”`, el('span', { class: 'chip-x' }, '×')));
  box.append(el('a', { class: 'small', style: 'cursor:pointer;margin-left:.2rem', onclick: () => {
    clearFilters(); syncURL(); renderAll();
  } }, T('limpar', 'clear')));
}
function syncURL() {
  const sp = new URLSearchParams();
  if (selColls.size) sp.set('searchcol', [...selColls.values()]
    .map((e) => encodeURIComponent((e.group ? 'grp:' : '') + e.label)).join(','));
  if (selTags.size) sp.set('searchtag', [...selTags].join(','));
  if (selDiffs.size) sp.set('diff', [...selDiffs].join(','));
  if (FSTATUS !== 'all') sp.set('filter', FSTATUS);
  if (SORT !== 'solved') sp.set('sort', SORT);
  if ($('q').value.trim()) sp.set('q', $('q').value.trim());
  if (MODE === 'browse' && !sp.toString()) sp.set('browse', '1');
  history.replaceState(null, '', sp.toString() ? '?' + sp.toString() : location.pathname);
}
function applyURL() {
  const sp = new URLSearchParams(location.search);
  if (sp.get('q')) { $('q').value = sp.get('q'); $('mq').value = sp.get('q'); }
  (sp.get('searchtag') || '').split(',').map(tagKey).filter(Boolean)
    .forEach((k) => { if (TAGS.has(k)) selTags.add(k); });
  (sp.get('diff') || '').split(',').filter(Boolean)
    .forEach((k) => { if (diffByKey(k)) selDiffs.add(k); });
  const f = sp.get('filter') || '';
  if (['solved', 'attempted', 'unsolved'].includes(f)) FSTATUS = f;
  const s = sp.get('sort') || '';
  if (SORTS.some((x) => x.key === s)) SORT = s;
  for (const raw of (sp.get('searchcol') || '').split(',').filter(Boolean)) {
    let sc; try { sc = decodeURIComponent(raw); } catch { sc = raw; }
    if (sc.startsWith('grp:')) {
      const n = findNode((x) => !x.leaf && x.label === sc.slice(4));
      if (n) selColls.set(nodeKey(n), { label: n.label, colls: n.colls, group: true });
    } else {
      const n = findNode((x) => x.leaf && x.label === sc);
      if (n) selColls.set(nodeKey(n), { label: n.label, colls: n.colls, group: false });
      else if (sc) selColls.set(sc, { label: sc, colls: null, group: false });  // legado: substring
    }
  }
  BROWSE_FLAG = sp.get('browse') === '1';
  MODE = (BROWSE_FLAG || hasFilter()) ? 'browse' : 'hub';
}
function enterBrowse() { MODE = 'browse'; }
function goHub() {
  clearFilters(); BROWSE_FLAG = false; MODE = 'hub';
  syncURL(); renderAll();
}
function showMode() {
  const pl = $('pageLoading'); if (pl) pl.remove();
  $('hub').classList.toggle('hidden', MODE !== 'hub');
  $('browse').classList.toggle('hidden', MODE !== 'browse');
}

// ---- HUB ----------------------------------------------------------------------------------
// mapa curado de banner p/ coleções conhecidas + fallback determinístico por hash do nome
const BANNERS = [
  [/apc/i, ['🧮', 'bn-blue']], [/olimp|obi/i, ['🏆', 'bn-orange']],
  [/compiladores/i, ['⚙️', 'bn-purple']], [/monitores/i, ['🧑‍🏫', 'bn-teal']],
  [/mini-gpt/i, ['🤖', 'bn-pink']], [/rust/i, ['🦀', 'bn-slate']],
  [/python/i, ['🐍', 'bn-blue']], [/bash/i, ['💻', 'bn-green']],
  [/c\+\+/i, ['➕', 'bn-purple']], [/\bc\b|^c\s|^c ·/i, ['🇨', 'bn-green']],
  [/mdp|maratona/i, ['🎓', 'bn-blue']], [/moj/i, ['✅', 'bn-blue']],
];
const BN_CLASSES = ['bn-blue', 'bn-purple', 'bn-green', 'bn-orange', 'bn-teal', 'bn-pink', 'bn-slate'];
function banner(label) {
  for (const [re, b] of BANNERS) if (re.test(label)) return b;
  let h = 0; for (const ch of label) h = (h * 31 + ch.codePointAt(0)) >>> 0;
  return [label.slice(0, 1).toUpperCase(), BN_CLASSES[h % BN_CLASSES.length]];
}
function fmtAgo(epoch) {
  const d = Math.floor((Date.now() / 1000 - epoch) / 86400);
  if (d <= 0) return T('hoje', 'today');
  if (d === 1) return T('ontem', 'yesterday');
  if (d < 30) return T(`há ${d} dias`, `${d} days ago`);
  return T(`há ${Math.floor(d / 30)} mês(es)`, `${Math.floor(d / 30)} month(s) ago`);
}
const probURL = (id) => '/treino/problema/?id=' + encodeURIComponent(id);

function renderHub() {
  const byId = new Map(ALL.map((p) => [p.id, p]));
  $('heroSub').textContent = LOGGED
    ? T(`${ALL.length} problemas · você resolveu ${solved.size}`, `${ALL.length} problems · you solved ${solved.size}`)
    : T(`${ALL.length} problemas para treinar — entre para acompanhar seu progresso`,
        `${ALL.length} problems to practice — sign in to track your progress`);
  $('allColls').textContent = T(`todas (${COLLN}) →`, `all (${COLLN}) →`);
  $('ctaSub').textContent = T(`${COLLN} coleções · ${TAGS.size} tags · filtros por dificuldade e status`,
    `${COLLN} collections · ${TAGS.size} tags · difficulty and status filters`);

  // ---- "Para você": continue de onde parou + sugestão (só logado, com history) ----
  const strip = $('contStrip'); strip.innerHTML = '';
  let anyCard = false;
  if (LOGGED && HIST && HIST.length) {
    const contRow = [...HIST].reverse().find((h) => byId.has(h.probid) && !solved.has(h.probid));
    if (contRow) {
      const p = byId.get(contRow.probid);
      strip.append(el('a', { class: 'cont-card', href: probURL(p.id) },
        el('span', { class: 'k' }, T('▶ Continue de onde parou', '▶ Pick up where you left off')),
        el('span', { class: 't' }, p.title || p.id),
        el('span', { class: 'small muted' },
          (p.collections || []).slice(0, 1).map((c) => el('span', { class: 'collection' }, c)),
          ` · ${T('última tentativa', 'last attempt')} ${fmtAgo(contRow.epoch)} · ${contRow.verdict}`)));
      anyCard = true;
    }
    const lastAC = [...HIST].reverse().find((h) => /^Accepted/.test(h.verdict) && byId.has(h.probid));
    const cands = (base, why) => {
      const c = base.filter((p) => !solved.has(p.id) && (p.attempted_count || 0) > 0)
        .sort((a, b) => (b.solved_count / b.attempted_count) - (a.solved_count / a.attempted_count)
          || (b.solved_count || 0) - (a.solved_count || 0));
      return c.length ? { p: c[0], why } : null;
    };
    let sug = null;
    if (lastAC) {
      const coll = (byId.get(lastAC.probid).collections || [])[0];
      if (coll) sug = cands(ALL.filter((p) => (p.collections || []).includes(coll)),
        T(`próximo passo em ${coll}`, `next step in ${coll}`));
    }
    if (!sug) sug = cands(ALL, T('um clássico para destravar', 'a classic to get you going'));
    if (sug && (!contRow || sug.p.id !== contRow.probid)) {
      const d = difficulty(sug.p);
      strip.append(el('a', { class: 'cont-card', href: probURL(sug.p.id), style: 'border-left-color:var(--ok)' },
        el('span', { class: 'k' }, T('🎯 Sugestão para você', '🎯 Suggested for you')),
        el('span', { class: 't' }, sug.p.title || sug.p.id),
        el('span', { class: 'small muted' },
          (sug.p.collections || []).slice(0, 1).map((c) => el('span', { class: 'collection' }, c)),
          ' · ', el('span', { class: 'diff ' + d.cls }, d.label), ` — ${sug.why}`)));
      anyCard = true;
    }
  }
  $('contSec').hidden = !anyCard;

  // ---- carrossel de coleções em destaque ----
  // dedup por SOBREPOSIÇÃO de problemas: o grupo "obi" e a coleção "Olimpíada Brasileira de
  // Informática" são o mesmo conjunto — mostrar um só (preferindo o rótulo de folha, mais bonito)
  const car = $('carousel'); car.innerHTML = '';
  const probSet = (n) => new Set(ALL.filter((p) => (p.collections || []).some((c) => n.colls.has(c))).map((p) => p.id));
  const chosen = [];
  for (const n of TREE.slice(0, CAROUSEL_N * 2)) {
    const s = probSet(n);
    const dup = chosen.find((c) => {
      let inter = 0; for (const id of s) if (c.set.has(id)) inter++;
      return inter >= 0.8 * Math.min(s.size, c.set.size);
    });
    if (dup) {
      if (s.size > dup.set.size || (s.size === dup.set.size && n.leaf && !dup.n.leaf)) {
        dup.n = n; dup.set = s; dup.mine = solvedIn(n.colls);
      }
      continue;
    }
    chosen.push({ n, set: s, mine: solvedIn(n.colls) });
  }
  const feat = chosen
    .sort((a, b) => {
      const ap = a.mine > 0 && a.mine < a.n.count, bp = b.mine > 0 && b.mine < b.n.count;
      if (ap !== bp) return ap ? -1 : 1;                     // em andamento primeiro
      return b.n.count - a.n.count;
    }).slice(0, CAROUSEL_N);
  feat.forEach(({ n, mine }) => {
    const [glyph, cls] = banner(n.label);
    const done = LOGGED && mine === n.count && n.count > 0;
    const card = el('a', { class: 'lcard', onclick: () => selectOnly(n) },
      el('div', { class: 'banner ' + cls }, glyph),
      el('div', { class: 'bd' },
        el('span', { class: 't' }, n.label),
        el('span', { class: 'sub' }, `${n.count} ${T('problemas', 'problems')}`
          + (n.leaf ? '' : T(` · ${n.colls.size} coleções`, ` · ${n.colls.size} collections`))),
        ...(LOGGED ? [
          el('div', { class: 'pbar' + (done ? ' done' : '') },
            el('i', { style: `width:${n.count ? Math.round(100 * mine / n.count) : 0}%` })),
          done ? el('span', { class: 'foot', style: 'color:var(--ok);font-weight:700' }, T('✓ concluído', '✓ completed'))
            : el('span', { class: 'foot' }, mine ? `${mine}/${n.count} ${T('resolvidos', 'solved')}` : T('começar →', 'start →')),
        ] : [el('span', { class: 'foot' }, T('explorar →', 'explore →'))])));
    car.append(card);
  });

  // ---- em alta na semana ----
  const tl = $('trendList'); tl.innerHTML = '';
  if (TRENDING === null) {
    tl.append(el('span', { class: 'muted small' }, T('carregando…', 'loading…')));
  } else if (!TRENDING.length) {
    tl.append(el('span', { class: 'muted small' },
      T('Pouca atividade esta semana — explore as coleções acima.',
        'Little activity this week — explore the collections above.')));
  } else {
    TRENDING.forEach((p, i) => tl.append(el('a', { class: 'trend-li', href: p.url || probURL(p.id) },
      el('span', { class: 'rk' }, String(i + 1)),
      el('span', { class: 'tt' }, p.title || p.id),
      el('span', { class: 'nn' }, `${p.count} ${T('envios', 'submissions')}`))));
  }
}

// ---- omnibusca do hub (sugestões agrupadas) -----------------------------------------------
let SUGITEMS = [], SUGIDX = -1;
function hideSuggest() { $('suggest').classList.add('hidden'); SUGITEMS = []; SUGIDX = -1; }
function renderSuggest() {
  const box = $('suggest');
  const qn = norm($('hq').value.trim());
  if (qn.length < 2) { hideSuggest(); return; }
  box.innerHTML = ''; SUGITEMS = []; SUGIDX = -1;
  const add = (node, action) => { SUGITEMS.push({ node, action }); box.append(node); };

  const colls = new Map();
  ALL.forEach((p) => (p.collections || []).forEach((c) => { if (norm(c).includes(qn)) colls.set(c, (colls.get(c) || 0) + 1); }));
  const collTop = [...colls.entries()].sort((a, b) => b[1] - a[1]).slice(0, 3);
  if (collTop.length) {
    box.append(el('div', { class: 'grp' }, T('Coleções', 'Collections')));
    collTop.forEach(([c, n]) => add(
      el('div', { class: 'it' }, `📚 ${c}`, el('span', { class: 'mut' }, `${n} ${T('problemas', 'problems')}`)),
      () => { $('hq').value = ''; hideSuggest(); addCollByName(c); }));
  }
  const tagTop = [...TAGS.entries()].filter(([k, v]) => k.includes(qn) || norm(v.label).includes(qn))
    .sort((a, b) => b[1].count - a[1].count).slice(0, 3);
  if (tagTop.length) {
    box.append(el('div', { class: 'grp' }, 'Tags'));
    tagTop.forEach(([k, v]) => add(
      el('div', { class: 'it' }, `🏷 ${v.label}`, el('span', { class: 'mut' }, `${v.count} ${T('problemas', 'problems')}`)),
      () => { $('hq').value = ''; hideSuggest(); toggleTag(k); }));
  }
  const probs = ALL.filter((p) => norm(p.title).includes(qn));
  if (probs.length) {
    box.append(el('div', { class: 'grp' }, T('Problemas', 'Problems')));
    probs.slice(0, 6).forEach((p) => {
      const d = difficulty(p);
      const st = solved.has(p.id) ? ' · ✓' : (attempted.has(p.id) ? ' · …' : '');
      add(el('div', { class: 'it' }, p.title || p.id,
        el('span', { class: 'mut' }, el('span', { class: 'diff ' + d.cls }, d.label), st)),
        () => { location.href = probURL(p.id); });
    });
    add(el('div', { class: 'it', style: 'color:var(--blue-dark);font-weight:700' },
      T(`ver os ${probs.length} resultados na busca avançada →`, `see all ${probs.length} results in the advanced search →`)),
      () => submitHeroQuery());
  }
  if (!SUGITEMS.length) {
    box.append(el('div', { class: 'grp' }, T('nada encontrado', 'nothing found')));
  }
  SUGITEMS.forEach((s, i) => { s.node.onclick = () => s.action(); s.node.onmouseenter = () => setSug(i); });
  box.classList.remove('hidden');
}
function setSug(i) {
  SUGIDX = i;
  SUGITEMS.forEach((s, j) => s.node.classList.toggle('sel', j === i));
}
function submitHeroQuery() {
  const v = $('hq').value.trim();
  hideSuggest();
  if (!v) return;
  $('q').value = v; $('mq').value = v; $('hq').value = '';
  page = 0; enterBrowse(); syncURL(); renderAll();
}

// ---- BUSCA AVANÇADA (tabela) --------------------------------------------------------------
function renderSorts() {
  const box = $('sorts'); box.innerHTML = '';
  const hasPub = ALL.some((p) => p.public_at);         // servidor antigo sem o campo: sem a aba
  SORTS.filter((s) => s.key !== 'new' || hasPub)
    .forEach((s) => box.append(el('a', { class: SORT === s.key ? 'on' : '',
      onclick: () => { SORT = s.key; page = 0; syncURL(); renderBrowse(); } }, T(s.pt, s.en))));
}
function renderPager(box, pages) {
  box.innerHTML = '';
  if (pages <= 1) return;
  box.append(el('button', { class: 'btn ghost', onclick: () => { if (page > 0) { page--; renderBrowse(); } } }, '‹'));
  box.append(el('span', { class: 'small' }, ` ${T('página', 'page')} ${page + 1} / ${pages} `));
  box.append(el('button', { class: 'btn ghost', onclick: () => { if (page < pages - 1) { page++; renderBrowse(); } } }, '›'));
}
function renderBrowse() {
  const rows = sortRows(filtered());
  $('count').textContent = `${rows.length} ${T('problema(s)', 'problem(s)')}`;
  $('mystats').textContent = LOGGED
    ? T(`Você resolveu ${solved.size} de ${ALL.length}`, `You solved ${solved.size} of ${ALL.length}`) : '';
  const nf = selColls.size + selTags.size + selDiffs.size + (FSTATUS !== 'all' ? 1 : 0);
  $('mFilters').textContent = T(`Filtros (${nf}) ▾`, `Filters (${nf}) ▾`);
  $('mFilters').classList.toggle('on', nf > 0);
  renderSorts();
  const pages = Math.max(1, Math.ceil(rows.length / PAGE));
  if (page >= pages) page = 0;
  const slice = rows.slice(page * PAGE, page * PAGE + PAGE);

  const list = $('list');
  list.innerHTML = '';
  const tbl = el('table', { class: 'moj' },
    el('thead', {}, el('tr', {},
      el('th', { class: 'stc' }, ''),
      el('th', {}, T('Problema', 'Problem')),
      el('th', { class: 'hide-m' }, T('Coleções', 'Collections')),
      ...(showTags ? [el('th', { class: 'hide-m' }, 'Tags')] : []),
      el('th', {}, T('Dificuldade', 'Difficulty')),
      el('th', { class: 'hide-m' }, T('Resolvidos', 'Solved')))));
  const tb = el('tbody');
  slice.forEach((p) => {
    const d = difficulty(p);
    const isS = solved.has(p.id), isA = attempted.has(p.id) && !isS;
    const cells = [
      el('td', { class: 'stc' + (isS ? ' v-ok' : isA ? ' v-warn' : '') }, isS ? '✓' : (isA ? '…' : '')),
      el('td', {}, el('a', { href: probURL(p.id) }, p.title || p.id)),
      el('td', { class: 'hide-m' }, (p.collections || []).map((c) => el('a', {
        class: 'collection', href: '?searchcol=' + encodeURIComponent(String(c)),
        onclick: (e) => { e.preventDefault(); addCollByName(c); },
      }, c))),
    ];
    if (showTags) cells.push(el('td', { class: 'hide-m' }, (p.tags || []).map((t) => el('a', {
      class: 'tag' + (selTags.has(tagKey(t)) ? ' on' : ''),
      href: '?searchtag=' + encodeURIComponent(tagKey(t)),
      onclick: (e) => { e.preventDefault(); toggleTag(tagKey(t)); },
    }, t))));
    cells.push(el('td', {}, el('span', { class: 'diff ' + d.cls }, d.label)));
    cells.push(el('td', { class: 'hide-m' },
      p.attempted_count ? `${p.solved_count}/${p.attempted_count}` : '—'));
    tb.append(el('tr', { class: isS ? 'solvedrow' : '' }, ...cells));
  });
  tbl.append(tb); list.append(tbl);
  renderPager($('pager'), pages);
  renderPager($('pager2'), pages);
}

function renderAll() {
  showMode();
  if (MODE === 'hub') { renderHub(); return; }
  renderBrowse(); renderTree(); renderTags(); renderRail(); renderActive();
}

// ---- dados pessoais -----------------------------------------------------------------------
async function loadSolve() {
  const st = await status(CONTEST);
  LOGGED = !!st.logged_in;
  if (!LOGGED) { solved = new Set(); attempted = new Set(); HIST = null; return; }
  try {
    const j = await apiGet('/treino/solvetry', { contest: CONTEST, auth: true });
    solved = new Set(j.solved || []); attempted = new Set(j.attempted || []);
  } catch {}
}
function loadHist() {
  // history-full: TXT, 7 campos time:user:probid:lang:verdict:epoch:subid (verdict pode
  // colapsar ':' internos — parse pela POSIÇÃO: fatia 4..len-2). Não-bloqueante.
  if (!LOGGED) return;
  apiGetText('/treino/history-full', { contest: CONTEST, auth: true }).then((txt) => {
    HIST = txt.split('\n').filter(Boolean).map((ln) => {
      const f = ln.split(':');
      if (f.length < 7) return null;
      return { probid: f[2], verdict: f.slice(4, f.length - 2).join(':'), epoch: +f[f.length - 2] || 0 };
    }).filter(Boolean).sort((a, b) => a.epoch - b.epoch);
    if (MODE === 'hub') renderHub();
  }).catch(() => { HIST = []; });
}

// ---- boot ---------------------------------------------------------------------------------
async function boot() {
  const authArea = $('authArea');
  await renderAuthArea(authArea, CONTEST, async () => { await loadSolve(); loadHist(); renderAll(); });

  try {
    const j = await apiGet('/treino/problems', { contest: CONTEST });
    ALL = Array.isArray(j) ? j : (j.problems || j.data || []);
  } catch (e) {
    $('pageLoading').innerHTML = `<span class="error-box">${T('Falha ao carregar problemas.', 'Failed to load problems.')}</span>`;
    return;
  }
  buildTags(); buildTree(); applyURL();
  await loadSolve();
  loadHist();
  apiGet('/treino/trending', { contest: CONTEST })
    .then((j) => { TRENDING = (j && j.problems) || []; if (MODE === 'hub') renderHub(); })
    .catch(() => { TRENDING = []; if (MODE === 'hub') renderHub(); });

  // busca do trilho (desktop) e do mobile — espelhadas
  $('q').addEventListener('input', () => { $('mq').value = $('q').value; page = 0; syncURL(); renderBrowse(); renderTags(); renderRail(); renderActive(); });
  $('mq').addEventListener('input', () => { $('q').value = $('mq').value; page = 0; syncURL(); renderBrowse(); renderTags(); renderRail(); renderActive(); });
  $('colFilter').addEventListener('input', renderTree);
  $('tagFilter').addEventListener('input', renderTags);
  $('toggleTags').addEventListener('click', () => {
    showTags = !showTags;
    $('toggleTags').textContent = showTags ? T('Ocultar tags', 'Hide tags') : T('Mostrar tags', 'Show tags');
    renderBrowse();
  });
  $('clearAll').addEventListener('click', () => { clearFilters(); syncURL(); renderAll(); });
  $('mFilters').addEventListener('click', () => $('rail').classList.toggle('open'));
  $('backHub').addEventListener('click', (e) => { e.preventDefault(); goHub(); });

  // omnibusca do hub
  $('hq').addEventListener('input', renderSuggest);
  $('hq').addEventListener('keydown', (e) => {
    if (e.key === 'ArrowDown') { e.preventDefault(); if (SUGITEMS.length) setSug((SUGIDX + 1) % SUGITEMS.length); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); if (SUGITEMS.length) setSug((SUGIDX - 1 + SUGITEMS.length) % SUGITEMS.length); }
    else if (e.key === 'Enter') { e.preventDefault(); (SUGIDX >= 0 && SUGITEMS[SUGIDX]) ? SUGITEMS[SUGIDX].action() : submitHeroQuery(); }
    else if (e.key === 'Escape') hideSuggest();
  });
  document.addEventListener('click', (e) => { if (!e.target.closest('.herosearch')) hideSuggest(); });

  // quickchips do hub
  $('qcRandom').addEventListener('click', () => {
    const pool = ALL.filter((p) => !solved.has(p.id));
    const pick = (pool.length ? pool : ALL)[Math.floor(Math.random() * (pool.length ? pool.length : ALL.length))];
    if (pick) location.href = probURL(pick.id);
  });
  $('qcEasy').addEventListener('click', () => {
    clearFilters(); selDiffs = new Set(['veasy', 'easy']);
    if (LOGGED) FSTATUS = 'unsolved';
    SORT = 'solved'; enterBrowse(); syncURL(); renderAll();
  });
  $('qcUnsolved').addEventListener('click', () => {
    clearFilters(); if (LOGGED) FSTATUS = 'unsolved';
    enterBrowse(); syncURL(); renderAll();
  });
  const openBrowse = (e) => { e.preventDefault(); BROWSE_FLAG = true; enterBrowse(); syncURL(); renderAll(); };
  $('qcBrowse').addEventListener('click', openBrowse);
  $('ctaBrowse').addEventListener('click', openBrowse);
  $('allColls').addEventListener('click', openBrowse);

  // setas do carrossel
  $('carPrev').addEventListener('click', () => $('carousel').scrollBy({ left: -600, behavior: 'smooth' }));
  $('carNext').addEventListener('click', () => $('carousel').scrollBy({ left: 600, behavior: 'smooth' }));

  renderAll();
}
boot();
