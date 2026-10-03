// shared/contest-config/settings-editor.js — editor das CONFIGURAÇÕES do contest (toggles do
// /contest/admin/settings + linguagens + gate de UA + placar completo), compartilhado entre a
// aba Configurações do admin e o passo "Opções" do wizard de criação (paridade real: é o MESMO
// editor). mode:'admin' inclui nome/início/fim; mode:'create' os omite (ficam no passo Dados)
// e acrescenta a PRIORIDADE de julgamento ('super' só aparece p/ o SUPER-ADMIN do treino, `canSuper`). No modo
// admin a prioridade é um bloco no FIM (editável desde 01/10/2026; Super nunca é oferecida aqui e, se o contest já
// está em Super, o campo vem travado — quem muda é o super-admin, no Painel do treino › Contests).
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
  'lista-publica': T('Lista pública (padrão)', 'Public list (default)', 'Lista pública (por defecto)'), 'lista-privada': T('Lista privada', 'Private list', 'Lista privada'),
  prova: T('Prova (julga antes das listas)', 'Contest (judged before lists)', 'Competencia (se evalúa antes que las listas)'), super: T('Super (super-admin do treino; fura toda fila)', 'Super (training super-admin; jumps the whole queue)', 'Super (superadministrador del entrenamiento; salta toda la cola)'),
});

// tzSuggestions(atual) — fusos p/ o <datalist>: o do navegador, o salvo, e todos os que o navegador conhece
// (Intl.supportedValuesOf; navegador antigo = uma lista curta das Américas + Europa). Exportada p/ o teste.
const TZ_FALLBACK = ['America/Sao_Paulo', 'America/Manaus', 'America/Belem', 'America/Fortaleza', 'America/Cuiaba',
  'America/Rio_Branco', 'America/Noronha', 'America/Santiago', 'America/Punta_Arenas', 'America/Argentina/Buenos_Aires',
  'America/Montevideo', 'America/Asuncion', 'America/La_Paz', 'America/Lima', 'America/Bogota', 'America/Guayaquil',
  'America/Caracas', 'America/Panama', 'America/Costa_Rica', 'America/El_Salvador', 'America/Guatemala',
  'America/Tegucigalpa', 'America/Managua', 'America/Mexico_City', 'America/Havana', 'America/Santo_Domingo',
  'America/Puerto_Rico', 'Europe/Lisbon', 'Europe/Madrid', 'UTC'];
export function tzSuggestions(current) {
  let mine = '', all = [];
  try { mine = Intl.DateTimeFormat().resolvedOptions().timeZone || ''; } catch { /* */ }
  try { all = typeof Intl.supportedValuesOf === 'function' ? Intl.supportedValuesOf('timeZone') : []; } catch { all = []; }
  if (!all.length) all = TZ_FALLBACK;
  return [...new Set([mine, current || '', ...all].filter(Boolean))];
}

const PENALTY_OPTS = [
  ['wa', 'Wrong Answer'], ['tle', 'Time Limit Exceeded'], ['mle', 'Memory Limit Exceeded'],
  ['rte', 'Runtime Error'], ['ce', 'Compilation Error'],
];
const PENALTY_DEFAULT = ['wa', 'tle', 'mle', 'rte'];

// contestMode: modo do placar ('icpc'|'obi'|…) — a seção de penalidade só existe no icpc.
// O wizard permite voltar e trocar o modo: use setContestMode() no remount.
// apiCtx: contexto {contest, auth} p/ o judge-picker buscar o registro de juízes.
export function makeSettingsEditor({ value = {}, mode = 'admin', canSuper = false, contestMode = '', apiCtx = null } = {}) {
  const s = value || {};
  const isCreate = mode === 'create';
  const name = el('input', { value: s.name || '' });
  const start = el('input', { type: 'datetime-local', value: s.start ? toLocalDT(s.start) : '' });
  const end = el('input', { type: 'datetime-local', value: s.end ? toLocalDT(s.end) : '' });
  const loginStart = el('input', { type: 'datetime-local', value: s.login_start ? toLocalDT(s.login_start) : '' });
  const freeze = el('input', { type: 'datetime-local', value: s.freeze ? toLocalDT(s.freeze) : '' });
  const locale = el('select', {}, el('option', { value: 'pt' }, 'Português'), el('option', { value: 'en' }, 'English'), el('option', { value: 'es' }, 'Español'));
  locale.value = s.locale || 'pt';
  const prios = ['lista-publica', 'lista-privada', 'prova', ...(canSuper ? ['super'] : [])];
  const PL = PRIORITY_LABEL();
  const priority = el('select', {}, ...prios.map((p) => el('option', { value: p }, PL[p] || p)));
  priority.value = prios.includes(s.priority) ? s.priority : 'lista-publica';
  const loginEnabled = mkBool(s.login_enabled !== false),
    showLog = mkBool(s.show_log !== false), showEditor = mkBool(s.show_editor !== false),
    scoreAnon = mkBool(s.score_anon),
    showTL = mkBool(s.show_tl !== false), allowBackup = mkBool(s.allow_backup !== false),
    allowPrint = mkBool(s.allow_print !== false), manualVerdict = mkBool(s.manual_verdict === true),
    secret = mkBool(s.secret === true), balloonsFreeze = mkBool(s.balloons_during_freeze === true);
  const blnStyle = el('select', {},
    el('option', { value: 'icon' }, T('Neutro + bolinha da cor (padrão)', 'Neutral + colour dot (default)', 'Neutro + punto de color (por defecto)')),
    el('option', { value: 'fill' }, T('Célula pintada com a cor do balão', 'Cell filled with the balloon colour', 'Celda pintada con el color del globo')));
  blnStyle.value = s.balloon_style === 'fill' ? 'fill' : 'icon';
  const ua = el('input', { value: s.login_ua_substring || '', placeholder: T('substring do UA (vazio = sem gate)', 'UA substring (empty = no gate)', 'substring del UA (vacío = sin filtro)') });
  // data-k: o settings-tab esconde este campo sem o módulo `maquinas` (por chave, não por índice)
  const uaField = field(T('Gate de login por substring de UA (só não-privilegiados)', 'Login gate by UA substring (only non-privileged)', 'Filtro de inicio de sesión por substring de UA (solo no privilegiados)'), ua);
  uaField.dataset.k = 'login_ua_substring';
  const penMin = el('input', { type: 'number', min: '0', step: '1', style: 'max-width:100px',
    value: String(Number.isInteger(s.penalty_minutes) ? s.penalty_minutes : 20) });
  // quórum da correção manual: quantos juízes validam cada veredicto (1..5; default 2)
  const revJudges = el('input', { type: 'number', min: '1', max: '5', step: '1', style: 'max-width:80px',
    value: String(Number.isInteger(s.review_judges) ? s.review_judges : 2) });
  const pvSel = new Set(Array.isArray(s.penalty_verdicts) ? s.penalty_verdicts : PENALTY_DEFAULT);
  const penChecks = PENALTY_OPTS.map(([code, label]) => ({ code, box: mkBool(pvSel.has(code)), label }));
  const langs = makeLangPicker(s.languages || []);
  const judges = makeJudgePicker(s.judges || [], apiCtx || {});
  const fullUsers = el('input', { value: (s.score_full_users || []).join(' '), placeholder: T('logins (espaço) — além de .admin/.judge/.cjudge', 'logins (space) — besides .admin/.judge/.cjudge', 'usuarios (espacio) — además de .admin/.judge/.cjudge'), style: 'width:100%' });
  // FUSO da prova: governa as horas que o SERVIDOR escreve para gente (DM do mojinho, checklist
  // pré-prova, caderno, relatório). Os campos de data desta tela seguem no relógio do navegador.
  // Sugestões = TODOS os fusos que o navegador conhece, com o do PRÓPRIO navegador em 1º (um admin no Chile vê
  // America/Santiago no topo). A lista antiga tinha 11 fusos, quase todos do Brasil, e o organizador do Chile
  // achou que o MOJ não tinha o dele (03/10/2026). O campo aceita qualquer nome digitado; o servidor valida e
  // troca nome antigo pelo atual (tz_canon).
  const tzList = el('datalist', { id: 'tzlist' }, ...tzSuggestions(s.tz).map((z) => el('option', { value: z })));
  const tz = el('input', { value: s.tz || '', list: 'tzlist', placeholder: 'America/Sao_Paulo', style: 'width:16rem' });

  // PRIORIDADE no modo admin: "não definida" (vale Lista pública) é um estado próprio — escolher QUALQUER uma,
  // inclusive Lista, registra a decisão (a Central avisa prova icpc/obi sem prioridade escolhida). Só vai no
  // getValue() quando MUDA: o salvar das outras opções não regrava nem audita a prioridade.
  const prioLocked = !isCreate && s.priority === 'super';
  const prioInitial = s.priority_set ? (s.priority || '') : '';
  const aPrio = el('select', {},
    ...(prioLocked ? [el('option', { value: 'super' }, PL.super)] : [
      ...(prioInitial ? [] : [el('option', { value: '' }, T('— não definida (vale Lista pública) —', '— not set (Public list applies) —', '— no definida (vale Lista pública) —'))]),
      ...['lista-publica', 'lista-privada', 'prova'].map((p) => el('option', { value: p }, PL[p]))]));
  aPrio.value = prioLocked ? 'super' : prioInitial;
  aPrio.style.maxWidth = '26rem';
  if (prioLocked) { aPrio.disabled = true; aPrio.style.background = '#f1f4f8'; aPrio.style.color = 'var(--muted)'; aPrio.style.cursor = 'not-allowed'; }

  let cmode = contestMode;
  const penaltySec = el('div', {},
    el('h3', { style: 'margin:1rem 0 .3rem' }, T('⏱ Penalidade (placar ICPC)', '⏱ Penalty (ICPC scoreboard)', '⏱ Penalización (marcador ICPC)')),
    field(T('Minutos somados por tentativa não aceita antes do Accepted', 'Minutes added per non-accepted attempt before the Accepted', 'Minutos sumados por cada intento no aceptado antes del Accepted'), penMin),
    el('p', { class: 'muted small' }, T('Verdicts que contam penalidade (Judge Error e submissões pendentes nunca contam):', 'Verdicts that count as penalty (Judge Error and pending submissions never count):', 'Veredictos que cuentan como penalización (Judge Error y los envíos pendientes nunca cuentan):')),
    ...penChecks.map((p) => chk(p.label, p.box)));
  const syncPen = () => { penaltySec.style.display = cmode === 'icpc' ? '' : 'none'; };
  syncPen();

  // Em modo icpc o log é OCULTO por padrão (showlog_effective no servidor): o report de
  // julgamento expõe a entrada e o diff de TODOS os casos de teste — religar vaza a prova.
  const showLogHint = el('p', { class: 'muted small', style: 'display:none;margin:.1rem 0 .4rem;color:#b45309' },
    T('⚠️ Prova ICPC: o log de julgamento fica oculto por padrão — o report expõe a entrada e o ', '⚠️ ICPC contest: the judging log is hidden by default — the report exposes the input and the ', '⚠️ Competencia ICPC: el registro de evaluación queda oculto por defecto — el informe expone la entrada y el '),
    T('diff de TODOS os casos de teste. Marcar esta opção entrega os testes ao competidor.', 'diff of ALL test cases. Checking this option hands the tests to the competitor.', 'diff de TODOS los casos de prueba. Marcar esta opción entrega las pruebas al competidor.'));
  let showLogTouched = false;
  const syncShowLog = () => {
    if (!showLogTouched && isCreate && cmode === 'icpc') showLog.checked = false;
    showLogHint.style.display = cmode === 'icpc' ? '' : 'none';
  };
  showLog.addEventListener('change', () => { showLogTouched = true; syncShowLog(); });
  syncShowLog();

  const box = el('div', {});
  if (!isCreate) {
    box.append(field(T('Nome', 'Name', 'Nombre'), name),
      el('div', { class: 'grid2' }, field(T('Início', 'Start', 'Inicio'), start), field(T('Fim', 'End', 'Fin'), end)));
  }
  box.append(
    el('div', { class: 'grid2' }, field(T('Abertura do login (tela de espera)', 'Login opening (waiting screen)', 'Apertura del login (pantalla de espera)'), loginStart), field(T('Freeze do placar', 'Scoreboard freeze', 'Congelamiento del marcador'), freeze)),
    isCreate ? el('div', { class: 'grid2' }, field(T('Idioma', 'Language', 'Idioma'), locale), field(T('Prioridade no julgamento', 'Judging priority', 'Prioridad en la evaluación'), priority)) : field(T('Idioma', 'Language', 'Idioma'), locale),
    chk(T('Login habilitado', 'Login enabled', 'Inicio de sesión habilitado'), loginEnabled),
    chk(T('Usuário pode ver o log de julgamento', 'User can see the judging log', 'El usuario puede ver el registro de evaluación'), showLog),
    showLogHint,
    chk(T('Editor de código no browser disponível', 'In-browser code editor available', 'Editor de código en el navegador disponible'), showEditor),
    chk(T('Mostrar o tempo-limite dos problemas aos usuários', "Show problems' time limit to users", "Mostrar el tiempo límite de los problemas a los usuarios"), showTL),
    chk(T('Permitir backup de arquivos pelos usuários', 'Allow file backup by users', 'Permitir el backup de archivos por los usuarios'), allowBackup),
    chk(T('Permitir pedidos de impressão pelos usuários (.staff)', 'Allow print requests by users (.staff)', 'Permitir solicitudes de impresión por los usuarios (.staff)'), allowPrint),
    chk(T('Veredicto manual (os juízes validam o que a tabela "O que vai para revisão" marca — painel Juízes; o resto sai automático)', 'Manual verdict (the judges validate what the "What goes to review" table checks — Judges panel; the rest is automatic)', 'Veredicto manual (los jueces validan lo que marca la tabla "Qué va a revisión" — panel Jueces; el resto sale automático)'), manualVerdict),
    field(T('Nº de juízes que validam cada veredicto (1–5; 1 = revisão simples)', 'Judges required to validate each verdict (1–5; 1 = single review)', 'N.º de jueces que validan cada veredicto (1–5; 1 = revisión simple)'), revJudges),
    chk(T('Placar anônimo (esconde desempenho individual)', 'Anonymous scoreboard (hides individual performance)', 'Marcador anónimo (oculta el desempeño individual)'), scoreAnon),
    chk(T('🕵️ SUPER SECRETO — fora da home/arquivo/status; placar e visual exigem login (a tela de login continua funcionando p/ quem tem o link)', '🕵️ SUPER SECRET — off the home/archive/status; scoreboard and view require login (the login screen still works for whoever has the link)', '🕵️ SUPER SECRETO — fuera de inicio/archivo/estado; el marcador y la vista exigen iniciar sesión (la pantalla de inicio de sesión sigue funcionando para quien tenga el enlace)'), secret),
    uaField,
    penaltySec,
    el('h3', { style: 'margin:1rem 0 .3rem' }, T('💻 Linguagens permitidas no contest', '💻 Languages allowed in the contest', '💻 Lenguajes permitidos en la competencia')),
    el('p', { class: 'muted small' }, T('Marque as permitidas. Nenhuma marcada = todas. (Pode ser refinado por problema na aba Problemas.)', 'Check the allowed ones. None checked = all. (Can be refined per problem in the Problems tab.)', 'Marca los permitidos. Ninguno marcado = todos. (Se puede ajustar por problema en la pestaña Problemas.)')),
    langs.el,
    el('h3', { style: 'margin:1rem 0 .3rem' }, T('🖥️ Máquinas de juiz (pool)', '🖥️ Judge machines (pool)', '🖥️ Máquinas de juez (pool)')),
    el('p', { class: 'muted small' },
      T('Nenhuma marcada = qualquer juiz online julga. Marcar FIXA a correção nessas máquinas — ', 'None checked = any online judge judges. Checking PINS judging to those machines — ', 'Ninguna marcada = cualquier juez en línea evalúa. Marcar FIJA la evaluación en esas máquinas — '),
      T('consistência de hardware: o tempo-limite exibido passa a ser só delas e, se todas caírem, ', 'hardware consistency: the displayed time limit becomes theirs only and, if all go down, ', 'consistencia de hardware: el tiempo límite mostrado pasa a ser solo el de ellas y, si todas caen, '),
      T('as submissões ESPERAM na fila (o pré-prova e a Situação avisam). (Pode ser refinado por problema na aba Problemas.)', 'submissions WAIT in the queue (the pre-contest check and the Situation warn). (Can be refined per problem in the Problems tab.)', 'los envíos ESPERAN en la cola (el chequeo previo a la competencia y Situación avisan). (Se puede ajustar por problema en la pestaña Problemas.)')),
    judges.el,
    el('h3', { style: 'margin:1rem 0 .3rem' }, T('👁️ Placar completo (sem freeze)', '👁️ Full scoreboard (no freeze)', '👁️ Marcador completo (sin congelamiento)')),
    el('p', { class: 'muted small' }, T('Quem vê o placar real mesmo durante o freeze: .admin, .judge e .cjudge (juiz-chefe) sempre; some outros logins aqui.', 'Who sees the real scoreboard even during freeze: .admin, .judge and .cjudge (chief judge) always; add other logins here.', 'Quién ve el marcador real incluso durante el congelamiento: .admin, .judge y .cjudge (juez principal) siempre; agrega otros usuarios aquí.')),
    fullUsers,
    // ⚠ campo NOVO entra no FIM: o settings-tab.js monta as seções por ÍNDICE dos filhos —
    // inserir no meio deslocaria todos os seguintes p/ a seção errada.
    el('h3', { style: 'margin:1rem 0 .3rem' }, T('🌎 Fuso horário da prova', '🌎 Contest timezone', '🌎 Zona horaria de la competencia')),
    el('p', { class: 'muted small' },
      T('Em que relógio o MOJ escreve as horas desta prova para as pessoas: mensagem do mojinho, checklist pré-prova, caderno e relatório. Vazio = padrão da instalação (America/Sao_Paulo). Os campos de data desta tela continuam no relógio do SEU navegador. Digite qualquer fuso (ex.: America/Santiago, America/Mexico_City); a lista sugere todos, começando pelo do seu navegador. Prefira o fuso da sua cidade a outro com a mesma hora hoje: o horário de verão muda em datas diferentes.',
        'Which clock the MOJ uses when writing this contest’s times for people: mojinho message, pre-contest checklist, problem set and report. Empty = installation default (America/Sao_Paulo). The date fields on this screen still follow YOUR browser’s clock. Type any timezone (e.g. America/Santiago, America/Mexico_City); the list suggests all of them, starting with your browser’s. Prefer your own city’s timezone to another one with the same time today: daylight saving time changes on different dates.',
        'En qué reloj escribe el MOJ los horarios de esta competencia para las personas: mensaje del mojinho, checklist previo a la competencia, cuadernillo e informe. Vacío = valor por defecto de la instalación (America/Sao_Paulo). Los campos de fecha de esta pantalla siguen el reloj de TU navegador. Escribe cualquier zona horaria (ej.: America/Santiago, America/Mexico_City); la lista sugiere todas, empezando por la de tu navegador. Prefiere la zona de tu ciudad a otra con la misma hora hoy: el horario de verano cambia en fechas distintas.')),
    el('div', {}, tzList, field(T('Fuso (IANA)', 'Timezone (IANA)', 'Zona horaria (IANA)'), tz)),
    // idem: no FIM (índice novo entra no GROUPS do settings-tab.js, seção do freeze)
    el('h3', { style: 'margin:1rem 0 .3rem' }, T('🎈 Balões durante o freeze', '🎈 Balloons during the freeze', '🎈 Globos durante el congelamiento')),
    el('p', { class: 'muted small' },
      T('Por padrão o MOJ NÃO gera tarefa de entrega para acerto feito com o placar congelado: o balão andando pela sala conta ao público exatamente o que o freeze esconde. Esses balões não são entregues depois — simplesmente não existem. Marque para entregar normalmente durante o freeze (o clássico do ICPC); marcar agora também libera os que já ficaram retidos. Pedido de impressão não é afetado.',
        'By default the MOJ does NOT create a delivery task for a solve made while the scoreboard is frozen: a balloon crossing the room tells the audience exactly what the freeze hides. Those balloons are not delivered later — they simply never exist. Check to deliver normally during the freeze (the ICPC classic); checking it now also releases the ones already held back. Print requests are unaffected.',
        'Por defecto el MOJ NO genera una tarea de entrega para un acierto logrado con el marcador congelado: el globo cruzando la sala le cuenta al público exactamente lo que el congelamiento esconde. Esos globos no se entregan después — simplemente no existen. Marca esta opción para entregarlos normalmente durante el congelamiento (el clásico del ICPC); marcarla ahora también libera los que ya quedaron retenidos. Las solicitudes de impresión no se ven afectadas.')),
    chk(T('Entregar balão durante o freeze', 'Deliver balloons during the freeze', 'Entregar globos durante el congelamiento'), balloonsFreeze),
    el('h3', { style: 'margin:1rem 0 .3rem' }, T('🎨 Célula "resolveu" no placar', '🎨 "Solved" cell on the scoreboard', '🎨 Celda de "resuelto" en el marcador')),
    el('p', { class: 'muted small' },
      T('No padrão, a célula de quem resolveu é sempre igual (verde) e a cor do balão vai numa bolinha ao lado — assim "resolveu" não depende de enxergar a cor, e o balão BRANCO deixa de sumir no fundo do placar. A outra opção é o clássico: a célula inteira pintada com a cor do balão (aí as cores claras ganham contorno para não sumir). Vale para o placar, a cerimônia de revelação e o relatório.',
        'By default the solved cell always looks the same (green) and the balloon colour goes in a small dot beside it — so "solved" does not depend on seeing the colour, and the WHITE balloon stops vanishing into the scoreboard background. The other option is the classic: the whole cell painted with the balloon colour (light colours then get an outline so they do not vanish). Applies to the scoreboard, the reveal ceremony and the report.',
        'Por defecto, la celda de quien resolvió siempre se ve igual (verde) y el color del globo va en un puntito al lado — así "resuelto" no depende de distinguir el color, y el globo BLANCO deja de desaparecer en el fondo del marcador. La otra opción es la clásica: toda la celda pintada con el color del globo (ahí los colores claros reciben un contorno para no desaparecer). Aplica al marcador, la ceremonia de revelación y el informe.')),
    field(T('Como pintar', 'How to paint', 'Cómo pintar'), blnStyle));
  // idem: no FIM (índices 35–37 no GROUPS do settings-tab.js, seção Julgamento). Só no modo admin: na criação a
  // prioridade fica ao lado do idioma (acima).
  if (!isCreate) box.append(
    el('h3', { style: 'margin:1rem 0 .3rem' }, T('🚦 Prioridade no julgamento', '🚦 Judging priority', '🚦 Prioridad en la evaluación')),
    el('p', { class: 'muted small' }, prioLocked
      ? T('Este contest está em Super, a prioridade que passa na frente de toda fila. Quem a deu foi o super-admin do treino, e só ele a muda (Painel do treino › Contests).',
        'This contest is on Super, the priority that jumps the whole queue. The training super-admin set it, and only the super-admin can change it (Training panel › Contests).',
        'Esta competencia está en Super, la prioridad que salta toda la cola. La dio el superadministrador del entrenamiento, y solo él la cambia (Panel del entrenamiento › Competencias).')
      : T('Decide a vez desta prova na fila de julgamento e a regra de envios. Lista (pública ou privada): cada time tem no máximo 3 envios esperando veredicto; o próximo é recusado até sair um resultado. Prova: julgada antes das listas e sem teto; a partir do 6º envio esperando veredicto, os seguintes do time vão mais para trás na fila. A prioridade Super só o super-admin do treino dá. Toda mudança fica registrada na Auditoria.',
        'Decides this contest’s turn in the judging queue and the submission rule. List (public or private): each team has at most 3 submissions waiting for a verdict; the next one is refused until a result comes out. Contest: judged before the lists and with no limit; from the 6th submission waiting for a verdict, the team’s next ones go further back in the queue. Only the training super-admin gives the Super priority. Every change is recorded in the Audit log.',
        'Decide el turno de esta competencia en la cola de evaluación y la regla de envíos. Lista (pública o privada): cada equipo tiene como máximo 3 envíos esperando veredicto; el siguiente se rechaza hasta que salga un resultado. Competencia: se evalúa antes que las listas y sin límite; a partir del 6.º envío esperando veredicto, los siguientes del equipo van más atrás en la cola. Solo el superadministrador del entrenamiento da la prioridad Super. Todo cambio queda registrado en la Auditoría.')),
    field(T('Prioridade', 'Priority', 'Prioridad'), aPrio));

  function getValue() {
    return {
      ...(isCreate ? { priority: priority.value } : {
        ...(!prioLocked && aPrio.value && aPrio.value !== prioInitial ? { priority: aPrio.value } : {}),
        name: name.value.trim() || undefined,
        ...(start.value ? { start: dtToEpoch(start.value) } : {}),
        ...(end.value ? { end: dtToEpoch(end.value) } : {}),
      }),
      // abertura VAZIA na edição = apagar (0): o login volta a abrir no início da rodada. Só manda o 0 se
      // havia uma abertura — senão todo salvar gravaria "LOGIN_START_TIME=padrao" no audit
      ...(loginStart.value ? { login_start: dtToEpoch(loginStart.value) }
        : (!isCreate && s.login_start ? { login_start: 0 } : {})),
      // freeze VAZIO = sem congelamento -> 0 (e não "não mexe"): apagar o campo tem de
      // DESCONGELAR. Omitir a chave fazia o salvar responder ✓ sem tirar o freeze.
      freeze: freeze.value ? dtToEpoch(freeze.value) : 0,
      locale: locale.value, tz: tz.value.trim(), login_enabled: loginEnabled.checked,
      show_log: showLog.checked, show_editor: showEditor.checked,
      score_anon: scoreAnon.checked, show_tl: showTL.checked,
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
