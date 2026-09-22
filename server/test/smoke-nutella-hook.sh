#!/bin/bash
# smoke-nutella-hook.sh — WEBHOOKS do NutellaBoot → MOJ (handlers/hooks/nutella.sh) e a instalação
# (POST /contest/nutella {action:"webhooks-install"}) contra o mock ESTRITO.
# Prende: a rota é pública e OPACA (401 igual p/ contest inexistente, sem segredo, assinatura errada,
# corpo adulterado, evento velho) · HMAC do corpo CRU · imagem de outro evento = 404 · só alerta vira
# registro · repetição sem efeito · time resolvido pelo elo do login · aviso ao dono SÓ durante a
# prova e com teto · o alerta aparece em Máquinas › Anomalias na MESMA chave de máquina · instalar
# exige chave admin, não atropela webhook alheio sem force, e o segredo nunca volta.
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; MOCKD="$(mktemp -d)"; RUN="$(mktemp -d)"; MOCKPID=""
cleanup(){ [[ -n "$MOCKPID" ]] && kill "$MOCKPID" 2>/dev/null; rm -rf "$FIX" "$SESS" "$MOCKD" "$RUN"; }
trap cleanup EXIT
source "$HERE/fixture.sh"
export RUNDIR="$RUN"

NOW=$EPOCHSECONDS
mkc(){ # <id> <start> <end>
  local C="$FIX/$1"; mkdir -p "$C/var" "$C/secrets"
  { printf 'CONTEST_ID=%s\nCONTEST_TYPE=icpc\nCONTEST_NAME=Hook\nCONTEST_START=%s\nCONTEST_END=%s\n' "$1" "$2" "$3"
    printf 'CONTEST_MODULES=maquinas\nNUTELLABOOT_IMAGES=26tsca\n'; printf "PROBS=( x col#pa Alfa A col#pa )\n"; } > "$C/conf"
  fx_user "$C" "$1.admin" pw Admin; fx_user "$C" alice pw "Time Alice"; printf 'dono\n' > "$C/owner"; }
mkc hk "$((NOW-600))" "$((NOW+3600))"; C="$FIX/hk"
mkc fora "$((NOW+86400))" "$((NOW+90000))"           # contest que ainda NÃO começou: registra, não avisa
# o dono tem Telegram vinculado (no treino)
mkdir -p "$FIX/treino/var"; printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\n' > "$FIX/treino/conf"
printf 'CONTEST=hk\nLOGIN=hk.admin\nLOGINAT=1\n' > "$SESS/adm"; printf 'CONTEST=hk\nLOGIN=alice\nLOGINAT=1\n' > "$SESS/usr"
( export CONTESTSDIR="$FIX"; source "$ROOT/api/v1/lib/common.sh" 2>/dev/null; source "$ROOT/api/v1/lib/telegram.sh"
  d="$(tg_dir treino)"; mkdir -p "$d/by-login"; printf '4242' > "$d/by-login/dono" )

jq -n '{images:[{id:"26tsca", fullname:"Cidade A"}]}' > "$MOCKD/images.json"
jq -n '{roster:[]}' > "$MOCKD/roster.26tsca.json"; jq -n '{machines:[]}' > "$MOCKD/machines.26tsca.json"
jq -n '{allowed:[], blocked:{}}' > "$MOCKD/commands.json"
export NB_MOCK_KEY="nb3a_mocktest123" NB_MOCK_SKEY="nb3s_servicetest456" NB_MOCK_SIMAGES="26ts*"
python3 "$HERE/nutella-mock.py" "$MOCKD" "$MOCKD/port" & MOCKPID=$!
for _ in $(seq 50); do [[ -s "$MOCKD/port" ]] && break; sleep 0.1; done
[[ -s "$MOCKD/port" ]] || { echo "mock não subiu"; exit 1; }
for c in hk fora; do printf 'NUTELLABOOT_URL=%q\n' "http://127.0.0.1:$(cat "$MOCKD/port")" >> "$FIX/$c/conf"; done

call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="contest=hk" HTTP_AUTHORIZATION="Bearer ${4:-adm}" HTTP_HOST="moj.exemplo" \
  CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" <<<"${3:-}" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
J(){ printf '%s' "$BODY" | jq -r "$1" 2>/dev/null; }
sign(){ python3 -c 'import hashlib,hmac,sys; print("sha256="+hmac.new(open(sys.argv[1],"rb").read().strip(), sys.stdin.buffer.read(), hashlib.sha256).hexdigest())' "$1"; }
hook(){ # <contest> <corpo> [assinatura|auto] [arquivo-do-segredo]
  local c="$1" b="$2" s="${3-auto}" sf="${4:-$FIX/$1/secrets/nutella-webhook.secret}"
  [[ "$s" == auto ]] && s="$(printf '%s' "$b" | sign "$sf" 2>/dev/null)"
  OUT="$(PATH_INFO=/hooks/nutella REQUEST_METHOD=POST QUERY_STRING="contest=$c" HTTP_X_NB_SIGNATURE="$s" CONTENT_LENGTH="${#b}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" < <(printf '%s' "$b") 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
ev(){ # <event> <mac> <id> <kind> [at] [image]
  jq -cn --arg e "$1" --arg m "$2" --arg i "$3" --arg k "$4" --argjson at "${5:-$EPOCHSECONDS}" --arg img "${6:-26tsca}" \
    '{event:$e, image:$img, at:($at + 0.45), data:{mac:$m, id:$i, kind:$k, detail:"SanDisk <b>Ultra</b>", vendor:"0781", at:$at}}'; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${OUT:0:240}"; ((fail++)); fi; }
LOGN(){ [[ -s "$C/var/nutella-events.log" ]] && wc -l < "$C/var/nutella-events.log" || echo 0; }
OUTBOX(){ find "$RUN/alerts/outbox" -name '*.json' 2>/dev/null | wc -l; }
M1=aa-bb-cc-00-00-01

echo "== antes de instalar: a rota é OPACA =="
hook hk "$(ev alert.raised $M1 a1 usb.storage)" "sha256=00"
ck "sem segredo no contest → 401"     '[[ "$OUT" == *"Status: 401"* ]]'
R0="$BODY"
hook naoexiste "$(ev alert.raised $M1 a1 usb.storage)" "sha256=00"
ck "contest inexistente → o MESMO 401 (não é oráculo de existência)" '[[ "$OUT" == *"Status: 401"* && "$BODY" == "$R0" ]]'
OUT="$(PATH_INFO=/hooks/nutella REQUEST_METHOD=GET QUERY_STRING="contest=hk" CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" 2>&1)"
ck "GET → 405"                        '[[ "$OUT" == *"Status: 405"* ]]'

echo "== instalar o webhook (por ENTRADA — chave de SERVIÇO com webhooks:write basta) =="
( umask 077; printf 'nb3s_servicetest456\n' > "$C/secrets/nutellaboot.key" )
call /contest/nutella POST '{"action":"webhooks-install"}' usr
ck "competidor → 403"                 '[[ "$OUT" == *"Status: 403"* ]]'
call /contest/nutella POST '{"action":"webhooks-install","base_url":"javascript:alert(1)"}'
ck "base_url inválida → 422"          '[[ "$OUT" == *"Status: 422"* ]]'
# webhook de OUTRO dono já na sede: com entradas por dono ele nem aparece p/ a chave de serviço e fica INTOCADO
jq -n '{webhooks:[{id:"wh_deles0000", url:"https://outro.exemplo/hook", secret:"deles-deles-deles", events:[], owner:"service:outro"}]}' > "$MOCKD/webhooks.26tsca.json"
call /contest/nutella POST '{"action":"webhooks-install"}'
ck "instala com chave de SERVIÇO (1 sede ok) e guarda o id" \
   '[[ "$(J .ok)" == 1 && "$(J .url)" == "https://moj.exemplo/api/v1/hooks/nutella?contest=hk" && "$(J ".sedes[\"26tsca\"].id")" == wh_* && "$(jq -r ".[\"26tsca\"]" "$C/var/nutella-webhooks.json")" == wh_* ]]'
ck "o webhook alheio da sede continua lá, intocado" '[[ "$(jq -r ".webhooks|length" "$MOCKD/webhooks.26tsca.json")" == 2 && "$(jq -r ".webhooks[0].url" "$MOCKD/webhooks.26tsca.json")" == "https://outro.exemplo/hook" ]]'
ck "eventos pedidos: os 2 alertas + reiniciou/sumiu/voltou (nunca events:[] — seria machine.status a 38/s)" '[[ "$(jq -r ".webhooks[1].events|sort|join(\",\")" "$MOCKD/webhooks.26tsca.json")" == "alert.dismissed,alert.raised,machine.offline,machine.online,machine.rebooted" ]]'
SEC="$C/secrets/nutella-webhook.secret"
ck "segredo: 48 caracteres, 600, e é o que foi ao serviço" '[[ "$(stat -c %a "$SEC")" == 600 && "$(tr -d "\n" < "$SEC" | wc -c)" == 48 && "$(jq -r ".webhooks[1].secret" "$MOCKD/webhooks.26tsca.json")" == "$(tr -d "\n" < "$SEC")" ]]'
ck "o segredo NÃO volta na resposta nem no GET" '[[ "$BODY" != *"$(tr -d "\n" < "$SEC")"* ]] && { call /contest/nutella GET ""; [[ "$BODY" != *"$(tr -d "\n" < "$SEC")"* && "$(J .webhook.installed)" == true ]]; }'
S0="$(cat "$SEC")"; W0="$(jq -r '.["26tsca"]' "$C/var/nutella-webhooks.json")"; call /contest/nutella POST '{"action":"webhooks-install"}'
ck "reinstalar = upsert pela url: mesmo id, mesmo segredo, sem duplicar" '[[ "$(J .ok)" == 1 && "$(cat "$SEC")" == "$S0" && "$(jq -r ".[\"26tsca\"]" "$C/var/nutella-webhooks.json")" == "$W0" && "$(jq -r ".webhooks|length" "$MOCKD/webhooks.26tsca.json")" == 2 ]]'
( umask 077; printf 'nb3a_mocktest123\n' > "$C/secrets/nutellaboot.key" )

echo "== assinatura =="
B="$(ev alert.raised $M1 a1 usb.storage)"
hook hk "$B" "sha256=$(printf '%064d' 0)"
ck "assinatura errada → 401, nada registrado" '[[ "$OUT" == *"Status: 401"* && "$(LOGN)" == 0 ]]'
hook hk "$B" ""
ck "sem cabeçalho → 401"              '[[ "$OUT" == *"Status: 401"* ]]'
SIG="$(printf '%s' "$B" | sign "$SEC")"
hook hk "${B/usb.storage/usb.other}" "$SIG"
ck "corpo ADULTERADO com assinatura válida do original → 401" '[[ "$OUT" == *"Status: 401"* && "$(LOGN)" == 0 ]]'
printf 'outro-segredo\n' > "$MOCKD/outro.secret"; hook hk "$B" auto "$MOCKD/outro.secret"
ck "assinado com OUTRO segredo → 401" '[[ "$OUT" == *"Status: 401"* ]]'
hook hk "$(ev alert.raised $M1 a0 usb.storage $((NOW-7200)))"
ck "evento de 2 h atrás, bem assinado → 401 (frescor: o \`at\` está no corpo assinado)" '[[ "$OUT" == *"Status: 401"* && "$(LOGN)" == 0 ]]'
hook hk "$(head -c 70000 /dev/zero | tr '\0' 'x')" "sha256=00"
ck "corpo > 64 KiB → 413"             '[[ "$OUT" == *"Status: 413"* ]]'

echo "== alerta bem assinado =="
printf '%s\talice\t26tsca\t1001\t%s\n' "$M1" "$NOW" > "$C/var/nutella-macs.tsv"      # o elo publicado no login
hook hk "$B"
ck "200, registrado e AVISADO (a prova está rolando)" '[[ "$(J .logged)" == true && "$(J .notified)" == true && "$(LOGN)" == 1 ]]'
L(){ tail -n1 "$C/var/nutella-events.log" | jq -r "$1"; }
ck "registro: evento, sede, máquina, tipo, TIME pelo elo do login" '[[ "$(L "[.event,.image,.mac,.kind,.team]|join(\",\")")" == "alert.raised,26tsca,$M1,usb.storage,alice" ]]'
ck "mkey = m:md5(MAC) — a chave de máquina do agente novo" '[[ "$(L .mkey)" == "m:$(printf "%s" "$M1" | md5sum | cut -c1-32)" ]]'
ck "DM p/ o DONO do contest no outbox, com HTML do detalhe ESCAPADO" \
   '[[ "$(OUTBOX)" == 1 ]] && f="$(find "$RUN/alerts/outbox" -name "*.json" | head -1)" && [[ "$(jq -r ".chats[0]" "$f")" == 4242 && "$(jq -r .group "$f")" == false && "$(jq -r .text "$f")" == *"&lt;b&gt;Ultra"* && "$(jq -r .text "$f")" == *alice* ]]'
hook hk "$B"
ck "repetição (o serviço tenta 3×): 200 duplicate, sem 2º registro nem 2º aviso" '[[ "$(J .duplicate)" == true && "$(LOGN)" == 1 && "$(OUTBOX)" == 1 ]]'
hook hk "$(ev alert.raised $M1 a2 usb.storage)"
ck "outro alerta do MESMO tipo na MESMA máquina em < 10 min: registra, NÃO avisa de novo" '[[ "$(J .logged)" == true && "$(J .notified)" == false && "$(LOGN)" == 2 && "$(OUTBOX)" == 1 ]]'
hook hk "$(ev alert.dismissed $M1 a1 usb.storage)"
ck "alert.dismissed: registra, nunca avisa" '[[ "$(J .logged)" == true && "$(J .notified)" == false && "$(LOGN)" == 3 ]]'
hook hk "$(ev machine.bound $M1 x x)"
ck "evento que não é alerta: 200 ignored, sem registro" '[[ "$(J .ignored)" == true && "$(LOGN)" == 3 ]]'
hook hk "$(ev alert.raised $M1 a9 usb.storage "$EPOCHSECONDS" 26outro)"
ck "imagem que NÃO é sede deste contest → 404 (depois da assinatura)" '[[ "$OUT" == *"Status: 404"* && "$(LOGN)" == 3 ]]'
hook hk "$(ev alert.raised 'zz;rm -rf' a9 usb.storage)"
ck "MAC malformado → 422"             '[[ "$OUT" == *"Status: 422"* && "$(LOGN)" == 3 ]]'
for i in $(seq 1 12); do hook hk "$(ev alert.raised "aa-bb-cc-00-01-$(printf '%02d' $i)" "t$i" usb.phone)"; done
ck "enchente: 12 máquinas em segundos ⇒ todas registradas, avisos no TETO de 10 por 10 min" '[[ "$(LOGN)" == 15 && "$(OUTBOX)" == 10 ]]'

echo "== protocolo novo: delivery, webhook.test e eventos de máquina =="
DB="$(ev alert.raised $M1 d1 usb.phone | jq -c '. + {delivery:"dlv-0001"} | .data += {boot_id:"7777", binding:{user_id:"alice"}}')"
hook hk "$DB"; hook hk "$(jq -c '.data.id = "d1-outro"' <<<"$DB")"
ck "mesmo delivery (3 tentativas do serviço) = 1 registro, mesmo com corpo levemente diferente" '[[ "$(J .duplicate)" == true && "$(tail -1 "$C/var/nutella-events.log" | jq -r .delivery)" == dlv-0001 ]]'
ck "o time vem do binding do PRÓPRIO corpo (sem lookup) e o boot_id fica no registro" '[[ "$(tail -1 "$C/var/nutella-events.log" | jq -r "[.team,.boot_id]|join(\",\")")" == "alice,7777" ]]'
hook hk "$(jq -cn --argjson at "$EPOCHSECONDS" '{event:"webhook.test", image:"26tsca", at:$at, delivery:"t1", data:{}}')"
ck "webhook.test (botão testar do serviço): 200 e nada registrado" '[[ "$(J .test)" == true && "$(tail -1 "$C/var/nutella-events.log" | jq -r .event)" != webhook.test ]]'
n0="$(LOGN)"
hook hk "$(jq -cn --argjson at "$EPOCHSECONDS" --arg m "$M1" '{event:"machine.rebooted", image:"26tsca", at:$at, delivery:"r1", data:{mac:$m, boot_id:"8888", previous_boot_id:"7777", boots:3, last_boot:$at}}')"
hook hk "$(jq -cn --argjson at "$EPOCHSECONDS" --arg m "$M1" '{event:"machine.offline", image:"26tsca", at:$at, delivery:"o1", data:{mac:$m, last_seen:($at-120)}}')"
hook hk "$(jq -cn --argjson at "$EPOCHSECONDS" --arg m "$M1" '{event:"machine.online", image:"26tsca", at:$at, delivery:"n1", data:{mac:$m, offline_for:600}}')"
ck "reiniciou / sumiu / voltou: 3 registros, NENHUM aviso (evento de máquina não é alerta)" '[[ "$(( $(LOGN) - n0 ))" == 3 && "$(tail -1 "$C/var/nutella-events.log" | jq -r ".notified")" == false && "$(tail -3 "$C/var/nutella-events.log" | jq -r ".extra | keys[]" | sort | tr "\n" ",")" == "boots,last_seen,offline_for,previous_boot_id," ]]'
call /contest/admin/anomalies GET ''
ck "Anomalias: os 3 viram machine_event (offline = atenção), ao lado do time da máquina" '[[ "$(J .counts.machine_events)" == 3 && "$(J "[.events[]|select(.kind==\"machine_event\")|.severity]|sort|join(\",\")")" == "info,info,warn" && "$(J "[.events[]|select(.kind==\"machine_event\")|.login]|unique|join(\",\")")" == alice ]]'

echo "== contest que ainda não começou: registra, não avisa =="
cp "$SEC" "$FIX/fora/secrets/nutella-webhook.secret"; n0="$(OUTBOX)"
hook fora "$(ev alert.raised $M1 f1 usb.storage)"
ck "fora da prova: logged, notified:false" '[[ "$(J .logged)" == true && "$(J .notified)" == false && "$(OUTBOX)" == "$n0" ]]'

echo "== Máquinas › Anomalias =="
call /contest/admin/anomalies GET ''
ck "trilha traz os alertas (tipo machine_alert), contados" '[[ "$(J .counts.machine_alerts)" == 15 && "$(J "[.events[]|select(.kind==\"machine_alert\")]|length")" == 16 ]]'
ck "pendrive = grave; dispensado = info; time e a chave m:md5(MAC)" \
   '[[ "$(J "[.events[]|select(.kind==\"machine_alert\" and .detail.alert==\"usb.storage\" and .detail.event==\"alert.raised\")][0]|[.severity,.login,.machine]|join(\",\")")" == "bad,alice,m:$(printf "%s" "$M1" | md5sum | cut -c1-32)" && "$(J "[.events[]|select(.kind==\"machine_alert\" and .detail.event==\"alert.dismissed\")][0].severity")" == info ]]'
OUT="$(PATH_INFO=/contest/admin/anomalies REQUEST_METHOD=GET QUERY_STRING="contest=hk" HTTP_AUTHORIZATION="Bearer usr" CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" 2>&1)"
ck "competidor não lê a trilha (403)"  '[[ "$OUT" == *"Status: 403"* ]]'

echo "== remover =="
call /contest/nutella POST '{"action":"webhooks-install","remove":true}'
ck "remove: SÓ o nosso sai (o alheio fica), segredo e ids apagados, rota volta a 401" \
   '[[ "$(jq -r ".webhooks|length" "$MOCKD/webhooks.26tsca.json")" == 1 && "$(jq -r ".webhooks[0].owner" "$MOCKD/webhooks.26tsca.json")" == "service:outro" && ! -e "$SEC" && ! -e "$C/var/nutella-webhooks.json" ]] && { hook hk "$B" "sha256=00"; [[ "$OUT" == *"Status: 401"* ]]; }'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
