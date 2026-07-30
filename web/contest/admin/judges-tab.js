// contest/admin/judges-tab.js — "Operação › Juízes": a fila da CORREÇÃO MANUAL (quem pegou,
// votos, idade) com o override auditado, mais a configuração do veredicto manual (rótulos das
// opções + matriz de auto-veredicto). O fluxo normal de votos é na área do juiz; aqui é o
// controle de quem organiza.
import { el } from '/shared/ui.js';
import { makeReviewBoard } from '/shared/review-board.js';
import { makeVerdictOptionsEditor, makeAutoVerdictEditor } from '/shared/contest-config/verdict-config.js';
import { T } from '/shared/i18n.js';

const enc = encodeURIComponent;

export function makeJudgesTab(CONTEST) {
  const panel = el('div', { class: 'section' });
  const board = makeReviewBoard({ contest: CONTEST });
  let timer = null;
  async function load() {
    panel.innerHTML = '';
    panel.append(el('h2', {}, T('⚖️ Tarefas do judge', '⚖️ Judge tasks')),
      el('p', { class: 'muted small' },
        T('Fila da correção manual: quem pegou, votos e idade de cada submissão segurada. ', 'Manual grading queue: who claimed, votes and age of each held submission. '),
        T('"Decidir/Resolver" libera o veredicto AO ALUNO na hora (override auditado); o fluxo normal de votos fica na ', '"Decide/Resolve" releases the verdict TO THE STUDENT right away (audited override); the normal voting flow is in the '),
        el('a', { href: '/contest/judge/?c=' + enc(CONTEST) }, T('área de avaliação', 'evaluation area')),
        T('. O modo e o nº de juízes que validam (1–5) ficam em Central › Regras; o juiz-chefe tem a mesma fila no ', '. The mode and how many judges validate (1–5) live in Home › Rules; the chief judge has the same queue in the '),
        el('a', { href: '/contest/chief/?c=' + enc(CONTEST) }, T('painel do juiz-chefe', 'chief judge panel')),
        T('. Papéis, quórum e quantas pessoas você precisa: ', '. Roles, quorum and how many people you need: '),
        el('a', { href: '/docs/MANUAL-ADMIN.html', target: '_blank' }, T('manual do organizador', "organizer's manual")), '.'),
      board.el,
      el('h3', { style: 'margin:1.2rem 0 .3rem' }, T('⚙️ Configuração do veredicto manual', '⚙️ Manual verdict configuration')),
      makeVerdictOptionsEditor(CONTEST), makeAutoVerdictEditor(CONTEST));
    await board.load();
    clearInterval(timer); timer = setInterval(() => { if (!panel.hidden && panel.isConnected) board.load(); }, 12000);
  }
  return { panel, load };
}
