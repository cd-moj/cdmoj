// shared/statement-langs.js — IDIOMA DO ENUNCIADO (pt/en/es), o eixo dos DOCUMENTOS — não o da
// interface (i18n.js é só pt|en). O pacote pode trazer docs/enunciado.<lang>.md; o treino serve
// `statement_langs` + `statements{<lang>:{title,html_b64}}`; o contest oferece a lista
// `STATEMENT_LANGS` e o corpo sai de /contest/statement?lang=. Aqui mora o que as três telas
// (treino, contest, editor) repetem: a allowlist, os rótulos, a escolha lembrada e os chips.
import { el } from '/shared/dom.js';
import { T, getLang } from '/shared/i18n.js';

export const STMT_LANGS = ['pt', 'en', 'es'];
export const STMT_SHORT = { pt: 'PT', en: 'EN', es: 'ES' };
export const stmtName = (l) => ({ pt: T('Português', 'Portuguese'), en: T('Inglês', 'English'), es: T('Espanhol', 'Spanish') }[l] || l);
export const stmtHtmlLang = (l) => (l === 'en' ? 'en' : l === 'es' ? 'es' : 'pt-br');
const KEY = 'moj_stmt_lang';

export function rememberStmtLang(l) { try { localStorage.setItem(KEY, l); } catch { /* storage indisponível */ } }
function remembered() { try { return localStorage.getItem(KEY) || ''; } catch { return ''; } }

// pickStmtLang(disponíveis, default) — a ordem: ?lang= da URL › escolha lembrada › default do
// servidor (LOCALE do contest) › idioma da interface › o 1º disponível. Só devolve idioma da lista.
export function pickStmtLang(avail, def) {
  const list = (avail && avail.length) ? avail : ['pt'];
  const ok = (l) => l && list.includes(l);
  let q = ''; try { q = new URLSearchParams(location.search).get('lang') || ''; } catch { /* */ }
  for (const c of [q, remembered(), def, getLang() === 'en' ? 'en' : 'pt']) if (ok(c)) return c;
  return list[0];
}

// makeStmtLangChips(disponíveis, atual, onPick) -> <div class="stmt-chips"> (vazio se só 1 idioma)
export function makeStmtLangChips(avail, cur, onPick) {
  const box = el('div', { class: 'stmt-chips', role: 'group', 'aria-label': T('Idioma do enunciado', 'Statement language') });
  const list = (avail && avail.length) ? avail : ['pt'];
  if (list.length < 2) return box;
  list.forEach((l) => {
    const b = el('button', { type: 'button', class: 'stmt-chip' + (l === cur ? ' active' : ''), title: stmtName(l), lang: stmtHtmlLang(l) }, STMT_SHORT[l] || l.toUpperCase());
    b.dataset.lang = l;
    b.addEventListener('click', () => { if (l === cur) return; onPick(l); });
    box.append(b);
  });
  return box;
}
export function setChipsActive(box, cur) {
  if (!box) return;
  [...box.querySelectorAll('.stmt-chip')].forEach((b) => b.classList.toggle('active', b.dataset.lang === cur));
}
