// contest/score/score-colors.js — utilidades de cor de balão (mapa hex SEM '#').
// FONTE ÚNICA: placar ao vivo, cerimônia e a página do contest importam daqui. O gêmeo
// inevitável é o awk de server/score/report-gen.sh (bash) — mudou aqui, mude lá.
import { el } from '/shared/ui.js';
export function balloonColorHex(balloons, shortName) {
  const c = balloons && balloons[shortName];
  if (!c) return '';
  const hex = typeof c === 'string' ? c : c.hex;
  if (!hex) return '';
  return hex.startsWith('#') ? hex : '#' + hex;
}
export function balloonIsDark(hex) {
  hex = String(hex).replace('#', '');
  if (hex.length === 3) hex = hex.split('').map(x => x + x).join('');
  const r = parseInt(hex.substr(0, 2), 16), g = parseInt(hex.substr(2, 2), 16), b = parseInt(hex.substr(4, 2), 16);
  if ([r, g, b].some(Number.isNaN)) return false;
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255 < 0.5;
}
// Luminância percebida (0..1) — a MESMA conta do balloonIsDark, extraída p/ reuso.
function lum(hex) {
  hex = String(hex).replace('#', '');
  if (hex.length === 3) hex = hex.split('').map(x => x + x).join('');
  const r = parseInt(hex.substr(0, 2), 16), g = parseInt(hex.substr(2, 2), 16), b = parseInt(hex.substr(4, 2), 16);
  if ([r, g, b].some(Number.isNaN)) return null;
  return { r, g, b, l: (0.299 * r + 0.587 * g + 0.114 * b) / 255 };
}
const hex2 = (n) => Math.max(0, Math.min(255, Math.round(n))).toString(16).padStart(2, '0').toUpperCase();

// Luminância RELATIVA da WCAG (≠ a percebida acima) — só ela dá a razão de contraste real.
function wcagLum(r, g, b) {
  const f = (c) => { c /= 255; return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
}
const ratioOnWhite = (r, g, b) => 1.05 / (wcagLum(r, g, b) + 0.05);

// balloonEdge(hex) -> contorno da cor: a PRÓPRIA cor escurecida ATÉ CRUZAR 3:1 contra o branco
// (o limite da WCAG 1.4.11 p/ objeto gráfico). É o que faz o balão branco aparecer
// (FFFFFF -> 8A8A8A). Escurecer por um fator FIXO não serve: o verde-limão 00FF00 tem
// luminância percebida alta mas relativa baixa e parava em 2,29:1 — a função GARANTE o
// contraste em vez de torcer para uma constante servir p/ as 15 cores. Cor já escura muda
// pouco ou nada (000000 -> 000000), então o contorno nunca vira enfeite em quem já contrasta.
// A casa inteira já contorna cor de balão (folha A4 -stroke '#333', bolinha do staff
// border:1px, o balloonSVG do cabeçalho); a célula do placar era a exceção.
export function balloonEdge(hex) {
  const c = lum(hex); if (!c) return '#8A8A8A';
  let k = 0.78;
  for (let i = 0; i < 12 && k > 0.2; i++) {
    if (ratioOnWhite(c.r * k, c.g * k, c.b * k) >= 3) break;
    k -= 0.06;
  }
  return '#' + hex2(c.r * k) + hex2(c.g * k) + hex2(c.b * k);
}

// balloonTint(hex) -> 12% da cor sobre branco: fundo suave p/ a LINHA da página do contest
// (linha inteira pintada com a cor crua deixava título/links ilegíveis nas 5 cores escuras).
export function balloonTint(hex) {
  const c = lum(hex); if (!c) return '#F2F2F2';
  const m = (v) => v * 0.12 + 255 * 0.88;
  return '#' + hex2(m(c.r)) + hex2(m(c.g)) + hex2(m(c.b));
}

// balloonDot(hex) -> o ponto da cor do balão para dentro da célula (modo 'icon'). A BORDA não é
// acabamento: sobre o verde de acerto o ponto branco dá 1,1:1, então é ela que carrega a
// informação — e por isso vem do balloonEdge (cor escura ganha borda quase invisível, que é o
// certo; cor clara ganha borda proporcional). Mesmo idioma da bolinha da fila do staff.
export function balloonDot(color) {
  return el('span', { class: 'bdot', style: `--bdot:${color};--bdot-edge:${balloonEdge(color)}` });
}

// paintSolvedCell(td, color, opts) — a ÚNICA definição de como uma célula RESOLVIDA se pinta.
//   'icon' (padrão): fundo neutro igual p/ todos + o ponto da cor. "Resolvido" deixa de depender
//           da cor — era o problema do balão branco (1,00:1 contra o fundo da tabela).
//   'fill' : o clássico, cor do balão no fundo, MAIS o contorno derivado (senão claro some).
// O anel do first-to-solve vence nos dois modos. `ring` é a espessura do contorno do 'fill'
// (2 na cerimônia: é projetor, 1px some).
export function paintSolvedCell(td, color, opts) {
  const { style = 'icon', fts = false, ring = 1 } = opts || {};
  td.style.fontWeight = '700';
  if (style === 'fill' && color) {
    td.style.background = color;
    td.style.color = balloonIsDark(color) ? '#fff' : '#222';
    if (!fts) td.style.boxShadow = `inset 0 0 0 ${ring}px ${balloonEdge(color)}`;
  } else {
    td.style.background = '#e2ffe9';
    td.style.color = '#222';
  }
  if (fts) td.style.boxShadow = 'inset 0 0 0 2px currentColor';
}

export function balloonSVG(color) {
  return `<svg class="balloon-svg" viewBox="0 0 42 47" aria-hidden="true">
    <ellipse cx="21" cy="21" rx="18" ry="18" fill="${color}" stroke="#b2b2b2" stroke-width="2"/>
    <ellipse cx="16" cy="14" rx="5" ry="5.1" fill="#fff" fill-opacity=".48"/>
    <polygon points="18,36 24,36 21,46" fill="${color}" stroke="#b2b2b2" stroke-width="1.4" stroke-linejoin="round"/>
    <ellipse cx="14" cy="15" rx="1.4" ry="2.8" fill="#fff" fill-opacity=".30"/>
    <ellipse cx="12" cy="22" rx="1.1" ry="1.5" fill="#fff" fill-opacity=".22"/>
  </svg>`;
}
