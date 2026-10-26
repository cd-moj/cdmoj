#!/bin/bash
# smoke-judge-gone.sh — report de juiz para problema que NÃO EXISTE MAIS (26/10/2026). Todo restart de agente
# re-reporta o cache inteiro, inclusive problemas apagados ou movidos; o /judge/tl-report respondia 500 (o
# tl_store_record recusava o checksum vazio) e o /judge/calib-report criava run/calib/<id>/ órfão e respondia 200.
# Agora os dois respondem 404 `problem_gone` ANTES de escrever qualquer coisa (o agente novo marca a entrada do
# cache e para de reportar), e a corrida com o delete fecha sob o lock (tl_store_record rc 3).
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; RUN="$(mktemp -d)"; PROBS="$(mktemp -d)"
trap 'rm -rf "$FIX" "$RUN" "$PROBS"' EXIT
source "$HERE/fixture.sh"
: "${MOJTOOLS_DIR:=$(cd "$ROOT/../../mojtools" 2>/dev/null && pwd)}"
export CONTESTSDIR="$FIX" RUNDIR="$RUN" MOJ_PROBLEMS_DIR="$PROBS" TL_STORE_DIR="$RUN/tl" CALIB_DIR="$RUN/calib" \
       CALX_SUM_DIR="$RUN/calib-sum" MOJTOOLS_DIR
mkdir -p "$RUN/tl" "$RUN/calib" "$RUN/secrets" "$FIX/treino/var"; printf 'mojw_smoketest' > "$RUN/secrets/worker.token"
P="$PROBS/col/pa"; mkdir -p "$P/sols/good" "$P/tests/input"; printf 'CALIBRATIONTL=5\n' > "$P/conf"
printf 'int main(){}\n' > "$P/sols/good/a.c"; printf '1\n' > "$P/tests/input/t1"
( cd "$P" && git init -q && git add -A && git -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm init )
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:300}"; ((fail++)); fi; }
J(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD=POST QUERY_STRING="" HTTP_AUTHORIZATION="Bearer mojw_smoketest" bash "$ROUTER" <<<"$2" 2>/dev/null)"
  STATUS="$(printf '%s' "$OUT" | sed -n 's/^Status: \([0-9]*\).*/\1/p' | head -1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
before="$(cd "$RUN" && find . | sort | md5sum)"

echo "== /judge/tl-report de problema apagado: 404 problem_gone, nada gravado =="
J /judge/tl-report '{"host":"juiz1","id":"col#gone","checksum":"abcdef12","tl":{"c":"1","default":"1"}}'
ck "404 problem_gone (era 500)"                 '[[ "$STATUS" == 404 && "$(jq -r .error.code <<<"$BODY")" == problem_gone ]]'
echo "== /judge/calib-report de problema apagado: 404 problem_gone, nenhum diretório =="
J /judge/calib-report '{"host":"juiz1","id":"col#gone","checksum":"abcdef12","log":"x","sols":[]}'
ck "404 problem_gone (era 200)"                 '[[ "$STATUS" == 404 && "$(jq -r .error.code <<<"$BODY")" == problem_gone ]]'
ck "nada criado em run/ pelos dois reports"     '[[ "$(cd "$RUN" && find . | sort | md5sum)" == "$before" ]]'

echo "== problema que existe: segue gravando =="
PV="$(cd "$MOJTOOLS_DIR" && bash tl-checksum.sh --all-sols "$P")"
J /judge/tl-report "$(jq -cn --arg c "$PV" '{host:"juiz1", id:"col#pa", checksum:$c, tl:{c:"0.3", default:"0.3"}}')"
ck "tl-report 200 recorded"                     '[[ "$STATUS" == 200 && "$(jq -r .recorded <<<"$BODY")" == true ]]'
J /judge/calib-report "$(jq -cn --arg c "$PV" '{host:"juiz1", id:"col#pa", checksum:$c, log:"x", sols:[]}')"
ck "calib-report 200"                           '[[ "$STATUS" == 200 && -s "$RUN/calib/col#pa/juiz1.json" ]]'

echo "== a corrida com o delete: pacote some enquanto o report espera o lock =="
source "$ROOT/api/v1/lib/tl-store.sh"
( exec 9>>"$TL_STORE_DIR/col#pa.lock"; flock 9; sleep 2; rm -rf "$P" ) &
sleep 0.5
tl_store_record juiz2 "col#pa" abcdef12 '{"c":"0.4","default":"0.4"}'; rc=$?
wait
ck "tl_store_record rc 3 (o handler responde 404) e não grava o juiz2" '[[ $rc -eq 3 && "$(jq -r ".hosts | has(\"juiz2\")" "$TL_STORE_DIR/col#pa.json")" == false ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
