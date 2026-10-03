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
fx_user "$C" bob b "Bob"
# A: AC pré-freeze (aparece nos 2). B: AC pós-freeze (só no full; no frozen vira pendente).
{ printf '10:col#pa:c:Accepted,100p:%s:s1\n' $(( START + 600 ))
  printf '20:col#pb:c:Accepted,100p:%s:s2\n' $(( FREEZE + 60 )); } > "$C/users/alice/history"
# bob: WA pré-freeze em A (igual nas duas visões) e WA PÓS-freeze em B — este tem de sair
# MARCADO (`1/-?`) no congelado: sem a marca ele saía igual ao full e a cerimônia o mostrava
# sem "?" (só os ACs pós-freeze tinham), entregando quem não acertou (TCP 2026, 03/10/2026).
{ printf '11:col#pa:c:Wrong Answer:%s:s3\n' $(( START + 660 ))
  printf '21:col#pb:c:Wrong Answer:%s:s4\n' $(( FREEZE + 120 )); } > "$C/users/bob/history"

mktok(){ printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' rev "$1" "$1" "$NOW" > "$SESS/$2"; }
mktok rev.admin t-adm; mktok alice t-a

call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD=GET QUERY_STRING="${3:-}" \
    HTTP_AUTHORIZATION="${2:+Bearer $2}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }
alicecells(){ grep ":alice:" <<<"$BODY" | head -1; }
bobcells(){ grep ":bob:" <<<"$BODY" | head -1; }

echo "== admin: default = full; view=public = congelado =="
call /contest/score t-adm 'contest=rev'
ck "full mostra A e B resolvidos"  '[[ "$(alicecells)" == *"1/600"*"1/3660"* ]]'   # células em SEGUNDOS (flag `icpc s`)
call /contest/score t-adm 'contest=rev&view=public'
ck "frozen mostra A resolvido"     '[[ "$(alicecells)" == *"1/600"* ]]'
ck "frozen NÃO mostra o AC de B"   '[[ "$(alicecells)" != *"1/3660"* ]]'

echo "== competidor: view=public não muda nada (já era o congelado) =="
call /contest/score t-a 'contest=rev&view=public'
ck "alice vê o congelado"          '[[ "$(alicecells)" != *"1/3660"* ]]'

echo "== marca do congelado: toda célula com resultado escondido sai tries/-? =="
call /contest/score t-adm 'contest=rev&view=public'
ck "AC pós-freeze: 1/-? no frozen"     '[[ "$(alicecells)" == *":1/600"*":1/-?:"* ]]'
ck "WA pós-freeze: 1/-? no frozen"     '[[ "$(bobcells)" == *":1/-:1/-?:"* ]]'
ck "WA pré-freeze: sem marca"          '[[ "$(bobcells)" == *":1/-:"* ]]'
call /contest/score t-adm 'contest=rev'
ck "full nunca leva a marca"           '[[ "$BODY" != *"/-?"* && "$(bobcells)" == *":1/-:1/-:"* ]]'
# leitores do TXT: o parser único (sc_board_rows) segue lendo total/penalidade da linha marcada
FROZ="$FIX/rev/var/placar.txt"
ck "sc_board_rows lê a linha marcada"  '[[ "$(bash -c "source \"$ROOT/score/score-common.sh\"; sc_board_rows \"$FROZ\"" | awk -F"\t" "\$3==\"bob\"{print \$8\":\"\$11}")" == "0:1" ]]'

echo "== antes do FREEZE_TIME o congelado não marca nada (run em julgamento não vira ?) =="
sed -i "s/^FREEZE_TIME=.*/FREEZE_TIME=$(( NOW + 1800 ))/" "$C/conf"
printf '30:col#pa:c:Not Answered Yet:%s:s5\n' $(( NOW - 60 )) >> "$C/users/bob/history"
touch "$C/var/.score-dirty"; export SCORE_SERVE_FLOOR_S=0   # sem o piso: o placar acabou de nascer
call /contest/score t-a 'contest=rev'
ck "freeze futuro: nenhuma marca"      '[[ "$BODY" == *":bob:"* && "$BODY" != *"/-?"* ]]'

echo "== conf SEM a linha FREEZE_TIME (o caso comum): o gerador não morre no set -u =="
sed -i '/^FREEZE_TIME=/d' "$C/conf"; rm -f "$C"/var/placar*   # sem placar velho p/ mascarar a falha
call /contest/score t-a 'contest=rev'
ck "sem FREEZE_TIME: placar sai"       '[[ "$BODY" == *":bob:"* && "$BODY" != *"/-?"* ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
