// shared/media-auth.js — helpers de MÍDIA DE TIME (<img>/<audio>/<a>).
//
// A MÍDIA DE TIME É PÚBLICA, inclusive em contest 🕵️ SUPER SECRETO (decisão de 2026-08-24): as
// quatro rotas — `team-photo`, `team-music`, `team-logo` e `placeholder` — saíram do
// `require_not_secret_or_auth`. A foto e a música existem para ir ao TELÃO, e o telão é um
// sistema EXTERNO (o Animeitor) que busca sem sessão; o gate atrapalhava muito e protegia pouco.
// O que o `SECRET` continua escondendo é o placar e o visual dele (`score`, `teams`,
// `teams-meta`, `balloons`, `regions`).
//
// HISTÓRIA, porque explica o nome do arquivo: entre 2026-08-24 e o mesmo dia, este módulo
// buscava as quatro rotas com Bearer e devolvia `blob:` — TAG DE MÍDIA NÃO MANDA
// `Authorization` (o MOJ não tem cookie; o token mora no localStorage), então em contest secreto
// TODA foto/miniatura/música voltava 401 para qualquer papel, admin inclusive, e a galeria do
// telão vinha cheia de imagem quebrada. Com as rotas abertas, esse caminho ficou inalcançável e
// saiu junto com a fila de 6-em-voo, o LRU de `blob:` e o observer que reimplementava o `lazy`.
//
// O que sobrou são três helpers que valem por si, e é por isso que o módulo continua existindo:
// `setMediaSrc` (o `lazy` nativo), `mediaLink` (um <a> de verdade) e `setAudioSrc` (UMA faixa
// viva por vez — regra da galeria, que nada tem a ver com autenticação).
//
// ⚠ NÃO importe este módulo de `dom.js`/`stats-view.js`/`charts.js`: eles são inlinados pelo
// `server/score/report-gen.sh`, que tem a invariante "zero `fetch(`" (relatório offline).
import { el } from './dom.js';

// mediaBlobUrl(url) -> Promise<string>: hoje é sempre a própria URL. Mantida para os chamadores
// que já a usam e porque descreve a intenção ("me dê algo que eu possa pôr num src").
export function mediaBlobUrl(url) { return Promise.resolve(url); }

// releaseMedia(url) — no-op: não há mais `blob:` para revogar. A galeria a chama ao TROCAR o
// asset de um time, e continua fazendo sentido chamar (o cache-buster `&v=<mtime>` da URL é que
// faz o browser rebaixar a imagem nova).
export function releaseMedia() {}

// setMediaSrc(node, url, {lazy}) -> node — `src` direto, com o `loading="lazy"` NATIVO.
// O `lazy` no placar não é enfeite: cada GET dessas rotas é um fork de bash sob fcgiwrap, e um
// contest de milhares de times pediria uma imagem por linha no primeiro render.
export function setMediaSrc(node, url, { lazy = false } = {}) {
  if (lazy) node.loading = 'lazy';
  node.src = url;
  return node;
}

// mediaLink(url, attrs, ...kids) -> <a> de verdade (clique do meio, "abrir em nova aba", tudo
// funciona — era isto que o caminho autenticado não conseguia entregar).
export function mediaLink(url, attrs = {}, ...kids) {
  return el('a', { ...attrs, href: url, target: '_blank' }, ...kids);
}

// setAudioSrc(audio, url) -> Promise — UMA faixa por vez na página do telão.
export function setAudioSrc(audio, url) {
  audio.src = url;
  return Promise.resolve(url);
}
