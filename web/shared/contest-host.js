// shared/contest-host.js — o endereço do contest. Cada contest tem o seu subdomínio (<ID>.moj.naquadah.com.br em
// produção, <ID>.moj.charge.naquadah.com.br em teste) e, desde 16/10/2026, TIME só entra por ele: a API recusa sessão de
// time fora dele (403 host_required, server/api/v1/lib/team-host.sh) e a página de contest aberta no site principal
// pula p/ o subdomínio (subdomainRedirect, chamado no contest-guard.js). Funções PURAS (o `loc` é opcional, default
// `location`): o smoke-team-host.gjs.sh as extrai e testa sem navegador.

// o id que pode ser rótulo de DNS sob o certificado curinga — a MESMA regra do th_subdomainable (lib/team-host.sh)
export const SUBDOMAINABLE = /^[a-z0-9][a-z0-9_-]{0,62}$/;

// contestHostOf(hostname) → o id do contest do subdomínio, ou null no site principal / IP / localhost
export function contestHostOf(hostname) {
  const m = String(hostname || '').match(/^([a-z0-9][a-z0-9._-]*)\.(?:new)?moj\./i);
  return m ? m[1].toLowerCase() : null;
}
export function contestHost() { return contestHostOf(location.hostname); }

// isMojBase(hostname) — é o site principal do MOJ (moj.* / newmoj.*)? IP e localhost não são.
export function isMojBase(hostname) { return /^(?:new)?moj\./i.test(String(hostname || '')); }

// o host (com porta) do site principal: no subdomínio, sem o rótulo do contest; fora dele, o próprio host
export function baseHost(loc = location) {
  const id = contestHostOf(loc.hostname);
  return id ? loc.host.slice(id.length + 1) : loc.host;
}
export function baseOrigin(loc = location) { return loc.protocol + '//' + baseHost(loc); }

// contestOrigin(id) → 'https://<id>.<site principal>' ou '' quando não há subdomínio p/ ele (treino, id que não vira
// rótulo, ou página fora do moj.* — IP, localhost: aí o link fica no `?c=` de sempre)
export function contestOrigin(id, loc = location) {
  const c = String(id || '');
  if (!c || c === 'treino' || !SUBDOMAINABLE.test(c)) return '';
  const bh = baseHost(loc);
  if (!isMojBase(bh.replace(/:\d+$/, ''))) return '';
  return loc.protocol + '//' + c + '.' + bh;
}

// subdomainRedirect(loc) → a MESMA URL no subdomínio do contest, ou '' (não redirecionar). Só no site principal moj.*,
// só nas páginas de contest (/contest…, menos os tutoriais estáticos de /contest/ajuda/) e só com `c` que tem
// subdomínio. Caminho, query (o `c` inclusive: toda página lê `__MOJ_CONTEST || c`) e hash vão inteiros — link antigo
// (Moodle, favorito, `next=`) continua valendo.
export function subdomainRedirect(loc = location) {
  if (contestHostOf(loc.hostname) || !isMojBase(loc.hostname)) return '';
  const p = loc.pathname || '';
  if (!(p === '/contest' || p.startsWith('/contest/')) || p.startsWith('/contest/ajuda')) return '';
  const o = contestOrigin(new URLSearchParams(loc.search || '').get('c'), loc);
  return o ? o + p + (loc.search || '') + (loc.hash || '') : '';
}
