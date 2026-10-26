#!/bin/bash
# smoke-save-recalib.gjs.sh — SALVAR RECALIBRA (26/10/2026): um save (ou um envio de pacote) que muda a VERSÃO do
# pacote num problema já calibrado faz o editor pedir a calibração sozinho (recalibIfOutdated, web/problemas/editar.js).
# Antes o "aplicar" da simulação + Salvar deixava o problema "desatualizado" sem nada na fila. Casos: versão mudou
# (pede nos juízes que tinham calibrado e estão online), não mudou, nunca calibrado, juízes offline (um juiz livre),
# calibração em voo sem cartão, resposta nula do pós-save e o POST que falha. Extrai as funções e roda no gjs.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
JS="$ROOT/web/problemas/editar.js"; W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
command -v gjs >/dev/null 2>&1 || { echo "save-recalib: gjs ausente — pulando"; exit 0; }
ex(){ awk -v a="$1" -v b="$2" 'index($0,a)==1{f=1} f&&index($0,b)==1&&!index($0,a){exit} f' "$JS"; }
blk="$(ex '// ---- SALVAR RECALIBRA' 'async function newDir(')"
[[ "$blk" == *"function calibSnapshot()"* && "$blk" == *"async function recalibIfOutdated("* ]] \
  || { echo "FAIL: o bloco SALVAR RECALIBRA não foi achado no editar.js"; exit 1; }
# o loadValidation devolve o calib que ELE buscou (o salvar compara com ele, não com o LASTCALIB global)
lv="$(ex 'async function loadValidation()' '// dispara Calibrar/Validar')"
lvok=0; grep -q '^  return calib;$' <<<"$lv" && lvok=1
# o salvar e o envio de pacote tiram a foto ANTES e comparam DEPOIS
sv="$(ex 'async function save(' 'async function act(')"; up="$(ex 'async function uploadTar(' '// ---- compartilhamento')"
svok=0; grep -q 'const prev = (MODE === .edit.) ? calibSnapshot() : null;' <<<"$sv" \
  && grep -q 'loadValidation().then((cal) => recalibIfOutdated(prev, cal' <<<"$sv" && svok=1
upok=0; grep -q 'const prev = ID ? calibSnapshot() : null;' <<<"$up" \
  && grep -q 'recalibIfOutdated(prev, cal, done)' <<<"$up" && [[ "$(grep -o 'after();' <<<"$up" | wc -l)" -eq 2 ]] && upok=1
{ cat <<'JS'
let ID = 'org#p', CONTEST = 'treino', RUNNING = '', CALIB_LIVE = [], LASTCALIB = null, JUDGES = [];
const calibRunning = () => CALIB_LIVE.length > 0;
let MSG = '', CLS = ''; const setMsg = (t, c) => { MSG = t; CLS = c; };
function T(pt) { return pt; }
let POSTS = [], POSTFAIL = null;
async function apiPost(path, body) { if (POSTFAIL) throw new Error(POSTFAIL); POSTS.push({ path, body }); return { status: 'queued' }; }
let NRV = 0, NSP = 0; const renderVal = () => { NRV++; }, updateReady = () => {}, startPolling = () => { NSP++; };
JS
  printf '%s\n' "$blk"
  cat <<'JS'
let fail = 0, pass = 0; const ck = (n, c) => { if (c) pass++; else { fail++; print('  FAIL: ' + n); } };
const reset = () => { POSTS = []; POSTFAIL = null; RUNNING = ''; CALIB_LIVE = []; MSG = ''; CLS = ''; NRV = NSP = 0; };
const judges = (...on) => [{ host: 'judge', online: on.includes('judge') }, { host: 'judge-sp1', online: on.includes('judge-sp1') },
                           { host: 'goiabada-judge', online: on.includes('goiabada-judge') }];
async function main() {
  // 1) calibrado em dois juízes online; o save mudou a versão: pede NOS DOIS (não no terceiro, que nunca calibrou)
  reset(); JUDGES = judges('judge', 'judge-sp1', 'goiabada-judge');
  LASTCALIB = { version: 'v1', hosts: [{ host: 'judge' }, { host: 'judge-sp1' }] };
  let prev = calibSnapshot();
  ck('foto antes do save: versão e juízes', prev && prev.version === 'v1' && prev.hosts.join() === 'judge,judge-sp1');
  let r = await recalibIfOutdated(prev, { version: 'v2', hosts: [] }, 'Salvo ✓');
  ck('versão mudou: pede a calibração', r === true && POSTS.length === 1 && POSTS[0].path === '/problems/request-calibration');
  ck('…nos juízes que tinham calibrado e estão online', JSON.stringify(POSTS[0].body) === JSON.stringify({ id: 'org#p', hosts: ['judge', 'judge-sp1'] }));
  ck('…e acompanha (RUNNING, painel, polling)', RUNNING === 'calibrate' && NRV === 1 && NSP === 1);
  ck('…dizendo onde', MSG.startsWith('Salvo ✓ — a mudança desatualizou a calibração: recalibrando em judge, judge-sp1') && CLS === 'v-ok');
  // 2) versão igual (enunciado, só o TLMETHOD): nada
  reset(); r = await recalibIfOutdated(prev, { version: 'v1', hosts: [] }, 'Salvo ✓');
  ck('versão igual: não pede nada', r === false && POSTS.length === 0 && RUNNING === '' && MSG === '');
  // 3) nunca calibrado: segue manual (Calibrar/Validar)
  reset(); LASTCALIB = { version: 'v1', hosts: [] };
  ck('nunca calibrado: sem foto', calibSnapshot() === null);
  r = await recalibIfOutdated(calibSnapshot(), { version: 'v2', hosts: [] }, 'Salvo ✓');
  ck('…e nada pedido', r === false && POSTS.length === 0);
  // 4) os juízes que calibraram estão offline (ou saíram do parque): um juiz livre, como o "Calibrar"
  reset(); JUDGES = judges('goiabada-judge'); LASTCALIB = { version: 'v1', hosts: [{ host: 'judge' }, { host: 'velho' }] };
  r = await recalibIfOutdated(calibSnapshot(), { version: 'v2', hosts: [] }, 'Salvo ✓');
  ck('juízes offline: pedido global (sem hosts)', r === true && JSON.stringify(POSTS[0].body) === JSON.stringify({ id: 'org#p' }));
  ck('…e diz "num juiz livre"', MSG.includes('recalibrando num juiz livre'));
  // 5) calibração em voo e nenhum cartão ainda: o save mudou a versão — pede de novo (a em voo é da versão velha)
  reset(); JUDGES = judges('judge'); CALIB_LIVE = [{ host: 'judge' }]; LASTCALIB = { version: 'v1', hosts: [] };
  prev = calibSnapshot();
  ck('em voo sem cartão: tem foto', prev && prev.hosts.length === 0);
  r = await recalibIfOutdated(prev, { version: 'v2', hosts: [] }, 'Salvo ✓');
  ck('…e pede (global)', r === true && POSTS.length === 1 && !('hosts' in POSTS[0].body));
  // 6) o GET pós-save falhou (cal nulo) ou o servidor é antigo (sem version): não adivinha
  reset(); LASTCALIB = { version: 'v1', hosts: [{ host: 'judge' }] };
  ck('pós-save sem resposta: nada', (await recalibIfOutdated(calibSnapshot(), null, 'Salvo ✓')) === false && POSTS.length === 0);
  ck('servidor sem version: nada', (await recalibIfOutdated(calibSnapshot(), { hosts: [] }, 'Salvo ✓')) === false && POSTS.length === 0);
  reset(); LASTCALIB = { hosts: [{ host: 'judge' }] };
  ck('foto sem version: nula', calibSnapshot() === null);
  // 7) o POST falhou: diz que salvou e manda clicar Calibrar; não finge que está calibrando
  reset(); JUDGES = judges('judge'); LASTCALIB = { version: 'v1', hosts: [{ host: 'judge' }] }; POSTFAIL = 'HTTP 500';
  r = await recalibIfOutdated(calibSnapshot(), { version: 'v2', hosts: [] }, 'Pacote enviado e recarregado ✓');
  ck('POST falhou: mensagem de erro com o que fazer', r === false && CLS === 'error'
     && MSG.startsWith('Pacote enviado e recarregado ✓, mas o pedido de recalibração falhou (HTTP 500)') && MSG.includes('Clique “Calibrar”'));
  ck('…sem RUNNING nem polling', RUNNING === '' && NSP === 0);
  // 8) sem id (problema novo): sem foto
  reset(); ID = ''; LASTCALIB = { version: 'v1', hosts: [{ host: 'judge' }] };
  ck('sem id: sem foto', calibSnapshot() === null); ID = 'org#p';
}
const loop = new imports.gi.GLib.MainLoop(null, false);
main().catch(e => { print('  FAIL: exceção ' + e + ' ' + (e && e.stack)); fail++; }).finally(() => loop.quit());
loop.run();
print(`RESULT: ${pass} passed, ${fail} failed`);
if (fail) imports.system.exit(1);
JS
} > "$W/t.js"
out="$(gjs "$W/t.js" 2>&1)"; printf '%s\n' "$out"
(( lvok )) && echo "  ok: o loadValidation devolve o calib que buscou" || echo "  FAIL: o loadValidation não devolve o calib"
(( svok )) && echo "  ok: o salvar tira a foto antes e compara depois" || echo "  FAIL: o salvar não chama o recalibIfOutdated"
(( upok )) && echo "  ok: o envio de pacote (e o reenvio do conflito) também" || echo "  FAIL: o envio de pacote não chama o recalibIfOutdated"
grep -q 'RESULT: [0-9]* passed, 0 failed' <<<"$out" && (( lvok && svok && upok ))
