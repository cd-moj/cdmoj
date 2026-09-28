// shared/nav-i18n.js — rótulos BILÍNGUES da nav do contest. O servidor (navbuttons.sh)
// manda o label em PT; a URL é o identificador estável — aqui ela vira o rótulo no idioma
// corrente (T resolve na RENDERIZAÇÃO; quem pinta a nav re-renderiza no evento moj:lang).
// Botão sem entrada no mapa cai no label do servidor (botão novo nunca some — só fica PT
// até ganhar a linha aqui). Entradas só onde PT != EN (Contest/Score/Backup/jplag/Logout/
// Animeitor são neutros). SEM EMOJI nos botões da nav (issue #28, 2026-09-15): a barra
// misturava "⚙ Administração" com "Score" e "jplag"; emoji fica nos títulos de painel/seção.
import { T } from '/shared/i18n.js';

const MAP = {
  '/contest/score/reveal.html': ['Revelação', 'Reveal', 'Revelación'],
  '/contest/admin/':            ['Administração', 'Administration', 'Administración'],
  '/contest/allsubmissions/':   ['Todas Submissões', 'All Submissions', 'Todos los envíos'],
  '/contest/submissions/':      ['Minhas submissões', 'My submissions', 'Mis envíos'],
  '/contest/statistics/':       ['Estatísticas', 'Statistics', 'Estadísticas'],
  '/contest/rounds/':           ['Rodadas', 'Rounds', 'Rondas'],
  '/contest/judge/':            ['Avaliar', 'Judge', 'Evaluar'],
  '/contest/chief/':            ['Juiz-chefe', 'Chief judge', 'Juez principal'],
  '/contest/staff/':            ['Impressão', 'Print queue', 'Cola de impresión'],
  '/contest/badges/':           ['Etiquetas', 'Badges', 'Etiquetas'],
  '/contest/docs/':             ['Documentos', 'Documents', 'Documentos'],
  '/contest/print/':            ['Impressão', 'Printing', 'Impresión'],
};

export function navLabel(url, serverLabel) {
  const p = String(url || '').split('?')[0].split('#')[0];
  const pair = MAP[p] || MAP[p.replace(/\/*$/, '/')];
  return pair ? T(pair[0], pair[1], pair[2]) : (serverLabel || p);
}
