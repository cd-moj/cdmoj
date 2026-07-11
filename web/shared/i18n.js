// shared/i18n.js — internacionalização pt/en UNIFICADA (mecanismo único da web).
//
// `T(pt, en)` é o jeito canônico de escrever QUALQUER string de exibição no JS
// (o par HTML é o atributo `data-en` + shared/i18n-dom.js). Um só `LANG` de módulo
// governa tudo. Precedência de idioma:
//   1. LOCALE do contest (explícito, em página de contest) — via setLang(loc) sem persist;
//   2. escolha manual do usuário (seletor pt/en no header) — localStorage 'moj_lang';
//   3. idioma do browser (navigator.language): não-português => inglês.
// Regra do projeto: TODA tela/string nova nasce nos DOIS idiomas (PT-only = bug).

const STORE_KEY = 'moj_lang';
const browserLang = () =>
  (navigator.language || 'pt').toLowerCase().startsWith('pt') ? 'pt' : 'en';

let LANG = localStorage.getItem(STORE_KEY) || browserLang();
if (LANG !== 'pt' && LANG !== 'en') LANG = 'pt';
applyHtmlLang();

export function getLang() { return LANG; }

// setLang(l, {persist}) — persist:true = escolha do usuário (grava e vale em todo o site);
// persist:false (default) = idioma imposto pelo contest, EFÊMERO (não vaza p/ páginas públicas).
export function setLang(l, { persist = false } = {}) {
  if (l !== 'pt' && l !== 'en') return;
  LANG = l;
  if (persist) { try { localStorage.setItem(STORE_KEY, l); } catch (_) {} }
  applyHtmlLang();
}

function applyHtmlLang() {
  try { document.documentElement.lang = LANG === 'en' ? 'en' : 'pt-br'; } catch (_) {}
}

// T(pt, en) — O mecanismo. `en` ausente cai no `pt` (nunca renderiza vazio).
export function T(pt, en) { return LANG === 'en' ? (en == null ? pt : en) : pt; }

// --- compat: dicionário keyed `t(key)`, agora reescrito sobre T (mesmo LANG). ----------
// Usado só pelo widget de auth (ui.js). Novos textos usam T('pt','en') direto.
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
};
export function t(k) { return T(STR.pt[k] || k, STR.en[k] || STR.pt[k] || k); }
