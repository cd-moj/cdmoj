#!/bin/bash
# Fila do staff (impressão + balões): visão TOTAL do admin, escopo por regex do staff,
# ações do admin (processed/delivered) e a geração preguiçosa de balões (1ª solução aceita).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
C="$FIX/sc"; mkdir -p "$C/var" "$C/print-requests"
NOW="$(date +%s)"
printf 'CONTEST_ID=sc\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nUSER_STORE=v2\nPROBS=( cdmoj apc#p1 Um A apc#p1 )\n' "$NOW" "$((NOW+7200))" > "$C/conf"
fx_user "$C" sc.admin p "Admin"
fx_user "$C" sede1.staff p "Sede Um"
fx_user "$C" aluno1 a "Aluno Um"
fx_user "$C" aluno2 b "Aluno Dois"
# aluno1 resolveu A (gera tarefa de balão no load da fila); aluno2 só pediu impressão
printf '10:apc#p1:C:Accepted,100p:%s:s1\n' "$NOW" > "$C/users/aluno1/history"
touch "$C/var/.score-dirty"
printf '%s' "{\"id\":\"pr1\",\"seq\":1,\"kind\":\"print\",\"login\":\"aluno2\",\"fullname\":\"Aluno Dois\",\"team\":\"\",\"univ\":\"\",\"filename\":\"sol.c\",\"mime\":\"text/plain\",\"size\":10,\"time\":$NOW,\"status\":\"pending\",\"pages\":1,\"claimed_by\":\"\",\"claimed_at\":0,\"processed_by\":\"\",\"processed_at\":0,\"delivered_by\":\"\",\"delivered_at\":0}" > "$C/print-requests/pr1.json"
printf '%s' '{"sede1.staff":["^aluno2$"]}' > "$C/print-requests/staff-filters.json"
printf 'CONTEST=sc\nLOGIN=sc.admin\nUSERFULLNAME=Admin\nLOGINAT=1\n' > "$SESS/adm"
printf 'CONTEST=sc\nLOGIN=sede1.staff\nUSERFULLNAME=Sede\nLOGINAT=1\n' > "$SESS/stf"
printf 'CONTEST=sc\nLOGIN=aluno1\nUSERFULLNAME=Aluno\nLOGINAT=1\n' > "$SESS/alu"
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-adm}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }

echo "== fila: admin vê tudo (impressão + balão gerado do history) =="
call /contest/staff/queue GET '' adm 'contest=sc'
ck "admin vê a impressão pr1"    '[[ "$(jq -r ".requests[]|select(.id==\"pr1\").login" <<<"$BODY")" == aluno2 ]]'
BLN="$(jq -r '.requests[]|select(.kind=="balloon").id' <<<"$BODY")"
ck "balão do aluno1 foi gerado"  '[[ -n "$BLN" && "$(jq -r ".requests[]|select(.kind==\"balloon\").login" <<<"$BODY")" == aluno1 ]]'
ck "balão tem cor e problema"    '[[ -n "$(jq -r ".requests[]|select(.kind==\"balloon\").color_hex" <<<"$BODY")" && "$(jq -r ".requests[]|select(.kind==\"balloon\").short" <<<"$BODY")" == A ]]'
ck "pendentes primeiro (rank)"   '[[ "$(jq -r ".requests[0].status" <<<"$BODY")" == pending ]]'

echo "== escopo do staff (regex) =="
call /contest/staff/queue GET '' stf 'contest=sc'
ck "staff vê pr1 (aluno2 no escopo)" '[[ "$(jq -r ".requests[]|select(.id==\"pr1\").id" <<<"$BODY")" == pr1 ]]'
ck "staff NÃO vê o balão do aluno1"  '[[ "$(jq -r "[.requests[]|select(.kind==\"balloon\")]|length" <<<"$BODY")" == 0 ]]'
call /contest/staff/queue GET '' alu 'contest=sc'
ck "aluno não acessa a fila (403)"   '[[ "$OUT" == *"Status: 403"* ]]'

echo "== ações do ADMIN na fila =="
call /contest/staff/print-action POST "{\"id\":\"$BLN\",\"action\":\"delivered\"}" adm 'contest=sc'
ck "entregar sem processar 409"  '[[ "$OUT" == *"Status: 409"* ]]'
call /contest/staff/print-action POST '{"id":"pr1","action":"processed"}' adm 'contest=sc'
ck "admin marca processada"      '[[ "$(jq -r .updated.status <<<"$BODY")" == printed && "$(jq -r .updated.processed_by <<<"$BODY")" == "sc.admin" ]]'
call /contest/staff/print-action POST '{"id":"pr1","action":"delivered"}' adm 'contest=sc'
ck "admin marca entregue"        '[[ "$(jq -r .updated.status <<<"$BODY")" == delivered ]]'
call /contest/staff/print-action POST "{\"id\":\"$BLN\",\"action\":\"processed\"}" adm 'contest=sc'
call /contest/staff/print-action POST "{\"id\":\"$BLN\",\"action\":\"delivered\"}" adm 'contest=sc'
ck "balão entregue"              '[[ "$(jq -r .updated.status <<<"$BODY")" == delivered ]]'
call /contest/staff/queue GET '' adm 'contest=sc'
ck "fila reflete os estados"     '[[ "$(jq -r "[.requests[]|select(.status==\"delivered\")]|length" <<<"$BODY")" == 2 ]]'
ck "auditoria registrou as ações" 'grep -q "print-processed" "$C/var/admin-audit.log" && grep -q "balloon-delivered" "$C/var/admin-audit.log" && grep -q "balloon-task" "$C/var/admin-audit.log"'

echo "== idempotência do reconcile =="
call /contest/staff/queue GET '' adm 'contest=sc'
ck "não duplica o balão"         '[[ "$(jq -r "[.requests[]|select(.kind==\"balloon\")]|length" <<<"$BODY")" == 1 ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
