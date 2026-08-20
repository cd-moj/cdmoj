#!/bin/bash
# /contest/score — o que a rota SERVE, e para quem.
#
# É a rota mais polada do contest (29% da mistura real) e a que mais mexeu na otimização de
# 20/08: a cascata de coortes virou um `ch_ctx` só e o `find` do piso de staleness passou a ser
# pago **depois** de um teste `-nt`. Duas famílias de risco, e é por isso que este teste existe:
#
#   VISIBILIDADE — qual arquivo cada login recebe. Convidado, time oficial, juiz, telão e
#     `SCORE_FULL_USERS` veem placares DIFERENTES; trocar um pelo outro vaza o placar
#     descongelado no meio da prova, que é o que o freeze existe para esconder.
#   FRESCOR — a guarda `-nt` decide se vale tentar regenerar. Se ela errar para o lado errado,
#     o placar **congela para sempre** e ninguém percebe: a rota responde 200, com dado velho.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"

C="$FIX/sv"; mkdir -p "$C/var"
T0=$(( $(date +%s) - 7200 )); TE=$(( T0 + 18000 ))
{ printf 'CONTEST_ID=sv\nCONTEST_TYPE=icpc\nCONTEST_NAME=Prova\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\nFREEZE_TIME=%s\n' "$T0" "$TE" "$(( T0 + 3600 ))"
  printf 'PROBS=( x c#a Alfa A c#a x c#b Beta B c#b )\n'; } > "$C/conf"
for u in time01 time02 conv01 sv.admin sv.judge sv.animeitor sv.cstaff livre01; do fx_user "$C" "$u" p "Nome $u"; done
# AC pré-freeze (todo mundo vê) e AC pós-freeze (só o placar full mostra)
printf '%s:c#a:C:Accepted,100p:%s:s1\n' "$(( T0 + 600 ))"  "$(( T0 + 600 ))"  > "$C/users/time01/history"
printf '%s:c#b:C:Accepted,100p:%s:s2\n' "$(( T0 + 7200 ))" "$(( T0 + 7200 ))" >> "$C/users/time01/history"
printf '%s:c#a:C:Accepted,100p:%s:s3\n' "$(( T0 + 900 ))"  "$(( T0 + 900 ))"  > "$C/users/conv01/history"
jq -cn '{results_released:false, cohorts:[
  {id:"oficial",  name:"Oficiais",   regex:"^time", public:true,  ranking:true, default:true},
  {id:"ccl",      name:"Convidados", regex:"^conv", public:false}]}' > "$C/cohorts.json"
for u in time01 time02 conv01 sv.admin sv.judge sv.animeitor sv.cstaff livre01; do
  printf 'CONTEST=sv\nLOGIN=%s\nUSERFULLNAME=X\nLOGINAT=1\n' "$u" > "$SESS/$u"
done
CONTESTSDIR="$FIX" RUNDIR="$FIX/run" bash "$ROOT/score/build.sh" sv >/dev/null 2>&1

call(){ BODY="$(PATH_INFO=/contest/score REQUEST_METHOD=GET QUERY_STRING="contest=sv${2:+&$2}" \
    HTTP_AUTHORIZATION="Bearer ${1:-}" CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$FIX/run" \
    SCORE_SERVE_FLOOR_S="${FLOOR:-8}" bash "$ROUTER" </dev/null 2>/dev/null \
    | awk 'f{print} /^\r?$/{f=1}')"; }
tem(){ grep -q "$1" <<<"$BODY"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1"; ((fail++)); fi; }

echo "== o placar existe e traz o modo na 1ª linha =="
call time01
ck "modo icpc na 1ª linha"        '[[ "$(head -1 <<<"$BODY")" == icpc* ]]'
ck "os times oficiais aparecem"   'tem time01 && tem time02'

echo "== COORTE: convidado de coorte privada não vaza p/ o placar público =="
ck "time oficial NÃO vê o convidado" '! tem conv01'
call conv01
ck "o convidado se vê no dele"       'tem conv01'
ck "e vê os oficiais junto"          'tem time01'
call ''
ck "anônimo cai no público"          '! tem conv01'
call time01 'view=oficial'
ck "?view=oficial força o público"   '! tem conv01'

echo "== FREEZE: só privilegiado recebe o placar descongelado =="
# o AC do problema B é pós-freeze: no congelado o time01 tem 1 resolvido, no full tem 2
call time01;       A_CONG="$BODY"
call sv.judge;     A_JUIZ="$BODY"
ck "juiz recebe corpo DIFERENTE do time" '[[ "$A_JUIZ" != "$A_CONG" ]]'
call sv.animeitor
ck "telão também recebe o descongelado"  '[[ "$BODY" != "$A_CONG" ]]'
call time02
ck "outro time segue no congelado"       '[[ "$BODY" == "$A_CONG" ]]'
# ⚠ `view=public` significa CONGELADO, não "visão pública de coorte" (essa é `view=oficial`):
# o juiz continua na visão dele (a `all`, que inclui o convidado), só que sem o descongelamento.
call sv.judge 'view=public'
ck "?view=public congela o juiz"     '[[ "$BODY" != "$A_JUIZ" ]]'
ck "mas ele segue na visão dele"     'tem conv01'
printf 'SCORE_FULL_USERS=livre01\n' >> "$C/conf"
sleep 1; CONTESTSDIR="$FIX" RUNDIR="$FIX/run" bash "$ROOT/score/build.sh" sv >/dev/null 2>&1
call livre01
ck "SCORE_FULL_USERS libera o full"      '[[ "$BODY" != "$A_CONG" ]]'
call time01
ck "e não vaza p/ quem não está na lista" '[[ "$BODY" == "$A_CONG" ]]'
# o .cstaff é privilegiado p/ COORTE (vê a visão `all`, como todo papel) mas NÃO p/ freeze:
# sem `scope=mine` + contest encerrado p/ todas as sedes, ele recebe o congelado.
call sv.cstaff
ck "cstaff vê a coorte all"          'tem conv01'
ck "mas CONGELADO (não é o do juiz)" '[[ "$BODY" != "$A_JUIZ" ]]'

echo "== FRESCOR: a guarda '-nt' não pode congelar o placar =="
# o risco da otimização: pular o regen quando ele era necessário. Aqui a submissão nova só
# aparece se a guarda deixar o rebuild acontecer.
printf '%s:c#a:C:Accepted,100p:%s:s9\n' "$(( T0 + 1200 ))" "$(( T0 + 1200 ))" > "$C/users/time02/history"
call time01
ck "sem carimbo de sujo, serve o velho" '[[ "$(grep -c . <<<"$BODY")" -ge 2 ]]'
sleep 1; touch "$C/var/.score-dirty"
FLOOR=0 call time01
ck "carimbo novo => REGENEROU"          '[[ "$(awk "/time02/{print}" <<<"$BODY" | grep -cE "[1-9]")" -ge 1 ]]'
ck "e o arquivo do placar é mais novo"  '[[ "$C/var/placar.txt" -nt "$C/var/.score-dirty" ]]'
# o conf também é fonte
sleep 1; printf 'PENALTY_MINUTES=15\n' >> "$C/conf"
FLOOR=0 call time01
ck "conf novo também regenera"          '[[ "$C/var/placar.txt" -nt "$C/conf" ]]'

echo "== e o PISO ainda segura rebuild concorrente =="
sleep 1; touch "$C/var/.score-dirty"
M0="$(stat -c %Y "$C/var/placar.txt")"
FLOOR=3600 call time01                    # sujo, mas dentro do piso: NÃO pode reconstruir
ck "dentro do piso, não reconstrói"     '[[ "$(stat -c %Y "$C/var/placar.txt")" == "$M0" ]]'
ck "e ainda assim responde 200 com corpo" '[[ -n "$BODY" ]]'
FLOOR=0 call time01
ck "fora do piso, reconstrói"           '[[ "$(stat -c %Y "$C/var/placar.txt")" != "$M0" ]]'

echo "== placar que NUNCA foi gerado nasce na 1ª chamada =="
rm -f "$C/var/placar"*.txt
FLOOR=3600 call time01                    # piso alto NÃO pode impedir a 1ª geração
ck "gera mesmo com piso alto"           '[[ -f "$C/var/placar.txt" ]]'
ck "e o corpo veio com os times"        'tem time01'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
