#!/bin/bash
# smoke-verdict-rule.sh — REGRA DO VEREDICTO por contest (VERDICT_RULE, 09/11/2026; decisão do Ribas pós-LATAM).
#   • Central › Regras (/contest/admin/settings): GET diz `verdict_rule` (ausente do conf = worst); POST first grava
#     VERDICT_RULE=first, worst APAGA a linha (o de sempre), outro valor = 422 verdict_rule_invalid, nada gravado;
#   • criação (/treino/contest-create/create): contest NOVO do icpc nasce com first (os outros modos, worst, salvo first
#     explícito); `verdict_rule:"worst"` explícito não grava;
#   • export leva SEMPRE a regra (worst explícito p/ contest antigo) ⇒ duplicate de contest antigo continua worst e
#     o de um first continua first; template guarda a regra.
# O job (judged/spool-drain) é coberto em smoke-submit-deprio.sh; o juízo, no mojtools (test-final-loop.sh).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS"
NOW="$EPOCHSECONDS"; FUT=$(( NOW + 100000 ))
T="$FIX/treino"; mkdir -p "$T/var/jsons"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=treino\n' > "$T/conf"
fx_user "$T" prof.admin p "Prof"; printf 'CONTEST=treino\nLOGIN=prof.admin\nUSERFULLNAME=Prof\nLOGINAT=1\n' > "$SESS/t-prof"
fx_owners_index "$FIX"
C="$FIX/ct"; mkdir -p "$C/var" "$C/enunciados"
{ printf 'CONTEST_ID=ct\nCONTEST_NAME=Prova\nCONTEST_TYPE=icpc\nCONTEST_PRIORITY=prova\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$((NOW-3600))" "$FUT"; printf "PROBS=( x col#pa Alfa A col#pa )\n"; } > "$C/conf"
printf 'prof.admin\n' > "$C/owner"; printf 'prof.admin\t%s\ticpc\n' "$NOW" > "$C/created-by"
fx_user "$C" ct.admin p "Admin"; printf 'CONTEST=ct\nLOGIN=ct.admin\nUSERFULLNAME=Admin\nLOGINAT=1\n' > "$SESS/c-adm"
call(){ # <path> <method> <body> <token> [query]
  local o; o="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer $4" bash "$ROUTER" <<<"$3" 2>/dev/null)"
  STATUS="$(printf '%s' "$o" | sed -n 's/^Status: \([0-9]*\).*/\1/p' | head -1)"; STATUS="${STATUS:-200}"
  BODY="$(printf '%s' "$o" | awk 'f{print} /^\r?$/{f=1}')"; }
regras(){ call /contest/admin/settings POST "$1" c-adm "contest=ct"; }
vrof(){ grep -m1 '^VERDICT_RULE=' "$FIX/$1/conf" 2>/dev/null | cut -d= -f2-; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: $STATUS ${BODY:0:200}"; ((fail++)); fi; }

echo "== Central › Regras =="
call /contest/admin/settings GET '' c-adm "contest=ct"
ck "contest antigo (sem a linha): worst"          '[[ "$(jq -r .verdict_rule <<<"$BODY")" == worst ]]'
regras '{"verdict_rule":"first"}'
ck "first grava VERDICT_RULE=first"               '[[ "$STATUS" == 200 && "$(vrof ct)" == first ]]'
ck "e aparece no changed"                         '[[ "$(jq -r ".changed | index(\"VERDICT_RULE=first\") != null" <<<"$BODY")" == true ]]'
call /contest/admin/settings GET '' c-adm "contest=ct"
ck "GET devolve first"                            '[[ "$(jq -r .verdict_rule <<<"$BODY")" == first ]]'
regras '{"verdict_rule":"maior"}'
ck "valor estranho: 422, nada gravado"            '[[ "$STATUS" == 422 && "$(jq -r .error.code <<<"$BODY")" == verdict_rule_invalid && "$(vrof ct)" == first ]]'
regras '{"verdict_rule":"worst"}'
ck "worst apaga a linha"                          '[[ "$STATUS" == 200 && -z "$(vrof ct)" ]]'

echo "== criação, export, duplicate, template =="
spec(){ printf '{"id":"%s","name":"%s","mode":"%s","end":%s%s,"problems":[{"problem_id":"a/b","name":"AB"}]}' "$1" "$1" "${MODE:-icpc}" "$FUT" "${2:+,\"verdict_rule\":\"$2\"}"; }
call /treino/contest-create/create POST "$(spec vr1)" t-prof
ck "contest NOVO nasce first"                     '[[ "$STATUS" == 200 && "$(vrof vr1)" == first ]]'
call /treino/contest-create/create POST "$(spec vr2 worst)" t-prof
ck "worst explícito na criação: sem a linha"      '[[ "$STATUS" == 200 && -z "$(vrof vr2)" ]]'
# fora do icpc a nota é o que vale (com STOPWHEN a ordem dos testes muda a nota): o first só entra pedido
MODE=obi call /treino/contest-create/create POST "$(MODE=obi spec vr3)" t-prof
ck "obi sem a chave: nasce worst (sem a linha)"   '[[ "$STATUS" == 200 && -z "$(vrof vr3)" ]]'
call /treino/contest-create/create POST "$(MODE=obi spec vr4 first)" t-prof
ck "obi com first explícito: grava first"         '[[ "$STATUS" == 200 && "$(vrof vr4)" == first ]]'
call /treino/contest-create/export GET '' t-prof "id=ct"
ck "export de contest antigo leva worst explícito" '[[ "$(jq -r ".spec.verdict_rule // .verdict_rule" <<<"$BODY")" == worst ]]'
call /treino/contest-create/duplicate POST '{"from":"ct","id":"ctcopia"}' t-prof
ck "duplicate do antigo continua worst"           '[[ "$STATUS" == 200 && -z "$(vrof ctcopia)" ]]'
call /treino/contest-create/duplicate POST '{"from":"vr1","id":"vr1copia"}' t-prof
ck "duplicate de um first continua first"         '[[ "$STATUS" == 200 && "$(vrof vr1copia)" == first ]]'
call /treino/contest-create/templates POST '{"op":"save","name":"antigo","from_contest":"ct"}' t-prof
call /treino/contest-create/templates GET '' t-prof "name=antigo"
ck "template guarda a regra"                      '[[ "$(jq -r .template.spec.verdict_rule <<<"$BODY")" == worst ]]'

echo "== a info sheet diz a regra (seção 2.1, pt/en/es) =="
INFO(){ ( _DIR="$ROOT/api/v1"; source "$ROOT/api/v1/lib/common.sh" 2>/dev/null; source "$ROOT/api/v1/lib/contest-docs.sh"; _doc_html_infosheet "$1" "$2" ) 2>/dev/null; }
H="$(INFO vr1 pt)"; BODY="${H:0:200}"
ck "first (pt): o primeiro teste que falhou"      '[[ "$H" == *"primeiro teste que falhou"* && "$H" != *"{{VERDICT_RULE}}"* ]]'
H="$(INFO ct pt)"
ck "worst (pt): o mais grave"                     '[[ "$H" == *"mais grave"* ]]'
H="$(INFO vr1 en)"
ck "first (en)"                                   '[[ "$H" == *"first failing test"* ]]'
H="$(INFO vr1 es)"
ck "first (es)"                                   '[[ "$H" == *"primer caso que falló"* ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
