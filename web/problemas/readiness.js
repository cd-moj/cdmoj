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
  if (st === 'ok') return { cls: 'ok', label: T('✓ conforme', '✓ as expected', '✓ conforme') };
  if (st === 'note') return { cls: 'warn', label: T('≈ conforme, outro motivo', '≈ as expected, other reason', '≈ conforme, otro motivo'),
    title: T('A solução fez o que a categoria pede, mas não do jeito típico (veja "obtido").',
             'The solution did what its category requires, but not in the typical way (see "got").',
             'La solución hizo lo que la categoría pide, pero no de la forma típica (mira "obtenido").') };
  if (st === 'bad') return { cls: 'no', label: T('✗ divergente', '✗ diverges', '✗ diverge') };
  if (st === 'norun') return { cls: 'no', label: T('✗ não rodou', '✗ did not run', '✗ no se ejecutó') };
  // os dois métodos de TL (26/10/2026): a linha não tem o juízo pelo método avaliado (calibrada antes deles)
  if (st === 'unmeasured') return { cls: '', label: T('· não medido', '· not measured', '· no medido'),
    title: T('Esta calibração não julgou a solução por este método de TL — recalibre.',
             'This calibration did not judge the solution by this time-limit method — recalibrate.',
             'Esta calibración no juzgó la solución por este método de tiempo límite — recalibra.') };
  return null;
}
// nome do método de TL (docs/PACOTE.md "Métodos de TL")
export const tlMethodName = (m) => (m === 'kattis' ? 'Kattis' : 'MOJ');

// o que a CATEGORIA exige (uma linha, para o autor não ter de lembrar a regra). Com o `expect` do método
// Kattis, a regra leva as MARGENS da spec (a × tempo da good ≤ TL; a lenta passa de b × o TL).
export function expectWant(cat, ex) {
  if (ex && ex.method === 'kattis' && ex.need) {
    const k = +(+ex.need).toFixed(2);
    if (cat === 'good') return T(`esperado (Kattis): aceita em todos os testes, com folga — ${k} × o pior tempo cabe no tempo-limite`,
                                 `expected (Kattis): accepted on every test, with headroom — ${k} × the worst time fits in the time limit`,
                                 `esperado (Kattis): aceptada en todas las pruebas, con margen — ${k} × el peor tiempo cabe en el tiempo límite`);
    if (cat === 'slow') return T(`esperado (Kattis): estourar o tempo em pelo menos 1 teste por ${k} × o tempo-limite, sem errar os outros`,
                                 `expected (Kattis): exceed the time on at least 1 test by ${k} × the time limit, without wrong answers`,
                                 `esperado (Kattis): exceder el tiempo en al menos 1 prueba por ${k} × el tiempo límite, sin fallar las demás`);
  }
  switch (cat) {
    case 'good': return T('esperado: aceita em todos os testes, dentro do tempo-limite que o juiz cobra',
                          'expected: accepted on every test, within the time limit the judge enforces',
                          'esperado: aceptada en todas las pruebas, dentro del tiempo límite que el juez exige');
    case 'pass': return T('esperado: aceita em todos os testes, dentro do tempo-limite (passa "raspando")',
                          'expected: accepted on every test, within the time limit (passes narrowly)',
                          'esperado: aceptada en todas las pruebas, dentro del tiempo límite (pasa “raspando”)');
    case 'slow': return T('esperado: estourar o tempo (TLE) em pelo menos 1 teste, sem errar os outros',
                          'expected: exceed the time (TLE) on at least 1 test, without wrong answers',
                          'esperado: exceder el tiempo (TLE) en al menos 1 prueba, sin fallar las demás');
    case 'wrong': return T('esperado: ser REPROVADA — de preferência por resposta errada (WA)',
                           'expected: be REJECTED — preferably by a wrong answer (WA)',
                           'esperado: ser RECHAZADA — de preferencia por respuesta incorrecta (WA)');
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
    case 'all_ac': return T('aceita em todos os testes', 'accepted on every test', 'aceptada en todas las pruebas');
    case 'over_tl': {
      const tol = ex.drift > 0 ? T(` + ${s2(ex.drift)} de tolerância`, ` + ${s2(ex.drift)} tolerance`, ` + ${s2(ex.drift)} de tolerancia`) : '';
      return T(`aceita, mas levou ${s2(ex.tmax)} — acima do tempo-limite de ${s2(ex.tl)}${tol} que o juiz cobra (TLOVERRIDE baixo demais?). No julgamento ela tomaria TLE.`,
               `accepted, but took ${s2(ex.tmax)} — above the ${s2(ex.tl)}${tol} time limit the judge enforces (TLOVERRIDE too low?). On real judging it would get TLE.`,
               `aceptada, pero tardó ${s2(ex.tmax)} — por encima del tiempo límite de ${s2(ex.tl)}${tol} que el juez exige (¿TLOVERRIDE demasiado bajo?). En el juzgamiento real recibiría TLE.`);
    }
    case 'failed': return T('não foi aceita: ', 'not accepted: ', 'no fue aceptada: ') + cnt;
    case 'tle_allowed': return T('estourou o tempo, e o conf permite (ALLOWTLEDURINGCALIBRATION=y)', 'exceeded the time, and the conf allows it (ALLOWTLEDURINGCALIBRATION=y)', 'excedió el tiempo, y el conf lo permite (ALLOWTLEDURINGCALIBRATION=y)');
    case 'tle': return T('estourou o tempo — o tempo-limite pega esta solução', 'exceeded the time — the time limit catches this solution', 'excedió el tiempo — el tiempo límite atrapa esta solución');
    case 'tle_and_wrong': return T(`estourou o tempo, mas também errou em ${plural(wrongish, 'teste', 'testes')} (${cnt}) — a solução lenta deveria ser correta`,
                                   `exceeded the time, but also failed ${plural(wrongish, 'test', 'tests')} (${cnt}) — a slow solution should be correct`,
                                   `excedió el tiempo, pero también falló en ${plural(wrongish, 'prueba', 'pruebas')} (${cnt}) — la solución lenta debería ser correcta`);
    case 'wrong_no_tle': return T(`errou sem estourar o tempo (${cnt}) — revise a solução ou os testes`, `failed without exceeding the time (${cnt}) — check the solution or the tests`, `falló sin exceder el tiempo (${cnt}) — revisa la solución o las pruebas`);
    case 'no_tle': return T('passou em todos os testes dentro do tempo — o tempo-limite não pega esta solução', 'passed every test in time — the time limit does not catch this solution', 'pasó todas las pruebas dentro del tiempo — el tiempo límite no atrapa esta solución');
    case 'wa': return T('errou (WA) — os testes pegam o erro', 'wrong answer (WA) — the tests catch the bug', 'respuesta incorrecta (WA) — las pruebas atrapan el error');
    case 'failed_other': return T(`reprovada por ${cnt || 'outro motivo'}, não por WA — conta como reprovada; confira se era esse o erro que você queria pegar`,
                                  `rejected by ${cnt || 'another reason'}, not by WA — counts as rejected; check that this is the bug you meant to catch`,
                                  `rechazada por ${cnt || 'otro motivo'}, no por WA — cuenta como rechazada; revisa si era ese el error que querías atrapar`);
    case 'accepted': return T('foi ACEITA — os testes não pegam o erro desta solução', 'was ACCEPTED — the tests do not catch the bug of this solution', 'fue ACEPTADA — las pruebas no atrapan el error de esta solución');
    case 'ce': return T('não compilou — não prova nada sobre os testes', 'did not compile — proves nothing about the tests', 'no compiló — no demuestra nada sobre las pruebas');
    case 'lang': return T('linguagem indisponível neste juiz', 'language not available on this judge', 'lenguaje no disponible en este juez');
    case 'ue': return T('erro do corretor/juiz (UE) em algum teste', 'checker/judge error (UE) on some test', 'error del corrector/juez (UE) en alguna prueba');
    case 'noverdict': return T('sem veredicto', 'no verdict', 'sin veredicto');
    // as MARGENS do método Kattis (lib/calib-expect.sh)
    case 'tl_no_margin': {
      const k = +(+(ex.need || 2)).toFixed(2);
      return T(`aceita, mas sem a folga do Kattis: ${k} × ${s2(ex.tmax)} passa do tempo-limite de ${s2(ex.tl)} (TLOVERRIDE baixo demais?)`,
               `accepted, but without the Kattis headroom: ${k} × ${s2(ex.tmax)} is above the ${s2(ex.tl)} time limit (TLOVERRIDE too low?)`,
               `aceptada, pero sin el margen de Kattis: ${k} × ${s2(ex.tmax)} supera el tiempo límite de ${s2(ex.tl)} (¿TLOVERRIDE demasiado bajo?)`);
    }
    case 'tle_no_margin': {
      const k = +(+(ex.need || 1.5)).toFixed(2), r = ex.ratio != null ? +(+ex.ratio).toFixed(2) : null;
      return T(`estourou o tempo, mas só ${r != null ? r + ' × ' : 'um pouco acima d'}o tempo-limite — o Kattis pede ${k} × (a spec recusaria o pacote: a solução lenta tem de ser lenta de verdade)`,
               `exceeded the time, but only by ${r != null ? r + ' ×' : 'a little over'} the time limit — Kattis requires ${k} × (the spec would reject the package: a slow solution must be really slow)`,
               `excedió el tiempo, pero solo ${r != null ? r + ' × ' : 'un poco por encima d'}el tiempo límite — Kattis pide ${k} × (la spec rechazaría el paquete: la solución lenta tiene que ser lenta de verdad)`);
    }
    case 'tle_unmeasured': {
      const k = +(+(ex.need || 1.5)).toFixed(2);
      return T(`estourou o tempo, mas o teste parou no teto de ${s2(ex.etl)} antes de ${k} × o tempo-limite — a margem do Kattis não pôde ser medida`,
               `exceeded the time, but the test stopped at the ${s2(ex.etl)} ceiling before ${k} × the time limit — the Kattis headroom could not be measured`,
               `excedió el tiempo, pero la prueba se detuvo en el techo de ${s2(ex.etl)} antes de ${k} × el tiempo límite — el margen de Kattis no se pudo medir`);
    }
    case 'other_method': return T('esta calibração não julgou a solução por este método de TL — recalibre',
                                  'this calibration did not judge the solution by this time-limit method — recalibrate',
                                  'esta calibración no juzgó la solución por este método de tiempo límite — recalibra');
    default: return '';
  }
}

// resumo das soluções de uma calibração (o `summary` do /problems/calib)
export function summaryText(sm) {
  if (!sm || !sm.total && !(sm.missing || []).length) return '';
  const ok = (sm.total || 0) - (sm.bad || 0);
  const parts = [T(`${ok} de ${sm.total || 0} conforme`, `${ok} of ${sm.total || 0} as expected`, `${ok} de ${sm.total || 0} conforme`)];
  if (sm.note) parts.push(T(`${sm.note} por outro motivo`, `${sm.note} by another reason`, `${sm.note} por otro motivo`));
  if (sm.bad) parts.push(T(`${plural(sm.bad, 'divergente', 'divergentes')}`, `${sm.bad} diverging`, `${sm.bad} divergente(s)`));
  const miss = (sm.missing || []).length;
  if (miss) parts.push(T(`${miss} sem resultado (clique Calibrar: a calibração rápida só roda as good)`,
                         `${miss} without result (click Calibrate: the quick calibration only runs the good ones)`,
                         `${miss} sin resultado (haz clic en Calibrar: la calibración rápida solo ejecuta las good)`));
  return parts.join(' · ');
}

// resultado do validador de entrada num juiz (hosts[].validator ou o sumário)
export function validatorText(v) {
  if (!v) return '';
  switch (v.state) {
    case 'none': return T('sem validador de entrada (scripts/validator.cpp)', 'no input validator (scripts/validator.cpp)', 'sin validador de entrada (scripts/validator.cpp)');
    case 'ok': return T(`validador aprovou as ${v.total} entradas`, `validator accepted all ${v.total} inputs`, `el validador aprobó las ${v.total} entradas`);
    case 'invalid': return T(`${v.invalid} de ${v.total} entradas INVÁLIDAS`, `${v.invalid} of ${v.total} inputs INVALID`, `${v.invalid} de ${v.total} entradas INVÁLIDAS`);
    case 'error': return T('o validador não rodou (não compilou?)', 'the validator did not run (did not compile?)', 'el validador no se ejecutó (¿no compiló?)');
    default: return '';
  }
}

// uma pendência do /problems/status (`pending[]`)
export function pendingLabel(code) {
  const [k, arg] = String(code).split(/:(.*)/s);
  const n = +arg || 0;
  switch (k) {
    case 'package_failed': return T('pacote com erro (veja Validação & calibração)', 'package has errors (see Validation & calibration)', 'paquete con error (mira Validación y calibración)');
    case 'package_unchecked': return T('pacote não conferido (clique Validar)', 'package not checked (click Validate)', 'paquete no verificado (haz clic en Validar)');
    case 'uncalibrated': return T('sem calibração', 'not calibrated', 'sin calibrar');
    case 'needs_recalibration': return T('precisa recalibrar', 'needs recalibration', 'necesita recalibración');
    case 'good_no_tl': return T('solução good sem tempo-limite: ', 'good solution without time limit: ', 'solución good sin tiempo límite: ') + (arg || '');
    case 'sols_divergent': return T(`${plural(n, 'solução divergente', 'soluções divergentes')}`, `${n} diverging solution(s)`, `${n} solución(es) divergente(s)`);
    case 'sols_unchecked': return T('soluções não conferidas desde a última edição (clique Calibrar)', 'solutions not checked since the last edit (click Calibrate)', 'soluciones no verificadas desde la última edición (haz clic en Calibrar)');
    case 'inputs_invalid': return T(`${plural(n, 'entrada inválida', 'entradas inválidas')} (validador)`, `${n} invalid input(s) (validator)`, `${n} entrada(s) inválida(s) (validador)`);
    case 'inputs_error': return T('o validador de entrada não rodou', 'the input validator did not run', 'el validador de entrada no se ejecutó');
    case 'issues_open': return T(`${plural(n, 'issue aberta', 'issues abertas')}`, `${n} open issue(s)`, `${n} issue(s) abierta(s)`);
    // NÃO JULGÁVEL com os juízes de hoje (a regra do escalonador, no /problems/status): "código,pedido,teto"
    case 'not_judgeable': {
      const [why, need, max] = String(arg || '').split(',');
      switch (why) {
        case 'memory': return T(`nenhum juiz comporta: MEMLIMITMB=${need} MB e o maior juiz aceita ~${max} MB — as submissões dariam Judge Error (a unidade é MB)`,
          `no judge can run it: MEMLIMITMB=${need} MB and the largest judge accepts ~${max} MB — submissions would get Judge Error (the unit is MB)`,
          `ningún juez lo soporta: MEMLIMITMB=${need} MB y el juez más grande acepta ~${max} MB — los envíos darían Judge Error (la unidad es MB)`);
        case 'cpus': return T(`nenhum juiz tem ${need} CPUs (CPUNEEDED); o maior tem ${max}`,
          `no judge has ${need} CPUs (CPUNEEDED); the largest has ${max}`,
          `ningún juez tiene ${need} CPUs (CPUNEEDED); el más grande tiene ${max}`);
        case 'numa': return T(`nenhum juiz tem ${need} CPUs num mesmo nó NUMA (SAMENUMA=y); o maior nó tem ${max}`,
          `no judge has ${need} CPUs on one NUMA node (SAMENUMA=y); the largest node has ${max}`,
          `ningún juez tiene ${need} CPUs en un mismo nodo NUMA (SAMENUMA=y); el nodo más grande tiene ${max}`);
        case 'langs': return T(`nenhum juiz roda as linguagens do problema (${need})`,
          `no judge runs the problem's languages (${need})`,
          `ningún juez ejecuta los lenguajes del problema (${need})`);
        default: return T('não julgável com os juízes de hoje', 'not judgeable with the current judges', 'no juzgable con los jueces actuales');
      }
    }
    default: return code;
  }
}
