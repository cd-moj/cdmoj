#!/bin/bash
# smoke-limits-tab.gjs.sh — a aba LIMITES do editor: os campos do conf são TRI-ESTADO (24/09/2026).
# Chave AUSENTE = o default do juiz (ALLOWPARALLELTEST/TLERERUN ausentes = ligados; STOPWHEN/SAMENUMA
# ausentes = desligados). Antes, um ALLOWPARALLELTEST ausente aparecia DESMARCADO (embora signifique
# ligado) e qualquer clique na aba gravava TODOS os checkboxes como =y/=n explícitos no conf. Cobre
# também o card "Problemas paralelos" (CPUNEEDED/SAMENUMA) — extrai o bloco de conf do editar.js e roda
# num DOM falso (gjs), como o smoke-sols-expect.gjs.sh.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
WEB="$ROOT/web"; W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
command -v gjs >/dev/null 2>&1 || { echo "limits-tab: gjs ausente — pulando"; exit 0; }
{ cat <<'JS'
const FIELDS = {};
function $(id) { return FIELDS[id] || (FIELDS[id] = { value: '', checked: false, hidden: false }); }
JS
  # o bloco de conf: de `const confVal` até antes de `const hiddenFile`
  awk 'index($0,"const confVal = ")==1{f=1} f&&index($0,"const hiddenFile = ")==1{exit} f' "$WEB/problemas/editar.js"
  cat <<'JS'
let PASS=0, FAIL=0; const ck=(n,c)=>{ if (c) PASS++; else { FAIL++; print('FALHOU: '+n); } };
const load = (t) => { $('confRaw').value = t; confToFields(t); };
const save = () => { syncConfFromFields(); return $('confRaw').value; };
const has = (t, k) => confVal(t, k) !== null;

// ---- chave ausente = default do juiz, e salvar sem mexer NÃO grava nada
load('TLMOD[calibrafactor]=1.35\nULIMITS[-u]=10000');
ck('ALLOWPARALLELTEST ausente aparece LIGADO', $('cf_allowparallel').checked === true);
ck('TLERERUN ausente aparece LIGADO', $('cf_tlererun').checked === true);
ck('STOPWHEN_WA ausente aparece desligado', $('cf_stopwa').checked === false);
ck('SAMENUMA ausente aparece desligado', $('cf_samenuma').checked === false);
ck('CPUNEEDED ausente = campo vazio', $('cf_cpuneeded').value === '');
let out = save();
ck('salvar sem mexer não espalha =y/=n (era o bug)', out === 'TLMOD[calibrafactor]=1.35\nULIMITS[-u]=10000');

// ---- desmarcar o que é ligado por default GRAVA =n; marcar o que é desligado GRAVA =y
$('cf_allowparallel').checked = false; out = save();
ck('desmarcar testes em paralelo grava ALLOWPARALLELTEST=n', confVal(out, 'ALLOWPARALLELTEST') === 'n');
$('cf_allowparallel').checked = true; out = save();
ck('marcar de novo mantém a chave explícita (=y), já que ela existia', confVal(out, 'ALLOWPARALLELTEST') === 'y');
$('cf_stopwa').checked = true; out = save();
ck('parar no WA grava STOPWHEN_WA=y', confVal(out, 'STOPWHEN_WA') === 'y');
$('cf_stopwa').checked = false; out = save();
ck('…e desmarcar grava =n (a chave já existia)', confVal(out, 'STOPWHEN_WA') === 'n');

// ---- conf com valores explícitos é respeitado
load('ALLOWPARALLELTEST=n\nTLERERUN=n\nSTOPWHEN_TLE=y');
ck('=n explícito aparece desmarcado', $('cf_allowparallel').checked === false && $('cf_tlererun').checked === false);
ck('STOPWHEN_TLE=y aparece marcado', $('cf_stoptle').checked === true);
out = save();
ck('salvar preserva os três como estavam', confVal(out,'ALLOWPARALLELTEST')==='n' && confVal(out,'TLERERUN')==='n' && confVal(out,'STOPWHEN_TLE')==='y');

// ---- problemas paralelos: CPUNEEDED / SAMENUMA
load('CPUNEEDED=4\nSAMENUMA=y');
ck('CPUNEEDED=4 e SAMENUMA=y lidos', $('cf_cpuneeded').value === '4' && $('cf_samenuma').checked === true);
$('cf_samenuma').checked = false; out = save();
ck('desmarcar SAMENUMA existente grava =n', confVal(out, 'SAMENUMA') === 'n' && confVal(out, 'CPUNEEDED') === '4');
load('');
$('cf_cpuneeded').value = '8'; $('cf_samenuma').checked = true; out = save();
ck('novo problema paralelo: CPUNEEDED=8 e SAMENUMA=y', confVal(out, 'CPUNEEDED') === '8' && confVal(out, 'SAMENUMA') === 'y');
ck('…sem espalhar as outras chaves', !has(out,'ALLOWPARALLELTEST') && !has(out,'TLERERUN') && !has(out,'STOPWHEN_WA'));
$('cf_cpuneeded').value = ''; out = save();
ck('limpar CPUNEEDED remove a linha', !has(out, 'CPUNEEDED'));
$('cf_maxparallel').value = '2'; out = save();
ck('MAXPARALLELTESTS=2 gravado', confVal(out, 'MAXPARALLELTESTS') === '2');
print(`RESULT: ${PASS} passed, ${FAIL} failed`);
JS
} > "$W/t.js"
out="$(gjs "$W/t.js" 2>&1)"; printf '%s\n' "$out"
grep -q 'RESULT: [0-9]* passed, 0 failed' <<<"$out"
