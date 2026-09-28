// shared/contest-card.js — cartão de contest reutilizável (home + arquivo de encerrados).
// Concentra a lógica do link (subdomínio ID.moj.<base> no site principal, senão ?c=)
// p/ que home e arquivo nunca divirjam.
import { el, fmtDate } from '/shared/ui.js';
import { T } from '/shared/i18n.js';

export function relTime(epoch) {
  const d = Number(epoch) - Date.now() / 1000, a = Math.abs(d);
  const days = Math.round(a / 86400);
  const s = a >= 86400 ? days + (days > 1 ? T(' dias', ' days', ' días') : T(' dia', ' day', ' día'))
          : a >= 3600 ? Math.round(a / 3600) + 'h'
          : Math.max(1, Math.round(a / 60)) + 'min';
  return d >= 0 ? T('em ', 'in ', 'en ') + s : T('há ', '', 'hace ') + s + T('', ' ago', '');
}

export function contestCard(c, status) {
  const id = c.id || '';
  // no site principal, abre o contest pelo subdomínio (ID.moj.<base>); senão cai no ?c=
  const sub = /^moj\./i.test(location.hostname) ? (location.protocol + '//' + id + '.' + location.host) : '';
  const url = sub ? (sub + '/') : ('/contest/?c=' + encodeURIComponent(id));
  const score = sub ? (sub + '/contest/score/') : ('/contest/score/?c=' + encodeURIComponent(id));
  const start = c.start_time || c.start, end = c.end_time || c.end;
  const label = { open: T('🟢 Aberto', '🟢 Open', '🟢 Abierto'), upcoming: T('🔵 Em breve', '🔵 Upcoming', '🔵 Próximamente'), closed: T('⚪ Encerrado', '⚪ Ended', '⚪ Finalizado') }[status];
  const when = status === 'open' ? T('termina ', 'ends ', 'termina ') + relTime(end)
             : status === 'upcoming' ? T('começa ', 'starts ', 'empieza ') + relTime(start)
             : T('encerrado ', 'ended ', 'finalizado ') + relTime(end);
  const bs = 'padding:.32rem .7rem; font-size:.82rem';
  const actions = [];
  if (status === 'open') actions.push(el('a', { class: 'btn', href: url, style: bs }, T('Entrar →', 'Enter →', 'Entrar →')));
  else actions.push(el('a', { class: 'btn ghost', href: url, style: bs }, status === 'upcoming' ? T('Detalhes', 'Details', 'Detalles') : T('Ver', 'View', 'Ver')));
  actions.push(el('a', { class: 'btn ghost', href: score, style: bs }, T('Placar', 'Scoreboard', 'Marcador')));
  // relatório estático PUBLICADO pelo admin (histórico do evento): /relatorio/<id>/
  if (c.report_url) actions.push(el('a', { class: 'btn ghost', href: c.report_url, style: bs }, T('📑 Relatório', '📑 Report', '📑 Informe')));
  // participação virtual: refazer a prova encerrada contra o placar oficial (treino/virtual)
  if (c.virtual_url) actions.push(el('a', { class: 'btn ghost', href: c.virtual_url, style: bs, title: T('Refazer esta prova contra o placar oficial, no seu tempo', 'Redo this contest against the official scoreboard, in your own time', 'Rehacer esta competencia contra el marcador oficial, a tu propio ritmo') }, '🕹️ Virtual'));

  // INSCRIÇÃO: o contest só deixa entrar quem se inscreveu ANTES (roster + janela). O estado
  // sai do relógio do cliente a partir das datas — a regra em bash é a do lib/registration.sh.
  const r = c.registration, now = Date.now() / 1000;
  let regState = '';
  if (r && status !== 'closed') {
    regState = now < (r.opens_at || 0) ? 'soon'
             : now <= (r.closes_at || 0) || !r.closes_at ? 'open'
             : now <= (r.late_until || 0) ? 'late' : 'closed';
    if (regState === 'open' || regState === 'late') {
      actions.unshift(el('a', { class: 'btn', href: r.url || ('/contests/inscricao/?c=' + encodeURIComponent(id)), style: bs },
        regState === 'late' ? T('Inscrição atrasada →', 'Late registration →', 'Inscripción tardía →') : T('📝 Inscreva-se', '📝 Register', '📝 Inscríbete')));
    }
  }

  const meta = el('div', { class: 'cc-meta' },
    el('span', { class: 'cc-when' }, when),
    el('span', {}, T('início ', 'start ', 'inicio ') + fmtDate(start)),
    el('span', {}, T('fim ', 'end ', 'fin ') + fmtDate(end)));
  if (regState === 'open') meta.append(el('span', {}, T('inscrições fecham ', 'registration closes ', 'inscripciones cierran ') + relTime(r.closes_at)));
  else if (regState === 'soon') meta.append(el('span', {}, T('inscrições abrem ', 'registration opens ', 'inscripciones abren ') + relTime(r.opens_at)));
  else if (regState === 'late') meta.append(el('span', {}, T('inscrição atrasada até ', 'late registration until ', 'inscripción tardía hasta ') + relTime(r.late_until)));
  else if (regState === 'closed') meta.append(el('span', {}, T('inscrições encerradas', 'registration closed', 'inscripciones cerradas')));
  // 0 = servidor ocultou de propósito (contest por vir não revela quantidade de problemas)
  if (c.problems_count) meta.append(el('span', {}, c.problems_count + T(' problemas', ' problems', ' problemas')));

  return el('div', { class: 'contest-card ' + status },
    el('span', { class: 'cc-badge ' + status }, label),
    el('div', { class: 'cc-main' },
      el('a', { class: 'cc-title', href: url }, c.title || c.name || id), meta),
    el('div', { class: 'cc-actions' }, ...actions));
}
