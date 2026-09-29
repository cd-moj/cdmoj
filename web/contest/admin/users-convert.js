// contest/admin/users-convert.js — cartão "🔗 Contas compartilhadas com o Treino Livre" de Pessoas › Contas.
// O "desfazer" do compartilhamento (USERS_FROM): prévia → confirmação → conversão em contas PRÓPRIAS
// (POST /contest/admin/users-convert; regra e invariantes em server/api/v1/lib/users-convert.sh).
// A prévia não grava nada; converter exige o plan_id dela (a lista mudou = 409 plan_changed, e o cartão
// mostra a prévia nova) e, com a prova já começada, o id do contest digitado. As senhas novas só
// aparecem na resposta — daí o CSV e o atalho para as etiquetas logo no resultado.
import { el } from '/shared/ui.js';
import { apiPost } from '/shared/api.js';
import { downloadCsv } from '/shared/users-batch.js';
import { T } from '/shared/i18n.js';

const enc = encodeURIComponent;

// avisos da prévia (códigos do servidor) → texto
function warnText(code, p) {
  const c = p.counts || {};
  switch (code) {
    case 'live': return T('A prova já começou. Quem está logado continua logado; quem sair precisa da senha NOVA — distribua as credenciais antes.',
      'The contest has already started. Whoever is logged in stays logged in; whoever leaves needs the NEW password — hand out the credentials first.',
      'La competencia ya empezó. Quien tiene la sesión iniciada la conserva; quien salga necesita la contraseña NUEVA — entrega las credenciales antes.');
    case 'team_members_lose_login': return T('Cada time vira UMA conta (login time-…) com senha única; os membros deixam de entrar com as contas deles.',
      'Each team becomes ONE account (login time-…) with a single password; the members no longer log in with their own accounts.',
      'Cada equipo pasa a ser UNA cuenta (usuario time-…) con contraseña única; los miembros dejan de entrar con sus propias cuentas.');
    case 'member_history_disabled': return T('Membros de time que já submeteram viram contas desabilitadas — a linha deles no placar fica.',
      'Team members who already submitted become disabled accounts — their scoreboard row stays.',
      'Los miembros de equipo que ya enviaron pasan a ser cuentas deshabilitadas — su fila en el marcador se mantiene.');
    case 'new_scoreboard_rows': return (c.new_scoreboard_rows || 0) + T(' pessoa(s) entraram sem submeter e passam a aparecer zeradas no placar.',
      ' person(s) logged in without submitting and will now show up with zero in the scoreboard.',
      ' persona(s) entraron sin enviar y pasan a aparecer en cero en el marcador.');
    case 'never_entered_excluded': return T('Quem nunca entrou neste contest não ganha conta (dá para adicionar depois em ➕ Adicionar).',
      'Whoever never entered this contest gets no account (you can add them later in ➕ Add).',
      'Quien nunca entró en esta competencia no recibe cuenta (se puede agregar después en ➕ Agregar).');
    case 'registration_closes': return T('A inscrição é encerrada e o roster, arquivado.',
      'Registration is closed and the roster is archived.',
      'La inscripción se cierra y el roster queda archivado.');
    case 'superadmins_lose_access': return T('Os superadmins do Treino Livre deixam de entrar neste contest.',
      'The Free Training superadmins can no longer enter this contest.',
      'Los superadmins de Entrenamiento libre dejan de entrar en esta competencia.');
    case 'admin_local_created': return T('O admin ', 'The admin ', 'El admin ') + (p.admin || '') +
      T(' ganha conta própria com senha NOVA (mostrada uma única vez, a seguir). A senha do Treino deixa de valer aqui.',
        ' gets its own account with a NEW password (shown only once, next). The Free Training password stops working here.',
        ' recibe una cuenta propia con contraseña NUEVA (se muestra una sola vez, a continuación). La contraseña de Entrenamiento libre deja de valer aquí.');
    default: return code;
  }
}

export function makeConvertCard(CONTEST, { onDone } = {}) {
  const G = { contest: CONTEST, auth: true };
  const call = (body) => apiPost('/contest/admin/users-convert?contest=' + enc(CONTEST), body, G);
  const box = el('div', {});
  const card = el('div', { class: 'notice', style: 'margin:.4rem 0 .8rem; display:none' });
  let SRC = '', DONE = false, introRow = null;   // DONE: o resultado (com as senhas) fica na tela mesmo depois que o contest deixa de ser compartilhado

  function intro() {
    card.innerHTML = '';
    const prevBtn = el('button', { class: 'btn', onclick: () => preview() }, T('Ver prévia da conversão', 'Preview the conversion', 'Ver vista previa de la conversión'));
    card.append(
      el('b', {}, T('🔗 Contas compartilhadas com o Treino Livre', '🔗 Accounts shared with Free Training', '🔗 Cuentas compartidas con Entrenamiento libre'), ' (', SRC, ')'),
      el('p', { class: 'small', style: 'margin:.3rem 0' },
        T('Os participantes entram com a conta e a senha do Treino Livre: você não as vê nem redefine, e as etiquetas saem sem senha. Para uma prova, converta em contas PRÓPRIAS deste contest: cada participante ganha uma senha NOVA, o histórico e o placar ficam. A conversão não tem volta.',
          'Participants log in with their Free Training account and password: you cannot see or reset them, and the badges come out without a password. For an exam, convert them into this contest\'s OWN accounts: each participant gets a NEW password, the history and the scoreboard stay. The conversion cannot be undone.',
          'Los participantes entran con la cuenta y la contraseña de Entrenamiento libre: no las ves ni las restableces, y las etiquetas salen sin contraseña. Para un examen, conviértelas en cuentas PROPIAS de esta competencia: cada participante recibe una contraseña NUEVA; el historial y el marcador se mantienen. La conversión no tiene vuelta atrás.')),
      (introRow = el('div', { class: 'row' }, prevBtn)), box);
  }

  function renderPreview(p, note) {
    box.innerHTML = '';
    const c = p.counts || {}, f = c.from || {}, s = p.samples || {};
    const live = p.phase !== 'before';
    const lines = [
      (c.individuals || 0) + T(' participante(s) ganham conta própria', ' participant(s) get their own account', ' participante(s) reciben cuenta propia'),
      (c.teams || 0) + T(' time(s) — uma conta cada', ' team(s) — one account each', ' equipo(s) — una cuenta cada uno'),
    ];
    if (c.members_with_history) lines.push(c.members_with_history + T(' membro(s) de time com submissão ficam desabilitados', ' team member(s) with submissions become disabled', ' miembro(s) de equipo con envíos quedan deshabilitados'));
    if (c.members_losing_login) lines.push(c.members_losing_login + T(' membro(s) de time passam a entrar pelo time', ' team member(s) now log in through the team', ' miembro(s) de equipo pasan a entrar por el equipo'));
    if (c.resumed) lines.push(c.resumed + T(' já convertida(s) numa tentativa anterior (a senha está nas etiquetas)', ' already converted in a previous attempt (the password is on the badges)', ' ya convertida(s) en un intento anterior (la contraseña está en las etiquetas)'));
    const from = T('De onde vieram: ', 'Where they came from: ', 'De dónde vinieron: ') +
      (f.dir || 0) + T(' com pasta no contest · ', ' with a folder in the contest · ', ' con carpeta en la competencia · ') +
      (f.session || 0) + T(' com sessão aberta · ', ' with an open session · ', ' con sesión abierta · ') +
      (f.access_log || 0) + T(' pelo log de acessos · ', ' from the access log · ', ' por el registro de accesos · ') +
      (f.registration || 0) + T(' inscritos', ' registered', ' inscritos');
    const sample = (title, arr, fmt) => (arr && arr.length)
      ? el('details', { class: 'small' }, el('summary', {}, title + ' (' + arr.length + (arr.length >= 50 ? '+' : '') + ')'),
        el('div', { style: 'max-height:12rem; overflow:auto' }, arr.map(fmt).join(', '))) : '';
    const logout = el('input', { type: 'checkbox' });
    const ack = el('input', { type: 'checkbox' });
    const typed = el('input', { placeholder: CONTEST, autocomplete: 'off', style: 'width:14rem' });
    const go = el('button', { class: 'btn danger' }, T('Converter em contas próprias', 'Convert into own accounts', 'Convertir en cuentas propias'));
    go.disabled = true;
    const msg = el('div', { class: 'small' });
    const ready = () => { go.disabled = live ? typed.value.trim() !== CONTEST : !ack.checked; };
    ack.addEventListener('change', ready); typed.addEventListener('input', ready);
    go.onclick = async () => {
      go.disabled = true; msg.className = 'small'; msg.textContent = T('Convertendo…', 'Converting…', 'Convirtiendo…');
      try {
        const r = await call({ dry_run: false, plan_id: p.plan_id, confirm: live ? typed.value.trim() : true, logout_all: !!logout.checked });
        renderResult(r);
        if (onDone) onDone();
      } catch (e) {
        if (e.code === 'plan_changed' && e.data && e.data.preview) {
          renderPreview(e.data.preview, T('A lista mudou desde a prévia (alguém entrou ou se inscreveu). Confira de novo e confirme.',
            'The list changed since the preview (someone logged in or registered). Check it again and confirm.',
            'La lista cambió desde la vista previa (alguien entró o se inscribió). Revísala de nuevo y confirma.'));
          return;
        }
        msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed', 'fallido'); ready();
      }
    };
    box.append(
      note ? el('div', { class: 'error-box small', style: 'margin:.4rem 0' }, note) : '',
      el('ul', { class: 'small', style: 'margin:.4rem 0; padding-left:1.2rem' }, ...lines.map((x) => el('li', {}, x))),
      el('div', { class: 'small muted' }, from),
      sample(T('Participantes', 'Participants', 'Participantes'), s.individuals, (x) => x),
      sample(T('Times', 'Teams', 'Equipos'), s.teams, (t) => t.login + (t.members && t.members.length ? ' [' + t.members.join(' ') + ']' : '')),
      sample(T('Membros desabilitados', 'Disabled members', 'Miembros deshabilitados'), s.members_with_history, (m) => m.login + ' → ' + m.team),
      el('ul', { class: 'small', style: 'margin:.5rem 0; padding-left:1.2rem' }, ...(p.warnings || []).map((w) => el('li', {}, '⚠ ' + warnText(w, p)))),
      el('label', { class: 'small', style: 'display:block; margin:.3rem 0' }, logout,
        T(' Derrubar as sessões abertas dos participantes (entram de novo com a senha nova)', ' Log out the participants\' open sessions (they log in again with the new password)', ' Cerrar las sesiones abiertas de los participantes (vuelven a entrar con la contraseña nueva)')),
      live
        ? el('div', { class: 'error-box small', style: 'margin:.4rem 0' },
          T('A prova já começou. Para confirmar, digite o id do contest (', 'The contest has already started. To confirm, type the contest id (', 'La competencia ya empezó. Para confirmar, escribe el id de la competencia ('),
          el('b', {}, CONTEST), '): ', typed)
        : el('label', { class: 'small', style: 'display:block; margin:.3rem 0' }, ack,
          T(' Entendi: a conversão não tem volta.', ' I understand: the conversion cannot be undone.', ' Entendido: la conversión no tiene vuelta atrás.')),
      el('div', { class: 'row' }, go), msg);
  }

  function renderResult(r) {
    DONE = true; box.innerHTML = '';
    const creds = r.credentials || [];
    const withPw = creds.filter((x) => x.password);
    const adm = creds.find((x) => x.kind === 'admin' && x.password);
    if (introRow) introRow.style.display = 'none';
    box.append(el('p', {}, '✓ ' + T('Convertido: ', 'Converted: ', 'Convertido: ') + withPw.length + T(' conta(s) com senha nova.', ' account(s) with a new password.', ' cuenta(s) con contraseña nueva.')));
    if (adm) box.append(el('div', { class: 'error-box', style: 'margin:.4rem 0' },
      T('Sua senha de admin agora é ', 'Your admin password is now ', 'Tu contraseña de admin ahora es '), el('span', { class: 'cred' }, adm.password),
      ' (', adm.login, ') — ', T('guarde-a: a do Treino Livre não vale mais aqui.', 'keep it: the Free Training one no longer works here.', 'guárdala: la de Entrenamiento libre ya no vale aquí.')));
    box.append(el('div', { class: 'row', style: 'margin:.4rem 0' },
      el('button', { class: 'btn', onclick: () => downloadCsv(CONTEST + '-credenciais.csv', withPw) }, T('⬇ baixar credenciais (CSV)', '⬇ download credentials (CSV)', '⬇ descargar credenciales (CSV)')),
      el('a', { class: 'btn ghost', target: '_blank', href: '/contest/badges/?c=' + enc(CONTEST) }, T('🏷️ Etiquetas de credenciais', '🏷️ Credential badges', '🏷️ Etiquetas de credenciales'))),
      el('p', { class: 'small muted' }, T('As senhas só aparecem agora e nas etiquetas. ', 'The passwords only show up now and on the badges. ', 'Las contraseñas solo aparecen ahora y en las etiquetas. ') +
        (r.sessions_removed ? r.sessions_removed + T(' sessão(ões) encerrada(s).', ' session(s) ended.', ' sesión(es) cerrada(s).') : '')));
  }

  async function preview() {
    box.innerHTML = ''; box.append(el('div', { class: 'small muted' }, T('Levantando as contas…', 'Collecting the accounts…', 'Reuniendo las cuentas…')));
    try { const r = await call({ dry_run: true }); renderPreview(r.preview); }
    catch (e) { box.innerHTML = ''; box.append(el('div', { class: 'error-box small' }, e.message || T('falha', 'failed', 'fallido'))); }
  }

  // show(src): contest compartilhado (src = a fonte) → cartão; vazio → some
  function show(src) {
    if (DONE) return;
    if (!src) { card.style.display = 'none'; return; }
    if (card.style.display === 'none' || SRC !== src) { SRC = src; intro(); }
    card.style.display = '';
  }
  return { el: card, show };
}
