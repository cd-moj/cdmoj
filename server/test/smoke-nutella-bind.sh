#!/bin/bash
# smoke-nutella-bind.sh — o LOGIN publica no NutellaBoot o elo máquina↔time (lib/nutella-bind.sh).
# O agente novo do mlinux põe o MAC no fim do UA; o login enfileira e um drenador faz o
# `PUT …/machines/{mac}/binding`. Contra o mock ESTRITO (404 se o time não está no roster).
# Prende: só UA com MAC · papel nunca · módulo/chave/NUTELLA_BIND · imagem de OUTRO evento recusada ·
# dedup (re-login não vira request) · reboot republica · 404 do roster no log · 503 ⇒ retry que
# entrega depois · push-bindings (replay do access.log) · resumo no GET sem MAC nem login.
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; MOCKD="$(mktemp -d)"; MOCKPID=""
cleanup(){ [[ -n "$MOCKPID" ]] && kill "$MOCKPID" 2>/dev/null; rm -rf "$FIX" "$SESS" "$MOCKD"; }
trap cleanup EXIT
source "$HERE/fixture.sh"
export MOJ_JOBS_SYNC=1      # o drenador roda em linha (em produção é destacado, no máx. 1 a cada 10 s)

C="$FIX/nb"; mkdir -p "$C/var" "$C/secrets"
NOW=$EPOCHSECONDS
{ printf 'CONTEST_ID=nb\nCONTEST_TYPE=icpc\nCONTEST_NAME=Bind\nCONTEST_START=%s\nCONTEST_END=%s\n' "$((NOW-600))" "$((NOW+3600))"
  printf 'CONTEST_MODULES=maquinas\nNUTELLABOOT_IMAGES=26tsca\n'
  printf "PROBS=( x col#pa Alfa A col#pa )\n"; } > "$C/conf"
for u in nb.admin alice bob carol; do fx_user "$C" $u pw "Conta $u"; done
printf 'CONTEST=nb\nLOGIN=nb.admin\nLOGINAT=1\n' > "$SESS/adm"

jq -n '{images:[{id:"26tsca", fullname:"Cidade A"}, {id:"26outro", fullname:"Outro Evento"}]}' > "$MOCKD/images.json"
jq -n '{roster:[{user_id:"alice", name:"A"}, {user_id:"bob", name:"B"}]}' > "$MOCKD/roster.26tsca.json"   # carol FORA
jq -n '{roster:[{user_id:"alice", name:"A"}]}' > "$MOCKD/roster.26outro.json"
jq -n '{machines:[]}' > "$MOCKD/machines.26tsca.json"; jq -n '{machines:[]}' > "$MOCKD/machines.26outro.json"
jq -n '{allowed:[], blocked:{}}' > "$MOCKD/commands.json"
export NB_MOCK_KEY="nb3a_mocktest123" NB_MOCK_SKEY="nb3s_servicetest456" NB_MOCK_SIMAGES="26ts*"
python3 "$HERE/nutella-mock.py" "$MOCKD" "$MOCKD/port" & MOCKPID=$!
for _ in $(seq 50); do [[ -s "$MOCKD/port" ]] && break; sleep 0.1; done
[[ -s "$MOCKD/port" ]] || { echo "mock não subiu"; exit 1; }
printf 'NUTELLABOOT_URL=%q\n' "http://127.0.0.1:$(cat "$MOCKD/port")" >> "$C/conf"

MID=0123456789abcdef0123456789abcdef
ua5(){ printf 'Mozilla/5.0 (MLinux/%s/%s/%s/%s) Gecko/20100101 Firefox/148.0' "$1" "$MID" "$2" "$3"; }
login(){ # <user> <ua>
  LOUT="$(PATH_INFO=/auth/login REQUEST_METHOD=POST QUERY_STRING="contest=nb" HTTP_USER_AGENT="$2" REMOTE_ADDR=10.0.0.9 \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"{\"username\":\"$1\",\"password\":\"pw\"}" 2>&1)"; }
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="contest=nb" HTTP_AUTHORIZATION="Bearer adm" \
  CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
J(){ printf '%s' "$BODY" | jq -r "$1" 2>/dev/null; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: $(tail -2 "$C/var/nutella-bind.log" 2>/dev/null | tr '\n\t' '| ')"; ((fail++)); fi; }
B(){ jq -r "$1" "$MOCKD/bindings.26tsca.json" 2>/dev/null; }
puts(){ grep -c '"PUT".*binding' "$MOCKD/posts.log" 2>/dev/null || true; }
LOGN(){ [[ -s "$C/var/nutella-bind.log" ]] && awk -F'\t' -v s="$1" '$5 == s' "$C/var/nutella-bind.log" | wc -l || echo 0; }

echo "== sem chave configurada: o login não faz nada =="
login alice "$(ua5 26tsca 1001 aa-bb-cc-00-00-01)"
ck "login ok"                          '[[ "$LOUT" == *"\"logged_in\":true"* ]]'
ck "sem chave ⇒ sem fila, sem log"     '[[ ! -e "$C/var/nutella-bind.queue" && ! -e "$C/var/nutella-bind.log" ]]'
( umask 077; printf 'nb3a_mocktest123\n' > "$C/secrets/nutellaboot.key" )

echo "== login com o UA do agente novo publica o elo =="
login alice "$(ua5 26tsca 1001 aa-bb-cc-00-00-01)"
ck "login ok (o login não depende do serviço)" '[[ "$LOUT" == *"\"logged_in\":true"* ]]'
ck "binding no serviço: MAC→alice, source moj-login, boot_id e o instante do login" \
   '[[ "$(B ".[\"aa-bb-cc-00-00-01\"]|[.user_id,.source,.boot_id]|join(\",\")")" == "alice,moj-login,1001" && "$(B ".[\"aa-bb-cc-00-00-01\"].client_at|floor")" -ge "$NOW" ]]'
ck "fila drenada, log ok, mapa mac→time gravado" '[[ ! -s "$C/var/nutella-bind.queue" && "$(LOGN ok)" == 1 && "$(cut -f1-4 "$C/var/nutella-macs.tsv")" == "aa-bb-cc-00-00-01	alice	26tsca	1001" ]]'
ck "a chave NUNCA vai p/ a fila, o log ou o mapa" '! grep -rq "nb3a_" "$C/var/"'
n0="$(puts)"; login alice "$(ua5 26tsca 1001 aa-bb-cc-00-00-01)"
ck "re-login igual NÃO vira request"   '[[ "$(puts)" == "$n0" ]]'
login alice "$(ua5 26tsca 1002 aa-bb-cc-00-00-01)"
ck "reboot (boot_id novo) republica"   '[[ "$(puts)" == "$((n0+1))" && "$(B ".[\"aa-bb-cc-00-00-01\"].boot_id")" == 1002 ]]'
login bob "$(ua5 26tsca 1003 AA:BB:CC:00:00:01 | tr 'A-F' 'a-f')"
ck "outro time na MESMA máquina: o último login vence (MAC com : normalizado)" '[[ "$(B ".[\"aa-bb-cc-00-00-01\"].user_id")" == bob && "$(wc -l < "$C/var/nutella-macs.tsv")" == 1 ]]'

echo "== o que NÃO publica =="
n0="$(puts)"
login alice "Mozilla/5.0 (MLinux/26tsca/$MID/1001) Gecko Firefox/148.0"
ck "agente antigo (UA sem MAC): nada"  '[[ "$(puts)" == "$n0" ]]'
login alice "Mozilla/5.0 (X11; Linux x86_64) Firefox/148.0"
ck "navegador comum: nada"             '[[ "$(puts)" == "$n0" ]]'
login nb.admin "$(ua5 26tsca 1001 aa-bb-cc-00-00-09)"
ck "conta de PAPEL nunca vincula"      '[[ "$(puts)" == "$n0" && "$(B "has(\"aa-bb-cc-00-00-09\")")" == false ]]'
login alice "$(ua5 26outro 1001 aa-bb-cc-00-00-02)"
ck "imagem de OUTRO evento (UA é entrada do cliente; a chave admin alcançaria): recusada" \
   '[[ "$(puts)" == "$n0" && "$(LOGN image_unknown)" == 1 && ! -s "$MOCKD/bindings.26outro.json" ]]'
login carol "$(ua5 26tsca 1001 aa-bb-cc-00-00-03)"
ck "time fora do roster: 404 do serviço vira noroster no log (login segue ok)" '[[ "$LOUT" == *"\"logged_in\":true"* && "$(LOGN noroster)" == 1 ]]'
n0="$(puts)"
sed -i 's/^CONTEST_MODULES=.*/CONTEST_MODULES=sedes/' "$C/conf"
login alice "$(ua5 26tsca 1001 aa-bb-cc-00-00-04)"
ck "módulo maquinas desligado: nada"   '[[ "$(puts)" == "$n0" ]]'
sed -i 's/^CONTEST_MODULES=.*/CONTEST_MODULES=maquinas/' "$C/conf"
call /contest/nutella POST '{"action":"config","bind":false}'
ck "config bind:false grava NUTELLA_BIND=0" 'grep -q "^NUTELLA_BIND=0" "$C/conf"'
login alice "$(ua5 26tsca 1001 aa-bb-cc-00-00-04)"
ck "NUTELLA_BIND=0: nada"              '[[ "$(puts)" == "$n0" ]]'
call /contest/nutella POST '{"action":"config","bind":true}'
ck "bind:true apaga a variável (ligado por omissão)" '! grep -q "^NUTELLA_BIND=" "$C/conf"'

echo "== serviço fora do ar: o login não sente e o retry entrega =="
touch "$MOCKD/bind503"
login alice "$(ua5 26tsca 1001 aa-bb-cc-00-00-05)"
ck "503: login ok, entrada VOLTA p/ a fila com a tentativa contada" '[[ "$LOUT" == *"\"logged_in\":true"* && "$(cut -f6 "$C/var/nutella-bind.queue")" == 1 && "$(LOGN retry)" == 1 ]]'
rm -f "$MOCKD/bind503"
login bob "Mozilla/5.0 Firefox"        # login comum NÃO drena…
ck "…login comum não drena (custo zero p/ quem não é mlinux)" '[[ -s "$C/var/nutella-bind.queue" ]]'
login bob "$(ua5 26tsca 1001 aa-bb-cc-00-00-06)"
ck "próximo login do mlinux drena: a pendente e a nova são entregues" '[[ "$(B ".[\"aa-bb-cc-00-00-05\"].user_id")" == alice && "$(B ".[\"aa-bb-cc-00-00-06\"].user_id")" == bob && ! -s "$C/var/nutella-bind.queue" ]]'

echo "== push-bindings: replay do access.log (quem logou antes da integração / do push-roster) =="
jq -c '.roster += [{user_id:"carol", name:"C"}]' "$MOCKD/roster.26tsca.json" > "$MOCKD/r.tmp" && mv "$MOCKD/r.tmp" "$MOCKD/roster.26tsca.json"
call /contest/nutella POST '{"action":"push-bindings"}'
ck "push-bindings enfileira o último login de cada MAC" '[[ "$(J .queued)" -ge 4 ]]'
ck "carol, que tinha levado 404, agora está vinculada" '[[ "$(B ".[\"aa-bb-cc-00-00-03\"].user_id")" == carol ]]'
ck "…e o que já estava publicado não foi reenviado (dedup contra o mapa)" '[[ "$(grep -c "aa-bb-cc-00-00-06" "$MOCKD/posts.log")" == 1 ]]'
ck "conta de papel continua fora no replay" '[[ "$(B "has(\"aa-bb-cc-00-00-09\")")" == false ]]'
call /contest/nutella GET ''
ck "GET traz o resumo: ligado, publicados, fila vazia, contagens do log" \
   '[[ "$(J .bind.enabled)" == true && "$(J .bind.published)" == "$(wc -l < "$C/var/nutella-macs.tsv")" && "$(J .bind.queued)" == 0 && "$(J .bind.log.noroster)" == 1 && "$(J .bind.log.retry)" == 1 && "$(J .bind.log.image_unknown)" -ge 1 ]]'
ck "…sem MAC nem login no resumo"      '[[ "$(J ".bind|tostring")" != *aa-bb* && "$(J ".bind|tostring")" != *alice* ]]'
printf 'CONTEST=nb\nLOGIN=alice\nLOGINAT=1\n' > "$SESS/usr"
OUT="$(PATH_INFO=/contest/nutella REQUEST_METHOD=POST QUERY_STRING="contest=nb" HTTP_AUTHORIZATION="Bearer usr" CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<'{"action":"push-bindings"}' 2>&1)"
ck "push-bindings por competidor → 403" '[[ "$OUT" == *"Status: 403"* ]]'

echo "== protocolo novo (≥ 21/09): code nos erros, Retry-After, roster automático, lote =="
# 404 que NÃO é "fora do roster": imagem/máquina inexistente vem com code próprio e é erro de verdade
login alice "$(ua5 26tsca 1001 ff-ff-ff-ff-ff-ff)"
ck "MAC que o serviço recusa (invalid_mac) NÃO vira noroster: é erro com o code" 'grep -q "invalid_mac" "$C/var/nutella-bind.log" && [[ "$(LOGN noroster)" == 1 ]]'
touch "$MOCKD/bind429"; n0="$(puts)"
login bob "$(ua5 26tsca 1001 aa-bb-cc-00-00-08)"; login alice "$(ua5 26tsca 1001 aa-bb-cc-00-00-04)"   # o 2º login drena a fila de novo
ck "429 com Retry-After: volta p/ a fila e a passada seguinte entrega" '[[ "$(B ".[\"aa-bb-cc-00-00-08\"].user_id")" == bob ]]'
# NUTELLA_BIND_ROSTER=1: o binding leva create_roster_entry (nome/univ/país do account.json) e o serviço
# cria a entrada marcada source:"binding" — carol, que levou 404 antes, entra sem push-roster
fx_user "$C" dave pw "Time Dave" >/dev/null; jq -c '.team={name:"Time Dave", univ_short:"UFPR", univ_full:"Universidade Federal do Paraná", flag:"br"}' "$C/users/dave/account.json" > "$C/t" && mv "$C/t" "$C/users/dave/account.json"
printf 'NUTELLA_BIND_ROSTER=1\n' >> "$C/conf"
login dave "$(ua5 26tsca 1001 aa-bb-cc-00-00-0a)"
ck "roster automático (opt-in): vínculo ok e a entrada nasce com nome/univ/país e source binding" \
   '[[ "$(B ".[\"aa-bb-cc-00-00-0a\"].roster_entry_created")" == true && "$(jq -r ".roster[]|select(.user_id==\"dave\")|[.source,.name,.organization.name,.country]|join(\"|\")" "$MOCKD/roster.26tsca.json")" == "binding|Time Dave|Universidade Federal do Paraná|BR" ]]'
sed -i '/^NUTELLA_BIND_ROSTER=/d' "$C/conf"
# push-bindings em LOTE (PUT …/bindings): 1 request por sede, resultado por item
: > "$MOCKD/posts.log"; : > "$C/var/nutella-macs.tsv"
fx_user "$C" erin pw "Time Erin" >/dev/null; login erin "$(ua5 26tsca 1001 aa-bb-cc-00-00-0b)"; : > "$MOCKD/posts.log"; : > "$C/var/nutella-macs.tsv"
call /contest/nutella POST '{"action":"push-bindings"}'
ck "push-bindings vai em LOTE: 1 PUT …/bindings p/ a sede, com resultado por item" '[[ "$(grep -c "\"PUT\".*/bindings\"" "$MOCKD/posts.log")" == 1 && "$(J .batch.sent)" -ge 5 && "$(J .batch.bound)" -ge 4 && "$(J .batch.noroster)" -ge 1 ]]'
ck "…e o mapa mac→time e o log refletem o lote (erin fora do roster = noroster, não erro)" '[[ "$(grep -c . "$C/var/nutella-macs.tsv")" -ge 4 ]] && grep -q "erin.*noroster" "$C/var/nutella-bind.log"'
touch "$MOCKD/legacy"; : > "$MOCKD/posts.log"; : > "$C/var/nutella-macs.tsv"
call /contest/nutella POST '{"action":"push-bindings"}'
ck "serviço LEGADO (sem a rota de lote): cai na fila, 1 PUT por máquina" '[[ "$(J .batch)" == null && "$(grep -c "\"PUT\".*/binding\"" "$MOCKD/posts.log")" -ge 4 ]]'
rm -f "$MOCKD/legacy"

echo "== caminho de PRODUÇÃO: drenador DESTACADO (sem MOJ_JOBS_SYNC) =="
# o serviço demora 2 s p/ responder (bindslow): o login NÃO pode esperar por ele
printf '2' > "$MOCKD/bindslow"; rm -f "$C/var/.nutella-bind.stamp"
t0=$(date +%s%N)
LOUT="$(PATH_INFO=/auth/login REQUEST_METHOD=POST QUERY_STRING="contest=nb" HTTP_USER_AGENT="$(ua5 26tsca 1001 aa-bb-cc-00-00-07)" REMOTE_ADDR=10.0.0.9 \
  MOJ_JOBS_SYNC=0 NB_BIND_EVERY=1 CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<'{"username":"alice","password":"pw"}' 2>&1)"
ms=$(( ($(date +%s%N) - t0) / 1000000 ))
ck "login volta SEM esperar o serviço lento (${ms} ms < 1500)" '[[ "$LOUT" == *"\"logged_in\":true"* && $ms -lt 1500 ]]'
ck "…e o binding ainda NÃO chegou (prova de que foi em segundo plano)" '[[ "$(B "has(\"aa-bb-cc-00-00-07\")")" == false ]]'
for _ in $(seq 60); do [[ "$(B "has(\"aa-bb-cc-00-00-07\")")" == true ]] && break; sleep 0.1; done
ck "o drenador destacado entrega"      '[[ "$(B ".[\"aa-bb-cc-00-00-07\"].user_id")" == alice ]]'
rm -f "$MOCKD/bindslow"
# (quem diz se há drenador vivo é o LOCK dele — pgrep -f casaria com o shell que roda este teste)
held(){ ! flock -n "$C/var/.nutella-bind.lock" true 2>/dev/null; }
ck "…o drenador segue vivo por NB_BIND_EVERY s (é ele quem pega o login seguinte)" 'held'
for _ in $(seq 50); do held || break; sleep 0.1; done
ck "…e morre sozinho com a fila vazia (lock livre)" '! held'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
