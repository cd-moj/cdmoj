// shared/i18n.js — internacionalização mínima pt/en.
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
let LANG = localStorage.getItem('moj_lang') || (navigator.language || 'pt').slice(0, 2);
if (!STR[LANG]) LANG = 'pt';
export function t(k) { return (STR[LANG] && STR[LANG][k]) || STR.pt[k] || k; }
export function setLang(l) { if (STR[l]) { LANG = l; localStorage.setItem('moj_lang', l); } }
export function getLang() { return LANG; }
