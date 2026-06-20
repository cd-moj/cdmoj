// shared/contest-config/index.js — editores reaproveitáveis de configuração de contest.
// Usados tanto na criação (web/treino/criar) quanto no admin do contest (web/contest/admin).
export { makeColorsEditor } from './colors.js';
export { makeTeamsEditor } from './teams.js';
export { makeRegionsEditor } from './regions.js';
export { makeBasicEditor } from './basic.js';
export { nowEpoch, toLocalDT, dtToEpoch } from './util.js';
