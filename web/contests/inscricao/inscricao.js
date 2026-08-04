// contests/inscricao/inscricao.js — INSCRIÇÃO num contest com a conta do Treino Livre:
// individual ou em TIME de até 3 contas existentes (convite + aceite).
//
// Esta página vive no SITE PRINCIPAL de propósito: o token é por origem, e o subdomínio do
// contest (`<id>.moj…`) tem outro localStorage — quem se inscreve é a conta do treino.
// Na prova, cada membro entra no contest com a PRÓPRIA senha e a sessão vira a do time.
import { apiGet, apiPost } from '/shared/api.js';
import { status } from '/shared/auth.js';
import { el, renderAuthArea, fmtDate } from '/shared/ui.js';
import { flagManifest, flagEl } from '/shared/flags.js';
import { T } from '/shared/i18n.js';

const CONTEST = 'treino';
const TARGET = new URLSearchParams(location.search).get('c') || '';
let st = null, busy = false, tick = null, FLAGS = null;

// seletor de bandeira: estados do Brasil primeiro (o público é BR), países depois; tudo
// offline (shared/flags/). Devolve {sel, box} — box mostra o preview da bandeira escolhida.
function flagPicker(current) {
  const sel = el('select', { style: 'max-width:16rem' },
    el('option', { value: '' }, T('bandeira (opcional)', 'flag (optional)')));
  const prev = el('span', { style: 'display:inline-flex;align-items:center;min-width:26px' });
  const draw = () => { prev.innerHTML = ''; const f = flagEl(sel.value, { height: 18 }); if (f) prev.append(f); };
  if (FLAGS) {
    const gBR = el('optgroup', { label: T('Estados do Brasil', 'Brazilian states') });
    (FLAGS.br_states || []).forEach((x) => gBR.append(el('option', { value: x.code }, x.name)));
    const gW = el('optgroup', { label: T('Países', 'Countries') });
    (FLAGS.countries || []).forEach((x) => gW.append(el('option', { value: x.code }, x.name)));
    sel.append(gBR, gW);
  }
  sel.value = current || '';
  sel.addEventListener('change', draw); draw();
  return { sel, box: el('span', { class: 'row', style: 'gap:.3rem;align-items:center' }, sel, prev) };
}

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
      el('span', {}, ' (' + fmtDate(w.closes_at)
        + (w.official_start && w.official_start === w.closes_at ? T(', início da prova', ', contest start') : '') + ')'));
    else box.append(el('span', {}, T(' — sem prazo definido ainda (a prova oficial não está marcada)',
                                     ' — no deadline yet (the official contest is not scheduled)')));
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

// AQUECIMENTO: por padrão o aquecimento também exige inscrição (só inscrito entra — quem não
// resolve isso no warmup vira atraso no dia da prova). gate_active=false = o contest optou
// pela porta aberta (REG_WARMUP_OPEN=y).
function warmupBox() {
  if (st.round_kind !== 'warmup') return '';
  const w = st.window || {};
  if (st.gate_active === false) {
    return el('div', { class: 'notice', style: 'margin:.6rem 0' },
      el('b', {}, T('🔥 Aquecimento no ar — entrada livre', '🔥 Warm-up running — open door')),
      el('span', {}, T(' Qualquer conta do Treino Livre entra e treina agora, sem inscrição. Para a PROVA você precisa estar inscrito',
                       ' Anyone with a Free Training account can come in and practice now, no registration needed. For the CONTEST you must be registered')),
      w.official_start ? el('span', {}, T(' — ela começa em ', ' — it starts on ') + fmtDate(w.official_start) + '.') : el('span', {}, '.'));
  }
  return el('div', { class: 'notice', style: 'margin:.6rem 0' },
    el('b', {}, T('🔥 Aquecimento no ar — só para inscritos', '🔥 Warm-up running — registered only')),
    el('span', {}, T(' Inscreva-se para participar do aquecimento E da prova: é no aquecimento que você testa login, submissão e placar — resolver isso agora evita atraso no dia',
                     ' Register to join the warm-up AND the contest: the warm-up is where you test login, submissions and the scoreboard — sorting it out now avoids delays on the day')),
    w.official_start ? el('span', {}, T('. A prova começa em ', '. The contest starts on ') + fmtDate(w.official_start) + '.') : el('span', {}, '.'));
}

function meBox() {
  const kind = (st.me || {}).kind || 'none';
  const late = String((st.me || {}).cohort || '').endsWith('-atrasado');
  const s = el('div', { class: 'section' });

  if (kind === 'none') {
    s.append(el('h2', {}, T('Como você quer participar?', 'How do you want to take part?')),
      el('p', { class: 'small muted' },
        T('Escolha uma das duas: individual ou em time de até ', 'Pick one: individually or in a team of up to ')
        + (st.team_max || 3) + T(' pessoas com conta no Treino Livre.', ' people with a Free Training account.')),
      el('div', { class: 'notice', style: 'margin:.3rem 0 .6rem' },
        el('b', {}, T('⚠️ Escolha com calma: ', '⚠️ Choose carefully: ')),
        T('depois de inscrito, o modo de participação (individual ou time) é definitivo — para qualquer mudança, fale com a organização.',
          'once registered, your participation mode (individual or team) is final — for any change, talk to the organizers.')));
    const row = el('div', { class: 'row', style: 'gap:.6rem; flex-wrap:wrap' });
    row.append(el('button', { class: 'btn', disabled: !canAct(),
      onclick: () => act({ action: 'register' }, T('Inscrição feita!', 'You are registered!')) },
      T('Participar individualmente', 'Take part individually')));
    if (st.teams_allowed !== false) {
      const name = el('input', { placeholder: T('nome do time', 'team name'), style: 'min-width:15rem' });
      const univ = el('input', { placeholder: T('sigla da universidade (opcional)', 'university acronym (optional)'), style: 'width:16rem', maxlength: '20' });
      const aiSel = el('select', {},
        el('option', { value: '' }, T('uso de IA: prefiro não declarar', 'AI use: prefer not to say')),
        el('option', { value: 'yes' }, T('🤖 vamos usar IA', '🤖 we will use AI')),
        el('option', { value: 'no' }, T('sem IA, na raça', 'no AI, old school')));
      const fp = flagPicker('');
      row.append(el('span', { class: 'row', style: 'gap:.4rem; flex-wrap:wrap' }, name, univ, aiSel, fp.box,
        el('button', { class: 'btn ghost', disabled: !canAct(),
          onclick: () => act({ action: 'team-create', name: name.value.trim(),
                               univ: univ.value.trim(), ai: aiSel.value, flag: fp.sel.value },
                             T('Time criado — agora convide o resto.', 'Team created — now invite the others.')) },
          T('Criar um time', 'Create a team'))));
      row.append(el('div', { class: 'small muted', style: 'flex-basis:100%' },
        T('A universidade vira o prefixo do nome no placar — “[SIGLA] Seu Time” — e a declaração de IA aparece como 🤖 ao lado do nome (transparência, sem julgamento).',
          'The university becomes the team-name prefix on the scoreboard — “[ACRONYM] Your Team” — and the AI declaration shows as 🤖 next to the name (transparency, not judgement).')));
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
        el('a', { class: 'btn', href: contestUrl() }, T('Ir para o contest →', 'Go to the contest →'))),
      el('p', { class: 'small muted', style: 'margin-top:.4rem' },
        T('Sua participação individual está confirmada e é definitiva — precisa mudar algo? Fale com a organização.',
          'Your individual participation is confirmed and final — need a change? Talk to the organizers.')));
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

    // universidade + declaração de IA (capitão edita enquanto a janela estiver aberta)
    const univ = el('input', { value: t.univ || '', maxlength: '20',
      placeholder: T('sigla da universidade', 'university acronym'), style: 'width:14rem' });
    const aiSel = el('select', {},
      el('option', { value: '' }, T('uso de IA: não declarado', 'AI use: not declared')),
      el('option', { value: 'yes' }, T('🤖 vamos usar IA', '🤖 we will use AI')),
      el('option', { value: 'no' }, T('sem IA, na raça', 'no AI, old school')));
    aiSel.value = t.ai === true ? 'yes' : t.ai === false ? 'no' : '';
    const fp = flagPicker(t.flag || '');
    s.append(el('div', { class: 'row', style: 'gap:.4rem; margin:.4rem 0; flex-wrap:wrap' }, univ, aiSel, fp.box,
      el('button', { class: 'btn ghost',
        onclick: () => act({ action: 'team-meta', univ: univ.value.trim(), ai: aiSel.value, flag: fp.sel.value },
                           T('Dados do time salvos.', 'Team info saved.')) },
        T('Salvar universidade/IA/bandeira', 'Save university/AI/flag'))));
    s.append(el('p', { class: 'small muted', style: 'margin:.1rem 0 .4rem' },
      T('No placar, a universidade aparece como prefixo do nome — “[SIGLA] Seu Time”.',
        'On the scoreboard the university shows as the name prefix — “[ACRONYM] Your Team”.')));

    // foto do time — pública no placar; pedido de bom senso escrito com carinho
    const file = el('input', { type: 'file', accept: 'image/*' });
    s.append(el('div', { class: 'section', style: 'margin:.5rem 0' },
      el('h3', { style: 'margin:.2rem 0' }, T('📷 Foto do time', '📷 Team photo')
        + (t.has_photo ? ' ✓' : '')),
      el('p', { class: 'small muted' },
        T('Uma foto deixa o placar com cara de gente. Escolham uma imagem em que o time apareça bem e da qual vocês se orgulhem — ela fica pública no placar durante toda a prova (e nas lembranças depois dela). Capricha: é assim que a comunidade vai conhecer vocês. 😊',
          'A photo gives the scoreboard a human face. Pick an image the team looks good in and is proud of — it stays public on the scoreboard for the whole contest (and in the memories afterwards). Make it count: this is how the community will meet you. 😊')),
      t.has_photo ? el('img', { src: '/api/v1/contest/team-photo?contest=' + encodeURIComponent(TARGET) + '&user=' + encodeURIComponent(t.login) + '&t=' + Date.now(),
        style: 'max-width:220px; border-radius:10px; display:block; margin:.3rem 0' }) : '',
      el('div', { class: 'row', style: 'gap:.4rem' }, file,
        el('button', { class: 'btn ghost', onclick: async () => {
          const f = file.files && file.files[0];
          if (!f) { err(T('Escolha uma imagem primeiro.', 'Pick an image first.')); return; }
          if (f.size > 4 * 1024 * 1024) { err(T('Imagem muito grande (máx 4MB).', 'Image too large (max 4MB).')); return; }
          const b64 = await new Promise((res, rej) => { const r = new FileReader(); r.onload = () => res(String(r.result)); r.onerror = rej; r.readAsDataURL(f); });
          act({ action: 'team-photo', image_b64: b64 }, T('Foto enviada! Ela já aparece no placar.', 'Photo uploaded! It already shows on the scoreboard.'));
        } }, T('Enviar foto', 'Upload photo')))));
  }

  s.append(el('div', { class: 'row', style: 'gap:.6rem; margin-top:.5rem' },
    el('a', { class: 'btn', href: contestUrl() }, T('Ir para o contest →', 'Go to the contest →'))),
    el('p', { class: 'small muted', style: 'margin-top:.4rem' },
      T('A formação em time é definitiva (dá para completar o time com convites até fechar a janela). Para sair ou desfazer, fale com a organização.',
        'The team setup is final (you can still fill the team via invites while the window is open). To leave or dissolve, talk to the organizers.')));
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
  c.append(warmupBox(), windowBox(), msg, invitesBox(), meBox());
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
  try { FLAGS = await flagManifest(); } catch (e) { FLAGS = null; }
  await renderAuthArea(document.getElementById('authArea'), CONTEST, () => load());
  load();
}
boot();
