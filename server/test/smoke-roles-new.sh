#!/bin/bash
# smoke-roles-new.sh — os papéis de 09/11/2026 (registro server/etc/roles.tsv), todos com ESCOPO no staff-filters.json:
#   .foto     — sobe/troca a FOTO dos times do escopo (sem música); fora do escopo 403; sem escopo, NADA (falha fechado);
#   .musica   — o mesmo p/ a MÚSICA;
#   .sistemas — Máquinas: nutella (leitura/comandos da sede) e a trava de sede por IP (vê e SOLTA só os IPs da sede);
#   .diretor  — o placar SEM freeze só do recorte, ★ recalculada no recorte, falha fechado; o porteiro declina p/ o bash;
#   e o que os quatro têm em comum: não veem enunciado nem submetem; a nav de cada um; a classe no "sair em massa".
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN"
NOW="$EPOCHSECONDS"
C="$FIX/rn"; mkdir -p "$C/var" "$C/print-requests"
{ printf 'CONTEST_ID=rn\nCONTEST_TYPE=icpc\nCONTEST_MODULES=sedes,baloes,maquinas\nUSER_STORE=v2\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\nFREEZE_TIME=%s\n' "$((NOW-7200))" "$((NOW+3600))" "$((NOW-600))"
  printf 'PROBS=( x col#pa Alfa A col#pa x col#pb Beta B col#pb )\n'; } > "$C/conf"
for u in rn.admin norte.foto norte.musica norte.sistemas norte.diretor solto.foto solto.diretor; do fx_user "$C" "$u" p "$u"; done
for t in tn1 tn2 ts1; do fx_user "$C" "$t" x "Time $t"; done
jq -c '.team={name:"Norte Um",region:"Norte"}' "$C/users/tn1/account.json" > "$C/t" && mv "$C/t" "$C/users/tn1/account.json"
jq -c '.team={name:"Norte Dois",region:"Norte"}' "$C/users/tn2/account.json" > "$C/t" && mv "$C/t" "$C/users/tn2/account.json"
jq -c '.team={name:"Sul Um",region:"Sul"}' "$C/users/ts1/account.json" > "$C/t" && mv "$C/t" "$C/users/ts1/account.json"
printf '%s' '{"norte.foto":["region:Norte"],"norte.musica":["region:Norte"],"norte.sistemas":["region:Norte"],"norte.diretor":["region:Norte"]}' > "$C/print-requests/staff-filters.json"
for p in "rn.admin adm" "norte.foto nf" "norte.musica nm" "norte.sistemas ns" "norte.diretor nd" "solto.foto sf" "solto.diretor sd" "tn1 t1"; do set -- $p
  printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' rn "$1" "$1" "$NOW" > "$SESS/$2"; done
call(){ # <path> <method> <token> [query] [body]
  local b="${5:-}"
  OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="contest=rn${4:+&$4}" HTTP_AUTHORIZATION="Bearer $3" \
    CONTENT_LENGTH="${#b}" REMOTE_ADDR=127.0.0.9 TEAM_HOST_LOCK=0 bash "$ROUTER" <<<"$b" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
st(){ local s; s="$(printf '%s' "$OUT" | sed -n 's/^Status: \([0-9]*\).*/\1/p' | head -1)"; printf '%s' "${s:-200}"; }
pass=0; fail=0; OUT=""; BODY=""
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: $(st) ${BODY:0:240}"; ((fail++)); fi; }

echo "== navegação =="
nav(){ call /contest/navbuttons GET "$1"; jq -r '[.buttons[].url] | join(" ")' <<<"$BODY" 2>/dev/null; }
ck ".diretor: placar e documentos"       '[[ "$(nav nd)" == "/contest/score/ /contest/docs/ /logout" ]]'
ck ".foto: placar e telão"               '[[ "$(nav nf)" == "/contest/score/ /contest/animeitor/ /logout" ]]'
ck ".sistemas: placar, máquinas, docs"   '[[ "$(nav ns)" == "/contest/score/ /contest/mlinux/ /contest/docs/ /logout" ]]'
call /auth/status GET nd; ck "auth/status diz o papel (role)" '[[ "$(jq -r .role <<<"$BODY")" == diretor ]]'

echo "== fora da prova: sem enunciado, sem submeter =="
call /contest/problems GET nf; ck ".foto: problemas travados (staff)" '[[ "$(jq -r .locked <<<"$BODY")" == staff ]]'
call /contest/problems GET nd; ck ".diretor: idem"                    '[[ "$(jq -r .locked <<<"$BODY")" == staff ]]'
call /submit POST nd "" '{"problem_id":"col#pa","filename":"a.c","code_b64":"aQ=="}'
ck ".diretor não submete (403)"         '[[ "$(st)" == 403 && "$BODY" == *submit_forbidden* ]]'
call /contest/offline-submit POST nf "" '{"packets":[]}'
ck ".foto não submete offline (403)"    '[[ "$(st)" == 403 && "$BODY" == *submit_forbidden* ]]'
call /contest/print POST ns "" '{"filename":"a.c","file_b64":"aQ=="}'
ck ".sistemas não pede impressão (403)" '[[ "$(st)" == 403 && "$BODY" == *role_forbidden* ]]'

echo "== .foto / .musica =="
PNG="$(convert -size 8x8 xc:red png:- 2>/dev/null | base64 -w0)"
MP3="$(python3 -c 'import sys,base64; sys.stdout.write(base64.b64encode(bytes([0xFF,0xFB,0x90,0x64])+bytes(413)*1 ).decode()*0 + base64.b64encode((bytes([0xFF,0xFB,0x90,0x64])+bytes(413))*40).decode())')"
call /contest/animeitor/photo POST nf "" "{\"login\":\"tn1\",\"file_b64\":\"$PNG\"}"
ck ".foto sobe foto do time do escopo"   '[[ "$(st)" == 200 ]]'
call /contest/animeitor/photo POST nf "" "{\"login\":\"ts1\",\"file_b64\":\"$PNG\"}"
ck "…fora do escopo: 403 staff_scope"    '[[ "$(st)" == 403 && "$BODY" == *staff_scope* ]]'
call /contest/animeitor/music POST nf "" "{\"login\":\"tn1\",\"file_b64\":\"$MP3\"}"
ck ".foto NÃO sobe música (403)"         '[[ "$(st)" == 403 ]]'
call /contest/animeitor/music POST nm "" "{\"login\":\"tn2\",\"file_b64\":\"$MP3\"}"
ck ".musica sobe música do escopo"       '[[ "$(st)" == 200 ]]'
call /contest/animeitor/photo POST nm "" "{\"login\":\"tn2\",\"file_b64\":\"$PNG\"}"
ck ".musica NÃO sobe foto (403)"         '[[ "$(st)" == 403 ]]'
call /contest/animeitor/photo POST sf "" "{\"login\":\"tn1\",\"file_b64\":\"$PNG\"}"
ck ".foto SEM escopo: 403 (falha fechado)" '[[ "$(st)" == 403 ]]'
call /contest/animeitor/photos GET nf
ck "galeria do .foto: só o Norte"        '[[ "$(jq -r "[.teams[].login] | sort | join(\",\")" <<<"$BODY")" == "tn1,tn2" ]]'
call /contest/animeitor/photos GET sf
ck "galeria do .foto sem escopo: vazia"  '[[ "$(jq -r ".teams | length" <<<"$BODY")" == 0 ]]'
call /contest/animeitor/webcast GET nf
ck ".foto não vê as chaves do webcast"   '[[ "$(st)" == 403 ]]'

echo "== .sistemas =="
call /contest/nutella GET ns;  ck ".sistemas entra nas Máquinas"   '[[ "$(st)" == 200 ]]'
call /contest/nutella GET nf;  ck ".foto não entra (403)"          '[[ "$(st)" == 403 ]]'
source "$ROOT/api/v1/lib/common.sh" 2>/dev/null; source "$ROOT/api/v1/lib/site-lock.sh" 2>/dev/null
printf 'SITE_LOCK=1\n' >> "$C/conf"
sl_claim rn 10.0.0.1 tn1 >/dev/null 2>&1; sl_claim rn 10.0.0.2 ts1 >/dev/null 2>&1
# a auditoria site-lock-claim (ip= login=) é a do PRÓPRIO sl_claim — é dela que o recorte do .sistemas sai
ck "o sl_claim audita ip e login"        'grep -q "site-lock-claim.*ip=10.0.0.1 login=tn1" "$C/var/admin-audit.log"'
call /contest/admin/site-lock GET ns
ck ".sistemas vê só o IP da sede"         '[[ "$(jq -r "[.claims[].ip] | join(\",\")" <<<"$BODY")" == 10.0.0.1 ]]'
call /contest/admin/site-lock POST ns "" '{"action":"release","ip":"10.0.0.2"}'
ck "…soltar IP de outra sede: 403"        '[[ "$(st)" == 403 && "$BODY" == *site_forbidden* ]]'
call /contest/admin/site-lock POST ns "" '{"action":"set","enabled":false}'
ck "…desligar a trava: 403 (só o admin)"  '[[ "$(st)" == 403 ]]'
call /contest/admin/site-lock POST ns "" '{"action":"release","ip":"10.0.0.1"}'
ck "…soltar o IP da sede: ok"             '[[ "$(jq -r .released <<<"$BODY")" == true ]]'
# a máquina solta passa a OUTRA sede: o que a auditoria antiga diz (tn1 a reivindicou) não vale mais
sleep 1; sl_claim rn 10.0.0.1 ts1 >/dev/null 2>&1
call /contest/admin/site-lock GET ns
ck "IP solto e reivindicado pela outra sede: some do .sistemas" '[[ "$(jq -r "[.claims[].ip] | join(\",\")" <<<"$BODY")" == "" ]]'
call /contest/admin/site-lock POST ns "" '{"action":"release","ip":"10.0.0.1"}'
ck "…e soltá-lo: 403"                     '[[ "$(st)" == 403 && "$BODY" == *site_forbidden* ]]'
call /contest/admin/site-lock GET adm
ck "…o admin vê os dois presos"            '[[ "$(jq -r "[.claims[].ip] | sort | join(\",\")" <<<"$BODY")" == "10.0.0.1,10.0.0.2" ]]'
# a linha também sai sem soltura auditada (módulo desligado, varredura): vale a reivindicação mais recente
sl_claim rn 10.0.0.3 tn2 >/dev/null 2>&1
call /contest/admin/site-lock GET ns
ck "IP novo da sede: aparece"              '[[ "$(jq -r "[.claims[].ip] | join(\",\")" <<<"$BODY")" == 10.0.0.3 ]]'
sl_release rn 10.0.0.3; sleep 1; sl_claim rn 10.0.0.3 ts1 >/dev/null 2>&1
call /contest/admin/site-lock GET ns
ck "linha removida sem auditoria e reivindicada por outra sede: some" '[[ "$(jq -r "[.claims[].ip] | join(\",\")" <<<"$BODY")" == "" ]]'
call /contest/admin/site-lock POST ns "" '{"action":"release","ip":"10.0.0.3"}'
ck "…e soltá-lo: 403"                     '[[ "$(st)" == 403 && "$BODY" == *site_forbidden* ]]'

echo "== .diretor: o placar SEM freeze do recorte =="
# congelado (público) e completo; a ★ de B é do Sul (fora do recorte) e a de A, do Norte. Mais novos que o conf.
printf 'icpc s\ndesc:asc:flag:username:univ short:team name:univ full:A:B:Total:Penalty:LastAC\n:tn2::Norte Dois::1/600*:1/900:2:25:15\n:ts1::Sul Um:::1/300*:1:5:5\n:tn1::Norte Um::1/1200::1:20:20\n' > "$C/var/placar.txt"
printf 'icpc s\ndesc:asc:flag:username:univ short:team name:univ full:A:B:Total:Penalty:LastAC\n:tn1::Norte Um::1/1200:1/4000:2:87:66\n:tn2::Norte Dois::1/600*:1/900:2:25:15\n:ts1::Sul Um:::1/300*:1:5:5\n' > "$C/var/placar-full.txt"
touch -d '-1 hour' "$C/conf"; rm -f "$C/var/.score-dirty"
call /contest/score GET nd
ck "descongelado (X-MOJ-Frozen: 0)"       '[[ "$OUT" == *"X-MOJ-Frozen: 0"* && "$BODY" == *"1/4000"* ]]'
ck "só o Norte (o Sul não sai)"           '[[ "$BODY" != *"ts1"* && "$(grep -c "^:tn" <<<"$BODY")" == 2 ]]'
ck "★ de B recalculada no recorte (tn2)"  'grep -q "^:tn2::Norte Dois::1/600\*:1/900\*:" <<<"$BODY"'
ck "…e tn1 sem ★ em B"                    'grep -q "^:tn1::Norte Um::1/1200:1/4000:" <<<"$BODY"'
call /contest/score GET sd
ck "diretor SEM escopo: só o cabeçalho"   '[[ "$(grep -c . <<<"$BODY")" == 2 ]]'
call /contest/score GET t1
ck "o time segue no congelado"            '[[ "$OUT" == *"X-MOJ-Frozen: 1"* && "$BODY" != *"1/4000"* ]]'
# ★ CERTA NO GERAL, INCERTA NO RECORTE: a de B é do Sul (300 s); no Norte o melhor é tn2 (900 s), mas tn1 tem run de B
# NÃO JULGADA enviada aos 500 s — ela pode virar o 1º AC do recorte: a ★ espera (revisão de 10/11/2026)
ST="$(sed -n 's/^CONTEST_START=//p' "$C/conf")"
jq -cn --argjson e "$((ST+500))" '{by_problem:{"col#pb":{solved:false, pending:true, pending_min_epoch:$e}}}' > "$C/users/tn1/metrics.json"
call /contest/score GET nd
ck "pendente do recorte ANTES do melhor AC dele: B sem ★" 'grep -q "^:tn2::Norte Dois::1/600\*:1/900:" <<<"$BODY"'
jq -cn --argjson e "$((ST+1000))" '{by_problem:{"col#pb":{solved:false, pending:true, pending_min_epoch:$e}}}' > "$C/users/tn1/metrics.json"
call /contest/score GET nd
ck "…pendente DEPOIS do melhor AC: a ★ volta"           'grep -q "^:tn2::Norte Dois::1/600\*:1/900\*:" <<<"$BODY"'
jq -cn '{by_problem:{"col#pb":{solved:false, pending:true}}}' > "$C/users/tn1/metrics.json"
call /contest/score GET nd
ck "…metrics velho (sem o campo): conservador, sem ★"  'grep -q "^:tn2::Norte Dois::1/600\*:1/900:" <<<"$BODY"'
jq -cn --argjson e "$((ST+100))" '{by_problem:{"col#pb":{solved:false, pending:true, pending_min_epoch:$e}}}' > "$C/users/ts1/metrics.json"
rm -f "$C/users/tn1/metrics.json"
call /contest/score GET nd
ck "…pendente FORA do recorte não segura a ★ do recorte" 'grep -q "^:tn2::Norte Dois::1/600\*:1/900\*:" <<<"$BODY"'
rm -f "$C/users/ts1/metrics.json"
# ★ RETIDA no placar inteiro (run antiga pendente): o recorte também retém
printf 'icpc s\ndesc:asc:flag:username:univ short:team name:univ full:A:B:Total:Penalty:LastAC\n:tn2::Norte Dois::1/600:1/900:2:25:15\n:tn1::Norte Um::1/1200:1/4000:2:87:66\n' > "$C/var/placar-full.txt"
call /contest/score GET nd
ck "★ retida no completo = retida no recorte" '[[ "$BODY" != *"*"* ]]'

echo "== sair em massa: a classe do registro =="
call /contest/admin/logout-all GET adm
ck "foto/musica/sistemas = equipe da sala; diretor = organização" '[[ "$(jq -r ".sessions.staff" <<<"$BODY")" -ge 4 && "$(jq -r ".sessions.privileged" <<<"$BODY")" -ge 3 ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
