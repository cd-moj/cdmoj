#!/bin/bash
# CALIB-SOLS — o vetor estruturado da calibração (por solução executada, teste a teste).
# Garante: o /judge/calib-report aceita `sols` (projeção FECHADA — campo desconhecido morre
# na borda), o /problems/calib o serve por host, e o RE-ENVIO DE BOOT do agente (sem sols,
# sem reports, mesmo checksum) PRESERVA o que já estava — checksum novo zera.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; PROBS="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN" "$PROBS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" \
       MOJ_PROBLEMS_DIR="$PROBS" TL_STORE_DIR="$RUN/tl" CALIB_DIR="$RUN/calib"
mkdir -p "$RUN/tl" "$RUN/calib" "$RUN/secrets" "$FIX/treino/var"
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
post(){ OUT="$(PATH_INFO=/judge/calib-report REQUEST_METHOD=POST \
    HTTP_AUTHORIZATION="Bearer mojw_smoketest" bash "$ROUTER" <<<"$1" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
getcalib(){ OUT="$(PATH_INFO=/problems/calib REQUEST_METHOD=GET QUERY_STRING="id=col%23pa" \
    HTTP_AUTHORIZATION="Bearer $1" bash "$ROUTER" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }

SOLS='[{"file":"sol.c","lang":"c","category":"good","verdict":"Accepted,100p",
        "tests":[{"name":"t1","code":"AC","time":0.12,"tl":5},{"name":"t2","code":"AC","time":"0.2","tl":5}],
        "campo_estranho":"não pode passar"}]'
RH="$(printf '<html>report</html>' | base64 -w0)"

echo "== POST com sols + report: grava com projeção fechada =="
post "$(jq -cn --argjson s "$SOLS" --arg rh "$RH" \
  '{host:"juiz1", id:"col#pa", checksum:"aabbccdd", log:"AC solutions:\nsol.c:\n 0.12 0.2",
    reports:[{name:"good-sol.c", html_b64:$rh}], sols:$s}')"
ck "aceito"                          'grep -q "\"recorded\":true" <<<"$BODY"'
F="$RUN/calib/col#pa/juiz1.json"
ck "sols persistido"                 '[[ "$(jq -r ".sols | length" "$F")" == 1 ]]'
ck "tests estruturados (2, time numérico)" '[[ "$(jq -r ".sols[0].tests | length" "$F")" == 2 && "$(jq -r ".sols[0].tests[1].time" "$F")" == "0.2" ]]'
ck "campo desconhecido MORREU na borda" '! jq -e ".sols[0].campo_estranho" "$F" >/dev/null 2>&1'
ck "report html no disco"            '[[ -s "$RUN/calib/col#pa/r/juiz1/good-sol.c.html" ]]'

echo "== GET /problems/calib serve sols por host (gate de edição) =="
getcalib aut
ck "autor vê sols"                   '[[ "$(jq -r ".hosts[0].sols | length" <<<"$BODY")" == 1 ]]'
ck "log texto continua"              'jq -e ".hosts[0].log" <<<"$BODY" >/dev/null'
getcalib out
ck "não-membro: 404 opaco"           'grep -q "not_found" <<<"$BODY"'

echo "== re-envio de BOOT (sem sols/reports, MESMO checksum) preserva =="
post '{"host":"juiz1","id":"col#pa","checksum":"aabbccdd","log":"boot resend"}'
ck "aceito"                          'grep -q "\"recorded\":true" <<<"$BODY"'
ck "sols preservado"                 '[[ "$(jq -r ".sols | length" "$F")" == 1 ]]'
ck "reports (nomes) preservados"     '[[ "$(jq -r ".reports | length" "$F")" == 1 ]]'
ck "html preservado"                 '[[ -s "$RUN/calib/col#pa/r/juiz1/good-sol.c.html" ]]'
ck "log atualizado"                  '[[ "$(jq -r .log "$F")" == "boot resend" ]]'

echo "== checksum NOVO sem sols zera (dado da versão velha engana) =="
post '{"host":"juiz1","id":"col#pa","checksum":"eeff0011","log":"versao nova"}'
ck "sols zerado"                     '[[ "$(jq -r ".sols | length" "$F")" == 0 ]]'
ck "reports zerados"                 '[[ "$(jq -r ".reports | length" "$F")" == 0 ]]'

echo "== sols acima do teto (1 MB) é descartado sem derrubar o report =="
BIG="$(mktemp)"; jq -cn '[{file:"x.c",lang:"c",category:"good",verdict:"AC",
  tests:[range(40000)|{name:("t"+tostring),code:"AC",time:0.1,tl:5}]}]' > "$BIG"
jq -cn --slurpfile s "$BIG" '{host:"juiz1", id:"col#pa", checksum:"eeff0011",
  log:"grande", sols:$s[0]}' > "$BIG.body"
OUT="$(PATH_INFO=/judge/calib-report REQUEST_METHOD=POST \
  HTTP_AUTHORIZATION="Bearer mojw_smoketest" bash "$ROUTER" < "$BIG.body" 2>/dev/null)"
BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"
rm -f "$BIG" "$BIG.body"
ck "aceito mesmo assim"              'grep -q "\"recorded\":true" <<<"$BODY"'
ck "sols descartado (teto)"          '[[ "$(jq -r ".sols | length" "$F")" == 0 ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
