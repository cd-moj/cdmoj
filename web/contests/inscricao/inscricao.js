// contests/inscricao/inscricao.js — INSCRIÇÃO num contest com a conta do Treino Livre:
// individual ou em TIME de até 3 contas existentes (convite + aceite).
//
// Esta página vive no SITE PRINCIPAL de propósito: o token é por origem, e o subdomínio do
// contest (`<id>.moj…`) tem outro localStorage — quem se inscreve é a conta do treino.
// Na prova, cada membro entra no contest com a PRÓPRIA senha e a sessão vira a do time.
import { apiGet, apiPost } from '/shared/api.js';
import { status } from '/shared/auth.js';
import { el, renderAuthArea, fmtDate } from '/shared/ui.js';
import { T } from '/shared/i18n.js';

const CONTEST = 'treino';
const TARGET = new URLSearchParams(location.search).get('c') || '';
let st = null, busy = false, tick = null;

const contestUrl = () => (/^moj\./i.test(location.hostname)
  ? `${location.protocol}//${TARGET}.${location.host}/`
  : `/contest/?c=${encodeURIComponent(TARGET)}`);

function fmtLeft(s) {
  if (s <= 0) return '0s';
  const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600),
        m = Math.floor(s % 3600 / 60), x = Math.floor(s % 60);
  return d ? `${d}d ${h}h` : h ? `${h}h ${m}min` : m ? `${m}min ${x}s` : `${x}s`;
}

const msg = el('div', { class: 'small', style: 'margin:.6rem 0' });
function ok(t) { msg.className = 'small v-ok'; msg.style.cssText = 'margin:.6rem 0;padding:.35rem .6rem;border-radius:7px'; msg.textContent = t; }
function err(t) { msg.className = 'small error-box'; msg.style.cssText = 'margin:.6rem 0'; msg.textContent = t; }

async function act(body, okText) {
  if (busy) return;
  busy = true;
  try {
    st = await apiPost('/treino/contest-registration', { contest: TARGET, ...body }, { contest: CONTEST, auth: true });
    render(); if (okText) ok(okText);
  } catch (e) { err(e.message || T('falha', 'failed')); }
  finally { busy = false; }
}

// ---------------------------------------------------------------- blocos
function windowBox() {
  const w = st.window || {}, now = Math.floor(Date.now() / 1000);
  const box = el('div', { class: w.state === 'open' ? 'notice' : w.state === 'late' ? 'notice' : 'error-box',
                          style: 'margin:.6rem 0' });
  // o contador é um nó PRÓPRIO, atualizado a cada segundo: re-renderizar a página inteira
  // apagaria o nome do time que a pessoa está digitando
  const cd = el('b', {}, ''), deadline = w.state === 'late' ? (w.late_until || 0) : (w.closes_at || 0);
  if (deadline > now) {
    clearInterval(tick);
    tick = setInterval(() => {
      const left = deadline - Math.floor(Date.now() / 1000);
      if (left <= 0) { clearInterval(tick); load(true); return; }   // virou a janela: recarrega
      cd.textContent = fmtLeft(left);
    }, 1000);
    cd.textContent = fmtLeft(deadline - now);
  }
  if (w.state === 'open') {
    box.append(el('b', {}, T('Inscrições abertas', 'Registration open')));
    if (deadline > now) box.append(el('span', {}, T(' — fecham em ', ' — closes in ')), cd,
      el('span', {}, ' (' + fmtDate(w.closes_at) + ')'));
  } else if (w.state === 'late') {
    box.append(el('b', {}, T('⏰ Inscrição atrasada', '⏰ Late registration')),
      el('span', {}, T(' — a prova já começou. Dá para entrar por mais ', ' — the contest already started. You can still join for ')), cd,
      el('span', {}, T(', mas fora da disputa oficial (aparece no placar sem ocupar posição).',
            ', but out of the official ranking (you show up on the scoreboard without taking a position).')));
  } else if (w.state === 'soon') {
    box.append(el('b', {}, T('Inscrições ainda não abriram', 'Registration has not opened yet')),
      el('span', {}, w.opens_at ? T(' — abrem em ', ' — opens in ') + fmtLeft(w.opens_at - now) : ''));
  } else {
    box.append(el('b', {}, T('Inscrições encerradas', 'Registration closed')));
  }
  return box;
}

const canAct = () => st.window && (st.window.state === 'open' || st.window.state === 'late');

function meBox() {
  const kind = (st.me || {}).kind || 'none';
  const late = String((st.me || {}).cohort || '').endsWith('-atrasado');
  const s = el('div', { class: 'section' });

  if (kind === 'none') {
    s.append(el('h2', {}, T('Como você quer participar?', 'How do you want to take part?')),
      el('p', { class: 'small muted' },
        T('Escolha uma das duas: individual ou em time de até ', 'Pick one: individually or in a team of up to ')
        + (st.team_max || 3) + T(' pessoas com conta no Treino Livre.', ' people with a Free Training account.')));
    const row = el('div', { class: 'row', style: 'gap:.6rem; flex-wrap:wrap' });
    row.append(el('button', { class: 'btn', disabled: !canAct(),
      onclick: () => act({ action: 'register' }, T('Inscrição feita!', 'You are registered!')) },
      T('Participar individualmente', 'Take part individually')));
    if (st.teams_allowed !== false) {
      const name = el('input', { placeholder: T('nome do time', 'team name'), style: 'min-width:15rem' });
      row.append(el('span', { class: 'row', style: 'gap:.4rem' }, name,
        el('button', { class: 'btn ghost', disabled: !canAct(),
          onclick: () => act({ action: 'team-create', name: name.value.trim() },
                             T('Time criado — agora convide o resto.', 'Team created — now invite the others.')) },
          T('Criar um time', 'Create a team'))));
    }
    s.append(row);
    return s;
  }

  if (kind === 'individual') {
    s.append(el('h2', {}, T('✅ Você está inscrito (individual)', '✅ You are registered (individual)')),
      el('p', { class: 'small muted' },
        T('Entre no contest com o SEU login e senha do Treino Livre.', 'Log into the contest with YOUR Free Training username and password.')),
      late ? el('p', { class: 'small' }, T('⏰ Inscrição atrasada: você aparece no placar sem ocupar posição oficial.',
                                           '⏰ Late registration: you appear on the scoreboard without taking an official position.')) : '',
      el('div', { class: 'row', style: 'gap:.6rem' },
        el('a', { class: 'btn', href: contestUrl() }, T('Ir para o contest →', 'Go to the contest →')),
        el('button', { class: 'btn ghost danger', disabled: !canAct(),
          onclick: () => confirm(T('Cancelar sua inscrição?', 'Cancel your registration?'))
            && act({ action: 'cancel' }, T('Inscrição cancelada.', 'Registration cancelled.')) },
          T('Cancelar inscrição', 'Cancel registration'))));
    return s;
  }

  // --- time
  const t = st.team || {}, me = window.__MOJ_LOGIN || '';
  const isCap = t.captain && t.captain === me;
  s.append(el('h2', {}, T('👥 Time: ', '👥 Team: ') + (t.name || '')),
    el('p', { class: 'small muted' },
      T('Na prova, cada um entra com o PRÓPRIO login e senha do Treino Livre — as submissões contam para o time.',
        'During the contest each of you logs in with THEIR OWN Free Training credentials — submissions count for the team.')),
    late ? el('p', { class: 'small' }, T('⏰ Time inscrito atrasado: aparece no placar sem ocupar posição oficial.',
                                         '⏰ Late team: it appears on the scoreboard without taking an official position.')) : '');

  const list = el('ul', { style: 'margin:.4rem 0 .4rem 1.1rem' });
  (t.members || []).forEach((m) => list.append(el('li', {}, m + (m === t.captain ? T(' — capitão', ' — captain') : ''))));
  (t.invited || []).forEach((m) => list.append(el('li', { class: 'muted' }, m + T(' — convite pendente', ' — invite pending'))));
  s.append(list);

  if (isCap && canAct()) {
    const room = (st.team_max || 3) - ((t.members || []).length + (t.invited || []).length);
    if (room > 0) {
      const who = el('input', { placeholder: T('login no Treino Livre', 'Free Training username'), style: 'min-width:14rem' });
      s.append(el('div', { class: 'row', style: 'gap:.4rem; margin:.4rem 0' }, who,
        el('button', { class: 'btn ghost',
          onclick: () => act({ action: 'team-invite', login: who.value.trim() },
                             T('Convite enviado.', 'Invite sent.')) }, T('Convidar', 'Invite')),
        el('span', { class: 'small muted' }, T('cabem mais ', 'room for ') + room)));
    }
    const nm = el('input', { value: t.name || '', style: 'min-width:14rem' });
    s.append(el('div', { class: 'row', style: 'gap:.4rem; margin:.4rem 0' }, nm,
      el('button', { class: 'btn ghost',
        onclick: () => act({ action: 'team-rename', name: nm.value.trim() }, T('Nome trocado.', 'Name changed.')) },
        T('Renomear', 'Rename'))));
  }

  const acts = el('div', { class: 'row', style: 'gap:.6rem; margin-top:.5rem' },
    el('a', { class: 'btn', href: contestUrl() }, T('Ir para o contest →', 'Go to the contest →')));
  if (canAct()) {
    acts.append(el('button', { class: 'btn ghost danger',
      onclick: () => confirm(T('Sair do time?', 'Leave the team?')) && act({ action: 'team-leave' }, T('Você saiu do time.', 'You left the team.')) },
      T('Sair do time', 'Leave team')));
    if (isCap) acts.append(el('button', { class: 'btn ghost danger',
      onclick: () => confirm(T('Desfazer o time inteiro?', 'Dissolve the whole team?'))
        && act({ action: 'team-dissolve' }, T('Time desfeito.', 'Team dissolved.')) },
      T('Desfazer o time', 'Dissolve team')));
  }
  s.append(acts);
  return s;
}

function invitesBox() {
  const inv = st.invites || [];
  if (!inv.length) return '';
  const s = el('div', { class: 'section' }, el('h2', {}, T('✉️ Convites para você', '✉️ Invites for you')));
  inv.forEach((i) => s.append(el('div', { class: 'row', style: 'gap:.6rem; align-items:center; margin:.3rem 0' },
    el('b', {}, i.name), el('span', { class: 'small muted' }, T('de ', 'from ') + i.captain + ' · ' + (i.members || []).join(', ')),
    el('div', { class: 'spacer' }),
    el('button', { class: 'btn', disabled: !canAct(), onclick: () => act({ action: 'team-accept', team: i.login }, T('Você entrou no time!', 'You joined the team!')) }, T('Aceitar', 'Accept')),
    el('button', { class: 'btn ghost', onclick: () => act({ action: 'team-decline', team: i.login }, T('Convite recusado.', 'Invite declined.')) }, T('Recusar', 'Decline')))));
  return s;
}

function render() {
  const c = document.getElementById('content');
  c.innerHTML = '';
  clearInterval(tick);
  c.append(el('div', { class: 'row', style: 'align-items:baseline; gap:.6rem; flex-wrap:wrap' },
    el('h1', { style: 'margin:.2rem 0' }, st.contest_name || TARGET),
    el('span', { class: 'small muted' }, T('início ', 'start ') + fmtDate(st.start_time) + T(' · fim ', ' · end ') + fmtDate(st.end_time)),
    el('div', { class: 'spacer' }),
    el('a', { class: 'btn ghost', href: '/#contests', style: 'padding:.32rem .7rem; font-size:.82rem' }, T('← contests', '← contests'))));

  if (st.enabled === false) {
    c.append(el('div', { class: 'notice', style: 'margin:.8rem 0' },
      T('Este contest não pede inscrição — é só entrar com a sua conta do Treino Livre.',
        'This contest does not require registration — just log in with your Free Training account.')),
      el('a', { class: 'btn', href: contestUrl() }, T('Ir para o contest →', 'Go to the contest →')));
    return;
  }
  c.append(windowBox(), msg, invitesBox(), meBox());
  const tot = st.totals || {};
  c.append(el('p', { class: 'small muted', style: 'margin-top:1rem' },
    T('Inscritos: ', 'Registered: ') + (tot.people || 0) + T(' pessoas · ', ' people · ') + (tot.teams || 0)
    + T(' times · ', ' teams · ') + (tot.individuals || 0) + T(' individuais.', ' individuals.')));
}

async function load(quiet) {
  const c = document.getElementById('content');
  if (!TARGET) { c.innerHTML = '<div class="error-box">' + T('Falta o contest (?c=…).', 'Missing contest (?c=…).') + '</div>'; return; }
  const s = await status(CONTEST);
  if (!s.logged_in) {
    clearInterval(tick);
    c.innerHTML = '<div class="notice" style="margin-top:1rem">'
      + T('Entre com a sua conta do Treino Livre (no topo da página) para se inscrever neste contest.',
          'Log in with your Free Training account (top of the page) to register for this contest.') + '</div>';
    return;
  }
  window.__MOJ_LOGIN = s.login;
  try {
    st = await apiGet('/treino/contest-registration?contest=' + encodeURIComponent(TARGET), { contest: CONTEST, auth: true });
    render();
  } catch (e) {
    if (quiet) return;
    clearInterval(tick);
    c.innerHTML = '<div class="error-box" style="margin-top:1rem">' + (e.message || T('falha ao carregar', 'failed to load')) + '</div>';
  }
}

async function boot() {
  await renderAuthArea(document.getElementById('authArea'), CONTEST, () => load());
  load();
}
boot();
