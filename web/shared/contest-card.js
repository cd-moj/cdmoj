// shared/contest-card.js — cartão de contest reutilizável (home + arquivo de encerrados).
// Concentra a lógica do link (subdomínio ID.moj.<base> no site principal, senão ?c=)
// p/ que home e arquivo nunca divirjam.
import { el, fmtDate } from '/shared/ui.js';

export function relTime(epoch) {
  const d = Number(epoch) - Date.now() / 1000, a = Math.abs(d);
  const days = Math.round(a / 86400);
  const s = a >= 86400 ? days + (days > 1 ? ' dias' : ' dia')
          : a >= 3600 ? Math.round(a / 3600) + 'h'
          : Math.max(1, Math.round(a / 60)) + 'min';
  return (d >= 0 ? 'em ' : 'há ') + s;
}

export function contestCard(c, status) {
  const id = c.id || '';
  // no site principal, abre o contest pelo subdomínio (ID.moj.<base>); senão cai no ?c=
  const sub = /^moj\./i.test(location.hostname) ? (location.protocol + '//' + id + '.' + location.host) : '';
  const url = sub ? (sub + '/') : ('/contest/?c=' + encodeURIComponent(id));
  const score = sub ? (sub + '/contest/score/') : ('/contest/score/?c=' + encodeURIComponent(id));
  const start = c.start_time || c.start, end = c.end_time || c.end;
  const label = { open: '🟢 Aberto', upcoming: '🔵 Em breve', closed: '⚪ Encerrado' }[status];
  const when = status === 'open' ? 'termina ' + relTime(end)
             : status === 'upcoming' ? 'começa ' + relTime(start)
             : 'encerrado ' + relTime(end);
  const bs = 'padding:.32rem .7rem; font-size:.82rem';
  const actions = [];
  if (status === 'open') actions.push(el('a', { class: 'btn', href: url, style: bs }, 'Entrar →'));
  else actions.push(el('a', { class: 'btn ghost', href: url, style: bs }, status === 'upcoming' ? 'Detalhes' : 'Ver'));
  actions.push(el('a', { class: 'btn ghost', href: score, style: bs }, 'Placar'));

  const meta = el('div', { class: 'cc-meta' },
    el('span', { class: 'cc-when' }, when),
    el('span', {}, 'início ' + fmtDate(start)),
    el('span', {}, 'fim ' + fmtDate(end)));
  if (c.problems_count != null) meta.append(el('span', {}, c.problems_count + ' problemas'));

  return el('div', { class: 'contest-card ' + status },
    el('span', { class: 'cc-badge ' + status }, label),
    el('div', { class: 'cc-main' },
      el('a', { class: 'cc-title', href: url }, c.title || c.name || id), meta),
    el('div', { class: 'cc-actions' }, ...actions));
}
