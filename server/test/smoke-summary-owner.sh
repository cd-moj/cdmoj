#!/bin/bash
# smoke-summary-owner.sh — /submission/summary em LOTE no treino (TCP 2026, 03/10/2026: 9,6 s numa chamada). O
# não-juiz só recebe o resumo DELE; o handler resolvia cada id com 3 globs sobre TODAS as contas (users/*/…).
# Prende: o dono recebe os dele, id alheio é OMITIDO (o mesmo de sempre), o juiz ainda acha de qualquer conta,
# e o lote do dono não depende do nº de contas (3.000 contas, 60 ids: < 1 s).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
C="$FIX/tr"; mkdir -p "$C/var"
printf 'CONTEST_ID=tr\nCONTEST_TYPE=treino\nCONTEST_START=1\nCONTEST_END=99999999999\nSHOWLOG=1\n' > "$C/conf"
for i in $(seq 1 3000); do mkdir -p "$C/users/u$i/results"; done
fx_user "$C" aluno a Aluno; fx_user "$C" outro o Outro; fx_user "$C" tr.admin p Admin
res(){ mkdir -p "$C/users/$1/results"; printf '{"id":"%s","verdict":"Accepted","verdict_canon":"Accepted","correct":3,"total_tests":3}' "$2" > "$C/users/$1/results/$2.json"; }
IDS=""; for i in $(seq 1 60); do id="$(printf '%032x' "$i")"; res aluno "$id"; IDS+="${IDS:+,}$id"; done
ALHEIO="$(printf '%032x' 999)"; res outro "$ALHEIO"
printf 'CONTEST=tr\nLOGIN=aluno\nLOGINAT=1\n' > "$SESS/al"; printf 'CONTEST=tr\nLOGIN=tr.admin\nLOGINAT=1\n' > "$SESS/adm"
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200} (${MS}ms)"; ((fail++)); fi; }
sum(){ local t0=$EPOCHREALTIME; OUT="$(PATH_INFO=/submission/summary REQUEST_METHOD=GET QUERY_STRING="contest=tr&ids=$2" \
    HTTP_AUTHORIZATION="Bearer $1" CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" 2>&1)"
  MS=$(( (${EPOCHREALTIME/./} - ${t0/./}) / 1000 )); BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }

sum al "$IDS,$ALHEIO"
ck "dono: os 60 resumos dele"                  '[[ "$(jq "keys|length" <<<"$BODY")" == 60 ]]'
ck "id alheio: omitido"                        '[[ "$(jq --arg a "$ALHEIO" "has(\$a)" <<<"$BODY")" == false ]]'
ck "3.000 contas, 60 ids: < 1 s"               '(( MS < 1000 ))'
sum adm "$ALHEIO"
ck "admin: acha o de qualquer conta"           '[[ "$(jq --arg a "$ALHEIO" "has(\$a)" <<<"$BODY")" == true ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
