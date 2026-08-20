// shared/contest-config/settings-editor.js — editor das CONFIGURAÇÕES do contest (toggles do
// /contest/admin/settings + linguagens + gate de UA + placar completo), compartilhado entre a
// aba Configurações do admin e o passo "Opções" do wizard de criação (paridade real: é o MESMO
// editor). mode:'admin' inclui nome/início/fim; mode:'create' os omite (ficam no passo Dados)
// e acrescenta a PRIORIDADE de julgamento ('super' só aparece p/ admin do treino).
// Sem botão de salvar próprio — quem monta decide o que fazer com getValue().
import { el } from '/shared/ui.js';
import { T } from '/shared/i18n.js';
import { makeLangPicker } from './lang-picker.js';
import { makeJudgePicker } from './judge-picker.js';
import { toLocalDT, dtToEpoch } from './util.js';

const field = (l, inp) => el('div', { class: 'field' }, el('label', {}, l), inp);
const chk = (l, c) => el('div', { class: 'field' }, el('label', { style: 'font-weight:400' }, c, ' ' + l));
const mkBool = (v) => { const c = el('input', { type: 'checkbox' }); c.checked = !!v; return c; };
const PRIORITY_LABEL = () => ({
  'lista-publica': T('Lista pública (padrão)', 'Public list (default)'), 'lista-privada': T('Lista privada', 'Private list'),
  prova: T('Prova (julga antes das listas)', 'Contest (judged before lists)'), super: T('Super (admin; fura toda fila)', 'Super (admin; jumps the whole queue)'),
});

const PENALTY_OPTS = [
  ['wa', 'Wrong Answer'], ['tle', 'Time Limit Exceeded'], ['mle', 'Memory Limit Exceeded'],
  ['rte', 'Runtime Error'], ['ce', 'Compilation Error'],
];
const PENALTY_DEFAULT = ['wa', 'tle', 'mle', 'rte'];

// contestMode: modo do placar ('icpc'|'obi'|…) — a seção de penalidade só existe no icpc.
// O wizard permite voltar e trocar o modo: use setContestMode() no remount.
// apiCtx: contexto {contest, auth} p/ o judge-picker buscar o registro de juízes.
export function makeSettingsEditor({ value = {}, mode = 'admin', isAdmin = false, contestMode = '', apiCtx = null } = {}) {
  const s = value || {};
  const isCreate = mode === 'create';
  const name = el('input', { value: s.name || '' });
  const start = el('input', { type: 'datetime-local', value: s.start ? toLocalDT(s.start) : '' });
  const end = el('input', { type: 'datetime-local', value: s.end ? toLocalDT(s.end) : '' });
  const loginStart = el('input', { type: 'datetime-local', value: s.login_start ? toLocalDT(s.login_start) : '' });
  const freeze = el('input', { type: 'datetime-local', value: s.freeze ? toLocalDT(s.freeze) : '' });
  const locale = el('select', {}, el('option', { value: 'pt' }, 'Português'), el('option', { value: 'en' }, 'English'));
  locale.value = s.locale || 'pt';
  const prios = ['lista-publica', 'lista-privada', 'prova', ...(isAdmin ? ['super'] : [])];
  const PL = PRIORITY_LABEL();
  const priority = el('select', {}, ...prios.map((p) => el('option', { value: p }, PL[p] || p)));
  priority.value = prios.includes(s.priority) ? s.priority : 'lista-publica';
  const loginEnabled = mkBool(s.login_enabled !== false), showCode = mkBool(s.show_code ?? s.showcode),
    showLog = mkBool(s.show_log !== false), showEditor = mkBool(s.show_editor !== false),
    allowLate = mkBool(s.allow_late), scoreAnon = mkBool(s.score_anon),
    showTL = mkBool(s.show_tl !== false), allowBackup = mkBool(s.allow_backup !== false),
    allowPrint = mkBool(s.allow_print !== false), manualVerdict = mkBool(s.manual_verdict === true),
    secret = mkBool(s.secret === true), balloonsFreeze = mkBool(s.balloons_during_freeze === true);
  const blnStyle = el('select', {},
    el('option', { value: 'icon' }, T('Neutro + bolinha da cor (padrão)', 'Neutral + colour dot (default)')),
    el('option', { value: 'fill' }, T('Célula pintada com a cor do balão', 'Cell filled with the balloon colour')));
  blnStyle.value = s.balloon_style === 'fill' ? 'fill' : 'icon';
  const ua = el('input', { value: s.login_ua_substring || '', placeholder: T('substring do UA (vazio = sem gate)', 'UA substring (empty = no gate)') });
  const penMin = el('input', { type: 'number', min: '0', step: '1', style: 'max-width:100px',
    value: String(Number.isInteger(s.penalty_minutes) ? s.penalty_minutes : 20) });
  // quórum da correção manual: quantos juízes validam cada veredicto (1..5; default 2)
  const revJudges = el('input', { type: 'number', min: '1', max: '5', step: '1', style: 'max-width:80px',
    value: String(Number.isInteger(s.review_judges) ? s.review_judges : 2) });
  const pvSel = new Set(Array.isArray(s.penalty_verdicts) ? s.penalty_verdicts : PENALTY_DEFAULT);
  const penChecks = PENALTY_OPTS.map(([code, label]) => ({ code, box: mkBool(pvSel.has(code)), label }));
  const langs = makeLangPicker(s.languages || []);
  const judges = makeJudgePicker(s.judges || [], apiCtx || {});
  const fullUsers = el('input', { value: (s.score_full_users || []).join(' '), placeholder: T('logins (espaço) — além de .admin/.judge/.cjudge', 'logins (space) — besides .admin/.judge/.cjudge'), style: 'width:100%' });
  // FUSO da prova: governa as horas que o SERVIDOR escreve para gente (DM do mojinho, checklist
  // pré-prova, caderno, relatório). Os campos de data desta tela seguem no relógio do navegador.
  const TZS = ['America/Sao_Paulo', 'America/Manaus', 'America/Belem', 'America/Fortaleza',
    'America/Cuiaba', 'America/Rio_Branco', 'America/Noronha', 'America/Argentina/Buenos_Aires',
    'America/Bogota', 'Europe/Lisbon', 'UTC'];
  const tzList = el('datalist', { id: 'tzlist' }, ...TZS.map((z) => el('option', { value: z })));
  const tz = el('input', { value: s.tz || '', list: 'tzlist', placeholder: 'America/Sao_Paulo', style: 'width:16rem' });

  let cmode = contestMode;
  const penaltySec = el('div', {},
    el('h3', { style: 'margin:1rem 0 .3rem' }, T('⏱ Penalidade (placar ICPC)', '⏱ Penalty (ICPC scoreboard)')),
    field(T('Minutos somados por tentativa não aceita antes do Accepted', 'Minutes added per non-accepted attempt before the Accepted'), penMin),
    el('p', { class: 'muted small' }, T('Verdicts que contam penalidade (Judge Error e submissões pendentes nunca contam):', 'Verdicts that count as penalty (Judge Error and pending submissions never count):')),
    ...penChecks.map((p) => chk(p.label, p.box)));
  const syncPen = () => { penaltySec.style.display = cmode === 'icpc' ? '' : 'none'; };
  syncPen();

  // Em modo icpc o log é OCULTO por padrão (showlog_effective no servidor): o report de
  // julgamento expõe a entrada e o diff de TODOS os casos de teste — religar vaza a prova.
  const showLogHint = el('p', { class: 'muted small', style: 'display:none;margin:.1rem 0 .4rem;color:#b45309' },
    T('⚠️ Prova ICPC: o log de julgamento fica oculto por padrão — o report expõe a entrada e o ', '⚠️ ICPC contest: the judging log is hidden by default — the report exposes the input and the '),
    T('diff de TODOS os casos de teste. Marcar esta opção entrega os testes ao competidor.', 'diff of ALL test cases. Checking this option hands the tests to the competitor.'));
  let showLogTouched = false;
  const syncShowLog = () => {
    if (!showLogTouched && isCreate && cmode === 'icpc') showLog.checked = false;
    showLogHint.style.display = cmode === 'icpc' ? '' : 'none';
  };
  showLog.addEventListener('change', () => { showLogTouched = true; syncShowLog(); });
  syncShowLog();

  const box = el('div', {});
  if (!isCreate) {
    box.append(field(T('Nome', 'Name'), name),
      el('div', { class: 'grid2' }, field(T('Início', 'Start'), start), field(T('Fim', 'End'), end)));
  }
  box.append(
    el('div', { class: 'grid2' }, field(T('Abertura do login (tela de espera)', 'Login opening (waiting screen)'), loginStart), field(T('Freeze do placar', 'Scoreboard freeze'), freeze)),
    isCreate ? el('div', { class: 'grid2' }, field(T('Idioma', 'Language'), locale), field(T('Prioridade no julgamento', 'Judging priority'), priority)) : field(T('Idioma', 'Language'), locale),
    chk(T('Login habilitado', 'Login enabled'), loginEnabled),
    chk(T('Permitir auto-cadastro de novos usuários (late users)', 'Allow self-registration of new users (late users)'), allowLate),
    chk(T('Mostrar o código das submissões (a todos)', "Show submissions' code (to everyone)"), showCode),
    chk(T('Usuário pode ver o log de julgamento', 'User can see the judging log'), showLog),
    showLogHint,
    chk(T('Editor de código no browser disponível', 'In-browser code editor available'), showEditor),
    chk(T('Mostrar o tempo-limite dos problemas aos usuários', "Show problems' time limit to users"), showTL),
    chk(T('Permitir backup de arquivos pelos usuários', 'Allow file backup by users'), allowBackup),
    chk(T('Permitir pedidos de impressão pelos usuários (.staff)', 'Allow print requests by users (.staff)'), allowPrint),
    chk(T('Veredicto manual (juízes validam cada veredicto; o daemon o segura até o acordo)', 'Manual verdict (judges validate each verdict; the daemon holds it until agreement)'), manualVerdict),
    field(T('Nº de juízes que validam cada veredicto (1–5; 1 = revisão simples)', 'Judges required to validate each verdict (1–5; 1 = single review)'), revJudges),
    chk(T('Placar anônimo (esconde desempenho individual)', 'Anonymous scoreboard (hides individual performance)'), scoreAnon),
    chk(T('🕵️ SUPER SECRETO — fora da home/arquivo/status; placar e visual exigem login (a tela de login continua funcionando p/ quem tem o link)', '🕵️ SUPER SECRET — off the home/archive/status; scoreboard and view require login (the login screen still works for whoever has the link)'), secret),
    field(T('Gate de login por substring de UA (só não-privilegiados)', 'Login gate by UA substring (only non-privileged)'), ua),
    penaltySec,
    el('h3', { style: 'margin:1rem 0 .3rem' }, T('💻 Linguagens permitidas no contest', '💻 Languages allowed in the contest')),
    el('p', { class: 'muted small' }, T('Marque as permitidas. Nenhuma marcada = todas. (Pode ser refinado por problema na aba Problemas.)', 'Check the allowed ones. None checked = all. (Can be refined per problem in the Problems tab.)')),
    langs.el,
    el('h3', { style: 'margin:1rem 0 .3rem' }, T('🖥️ Máquinas de juiz (pool)', '🖥️ Judge machines (pool)')),
    el('p', { class: 'muted small' },
      T('Nenhuma marcada = qualquer juiz online julga. Marcar FIXA a correção nessas máquinas — ', 'None checked = any online judge judges. Checking PINS judging to those machines — '),
      T('consistência de hardware: o tempo-limite exibido passa a ser só delas e, se todas caírem, ', 'hardware consistency: the displayed time limit becomes theirs only and, if all go down, '),
      T('as submissões ESPERAM na fila (o pré-prova e a Situação avisam). (Pode ser refinado por problema na aba Problemas.)', 'submissions WAIT in the queue (the pre-contest check and the Situation warn). (Can be refined per problem in the Problems tab.)')),
    judges.el,
    el('h3', { style: 'margin:1rem 0 .3rem' }, T('👁️ Placar completo (sem freeze)', '👁️ Full scoreboard (no freeze)')),
    el('p', { class: 'muted small' }, T('Quem vê o placar real mesmo durante o freeze: .admin, .judge e .cjudge (juiz-chefe) sempre; some outros logins aqui.', 'Who sees the real scoreboard even during freeze: .admin, .judge and .cjudge (chief judge) always; add other logins here.')),
    fullUsers,
    // ⚠ campo NOVO entra no FIM: o settings-tab.js monta as seções por ÍNDICE dos filhos —
    // inserir no meio deslocaria todos os seguintes p/ a seção errada.
    el('h3', { style: 'margin:1rem 0 .3rem' }, T('🌎 Fuso horário da prova', '🌎 Contest timezone')),
    el('p', { class: 'muted small' },
      T('Em que relógio o MOJ escreve as horas desta prova para as pessoas: mensagem do mojinho, checklist pré-prova, caderno e relatório. Vazio = padrão da instalação (America/Sao_Paulo). Os campos de data desta tela continuam no relógio do SEU navegador.',
        'Which clock the MOJ uses when writing this contest’s times for people: mojinho message, pre-contest checklist, problem set and report. Empty = installation default (America/Sao_Paulo). The date fields on this screen still follow YOUR browser’s clock.')),
    el('div', {}, tzList, field(T('Fuso (IANA)', 'Timezone (IANA)'), tz)),
    // idem: no FIM (índice novo entra no GROUPS do settings-tab.js, seção do freeze)
    el('h3', { style: 'margin:1rem 0 .3rem' }, T('🎈 Balões durante o freeze', '🎈 Balloons during the freeze')),
    el('p', { class: 'muted small' },
      T('Por padrão o MOJ NÃO gera tarefa de entrega para acerto feito com o placar congelado: o balão andando pela sala conta ao público exatamente o que o freeze esconde. Esses balões não são entregues depois — simplesmente não existem. Marque para entregar normalmente durante o freeze (o clássico do ICPC); marcar agora também libera os que já ficaram retidos. Pedido de impressão não é afetado.',
        'By default the MOJ does NOT create a delivery task for a solve made while the scoreboard is frozen: a balloon crossing the room tells the audience exactly what the freeze hides. Those balloons are not delivered later — they simply never exist. Check to deliver normally during the freeze (the ICPC classic); checking it now also releases the ones already held back. Print requests are unaffected.')),
    chk(T('Entregar balão durante o freeze', 'Deliver balloons during the freeze'), balloonsFreeze),
    el('h3', { style: 'margin:1rem 0 .3rem' }, T('🎨 Célula "resolveu" no placar', '🎨 "Solved" cell on the scoreboard')),
    el('p', { class: 'muted small' },
      T('No padrão, a célula de quem resolveu é sempre igual (verde) e a cor do balão vai numa bolinha ao lado — assim "resolveu" não depende de enxergar a cor, e o balão BRANCO deixa de sumir no fundo do placar. A outra opção é o clássico: a célula inteira pintada com a cor do balão (aí as cores claras ganham contorno para não sumir). Vale para o placar, a cerimônia de revelação e o relatório.',
        'By default the solved cell always looks the same (green) and the balloon colour goes in a small dot beside it — so "solved" does not depend on seeing the colour, and the WHITE balloon stops vanishing into the scoreboard background. The other option is the classic: the whole cell painted with the balloon colour (light colours then get an outline so they do not vanish). Applies to the scoreboard, the reveal ceremony and the report.')),
    field(T('Como pintar', 'How to paint'), blnStyle));

  function getValue() {
    return {
      ...(isCreate ? { priority: priority.value } : {
        name: name.value.trim() || undefined,
        ...(start.value ? { start: dtToEpoch(start.value) } : {}),
        ...(end.value ? { end: dtToEpoch(end.value) } : {}),
      }),
      ...(loginStart.value ? { login_start: dtToEpoch(loginStart.value) } : {}),
      // freeze VAZIO = sem congelamento -> 0 (e não "não mexe"): apagar o campo tem de
      // DESCONGELAR. Omitir a chave fazia o salvar responder ✓ sem tirar o freeze.
      freeze: freeze.value ? dtToEpoch(freeze.value) : 0,
      locale: locale.value, tz: tz.value.trim(), login_enabled: loginEnabled.checked,
      show_code: showCode.checked, show_log: showLog.checked, show_editor: showEditor.checked,
      allow_late: allowLate.checked, score_anon: scoreAnon.checked, show_tl: showTL.checked,
      allow_backup: allowBackup.checked, allow_print: allowPrint.checked,
      manual_verdict: manualVerdict.checked, secret: secret.checked, login_ua_substring: ua.value,
      balloons_during_freeze: balloonsFreeze.checked, balloon_style: blnStyle.value,
      review_judges: Math.min(5, Math.max(1, parseInt(revJudges.value, 10) || 2)),
      languages: langs.get(),
      judges: judges.get(),
      score_full_users: fullUsers.value.trim() ? fullUsers.value.trim().split(/\s+/) : [],
      ...(cmode === 'icpc' ? {
        penalty_minutes: penMin.value.trim() === '' ? 20 : Math.max(0, parseInt(penMin.value, 10) || 0),
        penalty_verdicts: penChecks.filter((p) => p.box.checked).map((p) => p.code),
      } : {}),
    };
  }
  return { el: box, getValue, setContestMode: (m) => { cmode = m; syncPen(); syncShowLog(); } };
}
