// shared/chief-alert.js — APELIDO do alerta global da organização (web/shared/staff-alert.js, 03/10/2026).
// O alerta de conflito do juiz-chefe virou um caso do alerta de juiz/chefe/admin/.mon (clarification
// sem resposta, voto pendente, conflito); os nomes antigos seguem valendo p/ quem já os importa
// (chief.js, review-board.js).
export { startStaffAlert as startChiefAlert, pokeStaffAlert as pokeChiefAlert } from './staff-alert.js';
