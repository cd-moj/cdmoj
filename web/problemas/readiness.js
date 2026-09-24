// problemas/readiness.js — os TEXTOS de "o problema está pronto?" (editor, Painel e a confirmação de
// publicar). A REGRA mora no servidor (server/api/v1/lib/calib-expect.sh + /problems/status): aqui só
// se traduz o que ele devolve — `expect` de cada solução, `summary`/`validator` da calibração e os
// códigos de `pending`. Nunca reescreva o juízo aqui (era o `solOk` do editor, que lia a string do
// veredicto e errava com TLE+WA, com problema pontuado e com wrong que nem compilou — relato do Arthur
// Botelho, 22/09/2026).
// Tudo é função (nada de T() no topo do módulo: congelaria o idioma no import).
import { T } from '/shared/i18n.js';

const plural = (n, one, many) => n + ' ' + (n === 1 ? one : many);

// pílula de uma solução: {cls, label, title}. cls usa as classes `pill ok|warn|no` da casa.
export function expectPill(ex) {
  const st = ex && ex.state;
  if (st === 'ok') return { cls: 'ok', label: T('✓ conforme', '✓ as expected') };
  if (st === 'note') return { cls: 'warn', label: T('≈ conforme, outro motivo', '≈ as expected, other reason'),
    title: T('A solução fez o que a categoria pede, mas não do jeito típico (veja "obtido").',
             'The solution did what its category requires, but not in the typical way (see "got").') };
  if (st === 'bad') return { cls: 'no', label: T('✗ divergente', '✗ diverges') };
  if (st === 'norun') return { cls: 'no', label: T('✗ não rodou', '✗ did not run') };
  return null;
}

// o que a CATEGORIA exige (uma linha, para o autor não ter de lembrar a regra)
export function expectWant(cat) {
  switch (cat) {
    case 'good': return T('esperado: aceita em todos os testes, dentro do tempo-limite que o juiz cobra',
                          'expected: accepted on every test, within the time limit the judge enforces');
    case 'pass': return T('esperado: aceita em todos os testes, dentro do tempo-limite (passa "raspando")',
                          'expected: accepted on every test, within the time limit (passes narrowly)');
    case 'slow': return T('esperado: estourar o tempo (TLE) em pelo menos 1 teste, sem errar os outros',
                          'expected: exceed the time (TLE) on at least 1 test, without wrong answers');
    case 'wrong': return T('esperado: ser REPROVADA — de preferência por resposta errada (WA)',
                           'expected: be REJECTED — preferably by a wrong answer (WA)');
    default: return '';
  }
}

export function countsText(c) {
  const order = ['AC', 'WA', 'TLE', 'MLE', 'RE', 'UE'];
  return order.filter(k => c && c[k]).map(k => `${k} ${c[k]}`).join(' · ');
}
const s2 = (v) => (v == null || !Number.isFinite(+v)) ? '—' : (+(+v).toFixed(3)) + 's';

// o que ACONTECEU, dito para o autor (o `why` do servidor)
export function expectGot(ex) {
  if (!ex) return '';
  const n = ex.counts || {};
  const cnt = countsText({ ...n, AC: 0 });   // o que FALHOU (os AC não explicam a falha)
  const wrongish = (n.WA || 0) + (n.RE || 0) + (n.MLE || 0);
  switch (ex.why) {
    case 'all_ac': return T('aceita em todos os testes', 'accepted on every test');
    case 'over_tl': return T(`aceita, mas levou ${s2(ex.tmax)} — acima do tempo-limite de ${s2(ex.tl)} que o juiz cobra (TLOVERRIDE baixo demais?). No julgamento ela tomaria TLE.`,
                             `accepted, but took ${s2(ex.tmax)} — above the ${s2(ex.tl)} time limit the judge enforces (TLOVERRIDE too low?). On real judging it would get TLE.`);
    case 'failed': return T('não foi aceita: ', 'not accepted: ') + cnt;
    case 'tle_allowed': return T('estourou o tempo, e o conf permite (ALLOWTLEDURINGCALIBRATION=y)', 'exceeded the time, and the conf allows it (ALLOWTLEDURINGCALIBRATION=y)');
    case 'tle': return T('estourou o tempo — o tempo-limite pega esta solução', 'exceeded the time — the time limit catches this solution');
    case 'tle_and_wrong': return T(`estourou o tempo, mas também errou em ${plural(wrongish, 'teste', 'testes')} (${cnt}) — a solução lenta deveria ser correta`,
                                   `exceeded the time, but also failed ${plural(wrongish, 'test', 'tests')} (${cnt}) — a slow solution should be correct`);
    case 'wrong_no_tle': return T(`errou sem estourar o tempo (${cnt}) — revise a solução ou os testes`, `failed without exceeding the time (${cnt}) — check the solution or the tests`);
    case 'no_tle': return T('passou em todos os testes dentro do tempo — o tempo-limite não pega esta solução', 'passed every test in time — the time limit does not catch this solution');
    case 'wa': return T('errou (WA) — os testes pegam o erro', 'wrong answer (WA) — the tests catch the bug');
    case 'failed_other': return T(`reprovada por ${cnt || 'outro motivo'}, não por WA — conta como reprovada; confira se era esse o erro que você queria pegar`,
                                  `rejected by ${cnt || 'another reason'}, not by WA — counts as rejected; check that this is the bug you meant to catch`);
    case 'accepted': return T('foi ACEITA — os testes não pegam o erro desta solução', 'was ACCEPTED — the tests do not catch the bug of this solution');
    case 'ce': return T('não compilou — não prova nada sobre os testes', 'did not compile — proves nothing about the tests');
    case 'lang': return T('linguagem indisponível neste juiz', 'language not available on this judge');
    case 'ue': return T('erro do corretor/juiz (UE) em algum teste', 'checker/judge error (UE) on some test');
    case 'noverdict': return T('sem veredicto', 'no verdict');
    default: return '';
  }
}

// resumo das soluções de uma calibração (o `summary` do /problems/calib)
export function summaryText(sm) {
  if (!sm || !sm.total && !(sm.missing || []).length) return '';
  const ok = (sm.total || 0) - (sm.bad || 0);
  const parts = [T(`${ok} de ${sm.total || 0} conforme`, `${ok} of ${sm.total || 0} as expected`)];
  if (sm.note) parts.push(T(`${sm.note} por outro motivo`, `${sm.note} by another reason`));
  if (sm.bad) parts.push(T(`${plural(sm.bad, 'divergente', 'divergentes')}`, `${sm.bad} diverging`));
  const miss = (sm.missing || []).length;
  if (miss) parts.push(T(`${miss} sem resultado (clique Calibrar: a calibração rápida só roda as good)`,
                         `${miss} without result (click Calibrate: the quick calibration only runs the good ones)`));
  return parts.join(' · ');
}

// resultado do validador de entrada num juiz (hosts[].validator ou o sumário)
export function validatorText(v) {
  if (!v) return '';
  switch (v.state) {
    case 'none': return T('sem validador de entrada (scripts/validator.cpp)', 'no input validator (scripts/validator.cpp)');
    case 'ok': return T(`validador aprovou as ${v.total} entradas`, `validator accepted all ${v.total} inputs`);
    case 'invalid': return T(`${v.invalid} de ${v.total} entradas INVÁLIDAS`, `${v.invalid} of ${v.total} inputs INVALID`);
    case 'error': return T('o validador não rodou (não compilou?)', 'the validator did not run (did not compile?)');
    default: return '';
  }
}

// uma pendência do /problems/status (`pending[]`)
export function pendingLabel(code) {
  const [k, arg] = String(code).split(/:(.*)/s);
  const n = +arg || 0;
  switch (k) {
    case 'package_failed': return T('pacote com erro (veja Validação & calibração)', 'package has errors (see Validation & calibration)');
    case 'package_unchecked': return T('pacote não conferido (clique Validar)', 'package not checked (click Validate)');
    case 'uncalibrated': return T('sem calibração', 'not calibrated');
    case 'needs_recalibration': return T('precisa recalibrar', 'needs recalibration');
    case 'good_no_tl': return T('solução good sem tempo-limite: ', 'good solution without time limit: ') + (arg || '');
    case 'sols_divergent': return T(`${plural(n, 'solução divergente', 'soluções divergentes')}`, `${n} diverging solution(s)`);
    case 'sols_unchecked': return T('soluções não conferidas desde a última edição (clique Calibrar)', 'solutions not checked since the last edit (click Calibrate)');
    case 'inputs_invalid': return T(`${plural(n, 'entrada inválida', 'entradas inválidas')} (validador)`, `${n} invalid input(s) (validator)`);
    case 'inputs_error': return T('o validador de entrada não rodou', 'the input validator did not run');
    case 'issues_open': return T(`${plural(n, 'issue aberta', 'issues abertas')}`, `${n} open issue(s)`);
    default: return code;
  }
}
