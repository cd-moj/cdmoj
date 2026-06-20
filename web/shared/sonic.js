// shared/sonic.js — "modo secreto do Sonic" (offline). GIFs locais em /shared/assets/sonic/.
// Ativado por enableSonic no balloons.json. Índice determinístico por chave (letra do problema).
const COUNT = 10;
const BASE = '/shared/assets/sonic';

export const sonicEnabled = (balloons) => !!(balloons && (balloons.enableSonic === true || balloons.enableSonic === 'true'));

export function sonicSrc(key) {
  let h = 0; const s = String(key == null ? '' : key);
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  return `${BASE}/sonic${h % COUNT}.gif`;
}
export function sonicImgHTML(key, height = 22) {
  return `<img src="${sonicSrc(key)}" alt="Sonic" style="height:${height}px;vertical-align:middle" onerror="this.remove()">`;
}
