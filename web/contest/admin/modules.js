// contest/admin/modules.js — CATÁLOGO dos módulos do contest, espelho do bash
// (server/api/v1/lib/modules.sh `MODULES=(…)`). Um módulo é um GRUPO DE FEATURES que o admin liga
// por contest (`CONTEST_MODULES` no conf): liga painéis, seções, checagens do preflight e cartões
// da Central. Desligar nunca apaga dado. O acesso continua sendo cortado na API — isto é UX.
//
// ⚠ Os DOIS espelhos têm de ter os MESMOS ids (server/test/smoke-admin-nav.sh confere a paridade).
// Módulo novo: id aqui + no bash (MODULES, mod_detect) + painel em nav.js (PANEL_MODULE) + doc.
import { T } from '/shared/i18n.js';

export const MODULE_IDS = ['sedes', 'maquinas', 'rodadas', 'documentos', 'baloes', 'coortes', 'inscricoes', 'telao', 'classificacao', 'virtual', 'esqueletos'];

// fábrica preguiçosa: T() no topo congelaria o idioma antes do LOCALE do contest
export const MODULES = () => [
  { id: 'sedes', icon: '🏫', name: T('Sedes & escolas', 'Sites & schools', 'Sedes y escuelas'),
    desc: T('Prova em várias sedes: regiões e escolas por regex, identidade dos times (país, sede, universidade, brasão), prorrogação por sede e escopo do staff por sede.',
      'Multi-site contest: regions and schools by regex, team identity (country, site, university, crest), per-site time extension and per-site staff scope.',
      'Competencia multisede: regiones y escuelas por regex, identidad de los equipos (país, sede, universidad, escudo), prórroga por sede y alcance del staff por sede.'),
    panels: [T('Evento › Sedes & escolas', 'Event › Sites & schools', 'Evento › Sedes y escuelas'), T('Evento › Times', 'Event › Teams', 'Evento › Equipos')] },
  { id: 'maquinas', icon: '🖥️', name: T('Máquinas (Maratona Linux)', 'Machines (Maratona Linux)', 'Máquinas (Maratona Linux)'),
    desc: T('Gate de navegador por sede, sessão única por time, trava de sede por IP, anomalias de uso de máquina e o painel mlinux (nutellaboot).',
      'Per-site browser gate, single session per team, per-site IP lock, machine-usage anomalies and the mlinux panel (nutellaboot).',
      'Control de acceso por navegador por sede, sesión única por equipo, bloqueo de IP por sede, anomalías de uso de máquina y el panel mlinux (nutellaboot).'),
    panels: [T('Máquinas › Gate & trava', 'Machines › Gate & lock', 'Máquinas › Gate y bloqueo'), T('Máquinas › Anomalias', 'Machines › Anomalies', 'Máquinas › Anomalías'), T('Máquinas › mlinux', 'Machines › mlinux', 'Máquinas › mlinux')] },
  { id: 'rodadas', icon: '🔁', name: T('Rodadas', 'Rounds', 'Rondas'),
    desc: T('Aquecimento → prova no mesmo contest: plano de rodadas, promoção, arquivamento e relatório de cada rodada.',
      'Warm-up → contest in the same contest: round plan, promotion, archiving and a report per round.',
      'Calentamiento → competencia en la misma competencia: plan de rondas, promoción, archivado e informe de cada ronda.'),
    panels: [T('Evento › Rodadas', 'Event › Rounds', 'Evento › Rondas')] },
  { id: 'documentos', icon: '📄', name: T('Documentos da prova', 'Contest documents', 'Documentos de la competencia'),
    desc: T('Info sheet, caderno de problemas, folha de time limits e editorial, em PDF e HTML, gerados do que o contest já tem.',
      'Info sheet, problem booklet, time-limits sheet and editorial, as PDF and HTML, generated from what the contest already has.',
      'Info sheet, cuadernillo de problemas, hoja de time limits y editorial, en PDF y HTML, generados a partir de lo que la competencia ya tiene.'),
    panels: [T('Evento › Documentos', 'Event › Documents', 'Evento › Documentos')] },
  { id: 'baloes', icon: '🎈', name: T('Balões', 'Balloons', 'Globos'),
    desc: T('Cor por problema (também por rodada), tarefa de balão na fila do staff, ★ primeiro da sede e retenção durante o freeze.',
      'Colour per problem (also per round), balloon task in the staff queue, ★ first of the site and holding during the freeze.',
      'Color por problema (también por ronda), tarea de globo en la cola del staff, ★ primero de la sede y retención durante el congelamiento.'),
    panels: [T('Evento › Balões', 'Event › Balloons', 'Evento › Globos')] },
  { id: 'coortes', icon: '🎯', name: T('Coortes', 'Cohorts', 'Cohortes'),
    desc: T('Times oficiais × convidados: coorte privada fora do placar público e placar próprio por coorte.',
      'Official × guest teams: private cohort off the public scoreboard and a scoreboard per cohort.',
      'Equipos oficiales × invitados: cohorte privada fuera del marcador público y un marcador propio por cohorte.'),
    panels: [T('Evento › Coortes', 'Event › Cohorts', 'Evento › Cohortes')] },
  { id: 'inscricoes', icon: '📝', name: T('Inscrições', 'Registrations', 'Inscripciones'),
    desc: T('Inscrição ancorada na prova: times por convite, individuais, janela e atraso. Só p/ contest com contas da fonte (USERS_FROM).',
      'Registration anchored on the contest: teams by invite, individuals, window and late entries. Only for contests with source accounts (USERS_FROM).',
      'Inscripción anclada en la competencia: equipos por invitación, individuales, ventana y entradas tardías. Solo para competencias con cuentas de origen (USERS_FROM).'),
    panels: [T('Pessoas › Inscrições', 'People › Registrations', 'Personas › Inscripciones')] },
  { id: 'telao', icon: '🎥', name: T('Telão e revelação', 'Big screen and reveal', 'Pantalla y revelación'),
    desc: T('Cerimônia de revelação do placar e telão Animeitor: fotos e músicas dos times, pacote e chaves do webcast.',
      'Scoreboard reveal ceremony and the Animeitor big screen: team photos and music, package and webcast keys.',
      'Ceremonia de revelación del marcador y la pantalla Animeitor: fotos y música de los equipos, paquete y claves del webcast.'),
    panels: [T('Central › Gerar (revelação, telão)', 'Home › Generate (reveal, big screen)', 'Central › Generar (revelación, pantalla)'), T('Evento › Times (fotos)', 'Event › Teams (photos)', 'Evento › Equipos (fotos)')] },
  { id: 'classificacao', icon: '🏅', name: T('Classificação', 'Qualification', 'Clasificación'),
    desc: T('Promoção à próxima fase por algoritmo (SBC 1ª fase hoje; PDA depois): rascunho, revisão e publicação no placar.',
      'Promotion to the next stage by algorithm (SBC stage 1 today; PDA later): draft, review and publication on the scoreboard.',
      'Promoción a la siguiente fase por algoritmo (SBC fase 1 hoy; PDA después): borrador, revisión y publicación en el marcador.'),
    panels: [T('Evento › Classificação', 'Event › Qualification', 'Evento › Clasificación')] },
  { id: 'virtual', icon: '🕹️', name: T('Participação virtual', 'Virtual participation', 'Participación virtual'),
    desc: T('Depois de encerrada, a prova pode ser refeita por qualquer conta do treino, contra o placar oficial no tempo do participante. Só liga se TODOS os problemas já forem públicos no treino; contest secreto nunca.',
      'After it ends, any training account can redo the contest against the official scoreboard, in the participant\'s own time. It only turns on if ALL problems are already public in training; a secret contest never.',
      'Después de terminar, cualquier cuenta de entrenamiento puede rehacer la competencia contra el marcador oficial, en su propio tiempo. Solo se activa si TODOS los problemas ya son públicos en el entrenamiento; una competencia secreta nunca.'),
    panels: [T('Evento › Virtual', 'Event › Virtual', 'Evento › Virtual')] },
  { id: 'esqueletos', icon: '📝', name: T('Esqueleto de código', 'Code skeleton', 'Esqueleto de código'),
    desc: T('O editor de código do time abre com o esqueleto da linguagem (o mesmo do treino) ou com o que você escrever para este contest; uma linguagem também pode abrir vazia. Precisa do editor de código no browser ligado. Enviar o esqueleto sem mudar nada é recusado na tela. Problema de submissão de função abre vazio.',
      'The team code editor opens with the language skeleton (the same as in training) or with the one you write for this contest; a language can also open empty. It needs the in-browser code editor on. Submitting the skeleton without changes is refused on screen. A function-submission problem opens empty.',
      'El editor de código del equipo abre con el esqueleto del lenguaje (el mismo del entrenamiento) o con el que escribas para esta competencia; un lenguaje también puede abrir vacío. Necesita el editor de código en el navegador activado. Enviar el esqueleto sin cambios se rechaza en pantalla. Un problema de envío de función abre vacío.'),
    panels: [T('Prova › Esqueletos', 'Contest › Skeletons', 'Competencia › Esqueletos')] },
];

// presets só PRÉ-MARCAM as caixas do painel Módulos — o admin ainda salva
export const PRESETS = () => [
  { id: 'disciplina', name: T('Prova de disciplina', 'Course exam', 'Examen de curso'), mods: [],
    hint: T('só o comum: problemas, contas, sessões, placar, staff, juízes', 'the common part only: problems, accounts, sessions, scoreboard, staff, judges', 'solo lo común: problemas, cuentas, sesiones, marcador, staff, jueces') },
  { id: 'disciplina-mlinux', name: T('Disciplina com Maratona Linux', 'Course exam with Maratona Linux', 'Examen de curso con Maratona Linux'), mods: ['maquinas'],
    hint: T('o comum + gate de máquina, sessão única e anomalias', 'the common part + machine gate, single session and anomalies', 'lo común + control de acceso de máquina, sesión única y anomalías') },
  { id: 'seletiva', name: T('Seletiva / prova com inscrição', 'Selection / contest with registration', 'Selectiva / competencia con inscripción'), mods: ['inscricoes', 'documentos', 'baloes', 'telao'],
    hint: T('inscrição, caderno, balões e cerimônia — uma sede', 'registration, booklet, balloons and ceremony — one site', 'inscripción, cuadernillo, globos y ceremonia — una sede') },
  { id: 'maratona', name: T('Maratona / ICPC (várias sedes)', 'Maratona / ICPC (multi-site)', 'Maratona / ICPC (multisede)'), mods: MODULE_IDS.filter((m) => m !== 'virtual' && m !== 'esqueletos'),   // virtual é decisão de DEPOIS da prova (exige problemas públicos); na maratona o time espera o editor VAZIO
    hint: T('tudo ligado', 'everything on', 'todo activado') },
];

// mensagens dos códigos de erro do módulo (o servidor responde em PT; a tela fala o idioma da interface)
export function esqErrorText(e) {
  const code = (e && (e.code || (e.data && e.data.code))) || '';
  if (code === 'editor_required') return T('Os esqueletos precisam do editor embutido: ligue "Editor de código no browser" em Central › Regras.', 'Skeletons need the built-in editor: turn on "In-browser code editor" in Home › Rules.', 'Los esqueletos necesitan el editor integrado: activa "Editor de código en el navegador" en Central › Reglas.');
  if (code === 'module_needs_editor') return T('O módulo Esqueletos de código está ligado e precisa do editor embutido: desligue o módulo antes (Central › Módulos).', 'The Code skeleton module is on and needs the built-in editor: turn the module off first (Home › Modules).', 'El módulo Esqueleto de código está activado y necesita el editor integrado: desactiva el módulo antes (Central › Módulos).');
  if (code === 'code_too_big') return T('Esqueleto grande demais (máximo de 64 KB).', 'Skeleton too large (64 KB maximum).', 'Esqueleto demasiado grande (máximo de 64 KB).');
  if (code === 'lang_invalid') return T('Linguagem inválida para este contest.', 'Invalid language for this contest.', 'Lenguaje inválido para esta competencia.');
  return (e && e.message) || T('erro', 'error', 'error');
}
