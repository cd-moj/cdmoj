// shared/contest-config/bank-panel.js — painel de BUSCA + SORTEIO no banco de problemas
// (coleção / tag / dificuldade, filtros em AND, seed reproduzível), compartilhado entre o
// wizard de criação (rotas /treino/contest-create/*) e a aba Problemas do admin do contest
// (rotas /contest/admin/{bank,draw}). O chamador injeta o adaptador de API:
//   api = { meta()   -> {tags:[{tag,count}], collections:[{collection,count}]},
//           draw(p)  -> {problems[],candidates,drawn,seed}   (p = {tags,collections,count,match,difficulty,seed?}),
//           search(q)-> {problems:[{id,title,private?,has_statement?}]} }
//   onAdd(item) é chamado ao adicionar ({id,title,private?,has_statement?}).
// opts: searchLabel/searchPlaceholder, noQueryFilter(items) (wizard: só os privados do usuário),
//       emptyHint (texto quando a busca sem query não tem nada).
import { el } from '/shared/ui.js';
import { T } from '/shared/i18n.js';
import { diffLabel } from '/shared/difficulty.js';

// buckets do sorteio = a dificuldade CANÔNICA (taxa POR USUÁRIO, shared/difficulty.js, #30):
// fáceis = muito fácil + fácil (≥70% de quem tenta resolve) · médios = 50–70% · difíceis <50%
const DIFF_LABEL = () => ({ any: T('qualquer', 'any', 'cualquiera'), easy: T('fáceis (≥70% resolvem)', 'easy (≥70% solve)', 'fáciles (≥70% resuelven)'), medium: T('médios (50–70%)', 'medium (50–70%)', 'medios (50–70%)'), hard: T('difíceis (<50% resolvem)', 'hard (<50% solve)', 'difíciles (<50% resuelven)'), known: T('com histórico', 'with history', 'con historial') });
const debounce = (fn, ms) => { let h; return (...a) => { clearTimeout(h); h = setTimeout(() => fn(...a), ms); }; };
let uid = 0;

export function makeBankPanel({ api, onAdd, searchLabel, searchPlaceholder, noQueryFilter, emptyHint } = {}) {
  const idsuf = String(++uid);
  let allTags = [], allCollections = [];

  // --- chips genéricos (coleções e tags) ---
  function chipsInput({ dlId, placeholder, options, optionLabel }) {
    const selected = [];
    const chips = el('div', { class: 'row', style: 'margin:.3rem 0' });
    const dl = el('datalist', { id: dlId });
    const input = el('input', { list: dlId, placeholder, style: 'min-width:220px' });
    const render = () => {
      chips.innerHTML = '';
      selected.forEach((v, i) => chips.append(el('span', { class: 'tag-chip' }, v,
        el('a', { href: '#', onclick: (e) => { e.preventDefault(); selected.splice(i, 1); render(); } }, ' ✕'))));
    };
    const add = (v) => { v = (v || '').trim(); if (v && !selected.includes(v)) { selected.push(v); render(); } input.value = ''; };
    const setOptions = (opts2) => { dl.innerHTML = ''; opts2.forEach((o) => dl.append(el('option', { value: o.value }, optionLabel(o)))); };
    input.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); add(input.value); } });
    input.addEventListener('input', () => { if (options().some((o) => o.value === input.value)) add(input.value); });
    return { input, dl, chips, selected, setOptions };
  }
  const colC = chipsInput({
    dlId: 'bpColsDL' + idsuf, placeholder: T('coleção (ex.: problemas-apc)…', 'collection (e.g. problemas-apc)…', 'colección (ej. problemas-apc)…'),
    options: () => allCollections.map((c) => ({ value: c.collection, count: c.count })),
    optionLabel: (o) => o.value + ' (' + o.count + ')',
  });
  const tagC = chipsInput({
    dlId: 'bpTagsDL' + idsuf, placeholder: T('tag (ex.: #lista-encadeada)…', 'tag (e.g. #lista-encadeada)…', 'etiqueta (ej. #lista-encadeada)…'),
    options: () => allTags.map((t) => ({ value: t.tag, count: t.count })),
    optionLabel: (o) => o.value + ' (' + o.count + ')',
  });

  const count = el('input', { type: 'number', min: '1', max: '100', value: '6', style: 'width:70px' });
  const match = el('select', {}, el('option', { value: 'any' }, T('qualquer tag', 'any tag', 'cualquier etiqueta')), el('option', { value: 'all' }, T('todas as tags', 'all tags', 'todas las etiquetas')));
  const DL = DIFF_LABEL();
  const diff = el('select', {}, ...Object.keys(DL).map((k) => el('option', { value: k }, DL[k])));
  const out = el('div', {});
  const drawBtn = el('button', { class: 'btn' }, T('🎲 Sortear', '🎲 Draw', '🎲 Sortear'));
  let lastSeed = null;

  const itemRow = (p, extraInfo) => el('div', { class: 'bank-item' },
    el('div', {}, el('div', { class: 't' }, (p.title || p.id), accBadge(p)), el('div', { class: 'i' }, extraInfo || p.id)),
    el('button', { class: 'btn ghost', onclick: () => onAdd(p) }, T('+ adicionar', '+ add', '+ agregar')));
  const accBadge = (it) => it.private
    ? el('span', { class: 'tag', style: 'margin-left:.4rem;background:#3d3417;color:#ffe08a' }, it.access === 'shared' ? T('compartilhado', 'shared', 'compartido') : T('privado', 'private', 'privado'))
    : '';

  async function doDraw(reshuffle) {
    const p = { tags: tagC.selected.join(','), count: count.value || '6', match: match.value, difficulty: diff.value };
    if (colC.selected.length) p.collections = JSON.stringify(colC.selected);
    if (!reshuffle && lastSeed != null) p.seed = lastSeed;
    out.innerHTML = T('sorteando…', 'drawing…', 'sorteando…');
    try {
      const r = await api.draw(p);
      lastSeed = r.seed;
      out.innerHTML = '';
      if (!r.problems || !r.problems.length) {
        out.append(el('p', { class: 'muted small' }, T('Nenhum problema encontrado (', 'No problem found (', 'Ningún problema encontrado (') + r.candidates + T(' candidatos). Ajuste coleções/tags/dificuldade.', ' candidates). Adjust collections/tags/difficulty.', ' candidatos). Ajusta colecciones/etiquetas/dificultad.')));
        return;
      }
      out.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' },
        T('Sorteados ', 'Drawn ', 'Sorteados ') + r.drawn + T(' de ', ' of ', ' de ') + r.candidates + T(' candidatos (seed ', ' candidates (seed ', ' candidatos (semilla ') + r.seed + '). ',
        el('a', { href: '#', onclick: (e) => { e.preventDefault(); doDraw(true); } }, T('↻ sortear de novo', '↻ draw again', '↻ sortear de nuevo')), ' · ',
        el('a', { href: '#', onclick: (e) => { e.preventDefault(); r.problems.forEach((p2) => onAdd(p2)); } }, T('+ adicionar todos', '+ add all', '+ agregar todos'))));
      r.problems.forEach((p2) => {
        const info = p2.id + ' · ' + (p2.difficulty ? diffLabel(p2.difficulty) : p2.bucket)
          + (p2.total ? (' · ' + (p2.user_rate != null ? Math.round(p2.user_rate * 100) + T('% resolvem · ', '% solve · ', '% resuelven · ') : '') + p2.solvers + T(' resolveram', ' solved', ' resolvieron')) : T(' · sem histórico', ' · no history', ' · sin historial'))
          + ((p2.collections || []).length ? (' · 📁 ' + p2.collections.join(', ')) : '');
        out.append(itemRow(p2, info));
      });
    } catch (e) { out.innerHTML = ''; out.append(el('div', { class: 'small error-box' }, e.message || T('erro', 'error', 'error'))); }
  }
  drawBtn.addEventListener('click', () => { lastSeed = null; doDraw(true); });

  // --- busca ---
  const search = el('input', { placeholder: searchPlaceholder || T('🔎 Buscar problemas — título ou id…', '🔎 Search problems — title or id…', '🔎 Buscar problemas — título o id…') });
  const results = el('div', { class: 'bank-results', style: 'display:none' });
  const doSearch = debounce(async () => {
    const q = search.value.trim();
    try {
      const r = await api.search(q);
      let items = r.problems || [];
      if (!q && noQueryFilter) items = noQueryFilter(items);
      results.innerHTML = ''; results.style.display = 'block';
      if (!items.length) {
        results.append(el('div', { class: 'bank-item' }, el('span', { class: 'muted small' },
          q ? T('nada encontrado', 'nothing found', 'nada encontrado') : (emptyHint || T('digite para buscar no banco', 'type to search the bank', 'escribe para buscar en el banco')))));
        return;
      }
      items.forEach((it) => results.append(itemRow(it)));
    } catch (e) {
      results.style.display = 'block'; results.innerHTML = '';
      results.append(el('div', { class: 'bank-item' }, el('span', { class: 'small error-box' }, e.message || T('erro', 'error', 'error'))));
    }
  }, 250);
  search.addEventListener('input', doSearch);
  search.addEventListener('focus', doSearch);

  // meta (tags+coleções) carregada em background
  (async () => {
    try {
      const m = await api.meta();
      allTags = m.tags || []; allCollections = m.collections || [];
      tagC.setOptions(allTags.map((t) => ({ value: t.tag, count: t.count })));
      colC.setOptions(allCollections.map((c) => ({ value: c.collection, count: c.count })));
    } catch { /* datalists ficam vazios; busca/sorteio seguem funcionando */ }
  })();

  const root = el('div', {},
    el('div', { class: 'section', style: 'background:#fbfdff' },
      el('h3', { style: 'margin:.1rem 0 .4rem' }, T('🎲 Sortear por coleção / tag / dificuldade', '🎲 Draw by collection / tag / difficulty', '🎲 Sortear por colección / etiqueta / dificultad')),
      el('div', { class: 'field' }, el('label', {}, T('Coleções', 'Collections', 'Colecciones')), colC.input, colC.dl, colC.chips),
      el('div', { class: 'field' }, el('label', {}, 'Tags'), tagC.input, tagC.dl, tagC.chips),
      el('div', { class: 'row' }, el('span', { class: 'small' }, T('quantos:', 'how many:', 'cuántos:')), count,
        el('span', { class: 'small' }, T('casar:', 'match:', 'coincidir:')), match, el('span', { class: 'small' }, T('dificuldade:', 'difficulty:', 'dificultad:')), diff, drawBtn),
      out),
    el('div', { class: 'field' }, el('label', {}, searchLabel || T('Buscar problemas', 'Search problems', 'Buscar problemas')), search, results));
  return { el: root };
}
