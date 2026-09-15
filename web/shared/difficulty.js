// shared/difficulty.js — DIFICULDADE e DIRT de um problema: fonte ÚNICA do lado da web
// (issue #30, 2026-09-15). Gêmeo de server/api/v1/lib/difficulty.sh — as faixas são as mesmas.
//
//   dificuldade = "quem tenta consegue?": taxa POR USUÁRIO (resolveram ÷ tentaram, distintos):
//       ≥ .9 muito fácil · ≥ .7 fácil · ≥ .5 médio · < .5 difícil · sem tentantes = novo
//   dirt        = "quanto se erra até acertar": (submissões de quem resolveu até o 1º AC − ACs)
//       ÷ (essas submissões) — a métrica do resolver do ICPC, a mesma das estatísticas do contest.
//
// O servidor já manda `difficulty` (chave) e `dirt` em /treino/problems, /treino/problem-stats e
// /contest/statistics; `diffKeyOf` PREFERE a chave do servidor e só recalcula dos counts quando
// ela falta (cache velho). Nenhuma outra tela recalcula faixa — a inconsistência veio disso.
import { T } from '/shared/i18n.js';

export const DIFF_KEYS = ['veasy', 'easy', 'med', 'hard', 'new'];
export const DIFF_META = {
  veasy: { pt: 'muito fácil', en: 'very easy', cls: 'diff-easy', color: '#15803d' },
  easy:  { pt: 'fácil',       en: 'easy',      cls: 'diff-easy', color: '#4ca464' },
  med:   { pt: 'médio',       en: 'medium',    cls: 'diff-med',  color: '#9a6700' },
  hard:  { pt: 'difícil',     en: 'hard',      cls: 'diff-hard', color: '#be1241' },
  new:   { pt: 'novo',        en: 'new',       cls: '',          color: '#64748b' },
};
export const DIFF_VEASY = 0.9, DIFF_EASY = 0.7, DIFF_MED = 0.5;

// taxa por usuário -> chave (null/undefined = sem tentantes = 'new')
export function diffKeyFromRate(rate) {
  if (rate == null || Number.isNaN(rate)) return 'new';
  return rate >= DIFF_VEASY ? 'veasy' : rate >= DIFF_EASY ? 'easy' : rate >= DIFF_MED ? 'med' : 'hard';
}
// objeto de problema (da lista do treino ou do stats) -> chave
export function diffKeyOf(p) {
  if (!p) return 'new';
  if (p.difficulty && DIFF_META[p.difficulty]) return p.difficulty;
  const a = p.attempted_count || p.distinct_attempted || 0;
  if (!a) return 'new';
  return diffKeyFromRate((p.solved_count || p.distinct_solved || 0) / a);
}
export function diffLabel(key) { const m = DIFF_META[key] || DIFF_META.new; return T(m.pt, m.en); }
export function diffClass(key) { return (DIFF_META[key] || DIFF_META.new).cls; }
export function diffColor(key) { return (DIFF_META[key] || DIFF_META.new).color; }
// {key,label,cls,color} de um problema — o pacote que as telas pintam
export function difficultyOf(p) { const k = diffKeyOf(p); return { key: k, label: diffLabel(k), cls: diffClass(k), color: diffColor(k) }; }
// taxa por usuário de um problema (0..1) ou null
export function userRateOf(p) {
  if (!p) return null;
  if (typeof p.user_rate === 'number') return p.user_rate;
  const a = p.attempted_count || p.distinct_attempted || 0;
  return a ? (p.solved_count || p.distinct_solved || 0) / a : null;
}

// dirt: tom p/ colorir (baixo ≤ .2 · médio ≤ .5 · alto) e texto "35%"
export function dirtTone(d) { if (d == null) return ''; return d <= 0.2 ? 'dirt-low' : d <= 0.5 ? 'dirt-mid' : 'dirt-high'; }
export function dirtText(d) { return d == null ? '—' : Math.round(d * 100) + '%'; }
export const dirtHelp = () => T('dirt: parte das submissões de quem RESOLVEU que estava errada (métrica do resolver do ICPC). Alto = o problema pune erros.',
  'dirt: the part of the SOLVERS’ submissions that was wrong (ICPC resolver metric). High = the problem punishes mistakes.');
export const difficultyHelp = () => T('dificuldade: quem tenta consegue? Taxa por usuário (resolveram ÷ tentaram): ≥90% muito fácil · ≥70% fácil · ≥50% médio · <50% difícil.',
  'difficulty: do those who try succeed? Per-user rate (solved ÷ attempted): ≥90% very easy · ≥70% easy · ≥50% medium · <50% hard.');
