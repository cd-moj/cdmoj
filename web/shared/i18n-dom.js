// shared/i18n-dom.js — traduz o texto ESTÁTICO do HTML (o que não é renderizado por JS).
//
// Anote a versão inglesa direto no markup e este módulo troca quando LANG==='en':
//   <span data-en="Home">Início</span>                     -> textContent
//   <input data-en-ph="Search…" placeholder="Buscar…">     -> placeholder
//   <a data-en-title="Edit profile" title="Editar perfil"> -> title
//   <h1 data-en-html="Welcome <b>back</b>">Bem-vindo…</h1>  -> innerHTML (raro)
//   <html data-en-doctitle="MOJ — Home">                   -> document.title
// O PT fica no conteúdo/atributo normal (idioma base). Em pt, este módulo é no-op.
//
// Uso: inclua ANTES do <script> da página (módulos são deferred, rodam em ordem):
//   <script type="module" src="/shared/i18n-dom.js"></script>
import { getLang } from '/shared/i18n.js';

export function i18nDOM(root = document) {
  if (getLang() !== 'en') return;
  root.querySelectorAll('[data-en]').forEach((e) => { e.textContent = e.getAttribute('data-en'); });
  root.querySelectorAll('[data-en-html]').forEach((e) => { e.innerHTML = e.getAttribute('data-en-html'); });
  root.querySelectorAll('[data-en-ph]').forEach((e) => { e.setAttribute('placeholder', e.getAttribute('data-en-ph')); });
  root.querySelectorAll('[data-en-title]').forEach((e) => { e.setAttribute('title', e.getAttribute('data-en-title')); });
  const dt = document.documentElement.getAttribute('data-en-doctitle');
  if (dt) document.title = dt;
}

// auto-init: o DOM já está parseado quando um módulo deferred roda.
i18nDOM();
