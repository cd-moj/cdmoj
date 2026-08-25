// contest/contest.js — entrada do contest: login full-screen (não logado) OU página
// principal (logado). Lê ?c=<contestId> da URL. Reusa shared/* e a API v1 real.
import { apiGet, apiGetText, apiGetBlob, apiPost, getToken } from '/shared/api.js';
import { login, logout, status, fileToBase64, textToBase64 } from '/shared/auth.js';
import { el, verdictClass, isPending, fmtDate, resumoText } from '/shared/ui.js';
import { createEditor } from '/shared/editor.js';
import { LANGUAGES, DEFAULT_SUBMIT_LANGUAGES, langById, extCanon } from '/shared/languages.js';
import { T, setLang, getLang } from '/shared/i18n.js';
import { navLabel } from '/shared/nav-i18n.js';
import { openHtmlReport } from '/shared/submission-links.js';
import { balloonColorHex, balloonSVG, balloonEdge, balloonTint } from '/contest/score/score-colors.js';

const qs = new URLSearchParams(location.search);
const CONTEST = (window.__MOJ_CONTEST || qs.get('c') || '');
// modo "só editor" (janela dedicada aberta pelo botão ⧉ Nova janela) p/ UM problema.
const EDITOR_ONLY = qs.get('editoronly') === '1';
const ONLY_PROB = qs.get('prob') || '';

// Linguagens: começa com TODAS as do MOJ (fonte única shared/languages.js) e é reduzida
// à whitelist do contest (conf LANGUAGES=) depois que /contest/basic carrega (resolveLangs).
let LANGS = LANGUAGES;
// conf LANGUAGES= traz tokens estilo FILETYPE ("C CPP PY3 JAVA"); mapeia p/ ids canônicos.
function normTok(t) {
  const a = { python: 'py', py3: 'py', py2: 'py', rust: 'rs', javascript: 'js', bash: 'sh', 'c++': 'cpp', cc: 'cpp', cxx: 'cpp' };
  const k = (t || '').toLowerCase();
  return a[k] || k;
}
function resolveLangs(tokens) {
  if (!Array.isArray(tokens) || !tokens.length) return LANGUAGES;
  const want = new Set(tokens.map(normTok));
  const sel = LANGUAGES.filter((l) => want.has(l.id));
  return sel.length ? sel : LANGUAGES;   // tokens exóticos (GREPE/MEPA/…) -> degrada p/ todas
}

// CSS do editor: tela cheia via <dialog> (top layer) + modo "só editor". Injetado uma vez.
// (.editor-box/.editor-bar/.cm-mojeditor já vêm de shared/ui.css.)
function injectEditorCss() {
  if (document.getElementById('editor-full-css')) return;
  const s = document.createElement('style'); s.id = 'editor-full-css';
  s.textContent = `
    dialog.editor-dialog{border:0;padding:0;margin:auto;background:transparent;width:96vw;height:94vh;max-width:96vw;max-height:96vh;overflow:visible}
    dialog.editor-dialog::backdrop{background:rgba(15,23,42,.5)}
    .editor-wrap{display:flex;flex-direction:column;gap:.3rem;margin:.4rem 0}
    .editor-wrap.editor-full{height:100%;margin:0;background:#fff;border-radius:10px;
      box-shadow:0 14px 50px rgba(0,0,0,.4);padding:.7rem 1rem 1rem;overflow:hidden}
    .editor-wrap.editor-full .editor-box{flex:1;min-height:0;max-height:none;overflow:auto;margin:0}
    .editor-wrap.editor-full .editor-box .cm-mojeditor,.editor-wrap.editor-full .editor-box .cm-editor{height:100%}
    body.editor-only #loginView{display:none}
    body.editor-only{margin:0;background:#fff}
    body.editor-only #mainView>*:not(.editor-only-host){display:none}
    body.editor-only .editor-only-host{height:100vh;display:flex;flex-direction:column;min-height:0;padding:.5rem;box-sizing:border-box}
    body.editor-only .editor-wrap{flex:1;display:flex;flex-direction:column;min-height:0;margin:0}
    body.editor-only .editor-box{flex:1;min-height:0;max-height:none;overflow:auto}
    body.editor-only .editor-box .cm-mojeditor,body.editor-only .editor-box .cm-editor{height:100%}`;
  document.head.append(s);
}

let basic = null;
let problems = [];
let balloons = {};
let userinfo = null;
let submissions = [];
let subSumm = {};   // subid -> resumo do /submission/summary (redigido por modo no servidor)
let subFilter = 'ALL';
let sortField = 'epoch', sortAsc = false;
let pollTimer = null;
let loginCountdownTimer = null, loginPollTimer = null;
let preStartTimer = null, preStartPoll = null;

// ---- helpers ---------------------------------------------------------------
function fmtLeft(sec) {
  if (sec < 0) sec = 0;
  const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
  const p = (x) => String(x).padStart(2, '0');
  return h > 0 ? `${p(h)}:${p(m)}:${p(s)}` : `${p(m)}:${p(s)}`;
}
// tempo-limite: segundos (string/num) -> "NNN ms" (<1s) ou "N.NNN s" (espelha o treino)
function fmtTime(v) {
  const n = parseFloat(v);
  if (isNaN(n)) return String(v);
  return n < 1 ? Math.round(n * 1000) + ' ms' : (Math.round(n * 1000) / 1000) + ' s';
}
function show(id) { document.getElementById(id).classList.remove('hidden'); }
function hide(id) { document.getElementById(id).classList.add('hidden'); }

// normaliza verdict (para classe de cor e ordenação)
function vClass(v) { return verdictClass(v); }

// cor do balão para um short_name (mapa hex SEM '#')
// cor/contorno/tom do balão: FONTE ÚNICA em contest/score/score-colors.js (aqui havia uma
// CÓPIA LITERAL das três funções — o tipo de duplicação que faz a correção nascer divergente)
const balloonColor = (shortName) => balloonColorHex(balloons, shortName);

// tintProbItem — a ÚNICA definição de como a linha de um problema RESOLVIDO se pinta.
// Antes a linha levava a cor CRUA no background e trocava `style.color`; isso (a) deixava o
// aceite do balão BRANCO idêntico ao não-aceito e (b) quebrava três coisas nas cores escuras:
// o título (.prob-full tem cor FIXA e não acompanhava), o hover (repinta o fundo e o color:#fff
// herdado ficava, texto branco sobre quase branco) e os links. Agora o fundo é o TOM CLARO da
// cor, a cor REAL vive na barra lateral (com contorno, que é o que faz a branca existir) e o
// texto nunca muda de cor. Ver web/contest/index.html (.prob-item.accepted).
function tintProbItem(item, accepted, color) {
  item.classList.toggle('accepted', accepted);
  item.style.color = '';                       // nunca mais mexer na cor do texto
  if (!accepted) { item.style.removeProperty('--bln'); item.style.removeProperty('--bln-edge');
                   item.style.removeProperty('--bln-tint'); item.style.background = ''; return; }
  const c = color || '#e2ffe9';
  item.style.setProperty('--bln', c);
  item.style.setProperty('--bln-edge', balloonEdge(c));
  item.style.setProperty('--bln-tint', color ? balloonTint(c) : '#e2ffe9');
  item.style.background = '';                  // quem pinta agora é o CSS
}

async function downloadAuthed(path, filename) {
  try {
    const r = await fetch('/api/v1' + path, { headers: { 'Authorization': 'Bearer ' + getToken(CONTEST) } });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const blob = await r.blob();
    const a = el('a', { href: URL.createObjectURL(blob), download: filename });
    document.body.append(a); a.click(); a.remove();
  } catch { alert(T('Falha ao baixar arquivo/log.', 'Failed to download file/log.')); }
}
async function openLogAuthed(path) {
  try {
    const r = await fetch('/api/v1' + path, { headers: { 'Authorization': 'Bearer ' + getToken(CONTEST) } });
    const txt = await r.text();
    const w = window.open();
    const pre = w.document.createElement('pre');
    pre.style.cssText = 'font-family:monospace;white-space:pre-wrap;padding:1rem';
    pre.textContent = txt;
    w.document.body.append(pre);
    w.document.close();
  } catch { alert(T('Falha ao abrir o log.', 'Failed to open log.')); }
}

// abre o report.html do julgamento numa aba nova (openHtmlReport: blob, nunca srcdoc — é o que
// faz as âncoras dos casos de teste rolarem em vez de navegar; ver shared/submission-links.js).
async function openReportAuthed(path) {
  try {
    const r = await fetch('/api/v1' + path, { headers: { 'Authorization': 'Bearer ' + getToken(CONTEST) } });
    openHtmlReport(await r.text());
  } catch { alert(T('Falha ao abrir o report.', 'Failed to open the report.')); }
}

// ============================================================================
// LOGIN FULL-SCREEN
// ============================================================================
function renderLoginStatic() {
  document.title = (basic.contest_name || 'Contest') + ' — MOJ';
  document.getElementById('loginContestName').textContent = basic.contest_name || 'Contest';
  document.getElementById('loginTimes').innerHTML =
    T(`Início: ${fmtDate(basic.start_time)}<br>Término: ${fmtDate(basic.end_time)}`,
      `Start: ${fmtDate(basic.start_time)}<br>End: ${fmtDate(basic.end_time)}`);
  document.getElementById('loginUserLbl').textContent = T('Usuário', 'Username');
  document.getElementById('loginPassLbl').textContent = T('Senha', 'Password');
  document.getElementById('loginBtn').textContent = T('Entrar', 'Log in');
  document.getElementById('loginCountdownLbl').textContent = T('Abertura em', 'Opens in');
}

function updateLoginCountdown() {
  clearTimeout(loginCountdownTimer);
  const now = Math.floor(Date.now() / 1000);
  const loginStart = basic.login_start_time != null ? basic.login_start_time : basic.start_time;
  const left = loginStart - now;
  const box = document.getElementById('loginCountdown');
  const form = document.getElementById('loginForm');
  if (left > 0) {
    box.classList.remove('hidden');
    form.classList.add('hidden');
    document.getElementById('loginCountdownTime').textContent = fmtLeft(left);
    loginCountdownTimer = setTimeout(updateLoginCountdown, 1000);
  } else {
    box.classList.add('hidden');
    form.classList.remove('hidden');
  }
}

// repolla basic para detectar mudança de login_start_time (admin pode adiar/antecipar)
function scheduleLoginPoll() {
  clearTimeout(loginPollTimer);
  loginPollTimer = setTimeout(async () => {
    try {
      const fresh = await apiGet('/contest/basic?contest=' + encodeURIComponent(CONTEST), {});
      basic = fresh; if (basic.locale) setLang(basic.locale, { persist: false });
      renderLoginStatic();
      updateLoginCountdown();
    } catch {}
    scheduleLoginPoll();
  }, 15000);
}

function bootLogin() {
  show('loginView');
  hide('mainView');
  renderLoginStatic();
  updateLoginCountdown();
  scheduleLoginPoll();
  const form = document.getElementById('loginForm');
  form.onsubmit = async (e) => {
    e.preventDefault();
    const btn = document.getElementById('loginBtn');
    const err = document.getElementById('loginError');
    err.classList.add('hidden'); err.textContent = '';
    btn.disabled = true;
    try {
      await login(CONTEST, form.username.value.trim(), form.password.value);
      // recarrega a página: agora logado, cai no fluxo principal
      location.reload();
    } catch (ex) {
      err.textContent = ex && ex.message ? ex.message : T('Erro de login, tente novamente', 'Login error, try again');
      // A PORTA do contest (roster/janela): a mensagem sozinha não resolve — quem não se
      // inscreveu precisa do link, e a inscrição mora no site principal (outro domínio).
      const code = ex && ex.code;
      if (code === 'not_registered' || code === 'registration_not_open') {
        const base = location.host.replace(/^[^.]+\./, '');   // <id>.moj.x → moj.x
        const a = document.createElement('a');
        a.href = location.protocol + '//' + base + '/contests/inscricao/?c=' + encodeURIComponent(CONTEST);
        a.textContent = T(' Inscreva-se aqui →', ' Register here →');
        a.style.marginLeft = '.4rem';
        err.append(a);
      }
      err.classList.remove('hidden');
      btn.disabled = false;
    }
  };
}

// ============================================================================
// PÁGINA PRINCIPAL DO CONTEST
// ============================================================================
function startContestCountdown() {
  const eln = document.getElementById('contestCountdown');
  const tick = () => {
    const now = Math.floor(Date.now() / 1000);
    const left = (basic.end_time || 0) - now;
    if (left > 0) {
      eln.textContent = T('Termina em: ', 'Ends in: ') + fmtLeft(left);
      setTimeout(tick, 1000);
    } else {
      eln.textContent = T('Competição encerrada', 'Contest ended');
    }
  };
  tick();
}

// mapeia uma url de navbutton (ex.: "/score", "/all_submissions") para a página real
function navHref(url) {
  const c = encodeURIComponent(CONTEST);
  const map = {
    '/': `/contest/?c=${c}`,
    '/score': `/contest/score/?c=${c}`,
    '/all_submissions': `/contest/allsubmissions/?c=${c}`,
    '/stats': `/contest/statistics/?c=${c}`,
    '/pending': `/contest/judge/?c=${c}`,
    '/logout': '#logout',
  };
  if (map[url]) return map[url];
  // urls sem página dedicada (clarification, jplag, reports, admin_tasks, log) -> mantém querystring
  return url + (url.includes('?') ? '&' : '?') + 'c=' + c;
}

let NAVBTNS = []; // últimos botões pintados — re-render quando o idioma muda (moj:lang)
function renderNav(buttons) {
  NAVBTNS = buttons;
  const nav = document.getElementById('contestNav');
  nav.innerHTML = '';
  const here = location.pathname.replace(/\/+$/, '');
  buttons.forEach(b => {
    const href = navHref(b.url);
    const label = navLabel(b.url, b.label);
    if (href === '#logout') {
      nav.append(el('a', {
        href: '#', onclick: async (e) => { e.preventDefault(); await doLogout(); },
      }, label));
      return;
    }
    const active = href.split('?')[0].replace(/\/+$/, '') === here;
    nav.append(el('a', { href, class: active ? 'active' : '' }, label));
  });
}
document.addEventListener('moj:lang', () => { if (NAVBTNS.length) renderNav(NAVBTNS); });

async function doLogout() {
  await logout(CONTEST);
  location.reload();
}

function renderUser() {
  const box = document.getElementById('userSection');
  box.innerHTML = '';
  if (!userinfo) return;
  // "Como funciona este papel" é o padrão das outras 5 páginas de papel (staff/cstaff/animeitor/
  // judge/chief, todas com o mesmo botão no topo). Aqui o papel é o COMPETIDOR — então o botão só
  // aparece p/ quem não tem papel nenhum; organização e juiz já têm o tutorial DELES na página
  // deles. O contest-guard deixa passar porque o caminho começa em /contest/.
  const plain = !(userinfo.is_admin || userinfo.is_judge || userinfo.is_staff
    || userinfo.is_cstaff || userinfo.is_animeitor);
  if (plain) {
    box.append(el('a', { class: 'btn ghost', href: '/contest/ajuda/competidor.html', target: '_blank',
      rel: 'noopener', style: 'float:right;margin:.2rem 0 0',
      title: T('As telas da prova explicadas: sanfona, envio, clarification e placar',
               'The contest screens explained: accordion, submitting, clarifications and scoreboard') },
      T('📖 Como funciona a prova', '📖 How the contest works')));
  }
  box.append(
    el('div', { style: 'font-size:1.2rem; font-weight:800; color:var(--blue-dark)' },
      userinfo.name || userinfo.login),
    el('div', { class: 'small muted' }, 'Login: ', el('b', {}, userinfo.login),
      userinfo.is_admin ? '  · admin' : (userinfo.is_judge ? '  · judge'
        : (userinfo.is_staff ? '  · staff' : (userinfo.is_cstaff ? '  · ' + T('chefe de sede', 'site chief')
          : (userinfo.is_animeitor ? '  · ' + T('placar/telão', 'scoreboard/screen') : ''))))),
    // sessão de TIME: quem está no teclado é o `actor`, mas quem compete é o time
    userinfo.is_team ? el('div', { class: 'small' },
      T('👥 Você entrou como ', '👥 You logged in as '), el('b', {}, userinfo.actor || ''),
      T(' e está competindo pelo time acima — as submissões contam para o time.',
        ' and you are competing for the team above — submissions count for the team.')) : '',
  );
}

function renderNews(items) {
  if (!Array.isArray(items) || !items.length) { hide('newsSection'); return; }
  show('newsSection');
  document.getElementById('newsTitle').textContent = T('Informações & Notícias', 'Info & News');
  const ul = document.getElementById('newsList'); ul.innerHTML = '';
  items.forEach(n => {
    const li = el('li', { style: 'margin:.4rem 0' },
      el('b', { style: 'color:var(--blue-dark)' }, n.title || ''),
      n.date ? el('span', { class: 'small muted' }, '  (' + fmtDate(n.date) + ')') : null,
      el('div', { class: 'small' }, n.text || n.summary || ''));
    if (n.file && n.file.name) {
      const kb = n.file.size ? ' (' + Math.max(1, Math.round(n.file.size / 1024)) + ' KB)' : '';
      li.append(el('div', { class: 'small' }, el('a', { href: '#', onclick: (e) => {
        e.preventDefault();
        downloadAuthed('/contest/news-file?contest=' + encodeURIComponent(CONTEST) + '&id=' + encodeURIComponent(n.id), n.file.name);
      } }, '📎 ' + n.file.name + kb)));
    }
    ul.append(li);
  });
}

// recurso da PRÓPRIA API (documentos da prova) exige Bearer — link cru daria 401. Busca como
// blob e abre numa aba (a aba é aberta ANTES do fetch, senão o navegador bloqueia o popup).
function openAuthed(url) {
  return async (ev) => {
    ev.preventDefault();
    const w = window.open('', '_blank');
    try {
      const resp = await fetch(url, { headers: { Authorization: 'Bearer ' + (getToken(CONTEST) || '') } });
      if (!resp.ok) throw new Error('HTTP ' + resp.status);
      const u = URL.createObjectURL(await resp.blob());
      if (w) w.location = u; else window.open(u, '_blank');
    } catch (e) { if (w) w.close(); alert(T('Falha ao abrir o arquivo.', 'Failed to open the file.')); }
  };
}

// nome de cada documento NO IDIOMA DA INTERFACE (o `label` do servidor vem no idioma do
// DOCUMENTO e traz o sufixo " (pt)" — aqui o idioma virou chip, o rótulo é do tipo)
const DOC_NAME = {
  'contest':    () => T('📘 Caderno de problemas', '📘 Problem set'),
  'info-sheet': () => T('📋 Informações do ambiente', '📋 Testing environment'),
  'times':      () => T('⏱️ Limites de tempo', '⏱️ Time limits'),
  'editorial':  () => T('📝 Editorial', '📝 Editorial'),
};

function renderResources(items) {
  if (!Array.isArray(items) || !items.length) { hide('resourcesSection'); return; }
  show('resourcesSection');
  const ul = document.getElementById('resourcesList'); ul.innerHTML = '';
  // renderResources pode rodar de novo (recarga): tira as linhas de documento da rodada anterior
  document.querySelectorAll('#resourcesSection .doc-lines').forEach((n) => n.remove());

  // DOCUMENTO DA PROVA (tem type+lang): uma linha por documento, um chip por idioma —
  // "Caderno: PT | EN | ES" em vez de um bullet por par. Recurso avulso segue bullet.
  const docs = new Map();
  const rest = [];
  items.forEach((r) => {
    if (r && r.type && r.lang && DOC_NAME[r.type]) {
      if (!docs.has(r.type)) docs.set(r.type, []);
      docs.get(r.type).push(r);
    } else rest.push(r);
  });

  if (docs.size) {
    const box = el('div', { class: 'doc-lines' });
    ['contest', 'info-sheet', 'times', 'editorial'].forEach((ty) => {
      const langs = docs.get(ty); if (!langs) return;
      const line = el('div', { class: 'doc-line' },
        el('span', { class: 'doc-name' }, DOC_NAME[ty]()));
      langs.sort((a, b) => ['pt', 'en', 'es'].indexOf(a.lang) - ['pt', 'en', 'es'].indexOf(b.lang))
        .forEach((r) => line.append(el('a', {
          class: 'tag', href: '#', title: r.label || '', onclick: openAuthed(r.url || '#'),
        }, (r.lang || '').toUpperCase())));
      box.append(line);
    });
    ul.parentNode.insertBefore(box, ul);
  }

  rest.forEach(r => {
    const url = r.url || '#', label = r.label || r.url || '';
    if (url.startsWith('/api/v1/')) {
      ul.append(el('li', { style: 'margin:.3rem 0' }, el('a', { href: '#', onclick: openAuthed(url) }, label)));
    } else {
      ul.append(el('li', { style: 'margin:.3rem 0' }, el('a', { href: url, target: '_blank' }, label)));
    }
  });
}

// ---- notificações ao usuário: novidades (notícias) + clarifications respondidas ----------
// Estado "visto" por usuário/contest em localStorage; aviso na tela + badge de não lidas.
const nseenKey = (f) => `moj_${f}_seen_${CONTEST}`;
const getSeen = (f) => parseInt(localStorage.getItem(nseenKey(f)) || '0', 10) || 0;
const setSeen = (f, v) => localStorage.setItem(nseenKey(f), String(v || 0));
let notifState = { news: { last: 0, unread: 0 }, clar: { last: 0, unread: 0 } };
let notifyTimer = null;

async function loadNotifications() {
  try {
    const u = await apiGet('/contest/updates?contest=' + encodeURIComponent(CONTEST)
      + '&news_since=' + getSeen('news') + '&clar_since=' + getSeen('clar'),
      { contest: CONTEST, auth: true });
    notifState = { news: u.news || { last: 0, unread: 0 }, clar: u.clar || { last: 0, unread: 0 } };
  } catch { /* silencioso: notificação é best-effort */ }
  renderNotifyBanner();
  renderClarBadge();
}

function markSeen(feat) {
  setSeen(feat, (notifState[feat] && notifState[feat].last) || 0);
  if (notifState[feat]) notifState[feat].unread = 0;
  renderNotifyBanner(); renderClarBadge();
}

function renderNotifyBanner() {
  const mv = document.getElementById('mainView');
  let bar = document.getElementById('notifyBanner');
  const nU = notifState.news.unread || 0, cU = notifState.clar.unread || 0;
  if (!nU && !cU) { if (bar) bar.remove(); return; }
  if (!bar) { bar = el('div', { id: 'notifyBanner', class: 'notify-banner' }); mv.prepend(bar); }
  bar.innerHTML = '';
  bar.className = 'notify-banner' + (cU > 0 ? ' urgent' : '');   // pisca enquanto houver clarification não lida
  const links = [];
  if (nU) links.push(el('a', { href: '#', onclick: (e) => { e.preventDefault(); markSeen('news'); const s = document.getElementById('newsSection'); if (s) { show('newsSection'); s.scrollIntoView({ behavior: 'smooth' }); } } },
    '📢 ' + nU + ' ' + T(nU > 1 ? 'novas notícias' : 'nova notícia', nU > 1 ? 'new posts' : 'new post')));
  if (cU) links.push(el('a', { href: '/contest/clarification/?c=' + encodeURIComponent(CONTEST), onclick: () => markSeen('clar') },
    '💬 ' + cU + ' ' + T(cU > 1 ? 'clarifications respondidas' : 'clarification respondida', cU > 1 ? 'answered clarifications' : 'answered clarification')));
  const sep = links.length > 1 ? [links[0], ' · ', links[1]] : links;
  bar.append(el('span', {}, T('Novidades: ', 'Updates: ')), ...sep,
    el('button', { class: 'btn ghost', type: 'button', style: 'margin-left:auto', title: T('Marcar tudo como visto', 'Mark all as seen'),
      onclick: () => { markSeen('news'); markSeen('clar'); } }, '✕'));
}

function renderClarBadge() {
  const cU = notifState.clar.unread || 0;
  document.querySelectorAll('#contestNav a').forEach((a) => {
    if (!(a.getAttribute('href') || '').includes('/contest/clarification')) return;
    let b = a.querySelector('.nav-badge');
    if (cU > 0) { if (!b) { b = el('span', { class: 'nav-badge' }); a.append(' ', b); } b.textContent = String(cU); }
    else if (b) b.remove();
  });
}

// problema accordion (porta de contest/contest/problems.js para shared/ui)
function problemAccepted(p) {
  return submissions.some(s => s.problem === p.problem_id && /^accepted/i.test(s.verdict || ''));
}

// CSS p/ o caso raro de enunciado-FRAGMENTO: num documento blob: nem <link href="/shared/ui.css">
// resolve (base URL opaca) — o CSS tem de ir INLINE. Busca uma vez e cacheia.
let _uiCssText = null;
async function uiCssText() {
  if (_uiCssText === null) {
    try { _uiCssText = await (await fetch('/shared/ui.css')).text(); } catch { _uiCssText = ''; }
  }
  return _uiCssText;
}

// ENUNCIADO SOB DEMANDA. A lista (/contest/problems) só diz QUE existe; o corpo vem daqui,
// quando a pessoa abre a sanfona ou clica em HTML/PDF — antes vinham todos em base64 dentro da
// lista, e num contest de PDF isso é 3,8 MB por time no segundo da abertura. Guarda a PROMESSA
// (não o texto): dois cliques rápidos no mesmo problema fazem uma requisição só.
const _stmt = new Map();
function statementUrl(p, fmt) {
  return '/contest/statement?contest=' + encodeURIComponent(CONTEST)
    + '&problem=' + encodeURIComponent(p.short_name) + '&format=' + fmt;
}
function statementHtml(p) {
  const k = p.short_name + ':html';
  if (!_stmt.has(k)) {
    _stmt.set(k, apiGetText(statementUrl(p, 'html'), { contest: CONTEST, auth: true })
      .catch((e) => { _stmt.delete(k); throw e; }));   // erro não fica grudado no cache
  }
  return _stmt.get(k);
}
// abre a aba ANTES de ir à rede: `window.open` depois de um await é bloqueado como pop-up
function openTabThen(fill) {
  const w = window.open('', '_blank');
  if (w) {
    try {
      w.document.write('<!DOCTYPE html><meta charset="utf-8"><body style="font:16px system-ui;padding:2rem">'
        + T('carregando o enunciado…', 'loading the statement…') + '</body>');
      w.document.close();
    } catch { /* alguns navegadores não deixam escrever em about:blank */ }
  }
  return fill(w).catch(() => {
    if (w) { try { w.document.body.textContent = T('não deu para abrir o enunciado.', 'could not open the statement.'); } catch { /* */ } }
  });
}
async function openStatementNewTab(p) {
  const html = await statementHtml(p);
  // MESMA cara da sanfona/Treino Livre: miolo do body em .statement-content com o ui.css
  // INLINE (num documento blob: nem <link href="/shared/ui.css"> resolve — base URL opaca;
  // e o <style> próprio do renderer tem OUTRAS cores, divergia do enunciado embutido)
  let body = html;
  try {
    const doc = new DOMParser().parseFromString(html, 'text/html');
    if (doc.body && doc.body.innerHTML.trim()) body = doc.body.innerHTML;
  } catch {}
  const css = await uiCssText();
  const full = `<!DOCTYPE html><html lang="${getLang() === 'en' ? 'en' : 'pt-br'}"><head>
    <meta charset="utf-8"><title>${(p.short_name || '') + ' — ' + (p.full_name || '')}</title>
    <style>${css}</style>
    <style>body{padding:1.4rem;max-width:900px;margin:auto}</style></head>
    <body><div class="statement-content">${body}</div></body></html>`;
  return full;
}
function openHtmlTab(p) {
  return openTabThen(async (w) => {
    const full = await openStatementNewTab(p);
    const url = URL.createObjectURL(new Blob([full], { type: 'text/html' }));
    if (w) w.location.replace(url); else window.open(url, '_blank');
    setTimeout(() => URL.revokeObjectURL(url), 60000);
  });
}
function openPdfTab(p) {
  return openTabThen(async (w) => {
    const blob = await apiGetBlob(statementUrl(p, 'pdf'), { contest: CONTEST, auth: true });
    const url = URL.createObjectURL(blob);
    if (w) w.location.replace(url); else window.open(url, '_blank');
    setTimeout(() => URL.revokeObjectURL(url), 60000);
  });
}

function renderProblems() {
  uiCssText(); // pré-carrega o CSS do "abrir em nova aba" (o clique não espera rede)
  const list = document.getElementById('problemList');
  list.innerHTML = '';
  const visible = problems.filter(p => p.show !== false);
  if (!visible.length) { list.innerHTML = `<span class="muted">${T('Nenhum problema disponível.', 'No problems available.')}</span>`; return; }

  visible.forEach(p => {
    const accepted = problemAccepted(p);
    const color = accepted ? balloonColor(p.short_name) : '';
    const item = el('div', { class: 'prob-item' + (accepted ? ' accepted' : ''), id: 'prob-' + p.problem_id });
    tintProbItem(item, accepted, color);

    const toggle = el('span', { class: 'prob-toggle' }, '▶');
    const balloonSlot = el('span', { class: 'prob-balloon', html: accepted && color ? balloonSVG(color) : '' });
    const left = el('span', { class: 'prob-left' },
      toggle,
      balloonSlot,
      el('span', { class: 'prob-sn' }, p.short_name || ''),
      ' ',
      el('span', { class: 'prob-full' }, p.full_name || ''),
      // crédito do autor: a API só manda depois que a prova acaba (durante a prova o nome
      // do autor é pista) — ver SHOW_AUTHOR em handlers/contest/problems.sh
      p.author ? el('span', { class: 'small muted', style: 'margin-left:.5rem' },
        T('· autor: ', '· author: ') + p.author) : null,
      accepted ? el('span', { class: 'pill ok prob-ok' }, T('✔ resolvido', '✔ solved')) : null);

    // links de enunciado (HTML/PDF em nova aba)
    const linksWrap = el('span', { class: 'row' });
    if (p.url) linksWrap.append(el('a', { href: p.url, target: '_blank' }, T('Enunciado', 'Statement')));
    if (p.has_statement_html) linksWrap.append(el('a', { href: '#', onclick: (e) => { e.preventDefault(); openHtmlTab(p); } }, 'HTML'));
    if (p.has_statement_pdf) linksWrap.append(el('a', { href: '#', onclick: (e) => { e.preventDefault(); openPdfTab(p); } }, 'PDF'));

    // form de submit ao lado (editor abre no detalhe; aqui só upload rápido + botão)
    const submitWrap = renderSubmitInline(p);

    const right = el('span', { class: 'prob-right' }, linksWrap, submitWrap.row);

    const row = el('div', { class: 'prob-row' },
      left, right);
    // toggle só ao clicar na parte esquerda (não atrapalha o form)
    left.addEventListener('click', () => toggleDetail(p, item, toggle, submitWrap));

    const detail = el('div', { class: 'prob-detail hidden', id: 'prob-detail-' + p.problem_id });
    item.append(row, detail);
    list.append(item);
  });
}

// Atualiza só a aparência (cor do balão) dos problemas aceitos SEM reconstruir a
// lista — preserva editor aberto e código digitado durante o polling.
function retintProblems() {
  problems.filter(p => p.show !== false).forEach(p => {
    const item = document.getElementById('prob-' + p.problem_id);
    if (!item) return;
    const accepted = problemAccepted(p);
    const color = accepted ? balloonColor(p.short_name) : '';
    tintProbItem(item, accepted, color);
    const slot = item.querySelector('.prob-balloon');
    if (slot) slot.innerHTML = accepted && color ? balloonSVG(color) : '';
    // o selo acompanha: quem resolve DURANTE a prova (o retint roda no polling) tem de ver
    // o "✔ resolvido" aparecer sem recarregar a página
    let pill = item.querySelector('.prob-ok');
    if (accepted && !pill) {
      pill = el('span', { class: 'pill ok prob-ok' }, T('✔ resolvido', '✔ solved'));
      const left = item.querySelector('.prob-left'); if (left) left.append(pill);
    } else if (!accepted && pill) pill.remove();
  });
}

function toggleDetail(p, item, toggle, submitWrap) {
  const detail = item.querySelector('.prob-detail');
  const opened = !detail.classList.contains('hidden');
  if (opened) { detail.classList.add('hidden'); toggle.textContent = '▶'; return; }
  toggle.textContent = '▼';
  if (!detail.dataset.rendered) {
    // time limits — chips (nome da linguagem expandido, igual ao treino)
    const tl = p.time_limits || {};
    // com whitelist (do problema ou do contest): UM chip POR linguagem permitida — o TL
    // medido dela, senão o `default` — e SEM o chip "padrão" (a lista é fechada, não há
    // "demais linguagens"). resolveLangs degrada p/ TODAS com tokens exóticos: nesse caso
    // trata como sem restrição (chips medidos + "padrão" cobrindo as não calibradas).
    const rl = resolveLangs(p.languages || []);
    const restricted = Array.isArray(p.languages) && p.languages.length > 0 && rl !== LANGUAGES;
    let chips;   // [{label, time}]
    if (restricted) {
      chips = rl.map((l) => ({ label: l.label, time: tl[l.id] != null ? tl[l.id] : tl.default }))
        .filter((c) => c.time != null);
    } else {
      chips = Object.keys(tl)
        .sort((a, b) => (a === 'default' ? -1 : b === 'default' ? 1 : a.localeCompare(b)))
        .map((k) => ({ label: k === 'default' ? T('padrão', 'default') : (langById(k).label || k), time: tl[k] }));
    }
    if (chips.length) {
      const tlBlock = el('div', { class: 'tl-block' },
        el('span', { class: 'tl-label' }, '⏱ ' + T('Tempo limite', 'Time limit')));
      chips.forEach((c) => tlBlock.append(el('span', { class: 'tl-chip' },
        el('b', {}, c.label), el('span', { class: 'tl-time' }, fmtTime(c.time)))));
      detail.append(tlBlock);
    }
    // enunciado | editor lado a lado — editor embutido só se o admin do contest o habilitou
    const editorOn = !(userinfo && userinfo.show_editor === false);
    // coluna do enunciado (decodifica o b64 só agora, na 1ª abertura)
    let stmtCol = null;
    if (p.has_statement_html) {
      // a coluna nasce agora (o layout não pode pular quando o texto chegar) e o corpo é
      // preenchido quando a rede responde — é a 1ª vez que ESTE time pede ESTE enunciado
      const stmtDiv = el('div', { class: 'statement-content' },
        el('span', { class: 'muted' }, T('carregando o enunciado…', 'loading the statement…')));
      stmtCol = el('div', { class: 'prob-statement-col' }, stmtDiv);
      statementHtml(p).then((html) => {
        stmtDiv.innerHTML = (() => {
          try { const d = new DOMParser().parseFromString(html, 'text/html'); return d.body ? d.body.innerHTML : html; }
          catch { return html; }
        })();
      }).catch(() => {
        stmtDiv.textContent = T('não deu para carregar o enunciado — recarregue a página.',
                               'could not load the statement — reload the page.');
      });
    }
    if (editorOn) {
      const edCol = el('div', { class: 'prob-editor-col' }, submitWrap.editorBlock);
      const cols = el('div', { class: 'prob-cols' }, ...(stmtCol ? [stmtCol] : []), edCol);
      // seletor de 3 estados: lado a lado (padrão) | só enunciado | só editor
      const vm = el('div', { class: 'prob-viewmode' });
      const MODES = [['both', T('Lado a lado', 'Side by side')],
        ['only-statement', T('Só enunciado', 'Statement only')],
        ['only-editor', T('Só editor', 'Editor only')]];
      const setMode = (m) => {
        cols.classList.toggle('only-statement', m === 'only-statement');
        cols.classList.toggle('only-editor', m === 'only-editor');
        [...vm.children].forEach((b) => b.classList.toggle('active', b.dataset.m === m));
        try { localStorage.setItem('moj-prob-viewmode', m); } catch { /* storage indisponível */ }
        submitWrap.refreshEd && submitWrap.refreshEd();
      };
      MODES.forEach(([m, lbl]) => {
        if (m !== 'only-editor' && !stmtCol) return;   // sem enunciado: só faz sentido "só editor"
        const b = el('button', { class: 'btn ghost', type: 'button' }, lbl);
        b.dataset.m = m; b.addEventListener('click', () => setMode(m)); vm.append(b);
      });
      detail.append(vm, cols);
      submitWrap.mountEditor();
      let saved = 'both'; try { saved = localStorage.getItem('moj-prob-viewmode') || 'both'; } catch { /* */ }
      setMode(stmtCol ? saved : 'only-editor');
    } else if (stmtCol) {
      detail.append(stmtCol);   // editor desligado: enunciado em largura cheia
    }
    detail.dataset.rendered = '1';
  }
  detail.classList.remove('hidden');
}

// form de submit por problema: upload rápido (na linha) + editor completo no detalhe
// (CodeMirror com tela cheia e "nova janela", espelhando o modo treino).
function renderSubmitInline(p) {
  // envia ao juiz; problem_id já é a forma canônica 'coleção#problema' (vinda de /contest/problems)
  async function doSubmit(payload, stepsEl, btnEl) {
    btnEl.disabled = true; stepsEl.textContent = T('Enviando…', 'Sending…');
    try {
      await apiPost('/submit?contest=' + encodeURIComponent(CONTEST),
        { problem_id: p.problem_id, ...payload }, { contest: CONTEST, auth: true });
      stepsEl.textContent = T('✓ Enviado!', '✓ Sent!');
      setTimeout(loadSubmissions, 1200);
    } catch (ex) {
      stepsEl.innerHTML = `<span class="error-box">${T('Erro: ', 'Error: ') + (ex && ex.message ? ex.message : T('falha ao enviar', 'failed to send'))}</span>`;
    } finally { btnEl.disabled = false; }
  }

  // ---- linha sempre visível: upload rápido de arquivo ----
  const fileInput = el('input', { type: 'file', style: 'max-width:170px' });
  const steps = el('span', { class: 'submit-steps' });
  const btn = el('button', { class: 'btn', type: 'button' }, T('Enviar', 'Submit'));
  const row = el('span', { class: 'prob-submit' }, fileInput, btn, steps);
  btn.addEventListener('click', async () => {
    if (fileInput.files && fileInput.files[0]) {
      const f = fileInput.files[0];
      steps.textContent = T('Preparando…', 'Preparing…');
      doSubmit({ filename: f.name, code_b64: await fileToBase64(f), source: 'file' }, steps, btn);
    } else {
      steps.innerHTML = `<span class="muted small">${T('Escolha um arquivo ou escreva no editor (abra os detalhes ▼).', 'Choose a file or write in the editor (open details ▼).')}</span>`;
    }
  });

  // ---- editor completo (montado sob demanda no detalhe) ----
  injectEditorCss();
  // linguagens deste problema: p.languages já vem RESOLVIDO pelo servidor (override do problema
  // -> whitelist do contest -> default do pacote -> []). Declarado -> exatamente esses ids (via
  // langById, que sintetiza exótica/custom não-registrada). Vazio -> sem restrição: as normais
  // (DEFAULT_SUBMIT_LANGUAGES, sem as exóticas opt-in) quando não há whitelist do contest, senão a
  // whitelist (LANGS). LANGS === LANGUAGES <=> resolveLangs não achou whitelist (= todas).
  const probLangs = (p.languages && p.languages.length)
    ? p.languages.map(langById)
    : (LANGS === LANGUAGES ? DEFAULT_SUBMIT_LANGUAGES : LANGS);
  const sel = el('select', {}, ...probLangs.map((l) => el('option', { value: l.id }, l.label)));
  const editorMount = el('div');
  const editorBox = el('div', { class: 'editor-box', style: 'height:520px' }, editorMount);   // ~26 linhas
  const edSteps = el('span', { class: 'submit-steps' });
  const edBtn = el('button', { class: 'btn', type: 'button' }, T('Enviar solução', 'Submit solution'));
  let editor = null;
  const refreshEd = () => { if (editor && typeof editor.refresh === 'function') editor.refresh(); };
  const focusEd = () => { if (editor && typeof editor.focus === 'function') editor.focus(); };

  // ⛶ Tela cheia (dialog no top layer) e ⧉ Nova janela (?editoronly=1&prob=<id>).
  const expandBtn = el('button', { class: 'btn ghost', type: 'button', title: T('Editor em tela cheia', 'Fullscreen editor') }, '⛶ ' + T('Tela cheia', 'Fullscreen'));
  const popBtn = el('button', { class: 'btn ghost', type: 'button', title: T('Abrir só o editor numa nova janela', 'Open only the editor in a new window'),
    onclick: () => { const u = new URL(location.href); u.searchParams.set('editoronly', '1'); u.searchParams.set('prob', p.problem_id); window.open(u.toString(), '_blank', 'width=900,height=820'); } }, '⧉ ' + T('Nova janela', 'New window'));
  const closeFullBtn = el('button', { class: 'btn ghost', type: 'button', title: T('Sair da tela cheia (Esc)', 'Exit fullscreen (Esc)'), onclick: () => exitFull() }, '✕ ' + T('Fechar', 'Close'));
  closeFullBtn.style.display = 'none';

  // ajuda no PONTO DE USO, igual ao treino. O contest-guard abre uma exceção p/ /treino/ajuda/
  // (página estática de instrução), senão o competidor ficaria sem saber como se lê a entrada.
  const helpLink = el('a', { class: 'small', href: '/treino/ajuda/', target: '_blank', rel: 'noopener',
    title: T('Entrada e saída, extensões e o código inicial de cada linguagem',
             'Input and output, extensions and the starter code for each language') },
    T('📖 Como enviar', '📖 How to submit'));
  const wrap = el('div', { class: 'editor-wrap' },
    el('div', { class: 'editor-bar' },
      el('label', { class: 'small' }, T('Linguagem: ', 'Language: ')), sel, helpLink,
      el('span', { style: 'flex:1' }), expandBtn, popBtn, closeFullBtn),
    editorBox,
    el('div', { class: 'row', style: 'margin-top:.3rem' }, edBtn, edSteps));
  const editorBlock = wrap;

  // dialog dedicado p/ tela cheia: o wrap MOVE-se p/ dentro (top layer) e volta ao fechar.
  const dlg = document.createElement('dialog'); dlg.className = 'editor-dialog'; document.body.append(dlg);
  let homeParent = null, homeNext = null;
  function enterFull() {
    homeParent = wrap.parentNode; homeNext = wrap.nextSibling;
    dlg.append(wrap); wrap.classList.add('editor-full');
    expandBtn.style.display = 'none'; closeFullBtn.style.display = '';
    if (!dlg.open) dlg.showModal(); refreshEd(); focusEd();
  }
  function exitFull() {
    wrap.classList.remove('editor-full');
    if (homeParent) homeParent.insertBefore(wrap, homeNext);
    expandBtn.style.display = ''; closeFullBtn.style.display = 'none';
    if (dlg.open) dlg.close(); refreshEd();
  }
  expandBtn.onclick = enterFull;
  dlg.addEventListener('cancel', (e) => { e.preventDefault(); exitFull(); });   // Esc fecha limpo
  if (EDITOR_ONLY) { expandBtn.style.display = 'none'; popBtn.style.display = 'none'; }

  async function mountEditor() {
    if (editor) return;
    editor = await createEditor(editorMount, { doc: '', cm: langById(sel.value).cm });
    sel.addEventListener('change', async () => {
      const cur = editor.getValue(); editorMount.innerHTML = '';
      editor = await createEditor(editorMount, { doc: cur, cm: langById(sel.value).cm });
    });
    setTimeout(refreshEd, 50);
  }
  edBtn.addEventListener('click', async () => {
    if (fileInput.files && fileInput.files[0]) {
      const f = fileInput.files[0];
      // whitelist do problema vale TAMBÉM p/ upload de arquivo (a API rejeita; aqui é a
      // mensagem amigável antes do POST — o dropdown do editor já filtra)
      if (p.languages && p.languages.length) {
        const fext = f.name.includes('.') ? f.name.split('.').pop() : '';
        if (!p.languages.map(extCanon).includes(extCanon(fext))) {
          edSteps.innerHTML = `<span class="error-box">${T(`Este problema só aceita: ${p.languages.join(', ')} — o arquivo .${fext || '?'} não pode ser enviado.`, `This problem only accepts: ${p.languages.join(', ')} — the .${fext || '?'} file cannot be submitted.`)}</span>`;
          return;
        }
      }
      edSteps.textContent = T('Preparando…', 'Preparing…');
      doSubmit({ filename: f.name, code_b64: await fileToBase64(f), source: 'file' }, edSteps, edBtn);
      return;
    }
    const txt = editor ? editor.getValue() : '';
    if (!txt.trim()) { edSteps.innerHTML = `<span class="error-box">${T('Escreva código ou escolha um arquivo.', 'Write code or choose a file.')}</span>`; return; }
    edSteps.textContent = T('Preparando…', 'Preparing…');
    doSubmit({ filename: 'solution.' + sel.value, code_b64: textToBase64(txt), source: 'web' }, edSteps, edBtn);
  });

  return { row, editorBlock, mountEditor, refreshEd };
}

// minuto de prova de um instante: é o que a coluna "Tempo" significa (e o que o placar mostra
// nas células, "1/12" = acertou na 1ª tentativa no minuto 12). Antes do início dá negativo —
// e isso é informação, não erro: é submissão de juiz testando a prova.
function minutoDeProva(epoch) {
  const ini = (basic && basic.start_time) || 0;
  if (!ini || !epoch) return '—';
  return String(Math.floor((epoch - ini) / 60));
}

// ---- submissões (tabela + filtro + ordenação + polling) --------------------
function parseHistLine(line) {
  const a = line.split(':');
  if (a.length < 7) return null;
  // tempo:username:problemid:lang:verdict:epoch:subid  (verdict pode conter ':')
  // ⚠ o campo 0 ("tempo") NÃO é minuto de prova: a reforma do store passou a gravar o EPOCH
  // nele (o submit.sh escreve `$AGORA` nos campos 0 e 4, e a migração fez `tempo := sub_epoch`
  // porque o campo 0 do legado era lixo). Mostrá-lo cru punha um número de 10 dígitos numa
  // coluna chamada "Tempo", ao lado de "Data" com o MESMO instante formatado. O minuto de
  // prova — que é o que "Tempo" quer dizer no ICPC e o que o placar usa nas células — é
  // calculado na hora de renderizar, a partir do início do contest.
  return {
    sinceStart: parseInt(a[0], 10) || 0,
    user: a[1],
    problem: a[2],
    lang: a[3],
    subid: a[a.length - 1],
    epoch: parseInt(a[a.length - 2], 10) || 0,
    verdict: a.slice(4, a.length - 2).join(':'),
  };
}

function renderSubFilter() {
  const bar = document.getElementById('subFilter');
  bar.innerHTML = '';
  const mk = (label, val) => {
    const t = el('span', { class: 'tag' + (subFilter === val ? ' active' : ''), onclick: () => { subFilter = val; renderSubFilter(); renderSubmissions(); } }, label);
    bar.append(t);
  };
  mk(T('Todos', 'All'), 'ALL');
  problems.filter(p => p.show !== false).forEach(p => mk(p.short_name || p.problem_id, p.problem_id));
}

function shortNameOf(pid) {
  const p = problems.find(x => x.problem_id === pid);
  return p ? (p.short_name || pid) : pid;
}
function fullNameOf(pid) {
  const p = problems.find(x => x.problem_id === pid);
  return p ? (p.full_name || '') : '';
}

function renderSubmissions() {
  const box = document.getElementById('submissionsTable');
  let rows = submissions.filter(s => subFilter === 'ALL' ? true : s.problem === subFilter);
  rows = rows.slice().sort((a, b) => {
    if (sortField === 'epoch') return sortAsc ? a.epoch - b.epoch : b.epoch - a.epoch;
    if (sortField === 'problem') {
      const sa = shortNameOf(a.problem), sb = shortNameOf(b.problem);
      return sortAsc ? sa.localeCompare(sb) : sb.localeCompare(sa);
    }
    if (sortField === 'verdict') return sortAsc ? (a.verdict || '').localeCompare(b.verdict || '') : (b.verdict || '').localeCompare(a.verdict || '');
    return 0;
  });

  box.innerHTML = '';
  if (!rows.length) { box.innerHTML = `<span class="muted small">${T('Nenhuma submissão ainda.', 'No submissions yet.')}</span>`; return; }

  const arrow = (f) => sortField === f ? (sortAsc ? ' ▲' : ' ▼') : '';
  const th = (label, f) => el('th', { onclick: () => { sortAsc = (sortField === f) ? !sortAsc : false; sortField = f; renderSubmissions(); } }, label + arrow(f));
  const canLog = !!(userinfo && (userinfo.show_log || userinfo.is_admin || userinfo.is_judge));

  const head = el('thead', {}, el('tr', {},
    th(T('Tempo', 'Time'), 'epoch'),
    th(T('Problema', 'Problem'), 'problem'),
    el('th', {}, T('Arquivo', 'File')),
    th(T('Resultado', 'Result'), 'verdict'),
    el('th', {}, T('Data', 'Date')),
    canLog ? el('th', {}, 'Log') : null));

  const tb = el('tbody');
  rows.forEach(s => {
    const pending = isPending(s.verdict);
    const fileLink = el('a', {
      href: '#', onclick: (e) => { e.preventDefault(); downloadAuthed(`/submission/source?contest=${encodeURIComponent(CONTEST)}&id=${encodeURIComponent(s.subid)}&time=${encodeURIComponent(s.epoch)}`, s.subid + '.' + (s.lang || 'txt').toLowerCase()); },
    }, T('cód', 'src'));
    // detalhe sob o veredicto canônico (pontos/grupos/heurístico): o servidor redige por
    // modo — em contest binário (icpc) o summary vem null e a linha simplesmente não existe.
    const rtxt = pending ? '' : resumoText(subSumm[s.subid]);
    const vcell = el('td', {}, el('span', { class: 'verdict ' + vClass(s.verdict) },
      pending ? el('span', {}, el('span', { class: 'spin' }), ' ' + s.verdict) : s.verdict),
      rtxt ? el('div', { class: 'small muted', style: 'margin-top:.15rem' }, rtxt) : '');
    const logCell = canLog ? el('td', {},
      el('a', { href: '#', onclick: (e) => { e.preventDefault(); openReportAuthed(`/submission/log?contest=${encodeURIComponent(CONTEST)}&id=${encodeURIComponent(s.subid)}&time=${encodeURIComponent(s.epoch)}`); } }, 'log')) : null;
    tb.append(el('tr', {},
      el('td', {}, minutoDeProva(s.epoch)),
      el('td', {}, el('b', {}, shortNameOf(s.problem)), ' ', el('span', { class: 'small muted' }, fullNameOf(s.problem))),
      el('td', {}, fileLink),
      vcell,
      el('td', {}, fmtDate(s.epoch)),
      logCell));
  });

  box.append(el('table', { class: 'moj' }, head, tb));
}

async function loadSubmissions() {
  let txt;
  try { txt = await apiGetText('/contest/history?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: true }); }
  catch { return; }
  submissions = txt.split('\n').map(s => s.trim()).filter(Boolean).map(parseHistLine).filter(Boolean);
  // resumo (pontos/grupos/heurístico) das já julgadas — em lotes de 100 (URL curta), best-effort;
  // o servidor redige por modo (icpc devolve tudo null e nada é mostrado).
  const done = submissions.filter(s => !isPending(s.verdict)).map(s => s.subid).filter(id => !(id in subSumm));
  for (let i = 0; i < done.length; i += 100) {
    try { Object.assign(subSumm, await apiGet('/submission/summary?contest=' + encodeURIComponent(CONTEST) + '&ids=' + done.slice(i, i + 100).join(','), { contest: CONTEST, auth: true }) || {}); }
    catch { /* best-effort */ }
  }
  renderSubFilter();
  renderSubmissions();
  retintProblems(); // re-tinge problemas que viraram accepted (sem reconstruir a lista)

  clearTimeout(pollTimer);
  if (submissions.some(s => isPending(s.verdict))) {
    pollTimer = setTimeout(loadSubmissions, 5000 + Math.random() * 5000); // 5–10s
  }
}

// Faixa da RODADA: um contest pode rodar aquecimento (ensaio) antes da prova oficial, no mesmo
// endereço e com o mesmo login. O time não pode confundir os dois — então, quando a rodada no ar
// é de aquecimento, a faixa fica fixa no topo dizendo que aquilo não vale.
function renderRoundBanner() {
  const r = basic && basic.round;
  document.getElementById('roundBanner')?.remove();
  if (!r || !r.warmup) return;
  const main = document.querySelector('main.container') || document.body;
  main.prepend(el('div', { id: 'roundBanner', class: 'alert', style: 'font-weight:600' },
    '🔁 ' + T('AQUECIMENTO', 'WARM-UP') + ' — ' + (r.name || r.slug) + '. '
    + T('Esta rodada serve para testar o ambiente e a sua conta: o placar dela NÃO é o da prova.',
        'This round is for testing the environment and your account: its scoreboard is NOT the contest one.')));
}

function renderRoundsLink(archived) {
  if (!archived || !archived.length) return;
  const ul = document.getElementById('resourcesList');
  if (!ul) return;
  show('resourcesSection');
  ul.append(el('li', { style: 'margin:.3rem 0' },
    el('a', { href: '/contest/rounds/?c=' + encodeURIComponent(CONTEST), target: '_blank' },
      '🔁 ' + T('Rodadas encerradas (placar e submissões do aquecimento)',
                'Finished rounds (warm-up scoreboard and submissions)'))));
}

async function bootMain() {
  hide('loginView'); show('mainView');
  document.title = (basic.contest_name || 'Contest') + ' — MOJ';
  document.getElementById('contestTitle').textContent = basic.contest_name || 'Contest';
  startContestCountdown();
  document.getElementById('logoutBtn').onclick = doLogout;

  // userinfo + nav (em paralelo)
  const [ui, nav, bc] = await Promise.all([
    apiGet('/contest/userinfo?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: true }).catch(() => null),
    apiGet('/contest/navbuttons?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: true }).catch(() => null),
    apiGet('/contest/balloons?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: true }).catch(() => null),
  ]);
  userinfo = ui;
  renderUser();
  const buttons = nav ? (Array.isArray(nav) ? nav : (nav.buttons || [])) : [];
  if (buttons.length) renderNav(buttons);
  balloons = bc ? (bc.balloons || bc) : {};

  renderRoundBanner();
  // rodadas: faixa do aquecimento + link p/ o arquivo das encerradas (só quando houver)
  apiGet('/contest/rounds?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: true })
    .then(j => renderRoundsLink((j.rounds || []).filter(r => r.state === 'archived'))).catch(() => {});

  // news/resources (opcionais — escondem se vazio/erro)
  apiGet('/contest/news?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: true })
    .then(j => renderNews(Array.isArray(j) ? j : (j.items || j.news || []))).catch(() => hide('newsSection'));
  apiGet('/contest/resources?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: true })
    .then(j => renderResources(Array.isArray(j) ? j : (j.items || []))).catch(() => hide('resourcesSection'));

  // GATE pré-início: usuário NÃO privilegiado (não .admin/.judge) não vê problemas antes do
  // início — tela de contagem regressiva (a API também recusa: /contest/problems devolve
  // {locked:"not_started"} e /submit -> 403). .admin/.judge entram direto (sempre).
  const privileged = !!(userinfo && (userinfo.is_admin || userinfo.is_judge));
  const nowS = Math.floor(Date.now() / 1000);
  if (!privileged && basic.start_time && nowS < basic.start_time) {
    renderPreStart();
    return;
  }
  await loadContestBody();
}

// carrega problemas + submissões + notificações (depois do início, ou já privilegiado)
async function loadContestBody() {
  clearTimeout(preStartTimer); clearInterval(preStartPoll);
  hide('prestartSection'); show('problemsSection'); show('mySubsSection');
  // O SEGUNDO ZERO é o pior instante do servidor: todos os times saem juntos da contagem
  // regressiva. Medido em carga (20/08/2026, 5 máquinas contra a produção): com até ~500
  // conexões simultâneas os 2000 times carregam em ~5 s sem um erro; acima disso a fila do
  // socket do fcgiwrap satura e o nginx devolve 502. Antes, um 502 aqui deixava a página
  // PARADA num aviso de erro até o time recarregar à mão — o pior desfecho possível no minuto
  // em que a prova começa. Agora tenta de novo, com espera crescente e ALEATÓRIA: o jitter é o
  // que impede que todos os que falharam retentem no mesmo instante (o mesmo idioma do poll
  // do placar, que já sorteia o intervalo).
  const lista = document.getElementById('problemList');
  let j = null;
  for (let tent = 0; tent < 5; tent++) {
    try { j = await apiGet('/contest/problems?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: true }); break; }
    catch {
      if (tent === 4) break;
      if (lista) lista.innerHTML = `<span class="muted">${T('Carregando a prova…', 'Loading the contest…')}</span>`;
      await new Promise(r => setTimeout(r, 350 * Math.pow(2, tent) + Math.random() * 700));
    }
  }
  if (j) {
    problems = Array.isArray(j) ? j : (j.problems || []);
  } else {
    if (lista) lista.innerHTML = `<span class="error-box">${T('Falha ao carregar problemas. Recarregue a página.', 'Failed to load problems. Reload the page.')}</span>`;
    problems = [];
  }
  renderProblems();
  renderSubFilter();
  await loadSubmissions();

  // notificações (notícias + clarifications respondidas): poll leve a cada 30s
  loadNotifications();
  clearInterval(notifyTimer);
  notifyTimer = setInterval(loadNotifications, 30000);
}

// tela de contagem regressiva até o início (não-privilegiados). Ao zerar, carrega o corpo.
// Repolla /contest/basic (admin pode adiar/antecipar o início).
function renderPreStart() {
  hide('problemsSection'); hide('mySubsSection'); show('prestartSection');
  const title = document.getElementById('prestartTitle');
  const cd = document.getElementById('prestartCountdown');
  const hint = document.getElementById('prestartHint');
  if (title) title.textContent = T('A competição ainda não começou', 'The contest has not started yet');
  if (hint) hint.textContent = T('Os problemas aparecem automaticamente quando a competição iniciar.',
    'Problems appear automatically when the contest starts.');
  const tick = async () => {
    clearTimeout(preStartTimer);
    const left = (basic.start_time || 0) - Math.floor(Date.now() / 1000);
    if (left > 0) {
      cd.textContent = fmtLeft(left);
      preStartTimer = setTimeout(tick, 1000);
    } else {
      // ESPALHA a largada: sem isto os 2000 times disparam no MESMO milissegundo e a rajada de
      // conexões satura a fila do socket do fcgiwrap (medido: acima de ~640 simultâneas começa
      // 502). Até 1,2 s de espera sorteada derruba o pico sem tirar tempo de prova de ninguém
      // de forma perceptível — e é bem melhor que a alternativa de hoje, que é uma fração dos
      // times receber erro e ter de recarregar.
      await new Promise(r => setTimeout(r, Math.random() * 1200));
      // começou: revalida com a API (que agora libera) e carrega o corpo do contest
      try { basic = await apiGet('/contest/basic?contest=' + encodeURIComponent(CONTEST), {}); } catch {}
      if ((basic.start_time || 0) - Math.floor(Date.now() / 1000) > 0) { preStartTimer = setTimeout(tick, 1000); return; }
      await loadContestBody();
    }
  };
  tick();
  // repoll de basic a cada 15s p/ refletir mudança do horário de início feita pelo admin
  clearInterval(preStartPoll);
  preStartPoll = setInterval(async () => {
    try { const fresh = await apiGet('/contest/basic?contest=' + encodeURIComponent(CONTEST), {}); basic = fresh; } catch {}
  }, 15000);
}

// ============================================================================
// BOOT
// ============================================================================
async function boot() {
  if (!CONTEST) {
    document.body.innerHTML = '<div class="container"><div class="error-box">' + T('Contest não informado (use ?c=&lt;id&gt;).', 'No contest specified (use ?c=&lt;id&gt;).') + '</div></div>';
    return;
  }
  try {
    basic = await apiGet('/contest/basic?contest=' + encodeURIComponent(CONTEST), {});
  } catch (e) {
    document.body.innerHTML = '<div class="container"><div class="error-box">' + T('Contest não encontrado.', 'Contest not found.') + '</div></div>';
    return;
  }
  if (basic.locale) setLang(basic.locale, { persist: false });
  LANGS = resolveLangs(basic.languages);   // whitelist do contest (conf LANGUAGES=); vazio = todas

  const st = await status(CONTEST);
  // .staff/.cstaff não participam do contest (não submetem / não veem problemas): vão
  // direto à área da fila (o .cstaff a vê em modo somente leitura).
  if (st.logged_in && (st.is_staff || st.is_cstaff) && !st.is_admin) {
    location.replace('/contest/staff/?c=' + encodeURIComponent(CONTEST));
    return;
  }
  // .animeitor opera o telão: vai direto à página dele (fotos + streaming do placar)
  if (st.logged_in && st.is_animeitor && !st.is_admin) {
    location.replace('/contest/animeitor/?c=' + encodeURIComponent(CONTEST));
    return;
  }
  if (st.logged_in) { if (EDITOR_ONLY) await bootEditorOnly(); else await bootMain(); }
  else bootLogin();
}

// janela "só editor" (?editoronly=1&prob=<id>): carrega o problema e mostra apenas o editor
// preenchendo a janela. Reusa a sessão do contest (token compartilhado no localStorage).
async function bootEditorOnly() {
  injectEditorCss();
  document.body.classList.add('editor-only');
  show('mainView');
  document.title = 'Editor — ' + (basic.contest_name || 'Contest');
  let list = [];
  try {
    const j = await apiGet('/contest/problems?contest=' + encodeURIComponent(CONTEST), { contest: CONTEST, auth: true });
    list = Array.isArray(j) ? j : (j.problems || []);
  } catch { /* mostra erro abaixo */ }
  const mv = document.getElementById('mainView');
  const host = el('div', { class: 'editor-only-host' });
  const p = list.find((x) => x.problem_id === ONLY_PROB) || list[0];
  if (!p) {
    host.append(el('div', { class: 'error-box' }, T('Problema não encontrado.', 'Problem not found.')));
    mv.append(host); return;
  }
  host.append(el('div', { class: 'row', style: 'margin:.1rem 0 .3rem' },
    el('b', {}, (p.short_name ? p.short_name + ' — ' : '') + (p.full_name || p.problem_id))));
  const sw = renderSubmitInline(p);
  host.append(sw.editorBlock);
  mv.append(host);
  sw.mountEditor();
}
boot();
