#!/bin/bash
# view=public no /contest/score: privilegiado recebe o placar CONGELADO em vez do completo —
# é a fonte da cerimônia de revelação (frozen + full => delta). Fixture icpc com FREEZE_TIME
# no meio: AC pré-freeze aparece nos dois; AC pós-freeze só no full.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"

NOW="$EPOCHSECONDS"; START=$(( NOW - 7200 )); FREEZE=$(( NOW - 3600 ))
C="$FIX/rev"; mkdir -p "$C/var"
{ printf 'CONTEST_ID=rev\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nFREEZE_TIME=%s\nUSER_STORE=v2\n' \
    "$START" $(( NOW + 3600 )) "$FREEZE"
  printf "PROBS=(f0 col/pa 'Prob A' A 'col#pa' f1 col/pb 'Prob B' B 'col#pb')\n"; } > "$C/conf"
fx_user "$C" rev.admin p "Admin"
fx_user "$C" alice a "Alice"
# A: AC pré-freeze (aparece nos 2). B: AC pós-freeze (só no full; no frozen vira pendente).
{ printf '10:col#pa:c:Accepted,100p:%s:s1\n' $(( START + 600 ))
  printf '20:col#pb:c:Accepted,100p:%s:s2\n' $(( FREEZE + 60 )); } > "$C/users/alice/history"

mktok(){ printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' rev "$1" "$1" "$NOW" > "$SESS/$2"; }
mktok rev.admin t-adm; mktok alice t-a

call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD=GET QUERY_STRING="${3:-}" \
    HTTP_AUTHORIZATION="${2:+Bearer $2}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }
alicecells(){ grep ":alice:" <<<"$BODY" | head -1; }

echo "== admin: default = full; view=public = congelado =="
call /contest/score t-adm 'contest=rev'
ck "full mostra A e B resolvidos"  '[[ "$(alicecells)" == *"1/10"*"1/61"* ]]'
call /contest/score t-adm 'contest=rev&view=public'
ck "frozen mostra A resolvido"     '[[ "$(alicecells)" == *"1/10"* ]]'
ck "frozen NÃO mostra o AC de B"   '[[ "$(alicecells)" != *"1/61"* ]]'

echo "== competidor: view=public não muda nada (já era o congelado) =="
call /contest/score t-a 'contest=rev&view=public'
ck "alice vê o congelado"          '[[ "$(alicecells)" != *"1/61"* ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
