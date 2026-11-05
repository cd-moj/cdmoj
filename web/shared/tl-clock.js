// tl-clock.js — o RELÓGIO do TL na tela do aluno (TLCLOCK=cpu no pacote; mojtools build-and-test, 05/11/2026).
// No relógio de CPU o TL é cobrado pelo tempo de CPU (user+sys) e a parede é só um teto maior: 3 × o limite, no
// mínimo o limite + 3,2 s, ou o WALLTL do pacote se for maior — quem fica parado esperando ou dorme leva TLE nele.
// O padrão (parede) não mostra nada. Treino (problema.js) e contest (contest.js) usam ESTE módulo: a frase é uma só
// nos três idiomas e a mesma da folha de TL da prova (server lib/contest-docs.sh, `tl_cpu`).
import { el } from './dom.js';
import { T } from './i18n.js';

export function tlClockIsCpu(p) { return !!p && p.tl_clock === 'cpu'; }

// texto do title (a explicação inteira); wall_tl do pacote = o mínimo do teto de parede, quando existe
export function tlClockTitle(p) {
  const w = p && typeof p.wall_tl === 'number' && p.wall_tl > 0 ? p.wall_tl : null;
  const fmt = (x) => String(x).replace('.', T(',', '.', ','));
  const base = T(
    'Limite em tempo de CPU (user+sys). O programa também é interrompido, com TLE, se o tempo de relógio passar de 3 vezes o limite (no mínimo o limite + 3,2 s)',
    'Limit in CPU time (user+sys). The program is also stopped, with TLE, if the wall-clock time exceeds 3 times the limit (at least the limit + 3.2 s)',
    'Límite en tiempo de CPU (user+sys). El programa también se detiene, con TLE, si el tiempo de reloj supera 3 veces el límite (como mínimo el límite + 3,2 s)');
  const extra = w ? T(` e nunca antes de ${fmt(w)} s`, ` and never before ${fmt(w)} s`, ` y nunca antes de ${fmt(w)} s`) : '';
  return base + extra + T(': quem fica parado esperando ou dormindo não escapa.', ': waiting or sleeping does not get around it.', ': quedarse esperando o dormido no lo evita.');
}

// o selo ao lado do "⏱ Tempo limite" (null no relógio de parede)
export function tlClockBadge(p) {
  if (!tlClockIsCpu(p)) return null;
  return el('span', { class: 'tl-clock', title: tlClockTitle(p) }, T('tempo de CPU', 'CPU time', 'tiempo de CPU'));
}
