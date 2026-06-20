// shared/contest-config/util.js — helpers de data para os editores.
export const nowEpoch = () => Math.floor(Date.now() / 1000);
export function toLocalDT(epoch) {
  if (!epoch) return '';
  const d = new Date(Number(epoch) * 1000), p = (n) => String(n).padStart(2, '0');
  return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) + 'T' + p(d.getHours()) + ':' + p(d.getMinutes());
}
export const dtToEpoch = (s) => { const t = Date.parse(s); return isNaN(t) ? 0 : Math.floor(t / 1000); };
