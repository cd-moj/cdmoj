#!/bin/bash
# smoke-score-prestart.sh — REGRA: o placar nunca revela a quantidade de problemas antes de a
# competição começar. Antes do CONTEST_START, /contest/score serve a VITRINE
# (var/placar-prestart.txt: times com bandeira/sigla/nome, ZERO colunas de problema);
# `is_judge` segue no placar completo; começou = placar de sempre. Da mesma família:
# /index/contests emite problems_count=0 para contest `upcoming`.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" SCOREDIR="$ROOT/score" RUNDIR="$RUN"
NOW="$(date +%s)"

C="$FIX/esq"; mkdir -p "$C/var"
conf(){ # <start> <end>
  { printf 'CONTEST_ID=esq\nCONTEST_NAME="Esquenta"\nCONTEST_TYPE=icpc\n'
    printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$1" "$2"
    printf 'PROBS=( cdmoj org#alfa Alfa W1 org#alfa cdmoj org#beta Beta W2 org#beta )\n'; } > "$C/conf"
}
conf "$((NOW+3600))" "$((NOW+10800))"
fx_user "$C" macacos s3nha "3 macacos"
fx_user "$C" esq.admin adm "Admin"
jq -c '.team={univ_short:"UFSC",flag:"br-sc"}' "$C/users/macacos/account.json" > "$C/users/macacos/account.json.t" \
  && mv "$C/users/macacos/account.json.t" "$C/users/macacos/account.json"

mkses(){ printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=1\n' "$2" "$3" "$3" > "$SESS/$1"; }
mkses tok-adm esq esq.admin
mkses tok-mac esq macacos

# call <path> [token]
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD=GET QUERY_STRING="contest=esq" \
    HTTP_AUTHORIZATION="Bearer ${2:-}" bash "$ROUTER" </dev/null 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:170}"; ((fail++)); fi; }
hdr(){ printf '%s' "$BODY" | sed -n 2p; }

echo "== antes do início: vitrine sem colunas de problema =="
call /contest/score
ck "modo icpc"                        '[[ "$(printf "%s" "$BODY" | sed -n 1p)" == icpc ]]'
ck "header SEM W1/W2"                 '[[ "$(hdr)" != *:W1:* && "$(hdr)" != *:W2:* ]]'
ck "header ainda tem Total"           '[[ "$(hdr)" == *:Total:* ]]'
ck "time listado (vitrine)"           '[[ "$BODY" == *macacos* ]]'
ck "bandeira na 1ª coluna"            '[[ "$BODY" == *"br-sc:macacos:UFSC:"* ]]'
ck "papel esq.admin fora da vitrine"  '[[ "$BODY" != *esq.admin* ]]'
ck "placar-prestart.txt materializado" '[[ -f "$C/var/placar-prestart.txt" ]]'

echo "== competidor logado também não vê (corte é por papel, não por sessão) =="
call /contest/score tok-mac
ck "logado comum: header sem W1"      '[[ "$(hdr)" != *:W1:* ]]'

echo "== juiz/admin vê o placar completo antes do início =="
call /contest/score tok-adm
ck "admin: header com W1 e W2"        '[[ "$(hdr)" == *:W1:*  && "$(hdr)" == *:W2:* ]]'

echo "== /index/contests: upcoming não revela problems_count =="
call /index/contests
ck "upcoming problems_count==0"       '[[ "$(jq -r ".upcoming[]|select(.id==\"esq\").problems_count" <<<"$BODY" 2>/dev/null)" == 0 ]]'

echo "== começou: placar de sempre para todos =="
conf "$((NOW-60))" "$((NOW+10800))"
rm -f "$C/var/placar.txt"
call /contest/score
ck "anônimo pós-início: header com W1" '[[ "$(hdr)" == *:W1:* ]]'
call /index/contests
ck "aberto problems_count==2"          '[[ "$(jq -r ".open[]|select(.id==\"esq\").problems_count" <<<"$BODY" 2>/dev/null)" == 2 ]]'

echo; echo "passed=$pass failed=$fail"
(( fail == 0 ))
