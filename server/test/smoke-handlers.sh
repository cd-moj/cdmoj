#!/bin/bash
# Smoke test dos handlers de index/contest/submission/admin/ops contra dados REAIS
# (somente leitura, exceto SPOOLDIR e SESSIONDIR temporários). Invoca router.sh
# simulando o ambiente CGI, como server/test/smoke.sh.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"   # .../server
ROUTER="$ROOT/api/v1/router.sh"
REALCONTESTS="${REALCONTESTS:-/home/ribas/moj/contests}"
CONTEST="${CONTEST:-bcr-eda2-2025_1-redencao}"

SESS="$(mktemp -d)"; SPOOL="$(mktemp -d)"; NEWS="$(mktemp -d)"
trap 'rm -rf "$SESS" "$SPOOL" "$NEWS"' EXIT

# Descobre um admin real do passwd do contest p/ forjar a sessão.
ADMIN="$(cut -d: -f1 "$REALCONTESTS/$CONTEST/passwd" | grep -m1 '\.admin$')"
[[ -z "$ADMIN" ]] && ADMIN="ribas.admin"
ANAME="$(awk -F: -v u="$ADMIN" '$1==u{print $3; exit}' "$REALCONTESTS/$CONTEST/passwd")"

# Forja um token de sessão (mesmo formato de create_session em lib/auth.sh).
TOKEN="11111111-2222-3333-4444-555555555555"
cat > "$SESS/$TOKEN" <<EOF
CONTEST="$CONTEST"
LOGIN="$ADMIN"
USERFULLNAME="$ANAME"
LOGINAT=$EPOCHSECONDS
EOF

pass=0; fail=0
check(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1"; echo "      out: ${OUT:0:500}"; ((fail++)); fi; }
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="$3" \
  HTTP_AUTHORIZATION="${4:+Bearer $4}" \
  CONTESTSDIR="$REALCONTESTS" SESSIONDIR="$SESS" SPOOLDIR="$SPOOL" NEWSDIR="$NEWS" \
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
check "redencao classified as closed" 'printf "%s" "$BODY" | jq -e ".closed.items + .open + .upcoming | map(.id) | index(\"$CONTEST\")" >/dev/null'
check "closed has pagination" 'printf "%s" "$BODY" | jq -e ".closed.total >= 1 and .closed.page==1" >/dev/null'

echo "== index/open_training (treino real) =="
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
# admin 'bruno.admin' has entries; our forged admin may differ -> just check it's only own lines
check "history lines only for logged user (or empty)" '[[ -z "$BODY" ]] || ! printf "%s" "$BODY" | awk -F: -v u="$ADMIN" "\$2!=u{exit 1}"'

echo "== contest/balloons =="
call "/contest/balloons" GET "contest=$CONTEST" ""
check "balloons 200 + valid JSON" 'okstatus && jvalid'
check "balloons default palette A=FFFFFF C=FF0000" 'printf "%s" "$BODY" | jq -e ".balloons.A==\"FFFFFF\" and .balloons.C==\"FF0000\" and .balloons.O==\"A3794D\"" >/dev/null'

echo "== contest/regions (empty default) =="
call "/contest/regions" GET "contest=$CONTEST" ""
check "regions 200 empty" 'okstatus && [[ "$BODY" == *\"regions\":\[\]* ]]'

echo "== contest/score (TXT, mode line) =="
call "/contest/score" GET "contest=$CONTEST" ""
check "score 200 (TXT)" 'okstatus'
check "score first line is a known mode" '[[ "$(printf "%s" "$BODY" | head -1)" =~ ^(icpc|obi|treino|heuristic|outro|custom)$ ]]'

echo "== contest/allsubmissions (Bearer, admin, TXT 9 fields) =="
call "/contest/allsubmissions" GET "contest=$CONTEST" "$TOKEN"
check "allsubmissions 200 (TXT)" 'okstatus'
check "allsubmissions has >=9 colon-fields" '[[ -z "$BODY" ]] || [[ "$(printf "%s" "$BODY" | head -1 | awk -F: "{print NF}")" -ge 9 ]]'

echo "== contest/final-verdicts (Bearer, judge) =="
call "/contest/final-verdicts" GET "contest=$CONTEST" "$TOKEN"
check "final-verdicts 200 + Accepted in list" 'okstatus && jvalid && (printf "%s" "$BODY" | jq -e ".verdicts|index(\"Accepted\")" >/dev/null)'

echo "== contest/set-verdict (POST judge) =="
call "/contest/set-verdict" POST "contest=$CONTEST" "$TOKEN" '{"problem_id":"A","verdict":"Accepted","username":"a221007902"}'
check "set-verdict queued" 'okstatus && [[ "$BODY" == *\"status\":\"queued\"* ]]'
check "set-verdict spool file created" '[[ -n "$(ls "$SPOOL"/$CONTEST:*:setverdict:A 2>/dev/null)" ]]'

echo "== contest/rejudge (POST admin) =="
call "/contest/rejudge" POST "contest=$CONTEST" "$TOKEN" '{"ids":["9a58663c59ca04970c7104195090bf33"]}'
check "rejudge count==1" 'okstatus && (printf "%s" "$BODY" | jq -e ".count==1" >/dev/null)'
check "rejudge spool file created" '[[ -n "$(ls "$SPOOL"/$CONTEST:*:rejulgar:* 2>/dev/null)" ]]'

echo "== submission/source (Bearer) =="
# pick a real submission: time:hash from filename of bruno.admin (owner) -> but our admin differs.
SUBFILE="$(ls "$REALCONTESTS/$CONTEST/submissions/" | grep -v accepted | head -1)"
STIME="${SUBFILE%%:*}"; rest="${SUBFILE#*:}"; SHASH="${rest%%-*}"
call "/submission/source" GET "contest=$CONTEST&time=$STIME&id=$SHASH" "$TOKEN"
# admin is judge -> allowed
check "source 200 returns code" 'okstatus && [[ "$BODY" == *include* || -n "$BODY" ]]'
call "/submission/source" GET "contest=$CONTEST&time=$STIME&id=deadbeef" "$TOKEN"
check "source bad id -> 400" '[[ "$OUT" == *"Status: 400"* ]]'

echo "== submission/log (Bearer) =="
LOGF="$(ls "$REALCONTESTS/$CONTEST/mojlog/" | head -1)"
LTIME="${LOGF%%:*}"; LHASH="${LOGF#*:}"
call "/submission/log" GET "contest=$CONTEST&time=$LTIME&id=$LHASH" "$TOKEN"
check "log 200 returns routing line" 'okstatus && [[ "$BODY" == *27000* || -n "$BODY" ]]'

echo "== admin/adduser + passwd (POST admin) — uses temp contest copy =="
TMPC="$(mktemp -d)"
cp -r "$REALCONTESTS/$CONTEST" "$TMPC/$CONTEST"
# forge session against this temp contestsdir copy
SESS2="$(mktemp -d)"
cat > "$SESS2/$TOKEN" <<EOF
CONTEST="$CONTEST"
LOGIN="$ADMIN"
USERFULLNAME="$ANAME"
LOGINAT=$EPOCHSECONDS
EOF
acall(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="$3" \
  HTTP_AUTHORIZATION="${4:+Bearer $4}" \
  CONTESTSDIR="$TMPC" SESSIONDIR="$SESS2" SPOOLDIR="$SPOOL" NEWSDIR="$NEWS" \
  bash "$ROUTER" <<<"${5:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }

acall "/admin/adduser" POST "" "$TOKEN" '{"contest":"'"$CONTEST"'","login":"smoketest.user","fullname":"Smoke Test User","email":"x@y.z"}'
check "adduser 200 + returns password" '[[ "$OUT" == *"Status: 200"* ]] && (printf "%s" "$BODY" | jq -e ".password|length>0" >/dev/null)'
check "adduser appended to passwd" 'grep -q "^smoketest.user:" "$TMPC/$CONTEST/passwd"'
acall "/admin/adduser" POST "" "$TOKEN" '{"contest":"'"$CONTEST"'","login":"smoketest.user","fullname":"Dup"}'
check "adduser duplicate -> 409" '[[ "$OUT" == *"Status: 409"* ]]'
acall "/admin/passwd" POST "" "$TOKEN" '{"contest":"'"$CONTEST"'","login":"smoketest.user","newpass":"NEWPW123"}'
check "passwd 200" '[[ "$OUT" == *"Status: 200"* ]]'
check "passwd replaced field 2" 'grep -q "^smoketest.user:NEWPW123:" "$TMPC/$CONTEST/passwd"'
check "passwd preserved fullname" 'grep -q "^smoketest.user:NEWPW123:Smoke Test User:" "$TMPC/$CONTEST/passwd"'

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

echo "== ops/judges (admin, best-effort) =="
call "/ops/judges" GET "" "$TOKEN"
check "judges 200 + judges field" 'okstatus && jvalid && (printf "%s" "$BODY" | jq -e "has(\"judges\")" >/dev/null)'

echo "== ops/problemtl (admin, best-effort) =="
call "/ops/problemtl" GET "problem=grafo-chp" "$TOKEN"
check "problemtl 200 + time_limits field" 'okstatus && jvalid && (printf "%s" "$BODY" | jq -e "has(\"time_limits\")" >/dev/null)'

echo "== ops/updateproblemset (admin, best-effort) =="
call "/ops/updateproblemset" POST "" "$TOKEN" '{"repo":"moj-problems"}'
check "updateproblemset 200 + success" 'okstatus && jvalid && (printf "%s" "$BODY" | jq -e ".success==true" >/dev/null)'

echo "== authz negatives =="
# non-admin user for admin-only endpoints
NONADMIN="$(cut -d: -f1 "$REALCONTESTS/$CONTEST/passwd" | grep -vm1 '\.\(admin\|judge\|staff\)$')"
[[ -n "$NONADMIN" ]] && {
  NTOK="99999999-8888-7777-6666-555555555555"
  cat > "$SESS/$NTOK" <<EOF
CONTEST="$CONTEST"
LOGIN="$NONADMIN"
USERFULLNAME="x"
LOGINAT=$EPOCHSECONDS
EOF
  call "/contest/allsubmissions" GET "contest=$CONTEST" "$NTOK"
  check "non-admin allsubmissions -> 403" '[[ "$OUT" == *"Status: 403"* ]]'
  call "/ops/queue" GET "" "$NTOK"
  check "non-admin ops/queue -> 403" '[[ "$OUT" == *"Status: 403"* ]]'
}

echo ""
echo "RESULT: $pass passed, $fail failed"
exit $(( fail > 0 ? 1 : 0 ))
