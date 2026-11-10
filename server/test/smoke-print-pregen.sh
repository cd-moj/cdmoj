#!/bin/bash
# smoke-print-pregen.sh — PRÉ-GERAÇÃO da folha (lib/print.sh pr_pregen_bg, 09/11/2026): a tarefa nasce e a folha
# (PDF combinado do pedido, folha do balão) já fica pronta no cache, antes de a estação pedir.
#   · pedido de impressão (/contest/print): com PR_PREGEN_SYNC=1 o .combined.pdf existe logo depois do POST;
#   · PRINT_PREGEN=n no conf: nada é pré-gerado (o clique gera, como antes);
#   · MOJ_JOBS_SYNC=1 sem PR_PREGEN_SYNC: não pré-gera (os smokes de balão não renderizam PDF à toa);
#   · destacado de verdade (sem MOJ_JOBS_SYNC): o PDF aparece sozinho em poucos segundos e a rota respondeu antes;
#   · balão novo do reconcile: a folha do lote sai pronta;
#   · tarefa de teste (/contest/staff/test-tasks): o lote sai pronto (mede a MESMA cadeia das reais).
# Precisa da cadeia de impressão (paps, ghostscript, pdfunite, magick): sem ela, pula.
set -u
for b in paps ps2pdf pdfinfo pdfunite magick; do
  command -v "$b" >/dev/null 2>&1 || { echo "SKIP: falta '$b' (a cadeia de impressão)"; exit 0; }
done
export BALLOON_RECONCILE_FLOOR_S=0
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN"
NOW="$EPOCHSECONDS"; T0=$((NOW-3600))
C="$FIX/pg"; P="$C/print-requests"; mkdir -p "$C/var" "$P"
conf(){ { printf 'CONTEST_ID=pg\nCONTEST_TYPE=icpc\nCONTEST_MODULES=sedes,baloes\nCONTEST_START=%s\nCONTEST_END=%s\nUSER_STORE=v2\n' "$T0" "$((NOW+3600))"
          printf 'PROBS=( cdmoj apc#p1 Um A apc#p1 )\n'; [[ -n "${1:-}" ]] && printf '%s\n' "$1"; } > "$C/conf"; }
conf ""
fx_user "$C" pg.admin p "Admin"; fx_user "$C" sala.staff p "Staff"; fx_user "$C" time1 x "Time 1"
for p in "pg.admin adm" "time1 t1"; do set -- $p
  printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' pg "$1" "$1" "$NOW" > "$SESS/$2"; done
call(){ # <path> <method> <token> [body] [env…]
  local b="${4:-}" path="$1" m="$2" tok="$3"; shift 4 2>/dev/null || shift 3
  OUT="$(env "$@" PATH_INFO="$path" REQUEST_METHOD="$m" QUERY_STRING="contest=pg" HTTP_AUTHORIZATION="Bearer $tok" \
    CONTENT_LENGTH="${#b}" REMOTE_ADDR=127.0.0.9 TEAM_HOST_LOCK=0 bash "$ROUTER" <<<"$b" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
SRC_B64="$(printf '#include <stdio.h>\nint main(void){ puts("oi"); return 0; }\n' | base64 -w0)"
req(){ call /contest/print POST t1 "{\"filename\":\"a.c\",\"file_b64\":\"$SRC_B64\"}" "$@"; ID="$(jq -r '.id // empty' <<<"$BODY")"; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }

echo "== pedido de impressão =="
req MOJ_JOBS_SYNC=1 PR_PREGEN_SYNC=1
ck "criou o pedido"                                '[[ -n "$ID" && -f "$P/$ID.json" ]]'
ck "o PDF já está pronto (pré-gerado)"             '[[ -s "$P/$ID.combined.pdf" ]]'
ck "e o meta tem as páginas"                       '[[ "$(jq -r .pages "$P/$ID.json")" -ge 1 ]]'
req MOJ_JOBS_SYNC=1
ck "MOJ_JOBS_SYNC sem PR_PREGEN_SYNC: não pré-gera" '[[ -n "$ID" && ! -e "$P/$ID.combined.pdf" ]]'
conf 'PRINT_PREGEN=n'; req MOJ_JOBS_SYNC=1 PR_PREGEN_SYNC=1
ck "PRINT_PREGEN=n: não pré-gera"                  '[[ -n "$ID" && ! -e "$P/$ID.combined.pdf" ]]'
conf ""
t0=$EPOCHSECONDS; req; dt=$(( EPOCHSECONDS - t0 ))
ck "destacado: a rota respondeu sem esperar"       '[[ -n "$ID" ]] && (( dt <= 3 ))'
for i in $(seq 1 40); do [[ -s "$P/$ID.combined.pdf" ]] && break; sleep 0.5; done
ck "…e o PDF aparece sozinho"                      '[[ -s "$P/$ID.combined.pdf" ]]'
ck "sem erro registrado"                           '[[ ! -s "$RUN/print-pregen.err" ]]'

echo "== balão novo (reconcile) =="
source "$ROOT/api/v1/lib/verdict.sh"; source "$ROOT/api/v1/lib/users.sh"
printf '%s\n' "$((T0+600)):apc#p1:C:Accepted,100p:$((T0+600)):s1" > "$C/users/time1/history"; metrics_recompute pg time1
sleep 1; touch "$C/var/.score-dirty"
call /contest/staff/queue GET adm '' MOJ_JOBS_SYNC=1 PR_PREGEN_SYNC=1
BID="$(jq -r '[.requests[] | select(.kind == "balloon")][0].id // empty' <<<"$BODY")"
ck "a tarefa de balão nasceu"                      '[[ -n "$BID" ]]'
ck "e a folha dela já está pronta"                 '[[ -s "$P/$BID.combined.pdf" ]]'

echo "== tarefa de teste =="
sed -i "s/^CONTEST_START=.*/CONTEST_START=$((NOW+3600))/; s/^CONTEST_END=.*/CONTEST_END=$((NOW+7200))/" "$C/conf"
call /contest/staff/test-tasks POST adm '{"action":"create","count":2,"kind":"mixed","pages":1}' MOJ_JOBS_SYNC=1 PR_PREGEN_SYNC=1
ck "criou o lote"                                  '[[ "$(jq -r .success <<<"$BODY")" == true ]]'
n=0; for f in "$P"/tst*.json; do id="${f##*/}"; id="${id%.json}"; [[ -s "$P/$id.combined.pdf" ]] && n=$((n+1)); done
ck "as 2 tarefas de teste saem prontas"            '(( n == 2 ))'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
