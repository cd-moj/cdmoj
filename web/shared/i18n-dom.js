// shared/i18n-dom.js — traduz o texto ESTÁTICO do HTML (o que não é renderizado por JS).
//
// Anote as versões inglesa e espanhola direto no markup e este módulo troca conforme o LANG:
//   <span data-en="Home" data-es="Inicio">Início</span>                        -> textContent
//   <input data-en-ph="Search…" data-es-ph="Buscar…" placeholder="Buscar…">    -> placeholder
//   <a data-en-title="Edit profile" data-es-title="Editar perfil" title="…">   -> title
//   <h1 data-en-html="Welcome <b>back</b>" data-es-html="…">Bem-vindo…</h1>     -> innerHTML (raro)
//   <a href="/docs/X.html" data-en-href="/docs/en/X.html" data-es-href="…">      -> href (doc traduzido)
//   <html data-en-doctitle="MOJ — Home" data-es-doctitle="MOJ — Inicio">       -> document.title
// O PT fica no conteúdo/atributo normal (idioma base) e é CAPTURADO em data-pt-* na primeira
// aplicação — assim a troca é REVERSÍVEL (qualquer idioma → PT restaura; antes, abrir com
// moj_lang=en e cair num contest LOCALE=pt deixava o estático preso em inglês).
// Mesma cascata do T(): em espanhol, `data-es*` ausente cai no `data-en*` (e este no PT).
//
// Uso: inclua ANTES do <script> da página (módulos são deferred, rodam em ordem):
//   <script type="module" src="/shared/i18n-dom.js"></script>
import { getLang } from '/shared/i18n.js';

// [sufixo do atributo, chave do data-pt-*, como ler o PT, como escrever]
const KINDS = [
  ['', 'pt', (e) => e.textContent, (e, v) => { e.textContent = v; }],
  ['-html', 'ptHtml', (e) => e.innerHTML, (e, v) => { e.innerHTML = v; }],
  ['-ph', 'ptPh', (e) => e.getAttribute('placeholder') || '', (e, v) => e.setAttribute('placeholder', v)],
  ['-title', 'ptTitle', (e) => e.getAttribute('title') || '', (e, v) => e.setAttribute('title', v)],
  // getAttribute, nunca `.href` (a propriedade devolve a URL ABSOLUTA e o PT capturado mudaria de forma)
  ['-href', 'ptHref', (e) => e.getAttribute('href') || '', (e, v) => e.setAttribute('href', v)],
];

export function i18nDOM(root = document) {
  const lang = getLang();
  for (const [suf, key, read, write] of KINDS) {
    root.querySelectorAll(`[data-en${suf}],[data-es${suf}]`).forEach((e) => {
      if (e.dataset[key] === undefined) e.dataset[key] = read(e);
      const pt = e.dataset[key], en = e.getAttribute(`data-en${suf}`), es = e.getAttribute(`data-es${suf}`);
      write(e, lang === 'es' ? (es ?? en ?? pt) : (lang === 'en' ? (en ?? pt) : pt));
    });
  }
  // doctitle: só alterna entre os títulos ESTÁTICOS — título dinâmico (ex.: nome do contest, posto
  // depois pelo app) não é tocado.
  const de = document.documentElement;
  const dEn = de.getAttribute('data-en-doctitle'), dEs = de.getAttribute('data-es-doctitle');
  if (dEn || dEs) {
    if (de.dataset.ptDoctitle === undefined) de.dataset.ptDoctitle = document.title;
    const pt = de.dataset.ptDoctitle, statics = [pt, dEn, dEs].filter((x) => x != null);
    const want = lang === 'es' ? (dEs ?? dEn ?? pt) : (lang === 'en' ? (dEn ?? pt) : pt);
    if (statics.includes(document.title)) document.title = want;
  }
}

// auto-init: o DOM já está parseado quando um módulo deferred roda.
i18nDOM();
// reaplica quando o idioma muda em runtime (ex.: página de contest chama setLang(LOCALE)
// depois de carregar /contest/basic) — assim o texto estático segue o idioma do contest.
document.addEventListener('moj:lang', () => i18nDOM());
