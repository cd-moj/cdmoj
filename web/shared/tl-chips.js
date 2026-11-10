// tl-chips.js — os CHIPS DE TEMPO-LIMITE ("⏱ Tempo limite  C 1 s  Python 3 s") — FONTE ÚNICA (10/11/2026) do contest
// (contest.js), do treino (problema.js) e da participação virtual (treino/virtual): eram duas cópias, e o virtual não
// mostrava o TL (relato de usuário: "não consegui achar os tempos limites").
// Regras:
//   · TL ÚNICO (`tl_unified`, TLUNIFIED=y no pacote) com todos os valores iguais = UM chip "todas as linguagens" (se um
//     ajuste por linguagem do conf desfez a igualdade, os chips de sempre: a tela nunca esconde um TL diferente);
//   · com a lista de linguagens da prova (`langs`, objetos de shared/languages.js) = um chip POR linguagem permitida (o
//     TL medido dela, senão o `default`) e sem o "padrão" — a lista é fechada;
//   · sem lista = todas as chaves, o "padrão" primeiro.
// O selo do relógio de CPU (tl-clock.js) vai ao lado do rótulo.
import { el } from './dom.js';
import { T } from './i18n.js';
import { langById } from './languages.js';
import { tlClockBadge } from './tl-clock.js';

export function fmtTime(v) {
  const n = parseFloat(v);
  if (isNaN(n)) return String(v);
  return n < 1 ? Math.round(n * 1000) + ' ms' : (Math.round(n * 1000) / 1000) + ' s';
}

// tlChips(p, langs?) -> [{label, time}]
export function tlChips(p, langs) {
  const tl = (p && p.time_limits) || {};
  const keys = Object.keys(tl);
  if (!keys.length) return [];
  if (p.tl_unified && new Set(Object.values(tl).map((v) => String(+v))).size === 1) {
    return [{ label: T('todas as linguagens', 'all languages', 'todos los lenguajes'), time: Object.values(tl)[0] }];
  }
  if (Array.isArray(langs) && langs.length) {
    return langs.map((l) => ({ label: l.label, time: tl[l.id] != null ? tl[l.id] : tl.default })).filter((c) => c.time != null);
  }
  return keys.sort((a, b) => (a === 'default' ? -1 : b === 'default' ? 1 : a.localeCompare(b)))
    .map((k) => ({ label: k === 'default' ? T('padrão', 'default', 'predeterminado') : (langById(k).label || k), time: tl[k] }));
}

// tlParts(p, langs?) -> os nós do bloco (rótulo, selo do relógio, chips) ou [] sem TL — o chamador os põe no contêiner
export function tlParts(p, langs) {
  const chips = tlChips(p, langs);
  if (!chips.length) return [];
  const out = [el('span', { class: 'tl-label' }, '⏱ ' + T('Tempo limite', 'Time limit', 'Límite de tiempo'))];
  const clk = tlClockBadge(p); if (clk) out.push(clk);
  chips.forEach((c) => out.push(el('span', { class: 'tl-chip' }, el('b', {}, c.label), el('span', { class: 'tl-time' }, fmtTime(c.time)))));
  return out;
}
