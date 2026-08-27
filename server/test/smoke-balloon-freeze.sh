#!/bin/bash
# Balão × FREEZE: AC feito com o placar congelado NÃO vira tarefa de entrega (o balão andando
# pela sala contaria o que o freeze esconde), a supressão é REGISTRADA (.balloon-frozen) e nem
# o "encerrar evento" (FREEZE_TIME=0) a desfaz. Só o admin desfaz, ligando a permissão — e aí
# os retidos saem todos. Pedido de IMPRESSÃO continua livre durante o freeze.
set -u
# o PISO do reconcile (1x/10s sob churn de veredicto) é comportamento de produção; aqui os
# cenários encadeiam reconciles em segundos e o que se testa é a SEMÂNTICA — piso desligado.
export BALLOON_RECONCILE_FLOOR_S=0
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
C="$FIX/bf"; mkdir -p "$C/var" "$C/print-requests"
NOW="$(date +%s)"; FZ=$((NOW-1800)); PRE=$((NOW-2400)); POS=$((NOW-600))
printf 'CONTEST_ID=bf\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nFREEZE_TIME=%s\nUSER_STORE=v2\nPROBS=( cdmoj apc#p1 Um A apc#p1 cdmoj apc#p2 Dois B apc#p2 )\n' \
  "$((NOW-3600))" "$((NOW+3600))" "$FZ" > "$C/conf"
fx_user "$C" bf.admin p "Admin"
fx_user "$C" sede.staff p "Staff"
fx_user "$C" aluno1 a "Aluno Um"
# aluno1: A resolvido ANTES do freeze, B DEPOIS. O 5º campo é o sub_epoch — é ele que manda,
# não o campo 1 (que em MANUAL_VERDICT é o instante em que o juiz decidiu).
{ printf '%s:apc#p1:C:Accepted,100p:%s:s1\n' "$PRE" "$PRE"
  printf '%s:apc#p2:C:Accepted,100p:%s:s2\n' "$NOW" "$POS"; } > "$C/users/aluno1/history"
touch "$C/var/.score-dirty"
printf 'CONTEST=bf\nLOGIN=bf.admin\nUSERFULLNAME=Admin\nLOGINAT=1\n' > "$SESS/adm"
printf 'CONTEST=bf\nLOGIN=sede.staff\nUSERFULLNAME=Staff\nLOGINAT=1\n' > "$SESS/stf"
printf 'CONTEST=bf\nLOGIN=aluno1\nUSERFULLNAME=Aluno\nLOGINAT=1\n' > "$SESS/alu"
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-adm}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
shorts(){ jq -r '[.requests[]|select(.kind=="balloon").short]|sort|join(",")' <<<"$BODY"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }

echo "== o AC do freeze não vira tarefa =="
call /contest/staff/queue GET '' adm 'contest=bf'
ck "balão do A (pré-freeze) existe"   '[[ "$(shorts)" == A ]]'
ck "balão do B (no freeze) NÃO existe" '[[ "$(jq -r "[.requests[]|select(.short==\"B\")]|length" <<<"$BODY")" == 0 ]]'
ck "a supressão foi registrada"        '[[ "$(grep -c "\"id\"" "$C/print-requests/.balloon-frozen" 2>/dev/null)" == 1 ]]'
ck "a lápide guarda o sub_epoch"       '[[ "$(jq -r .sub_epoch "$C/print-requests/.balloon-frozen")" == "'"$POS"'" ]]'
ck "auditado como balloon-frozen"      'grep -q "balloon-frozen" "$C/var/admin-audit.log"'
ck "contagem só p/ o admin"            '[[ "$(jq -r .balloons_frozen <<<"$BODY")" == 1 ]]'
call /contest/staff/queue GET '' stf 'contest=bf'
ck "staff não recebe a contagem"       '[[ "$(jq -r .balloons_frozen <<<"$BODY")" == 0 ]]'
ck "staff também não vê o balão de B"  '[[ "$(jq -r "[.requests[]|select(.short==\"B\")]|length" <<<"$BODY")" == 0 ]]'

echo "== impressão NÃO é afetada pelo freeze =="
call /contest/print POST '{"filename":"sol.c","file_b64":"aW50IG1haW4oKXtyZXR1cm4gMDt9"}' alu 'contest=bf'
ck "aluno imprime durante o freeze"    '[[ "$(jq -r .status <<<"$BODY")" == pending && "$(jq -r .success <<<"$BODY")" == true ]]'
call /contest/staff/queue GET '' adm 'contest=bf'
ck "impressão entra na fila do staff"  '[[ "$(jq -r "[.requests[]|select(.kind==\"print\")]|length" <<<"$BODY")" == 1 ]]'

echo "== encerrar o evento (FREEZE_TIME=0) NÃO ressuscita o suprimido =="
sed -i 's/^FREEZE_TIME=.*/FREEZE_TIME=0/' "$C/conf"
touch "$C/var/.score-dirty"                       # força o reconcile a varrer de novo
call /contest/staff/queue GET '' adm 'contest=bf'
ck "B continua sem balão sem o freeze" '[[ "$(shorts)" == A ]]'
ck "a lápide sobreviveu"               '[[ "$(grep -c "\"id\"" "$C/print-requests/.balloon-frozen" 2>/dev/null)" == 1 ]]'

echo "== só o admin desfaz: ligar a permissão libera os retidos =="
sed -i 's/^FREEZE_TIME=.*/FREEZE_TIME='"$FZ"'/' "$C/conf"
call /contest/admin/settings GET '' adm 'contest=bf'
ck "settings expõe o estado"           '[[ "$(jq -r .balloons_during_freeze <<<"$BODY")" == false && "$(jq -r .balloons_frozen <<<"$BODY")" == 1 ]]'
call /contest/admin/settings POST '{"balloons_during_freeze":true}' adm 'contest=bf'
ck "resposta diz quantos liberou"      '[[ "$(jq -r .balloons_released <<<"$BODY")" == 1 ]]'
ck "auditado o release"                'grep -q "balloon-freeze-release" "$C/var/admin-audit.log"'
call /contest/staff/queue GET '' adm 'contest=bf'
ck "agora o balão de B existe"         '[[ "$(shorts)" == A,B ]]'
ck "não duplicou o de A"               '[[ "$(jq -r "[.requests[]|select(.kind==\"balloon\")]|length" <<<"$BODY")" == 2 ]]'
call /contest/staff/queue GET '' adm 'contest=bf'
ck "reconcile segue idempotente"       '[[ "$(jq -r "[.requests[]|select(.kind==\"balloon\")]|length" <<<"$BODY")" == 2 ]]'

echo "== com a permissão ligada, AC novo no freeze entra direto =="
printf '%s:apc#p1:C:Accepted,100p:%s:s3\n' "$NOW" "$POS" >> "$C/users/sede.staff/history"  # papel: nunca ganha balão
fx_user "$C" aluno2 b "Aluno Dois"
printf '%s:apc#p2:C:Accepted,100p:%s:s4\n' "$NOW" "$POS" > "$C/users/aluno2/history"
touch "$C/var/.score-dirty"
call /contest/staff/queue GET '' adm 'contest=bf'
ck "aluno2 ganhou balão no freeze"     '[[ "$(jq -r "[.requests[]|select(.kind==\"balloon\" and .login==\"aluno2\")]|length" <<<"$BODY")" == 1 ]]'
ck "conta de papel não ganha balão"    '[[ "$(jq -r "[.requests[]|select(.login==\"sede.staff\")]|length" <<<"$BODY")" == 0 ]]'

echo "== (Ignored) não ganha balão =="
fx_user "$C" aluno3 c "Aluno Tres"
printf '%s:apc#p1:C:Accepted,100p (Ignored):%s:s5\n' "$PRE" "$PRE" > "$C/users/aluno3/history"
touch "$C/var/.score-dirty"
call /contest/staff/queue GET '' adm 'contest=bf'
ck "AC ignorado fica de fora"          '[[ "$(jq -r "[.requests[]|select(.login==\"aluno3\")]|length" <<<"$BODY")" == 0 ]]'

echo "== veredicto com ':' não quebra o parse do sub_epoch =="
fx_user "$C" aluno4 d "Aluno Quatro"
printf '%s:apc#p1:C:Accepted,100p. Pontos | 100 |:%s:s6\n' "$PRE" "$PRE" > "$C/users/aluno4/history"
touch "$C/var/.score-dirty"
call /contest/staff/queue GET '' adm 'contest=bf'
ck "AC com ':' no veredicto vira balão" '[[ "$(jq -r "[.requests[]|select(.login==\"aluno4\")]|length" <<<"$BODY")" == 1 ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
