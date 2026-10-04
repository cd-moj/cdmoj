// shared/problem-titles.js — O NOME DE UM PROBLEMA NO CONTEST × os títulos do banco por idioma (03/10/2026).
// O problema pode ter título em pt/en/es (um por enunciado traduzido). As listas do banco (busca e sorteio)
// e o GET /contest/admin/problems trazem `titles` {pt,en,es} SÓ quando há mais de um título distinto; sem o
// campo, o único título é o `title`. O NOME padrão (spec/inclusão sem nome) é decidido pelo SERVIDOR: o
// título no idioma em que a sanfona abre (LOCALE, salvo STATEMENT_LANGS sem ele), senão o PT — cc_prob_title
// em lib/contest-create.sh. `autoTitle` é o gêmeo dessa regra p/ a tela MOSTRAR o que será usado.
import { el } from '/shared/dom.js';
import { T } from '/shared/i18n.js';
import { STMT_LANGS, STMT_SHORT, stmtName, stmtHtmlLang } from '/shared/statement-langs.js';

// titleOptions(titles) -> [[lang, título], …] na ordem pt·en·es, só os não vazios
export function titleOptions(titles) {
  const t = (titles && typeof titles === 'object') ? titles : {};
  return STMT_LANGS.filter((l) => typeof t[l] === 'string' && t[l].trim()).map((l) => [l, t[l]]);
}
// hasTitleChoice(titles) -> há mais de um título DISTINTO (só então a tela oferece a escolha)
export function hasTitleChoice(titles) {
  return new Set(titleOptions(titles).map(([, v]) => v)).size > 1;
}
// autoTitle(titles, lang, fallback) — o nome padrão: o título no idioma, senão o PT, senão o fallback
export function autoTitle(titles, lang, fallback) {
  const t = (titles && typeof titles === 'object') ? titles : {};
  return (lang && t[lang]) || t.pt || fallback || '';
}

// makeTitleChips(titles, getCur, onPick) -> <span class="title-chips"> com um botão PT/EN/ES por título
// (vazio sem escolha). O clique PREENCHE o nome (onPick(título, lang)); o ativo é o que bate com o nome atual,
// lido na hora (getCur()) — o campo pode ter sido digitado depois.
export function makeTitleChips(titles, getCur, onPick) {
  const box = el('span', { class: 'stmt-chips title-chips', role: 'group',
    'aria-label': T('Título em outro idioma', 'Title in another language', 'Título en otro idioma') });
  if (!hasTitleChoice(titles)) return box;
  const paint = () => {
    const cur = (getCur() || '').trim();
    [...box.querySelectorAll('.stmt-chip')].forEach((b) => b.classList.toggle('active', b.dataset.title === cur));
  };
  titleOptions(titles).forEach(([l, v]) => {
    const b = el('button', { type: 'button', class: 'stmt-chip', lang: stmtHtmlLang(l),
      title: stmtName(l) + ': ' + v }, STMT_SHORT[l] || l.toUpperCase());
    b.dataset.lang = l; b.dataset.title = v;
    b.addEventListener('click', () => { onPick(v, l); paint(); });
    box.append(b);
  });
  box.repaint = paint;
  paint();
  return box;
}

// titlesLine(titles) -> "PT Título · EN Title · ES Título" (as opções, numa linha, p/ a lista do banco)
export function titlesLine(titles) {
  if (!hasTitleChoice(titles)) return '';
  return el('div', { class: 'small muted', title: T('Títulos do problema por idioma; o nome no contest segue o idioma da prova e pode ser trocado depois.',
    "The problem's titles by language; the name in the contest follows the contest language and can be changed later.",
    'Títulos del problema por idioma; el nombre en la competencia sigue el idioma de la competencia y se puede cambiar después.') },
  '🌐 ', titleOptions(titles).map(([l, v]) => (STMT_SHORT[l] || l.toUpperCase()) + ' ' + v).join(' · '));
}
