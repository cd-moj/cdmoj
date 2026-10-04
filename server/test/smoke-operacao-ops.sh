#!/bin/bash
# Operação › Juízes / Staff / Auditoria — o que a auditoria do painel (03/10/2026) pegou dando falsa impressão:
#   - opção de veredicto com ':' no texto do time era DESCARTADA calada e a tela dizia "✓ salvo";
#   - regex de escopo do staff que não compila salvava com "✓" e o staff passava a ver NADA;
#   - o feed da auditoria cortava em 500 sem avisar (e o CSV "p/ auditoria externa" saía truncado);
#     o filtro "usuário" só casava quem FEZ, nunca sobre quem foi (`user-disable login=ana`).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN"
NOW="$EPOCHSECONDS"; C="$FIX/op"; mkdir -p "$C/var" "$C/print-requests"
printf 'CONTEST_ID=op\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nMANUAL_VERDICT=1\n' "$((NOW-60))" "$((NOW+3600))" > "$C/conf"
fx_user "$C" op.admin p Admin; fx_user "$C" sala1.staff s Staff
printf 'CONTEST=op\nLOGIN=op.admin\nUSERFULLNAME=A\nLOGINAT=1\n' > "$SESS/adm"
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${4:-contest=op}" HTTP_AUTHORIZATION="Bearer adm" bash "$ROUTER" <<<"${3:-}" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:220}"; ((fail++)); fi; }
J(){ jq -r "$1" <<<"$BODY" 2>/dev/null; }

echo "== opções de veredicto: inválida é recusada com o nome, nada gravado =="
call /contest/final-verdicts POST '{"options":[{"label":"1 - YES","verdict":"Accepted"},{"label":"5 - NO","verdict":"Wrong Answer","team":"NO: contact staff"}]}'
ck "texto do time com ':' = 422 option_invalid com a opção" '[[ "$(J .error.code)" == option_invalid && "$(J .error.option)" == *"contact staff"* && ! -f "$C/final-verdicts.json" ]]'
call /contest/final-verdicts POST '{"options":[{"label":"1 - YES","verdict":"Accepted"},{"label":"5 - NO","verdict":"Wrong Answer","team":"NO - contact staff"}]}'
ck "sem ':' salva as duas" '[[ "$(J ".options | length")" == 2 ]]'

echo "== escopo do staff: regex que não compila é recusada =="
call /contest/admin/staff-filters POST '{"filters":{"sala1.staff":["^team(a"]}}'
ck "regex quebrada = 422 regex_invalid com a regra" '[[ "$(J .error.code)" == regex_invalid && "$(J .error.regex)" == "^team(a" ]]'
call /contest/admin/staff-filters POST '{"filters":{"sala1.staff":["^teama","region:Sede 1"]}}'
ck "regex boa + region: salvam" '[[ "$(J ".filters[\"sala1.staff\"] | length")" == 2 ]]'

echo "== auditoria: total e corte avisados; filtro de usuário casa os detalhes =="
for i in $(seq 1 600); do printf '%s\top.admin\tuser-disable\tlogin=user%s\n' "$((NOW-1000+i))" "$i"; done >> "$C/var/admin-audit.log"
printf '%s\top.admin\tuser-disable\tlogin=ana\n' "$NOW" >> "$C/var/admin-audit.log"
call /contest/admin/audit-log GET '' 'contest=op&action=user-disable'
ck "600+ eventos: count 500, total ≥ 601, truncated" '[[ "$(J .count)" == 500 && "$(J .total)" -ge 601 && "$(J .truncated)" == true ]]'
call /contest/admin/audit-log GET '' 'contest=op&action=user-disable&limit=5000'
ck "limit=5000 (o CSV) traz todos" '[[ "$(J .truncated)" == false && "$(J .count)" == "$(J .total)" ]]'
call /contest/admin/audit-log GET '' 'contest=op&user=ana'
ck "filtro de usuário casa sobre quem foi (login=ana nos detalhes)" '[[ "$(J "[.events[] | select(.details | test(\"login=ana\"))] | length")" -ge 1 ]]'

echo; echo "RESULT: $pass passed, $fail failed"; (( fail == 0 ))
