// shared/i18n.js — internacionalização pt/en/es UNIFICADA (mecanismo único da web).
//
// `T(pt, en, es)` é o jeito canônico de escrever QUALQUER string de exibição no JS
// (o par HTML são os atributos `data-en`/`data-es` + shared/i18n-dom.js). Um só `LANG` de módulo
// governa tudo. Precedência de idioma:
//   1. LOCALE do contest (explícito, em página de contest) — via setLang(loc) sem persist;
//   2. `?lang=` na URL — link explícito, e vale como escolha do usuário (grava);
//   3. escolha manual do usuário (seletor PT · EN · ES no header) — localStorage 'moj_lang';
//   4. idioma do browser (navigator.language): pt* ⇒ pt, es* ⇒ es, o resto ⇒ en.
// Regra do projeto: TODA tela/string nova nasce nos TRÊS idiomas (faltar um = bug; ver docs/I18N.md,
// que tem o glossário do espanhol). `es` ausente cai no `en` (e o `en` ausente no `pt`) — nunca vazio.
//
// O `?lang=` existe para o link que alguém MANDA: o e-mail de convocação p/ uma sede de fora,
// o tutorial passado adiante. Sem ele o destinatário abre no idioma do navegador DELE, e não
// há como quem escreve o e-mail garantir a versão certa. Três decisões:
//   • ele GRAVA (como o seletor do header) — senão o idioma se perderia no primeiro clique
//     dentro da página, que é o contrário do que quem abriu o link pediu;
//   • ele PERDE para o LOCALE do contest, exatamente como o seletor: dentro de uma prova quem
//     manda no idioma é a prova. Um só valor governa a tela toda;
//   • ele tem UM sentido só — o idioma da visita: vale p/ a interface E p/ o enunciado (o
//     statement-langs.js lê o mesmo parâmetro p/ escolher a aba do enunciado).
// Tag fora de pt/es cai em `en` (mesma regra do navegador). Valor vazio/ausente não mexe em nada.

const STORE_KEY = 'moj_lang';
export const LANGS = ['pt', 'en', 'es'];
const norm = (v) => { const x = String(v || '').toLowerCase(); return x.startsWith('pt') ? 'pt' : (x.startsWith('es') ? 'es' : 'en'); };
const browserLang = () => norm(navigator.language || 'pt');
const urlLang = () => {
  try {
    const v = new URLSearchParams(location.search).get('lang');
    return v ? norm(v) : null;
  } catch (_) { return null; }
};

const forced = urlLang();
let LANG = forced || localStorage.getItem(STORE_KEY) || browserLang();
if (!LANGS.includes(LANG)) LANG = 'pt';
if (forced) { try { localStorage.setItem(STORE_KEY, forced); } catch (_) {} }
applyHtmlLang();

export function getLang() { return LANG; }

// setLang(l, {persist}) — persist:true = escolha do usuário (grava e vale em todo o site);
// persist:false (default) = idioma imposto pelo contest, EFÊMERO (não vaza p/ páginas públicas).
export function setLang(l, { persist = false } = {}) {
  if (!LANGS.includes(l)) return;
  LANG = l;
  if (persist) { try { localStorage.setItem(STORE_KEY, l); } catch (_) {} }
  applyHtmlLang();
  // avisa quem traduz HTML estático (i18n-dom.js) p/ reaplicar quando o contest impõe o LOCALE
  try { document.dispatchEvent(new CustomEvent('moj:lang', { detail: LANG })); } catch (_) {}
}

function applyHtmlLang() {
  try { document.documentElement.lang = LANG === 'pt' ? 'pt-br' : LANG; } catch (_) {}
}

// DOCUMENTAÇÃO traduzida (docs/I18N.md, "Documentação"): os docs de USUÁRIO que existem em
// /docs/en/ e /docs/es/. ESPELHO do DOCS_I18N de docs/i18n.sh (paridade no smoke-docs-i18n.sh).
export const DOCS_I18N = ['MANUAL-CONTEST', 'MANUAL-TREINO', 'MANUAL-JUIZ', 'MANUAL-STAFF', 'MANUAL-ANIMEITOR'];
// docHref('MANUAL-ADMIN') — o link do doc no idioma da tela (o LOCALE do contest manda, como no T());
// doc não traduzido (ou pt) = o PT de sempre. No HTML estático o par é data-en-href/data-es-href.
export function docHref(name) {
  return (LANG !== 'pt' && DOCS_I18N.includes(name)) ? `/docs/${LANG}/${name}.html` : `/docs/${name}.html`;
}

// uiLocale() — a tag do Intl p/ datas/números no idioma da INTERFACE (toLocaleString(uiLocale(), …)).
// es-419 = espanhol da América Latina (o público das provas em espanhol).
export function uiLocale() { return LANG === 'pt' ? 'pt-BR' : (LANG === 'es' ? 'es-419' : 'en-US'); }

// T(pt, en, es) — O mecanismo. `es` ausente cai no `en`; `en` ausente cai no `pt` (nunca vazio).
export function T(pt, en, es) {
  if (LANG === 'es') return es != null ? es : (en != null ? en : pt);
  if (LANG === 'en') return en != null ? en : pt;
  return pt;
}

// --- compat: dicionário keyed `t(key)`, agora reescrito sobre T (mesmo LANG). ----------
// Usado só pelo widget de auth (ui.js). Novos textos usam T('pt','en','es') direto.
const STR = {
  pt: {
    login: 'Entrar', logout: 'Sair', user: 'Usuário', password: 'Senha',
    submit: 'Enviar', send_code: 'Enviar solução', upload: 'Escolher arquivo',
    problems: 'Problemas', search: 'Buscar', tags: 'Tags', score: 'Placar',
    contest: 'Prova', news: 'Notícias', training: 'Treino Livre', docs: 'Documentação',
    home: 'Página Inicial', solved: 'Resolvidos', attempted: 'Tentados',
    not_logged: 'Você não está logado', loading: 'carregando…',
    open: 'Abertos', upcoming: 'Por vir', closed: 'Encerrados',
    statement: 'Enunciado', show: 'mostrar', hide: 'esconder',
    history: 'Histórico de submissões', status: 'Status', language: 'Linguagem',
    datetime: 'Data/Hora', file: 'Arquivo', wrong_login: 'Usuário ou senha incorretos',
    create_account: 'Criar conta',
  },
  en: {
    login: 'Log in', logout: 'Log out', user: 'User', password: 'Password',
    submit: 'Submit', send_code: 'Submit solution', upload: 'Choose file',
    problems: 'Problems', search: 'Search', tags: 'Tags', score: 'Scoreboard',
    contest: 'Contest', news: 'News', training: 'Free Training', docs: 'Documentation',
    home: 'Home', solved: 'Solved', attempted: 'Attempted',
    not_logged: 'You are not logged in', loading: 'loading…',
    open: 'Open', upcoming: 'Upcoming', closed: 'Closed',
    statement: 'Statement', show: 'show', hide: 'hide',
    history: 'Submission history', status: 'Status', language: 'Language',
    datetime: 'Date/Time', file: 'File', wrong_login: 'Wrong user or password',
    create_account: 'Create account',
  },
  es: {
    login: 'Ingresar', logout: 'Salir', user: 'Usuario', password: 'Contraseña',
    submit: 'Enviar', send_code: 'Enviar solución', upload: 'Elegir archivo',
    problems: 'Problemas', search: 'Buscar', tags: 'Etiquetas', score: 'Marcador',
    contest: 'Competencia', news: 'Noticias', training: 'Entrenamiento libre', docs: 'Documentación',
    home: 'Inicio', solved: 'Resueltos', attempted: 'Intentados',
    not_logged: 'No has iniciado sesión', loading: 'cargando…',
    open: 'Abiertas', upcoming: 'Próximas', closed: 'Finalizadas',
    statement: 'Enunciado', show: 'mostrar', hide: 'ocultar',
    history: 'Historial de envíos', status: 'Estado', language: 'Lenguaje',
    datetime: 'Fecha/Hora', file: 'Archivo', wrong_login: 'Usuario o contraseña incorrectos',
    create_account: 'Crear cuenta',
  },
};
export function t(k) { return T(STR.pt[k] || k, STR.en[k] || STR.pt[k] || k, STR.es[k] || STR.en[k] || STR.pt[k] || k); }
