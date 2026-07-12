// shared/contest-guard.js — isolamento no frontend (defesa em profundidade junto da API).
// Num subdomínio de contest, QUALQUER página fora de /contest/ é redirecionada para o
// contest. Importado por shared/api.js, então roda em toda página. Racional: a máquina de
// prova abre o browser já no contest e nada fora dele deve ser alcançável.
import { contestHost } from './contest-host.js';

const _cid = contestHost();
// disponível para as páginas de contest derivarem o id do host (sem import extra).
window.__MOJ_CONTEST = _cid || '';
// EXCEÇÃO à regra: /treino/ajuda/ (o "como enviar": E/S, extensões, template por linguagem).
// É página ESTÁTICA de instrução — não fala com a API do treino, não lista problema nem contest,
// não vaza nada. O competidor precisa dela DENTRO da prova (a LAN é isolada: se bloquearmos aqui,
// ele fica sem saber como se lê a entrada). Ela detecta o subdomínio e veste o topbar do contest.
const ALLOW = ['/treino/ajuda'];

if (_cid) {
  const p = location.pathname;
  if (!(p === '/contest' || p.startsWith('/contest/') || ALLOW.some((a) => p.startsWith(a)))) {
    location.replace('/contest/?c=' + encodeURIComponent(_cid));
  }
}
