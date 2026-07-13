#!/bin/bash
# Fila de revisão do veredicto manual: visibilidade dos votos (juiz comum não vê; admin e
# chief veem), claim/vote, conflito, resolve/override do admin (libera setverdict + audita)
# e o placar COMPLETO (sem freeze) p/ .cjudge (is_judge cobre o juiz-chefe).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; SPOOL="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$SPOOL"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
C="$FIX/rv"; mkdir -p "$C/review" "$C/var"
NOW="$(date +%s)"; OLD=$(( NOW - 1200 ))
printf 'CONTEST_ID=rv\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nMANUAL_VERDICT=1\n' "$((NOW-3600))" "$((NOW+3600))" > "$C/conf"
fx_user "$C" rv.admin  p Admin
fx_user "$C" j1.judge  p "Juiz Um"
fx_user "$C" j2.judge  p "Juiz Dois"
fx_user "$C" cj.cjudge p Chefe
fx_user "$C" aluno1    a Aluno
mkrev(){ printf '%s' "{\"id\":\"$1\",\"login\":\"aluno1\",\"problem_id\":\"apc#p1\",\"lang\":\"C\",\"computed_verdict\":\"Wrong Answer\",\"status\":\"open\",\"conflict\":false,\"created_at\":$OLD,\"sub_epoch\":$OLD,\"claimants\":[],\"votes\":[]}" > "$C/review/$1.json"; }
mkrev r1; mkrev r2
for s in adm:rv.admin j1:j1.judge j2:j2.judge cj:cj.cjudge alu:aluno1; do
  printf 'CONTEST=rv\nLOGIN=%s\nUSERFULLNAME=x\nLOGINAT=1\n' "${s#*:}" > "$SESS/${s%%:*}"
done
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-adm}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" SPOOLDIR="$SPOOL" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }

echo "== list: gates e visibilidade dos votos =="
call /contest/review/list GET '' alu 'contest=rv'
ck "aluno não vê a fila (403)"    '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/review/list GET '' j1 'contest=rv'
ck "juiz vê 2 itens, manual on"   '[[ "$(jq -r ".items|length" <<<"$BODY")" == 2 && "$(jq -r .manual <<<"$BODY")" == true ]]'
ck "counts: 2 não avaliadas"      '[[ "$(jq -r .counts.not_evaluated <<<"$BODY")" == 2 ]]'
ck "idade disponível (created_at)" '[[ "$(jq -r ".items[0].created_at" <<<"$BODY")" == "$OLD" ]]'

echo "== claim + vote (j1) =="
call /contest/review/claim POST '{"id":"r1","action":"claim"}' j1 'contest=rv'
ck "j1 pegou r1"                  '[[ "$(jq -r .updated.status <<<"$BODY")" == claimed ]]'
call /contest/review/list GET '' j2 'contest=rv'
ck "j2 vê quem pegou (claimants)" '[[ "$(jq -r ".items[]|select(.id==\"r1\").claimants[0].by" <<<"$BODY")" == "j1.judge" ]]'
call /contest/review/vote POST '{"id":"r1","label":"5 - NO - Wrong answer"}' j1 'contest=rv'
ck "voto do j1 registrado"        '[[ "$(jq -r .status <<<"$BODY")" == voting ]]'
call /contest/review/list GET '' j2 'contest=rv'
ck "juiz comum NÃO vê os votos"   '[[ "$(jq -r ".items[]|select(.id==\"r1\").votes" <<<"$BODY")" == null && "$(jq -r ".items[]|select(.id==\"r1\").votes_n" <<<"$BODY")" == 1 ]]'
call /contest/review/list GET '' adm 'contest=rv'
ck "ADMIN vê os votos"            '[[ "$(jq -r ".items[]|select(.id==\"r1\").votes[0].by" <<<"$BODY")" == "j1.judge" ]]'
call /contest/review/list GET '' cj 'contest=rv'
ck "chefe vê os votos"            '[[ "$(jq -r ".items[]|select(.id==\"r1\").votes[0].by" <<<"$BODY")" == "j1.judge" ]]'

echo "== conflito + resolve do admin =="
call /contest/review/claim POST '{"id":"r1","action":"claim"}' j2 'contest=rv'
call /contest/review/vote POST '{"id":"r1","label":"1 - YES"}' j2 'contest=rv'
ck "votos diferentes => conflito" '[[ "$(jq -r .status <<<"$BODY")" == conflict ]]'
call /contest/review/resolve POST '{"id":"r1","verdict":"5 - NO - Wrong answer"}' j1 'contest=rv'
ck "juiz comum não resolve (403)" '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/review/resolve POST '{"id":"r1","verdict":"5 - NO - Wrong answer"}' adm 'contest=rv'
ck "admin resolve o conflito"     '[[ "$(jq -r .status <<<"$BODY")" == released && "$(jq -r .released_verdict <<<"$BODY")" == "Wrong Answer" ]]'
ck "setverdict enfileirado"       'ls "$SPOOL" | grep -q setverdict'
ck "auditado (review-resolve)"    'grep -q "review-resolve" "$C/var/admin-audit.log"'

echo "== override do admin SEM conflito (r2 sem votos) =="
call /contest/review/resolve POST '{"id":"r2","verdict":"1 - YES"}' adm 'contest=rv'
ck "override direto => released"  '[[ "$(jq -r .status <<<"$BODY")" == released && "$(jq -r .released_verdict <<<"$BODY")" == Accepted ]]'
call /contest/review/resolve POST '{"id":"r2","verdict":"1 - YES"}' adm 'contest=rv'
ck "resolver de novo => 409"      '[[ "$OUT" == *"Status: 409"* ]]'
call /contest/review/list GET '' adm 'contest=rv'
ck "released some da fila"        '[[ "$(jq -r ".items|length" <<<"$BODY")" == 0 ]]'

echo "== placar completo (sem freeze) p/ .cjudge =="
printf 'icpc\nCONGELADO\n' > "$C/var/placar.txt"
printf 'icpc\nCOMPLETO\n' > "$C/var/placar-full.txt"
call /contest/score GET '' cj 'contest=rv'
ck ".cjudge vê o placar COMPLETO" '[[ "$OUT" == *COMPLETO* ]]'
call /contest/score GET '' alu 'contest=rv'
ck "aluno vê o congelado"         '[[ "$OUT" == *CONGELADO* && "$OUT" != *COMPLETO* ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
