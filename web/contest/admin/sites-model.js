// contest/admin/sites-model.js — o MODELO do painel de sedes em três modos (Simples · Intermediário ·
// Avançado), sem DOM. A verdade é SEMPRE a árvore do regions.json (a regex de cada nó); cada modo é uma
// VISTA dela, e só abre quando a árvore cabe nele (senão o botão fica desabilitado com o motivo).
//
//   Simples       — lista de sedes, cada uma com "logins que começam com" (prefixos). Um nível, sem recorte.
//   Intermediário — grupos › sedes (dois níveis), cada sede com regras: começa / contém / termina / lista.
//   Avançado      — a árvore inteira (subregiões, recortes `view`, regex livre no subconjunto seguro).
//
// Regra → regex (sempre no subconjunto seguro de web/shared/regions-match.js › rgNorm):
//   começa p → ^p · contém p → p · termina p → p$ · lista a,b → ^(a|b)$ ; vários valores = alternância
//   (^(p|q)); várias regras = (r1)|(r2) — cada uma ancorada em si (^a|b$ seria a armadilha de precedência).
// O nó guarda `rule` (SÓ p/ a interface voltar do jeito que foi escrito); se `rule` não gera EXATAMENTE a
// regex do nó (alguém editou a regex no Avançado/CLI), `rule` é descartado e a regex é relida — ou o nó
// não cabe no modo. Uma `rule` velha nunca diverge em silêncio do que o servidor casa.
import { rgNorm, rgKey } from '/shared/regions-match.js';

export const RULE_TYPES = ['starts', 'contains', 'ends', 'list'];
// escapa o texto do usuário p/ a regex: a pontuação que o rgNorm aceita escapada
const escLit = (s) => String(s).replace(/[.[\](){}*+?|^$\\]/g, (c) => '\\' + c);
const vals = (v) => (Array.isArray(v) ? v : String(v == null ? '' : v).split(',')).map((x) => String(x).trim()).filter(Boolean);

export function ruleRegex(rule) {
  const vs = vals(rule && rule.v);
  if (!vs.length || !RULE_TYPES.includes(rule.t)) return '';
  const alt = vs.length === 1 ? escLit(vs[0]) : '(' + vs.map(escLit).join('|') + ')';
  if (rule.t === 'starts') return '^' + alt;
  if (rule.t === 'contains') return alt;
  if (rule.t === 'ends') return alt + '$';
  return '^(' + vs.map(escLit).join('|') + ')$';           // list
}
export function rulesRegex(rules) {
  const rs = (rules || []).map(ruleRegex).filter(Boolean);
  if (rs.length <= 1) return rs[0] || '';
  return rs.map((r) => '(' + r + ')').join('|');
}

// lê uma regex de UMA regra (as formas que o ruleRegex gera) — o que não relê byte a byte = null
const LIT = '(?:[^.[\\](){}*+?|^$\\\\]|\\\\[.[\\](){}*+?|^$\\\\])+';
const unesc = (s) => s.replace(/\\(.)/g, '$1');
function parseOne(re) {
  let m;
  const alts = (body) => { if (new RegExp('^' + LIT + '$').test(body)) return [unesc(body)];
    const mm = new RegExp('^\\((' + LIT + '(?:\\|' + LIT + ')*)\\)$').exec(body);
    return mm ? mm[1].split(/(?<!\\)\|/).map(unesc) : null; };
  if ((m = /^\^\((.*)\)\$$/.exec(re))) { const v = alts('(' + m[1] + ')'); if (v) return { t: 'list', v }; }
  if ((m = /^\^(.*)$/.exec(re)) && !re.endsWith('$')) { const v = alts(m[1]); if (v) return { t: 'starts', v }; }
  if ((m = /^(.*)\$$/.exec(re)) && !re.startsWith('^')) { const v = alts(m[1]); if (v) return { t: 'ends', v }; }
  if (!re.startsWith('^') && !re.endsWith('$')) { const v = alts(re); if (v) return { t: 'contains', v }; }
  return null;
}
// as regras de um nó: a `rule` guardada (se ainda gera a regex EXATA), senão relê a regex; null = não relê
export function nodeRules(node) {
  const re = String((node && node.regex) || '');
  if (!re) return [];
  if (Array.isArray(node.rule) && node.rule.length && rulesRegex(node.rule) === re) return node.rule.map((r) => ({ t: r.t, v: vals(r.v) }));
  const one = parseOne(re);
  if (one && rulesRegex([one]) === re) return [one];
  // (r1)|(r2)|… — só se cada parte relê e o todo regenera igual
  const parts = re.match(/^\((.+)\)$/) ? splitTop(re) : null;
  if (parts && parts.length > 1) {
    const rs = parts.map((p) => parseOne(p.replace(/^\(|\)$/g, '')));
    if (rs.every(Boolean) && rulesRegex(rs) === re) return rs;
  }
  return null;
}
function splitTop(re) {   // "(a)|(b)" → ["(a)", "(b)"] no nível de fora
  const out = []; let depth = 0, cur = '', esc = false;
  for (const c of re) {
    if (esc) { cur += c; esc = false; continue; }
    if (c === '\\') { cur += c; esc = true; continue; }
    if (c === '(') depth++; else if (c === ')') depth--;
    if (c === '|' && depth === 0) { out.push(cur); cur = ''; } else cur += c;
  }
  out.push(cur);
  return out.every((p) => /^\(.*\)$/.test(p)) ? out : null;
}

const kids = (n) => (Array.isArray(n && n.subregions) ? n.subregions : []);
const isObj = (n) => n && typeof n === 'object' && !Array.isArray(n);

// ---- SIMPLES: [{name, prefixes[]}] -------------------------------------------------------------
// motivo (código) de a árvore NÃO caber no modo, ou '' — a tela traduz (sitesFitText)
export function fitSimple(tree) {
  if (!Array.isArray(tree)) return 'not_list';
  for (const n of tree) {
    if (!isObj(n)) return 'not_list';
    if (n.view === true) return 'has_view';
    if (kids(n).length) return 'has_subregions';
    const rs = nodeRules(n);
    if (rs === null) return 'regex_free';
    if (rs.length > 1 || (rs.length === 1 && rs[0].t !== 'starts')) return 'rules_not_prefix';
  }
  return '';
}
export function toSimple(tree) {
  return (tree || []).map((n) => { const rs = nodeRules(n) || []; return { name: String(n.name || ''), prefixes: rs.length ? rs[0].v.slice() : [] }; });
}
export function fromSimple(sites) {
  return (sites || []).filter((s) => String(s.name || '').trim()).map((s) => {
    const pf = vals(s.prefixes); const node = { name: String(s.name).trim() };
    if (pf.length) { const rule = [{ t: 'starts', v: pf }]; node.regex = rulesRegex(rule); node.rule = rule; }
    return node;
  });
}

// ---- INTERMEDIÁRIO: [{name, rules[], sites?:[{name, rules[]}]}] (grupo = item com sites; grupo não tem regra)
export function fitRules(tree) {
  if (!Array.isArray(tree)) return 'not_list';
  for (const n of tree) {
    if (!isObj(n)) return 'not_list';
    if (n.view === true) return 'has_view';
    if (kids(n).length) {
      if (n.regex) return 'group_regex';
      for (const s of kids(n)) {
        if (!isObj(s)) return 'not_list';
        if (s.view === true) return 'has_view';
        if (kids(s).length) return 'too_deep';
        if (nodeRules(s) === null) return 'regex_free';
      }
    } else if (nodeRules(n) === null) return 'regex_free';
  }
  return '';
}
export function toRules(tree) {
  return (tree || []).map((n) => (kids(n).length
    ? { name: String(n.name || ''), group: true, sites: kids(n).map((s) => ({ name: String(s.name || ''), rules: nodeRules(s) || [] })) }
    : { name: String(n.name || ''), group: false, rules: nodeRules(n) || [] }));
}
const siteNode = (s) => {
  const node = { name: String(s.name).trim() };
  const rules = (s.rules || []).map((r) => ({ t: r.t, v: vals(r.v) })).filter((r) => r.v.length && RULE_TYPES.includes(r.t));
  if (rules.length) { node.regex = rulesRegex(rules); node.rule = rules; }
  return node;
};
export function fromRules(model) {
  return (model || []).filter((x) => String(x.name || '').trim()).map((x) => (x.group
    ? { name: String(x.name).trim(), subregions: (x.sites || []).filter((s) => String(s.name || '').trim()).map(siteNode) }
    : siteNode(x)));
}

// o modo mais simples que a árvore aceita
export function simplestMode(tree) { return !fitSimple(tree) ? 'simple' : (!fitRules(tree) ? 'rules' : 'tree'); }

// regex de uma regra ruim? (o rgNorm do gêmeo: o mesmo código de erro do servidor)
export function ruleError(rule) { const re = ruleRegex(rule); return re ? rgNorm(re).err : null; }

// renomear uma sede: as atribuições GRAVADAS com o nome velho passam p/ o novo. Devolve o delta (quantos
// times e quais) — a tela MOSTRA antes de salvar. `explicit` = Map login → sede gravada hoje; `pending` =
// Map login → sede proposta (muda no lugar).
export function renameAssignments(explicit, pending, oldName, newName) {
  const ok = rgKey(oldName), moved = [];
  if (!ok || rgKey(newName) === ok) return moved;
  const cur = new Map(explicit); pending.forEach((v, k) => cur.set(k, v));
  cur.forEach((reg, login) => { if (rgKey(reg) === ok) { pending.set(login, newName); moved.push(login); } });
  return moved;
}
