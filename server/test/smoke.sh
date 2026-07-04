#!/bin/bash
# Smoke test da API v1 sem nginx: invoca o router.sh simulando o ambiente CGI.
# Cria um contest-fixture temporário p/ login e exercita o vertical de treino
# contra os dados REAIS de contests/treino (somente leitura).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"   # .../server
ROUTER="$ROOT/api/v1/router.sh"
REALCONTESTS="${REALCONTESTS:-/home/ribas/moj/contests}"

source "$(dirname "$(readlink -f "$0")")/fixture.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS"' EXIT
mkdir -p "$FIX/smoke/var"
printf 'CONTEST_ID=smoke\nCONTEST_NAME="Smoke"\nCONTEST_TYPE=icpc\nUSER_STORE=v2\n' > "$FIX/smoke/conf"
fx_user "$FIX/smoke" alice secret "Alice Tester"
fx_user "$FIX/smoke" bob.admin pw "Bob Admin"

pass=0; fail=0
check(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1"; echo "      out: $OUT" | head -c 400; echo; ((fail++)); fi; }
# call <PATH_INFO> <METHOD> <QUERY> <BEARER> [body] ; usa CONTESTSDIR=$CALLCD
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="$3" HTTP_AUTHORIZATION="${4:+Bearer $4}" \
  CONTESTSDIR="${CALLCD:-$REALCONTESTS}" SESSIONDIR="$SESS" SPOOLDIR="$FIX/spool" \
  bash "$ROUTER" <<<"${5:-}" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }

echo "== root =="
CALLCD="$REALCONTESTS"; call "/" GET "" ""
check "root returns version" '[[ "$BODY" == *\"version\":\"v1\"* ]]'

echo "== auth (fixture contest) =="
CALLCD="$FIX"
call "/auth/login" POST "contest=smoke" "" '{"username":"alice","password":"secret"}'
TOKEN="$(printf '%s' "$BODY" | jq -r '.token // empty' 2>/dev/null)"
check "login ok + token" '[[ -n "$TOKEN" ]]'
call "/auth/login" POST "contest=smoke" "" '{"username":"alice","password":"WRONG"}'
check "login wrong -> 401" '[[ "$OUT" == *"Status: 401"* ]]'
call "/auth/status" GET "contest=smoke" "$TOKEN"
check "status logged_in" '[[ "$BODY" == *\"logged_in\":true* && "$BODY" == *\"login\":\"alice\"* ]]'
call "/auth/status" GET "contest=smoke" "deadbeef-bad-token"
check "status bad token -> logged_in false" '[[ "$BODY" == *\"logged_in\":false* ]]'

echo "== admin role =="
call "/auth/login" POST "contest=smoke" "" '{"username":"bob.admin","password":"pw"}'
ATOK="$(printf '%s' "$BODY" | jq -r '.token // empty')"
call "/auth/status" GET "contest=smoke" "$ATOK"
check "bob.admin is_admin" '[[ "$BODY" == *\"is_admin\":true* ]]'

echo "== treino (dados reais, read-only) =="
CALLCD="$REALCONTESTS"
SOMEID="$(basename "$(ls "$REALCONTESTS"/treino/var/jsons/*.json 2>/dev/null | head -1)" .json)"
call "/treino/problem" GET "id=$(jq -rn --arg s "$SOMEID" '$s|@uri')" ""
check "treino/problem returns statement" '[[ "$BODY" == *statement_html_b64* ]]'
call "/treino/problem" GET "id=naoexiste-xyz" ""
check "treino/problem 404" '[[ "$OUT" == *"Status: 404"* ]]'

echo "== submit assíncrono (fixture) =="
CALLCD="$FIX"
call "/auth/login" POST "contest=smoke" "" '{"username":"alice","password":"secret"}'
TOKEN="$(printf '%s' "$BODY" | jq -r '.token')"
call "/submit" POST "contest=smoke" "$TOKEN" '{"problem_id":"smoke-p1","filename":"sol.c","code_b64":"aW50IG1haW4oKXt9"}'
SID="$(printf '%s' "$BODY" | jq -r '.submission_id // empty')"
check "submit returns submission_id+queued" '[[ -n "$SID" && "$BODY" == *\"status\":\"queued\"* ]]'
check "spool file created" '[[ -n "$(ls "$FIX"/spool/smoke:*:submit:smoke-p1:C 2>/dev/null)" ]]'
check "history got Not Answered Yet" 'grep -q "Not Answered Yet" "$FIX/smoke/users/alice/history"'

echo ""
echo "RESULT: $pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
