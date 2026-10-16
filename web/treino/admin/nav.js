// treino/admin/nav.js — a NAVEGAÇÃO do painel do treino em GRUPOS (16/10/2026). Puro e sem DOM (testável em gjs).
// O painel abria na aba Sessões, com o "todos" à mão — foi por ali que um clique deslogou 1.310 contas. Agora abre em
// Visão geral › Estatísticas, e a aba fica no #endereço (`#grupo/painel`): recarregar mantém onde você estava.
// Os ids antigos de aba (`#sessions`, `#judges`…) seguem valendo pelo ALIAS. Rótulos são fábrica preguiçosa: T() no
// topo do módulo congelaria o idioma antes de a página aplicar o dela.
import { T } from '/shared/i18n.js';

export const GROUPS = () => [
  { id: 'visao', label: T('📊 Visão geral', '📊 Overview', '📊 Visión general'), panels: [
    { id: 'estatisticas', label: T('Estatísticas', 'Statistics', 'Estadísticas') },
    { id: 'fila', label: T('Fila & tempo de resposta', 'Queue & response time', 'Cola y tiempo de respuesta') },
    { id: 'maquinas', label: T('Máquinas de julgamento', 'Judging machines', 'Máquinas de evaluación') }] },
  { id: 'pessoas', label: T('👥 Pessoas', '👥 People', '👥 Personas'), panels: [
    { id: 'geridas', label: T('Contas geridas', 'Managed accounts', 'Cuentas gestionadas') },
    { id: 'sessoes', label: T('Sessões ativas', 'Active sessions', 'Sesiones activas') }] },
  { id: 'contests', label: T('🏆 Contests', '🏆 Contests', '🏆 Competencias'), panels: [
    { id: 'lista', label: T('Contests', 'Contests', 'Competencias') },
    { id: 'criar', label: T('Quem pode criar', 'Who can create', 'Quién puede crear') }] },
  { id: 'conteudo', label: T('📰 Conteúdo', '📰 Content', '📰 Contenido'), panels: [
    { id: 'noticias', label: T('Notícias', 'News', 'Noticias') },
    { id: 'conquistas', label: T('Conquistas', 'Achievements', 'Logros') }] },
  { id: 'registros', label: T('📜 Registros', '📜 Records', '📜 Registros'), panels: [
    { id: 'auditoria', label: T('Auditoria', 'Audit', 'Auditoría') },
    { id: 'atividade', label: T('Atividade', 'Activity', 'Actividad') },
    { id: 'acessos', label: T('Acessos', 'Access log', 'Accesos') }] },
];

export const DEFAULT = 'visao/estatisticas';

// os ids das abas de antes de 16/10/2026 (link salvo, favorito, tutorial)
export const ALIAS = {
  sessions: 'pessoas/sessoes', managed: 'pessoas/geridas', contests: 'contests/lista', perms: 'contests/criar',
  news: 'conteudo/noticias', achievements: 'conteudo/conquistas', stats: 'visao/estatisticas', queue: 'visao/fila',
  judges: 'visao/maquinas', audit: 'registros/auditoria', activity: 'registros/atividade', access: 'registros/acessos',
};

// resolveHash('#pessoas/sessoes') -> {group:'pessoas', panel:'sessoes', key:'pessoas/sessoes'}; desconhecido = DEFAULT
export function resolveHash(hash) {
  let h = String(hash || '').replace(/^#/, '').trim();
  if (ALIAS[h]) h = ALIAS[h];
  const [g, p] = h.split('/');
  const grp = GROUPS().find((x) => x.id === g);
  if (grp) {
    const pan = grp.panels.find((x) => x.id === p) || grp.panels[0];
    return { group: grp.id, panel: pan.id, key: grp.id + '/' + pan.id };
  }
  const [dg, dp] = DEFAULT.split('/');
  return { group: dg, panel: dp, key: DEFAULT };
}
