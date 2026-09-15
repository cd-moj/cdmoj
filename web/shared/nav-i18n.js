// shared/nav-i18n.js — rótulos BILÍNGUES da nav do contest. O servidor (navbuttons.sh)
// manda o label em PT; a URL é o identificador estável — aqui ela vira o rótulo no idioma
// corrente (T resolve na RENDERIZAÇÃO; quem pinta a nav re-renderiza no evento moj:lang).
// Botão sem entrada no mapa cai no label do servidor (botão novo nunca some — só fica PT
// até ganhar a linha aqui). Entradas só onde PT != EN (Contest/Score/Backup/jplag/Logout/
// Animeitor são neutros). SEM EMOJI nos botões da nav (issue #28, 2026-09-15): a barra
// misturava "⚙ Administração" com "Score" e "jplag"; emoji fica nos títulos de painel/seção.
import { T } from '/shared/i18n.js';

const MAP = {
  '/contest/score/reveal.html': ['Revelação', 'Reveal'],
  '/contest/admin/':            ['Administração', 'Administration'],
  '/contest/allsubmissions/':   ['Todas Submissões', 'All Submissions'],
  '/contest/submissions/':      ['Minhas submissões', 'My submissions'],
  '/contest/statistics/':       ['Estatísticas', 'Statistics'],
  '/contest/rounds/':           ['Rodadas', 'Rounds'],
  '/contest/judge/':            ['Avaliar', 'Judge'],
  '/contest/chief/':            ['Juiz-chefe', 'Chief judge'],
  '/contest/staff/':            ['Impressão', 'Print queue'],
  '/contest/badges/':           ['Etiquetas', 'Badges'],
  '/contest/docs/':             ['Documentos', 'Documents'],
  '/contest/print/':            ['Impressão', 'Printing'],
};

export function navLabel(url, serverLabel) {
  const p = String(url || '').split('?')[0].split('#')[0];
  const pair = MAP[p] || MAP[p.replace(/\/*$/, '/')];
  return pair ? T(pair[0], pair[1]) : (serverLabel || p);
}
