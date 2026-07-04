#!/bin/bash
# Item 4: estatísticas agregadas do contest.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
C="$FIX/st"; mkdir -p "$C/var"
# conf com PROBS reais (5-tuplas): offset 0->Q, 5->R, 10->S; o history grava ou o
# OFFSET-base (legado: 0,5,10) ou o id-fonte pontilhado (mon/soma -> mon.soma).
{ printf 'CONTEST_ID=st\nCONTEST_TYPE=icpc\n'
  printf "PROBS=(f0 mon/quadrados 'Quadrados Magicos' Q k0 f1 mon/retas 'Retas e Pontos' R k1 f2 mon/soma Somatorio S k2)\n"; } > "$C/conf"
fx_user "$C" st.admin p "Admin"
fx_user "$C" alice a "Alice"
fx_user "$C" bob b "Bob"
fx_user "$C" carol c "Carol"
fx_user "$C" zz.judge p "Judge"
fx_user "$C" zz.staff p "Staff"
printf 'CONTEST=st\nLOGIN=st.admin\nLOGINAT=1\n' > "$SESS/adm"
printf 'CONTEST=st\nLOGIN=alice\nLOGINAT=1\n' > "$SESS/usr"
{ printf '5:0:C:Accepted,100p:1718000000:h1\n'                 # Q (offset)
  printf '2:mon.soma:PY:Accepted,100p:1718000030:h6\n'; } > "$C/users/alice/history"  # S (pontilhado)
{ printf '3:0:CPP:Wrong Answer:1718000010:h2\n'                # Q (offset)
  printf '8:0:CPP:Accepted,100p:1718000020:h3\n'; } > "$C/users/bob/history"
printf '9:5:C:Accepted,100p:1718000040:h5\n' > "$C/users/carol/history"      # R (offset)
printf '1:0:C:Accepted,100p:1718000050:h7\n' > "$C/users/zz.judge/history"   # privilegiado -> descartado
printf '4:5:C:Accepted,100p:1718000060:h8\n' > "$C/users/zz.staff/history"   # privilegiado
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-adm}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${3:-}" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }

call /contest/statistics GET '' adm 'contest=st'
ck "totals submissions=5 (privilegiados fora)"  '[[ "$(jq -r .totals.submissions <<<"$BODY")" == 5 ]]'
ck "totals accepted=4"     '[[ "$(jq -r .totals.accepted <<<"$BODY")" == 4 ]]'
ck "totals users=3 (.judge/.staff descartados)" '[[ "$(jq -r .totals.users <<<"$BODY")" == 3 ]]'
ck "totals problems_solved=3" '[[ "$(jq -r .totals.problems_solved <<<"$BODY")" == 3 ]]'
# mapeamento offset->letra/nome
ck "offset 0 -> short_name Q + nome" '[[ "$(jq -r ".problems[]|select(.problem_id==\"0\")|.short_name" <<<"$BODY")" == "Q" && "$(jq -r ".problems[]|select(.problem_id==\"0\")|.full_name" <<<"$BODY")" == "Quadrados Magicos" ]]'
ck "offset 5 -> short_name R" '[[ "$(jq -r ".problems[]|select(.problem_id==\"5\")|.short_name" <<<"$BODY")" == "R" ]]'
# mapeamento id-fonte pontilhado -> letra/nome
ck "mon.soma -> short_name S + nome Somatorio" '[[ "$(jq -r ".problems[]|select(.problem_id==\"mon.soma\")|.short_name" <<<"$BODY")" == "S" && "$(jq -r ".problems[]|select(.problem_id==\"mon.soma\")|.full_name" <<<"$BODY")" == "Somatorio" ]]'
ck "problems ordenados por letra (1o = Q)" '[[ "$(jq -r ".problems[0].short_name" <<<"$BODY")" == "Q" ]]'
# privilegiados não contaminam o problema 0 (zz.judge resolveu mais cedo, mas é descartado)
ck "problema 0: solved=2, attempted=2 (sem zz.judge)" '[[ "$(jq -r ".problems[]|select(.problem_id==\"0\")|.solved" <<<"$BODY")" == 2 && "$(jq -r ".problems[]|select(.problem_id==\"0\")|.attempted" <<<"$BODY")" == 2 ]]'
ck "problema 0: first_solver alice (não zz.judge)" '[[ "$(jq -r ".problems[]|select(.problem_id==\"0\")|.first_solver" <<<"$BODY")" == "alice" ]]'
ck "lang CPP: submissions=2" '[[ "$(jq -r ".languages[]|select(.lang==\"CPP\")|.submissions" <<<"$BODY")" == 2 ]]'
ck "verdict Accepted count=4" '[[ "$(jq -r ".verdicts[]|select(.verdict==\"Accepted\")|.count" <<<"$BODY")" == 4 ]]'
ck "verdict Wrong Answer count=1" '[[ "$(jq -r ".verdicts[]|select(.verdict==\"Wrong Answer\")|.count" <<<"$BODY")" == 1 ]]'
ck "timeline tem bins"     '[[ "$(jq -r ".timeline|length" <<<"$BODY")" -ge 1 ]]'
call /contest/statistics GET '' usr 'contest=st'
ck "não-privilegiado 403"  '[[ "$OUT" == *"Status: 403"* ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
