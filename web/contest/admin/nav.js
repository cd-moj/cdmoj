// contest/admin/nav.js — a NAVEGAÇÃO do painel de admin, PURA (sem DOM, sem importar painel):
// grupos × painéis, qual MÓDULO cada painel exige, o ALIAS de todo hash antigo e a resolução de um
// hash contra os módulos ligados. É o que o admin.js renderiza e o que os testes (gjs /
// smoke-admin-nav.sh) verificam — rótulo, ordem e alias vivem aqui e só aqui.
//
// Regras:
//  - ids de painel são ÚNICOS no painel inteiro ⇒ um hash resolve pelo id do painel em qualquer
//    grupo visível (bookmark/TARGET/âncora com grupo antigo continua abrindo o painel certo);
//  - painel de módulo DESLIGADO cai em Central › Módulos com um aviso (nunca em 404 nem na Central
//    muda — a pessoa veio de um link e precisa saber por que não chegou);
//  - grupos de EVENTO (`evento`, `maquinas`) só aparecem com algum painel visível, depois do
//    separador; os quatro comuns aparecem sempre.
import { T } from '/shared/i18n.js';

// painel -> módulo(s) que o liga (qualquer um basta). Ausente = comum a todo contest.
export const PANEL_MODULE = {
  inscricoes: ['inscricoes'],
  rodadas: ['rodadas'], documentos: ['documentos'], baloes: ['baloes'], classificacao: ['classificacao'], virtual: ['virtual'],
  times: ['sedes', 'telao'], coortes: ['coortes'], sedes: ['sedes'],
  gate: ['maquinas'], anomalias: ['maquinas'], mlinux: ['maquinas'],
};
export const EVENT_GROUPS = ['evento', 'maquinas'];

// fábrica preguiçosa: T() no topo congelaria o idioma antes do LOCALE do contest
export const GROUPS = () => [
  { id: 'central', label: T('🏁 Central', '🏁 Home', '🏁 Central'), panels: [
    { id: 'central', label: T('Central', 'Home', 'Central') },
    { id: 'modulos', label: T('Módulos', 'Modules', 'Módulos') },
    { id: 'regras', label: T('Regras', 'Rules', 'Reglas') },
  ] },
  { id: 'prova', label: T('🧩 Prova', '🧩 Contest', '🧩 Competencia'), panels: [
    { id: 'problemas', label: T('Problemas', 'Problems', 'Problemas') },
    { id: 'relatorio', label: T('Relatório', 'Report', 'Informe') },
  ] },
  { id: 'pessoas', label: T('👥 Pessoas', '👥 People', '👥 Personas'), panels: [
    { id: 'contas', label: T('Contas', 'Accounts', 'Cuentas') },
    { id: 'inscricoes', label: T('Inscrições', 'Registrations', 'Inscripciones') },
    { id: 'sessoes', label: T('Sessões', 'Sessions', 'Sesiones') },
  ] },
  { id: 'operacao', label: T('🎛️ Operação', '🎛️ Operations', '🎛️ Operación'), panels: [
    { id: 'situacao', label: T('Situação', 'Status', 'Situación') },
    { id: 'staff', label: T('Staff', 'Staff', 'Staff') },
    { id: 'juizes', label: T('Juízes', 'Judges', 'Jueces') },
    { id: 'auditoria', label: T('Auditoria', 'Audit', 'Auditoría') },
  ] },
  { id: 'evento', label: T('🏟️ Evento', '🏟️ Event', '🏟️ Evento'), panels: [
    { id: 'rodadas', label: T('Rodadas', 'Rounds', 'Rondas') },
    { id: 'documentos', label: T('Documentos', 'Documents', 'Documentos') },
    { id: 'baloes', label: T('Balões', 'Balloons', 'Globos') },
    { id: 'classificacao', label: T('Classificação', 'Qualification', 'Clasificación') },
    { id: 'virtual', label: 'Virtual' },
    { id: 'times', label: T('Times', 'Teams', 'Equipos') },
    { id: 'coortes', label: T('Coortes', 'Cohorts', 'Cohortes') },
    { id: 'sedes', label: T('Sedes & escolas', 'Sites & schools', 'Sedes y escuelas') },
  ] },
  { id: 'maquinas', label: T('🖥️ Máquinas', '🖥️ Machines', '🖥️ Máquinas'), panels: [
    { id: 'gate', label: T('Gate & trava', 'Gate & lock', 'Gate y bloqueo') },
    { id: 'anomalias', label: T('Anomalias', 'Anomalies', 'Anomalías') },
    { id: 'mlinux', label: 'mlinux' },
  ] },
];

// hash antigo -> novo. Link salvo/atalho de manual/TARGET não pode quebrar.
export const ALIAS = {
  // 1ª geração (13 abas planas)
  dash: 'operacao/situacao', preflight: 'central/central', settings: 'central/regras',
  problems: 'prova/problemas', teams: 'evento/times', cohorts: 'evento/coortes',
  appearance: 'evento/sedes', users: 'pessoas/contas', log: 'pessoas/sessoes',
  backups: 'operacao/auditoria', rounds: 'evento/rodadas', machines: 'maquinas/gate',
  docs: 'evento/documentos', tasks: 'operacao/staff', staff: 'operacao/staff',
  verdict: 'operacao/juizes', audit: 'operacao/auditoria', registrations: 'pessoas/inscricoes',
  // 2ª geração (4 grupos, 2026-08) -> 3ª (módulos, 2026-09)
  'prova/rodadas': 'evento/rodadas', 'prova/documentos': 'evento/documentos', 'prova/baloes': 'evento/baloes',
  'prova/classificacao': 'evento/classificacao', 'pessoas/times': 'evento/times',
  'pessoas/coortes': 'evento/coortes', 'pessoas/sedes': 'evento/sedes',
  'pessoas/maquinas': 'maquinas/gate', 'operacao/mlinux': 'maquinas/mlinux',
};

export const panelVisible = (id, mods) => { const need = PANEL_MODULE[id]; return !need || need.some((m) => mods.has(m)); };

// grupos com só os painéis visíveis; grupo vazio some
export function visibleGroups(mods) {
  return GROUPS().map((g) => ({ ...g, panels: g.panels.filter((p) => panelVisible(p.id, mods)) })).filter((g) => g.panels.length);
}

// resolveHash('#grupo/painel' | '#alias', Set(mods)) -> { groups, grp, pan, notice }
// notice = { panel, modules } quando o hash pedia um painel de módulo desligado
export function resolveHash(hash, mods) {
  let h = decodeURIComponent((hash || '').replace(/^#/, ''));
  if (ALIAS[h]) h = ALIAS[h];
  const groups = visibleGroups(mods);
  const [hg, hp] = h.split('/');
  let grp = groups.find((g) => g.id === hg) || null;
  let pan = grp ? grp.panels.find((p) => p.id === hp) || null : null;
  if (!pan && hp) {                       // pelo id, em qualquer grupo visível (ids são únicos)
    for (const g of groups) { const p = g.panels.find((x) => x.id === hp); if (p) { grp = g; pan = p; break; } }
  }
  let notice = null;
  if (!pan && hp) {                       // existe, mas é de módulo desligado
    for (const g of GROUPS()) {
      const p = g.panels.find((x) => x.id === hp);
      if (p && PANEL_MODULE[p.id]) { notice = { panel: p.label, modules: PANEL_MODULE[p.id] }; break; }
    }
    if (notice) { grp = groups[0]; pan = grp.panels.find((p) => p.id === 'modulos') || grp.panels[0]; }
  }
  if (!grp) grp = groups[0];
  if (!pan) pan = grp.panels[0];
  return { groups, grp, pan, notice };
}

// [grupo, painel] de um painel pelo id (p/ links: TARGET da Central, âncoras)
export function locate(panelId) {
  for (const g of GROUPS()) { if (g.panels.some((p) => p.id === panelId)) return [g.id, panelId]; }
  return null;
}
