#!/bin/bash
# TEST-RUN — rodar UMA solução avulsa no juiz, p/ autoria (/problems/test-run).
# Garante: gate de EDIÇÃO ponta a ponta (404 opaco), job real na banda lista-privada com o
# contest sentinela _testrun, o judged DESVIA o resultado p/ run/testrun/ (history de
# NINGUÉM é tocado), o GET devolve o vetor tests e o report sai pelo endpoint próprio.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; PROBS="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN" "$PROBS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" \
       MOJ_PROBLEMS_DIR="$PROBS" TL_STORE_DIR="$RUN/tl" \
       SPOOLDIR="$RUN/spool/submissions" SPOOLDONEDIR="$RUN/spool/submissions-done"
mkdir -p "$RUN/tl" "$RUN/secrets" "$SPOOLDIR" "$SPOOLDONEDIR" "$FIX/treino/var"
printf 'mojw_smoketest' > "$RUN/secrets/worker.token"

NOW="$EPOCHSECONDS"
echo '{"col":{"members":["autor"],"admins":[],"public_allowed":true,"title":"Col"}}' > "$FIX/treino/var/orgs.json"
P="$PROBS/col/pa"; mkdir -p "$P/sols/good"
printf 'CALIBRATIONTL=5\n' > "$P/conf"
printf '{"owner":"autor","public":true,"display_title":"PA"}\n' > "$P/.moj-meta.json"
printf 'int main(){return 0;}\n' > "$P/sols/good/sol.c"
fx_user "$FIX/treino" autor s "Autor"
fx_user "$FIX/treino" outro s "Outro"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' treino autor Autor "$NOW" > "$SESS/aut"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' treino outro Outro "$NOW" > "$SESS/out"

pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${4:-}" \
    HTTP_AUTHORIZATION="Bearer $3" bash "$ROUTER" <<<"${5:-}" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }

B64="$(printf 'int main(){return 0;}' | base64 -w0)"

echo "== gate: só quem EDITA roda =="
call /problems/test-run POST out "" "{\"id\":\"col#pa\",\"filename\":\"a.c\",\"code_b64\":\"$B64\"}"
ck "não-membro: 404 opaco"          'grep -q "not_found" <<<"$BODY"'
call /problems/test-run POST aut "" "{\"id\":\"col#pa\",\"filename\":\"a.exe\",\"code_b64\":\"$B64\"}"
ck ".exe recusado (plataforma)"     'grep -q "lang_not_allowed" <<<"$BODY"'

echo "== POST: registro + job na banda lista-privada com sentinela _testrun =="
call /problems/test-run POST aut "" "{\"id\":\"col#pa\",\"filename\":\"a.c\",\"code_b64\":\"$B64\"}"
ck "aceito, run devolvido"          'grep -q "\"status\":\"queued\"" <<<"$BODY"'
RUNID="$(jq -r '.run // empty' <<<"$BODY")"
ck "runid 32-hex"                   '[[ "$RUNID" =~ ^[a-f0-9]{32}$ ]]'
JOB="$(ls "$RUN"/queue/040-lista-privada/*_"$RUNID".json 2>/dev/null | head -1)"
ck "job na banda lista-privada"     '[[ -n "$JOB" ]]'
ck "job leva o sentinela"           '[[ "$(jq -r .contest "$JOB")" == "_testrun" ]]'
ck "fonte inteira no job"           '[[ "$(jq -r ".code_b64 | length" "$JOB")" == "${#B64}" ]]'
ck "registro queued"                '[[ "$(jq -r .status "$RUN/testrun/$RUNID.json")" == "queued" ]]'

echo "== GET: polling (queued) e gate do registro =="
call /problems/test-run GET aut "run=$RUNID"
ck "autor vê o run"                 '[[ "$(jq -r .status <<<"$BODY")" == "queued" ]]'
call /problems/test-run GET out "run=$RUNID"
ck "não-membro: 404 no registro"    'grep -q "not_found" <<<"$BODY"'

echo "== rate: 3 na fila → 429 =="
call /problems/test-run POST aut "" "{\"id\":\"col#pa\",\"filename\":\"b.c\",\"code_b64\":\"$B64\"}"
call /problems/test-run POST aut "" "{\"id\":\"col#pa\",\"filename\":\"c.c\",\"code_b64\":\"$B64\"}"
call /problems/test-run POST aut "" "{\"id\":\"col#pa\",\"filename\":\"d.c\",\"code_b64\":\"$B64\"}"
ck "4º na fila → 429 testrun_busy"  'grep -q "testrun_busy" <<<"$BODY"'

echo "== resultado do juiz: POST /judge/result → judged DESVIA p/ run/testrun =="
RH="$(printf '<html>report do test-run</html>' | base64 -w0)"
RES="$(jq -cn --arg id "$RUNID" --arg rh "$RH" \
  '{host:"juiz1", id:$id, contest:"_testrun", problem_id:"col#pa", login:"autor", lang:"c",
    verdict:"Accepted,100p", verdict_canon:"Accepted", score:100, score_max:100,
    correct:2, total_tests:2, duration_s:0.3, tl_used:0.5,
    tests:[{name:"t1",code:"AC",time:0.12,tl:0.5},{name:"t2",code:"AC",time:0.18,tl:0.5}],
    report_html_b64:$rh}')"
call /judge/result POST mojw_smoketest "" "$RES"
ck "result aceito no spool"         'grep -q "\"accepted\":true" <<<"$BODY"'
( cd "$ROOT/daemons" && SPOOLDIR="$SPOOLDIR" SPOOLDONEDIR="$SPOOLDONEDIR" CONTESTSDIR="$FIX" \
    RUNDIR="$RUN" JUDGE_BACKEND=queue INTAKE_MODE=queue bash judged.sh --drain >/dev/null 2>&1 )
REG="$RUN/testrun/$RUNID.json"
ck "registro virou done"            '[[ "$(jq -r .status "$REG")" == "done" ]]'
ck "verdict no registro"            '[[ "$(jq -r .verdict "$REG")" == "Accepted,100p" ]]'
ck "vetor tests presente"           '[[ "$(jq -r ".tests | length" "$REG")" == 2 ]]'
ck "html_b64 NÃO fica no registro"  '! jq -e .report_html_b64 "$REG" >/dev/null 2>&1'
ck "report.html no disco"           '[[ -s "$RUN/testrun/r/$RUNID.html" ]]'
ck "history do autor INTOCADO"      '[[ ! -s "$FIX/treino/users/autor/history" ]]'
ck "nenhum history de _testrun"     '[[ ! -d "$FIX/_testrun" ]]'

echo "== GET pós-veredicto + report =="
call /problems/test-run GET aut "run=$RUNID"
ck "polling devolve done+tests"     '[[ "$(jq -r .status <<<"$BODY")" == "done" && "$(jq -r ".tests|length" <<<"$BODY")" == 2 ]]'
ck "code do aluno não vaza no GET"  '! jq -e .code_b64 <<<"$BODY" >/dev/null 2>&1'
call /problems/test-run-report GET aut "run=$RUNID"
ck "report servido"                 'grep -q "report do test-run" <<<"$BODY"'
call /problems/test-run-report GET out "run=$RUNID"
ck "report: não-membro 404"         'grep -q "not_found" <<<"$BODY"'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
