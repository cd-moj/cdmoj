#!/bin/bash
# smoke-prestart-login.sh — LOGIN ANTES DO INÍCIO conta como a máquina da prova (relato do Daniel Saad, 07/10/2026:
# "5 alunos logados, mas no painel só aparecem 3" — os 2 que faltavam logaram às 13:29 numa prova das 13:30).
#   Anomalias (/contest/admin/anomalies): o ÚLTIMO login antes do início é a máquina com que o time começa a prova
#     (`pre`) — entra em "máquinas na prova", em "trocou de máquina" e na máquina atual; trocar ANTES do início não
#     é anomalia; os canais de login seguem contando só a janela.
#   Gate & trava (/contest/admin/machines): os logins contam desde a ABERTURA do login (LOGIN_START_TIME), nunca
#     antes do fim da rodada anterior.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; [[ -n "${KEEP:-}" ]] && echo "FIX=$FIX SESS=$SESS" || trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
C="$FIX/pl"; mkdir -p "$C/var"
NOW=$EPOCHSECONDS; CS=$((NOW-3600)); CE=$((NOW+3600)); LST=$((CS-2100))
printf 'CONTEST_ID=pl\nCONTEST_MODULES=maquinas\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nLOGIN_START_TIME=%s\nUSER_STORE=v2\n' "$CS" "$CE" "$LST" > "$C/conf"
printf "PROBS=( x col#pa Alfa A col#pa )\n" >> "$C/conf"
# rodada anterior (aquecimento) terminou 30 min antes do início — o mapa da prova não pode puxar logins dela
jq -n --argjson cs "$CS" --argjson ce "$CE" '{version:1, active:"oficial", rounds:[
  {slug:"aquec", name:"Aquecimento", kind:"warmup", state:"archived", start:($cs-9000), end:($cs-1800)},
  {slug:"oficial", name:"Prova", kind:"official", state:"active", start:$cs, end:$ce}]}' > "$C/rounds.json"
fx_user "$C" pl.admin p Admin >/dev/null
for u in t1 t2 t3 t4 t5; do fx_user "$C" $u x "Time $u" >/dev/null; done
b64(){ printf '%s' "$1" | base64 -w0; }
ua(){ printf 'Mozilla/5.0 (MLinux/lab/%s/%s/e0-d5-5e-f5-d0-%s) Gecko Firefox/140.0' "$1" "$2" "$3"; }
M(){ printf '%032d' "$1"; }
row(){ printf '%s\t%s\t10.0.0.%s\t%s\n' "$1" "$2" "$3" "$(b64 "$4")"; }
{ row $((CS-25))   t1 1 "$(ua $(M 1) 101 01)"     # como o Erick: 25 s antes, e só
  row $((CS-1000)) t2 2 "$(ua $(M 21) 121 21)"    # trocou de máquina ANTES do início: não é anomalia
  row $((CS-30))   t2 2 "$(ua $(M 22) 122 22)"
  row $((CS-20))   t3 3 "$(ua $(M 31) 131 31)"    # começou numa, foi p/ outra DEPOIS do início: trocou
  row $((CS+600))  t3 3 "$(ua $(M 32) 132 32)"
  row $((CS+5))    t4 4 "$(ua $(M 4) 104 04)"     # dentro da janela, como sempre
  row $((CS-2500)) t5 5 "$(ua $(M 5) 105 05)"     # durante o aquecimento (antes do fim dele): fora do mapa da prova
} > "$C/var/access.log"
printf 'CONTEST=pl\nLOGIN=pl.admin\nLOGINAT=1\n' > "$SESS/adm"
# a sessão viva de cada time é a do ÚLTIMO login (como o login grava: IP, UA e a chave da máquina). Com o MAC no UA a
# chave da máquina é estável: `m:<machine_id>` (sem o boot — lib/anomalies.sh idk)
ses(){ printf 'CONTEST=pl\nLOGIN=%s\nUSERFULLNAME=x\nLOGINAT=%s\nIP=10.0.0.%s\nUA_B64=%s\nMKEY=m:%s/%s\n' "$1" "$2" "$3" "$(b64 "$(ua "$4" "$5" "$6")")" "$4" "$5" > "$SESS/s-$1"; }
ses t1 $((CS-25)) 1 "$(M 1)" 101 01; ses t2 $((CS-30)) 2 "$(M 22)" 122 22
ses t3 $((CS+600)) 3 "$(M 32)" 132 32; ses t4 $((CS+5)) 4 "$(M 4)" 104 04
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD=GET QUERY_STRING="contest=pl" HTTP_AUTHORIZATION="Bearer adm" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" </dev/null 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
J(){ jq -r "$1" <<<"$BODY" 2>/dev/null; }
TM(){ J "[.teams[]|select(.login==\"$1\")|.machines[]|select(.in > 0)|.key]|join(\" \")"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:240}"; ((fail++)); fi; }

echo "== Anomalias: o último login antes do início é a máquina da prova =="
call /contest/admin/anomalies
ck "t1 (25 s antes) tem a máquina na prova, marcada pre" '[[ "$(TM t1)" == "m:$(M 1)" && "$(J "[.teams[]|select(.login==\"t1\")|.machines[]|select(.in > 0)|.pre][0]")" == 1 ]]'
ck "t2: só a ÚLTIMA antes do início conta (trocar antes não é anomalia)" '[[ "$(TM t2)" == "m:$(M 22)" && -z "$(J ".anomalies[]|select(.kind==\"switched\" and .login==\"t2\")|.login")" ]]'
ck "t3: começou numa e foi p/ outra depois do início = trocou de máquina" '[[ "$(J ".anomalies[]|select(.kind==\"switched\" and .login==\"t3\")|.machine")" == "m:$(M 31) → m:$(M 32)" ]]'
ck "t4 (dentro da janela) segue igual, sem pre" '[[ "$(TM t4)" == "m:$(M 4)" && "$(J "[.teams[]|select(.login==\"t4\")|.machines[]|select(.in > 0)|.pre][0]")" == 0 ]]'
ck "canais de login contam só a janela (t3 e t4)" '[[ "$(J ".channels.logins.web")" == 2 ]]'

echo "== Gate & trava: logins desde a abertura do login, sem invadir a rodada anterior =="
call /contest/admin/machines
ck "mapa com t1..t4 (os de antes do início entram)" '[[ "$(J "[.by_login[].login]|sort|join(\",\")")" == "t1,t2,t3,t4" ]]'
ck "t5 (durante o aquecimento) fora"   '[[ "$(J "[.by_login[]|select(.login==\"t5\")]|length")" == 0 ]]'
ck "janela diz desde quando (fim do aquecimento, que é depois da abertura do login)" '[[ "$(J .window.logins_from)" == "$((CS-1800))" && "$(J .window.start)" == "$CS" ]]'
jq --argjson cs "$CS" --argjson ce "$CE" '.rounds = [.rounds[] | select(.slug != "aquec")]' "$C/rounds.json" > "$C/r.t" && mv "$C/r.t" "$C/rounds.json"
call /contest/admin/machines
ck "sem rodada anterior: desde a abertura do login (LOGIN_START_TIME) — t5 ainda antes dela, fora" '[[ "$(J .window.logins_from)" == "$LST" && "$(J "[.by_login[].login]|sort|join(\",\")")" == "t1,t2,t3,t4" ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
