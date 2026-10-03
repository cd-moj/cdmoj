#!/bin/bash
# smoke-dashboard-review.sh — o bloco de AVALIAÇÃO MANUAL do /contest/admin/dashboard (Operação › Situação).
# Levantamento de 03/10/2026 (TCP 2026): o dashboard rodava um jq + rv_quorum POR arquivo de review (o custo que o
# review/list e o review/conflicts já tinham perdido em 25/09) e contava "aguardando" com `votes_n == 1` — certo só
# com quórum 2. Prende: as contagens com quórum 3 (votos abaixo do quórum = aguardando), released fora, conflito,
# claim vencido não conta; e o nº de jq NÃO cresce com a fila (rv_scan, uma passada).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; SHIM="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN" "$SHIM"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
C="$FIX/db"; mkdir -p "$C/var" "$C/review" "$RUN/registry"; NOW=$EPOCHSECONDS; OLD=$((NOW-600))
printf 'CONTEST_ID=db\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nMANUAL_VERDICT=1\nREVIEW_JUDGES=3\n' $((NOW-3600)) $((NOW+3600)) > "$C/conf"
fx_user "$C" db.admin p Admin; fx_user "$C" aluno1 a Aluno
printf 'CONTEST=db\nLOGIN=db.admin\nLOGINAT=1\n' > "$SESS/adm"
mk(){ # <id> <status> <claimants-json> <votes-json>
  printf '{"id":"%s","login":"aluno1","problem_id":"apc#p1","lang":"C","computed_verdict":"Wrong Answer","status":"%s","conflict":false,"created_at":%s,"sub_epoch":%s,"claimants":%s,"votes":%s}' \
    "$1" "$2" "$OLD" "$OLD" "$3" "$4" > "$C/review/$1.json"; }
V(){ printf '{"by":"%s","verdict":"%s","at":%s}' "$1" "$2" "$OLD"; }
mk r-novo   open '[]' '[]'                                                              # não avaliada
mk r-claim  open "[{\"by\":\"j1.judge\",\"at\":$OLD,\"expires_at\":$((NOW+600))}]" '[]'  # sendo avaliada
mk r-venc   open "[{\"by\":\"j2.judge\",\"at\":$OLD,\"expires_at\":$((NOW-60))}]" '[]'   # claim vencido = não avaliada
mk r-1voto  open '[]' "[$(V j1.judge Accepted)]"                                         # 1 de 3: aguardando
mk r-2votos open '[]' "[$(V j1.judge Accepted),$(V j2.judge Accepted)]"                  # 2 de 3: AGUARDANDO (era ignorada)
mk r-confl  open '[]' "[$(V j1.judge Accepted),$(V j2.judge 'Wrong Answer'),$(V j3.judge Accepted)]"   # 3 de 3 divergentes
mk r-solto  released '[]' "[$(V j1.judge Accepted),$(V j2.judge Accepted),$(V j3.judge Accepted)]"     # liberada: fora
printf '#!/bin/bash\necho jq >> "%s/n"\nexec "%s" "$@"\n' "$SHIM" "$(command -v jq)" > "$SHIM/jq"; chmod +x "$SHIM/jq"
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: $(jq -c .review <<<"$BODY" 2>/dev/null | head -c 300)"; ((fail++)); fi; }
dash(){ : > "$SHIM/n"; OUT="$(PATH="$SHIM:$PATH" PATH_INFO=/contest/admin/dashboard REQUEST_METHOD=GET QUERY_STRING=contest=db \
    HTTP_AUTHORIZATION="Bearer adm" CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" bash "$ROUTER" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; NJQ=$(grep -c . "$SHIM/n"); }
R(){ jq -r ".review.$1" <<<"$BODY"; }

echo "== contagens com quórum 3 =="
dash
ck "pendentes: 6 (a liberada fica fora)"            '[[ "$(R pending_total)" == 6 ]]'
ck "não avaliadas: 2 (a nova + a de claim vencido)"  '[[ "$(R not_evaluated)" == 2 ]]'
ck "sendo avaliada: 1"                               '[[ "$(R being_evaluated)" == 1 ]]'
ck "aguardando quórum: 2 (1 e 2 votos de 3)"         '[[ "$(R awaiting_second)" == 2 ]]'
ck "conflito: 1"                                     '[[ "$(R conflicts)" == 1 ]]'
N0=$NJQ

echo "== o nº de jq não cresce com a fila (uma passada) =="
for i in $(seq 1 60); do mk "x$i" open '[]' '[]'; done
dash
ck "66 pendentes"                                    '[[ "$(R pending_total)" == 66 ]]'
ck "60 reviews a mais custam no máx. 2 jq a mais (era 1 por arquivo)" '(( NJQ <= N0 + 2 ))'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
