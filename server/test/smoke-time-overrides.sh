#!/bin/bash
# Prorrogação de vigência por sede/grupo (contests/<c>/time-overrides.json):
# a 1ª regra {regex,end} que casa com o login ESTENDE o fim do contest só p/ aquele grupo
# (contest_end_effective em lib/contest-gate.sh). Exercita: /submit após o fim global
# (grupo prorrogado = aceito; fora = 403 contest_ended), /contest/basic personalizado
# (countdown), e o admin GET/POST /contest/admin/time-overrides (validação + auditoria).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; SPOOL="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$SPOOL"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"

NOW="$EPOCHSECONDS"
C="$FIX/tov"; mkdir -p "$C/var"
# contest começou há 2h e o fim GLOBAL foi há 10 min; prorrogação dá +30 min à sede1
{ printf 'CONTEST_ID=tov\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nUSER_STORE=v2\n' \
    $(( NOW - 7200 )) $(( NOW - 600 ))
  printf "PROBS=(f0 col/pa 'Prob A' A 'col#pa')\n"; } > "$C/conf"
fx_user "$C" tov.admin p "Admin"
fx_user "$C" sede1-alfa a "Alfa"
fx_user "$C" sede2-beta b "Beta"
printf '[{"regex":"^sede1-","end":%s,"reason":"queda de energia sede 1"}]\n' $(( NOW + 1800 )) \
  > "$C/time-overrides.json"

mktok(){ printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' tov "$1" "$1" "$NOW" > "$SESS/$2"; }
mktok tov.admin t-adm; mktok sede1-alfa t-s1; mktok sede2-beta t-s2

call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${4:-}" \
    HTTP_AUTHORIZATION="${3:+Bearer $3}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" SPOOLDIR="$SPOOL" bash "$ROUTER" <<<"${5:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${OUT:0:200}"; ((fail++)); fi; }
SUB='{"problem_id":"col#pa","filename":"a.c","code_b64":"aW50IG1haW4oKXt9"}'

echo "== submit após o fim global =="
call /submit POST t-s1 'contest=tov' "$SUB"
ck "sede1 (prorrogada) submete"   '[[ "$(jq -r .status <<<"$BODY")" == "queued" ]]'
call /submit POST t-s2 'contest=tov' "$SUB"
ck "sede2 recebe 403 contest_ended" '[[ "$OUT" == *"Status: 403"* && "$(jq -r .error.code <<<"$BODY")" == "contest_ended" ]]'

echo "== countdown personalizado (/contest/basic) =="
call /contest/basic GET t-s1 'contest=tov'
ck "sede1 vê o fim prorrogado"    '[[ "$(jq -r .end_time <<<"$BODY")" == "$(( NOW + 1800 ))" ]]'
call /contest/basic GET t-s2 'contest=tov'
ck "sede2 vê o fim global"        '[[ "$(jq -r .end_time <<<"$BODY")" == "$(( NOW - 600 ))" ]]'
call /contest/basic GET '' 'contest=tov'
ck "sem token vê o fim global"    '[[ "$(jq -r .end_time <<<"$BODY")" == "$(( NOW - 600 ))" ]]'

echo "== admin GET/POST /contest/admin/time-overrides =="
call /contest/admin/time-overrides GET t-adm 'contest=tov'
ck "GET lista a regra"            '[[ "$(jq -r ".rules|length" <<<"$BODY")" == 1 && "$(jq -r .rules[0].regex <<<"$BODY")" == "^sede1-" ]]'
call /contest/admin/time-overrides POST t-adm 'contest=tov' \
  "{\"rules\":[{\"regex\":\"^sede2-\",\"end\":$(( NOW + 900 )),\"reason\":\"sede 2 tb\"}]}"
ck "POST substitui as regras"     '[[ "$(jq -r .saved <<<"$BODY")" == "true" && "$(jq -r ".rules|length" <<<"$BODY")" == 1 ]]'
call /submit POST t-s2 'contest=tov' "$SUB"
ck "sede2 agora submete"          '[[ "$(jq -r .status <<<"$BODY")" == "queued" ]]'
call /submit POST t-s1 'contest=tov' "$SUB"
ck "sede1 perdeu a prorrogação (403)" '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/admin/time-overrides POST t-adm 'contest=tov' '{"rules":[{"regex":"(","end":99}]}'
ck "regra inválida some na limpeza ou 422" '[[ "$OUT" == *"Status: 422"* || "$(jq -r ".rules|length" <<<"$BODY")" == 0 ]]'
call /contest/admin/time-overrides GET t-s1 'contest=tov'
ck "não-admin 403"                '[[ "$OUT" == *"Status: 403"* ]]'
ck "auditoria registra"           'grep -q time-overrides "$C/var/admin-audit.log"'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
