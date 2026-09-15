// contest/ajuda/_tutorial.js — comum aos tutoriais de papel (HTML estático bilíngue por data-en).
// Além do `?lang=` do link, os botões PT · EN no topbar trocam o idioma EM LUGAR e gravam a
// escolha (shared/lang-toggle.js). Inclua DEPOIS do i18n-dom.js.
import { mkLangToggle } from '/shared/lang-toggle.js';

const nav = document.querySelector('.topbar .navlinks');
if (nav) nav.append(mkLangToggle({ reload: false }));
