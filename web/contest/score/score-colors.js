// contest/score/score-colors.js — utilidades de cor de balão (mapa hex SEM '#').
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
export function balloonSVG(color) {
  return `<svg class="balloon-svg" viewBox="0 0 42 47" aria-hidden="true">
    <ellipse cx="21" cy="21" rx="18" ry="18" fill="${color}" stroke="#b2b2b2" stroke-width="2"/>
    <ellipse cx="16" cy="14" rx="5" ry="5.1" fill="#fff" fill-opacity=".48"/>
    <polygon points="18,36 24,36 21,46" fill="${color}" stroke="#b2b2b2" stroke-width="1.4" stroke-linejoin="round"/>
    <ellipse cx="14" cy="15" rx="1.4" ry="2.8" fill="#fff" fill-opacity=".30"/>
    <ellipse cx="12" cy="22" rx="1.1" ry="1.5" fill="#fff" fill-opacity=".22"/>
  </svg>`;
}
