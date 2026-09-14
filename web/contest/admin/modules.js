// contest/admin/modules.js — CATÁLOGO dos módulos do contest, espelho do bash
// (server/api/v1/lib/modules.sh `MODULES=(…)`). Um módulo é um GRUPO DE FEATURES que o admin liga
// por contest (`CONTEST_MODULES` no conf): liga painéis, seções, checagens do preflight e cartões
// da Central. Desligar nunca apaga dado. O acesso continua sendo cortado na API — isto é UX.
//
// ⚠ Os DOIS espelhos têm de ter os MESMOS ids (server/test/smoke-admin-nav.sh confere a paridade).
// Módulo novo: id aqui + no bash (MODULES, mod_detect) + painel em nav.js (PANEL_MODULE) + doc.
import { T } from '/shared/i18n.js';

export const MODULE_IDS = ['sedes', 'maquinas', 'rodadas', 'documentos', 'baloes', 'coortes', 'inscricoes', 'telao', 'classificacao'];

// fábrica preguiçosa: T() no topo congelaria o idioma antes do LOCALE do contest
export const MODULES = () => [
  { id: 'sedes', icon: '🏫', name: T('Sedes & escolas', 'Sites & schools'),
    desc: T('Prova em várias sedes: regiões e escolas por regex, identidade dos times (país, sede, universidade, brasão), prorrogação por sede e escopo do staff por sede.',
      'Multi-site contest: regions and schools by regex, team identity (country, site, university, crest), per-site time extension and per-site staff scope.'),
    panels: [T('Evento › Sedes & escolas', 'Event › Sites & schools'), T('Evento › Times', 'Event › Teams')] },
  { id: 'maquinas', icon: '🖥️', name: T('Máquinas (Maratona Linux)', 'Machines (Maratona Linux)'),
    desc: T('Gate de navegador por sede, sessão única por time, trava de sede por IP, anomalias de uso de máquina e o painel mlinux (nutellaboot).',
      'Per-site browser gate, single session per team, per-site IP lock, machine-usage anomalies and the mlinux panel (nutellaboot).'),
    panels: [T('Máquinas › Gate & trava', 'Machines › Gate & lock'), T('Máquinas › Anomalias', 'Machines › Anomalies'), T('Máquinas › mlinux', 'Machines › mlinux')] },
  { id: 'rodadas', icon: '🔁', name: T('Rodadas', 'Rounds'),
    desc: T('Aquecimento → prova no mesmo contest: plano de rodadas, promoção, arquivamento e relatório de cada rodada.',
      'Warm-up → contest in the same contest: round plan, promotion, archiving and a report per round.'),
    panels: [T('Evento › Rodadas', 'Event › Rounds')] },
  { id: 'documentos', icon: '📄', name: T('Documentos da prova', 'Contest documents'),
    desc: T('Info sheet, caderno de problemas, folha de time limits e editorial, em PDF e HTML, gerados do que o contest já tem.',
      'Info sheet, problem booklet, time-limits sheet and editorial, as PDF and HTML, generated from what the contest already has.'),
    panels: [T('Evento › Documentos', 'Event › Documents')] },
  { id: 'baloes', icon: '🎈', name: T('Balões', 'Balloons'),
    desc: T('Cor por problema (também por rodada), tarefa de balão na fila do staff, ★ primeiro da sede e retenção durante o freeze.',
      'Colour per problem (also per round), balloon task in the staff queue, ★ first of the site and holding during the freeze.'),
    panels: [T('Evento › Balões', 'Event › Balloons')] },
  { id: 'coortes', icon: '🎯', name: T('Coortes', 'Cohorts'),
    desc: T('Times oficiais × convidados: coorte privada fora do placar público e placar próprio por coorte.',
      'Official × guest teams: private cohort off the public scoreboard and a scoreboard per cohort.'),
    panels: [T('Evento › Coortes', 'Event › Cohorts')] },
  { id: 'inscricoes', icon: '📝', name: T('Inscrições', 'Registrations'),
    desc: T('Inscrição ancorada na prova: times por convite, individuais, janela e atraso. Só p/ contest com contas da fonte (USERS_FROM).',
      'Registration anchored on the contest: teams by invite, individuals, window and late entries. Only for contests with source accounts (USERS_FROM).'),
    panels: [T('Pessoas › Inscrições', 'People › Registrations')] },
  { id: 'telao', icon: '🎥', name: T('Telão e revelação', 'Big screen and reveal'),
    desc: T('Cerimônia de revelação do placar e telão Animeitor: fotos e músicas dos times, pacote e chaves do webcast.',
      'Scoreboard reveal ceremony and the Animeitor big screen: team photos and music, package and webcast keys.'),
    panels: [T('Central › Gerar (revelação, telão)', 'Home › Generate (reveal, big screen)'), T('Evento › Times (fotos)', 'Event › Teams (photos)')] },
  { id: 'classificacao', icon: '🏅', name: T('Classificação', 'Qualification'),
    desc: T('Promoção à próxima fase por algoritmo (SBC 1ª fase hoje; PDA depois): rascunho, revisão e publicação no placar.',
      'Promotion to the next stage by algorithm (SBC stage 1 today; PDA later): draft, review and publication on the scoreboard.'),
    panels: [T('Evento › Classificação', 'Event › Qualification')] },
];

// presets só PRÉ-MARCAM as caixas do painel Módulos — o admin ainda salva
export const PRESETS = () => [
  { id: 'disciplina', name: T('Prova de disciplina', 'Course exam'), mods: [],
    hint: T('só o comum: problemas, contas, sessões, placar, staff, juízes', 'the common part only: problems, accounts, sessions, scoreboard, staff, judges') },
  { id: 'disciplina-mlinux', name: T('Disciplina com Maratona Linux', 'Course exam with Maratona Linux'), mods: ['maquinas'],
    hint: T('o comum + gate de máquina, sessão única e anomalias', 'the common part + machine gate, single session and anomalies') },
  { id: 'seletiva', name: T('Seletiva / prova com inscrição', 'Selection / contest with registration'), mods: ['inscricoes', 'documentos', 'baloes', 'telao'],
    hint: T('inscrição, caderno, balões e cerimônia — uma sede', 'registration, booklet, balloons and ceremony — one site') },
  { id: 'maratona', name: T('Maratona / ICPC (várias sedes)', 'Maratona / ICPC (multi-site)'), mods: MODULE_IDS.slice(),
    hint: T('tudo ligado', 'everything on') },
];
