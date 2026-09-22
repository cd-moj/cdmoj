#!/bin/bash
# smoke-problem-rev.sh — TRAVA DE EDIÇÃO CONCORRENTE (pkg_rev em lib/problems.sh).
# O editor web e a CLI mandam o `rev` que carregaram (`base_rev`); o /problems/edit e o /problems/upload
# recusam com 409 `stale_rev` {current_rev, changed_by, changed_at} se o pacote mudou desde então.
# Prende: rev em source/get · publicar e mexer no DONO não mudam o rev (senão travaria todo mundo à toa),
# coleção e título mudam (o push manda os dois) · edit com rev velho → 409 com quem/quando · force
# passa · sem base_rev passa (cliente antigo) · upload idem · dois edits simultâneos com o MESMO
# base_rev → exatamente UM vence (conferência + escrita sob o lock do problema).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; PROBS="$(mktemp -d)"; W="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN" "$PROBS" "$W"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" MOJ_PROBLEMS_DIR="$PROBS" MOJ_JOBS_SYNC=1
mkdir -p "$FIX/treino/var"
NOW="$EPOCHSECONDS"
fx_user "$FIX/treino" alice s "Alice"; fx_user "$FIX/treino" bob s "Bob"
echo '{"threshold":0,"allow":["alice","bob"],"deny":[]}' > "$FIX/treino/var/contest-perms.json"
echo '{"col":{"members":["alice","bob"],"admins":["alice"],"created_by":"alice","title":"Col","public_allowed":true}}' > "$FIX/treino/var/orgs.json"
echo '{"Lista 1":{"owner":"alice","created_by":"alice"}}' > "$FIX/treino/var/collections.json"
for u in ali:alice bob:bob; do printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' treino "${u#*:}" "${u#*:}" "$NOW" > "$SESS/${u%%:*}"; done
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:240}"; ((fail++)); fi; }
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer $3" bash "$ROUTER" <<<"${4:-}" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
J(){ printf '%s' "$BODY" | jq -r "$1" 2>/dev/null; }

P="$PROBS/col/pa"; mkdir -p "$P/docs" "$P/tests/input" "$P/tests/output" "$P/sols/good"
printf 'Leia N.\n\n## Entrada\n\nx\n\n## Saída\n\ny\n' > "$P/docs/enunciado.md"
printf '3\n' > "$P/tests/input/x"; printf '3\n' > "$P/tests/output/x"; printf '1\n' > "$P/tests/input/sample1"; printf '1\n' > "$P/tests/output/sample1"
printf 'int main(){return 0;}\n' > "$P/sols/good/a.c"; printf 'Autor\n' > "$P/author"
printf '{"owner":"alice","public":false,"display_title":"PA"}' > "$P/.moj-meta.json"
( cd "$P" && git init -q . && git add -A . && git -c user.name=alice -c user.email=a@a commit -qm init ) 2>/dev/null

echo "== o rev =="
call /problems/source GET ali '' 'id=col%23pa'
R0="$(J .rev)"
ck "source devolve rev (16 hex) e quem/quando"   '[[ "$R0" =~ ^[0-9a-f]{16}$ && "$(J .rev_by)" == alice && "$(J .rev_at)" -gt 0 ]]'
call /problems/get GET ali '' 'id=col%23pa'
ck "get devolve o MESMO rev"                     '[[ "$(J .rev)" == "$R0" ]]'
call /problems/set-public POST ali '{"id":"col#pa","public":true}'
call /problems/source GET ali '' 'id=col%23pa'
ck "publicar (set-public) NÃO muda o rev"        '[[ "$(jq -r .public "$P/.moj-meta.json")" == true && "$(J .rev)" == "$R0" ]]'
ck "…nem vira o \"quem mudou\" (commit de sistema)" '[[ "$(J .rev_by)" == alice ]]'
jq -c '.owner = "carol"' "$P/.moj-meta.json" > "$P/m" && mv "$P/m" "$P/.moj-meta.json"; ( cd "$P" && git add -A && git -c user.name=moj -c user.email=m@m commit -qm "dono: alice -> carol (troca de username)" ) 2>/dev/null
call /problems/source GET ali '' 'id=col%23pa'
ck "trocar o dono NÃO muda o rev"                '[[ "$(J .rev)" == "$R0" ]]'
jq -c '.owner = "alice"' "$P/.moj-meta.json" > "$P/m" && mv "$P/m" "$P/.moj-meta.json"; ( cd "$P" && git add -A && git -c user.name=moj -c user.email=m@m commit -qm "dono: carol -> alice" ) 2>/dev/null
call /problems/set-collections POST ali '{"id":"col#pa","collections":["Lista 1"]}'
call /problems/source GET ali '' 'id=col%23pa'
R1="$(J .rev)"
ck "mexer nas COLEÇÕES muda o rev (o push manda as coleções)" '[[ "$OUT" == *"Status: 200"* && "$R1" != "$R0" ]]'

echo "== edit com base_rev =="
call /problems/edit POST bob "$(jq -cn --arg r "$R1" '{id:"col#pa", enunciado_md:"Bob mudou.\n\n## Entrada\n\nx\n\n## Saída\n\ny\n", base_rev:$r}')"
R2="$(J .rev)"
ck "edit com o rev ATUAL passa e devolve o rev novo" '[[ "$OUT" == *"Status: 200"* && "$R2" =~ ^[0-9a-f]{16}$ && "$R2" != "$R1" ]]'
call /problems/edit POST ali "$(jq -cn --arg r "$R1" '{id:"col#pa", enunciado_md:"Alice por cima.\n", base_rev:$r}')"
ck "edit com rev VELHO → 409 stale_rev, com quem mudou (bob) e o rev atual" \
   '[[ "$OUT" == *"Status: 409"* && "$(J .error.code)" == stale_rev && "$(J .error.changed_by)" == bob && "$(J .error.current_rev)" == "$R2" && "$(J .error.changed_at)" -gt 0 ]]'
ck "…e NADA foi gravado"                         'grep -q "Bob mudou" "$P/docs/enunciado.md"'
call /problems/edit POST ali "$(jq -cn --arg r "$R1" '{id:"col#pa", enunciado_md:"Alice por cima.\n\n## Entrada\n\nx\n\n## Saída\n\ny\n", base_rev:$r, force:true}')"
ck "force:true passa por cima"                   '[[ "$OUT" == *"Status: 200"* ]] && grep -q "Alice por cima" "$P/docs/enunciado.md"'
R3="$(J .rev)"
call /problems/edit POST bob '{"id":"col#pa","author":"Bob\n"}'
ck "sem base_rev (cliente antigo): passa como antes" '[[ "$OUT" == *"Status: 200"* ]]'
R4="$(J .rev)"
call /problems/edit POST bob '{"id":"col#pa","base_rev":"zzz"}'
ck "base_rev malformado → 400"                   '[[ "$(J .error.code)" == bad_rev ]]'
call /problems/edit POST ali "$(jq -cn --arg r "$R4" '{id:"col#pa", title:"PA novo", base_rev:$r}')"
R5="$(J .rev)"
ck "mudar SÓ o título muda o rev"                '[[ "$OUT" == *"Status: 200"* && "$R5" != "$R4" ]]'

echo "== upload com base_rev =="
C="$W/pa"; mkdir -p "$C/docs" "$C/tests/input" "$C/tests/output" "$C/sols/good"
cp "$P/docs/enunciado.md" "$C/docs/"; cp "$P/sols/good/a.c" "$C/sols/good/"; printf 'Autor\n' > "$C/author"
printf '3\n' > "$C/tests/input/x"; printf '3\n' > "$C/tests/output/x"
TAR="$( (cd "$W" && tar -cf - pa) | base64 -w0 )"
call /problems/upload POST ali "$(jq -cn --arg t "$TAR" --arg r "$R3" '{id:"col#pa", tar_b64:$t, base_rev:$r}')"
ck "upload com rev velho → 409 stale_rev"        '[[ "$OUT" == *"Status: 409"* && "$(J .error.code)" == stale_rev ]]'
call /problems/upload POST ali "$(jq -cn --arg t "$TAR" --arg r "$R5" '{id:"col#pa", tar_b64:$t, base_rev:$r}')"
ck "upload com o rev atual passa e devolve rev"   '[[ "$OUT" == *"Status: 200"* && "$(J .rev)" =~ ^[0-9a-f]{16}$ ]]'
R6="$(J .rev)"

echo "== corrida: dois edits com o MESMO base_rev ao mesmo tempo =="
for who in ali bob; do
  ( PATH_INFO=/problems/edit REQUEST_METHOD=POST HTTP_AUTHORIZATION="Bearer $who" bash "$ROUTER" \
      <<<"$(jq -cn --arg r "$R6" --arg w "$who" '{id:"col#pa", enunciado_md:("corrida " + $w + "\n\n## Entrada\n\nx\n\n## Saída\n\ny\n"), base_rev:$r}')" 2>/dev/null \
      | head -1 > "$W/race.$who" ) &
done; wait
ck "exatamente UM venceu (200) e o outro levou 409" '[[ "$(cat "$W/race.ali" "$W/race.bob" | grep -c "Status: 200")" == 1 && "$(cat "$W/race.ali" "$W/race.bob" | grep -c "Status: 409")" == 1 ]]'
ck "o lock do problema foi liberado (nenhum edit preso)" 'call /problems/edit POST ali "{\"id\":\"col#pa\",\"author\":\"x\\n\"}"; [[ "$OUT" == *"Status: 200"* ]]'
echo; echo "RESULT: $pass passed, $fail failed"; [[ $fail -eq 0 ]]
