#!/bin/bash
# GET /contest/admin/judges — a lista de juízes do registro p/ o seletor de POOL em Regras, DENTRO do contest.
# Antes o seletor chamava /problems/judges, que o roteador barra no subdomínio do contest (403 contest_isolated)
# — o admin via o campo de texto livre em toda abertura (TCP 2026 / LATAM, 03/10/2026). As duas rotas leem o
# registro pela MESMA função (lib/judges-registry.sh) e devolvem o mesmo formato.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
C="$FIX/jc"; mkdir -p "$C/var" "$FIX/treino/var" "$RUN/registry"
{ printf 'CONTEST_ID=jc\nCONTEST_TYPE=icpc\nCONTEST_START=1\nCONTEST_END=%s\n' $(( EPOCHSECONDS + 9000 )); } > "$C/conf"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=treino\n' > "$FIX/treino/conf"
fx_user "$C" jc.admin p Admin; fx_user "$C" jc.cjudge p Chefe; fx_user "$C" jc.judge p Juiz; fx_user "$C" alice a Alice
fx_user "$FIX/treino" prof.admin p Prof
for l in jc.admin jc.cjudge jc.judge alice; do printf 'CONTEST=jc\nLOGIN=%s\nLOGINAT=1\n' "$l" > "$SESS/t-$l"; done
printf 'CONTEST=treino\nLOGIN=prof.admin\nLOGINAT=1\n' > "$SESS/t-treino"
# dois juízes: um vivo (batida agora) e um que sumiu
printf '{"host":"judge-a","cpu":"Ryzen","langs":["c","cpp"],"last_seen":%s}' "$EPOCHSECONDS" > "$RUN/registry/judge-a.json"
printf '{"host":"judge-b","cpu":"Xeon","langs":["py"],"last_seen":%s}' $(( EPOCHSECONDS - 3600 )) > "$RUN/registry/judge-b.json"

call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD=GET QUERY_STRING="${3:-}" HTTP_AUTHORIZATION="Bearer $2" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" CONTEST_HOST="${HOSTC:-}" bash "$ROUTER" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }

echo "== no subdomínio do contest: /problems/judges é barrado; /contest/admin/judges serve =="
HOSTC=jc call /problems/judges t-jc.admin
ck "/problems/judges → 403 contest_isolated"   '[[ "$OUT" == *"Status: 403"* && "$BODY" == *contest_isolated* ]]'
HOSTC=jc call /contest/admin/judges t-jc.admin 'contest=jc'
ck "admin: 200 com os dois juízes"             '[[ "$(jq -r ".success" <<<"$BODY")" == true && "$(jq -r ".judges|length" <<<"$BODY")" == 2 ]]'
ck "online primeiro, offline marcado"          '[[ "$(jq -c "[.judges[]|[.host,.online]]" <<<"$BODY")" == "[[\"judge-a\",true],[\"judge-b\",false]]" ]]'
ck "campos do seletor (cpu, langs)"            '[[ "$(jq -r ".judges[0].cpu" <<<"$BODY")" == Ryzen && "$(jq -c ".judges[0].langs" <<<"$BODY")" == "[\"c\",\"cpp\"]" ]]'

echo "== quem pode =="
call /contest/admin/judges t-jc.cjudge 'contest=jc'
ck "juiz-chefe: 200"                           '[[ "$(jq -r ".judges|length" <<<"$BODY")" == 2 ]]'
call /contest/admin/judges t-jc.judge 'contest=jc'
ck "juiz comum: 403"                           '[[ "$OUT" == *"Status: 403"* && "$BODY" == *admin_required* ]]'
call /contest/admin/judges t-alice 'contest=jc'
ck "time: 403"                                 '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/admin/judges t-treino 'contest=jc'
ck "sessão de outro contest: 403"              '[[ "$OUT" == *"Status: 403"* ]]'

echo "== a rota do treino segue igual (mesma função) =="
call /problems/judges t-treino
ck "/problems/judges: mesma lista"             '[[ "$(jq -c "[.judges[]|.host]" <<<"$BODY")" == "[\"judge-a\",\"judge-b\"]" && "$(jq -r .success <<<"$BODY")" == true ]]'
rm -f "$RUN"/registry/*.json
call /contest/admin/judges t-jc.admin 'contest=jc'
ck "registro vazio: [] (nunca corpo vazio)"    '[[ "$(jq -c ".judges" <<<"$BODY")" == "[]" ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
