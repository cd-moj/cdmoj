// shared/module-requires.js — o texto (pt/en/es) de cada PRÉ-REQUISITO de módulo não atendido, pelo CÓDIGO que a API
// manda (o mesmo do 422 e do `requires` do catálogo: lib/modules.sh mod_requires_ok) e, no virtual, pelo MOTIVO
// (`reason`). Fonte única p/ o painel Central › Módulos, o passo 7 do assistente e o resultado da criação
// (`modules_skipped`). Código desconhecido cai na mensagem do servidor (PT).
import { T } from '/shared/i18n.js';

const REQ_TXT = {
  requires_shared_users: () => T('A inscrição usa as contas do Treino Livre (cada aluno se inscreve com a conta dele no treino), e este contest tem contas próprias: ligada, ela barraria todo aluno. Com contas próprias, distribua as credenciais em Pessoas › Contas.',
    'Registration uses the Free Training accounts (each student registers with their own training account), and this contest has its own accounts: turned on, it would block every student. With own accounts, hand out the credentials in People › Accounts.',
    'La inscripción usa las cuentas del Entrenamiento Libre (cada alumno se inscribe con su cuenta del entrenamiento), y esta competencia tiene cuentas propias: activada, bloquearía a todos los alumnos. Con cuentas propias, entrega las credenciales en Personas › Cuentas.'),
  editor_required: () => T('Precisa do editor de código no browser: ligue em Regras antes.', 'Needs the in-browser code editor: turn it on in Rules first.', 'Necesita el editor de código en el navegador: actívalo en Reglas antes.'),
  // virtual: o portão de lib/virtual.sh menos o que o tempo resolve; o MOTIVO vem em `reason`
  virtual_not_eligible: (reason) => T('Participação virtual indisponível: ', 'Virtual participation unavailable: ', 'Participación virtual no disponible: ') + (({
    problems_not_public: () => T('há problema não público no treino — publique os problemas antes.', 'a problem is not public in the training — publish the problems first.', 'hay un problema no público en el entrenamiento — publica los problemas antes.'),
    secret: () => T('contest secreto não pode ter participação virtual.', 'a secret contest cannot have virtual participation.', 'una competencia secreta no puede tener participación virtual.'),
    score_anon: () => T('o placar é anônimo — desligue o placar anônimo nas Regras.', 'the scoreboard is anonymous — turn the anonymous scoreboard off in Rules.', 'el marcador es anónimo — desactiva el marcador anónimo en Reglas.'),
    type: () => T('só no modo ICPC.', 'ICPC mode only.', 'solo en modo ICPC.'),
    window: () => T('o contest precisa de início e fim.', 'the contest needs a start and an end.', 'la competencia necesita inicio y fin.'),
  })[reason] || (() => reason || ''))(),
};

// requiresText({code, reason?, message?}) -> texto na língua da interface
export function requiresText(req) {
  if (!req) return '';
  const f = REQ_TXT[req.code];
  return f ? f(req.reason) : (req.message || '');
}
