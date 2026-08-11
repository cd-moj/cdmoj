// contest/admin/registrations-tab.js — painel "📝 Inscrições": o roster do contest (quem
// pode entrar) e a JANELA (quando dá p/ se inscrever). Espelha GET/POST
// /contest/admin/registrations (enable|disable|window|add|rm|team-add|team-rm|materialize|
// invite-remind|invite-remind-all).
//
// CONVITE PENDENTE é a linha que mais custa no dia da prova: quem não aceita NÃO entra como
// membro do time. Por isso cada convite aparece como uma pílula com o estado do canal (📨 =
// Telegram vinculado) e o botão 🔔 que manda o mojinho cutucar — o aviso da véspera é
// automático (lib/invite-notify.sh), este é o empurrão manual.
//
// Como funciona: com o registro LIGADO, só quem está no roster entra no contest (a API corta
// no /auth/login). Quem se inscreve são as contas do Treino Livre, pela página
// /contests/inscricao/ — aqui é a visão do organizador e o conserto à mão.
import { el, fmtDate } from '/shared/ui.js';
import { apiGet, apiPost } from '/shared/api.js';
import { T } from '/shared/i18n.js';
import { field, toCsv, downloadText } from '/shared/admin-ui.js';
import { toLocalDT, dtToEpoch } from '/shared/contest-config/index.js';
import { flagEl } from '/shared/flags.js';

const enc = encodeURIComponent;
// ⚠ datas: SEMPRE o par toLocalDT/dtToEpoch. `<input type=datetime-local>` é lido por Date.parse
// em hora LOCAL, então preencher com toISOString() (UTC) não fecha o ida-e-volta: a janela nascia
// +3h na tela e CADA "Salvar" empurrava REG_OPEN/REG_CLOSE mais 3h — bastava mexer no checkbox
// ao lado. É o helper que as outras 9 telas de data já usavam.
const tzName = () => { try { return Intl.DateTimeFormat().resolvedOptions().timeZone || ''; } catch { return ''; } };
const tzOffset = () => { const m = -new Date().getTimezoneOffset();
  return 'UTC' + (m < 0 ? '−' : '+') + Math.floor(Math.abs(m) / 60) + (Math.abs(m) % 60 ? ':' + String(Math.abs(m) % 60).padStart(2, '0') : ''); };

export function makeRegistrationsTab(CONTEST) {
  const G = { contest: CONTEST, auth: true };
  const panel = el('div', { class: 'section' });
  let DATA = null;

  const say = (m, bad) => { const d = panel.querySelector('#rgMsg'); if (!d) return; d.className = bad ? 'small error-box' : 'small v-ok'; d.textContent = m; };
  const post = (b) => apiPost('/contest/admin/registrations?contest=' + enc(CONTEST), b, G);
  // okMsg pode ser função (recebe a resposta) — o lembrete em lote precisa contar quantos foram
  async function act(body, okMsg) {
    try { DATA = await post(body); render(); say(typeof okMsg === 'function' ? okMsg(DATA) : okMsg); }
    catch (e) { say(e.message || T('falha', 'failed'), true); }
  }

  // "há 3 d" / "3d ago" — idade do convite (T() aqui dentro, nunca no topo do módulo: no topo
  // ele congelaria o idioma antes de o LOCALE do contest ser aplicado)
  function ago(at) {
    if (!at) return '';
    const s = Math.max(0, Math.floor(Date.now() / 1000) - at);
    const d = Math.floor(s / 86400), h = Math.floor(s / 3600);
    if (d >= 1) return T('há ' + d + ' d', d + 'd ago');
    if (h >= 1) return T('há ' + h + ' h', h + 'h ago');
    return T('há ' + Math.floor(s / 60) + ' min', Math.floor(s / 60) + 'm ago');
  }

  const STATE = () => ({
    open:   T('aberta', 'open'), late: T('atrasada (só fora de disputa)', 'late (out of competition only)'),
    soon:   T('ainda não abriu', 'not open yet'), closed: T('encerrada', 'closed'),
  }[(DATA.window || {}).state] || '?');

  function windowBox() {
    const w = DATA.window || {};
    const op = el('input', { type: 'datetime-local', value: toLocalDT(w.opens_at) });
    const cl = el('input', { type: 'datetime-local', value: toLocalDT(w.closes_at) });
    const lm = el('input', { type: 'number', min: '0', style: 'width:6rem',
      value: String(Math.max(0, Math.round(((w.late_until || 0) - (w.closes_at || 0)) / 60))) });
    const mx = el('input', { type: 'number', min: '1', max: '9', style: 'width:5rem', value: String(DATA.team_max || 3) });
    const tm = el('input', { type: 'checkbox' }); tm.checked = DATA.teams_allowed !== false;
    const rm = el('input', { type: 'checkbox' }); rm.checked = DATA.remind !== false;
    // a data herdada é a da PROVA OFICIAL (o aquecimento pode ficar dias no ar) — ver
    // reg_official_window em lib/registration.sh
    const anc = w.official_start ? fmtDate(w.official_start) : T('(prova não marcada)', '(contest not scheduled)');
    const herda = el('p', { class: 'small' },
      T('Deixe “fecha” vazio para herdar o início da prova: ', 'Leave “closes” empty to inherit the contest start: '),
      el('b', {}, anc),
      w.official_round ? el('span', { class: 'muted' }, T(' · rodada ', ' · round ') + w.official_round) : '');
    // em que relógio estão estes campos — a ambiguidade entre o fuso do navegador e o do contest
    // é o que fazia o organizador achar que o horário "andava sozinho"
    const inTz = (e, tz) => { try { return new Date(e * 1000).toLocaleString(undefined, { timeZone: tz, dateStyle: 'short', timeStyle: 'short' }); } catch { return ''; } };
    const ctz = DATA.tz || '';
    const difere = ctz && w.closes_at && inTz(w.closes_at, ctz) !== inTz(w.closes_at, undefined);
    const tzline = el('p', { class: 'small muted' },
      T('Horários no relógio DESTE navegador (', 'Times in THIS browser’s clock ('),
      (tzName() ? tzName() + ' · ' : '') + tzOffset(), ')',
      ctz ? T('. Fuso da prova: ', '. Contest timezone: ') + ctz : '',
      difere ? el('b', {}, T(' — lá, “fecha” é ', ' — there, “closes” is ') + inTz(w.closes_at, ctz)) : '');
    const form = el('div', { class: 'row', style: 'gap:.8rem; flex-wrap:wrap; align-items:flex-end' },
      field(T('abre', 'opens'), op), field(T('fecha', 'closes'), cl),
      field(T('atraso (min)', 'late (min)'), lm), field(T('tamanho do time', 'team size'), mx),
      el('div', { class: 'field' }, el('label', { style: 'font-weight:400' }, tm, ' ' + T('aceita times', 'teams allowed'))),
      el('div', { class: 'field' }, el('label', {
        style: 'font-weight:400',
        title: T('na véspera do fechamento, o mojinho manda UMA DM a cada convite ainda pendente',
                 'the day before it closes, mojinho sends ONE DM per still-pending invite'),
      }, rm, ' ' + T('lembrete automático', 'automatic reminder'))),
      el('button', { class: 'btn', onclick: () => act({
        action: 'window', open: dtToEpoch(op.value) || undefined,
        // `null` (não `undefined`) APAGA o REG_CLOSE: é o que faz a promessa do "deixe vazio para
        // herdar o início da prova" valer depois que o valor já foi gravado uma vez
        close: cl.value ? dtToEpoch(cl.value) : null,
        late_minutes: Number(lm.value) || 0, team_max: Number(mx.value) || 3, teams: tm.checked,
        remind: rm.checked,
      }, T('Janela salva.', 'Window saved.')) }, T('Salvar janela', 'Save window')));
    return el('div', { class: 'section' },
      el('h3', {}, T('Janela de inscrição', 'Registration window')),
      el('p', { class: 'small muted' },
        T('Fecha por padrão no início da PROVA OFICIAL — não no da rodada corrente: o aquecimento pode ficar dias no ar. Os minutos de atraso deixam entrar depois do início da prova, mas na coorte “atrasado” (aparece no placar sem ocupar posição) — é a extra registration do Codeforces.',
          'Closes at the OFFICIAL CONTEST start by default — not the current round: the warm-up may run for days. The late minutes let people join after the contest starts, but in the “late” cohort (they appear on the scoreboard without taking a position) — the Codeforces extra registration.')),
      herda, tzline, form);
  }

  // pílulas dos convites pendentes: quem é, se o mojinho alcança (📨), há quanto tempo espera,
  // se já foi avisado — e o botão de cutucar.
  function inviteChips(t) {
    const meta = (t.invited_meta && t.invited_meta.length) ? t.invited_meta
      : (t.invited || []).map((l) => ({ login: l, tg: false, at: 0, dm_at: 0, warned_at: 0 }));
    if (!meta.length) return el('span', { class: 'muted small' }, '—');
    return el('div', { class: 'row', style: 'gap:.35rem; flex-wrap:wrap' }, ...meta.map((m) => {
      const last = Math.max(m.dm_at || 0, m.warned_at || 0);
      const btn = el('button', {
        class: 'btn ghost', style: 'padding:0 .3rem; line-height:1.4',
        title: m.tg ? T('mandar um lembrete agora pelo mojinho', 'send a reminder now via mojinho')
                    : T('sem Telegram vinculado — nenhum lembrete alcança essa pessoa',
                        'no Telegram linked — no reminder can reach this person'),
        onclick: () => act({ action: 'invite-remind', team: t.login, login: m.login },
          T('Lembrete a caminho.', 'Reminder on its way.')),
      }, '🔔');
      if (!m.tg) btn.disabled = true;
      return el('span', { class: 'pill', style: 'gap:.3rem' },
        el('span', {}, (m.tg ? '📨 ' : '⚠️ ') + m.login),
        el('span', { class: 'small muted' },
          ago(m.at) + (last ? ' · ' + T('avisado ', 'notified ') + ago(last) : '')),
        btn);
    }));
  }

  function teamsTable() {
    const rows = (DATA.teams || []).map((t) => el('tr', {},
      el('td', {}, el('b', {}, (t.univ ? '[' + t.univ + '] ' : '') + t.name),
        el('div', { class: 'small muted' }, flagEl(t.flag, { height: 14 }) || '',
          (t.flag ? ' ' + t.flag.toUpperCase() + ' · ' : '') + t.login
          + (t.ai === true ? ' · 🤖 IA' : t.ai === false ? ' · sem IA' : '')
          + (t.has_photo ? ' · 📷' : ''))),
      el('td', {}, (t.members || []).join(', ')),
      el('td', { class: 'small' }, inviteChips(t)),
      el('td', { class: 'small' }, t.cohort || ''),
      el('td', {}, el('button', {
        class: 'btn ghost danger', title: T('dissolver', 'dissolve'),
        onclick: () => confirm(T(`Dissolver o time "${t.name}"?`, `Dissolve team "${t.name}"?`))
          && act({ action: 'team-rm', team: t.login }, T('Time dissolvido.', 'Team dissolved.')),
      }, '✕'))));
    return el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {},
        el('th', {}, T('Time', 'Team')), el('th', {}, T('Membros', 'Members')),
        el('th', {}, T('Convites pendentes', 'Pending invites')), el('th', {}, T('Coorte', 'Cohort')), el('th', {}, ''))),
      el('tbody', {}, ...(rows.length ? rows
        : [el('tr', {}, el('td', { colspan: '5', class: 'muted small' }, T('nenhum time inscrito', 'no teams registered')))]))));
  }

  function peopleTable() {
    const rows = (DATA.individuals || []).map((p) => el('tr', {},
      el('td', {}, (p.univ ? '[' + p.univ + '] ' : '') + p.login,
        el('span', { class: 'small muted' }, ' ', flagEl(p.flag, { height: 14 }) || '',
          (p.flag ? ' ' + p.flag.toUpperCase() : '')
          + (p.ai === true ? ' · 🤖 IA' : p.ai === false ? ' · sem IA' : ''))),
      el('td', { class: 'small' }, p.cohort || ''),
      el('td', { class: 'small muted' }, p.at ? fmtDate(p.at) : ''),
      el('td', {}, el('button', {
        class: 'btn ghost danger', title: T('remover', 'remove'),
        onclick: () => act({ action: 'rm', login: p.login }, T('Removido.', 'Removed.')),
      }, '✕'))));
    return el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, 'Login'), el('th', {}, T('Coorte', 'Cohort')),
        el('th', {}, T('Desde', 'Since')), el('th', {}, ''))),
      el('tbody', {}, ...(rows.length ? rows
        : [el('tr', {}, el('td', { colspan: '4', class: 'muted small' }, T('ninguém inscrito individualmente', 'nobody registered individually')))]))));
  }

  function render() {
    panel.innerHTML = '';
    const t = DATA.totals || {};
    panel.append(
      el('div', { class: 'row', style: 'align-items:baseline; gap:.6rem; flex-wrap:wrap' },
        el('h2', { style: 'margin:.2rem 0' }, T('📝 Inscrições', '📝 Registrations')),
        el('span', { class: 'pill ' + (DATA.enabled ? 'ok' : '') },
          DATA.enabled ? T('ligada · ', 'on · ') + STATE() : T('desligada', 'off')),
        // no aquecimento a porta fica aberta: o roster só é exigido quando a prova entra no ar
        DATA.enabled && DATA.gate_active === false
          ? el('span', { class: 'pill', title: T('a porta só fecha quando a prova oficial entrar no ar (promoção da rodada)',
                                                 'the door only closes when the official round goes live (round promotion)') },
              T('🔥 aquecimento: entrada livre', '🔥 warm-up: open door'))
          : '',
        el('div', { class: 'spacer' }),
        el('button', { class: 'btn ghost', onclick: () => act({ action: DATA.enabled ? 'disable' : 'enable' },
          DATA.enabled ? T('Inscrição desligada.', 'Registration off.') : T('Inscrição ligada.', 'Registration on.')) },
          DATA.enabled ? T('Desligar', 'Turn off') : T('Ligar inscrição', 'Turn on')),
        DATA.enabled && (t.invites || 0) > 0
          ? el('button', { class: 'btn ghost',
              title: T('o mojinho manda uma DM a cada convidado que ainda não respondeu',
                       'mojinho sends a DM to every invitee who has not answered yet'),
              onclick: () => confirm(T('Mandar lembrete para os ' + t.invites + ' convites pendentes?',
                                       'Send a reminder to the ' + t.invites + ' pending invites?'))
                && act({ action: 'invite-remind-all' }, (d) => {
                  const r = d.remind_result || {}; const k = (r.skipped || []).length;
                  return T('Lembrete a caminho para ' + (r.sent || 0) + '.' + (k ? ' ' + k + ' sem Telegram vinculado.' : ''),
                           'Reminder on its way to ' + (r.sent || 0) + '.' + (k ? ' ' + k + ' without a linked Telegram.' : ''));
                }) }, T('🔔 Lembrar todos', '🔔 Remind all'))
          : '',
        el('button', { class: 'btn ghost', onclick: () => act({ action: 'materialize' }, T('Store reescrito a partir do roster.', 'Store rewritten from the roster.')) },
          T('Re-materializar', 'Re-materialize'))),
      el('div', { id: 'rgMsg', class: 'small' }));

    if (!DATA.enabled) {
      panel.append(el('div', { class: 'notice', style: 'margin:.6rem 0' },
        T('Sem inscrição: qualquer conta da fonte de usuários entra no contest, a qualquer momento. Ligue para exigir inscrição prévia (e liberar times).',
          'No registration: any account from the user source can enter the contest at any time. Turn it on to require prior registration (and to allow teams).')));
      return;
    }
    panel.append(
      el('p', { class: 'small muted' },
        T('Inscritos: ', 'Registered: ') + (t.people || 0) + T(' pessoas · ', ' people · ') + (t.teams || 0)
        + T(' times · ', ' teams · ') + (t.individuals || 0) + T(' individuais · ', ' individuals · ')
        + (t.invites || 0) + T(' convites pendentes', ' pending invites')
        + ((t.invites_no_tg || 0) > 0
            ? T(' (' + t.invites_no_tg + ' sem Telegram vinculado — nenhum lembrete os alcança)',
                ' (' + t.invites_no_tg + ' without a linked Telegram — no reminder reaches them)')
            : '')
        + T('. A pessoa se inscreve em ', '. People register at ')
        + '/contests/inscricao/?c=' + CONTEST),
      windowBox(),
      el('h3', {}, T('Times', 'Teams')), teamsTable(),
      el('h3', {}, T('Individuais', 'Individuals')), peopleTable(),
      addBox());
  }

  function addBox() {
    const who = el('input', { placeholder: T('login', 'username'), style: 'width:11rem' });
    const tname = el('input', { placeholder: T('nome do time', 'team name'), style: 'width:12rem' });
    const tmem = el('input', { placeholder: T('logins separados por vírgula (o 1º é o capitão)', 'comma-separated usernames (1st is the captain)'), style: 'min-width:20rem' });
    return el('div', { class: 'section' },
      el('h3', {}, T('Inscrever à mão', 'Register by hand')),
      el('div', { class: 'row', style: 'gap:.5rem; flex-wrap:wrap; align-items:flex-end' },
        field(T('individual', 'individual'), who),
        el('button', { class: 'btn ghost', onclick: () => act({ action: 'add', login: who.value.trim() }, T('Inscrito.', 'Registered.')) },
          T('Inscrever', 'Register'))),
      el('div', { class: 'row', style: 'gap:.5rem; flex-wrap:wrap; align-items:flex-end; margin-top:.4rem' },
        field(T('time', 'team'), tname), field(T('membros', 'members'), tmem),
        el('button', { class: 'btn ghost', onclick: () => act({
          action: 'team-add', name: tname.value.trim(),
          members: tmem.value.split(',').map((s) => s.trim()).filter(Boolean),
        }, T('Time criado.', 'Team created.')) }, T('Criar time', 'Create team'))),
      el('div', { class: 'row', style: 'margin-top:.6rem' },
        el('button', { class: 'btn ghost', onclick: () => {
          const rows = [[T('tipo', 'kind'), 'login', T('nome', 'name'), T('membros', 'members'), T('coorte', 'cohort'), T('univ', 'univ'), 'IA', T('bandeira', 'flag'), T('foto', 'photo')]];
          (DATA.teams || []).forEach((x) => rows.push(['time', x.login, x.name, (x.members || []).join(' '), x.cohort || '', x.univ || '', x.ai === true ? 'sim' : x.ai === false ? 'nao' : '', x.flag || '', x.has_photo ? 'sim' : '']));
          (DATA.individuals || []).forEach((x) => rows.push(['individual', x.login, '', '', x.cohort || '', x.univ || '', x.ai === true ? 'sim' : x.ai === false ? 'nao' : '', x.flag || '', '']));
          downloadText(`inscricoes-${CONTEST}.csv`, toCsv(rows));
        } }, T('⬇ CSV dos inscritos', '⬇ CSV of registrations'))));
  }

  async function load() {
    try { DATA = await apiGet('/contest/admin/registrations?contest=' + enc(CONTEST), G); render(); }
    catch (e) {
      panel.innerHTML = '';
      panel.append(el('div', { class: 'error-box' }, e.message || T('falha ao carregar', 'failed to load')));
    }
  }
  return { panel, load };
}
