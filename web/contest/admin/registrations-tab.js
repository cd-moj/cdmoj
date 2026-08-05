// contest/admin/registrations-tab.js — painel "📝 Inscrições": o roster do contest (quem
// pode entrar) e a JANELA (quando dá p/ se inscrever). Espelha GET/POST
// /contest/admin/registrations (enable|disable|window|add|rm|team-add|team-rm|materialize).
//
// Como funciona: com o registro LIGADO, só quem está no roster entra no contest (a API corta
// no /auth/login). Quem se inscreve são as contas do Treino Livre, pela página
// /contests/inscricao/ — aqui é a visão do organizador e o conserto à mão.
import { el, fmtDate } from '/shared/ui.js';
import { apiGet, apiPost } from '/shared/api.js';
import { T } from '/shared/i18n.js';
import { field, toCsv, downloadText } from '/shared/admin-ui.js';
import { flagEl } from '/shared/flags.js';

const enc = encodeURIComponent;
const dt = (e) => (e ? new Date(e * 1000).toISOString().slice(0, 16) : '');
const toEpoch = (s) => (s ? Math.floor(new Date(s).getTime() / 1000) : 0);

export function makeRegistrationsTab(CONTEST) {
  const G = { contest: CONTEST, auth: true };
  const panel = el('div', { class: 'section' });
  let DATA = null;

  const say = (m, bad) => { const d = panel.querySelector('#rgMsg'); if (!d) return; d.className = bad ? 'small error-box' : 'small v-ok'; d.textContent = m; };
  const post = (b) => apiPost('/contest/admin/registrations?contest=' + enc(CONTEST), b, G);
  async function act(body, okMsg) {
    try { DATA = await post(body); render(); say(okMsg); }
    catch (e) { say(e.message || T('falha', 'failed'), true); }
  }

  const STATE = () => ({
    open:   T('aberta', 'open'), late: T('atrasada (só fora de disputa)', 'late (out of competition only)'),
    soon:   T('ainda não abriu', 'not open yet'), closed: T('encerrada', 'closed'),
  }[(DATA.window || {}).state] || '?');

  function windowBox() {
    const w = DATA.window || {};
    const op = el('input', { type: 'datetime-local', value: dt(w.opens_at) });
    const cl = el('input', { type: 'datetime-local', value: dt(w.closes_at) });
    const lm = el('input', { type: 'number', min: '0', style: 'width:6rem',
      value: String(Math.max(0, Math.round(((w.late_until || 0) - (w.closes_at || 0)) / 60))) });
    const mx = el('input', { type: 'number', min: '1', max: '9', style: 'width:5rem', value: String(DATA.team_max || 3) });
    const tm = el('input', { type: 'checkbox' }); tm.checked = DATA.teams_allowed !== false;
    // a data herdada é a da PROVA OFICIAL (o aquecimento pode ficar dias no ar) — ver
    // reg_official_window em lib/registration.sh
    const anc = w.official_start ? fmtDate(w.official_start) : T('(prova não marcada)', '(contest not scheduled)');
    const herda = el('p', { class: 'small' },
      T('Deixe “fecha” vazio para herdar o início da prova: ', 'Leave “closes” empty to inherit the contest start: '),
      el('b', {}, anc),
      w.official_round ? el('span', { class: 'muted' }, T(' · rodada ', ' · round ') + w.official_round) : '');
    const form = el('div', { class: 'row', style: 'gap:.8rem; flex-wrap:wrap; align-items:flex-end' },
      field(T('abre', 'opens'), op), field(T('fecha', 'closes'), cl),
      field(T('atraso (min)', 'late (min)'), lm), field(T('tamanho do time', 'team size'), mx),
      el('div', { class: 'field' }, el('label', { style: 'font-weight:400' }, tm, ' ' + T('aceita times', 'teams allowed'))),
      el('button', { class: 'btn', onclick: () => act({
        action: 'window', open: toEpoch(op.value) || undefined, close: toEpoch(cl.value) || undefined,
        late_minutes: Number(lm.value) || 0, team_max: Number(mx.value) || 3, teams: tm.checked,
      }, T('Janela salva.', 'Window saved.')) }, T('Salvar janela', 'Save window')));
    return el('div', { class: 'section' },
      el('h3', {}, T('Janela de inscrição', 'Registration window')),
      el('p', { class: 'small muted' },
        T('Fecha por padrão no início da PROVA OFICIAL — não no da rodada corrente: o aquecimento pode ficar dias no ar. Os minutos de atraso deixam entrar depois do início da prova, mas na coorte “atrasado” (aparece no placar sem ocupar posição) — é a extra registration do Codeforces.',
          'Closes at the OFFICIAL CONTEST start by default — not the current round: the warm-up may run for days. The late minutes let people join after the contest starts, but in the “late” cohort (they appear on the scoreboard without taking a position) — the Codeforces extra registration.')),
      herda, form);
  }

  function teamsTable() {
    const rows = (DATA.teams || []).map((t) => el('tr', {},
      el('td', {}, el('b', {}, (t.univ ? '[' + t.univ + '] ' : '') + t.name),
        el('div', { class: 'small muted' }, flagEl(t.flag, { height: 14 }) || '',
          (t.flag ? ' ' + t.flag.toUpperCase() + ' · ' : '') + t.login
          + (t.ai === true ? ' · 🤖 IA' : t.ai === false ? ' · sem IA' : '')
          + (t.has_photo ? ' · 📷' : ''))),
      el('td', {}, (t.members || []).join(', ')),
      el('td', { class: 'small muted' }, (t.invited || []).join(', ')),
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
        + (t.invites || 0) + T(' convites pendentes. A pessoa se inscreve em ', ' pending invites. People register at ')
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
