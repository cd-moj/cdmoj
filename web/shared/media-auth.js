// shared/media-auth.js — mídia de TIME (<img>/<audio>/<a>) em contest 🕵️ SUPER SECRETO.
//
// O PORQUÊ: com `SECRET=1` as quatro rotas de mídia do contest — `team-photo`, `team-music`,
// `team-logo` e `placeholder` — passam pelo `require_not_secret_or_auth` (server/api/v1/
// lib/common.sh), que exige sessão DAQUELE contest. Só que TAG DE MÍDIA NÃO MANDA
// `Authorization`: o MOJ não tem cookie (o token mora no localStorage) e o nginx nem repassa
// `HTTP_COOKIE` (lista branca de fastcgi_param). Resultado, até 2026-08-24: em contest secreto
// TODA foto/miniatura/música/padrão voltava 401 `secret_login_required` — para qualquer papel,
// admin inclusive. A galeria do telão montava (a LISTAGEM vai por apiGet com Bearer e responde
// 200) e vinha cheia de imagem quebrada; trocar a foto de um time "não fazia nada", porque o
// POST gravava e o <img> repintado dava 401 de novo.
//
// A SAÍDA é a única que uma tag tem: buscar com Bearer e virar `blob:` — o mesmo desenho do
// `pdfBlobUrl` do `contest/staff/staff.js` ("URL temporária, sem token na URL").
//
// ⚠ CAMINHO RÁPIDO: contest que NÃO é secreto devolve a URL crua de sempre, de forma SÍNCRONA.
// O placar é o corpo mais servido do dia e não pode ganhar um `fetch` sequer: mesma URL, mesmo
// cache HTTP, mesmo `loading="lazy"` nativo. O default é esse caminho, então tela que esquecer
// de chamar `primeMedia` se comporta exatamente como hoje — nunca pior.
//
// ⚠ NÃO importe este módulo de `dom.js`/`stats-view.js`/`charts.js`: eles são inlinados pelo
// `server/score/report-gen.sh`, que tem a invariante "zero `fetch(`" (relatório offline).
import { apiGetBlob, getToken, API_BASE } from './api.js';
import { el } from './dom.js';

let AUTHED = false;    // o contest é secreto?
let CONTEST = '';

// Só as NOSSAS quatro rotas entram no caminho autenticado. URL de fora passa reta — o
// `rule.logo` do teams-meta (score.js) é `data:`/`https:` arbitrário escolhido pelo admin.
const MEDIA_RE = /^\/api\/v1\/contest\/(team-photo|team-music|team-logo|placeholder)\?/;

// primeMedia(contest, basic) — liga o caminho autenticado a partir do `secret` que o
// /contest/basic JÁ devolve. Chamado no `initContestShell` (cobre as telas de contest) e no
// `score/score.js`, que é a única página de mídia que não passa pelo shell.
export function primeMedia(contest, basic) {
  CONTEST = contest || '';
  AUTHED = !!(basic && basic.secret);
}
export function mediaAuthed() { return AUTHED; }
const needsAuth = (url) => AUTHED && MEDIA_RE.test(url || '');

// --- fila: no máximo 6 buscas em voo ---------------------------------------
// Cada GET dessas rotas é um FORK DE BASH sob fcgiwrap. O <img> cru estava implicitamente
// limitado pelo teto de 6 conexões por host do browser; `fetch` sobre HTTP/2 abriria 100+
// streams de uma vez e derrubaria a API num contest grande.
const MAX_INFLIGHT = 6;
const QUEUE = [];
let running = 0;
function pump() {
  while (running < MAX_INFLIGHT && QUEUE.length) {
    running++;
    QUEUE.shift()().then(() => { running--; pump(); }, () => { running--; pump(); });
  }
}
const schedule = (fn) => new Promise((res, rej) => { QUEUE.push(() => fn().then(res, rej)); pump(); });

// --- memo por URL CRUA, com LRU --------------------------------------------
// O placar reconstrói o DOM inteiro a cada poll e a galeria repagina a cada filtro: sem memo
// seria uma requisição por imagem por render. A chave é a URL crua porque ela já carrega o
// cache-buster `&v=<mtime>` — asset trocado gera chave nova sozinho.
const CACHE = new Map();      // url crua -> blob:   (Map preserva ordem de inserção = LRU)
const INFLIGHT = new Map();   // url crua -> Promise<blob:>
const CACHE_MAX = 300;        // 300 × ~40 KB ≈ 12 MB, constante: o telão fica 12 h aberto

function trim() {
  while (CACHE.size > CACHE_MAX) {
    const k = CACHE.keys().next().value;
    URL.revokeObjectURL(CACHE.get(k));
    CACHE.delete(k);
  }
}
function fetchBlob(url) {
  // visitante sem sessão não dispara N 401 inúteis
  if (!getToken(CONTEST)) return Promise.reject(new Error('sem sessão do contest'));
  return schedule(() => apiGetBlob(url.slice(API_BASE.length), { contest: CONTEST, auth: true }))
    .then((b) => URL.createObjectURL(b));
}

// mediaBlobUrl(url, {cache}) -> Promise<string>: a URL crua (contest público) ou um `blob:`.
// `cache:false` para o que NÃO pode ficar guardado — música (até 15 MB cada) e foto em
// tamanho real; quem chama com false revoga por conta própria.
export function mediaBlobUrl(url, { cache = true } = {}) {
  if (!needsAuth(url)) return Promise.resolve(url);
  if (!cache) return fetchBlob(url);
  const hit = CACHE.get(url);
  if (hit) { CACHE.delete(url); CACHE.set(url, hit); return Promise.resolve(hit); }  // LRU touch
  let p = INFLIGHT.get(url);
  if (!p) {
    p = fetchBlob(url).then(
      (b) => { INFLIGHT.delete(url); CACHE.set(url, b); trim(); return b; },
      (e) => { INFLIGHT.delete(url); throw e; });
    INFLIGHT.set(url, p);
  }
  return p;
}

// releaseMedia(url) — revoga UMA entrada na hora. É o que a galeria usa ao TROCAR o asset de
// um time: sem isso, quem troca 300 fotos numa sessão empurra o LRU inteiro para fora.
export function releaseMedia(url) {
  const b = CACHE.get(url);
  if (b) { URL.revokeObjectURL(b); CACHE.delete(url); }
  INFLIGHT.delete(url);
}

// --- lazy: `blob:` não conhece o atributo `loading` -------------------------
// Um observer compartilhado reimplementa a semântica do `loading="lazy"`. No PLACAR isso não é
// enfeite: sem ele, um contest de milhares de times dispararia uma busca por linha no primeiro
// render (= milhares de forks de bash), em vez de só as linhas visíveis.
let OBS = null;
function observer() {
  if (!OBS) {
    OBS = new IntersectionObserver((ents) => {
      ents.forEach((en) => {
        if (!en.isIntersecting) return;
        OBS.unobserve(en.target);
        const go = en.target._mojMediaGo;
        if (go) { delete en.target._mojMediaGo; go(); }
      });
    }, { rootMargin: '200px' });
  }
  return OBS;
}

// setMediaSrc(node, url, {lazy, onerror}) -> node
// Contest público: `node.src = url`, síncrono, com o `loading` nativo intacto.
export function setMediaSrc(node, url, { lazy = false, onerror = null } = {}) {
  if (!needsAuth(url)) { node.src = url; return node; }
  node.removeAttribute('loading');
  const go = () => mediaBlobUrl(url).then((u) => { node.src = u; }, () => { if (onerror) onerror(); });
  if (lazy && typeof IntersectionObserver === 'function') { node._mojMediaGo = go; observer().observe(node); }
  else go();
  return node;
}

// mediaLink(url, attrs, ...kids) -> <a>
// Contest público: um <a href> de verdade (clique do meio, "abrir em nova aba", tudo funciona).
// Secreto: abre a aba SINCRONAMENTE no clique — preserva o gesto do usuário, senão o browser
// bloqueia como pop-up — e só aponta para o blob quando a busca termina (molde do
// `openPdfWindow` do staff.js). O blob é descartado em 120 s, o mesmo prazo de lá.
export function mediaLink(url, attrs = {}, ...kids) {
  if (!needsAuth(url)) return el('a', { ...attrs, href: url, target: '_blank' }, ...kids);
  return el('a', {
    ...attrs,
    href: '#',
    onclick: (ev) => {
      ev.preventDefault();
      const w = window.open('', '_blank');
      mediaBlobUrl(url, { cache: false }).then(
        (u) => { if (w) { w.location = u; setTimeout(() => URL.revokeObjectURL(u), 120000); } },
        () => { if (w) w.close(); });
    },
  }, ...kids);
}

// setAudioSrc(audio, url) -> Promise
// UMA faixa viva por vez: mp3 vai até 15 MB e guardar 100 delas seria 1,5 GB — por isso a
// música fica FORA do LRU. Mas a faixa CORRENTE fica: repetir a mesma (o time resolve de novo,
// o operador testa antes da prova) não pode rebaixar 15 MB outra vez.
let LIVE_URL = '';      // a URL crua da faixa viva
let LIVE_AUDIO = '';    // o blob: dela (vazio em contest público — lá o src é a própria URL)
export function setAudioSrc(audio, url) {
  if (url === LIVE_URL && LIVE_AUDIO) { audio.src = LIVE_AUDIO; return Promise.resolve(LIVE_AUDIO); }
  return mediaBlobUrl(url, { cache: false }).then((u) => {
    const prev = LIVE_AUDIO;
    audio.src = u;
    LIVE_URL = url;
    LIVE_AUDIO = (u === url) ? '' : u;          // caminho rápido: não há blob a revogar
    if (prev && prev !== u) URL.revokeObjectURL(prev);
    return u;
  });
}
