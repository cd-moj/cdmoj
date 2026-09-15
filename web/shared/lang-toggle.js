// shared/lang-toggle.js — os botões PT · EN do idioma da INTERFACE. Fonte única dos dois usos:
//   • header do site (`site-header.js`): a página RECARREGA (os módulos leem LANG no import);
//   • páginas estáticas bilíngues (tutoriais de papel): troca EM LUGAR — o `i18n-dom.js` é
//     reversível e escuta `moj:lang` — e grava a escolha (localStorage, via setLang persist).
// O `?lang=` da URL acompanha o clique: é o link que a pessoa copia e manda adiante, e, sem
// isso, um reload com `?lang=en` na barra desfaria o clique em PT (o `?lang=` vence o seletor).
// Nunca dentro de contest (o LOCALE da prova manda no idioma).
import { el } from '/shared/dom.js';
import { T, getLang, setLang } from '/shared/i18n.js';

export function mkLangToggle({ reload = true } = {}) {
  const wrap = el('span', { class: 'lang-toggle', title: T('Idioma da interface', 'Interface language') });
  const paint = () => [...wrap.children].forEach((b) => {
    const on = b.dataset.lang === getLang();
    b.classList.toggle('active', on); b.setAttribute('aria-pressed', on ? 'true' : 'false');
  });
  ['pt', 'en'].forEach((l) => {
    const b = el('button', { type: 'button', class: 'lang-opt', 'aria-pressed': 'false', onclick: () => {
      if (l === getLang()) return;
      setLang(l, { persist: true });
      try {
        const u = new URL(location.href);
        if (!reload || u.searchParams.has('lang')) { u.searchParams.set('lang', l); history.replaceState(null, '', u); }
      } catch { /* URL indisponível */ }
      if (reload) location.reload(); else paint();
    } }, l.toUpperCase());
    b.dataset.lang = l; wrap.append(b);
  });
  paint();
  document.addEventListener('moj:lang', paint);
  return wrap;
}
