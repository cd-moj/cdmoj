// shared/i18n-dom.js — traduz o texto ESTÁTICO do HTML (o que não é renderizado por JS).
//
// Anote a versão inglesa direto no markup e este módulo troca quando LANG==='en':
//   <span data-en="Home">Início</span>                     -> textContent
//   <input data-en-ph="Search…" placeholder="Buscar…">     -> placeholder
//   <a data-en-title="Edit profile" title="Editar perfil"> -> title
//   <h1 data-en-html="Welcome <b>back</b>">Bem-vindo…</h1>  -> innerHTML (raro)
//   <html data-en-doctitle="MOJ — Home">                   -> document.title
// O PT fica no conteúdo/atributo normal (idioma base) e é CAPTURADO em data-pt-* na
// primeira aplicação — assim a troca é REVERSÍVEL (EN→PT restaura; antes, abrir com
// moj_lang=en e cair num contest LOCALE=pt deixava o estático preso em inglês).
//
// Uso: inclua ANTES do <script> da página (módulos são deferred, rodam em ordem):
//   <script type="module" src="/shared/i18n-dom.js"></script>
import { getLang } from '/shared/i18n.js';

export function i18nDOM(root = document) {
  const en = getLang() === 'en';
  root.querySelectorAll('[data-en]').forEach((e) => {
    if (e.dataset.pt === undefined) e.dataset.pt = e.textContent;
    e.textContent = en ? e.getAttribute('data-en') : e.dataset.pt;
  });
  root.querySelectorAll('[data-en-html]').forEach((e) => {
    if (e.dataset.ptHtml === undefined) e.dataset.ptHtml = e.innerHTML;
    e.innerHTML = en ? e.getAttribute('data-en-html') : e.dataset.ptHtml;
  });
  root.querySelectorAll('[data-en-ph]').forEach((e) => {
    if (e.dataset.ptPh === undefined) e.dataset.ptPh = e.getAttribute('placeholder') || '';
    e.setAttribute('placeholder', en ? e.getAttribute('data-en-ph') : e.dataset.ptPh);
  });
  root.querySelectorAll('[data-en-title]').forEach((e) => {
    if (e.dataset.ptTitle === undefined) e.dataset.ptTitle = e.getAttribute('title') || '';
    e.setAttribute('title', en ? e.getAttribute('data-en-title') : e.dataset.ptTitle);
  });
  // doctitle: só alterna entre os DOIS títulos estáticos — título dinâmico (ex.: nome do
  // contest, posto depois pelo app) não é tocado.
  const de = document.documentElement;
  const dt = de.getAttribute('data-en-doctitle');
  if (dt) {
    if (de.dataset.ptDoctitle === undefined) de.dataset.ptDoctitle = document.title;
    if (en) { if (document.title === de.dataset.ptDoctitle) document.title = dt; }
    else if (document.title === dt) document.title = de.dataset.ptDoctitle;
  }
}

// auto-init: o DOM já está parseado quando um módulo deferred roda.
i18nDOM();
// reaplica quando o idioma muda em runtime (ex.: página de contest chama setLang(LOCALE)
// depois de carregar /contest/basic) — assim o texto estático segue o idioma do contest.
document.addEventListener('moj:lang', () => i18nDOM());
