#!/bin/bash
# Anomalias de uso de máquina (/contest/admin/anomalies, lib/anomalies.sh): time com 2 sessões
# vivas em máquinas diferentes, máquina com 2 times, submissão de outra máquina (e reboot),
# UA fora do esperado, sede com menos máquinas que times, troca de máquina, trilha de eventos.
# Também: gate desligado ⇒ nada disso vale; papéis; seeding do índice pela varredura; ARG_MAX.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; [[ -n "${KEEP:-}" ]] && echo "FIX=$FIX SESS=$SESS" || trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
C="$FIX/an"; mkdir -p "$C/var"
NOW=$EPOCHSECONDS; CS=$((NOW-3600)); CE=$((NOW+3600))
printf 'CONTEST_ID=an\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nUSER_STORE=v2\n' "$CS" "$CE" > "$C/conf"
printf "PROBS=( x col#pa Alfa A col#pa )\n" >> "$C/conf"
fx_user "$C" an.admin p "Admin"; fx_user "$C" cj.cjudge p "Chefe"
for u in teamaa001 teamaa002 teamaa003 teamaa004 teamaa005; do fx_user "$C" $u x "Time $u"; done
jq -c '.team={region:"Sede A"}' "$C/users/teamaa001/account.json" > "$C/x" && mv "$C/x" "$C/users/teamaa001/account.json"
# gate: a imagem manda "MLinux/26aa/…" e o esperado do login teamaa001 é "aa" (captura)
jq -n '{mode:"enforce", from_login:{regex:"^team([a-z]{2})[0-9]{3}$", expect:"\\1"}}' > "$C/ua-gate.json"
b64(){ printf '%s' "$1" | base64 -w0; }
MID1=11111111111111111111111111111111; MID2=22222222222222222222222222222222; MIDC=cccccccccccccccccccccccccccccccc; MID4=44444444444444444444444444444444
ua(){ printf 'Mozilla/5.0 (MLinux/26aa/%s/%s) Gecko Firefox/148.0' "$1" "$2"; }
UA_M1="$(ua $MID1 1001)"; UA_M2="$(ua $MID2 2002)"; UA_M3="$(ua $MIDC 3003)"; UA_M3b="$(ua $MIDC 9009)"; UA_M4="$(ua $MID4 4004)"; UA_M5="$(ua $MIDC 5005)"
# access.log: 001 em M1 e depois M2 (troca) · 002 e 003 em M3 (compartilhada) · 004 só de manhã · 005 no clone de M3 com outro boot
{ printf '%s\tteamaa001\t10.0.0.1\t%s\n' "$((CS+60))"   "$(b64 "$UA_M1")"
  printf '%s\tteamaa001\t10.0.0.2\t%s\n' "$((CS+600))"  "$(b64 "$UA_M2")"
  printf '%s\tteamaa002\t10.0.0.3\t%s\n' "$((CS+100))"  "$(b64 "$UA_M3")"
  printf '%s\tteamaa003\t10.0.0.3\t%s\n' "$((CS+700))"  "$(b64 "$UA_M3")"
  printf '%s\tteamaa004\t10.0.0.4\t%s\n' "$((CS-3000))" "$(b64 "$UA_M4")"
  printf '%s\tteamaa005\t10.0.0.5\t%s\n' "$((CS+200))"  "$(b64 "$UA_M5")"
  printf '%s\tan.admin\t10.0.0.9\t%s\n'  "$((CS+10))"   "$(b64 'Mozilla Chrome')"
  # sede atrás de NAT sem UA do mlinux: mesmo IP p/ dois times NÃO é máquina compartilhada
  printf '%s\tteamnn001\t10.9.9.9\t%s\n' "$((CS+300))" "$(b64 'Mozilla Chrome NAT')"
  printf '%s\tteamnn002\t10.9.9.9\t%s\n' "$((CS+310))" "$(b64 'Mozilla Chrome NAT')"
} > "$C/var/access.log"
fx_user "$C" teamnn001 x "NAT 1"; fx_user "$C" teamnn002 x "NAT 2"
mkses(){ printf 'CONTEST=an\nLOGIN=%q\nUSERFULLNAME=x\nLOGINAT=%q\nIP=%q\nUA_B64=%q\n%s' "$2" "$3" "$4" "$(b64 "$5")" "${6:+MKEY=$6
}" > "$SESS/$1"; }
mkses s1 teamaa001 "$((CS+60))"  10.0.0.1 "$UA_M1"           # 001: DUAS sessões vivas em máquinas diferentes
mkses s2 teamaa001 "$((CS+600))" 10.0.0.2 "$UA_M2" "m:$MID2/2002"
mkses s3 teamaa002 "$((CS+100))" 10.0.0.3 "$UA_M3"
mkses s4 teamaa003 "$((CS+700))" 10.0.0.3 "$UA_M3"           # 002 e 003 vivos na MESMA máquina ⇒ bad
mkses s5 teamaa004 "$((CS-3000))" 10.0.0.4 "Mozilla Chrome"  # UA fora do esperado (entrou antes do gate)
printf 'CONTEST=an\nLOGIN=an.admin\nLOGINAT=1\n' > "$SESS/adm"
printf 'CONTEST=an\nLOGIN=cj.cjudge\nLOGINAT=1\n' > "$SESS/chief"
mkses comp teamaa005 "$((CS+200))" 10.0.0.5 "$UA_M5" "m:$MIDC/5005"   # competidor (token p/ o teste de 403)
# submit-origin: 001 submete de M2 com sessão de M1 (bad) · 002 submete de M3 reiniciada (reboot=info) · 003 normal
{ printf '%s\tsub1\tteamaa001\t10.0.0.2\t%s\t10.0.0.1\t%s\tm:%s/1001\tabcdef01\n' "$((CS+900))" "$(b64 "$UA_M2")" "$(b64 "$UA_M1")" "$MID1"
  printf '%s\tsub2\tteamaa002\t10.0.0.3\t%s\t10.0.0.3\t%s\tm:%s/3003\tabcdef02\n' "$((CS+950))" "$(b64 "$UA_M3b")" "$(b64 "$UA_M3")" "$MIDC"
  printf '%s\tsub3\tteamaa003\t10.0.0.3\t%s\t10.0.0.3\t%s\tm:%s/3003\tabcdef03\n' "$((CS+960))" "$(b64 "$UA_M3")" "$(b64 "$UA_M3")" "$MIDC"
} > "$C/var/submit-origin.log"
printf '%s\tteamaa001\trevoke\tm:%s/1001\tm:%s/2002\tdeadbeef\n' "$((CS+600))" "$MID1" "$MID2" > "$C/var/session-events.log"
jq -n '{collected_at:1, sedes:[{name:"Sede A", machines_total:2, seen:1, teams:["teamaa001","teamaa002","teamaa003"], pop:{teams:3, present:3}},
                                {name:"Sede B", machines_total:9, seen:9, teams:["teamaa004"], pop:{teams:1, present:1}}]}' > "$C/var/nutella.cache.json"

call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-adm}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:300}"; ((fail++)); fi; }
J(){ printf '%s' "$BODY" | jq -r "$1" 2>/dev/null; }
K(){ printf '%s' "$BODY" | jq -r ".anomalies[]|select(.kind==\"$1\")|$2" 2>/dev/null; }

echo "== gates =="
call /contest/admin/anomalies GET '' comp 'contest=an'
ck "competidor → 403"                 '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/admin/anomalies GET '' chief 'contest=an'
ck "juiz-chefe lê"                    '[[ "$(J .success)" == true && "$(J .gate.active)" == true ]]'

echo "== apuração (admin) =="
call /contest/admin/anomalies GET '' adm 'contest=an'
ck "gate ativo, sessão única ligada"  '[[ "$(J .gate.active)" == true && "$(J .gate.single_session)" == true && "$(J .gate.mode)" == enforce ]]'
ck "janela = a prova"                 '[[ "$(J .window.start)" == "$CS" ]]'
ck "contagens: 1 multi-sessão, 1 compartilhada, 1 sub de outra máquina, 1 reboot, 1 UA fora, 1 sede curta, 1 troca, 1 revogação" \
   '[[ "$(J ".counts|[.multi_session,.machine_shared,.sub_other_machine,.reboot,.ua_mismatch,.site_short,.switched,.revoked]|join(\",\")")" == "1,1,1,1,1,1,1,1" ]]'
ck "multi_session: teamaa001, bad, 2 chaves"  '[[ "$(K multi_session .login)" == teamaa001 && "$(K multi_session .severity)" == bad && "$(K multi_session ".detail.keys|length")" == 2 ]]'
ck "machine_shared: 002+003 vivos na mesma ⇒ bad" '[[ "$(K machine_shared .severity)" == bad && "$(K machine_shared ".detail.logins|length")" == 2 && "$(K machine_shared .detail.live_both)" == true ]]'
ck "clone com boot diferente NÃO é compartilhada (005 fora)" '[[ "$(K machine_shared .login)" != *teamaa005* ]]'
ck "mesmo IP sem UA mlinux (NAT) NÃO é máquina compartilhada" '[[ "$(K machine_shared .login)" != *teamnn* && "$(J .counts.machine_shared)" == 1 ]]'
ck "sub_other_machine: sub1 de 001 bad; sub2 de 002 = reboot info" \
   '[[ "$(K sub_other_machine "select(.severity==\"bad\")|.detail.subid")" == sub1 && "$(K sub_other_machine "select(.severity==\"info\")|.detail.subid")" == sub2 && "$(K sub_other_machine "select(.severity==\"info\")|.detail.reboot")" == true ]]'
ck "ua_mismatch: 004 (Chrome vs esperado aa)"  '[[ "$(K ua_mismatch .login)" == teamaa004 && "$(K ua_mismatch .detail.expected)" == aa ]]'
ck "site_short: Sede A (1 máquina vista p/ 3 presentes)" '[[ "$(K site_short .name)" == "Sede A" && "$(J ".sites|length")" == 1 ]]'
ck "switched: 001 (M1 → M2)"          '[[ "$(K switched .login)" == teamaa001 && "$(K switched ".detail.machines|length")" == 2 ]]'
ck "evento de revogação na trilha"    '[[ "$(J ".events[0].detail.event")" == revoke && "$(J ".events[0].login")" == teamaa001 ]]'
ck "teams: 001 com flags multi_session+switched+sub_other_machine" '[[ "$(J ".teams[]|select(.login==\"teamaa001\")|.flags|join(\",\")")" == *multi_session* && "$(J ".teams[]|select(.login==\"teamaa001\")|.flags|join(\",\")")" == *switched* && "$(J ".teams[]|select(.login==\"teamaa001\")|.flags|join(\",\")")" == *sub_other_machine* ]]'
ck "teams: 001 tem 2 sessões e 2 máquinas; última sub NÃO da sessão" '[[ "$(J ".teams[]|select(.login==\"teamaa001\")|.sessions|length")" == 2 && "$(J ".teams[]|select(.login==\"teamaa001\")|.last_sub.same_as_session")" == false ]]'
ck "teams: 004 só de manhã, sem troca"  '[[ "$(J ".teams[]|select(.login==\"teamaa004\")|.flags|join(\",\")")" == ua_mismatch ]]'
ck "machines: M3 compartilhada e viva"  '[[ "$(J ".machines[]|select(.key==\"m:$MIDC/3003\")|.shared")" == true ]]'
ck "papéis fora de tudo"              '[[ "$(J "[.teams[].login]|index(\"an.admin\")")" == null ]]'
ck "cache de resposta gravado"        '[[ -s "$C/var/.anomalies-cache.active.json" ]]'

echo "== índice semeado pela varredura =="
ck "marcador .seeded + tokens de 001" '[[ -e "$SESS/.idx/an/.seeded" && "$(sort -u "$SESS/.idx/an/teamaa001" | wc -l)" == 2 ]]'
sleep 1; touch "$C/var/access.log"    # invalida o cache (entrada mais nova)
call /contest/admin/anomalies GET '' adm 'contest=an'
ck "2ª chamada (pelo índice) dá o mesmo" '[[ "$(J .counts.multi_session)" == 1 && "$(J .counts.sessions)" == 6 ]]'

echo "== gate desligado ⇒ nada vale =="
jq -c '.mode="off"' "$C/ua-gate.json" > "$C/x" && mv "$C/x" "$C/ua-gate.json"
call /contest/admin/anomalies GET '' adm 'contest=an'
ck "gate.active=false, sem anomalias, contagens zeradas, sessões contadas" '[[ "$(J .gate.active)" == false && "$(J ".anomalies|length")" == 0 && "$(J .counts.multi_session)" == 0 && "$(J .counts.sessions)" == 6 ]]'
jq -c '.mode="enforce"' "$C/ua-gate.json" > "$C/x" && mv "$C/x" "$C/ua-gate.json"

echo "== rodada inválida / ARG_MAX =="
call /contest/admin/anomalies GET '' adm 'contest=an&round=Nao%20Existe'
ck "round inválido → 400"             '[[ "$OUT" == *"Status: 400"* ]]'
for i in $(seq 1 1500); do printf '%s\tteamzz%04d\t10.1.%d.%d\t%s\n' "$((CS+i))" "$i" "$((i/250))" "$((i%250))" "$(b64 "Mozilla/5.0 (MLinux/26aa/$(printf '%032d' $i)/777) Gecko Firefox/148.0 padding-padding-padding-padding-padding")"; done >> "$C/var/access.log"
for i in $(seq 1 1500); do fx_user "$C" "$(printf 'teamzz%04d' $i)" x "Z $i" >/dev/null; done
call /contest/admin/anomalies GET '' adm 'contest=an'
ck "1500 logins (access.log >128 KiB): corpo válido e contagens intactas" '[[ "$(J .success)" == true && "$(stat -c %s "$C/var/access.log")" -gt 131072 && "$(J .counts.multi_session)" == 1 && "$(J .counts.teams_live)" == 5 ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
