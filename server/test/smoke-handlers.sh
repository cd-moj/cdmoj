#!/bin/bash
# Smoke test dos handlers de index/contest/submission/admin/ops contra um FIXTURE
# store-v2 auto-contido (contest "handson" + treino mínimo). Antes rodava contra a
# base real; os contests legados foram arquivados em contests-legado/. Invoca
# router.sh simulando o ambiente CGI, como server/test/smoke.sh.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"   # .../server
ROUTER="$ROOT/api/v1/router.sh"

FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; SPOOL="$(mktemp -d)"; NEWS="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$SPOOL" "$NEWS"' EXIT

CONTEST=handson
ADMIN=hands.admin
SID="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"   # 32 hex, como um md5

source "$(dirname "$(readlink -f "$0")")/fixture.sh"

C="$FIX/$CONTEST"
mkdir -p "$C/var" "$C/enunciados"
{ printf 'CONTEST_ID=%s\nCONTEST_NAME="Hands On"\nCONTEST_TYPE=icpc\n' "$CONTEST"
  printf 'CONTEST_START=1000\nCONTEST_END=2000\nUSER_STORE=v2\n'
  printf "PROBS=(f0 col/pa 'Prob A' A 'col#pa' f1 col/pb 'Prob B' B 'col#pb' f2 col/pc 'Prob C' C 'col#pc' f3 col/pd 'Prob D' D 'col#pd')\n"
} > "$C/conf"
for k in pa pb pc pd; do printf '<h1>col#%s</h1>' "$k" > "$C/enunciados/col#$k.html"; done
# fx_user cria users/<login>/{account.json,history,submissions,mojlog,results}
fx_user "$C" "$ADMIN" adm "Admin Handson"
fx_user "$C" alice    a   "Alice Silva"
printf '5:col#pa:C:Accepted,100p:1718000000:%s\n' "$SID" > "$C/users/alice/history"
printf 'int main(){return 0;}\n' > "$C/users/alice/submissions/$SID.c"
printf '<html>report</html>\n'   > "$C/users/alice/mojlog/$SID.html"

# treino mínimo p/ /index/open_training
T="$FIX/treino"; mkdir -p "$T/var"
{ printf 'CONTEST_ID=treino\nCONTEST_NAME="Treino"\nCONTEST_TYPE=lista-publica\n'
  printf 'CONTEST_START=1000\nCONTEST_END=9999999999\nUSER_STORE=v2\n'; } > "$T/conf"
fx_user "$T" alice a "Alice Silva"
printf '1718000000:col#pa:C:Accepted,100p:1718000000:t1\n' > "$T/users/alice/history"

# Forja tokens de sessão (mesmo formato de create_session em lib/auth.sh).
TOKEN="11111111-2222-3333-4444-555555555555"
cat > "$SESS/$TOKEN" <<EOF
CONTEST="$CONTEST"
LOGIN="$ADMIN"
USERFULLNAME="Admin Handson"
LOGINAT=$EPOCHSECONDS
EOF
NTOK="99999999-8888-7777-6666-555555555555"
cat > "$SESS/$NTOK" <<EOF
CONTEST="$CONTEST"
LOGIN="alice"
USERFULLNAME="Alice Silva"
LOGINAT=$EPOCHSECONDS
EOF

pass=0; fail=0
check(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1"; echo "      out: ${OUT:0:500}"; ((fail++)); fi; }
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="$3" \
  HTTP_AUTHORIZATION="${4:+Bearer $4}" \
  CONTESTSDIR="$FIX" SESSIONDIR="$SESS" SPOOLDIR="$SPOOL" NEWSDIR="$NEWS" \
  bash "$ROUTER" <<<"${5:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }

okstatus(){ [[ "$OUT" == *"Status: 200"* ]]; }
jvalid(){ printf '%s' "$BODY" | jq -e . >/dev/null 2>&1; }

echo "== index/news (empty NEWSDIR) =="
call "/index/news" GET "" ""
check "news 200 + valid JSON" 'okstatus && jvalid'
check "news has news[] array" '[[ "$BODY" == *\"news\":\[* ]]'

echo "== index/contests =="
call "/index/contests" GET "page=1" ""
check "contests 200 + valid JSON" 'okstatus && jvalid'
check "contests has open/upcoming/closed" '[[ "$BODY" == *\"open\":* && "$BODY" == *\"closed\":* ]]'
check "handson classified as closed" 'printf "%s" "$BODY" | jq -e ".closed.items + .open + .upcoming | map(.id) | index(\"$CONTEST\")" >/dev/null'
check "closed has pagination" 'printf "%s" "$BODY" | jq -e ".closed.total >= 1 and .closed.page==1" >/dev/null'

echo "== index/open_training (treino fixture) =="
call "/index/open_training" GET "" ""
check "open_training 200 + valid JSON" 'okstatus && jvalid'
check "top_users present" 'printf "%s" "$BODY" | jq -e ".top_users|type==\"array\"" >/dev/null'
check "recent_solved present" 'printf "%s" "$BODY" | jq -e ".recent_solved|type==\"array\"" >/dev/null'

echo "== contest/basic (public) =="
call "/contest/basic" GET "contest=$CONTEST" ""
check "basic 200 + valid JSON" 'okstatus && jvalid'
check "basic has name/id/start/end/locale" 'printf "%s" "$BODY" | jq -e ".contest_id==\"$CONTEST\" and (.start_time|type==\"number\") and (.end_time|type==\"number\") and (.locale|type==\"string\")" >/dev/null'
check "basic has login_start_time" 'printf "%s" "$BODY" | jq -e ".login_start_time|type==\"number\"" >/dev/null'
call "/contest/basic" GET "contest=naoexiste-xyz" ""
check "basic unknown contest -> 404" '[[ "$OUT" == *"Status: 404"* ]]'

echo "== contest/userinfo (Bearer) =="
call "/contest/userinfo" GET "contest=$CONTEST" "$TOKEN"
check "userinfo 200 + valid JSON" 'okstatus && jvalid'
check "userinfo login==admin & is_admin true" 'printf "%s" "$BODY" | jq -e ".login==\"$ADMIN\" and .is_admin==true" >/dev/null'
call "/contest/userinfo" GET "contest=$CONTEST" ""
check "userinfo no token -> 401" '[[ "$OUT" == *"Status: 401"* ]]'

echo "== contest/navbuttons (Bearer, admin) =="
call "/contest/navbuttons" GET "contest=$CONTEST" "$TOKEN"
check "navbuttons 200 + valid JSON" 'okstatus && jvalid'
check "admin sees Todas Submissões & Administração & Logout" 'printf "%s" "$BODY" | jq -e "[.buttons[].label] as \$l | (\$l|index(\"Todas Submissões\")) and (\$l|index(\"⚙ Administração\")) and (\$l|index(\"Logout\"))" >/dev/null'
check "navbuttons base has Contest/Score/Clarification" 'printf "%s" "$BODY" | jq -e "[.buttons[].label] as \$l | (\$l|index(\"Contest\")) and (\$l|index(\"Score\")) and (\$l|index(\"Clarification\"))" >/dev/null'

echo "== contest/problems (Bearer) =="
call "/contest/problems" GET "contest=$CONTEST" "$TOKEN"
check "problems 200 + valid JSON" 'okstatus && jvalid'
check "problems has 4 items (PROBS/5)" 'printf "%s" "$BODY" | jq -e ".problems|length==4" >/dev/null'
check "problems short_names A..D" 'printf "%s" "$BODY" | jq -e "[.problems[].short_name]==[\"A\",\"B\",\"C\",\"D\"]" >/dev/null'
check "problem has problem_id & statement_html_b64 key" 'printf "%s" "$BODY" | jq -e ".problems[0]|has(\"problem_id\") and has(\"statement_html_b64\")" >/dev/null'

echo "== contest/news + resources (optional empty) =="
call "/contest/news" GET "contest=$CONTEST" "$TOKEN"
check "contest/news empty items" 'okstatus && [[ "$BODY" == *\"items\":\[\]* ]]'
call "/contest/resources" GET "contest=$CONTEST" "$TOKEN"
check "contest/resources empty items" 'okstatus && [[ "$BODY" == *\"items\":\[\]* ]]'

echo "== contest/history (Bearer, TXT) =="
call "/contest/history" GET "contest=$CONTEST" "$TOKEN"
check "history 200 (TXT)" 'okstatus'
check "history lines only for logged user (or empty)" '[[ -z "$BODY" ]] || ! printf "%s" "$BODY" | awk -F: -v u="$ADMIN" "\$2!=u{exit 1}"'
call "/contest/history" GET "contest=$CONTEST" "$NTOK"
check "history alice has her AC line" 'okstatus && [[ "$BODY" == *"$SID"* ]]'

echo "== contest/balloons =="
call "/contest/balloons" GET "contest=$CONTEST" ""
check "balloons 200 + valid JSON" 'okstatus && jvalid'
check "balloons default palette A=FFFFFF C=FF0000" 'printf "%s" "$BODY" | jq -e ".balloons.A==\"FFFFFF\" and .balloons.C==\"FF0000\" and .balloons.O==\"A3794D\"" >/dev/null'

echo "== contest/regions (empty default) =="
call "/contest/regions" GET "contest=$CONTEST" ""
check "regions 200 empty" 'okstatus && [[ "$BODY" == *\"regions\":\[\]* ]]'

echo "== contest/score (TXT, mode line, gerado de users/*/metrics.json) =="
call "/contest/score" GET "contest=$CONTEST" ""
check "score 200 (TXT)" 'okstatus'
check "score first line is a known mode" '[[ "$(printf "%s" "$BODY" | head -1)" =~ ^(icpc|obi|treino|heuristic|outro|custom)$ ]]'
check "score has alice row (metrics-driven)" '[[ "$BODY" == *alice* ]]'
check "placar gerado em var/placar.txt" '[[ -s "$FIX/$CONTEST/var/placar.txt" ]]'

echo "== contest/allsubmissions (Bearer, admin, TXT 9 fields) =="
call "/contest/allsubmissions" GET "contest=$CONTEST" "$TOKEN"
check "allsubmissions 200 (TXT)" 'okstatus'
check "allsubmissions has >=9 colon-fields" '[[ -n "$BODY" ]] && [[ "$(printf "%s" "$BODY" | head -1 | awk -F: "{print NF}")" -ge 9 ]]'
check "allsubmissions resolve fullname do account.json" '[[ "$BODY" == *"Alice Silva"* ]]'

echo "== contest/final-verdicts (Bearer, judge) =="
call "/contest/final-verdicts" GET "contest=$CONTEST" "$TOKEN"
check "final-verdicts 200 + Accepted in list" 'okstatus && jvalid && (printf "%s" "$BODY" | jq -e ".verdicts|index(\"Accepted\")" >/dev/null)'

echo "== contest/set-verdict (POST judge) =="
call "/contest/set-verdict" POST "contest=$CONTEST" "$TOKEN" '{"problem_id":"A","verdict":"Accepted","username":"alice"}'
check "set-verdict queued" 'okstatus && [[ "$BODY" == *\"status\":\"queued\"* ]]'
check "set-verdict spool file created" '[[ -n "$(ls "$SPOOL"/$CONTEST:*:setverdict:A 2>/dev/null)" ]]'

echo "== contest/rejudge (POST admin, store-v2) =="
call "/contest/rejudge" POST "contest=$CONTEST" "$TOKEN" '{"ids":["'"$SID"'"]}'
check "rejudge count==1" 'okstatus && (printf "%s" "$BODY" | jq -e ".count==1" >/dev/null)'
check "rejudge spool file created" '[[ -n "$(ls "$SPOOL"/$CONTEST:*:rejulgar:* "$SPOOL"/$CONTEST:*:submit:* 2>/dev/null)" ]]'
check "rejudge marcou history provisório" 'grep -q "Not Answered Yet" "$C/users/alice/history"'
# restaura o veredicto p/ os checks seguintes
printf '5:col#pa:C:Accepted,100p:1718000000:%s\n' "$SID" > "$C/users/alice/history"

echo "== submission/source (Bearer) =="
call "/submission/source" GET "contest=$CONTEST&time=1718000000&id=$SID" "$TOKEN"
check "source 200 returns code" 'okstatus && [[ "$BODY" == *"int main"* ]]'
call "/submission/source" GET "contest=$CONTEST&time=1718000000&id=deadbeef" "$TOKEN"
check "source bad id -> 400" '[[ "$OUT" == *"Status: 400"* ]]'

echo "== submission/log (Bearer) =="
call "/submission/log" GET "contest=$CONTEST&time=1718000000&id=$SID" "$TOKEN"
check "log 200 returns report" 'okstatus && [[ "$BODY" == *report* ]]'

echo "== admin/adduser + passwd (POST admin) — uses temp contest copy =="
TMPC="$(mktemp -d)"
cp -r "$C" "$TMPC/$CONTEST"
SESS2="$(mktemp -d)"
cp "$SESS/$TOKEN" "$SESS2/$TOKEN"
acall(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="$3" \
  HTTP_AUTHORIZATION="${4:+Bearer $4}" \
  CONTESTSDIR="$TMPC" SESSIONDIR="$SESS2" SPOOLDIR="$SPOOL" NEWSDIR="$NEWS" \
  bash "$ROUTER" <<<"${5:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }

acall "/admin/adduser" POST "" "$TOKEN" '{"contest":"'"$CONTEST"'","login":"smoketest.user","fullname":"Smoke Test User","email":"x@y.z"}'
check "adduser 200 + returns password" '[[ "$OUT" == *"Status: 200"* ]] && (printf "%s" "$BODY" | jq -e ".password|length>0" >/dev/null)'
check "adduser criou account.json" '[[ -f "$TMPC/$CONTEST/users/smoketest.user/account.json" ]]'
acall "/admin/adduser" POST "" "$TOKEN" '{"contest":"'"$CONTEST"'","login":"smoketest.user","fullname":"Dup"}'
check "adduser duplicate -> 409" '[[ "$OUT" == *"Status: 409"* ]]'
acall "/admin/passwd" POST "" "$TOKEN" '{"contest":"'"$CONTEST"'","login":"smoketest.user","newpass":"NEWPW123"}'
check "passwd 200" '[[ "$OUT" == *"Status: 200"* ]]'
check "senha trocada no account.json" '[[ "$(jq -r .password "$TMPC/$CONTEST/users/smoketest.user/account.json")" == "NEWPW123" ]]'
check "fullname preservado" '[[ "$(jq -r .fullname "$TMPC/$CONTEST/users/smoketest.user/account.json")" == "Smoke Test User" ]]'

echo "== admin/contest/extend (POST admin) =="
acall "/admin/contest/extend" POST "" "$TOKEN" '{"contest":"'"$CONTEST"'","end_epoch":1999999999}'
check "extend 200" '[[ "$OUT" == *"Status: 200"* ]]'
check "extend appended CONTEST_END" 'tail -1 "$TMPC/$CONTEST/conf" | grep -qx "CONTEST_END=1999999999"'
rm -rf "$TMPC" "$SESS2"

echo "== admin/synctreino (POST admin) =="
call "/admin/synctreino" POST "" "$TOKEN"
check "synctreino queued + spool" 'okstatus && [[ -n "$(ls "$SPOOL"/treino:*:synctreino:* 2>/dev/null)" ]]'

echo "== admin/rejudge (bot alias) =="
call "/admin/rejudge" POST "" "$TOKEN" '{"contest":"'"$CONTEST"'","problem":"A"}'
check "admin/rejudge problem queued" 'okstatus && [[ -n "$(ls "$SPOOL"/$CONTEST:*:rejulgarproblema:A 2>/dev/null)" ]]'

echo "== ops/queue (admin) =="
call "/ops/queue" GET "" "$TOKEN"
check "queue 200 + valid JSON + total>=1" 'okstatus && jvalid && (printf "%s" "$BODY" | jq -e ".total>=1 and (.by_contest|type==\"object\")" >/dev/null)'

echo "== ops/problemtl (admin, best-effort) =="
call "/ops/problemtl" GET "problem=grafo-chp" "$TOKEN"
check "problemtl 200 + time_limits field" 'okstatus && jvalid && (printf "%s" "$BODY" | jq -e "has(\"time_limits\")" >/dev/null)'

echo "== ops/updateproblemset (admin, best-effort) =="
# usa uma ORG real do store de problemas (pós-migração p/ orgs não existe mais "moj-problems")
REPO="$(ls "${MOJ_PROBLEMS_DIR:-/home/ribas/moj/moj-problems}" 2>/dev/null | head -1)"
if [[ -n "$REPO" ]]; then
  call "/ops/updateproblemset" POST "" "$TOKEN" '{"repo":"'"$REPO"'"}'
  check "updateproblemset 200 + success" 'okstatus && jvalid && (printf "%s" "$BODY" | jq -e ".success==true" >/dev/null)'
else
  echo "  skip: store de problemas vazio"
fi

echo "== authz negatives =="
call "/contest/allsubmissions" GET "contest=$CONTEST" "$NTOK"
check "non-admin allsubmissions -> 403" '[[ "$OUT" == *"Status: 403"* ]]'
call "/ops/queue" GET "" "$NTOK"
check "non-admin ops/queue -> 403" '[[ "$OUT" == *"Status: 403"* ]]'

echo ""
echo "RESULT: $pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
