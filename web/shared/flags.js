// shared/flags.js — bandeiras locais (offline-safe). Resolve um "código" para um SVG
// servido pelo próprio MOJ: país ISO-2 (ex.: "BR", "US") ou estado do Brasil ("BR-SP").
// Cache de bandeiras em /shared/flags/{country,br}/*.svg (ver README lá).
const BASE = '/shared/flags';

// flagPath(code) -> caminho local do SVG, ou '' se o código não for reconhecível.
export function flagPath(code) {
  if (!code) return '';
  const c = String(code).trim().toLowerCase();
  const m = c.match(/^br[-_]([a-z]{2})$/);
  if (m) return BASE + '/br/' + m[1] + '.svg';
  if (/^[a-z]{2}$/.test(c)) return BASE + '/country/' + c + '.svg';
  // subdivisão fora do Brasil (gb-eng, es-ct, sh-ac…): o cache de países tem esses arquivos
  // com o código INTEIRO. Sem isto, um time com flag "sh-ac" ficava sem bandeira nenhuma.
  if (/^[a-z]{2}[-_][a-z]{2,3}$/.test(c)) return BASE + '/country/' + c.replace('_', '-') + '.svg';
  return '';
}

// flagName(code) -> nome legível ("Costa Rica", "Santa Catarina") ou o código em MAIÚSCULAS
// quando o manifesto ainda não carregou/não conhece. FONTE ÚNICA do nome (issue #21, 2026-09-15):
// antes score.js e statistics.js remontavam o mapa à mão e a revelação/cadastros nem passavam
// título (tooltip "br-sp"). ⚠ UF entra SÓ com prefixo `br-`: no index.json o estado é indexado
// sem prefixo e 16 UFs colidem com país ("sc" = Seychelles, "es" = Espanha, "pr" = Porto Rico).
// Um "SC" solto É Seychelles — o cadastro de time tem de dizer "BR-SC".
let _names = null;   // {"br": "Brazil", "br-sc": "Santa Catarina", …} (preenchido por flagManifest)
export function flagName(code) {
  const c = String(code || '').trim().toLowerCase().replace('_', '-');
  if (!c) return '';
  return (_names && _names[c]) || c.toUpperCase();
}
// flagNamesReady() -> Promise que resolve quando o manifesto está em memória (as telas que
// pintam muitas bandeiras esperam por ela antes do 1º render; as demais aceitam o código).
export async function flagNamesReady() { await flagManifest(); return _names || {}; }

// flagEl(code, opts) -> <img> (ou null). Some sozinho se o arquivo não existir (offline-safe).
// Sem `title`, o tooltip é o NOME (flagName), nunca o código cru.
export function flagEl(code, { height = 16, title = '' } = {}) {
  const src = flagPath(code);
  if (!src) return null;
  const img = document.createElement('img');
  const t = title || flagName(code);
  img.src = src; img.alt = t; img.title = t;
  img.className = 'flag-mini';
  img.style.cssText = `height:${height}px;vertical-align:middle;border-radius:2px;box-shadow:0 0 1px rgba(0,0,0,.45)`;
  img.addEventListener('error', () => img.remove());
  return img;
}

// flagImgHTML(code, h) -> string <img …> (para renderers baseados em template). '' se desconhecido.
export function flagImgHTML(code, height = 16, title = '') {
  const src = flagPath(code);
  if (!src) return '';
  const t = String(title || flagName(code)).replace(/"/g, '&quot;');
  return `<img class="flag-mini" src="${src}" alt="${t}" title="${t}" style="height:${height}px;vertical-align:middle;border-radius:2px;box-shadow:0 0 1px rgba(0,0,0,.45)" onerror="this.remove()">`;
}

// flagManifest() -> {countries:[{code,name}], br_states:[{code,name}]} (cache em memória).
let _manifest = null;
export async function flagManifest() {
  if (_manifest) return _manifest;
  try { _manifest = await (await fetch(BASE + '/index.json')).json(); }
  catch { _manifest = { countries: [], br_states: [] }; }
  // o mapa de nomes: país pelo código; UF SEMPRE com o prefixo br- (ver flagName)
  _names = {};
  (_manifest.countries || []).forEach((c) => { _names[String(c.code).toLowerCase()] = c.name; });
  (_manifest.br_states || []).forEach((s) => { _names['br-' + String(s.code).toLowerCase()] = s.name; });
  return _manifest;
}
