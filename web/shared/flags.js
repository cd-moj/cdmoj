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
  return '';
}

// flagEl(code, opts) -> <img> (ou null). Some sozinho se o arquivo não existir (offline-safe).
export function flagEl(code, { height = 16, title = '' } = {}) {
  const src = flagPath(code);
  if (!src) return null;
  const img = document.createElement('img');
  img.src = src; img.alt = title || code; img.title = title || code;
  img.className = 'flag-mini';
  img.style.cssText = `height:${height}px;vertical-align:middle;border-radius:2px;box-shadow:0 0 1px rgba(0,0,0,.45)`;
  img.addEventListener('error', () => img.remove());
  return img;
}

// flagImgHTML(code, h) -> string <img …> (para renderers baseados em template). '' se desconhecido.
export function flagImgHTML(code, height = 16, title = '') {
  const src = flagPath(code);
  if (!src) return '';
  const t = (title || code).replace(/"/g, '&quot;');
  return `<img class="flag-mini" src="${src}" alt="${t}" title="${t}" style="height:${height}px;vertical-align:middle;border-radius:2px;box-shadow:0 0 1px rgba(0,0,0,.45)" onerror="this.remove()">`;
}

// flagManifest() -> {countries:[{code,name}], br_states:[{code,name}]} (cache em memória).
let _manifest = null;
export async function flagManifest() {
  if (_manifest) return _manifest;
  try { _manifest = await (await fetch(BASE + '/index.json')).json(); }
  catch { _manifest = { countries: [], br_states: [] }; }
  return _manifest;
}
