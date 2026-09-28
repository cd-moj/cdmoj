// shared/contest-config/regions.js — editor de filtros de região (regions.json).
// Lista simples {name, regex}; “JSON avançado” permite sub-regiões aninhadas.
//
// NUNCA PERDE DADOS (28/09/2026): o editor antigo devolvia, no modo simples, só {name,regex} dos nós com
// regex — salvar apagava subregions, recortes `view` e sedes sem regex (a árvore da Maratona virava lista
// plana; a de zz-virtual-demo sumia). Agora:
//   • configuração que a lista simples não representa (sub-regiões, `view`, campo extra) abre no JSON e a
//     lista fica BLOQUEADA — não há como "descer" para uma vista que a perderia;
//   • no modo simples, sede SEM regex é legítima (a sede gravada no time, `.team.region`, casa pelo nome);
//   • JSON inválido não cai calado no modo simples: getValue() devolve a última árvore VÁLIDA (a inicial, se
//     nenhuma) e validate() diz o erro — o chamador bloqueia o salvar com ele. getValue() nunca lança (o
//     passo de revisão do assistente o chama fora de try).
import { el } from '/shared/ui.js';
import { T } from '/shared/i18n.js';
import { rgNorm } from '/shared/regions-match.js';

const SIMPLE_KEYS = new Set(['name', 'regex']);

// a lista simples representa a árvore sem perder nada?
export function regionsFitSimple(tree) {
  if (!Array.isArray(tree)) return false;
  return tree.every((r) => r && typeof r === 'object' && !Array.isArray(r)
    && Object.keys(r).every((k) => SIMPLE_KEYS.has(k))
    && typeof (r.name ?? '') === 'string' && typeof (r.regex ?? '') === 'string');
}

// validação estrutural (a regex é conferida no servidor): array de nós {name, regex?, subregions?, view?}
// o porquê de uma regex recusada (os códigos são os do servidor: rg_norm em server/api/v1/lib/regions.sh — a
// regex tem de casar IGUAL no navegador, no jq e no gawk do placar/estatística)
export function regexErrText(code) {
  const M = {
    word_boundary: T('\\b (fronteira de palavra) não é aceito — no placar ele vira outra coisa; use ^ e $', '\\b (word boundary) is not accepted — the scoreboard reads it as something else; use ^ and $', '\\b (límite de palabra) no se acepta — el marcador lo interpreta como otra cosa; usa ^ y $'),
    escape: T('escape não aceito (\\p, \\k, \\1, \\x…); use só \\d \\w \\s ou escape de pontuação', 'escape not accepted (\\p, \\k, \\1, \\x…); use only \\d \\w \\s or punctuation escapes', 'escape no aceptado (\\p, \\k, \\1, \\x…); usa solo \\d \\w \\s o escapes de puntuación'),
    group_ext: T('(?=, (?!, (?<, (?i)… não são aceitos; só ( ) e (?: )', '(?=, (?!, (?<, (?i)… are not accepted; only ( ) and (?: )', '(?=, (?!, (?<, (?i)… no se aceptan; solo ( ) y (?: )'),
    posix_class: T('[[:classe:]] não é aceito; use [a-z], [0-9]…', '[[:class:]] is not accepted; use [a-z], [0-9]…', '[[:clase:]] no se acepta; usa [a-z], [0-9]…'),
    lazy: T('quantificador preguiçoso (*? +? ??) não é aceito', 'lazy quantifier (*? +? ??) is not accepted', 'cuantificador perezoso (*? +? ??) no se acepta'),
    double_quantifier: T('dois quantificadores seguidos (a**, a+*…)', 'two quantifiers in a row (a**, a+*…)', 'dos cuantificadores seguidos (a**, a+*…)'),
    brace: T('{ } só como repetição {m} ou {m,n}, com números até 100', '{ } only as repetition {m} or {m,n}, with numbers up to 100', '{ } solo como repetición {m} o {m,n}, con números hasta 100'),
    ambiguous_range: T('hífen ambíguo dentro de [ ] (depois de um intervalo ou de \\d/\\w); ponha o - no fim: [a-z0-9-]', 'ambiguous hyphen inside [ ] (after a range or \\d/\\w); put the - at the end: [a-z0-9-]', 'guion ambiguo dentro de [ ] (después de un rango o de \\d/\\w); pon el - al final: [a-z0-9-]'),
    class_intersection: T('&& dentro de [ ] não é aceito', '&& inside [ ] is not accepted', '&& dentro de [ ] no se acepta'),
    negated_class_in_bracket: T('\\D \\W \\S dentro de [ ] não são aceitos', '\\D \\W \\S inside [ ] are not accepted', '\\D \\W \\S dentro de [ ] no se aceptan'),
    non_ascii: T('só caracteres ASCII (login não tem acento)', 'ASCII characters only (logins have no accents)', 'solo caracteres ASCII (el usuario no lleva acentos)'),
    control_char: T('caractere de controle (tab, quebra de linha)', 'control character (tab, line break)', 'carácter de control (tab, salto de línea)'),
    trailing_backslash: T('termina com \\ sozinha', 'ends with a lone \\', 'termina con una \\ sola'),
    unclosed_bracket: T('[ sem ]', '[ without ]', '[ sin ]'),
    invalid: T('regex inválida', 'invalid regex', 'regex inválida'),
  };
  return M[code] || (T('regex recusada', 'regex rejected', 'regex rechazada') + ' (' + code + ')');
}

export function regionsError(tree) {
  if (!Array.isArray(tree)) return T('O JSON das sedes tem de ser uma lista […].', 'The sites JSON must be a list […].', 'El JSON de las sedes debe ser una lista […].');
  const bad = (n, path) => {
    if (!n || typeof n !== 'object' || Array.isArray(n)) return path + ': ' + T('cada sede é um objeto {"name": …}', 'each site is an object {"name": …}', 'cada sede es un objeto {"name": …}');
    if (typeof n.name !== 'string' || !n.name.trim()) return path + ': ' + T('sede sem "name"', 'site without "name"', 'sede sin "name"');
    if (n.regex !== undefined && typeof n.regex !== 'string') return n.name + ': ' + T('"regex" tem de ser texto', '"regex" must be text', '"regex" debe ser texto');
    if (n.regex) { const r = rgNorm(n.regex); if (r.err) return n.name + ': ' + regexErrText(r.err); }
    if (n.subregions !== undefined) {
      if (!Array.isArray(n.subregions)) return n.name + ': ' + T('"subregions" tem de ser uma lista', '"subregions" must be a list', '"subregions" debe ser una lista');
      for (let i = 0; i < n.subregions.length; i++) { const e = bad(n.subregions[i], n.name + ' › #' + (i + 1)); if (e) return e; }
    }
    return '';
  };
  for (let i = 0; i < tree.length; i++) { const e = bad(tree[i], '#' + (i + 1)); if (e) return e; }
  return '';
}

export function makeRegionsEditor(opts = {}) {
  const initial = Array.isArray(opts.initial) ? opts.initial : [];
  let regions = initial.map((r) => ({ ...r }));
  let lastGood = initial;
  const list = el('div', {});
  const lockNote = el('p', { class: 'small', style: 'display:none;margin:.3rem 0' },
    T('🔒 Esta configuração usa sub-regiões, recortes ou campos que a lista simples não mostra — ela só é editada no JSON abaixo (a lista a perderia).',
      '🔒 This setup uses sub-regions, views or fields the simple list does not show — edit it only in the JSON below (the list would lose it).',
      '🔒 Esta configuración usa subregiones, recortes o campos que la lista simple no muestra — solo se edita en el JSON de abajo (la lista la perdería).'));
  function render() {
    list.innerHTML = '';
    if (!regions.length) list.append(el('p', { class: 'muted small' }, T('Sem filtros de região. Ex.: nome “DF”, regex “^br-df-”.', 'No region filters. E.g.: name “DF”, regex “^br-df-”.', 'Sin filtros de región. Ej.: nombre “DF”, regex “^br-df-”.')));
    regions.forEach((r, i) => {
      const name = el('input', { value: r.name || '', placeholder: T('nome (ex.: DF)', 'name (e.g. DF)', 'nombre (ej. DF)'), style: 'width:150px' });
      name.addEventListener('input', () => { r.name = name.value; });
      const rx = el('input', { value: r.regex || '', placeholder: T('regex (opcional, ex.: ^br-df-)', 'regex (optional, e.g. ^br-df-)', 'regex (opcional, ej. ^br-df-)'), style: 'flex:1' });
      rx.addEventListener('input', () => { r.regex = rx.value; });
      const rm = el('button', { class: 'btn danger ghost', title: T('remover', 'remove', 'quitar'), onclick: () => { regions.splice(i, 1); render(); } }, '✕');
      list.append(el('div', { class: 'row', style: 'margin:.25rem 0' }, name, rx, rm));
    });
  }
  const adv = el('textarea', { rows: '8', style: 'width:100%;display:none;font-family:monospace;font-size:.82rem', placeholder: T('JSON avançado com subregions…', 'advanced JSON with subregions…', 'JSON avanzado con subregiones…') });
  const advMsg = el('div', { class: 'small', style: 'display:none' });
  const addBtn = el('button', { class: 'btn ghost', onclick: () => { regions.push({ name: '', regex: '' }); render(); } }, T('+ região', '+ region', '+ región'));
  const inJson = () => adv.style.display !== 'none';
  function showJson(tree) {
    adv.value = JSON.stringify(tree, null, 1); adv.style.display = ''; list.style.display = 'none'; addBtn.style.display = 'none';
  }
  function showSimple() { adv.style.display = 'none'; list.style.display = ''; addBtn.style.display = ''; advMsg.style.display = 'none'; render(); }
  const simpleTree = () => regions
    .map((r) => ({ name: (r.name || '').trim() || (r.regex || '').trim(), regex: (r.regex || '').trim() }))
    .filter((r) => r.name)
    .map((r) => (r.regex ? r : { name: r.name }));
  const advToggle = el('a', { href: '#', class: 'small', onclick: (e) => {
    e.preventDefault();
    if (!inJson()) { showJson(simpleTree()); return; }
    let j;
    try { j = JSON.parse(adv.value); } catch { advMsg.className = 'small error-box'; advMsg.textContent = T('JSON inválido — corrija antes de voltar à lista.', 'Invalid JSON — fix it before going back to the list.', 'JSON inválido — corrígelo antes de volver a la lista.'); advMsg.style.display = ''; return; }
    if (!regionsFitSimple(j)) { advMsg.className = 'small error-box'; advMsg.textContent = T('Esta árvore não cabe na lista simples (sub-regiões/recortes) — siga no JSON.', 'This tree does not fit the simple list (sub-regions/views) — keep using the JSON.', 'Este árbol no cabe en la lista simple (subregiones/recortes) — sigue en el JSON.'); advMsg.style.display = ''; return; }
    regions = j.map((r) => ({ ...r })); lastGood = j; showSimple();
  } }, T('JSON avançado (sub-regiões) ⇄ lista', 'advanced JSON (sub-regions) ⇄ list', 'JSON avanzado (subregiones) ⇄ lista'));
  const panel = el('div', {}, lockNote, list, el('div', { class: 'row' }, addBtn, advToggle), adv, advMsg);
  // estado inicial explícito (o modo é lido de style.display — não depender do atributo em texto)
  lockNote.style.display = 'none'; adv.style.display = 'none'; advMsg.style.display = 'none';
  render();
  if (!regionsFitSimple(initial)) { showJson(initial); lockNote.style.display = ''; }
  return {
    el: panel,
    // o erro que impede salvar ('' = pode salvar)
    validate() {
      if (!inJson()) return regionsError(simpleTree());
      let j;
      try { j = JSON.parse(adv.value || '[]'); } catch (e) { return T('JSON das sedes inválido: ', 'Invalid sites JSON: ', 'JSON de las sedes inválido: ') + (e.message || ''); }
      return regionsError(j);
    },
    getValue() {
      if (!inJson()) return simpleTree();
      try { const j = JSON.parse(adv.value || '[]'); if (!regionsError(j)) { lastGood = j; return j; } } catch { /* inválido: devolve a última árvore válida */ }
      return lastGood;
    },
  };
}
