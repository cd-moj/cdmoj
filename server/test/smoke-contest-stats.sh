#!/bin/bash
# Item 4: estatísticas agregadas do contest.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
C="$FIX/st"; mkdir -p "$C/controle"
printf 'CONTEST_ID=st\nCONTEST_TYPE=icpc\n' > "$C/conf"
printf 'st.admin:p:Admin\nalice:a:Alice\n' > "$C/passwd"
printf 'CONTEST=st\nLOGIN=st.admin\nLOGINAT=1\n' > "$SESS/adm"
printf 'CONTEST=st\nLOGIN=alice\nLOGINAT=1\n' > "$SESS/usr"
{ printf '5:alice:A:C:Accepted,100p:1718000000:h1\n'
  printf '3:bob:A:CPP:Wrong Answer:1718000010:h2\n'
  printf '8:bob:A:CPP:Accepted,100p:1718000020:h3\n'
  printf '2:alice:B:PY:Wrong Answer:1718000030:h4\n'; } > "$C/controle/history"
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-adm}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${3:-}" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }

call /contest/statistics GET '' adm 'contest=st'
ck "totals submissions=4"  '[[ "$(jq -r .totals.submissions <<<"$BODY")" == 4 ]]'
ck "totals accepted=2"     '[[ "$(jq -r .totals.accepted <<<"$BODY")" == 2 ]]'
ck "totals users=2"        '[[ "$(jq -r .totals.users <<<"$BODY")" == 2 ]]'
ck "totals problems_solved=1" '[[ "$(jq -r .totals.problems_solved <<<"$BODY")" == 1 ]]'
ck "problema A: solved=2, attempted=2" '[[ "$(jq -r ".problems[]|select(.problem_id==\"A\")|.solved" <<<"$BODY")" == 2 && "$(jq -r ".problems[]|select(.problem_id==\"A\")|.attempted" <<<"$BODY")" == 2 ]]'
ck "problema A: first_solver alice" '[[ "$(jq -r ".problems[]|select(.problem_id==\"A\")|.first_solver" <<<"$BODY")" == "alice" ]]'
ck "lang CPP: submissions=2" '[[ "$(jq -r ".languages[]|select(.lang==\"CPP\")|.submissions" <<<"$BODY")" == 2 ]]'
ck "verdict Accepted count=2" '[[ "$(jq -r ".verdicts[]|select(.verdict==\"Accepted\")|.count" <<<"$BODY")" == 2 ]]'
ck "verdict Wrong Answer count=2" '[[ "$(jq -r ".verdicts[]|select(.verdict==\"Wrong Answer\")|.count" <<<"$BODY")" == 2 ]]'
ck "timeline tem bins"     '[[ "$(jq -r ".timeline|length" <<<"$BODY")" -ge 1 ]]'
call /contest/statistics GET '' usr 'contest=st'
ck "não-privilegiado 403"  '[[ "$OUT" == *"Status: 403"* ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
