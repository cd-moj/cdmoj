#!/bin/bash
# /contest/admin/ua-gate — os MODOS e a recusa de gate sem regra (TCP 2026, 03/10/2026: sem ua-gate.json o painel
# dizia "ativo — o login devolve 403" e ninguém era barrado, nem a sessão única valia; o organizador achou que o
# gate funcionava). GET diz `configured` e `has_rule`; ligar (enforce/observe) sem nenhuma regra = 422.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
C="$FIX/ug"; mkdir -p "$C/var"
printf 'CONTEST_ID=ug\nCONTEST_TYPE=icpc\nCONTEST_START=1\nCONTEST_END=%s\n' $(( EPOCHSECONDS + 9000 )) > "$C/conf"
fx_user "$C" ug.admin p Admin; fx_user "$C" ug.cjudge p Chefe; fx_user "$C" teamabc001 a Time
for l in ug.admin ug.cjudge; do printf 'CONTEST=ug\nLOGIN=%s\nLOGINAT=1\n' "$l" > "$SESS/t-$l"; done
call(){ OUT="$(PATH_INFO=/contest/admin/ua-gate REQUEST_METHOD="$1" QUERY_STRING="contest=ug${3:-}" \
    HTTP_AUTHORIZATION="Bearer ${4:-t-ug.admin}" CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${2:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:220}"; ((fail++)); fi; }

echo "== sem ua-gate.json: nada configurado, nenhuma regra =="
call GET
ck "configured:false e has_rule:false"   '[[ "$(jq -r .configured <<<"$BODY")" == false && "$(jq -r .has_rule <<<"$BODY")" == false ]]'

echo "== ligar SEM regra é recusado (nos dois modos ligados) =="
call POST '{"action":"set","mode":"enforce"}'
ck "enforce sem regra → 422 gate_no_rule" '[[ "$OUT" == *"Status: 422"* && "$(jq -r .error.code <<<"$BODY")" == gate_no_rule && ! -e "$C/ua-gate.json" ]]'
call POST '{"action":"set","mode":"observe","exempt":["^x"]}'
ck "observe só com isento → 422"         '[[ "$OUT" == *"Status: 422"* && "$(jq -r .error.code <<<"$BODY")" == gate_no_rule ]]'
call POST '{"action":"set","mode":"off"}'
ck "off sem regra: grava (escolha)"      '[[ "$(jq -r .gate.mode <<<"$BODY")" == off && -s "$C/ua-gate.json" ]]'
call GET
ck "agora configured:true"               '[[ "$(jq -r .configured <<<"$BODY")" == true && "$(jq -r .has_rule <<<"$BODY")" == false ]]'

echo "== observar =="
call POST '{"action":"set","mode":"observe","from_login":{"regex":"^team([a-z]{3})[0-9]{3}$","expect":"img-\\1"}}'
ck "observe com regra: gravado"          '[[ "$(jq -r .gate.mode <<<"$BODY")" == observe && "$(jq -r .mode "$C/ua-gate.json")" == observe ]]'
ck "e liga o módulo maquinas"            'grep -q "maquinas" "$C/conf"'
call GET '' '&login=teamabc001'
ck "observe resolve o esperado (painel)" '[[ "$(jq -r .check.expected <<<"$BODY")" == img-abc && "$(jq -r .has_rule <<<"$BODY")" == true ]]'
call POST '{"action":"set","mode":"bloquear"}'
ck "modo desconhecido → 422"             '[[ "$OUT" == *"Status: 422"* && "$(jq -r .error.code <<<"$BODY")" == mode_invalid ]]'

echo "== o LOGIN_UA_SUBSTRING legado conta como regra =="
rm -f "$C/ua-gate.json"; printf 'LOGIN_UA_SUBSTRING=MOJBOX\n' >> "$C/conf"
call GET
ck "legado: has_rule:true"               '[[ "$(jq -r .has_rule <<<"$BODY")" == true && "$(jq -r .configured <<<"$BODY")" == false ]]'
call POST '{"action":"set","mode":"enforce"}'
ck "legado: enforce sem regra no arquivo grava" '[[ "$(jq -r .gate.mode <<<"$BODY")" == enforce ]]'

echo "== quem pode =="
call POST '{"action":"set","mode":"off"}' '' t-ug.cjudge
ck "juiz-chefe não grava (403)"          '[[ "$OUT" == *"Status: 403"* ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
