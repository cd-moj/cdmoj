#!/bin/bash
# Encerrar evento (GET/POST /contest/admin/finish): o checklist pós-prova e a ação que abre
# o placar + publica os documentos. O que importa aqui: não age com a prova em andamento,
# descongela DE VERDADE (conf), publica só o que estava gerado, é idempotente e não deixa
# ninguém além do admin encostar.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"

C="$FIX/fin"; mkdir -p "$C/var" "$C/docs"
NOW=$(date +%s); T0=$(( NOW - 7200 )); TE=$(( NOW - 600 )); FZ=$(( NOW - 1800 ))
mkconf(){ # mkconf <fim> <freeze>
  { printf 'CONTEST_ID=fin\nCONTEST_TYPE=icpc\nCONTEST_NAME=Prova\\ Fim\n'
    printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$T0" "$1"
    (( $2 > 0 )) && printf 'FREEZE_TIME=%s\n' "$2"
    printf "PROBS=( x col#pa Alfa A col#pa )\n"; } > "$C/conf"
}
mkconf "$TE" "$FZ"
fx_user "$C" fin.admin p "Admin"
fx_user "$C" fin.cjudge p "Chefe"
fx_user "$C" alice a "Time Alice"
printf '10:col#pa:C:Accepted,100p:%s:sA1\n' "$(( T0 + 600 ))" > "$C/users/alice/history"
printf 'CONTEST=fin\nLOGIN=fin.admin\nLOGINAT=1\n' > "$SESS/adm"
printf 'CONTEST=fin\nLOGIN=fin.cjudge\nLOGINAT=1\n' > "$SESS/cjd"
printf 'CONTEST=fin\nLOGIN=alice\nLOGINAT=1\n' > "$SESS/usr"
# documentos: caderno + folha de TL gerados; NADA publicado ainda
printf '%%PDF-1.4 caderno\n' > "$C/docs/contest.pt.pdf"
printf '%%PDF-1.4 tl\n'      > "$C/docs/times.pt.pdf"
jq -cn '{caderno_version:"v1.0",published:[]}' > "$C/docs/config.json"

call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="contest=fin" HTTP_AUTHORIZATION="Bearer ${4:-adm}" \
  CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1"; echo "      $BODY"; ((fail++)); fi; }
J(){ printf '%s' "$BODY" | jq -r "$1" 2>/dev/null; }

echo "== gates =="
call /contest/admin/finish GET '' usr
ck "não-admin → 403" '[[ "$OUT" == *"Status: 403"* ]]'
# juiz-chefe LÊ o checklist (o 403 fazia o cartão da Central sumir p/ o .cjudge — 29/08),
# mas não AGE: can_act diz ao front quem pode apertar o botão.
call /contest/admin/finish GET '' cjd
ck "juiz-chefe GET → 200 + can_act:false" '[[ "$OUT" == *"Status: 200"* && "$(J .can_act)" == false ]]'
call /contest/admin/finish POST '{"action":"finish"}' cjd
ck "juiz-chefe POST → 403"               '[[ "$OUT" == *"Status: 403"* ]]'

echo "== prova AINDA em andamento =="
mkconf "$(( NOW + 3600 ))" "$FZ"
call /contest/admin/finish GET ''
ck "checklist diz que não dá p/ encerrar" '[[ "$(J .can_finish)" == false ]] && [[ "$(J "[.checks[]|select(.id==\"fim\")][0].level")" == warn ]]'
call /contest/admin/finish POST '{"action":"finish"}'
ck "POST recusado → 409 contest_running" '[[ "$OUT" == *"Status: 409"* && "$OUT" == *contest_running* ]]'
ck "não descongelou nada"                'grep -q "FREEZE_TIME=$FZ" "$C/conf"'

echo "== prova encerrada: checklist =="
mkconf "$TE" "$FZ"
call /contest/admin/finish GET ''
ck "pode encerrar"                    '[[ "$(J .can_finish)" == true ]]'
ck "admin vê can_act:true"            '[[ "$(J .can_act)" == true ]]'
ck "placar congelado = pendência"     '[[ "$(J "[.checks[]|select(.id==\"freeze\")][0].level")" == fail ]]'
ck "2 documentos pendentes"           '[[ "$(J ".pending_docs|length")" == 2 ]]'
ck "informativos aparecem (show_log)" '[[ -n "$(J "[.checks[]|select(.id==\"show_log\")][0].label")" ]]'

echo "== encerrar =="
# corrida de mtime (29/08): um stamp deixado por um build em voo tem de ser REMOVIDO pelo
# encerramento — é o `! -f` que garante o recompute em massa. Seguramos o .placar.lock no
# teste p/ o build destacado não re-carimbar antes da asserção.
touch "$C/var/.metrics-stamp"
exec 8>>"$C/var/.placar.lock"; flock 8
call /contest/admin/finish POST '{"action":"finish"}'
ck "200 + finished"                   '[[ "$(J .finished)" == true ]]'
ck "descongelou no conf"              'grep -q "^FREEZE_TIME=0$" "$C/conf"'
ck "placar marcado p/ reconstruir"    '[[ -f "$C/var/.score-dirty" ]]'
ck "stamp dos metrics REMOVIDO"       '[[ ! -f "$C/var/.metrics-stamp" ]]'
ck "publicou os 2 documentos"         '[[ "$(jq -r ".published|length" "$C/docs/config.json")" == 2 ]]'
ck "entraram na seção Prova"          '[[ "$(jq -r "length" "$C/resources.json")" == 2 ]] && grep -q "type=contest" "$C/resources.json"'
ck "auditado"                         'grep -q "finish-event" "$C/var/admin-audit.log"'

echo "== idempotência =="
call /contest/admin/finish POST '{"action":"finish"}'
ck "2ª vez não faz nada"              '[[ "$(J ".done|length")" == 0 ]] && [[ "$(J "[.skipped[].item]|index(\"placar\")")" != null ]]'
call /contest/admin/finish GET ''
ck "checklist agora está verde"       '[[ "$(J .summary.fail)" == 0 ]]'

echo "== action inválida =="
call /contest/admin/finish POST '{"action":"boom"}'
ck "→ 400"                            '[[ "$OUT" == *"Status: 400"* ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
