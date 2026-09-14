#!/bin/bash
# deliver.sh — a metade do relatório de quartil que NENHUM smoke do servidor exercita: o bot
# entregando (tg_send/deliver_alerts) e confirmando (ack). Telegram e API são FALSOS (funções
# sobrescritas depois de carregar o bot até o loop principal). Casos: entrega ok → ack ok:true;
# chat migrado p/ supergrupo → ack ok:false com o chat novo na mensagem; item só-grupo sem
# ALERT_GROUP_CHAT → ack ok:false "sem destino" (e não some em silêncio); chat_id não numérico.
set -u
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${3:-}"; ((fail++)); fi; }
# carrega o bot ATÉ o loop principal (as funções), com config vazia e sem token de verdade
printf 'BOT_TOKEN=mojb_fake\nALERT_GROUP_CHAT="%s"\n' "${GROUP:-}" > "$T/bot.conf"
printf '123456:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef\n' > "$T/token"   # token falso do Telegram (o bot exige o formato)
sed -n '1,/^# LOOP PRINCIPAL/p' "$HERE/../mojinho-api.sh" | sed 's|^BOTDIR=.*|BOTDIR="'"$T"'"|' > "$T/bot-funcs.sh"
sed -i 's|^\(\s*\)while true; do|\1: ; while false; do|' "$T/bot-funcs.sh"
source "$T/bot-funcs.sh" 2>/dev/null
# Telegram falso: chat -100999 migrou; chat -1 não existe; o resto entrega
tg_api(){ local body="$2" chat; chat="$(jq -r '.chat_id' <<<"$body")"; echo "$chat" >> "$T/sent"
  case "$chat" in
    -100999) printf '{"ok":false,"description":"Bad Request: group chat was upgraded to a supergroup chat","parameters":{"migrate_to_chat_id":-1001234}}';;
    -1) printf '{"ok":false,"description":"Bad Request: chat not found"}';;
    *) printf '{"ok":true,"result":{"message_id":1}}';;
  esac; }
# API falsa: GET devolve os itens do caso; POST grava o ack
api(){ local m="$1" p="$2"; if [[ "$m" == GET ]]; then cat "$T/items.json"; printf '\nHTTP 200'; else printf '{"success":true}\nHTTP 200'; fi; }
api_json(){ local m="$1" p="$2" body="$3"; printf '%s' "$body" > "$T/ack.json"; printf '{"success":true}\nHTTP 200'; }
run(){ : > "$T/sent"; rm -f "$T/ack.json"; printf '%s' "$1" > "$T/items.json"; deliver_alerts 2>"$T/err"; }

echo "== entrega ok -> ack ok:true =="
ALERT_GROUP_CHAT=""
run '{"items":[{"id":"1-dm-A","text":"oi","chats":[42],"loud":true,"group":false}]}'
ck "mandou p/ o chat 42"                 '[[ "$(cat "$T/sent")" == 42 ]]'
ck "ack ok:true com o id"                '[[ "$(jq -r ".ack[0].id + \" \" + (.ack[0].ok|tostring)" "$T/ack.json")" == "1-dm-A true" ]]'
echo "== chat migrou -> ack ok:false com o chat novo =="
run '{"items":[{"id":"2-dm-B","text":"oi","chats":[-100999],"loud":false,"group":false}]}'
ck "ack ok:false"                        '[[ "$(jq -r ".ack[0].ok" "$T/ack.json")" == false ]]'
ck "erro cita o supergrupo novo"         '[[ "$(jq -r ".ack[0].error" "$T/ack.json")" == *"-1001234"* ]]'
ck "stderr tem a linha do tg_send"       'grep -q "tg_send chat=-100999 falhou" "$T/err"'
echo "== só-grupo sem ALERT_GROUP_CHAT -> não some em silêncio =="
run '{"items":[{"id":"3-grp-C","text":"relatório","chats":[],"loud":true,"group":true}]}'
ck "nada enviado"                        '[[ ! -s "$T/sent" ]]'
ck "ack ok:false 'sem destino'"          '[[ "$(jq -r ".ack[0].error" "$T/ack.json")" == *"sem destino"* ]]'
ck "stderr avisa"                        'grep -q "descartado: sem destino" "$T/err"'
echo "== só-grupo COM ALERT_GROUP_CHAT -> vai p/ o grupo =="
ALERT_GROUP_CHAT=-777
run '{"items":[{"id":"4-grp-D","text":"relatório","chats":[],"loud":true,"group":true}]}'
ck "foi p/ -777"                         '[[ "$(cat "$T/sent")" == -777 ]]'
ck "ack ok:true"                         '[[ "$(jq -r ".ack[0].ok" "$T/ack.json")" == true ]]'
echo "== group:false NÃO copia no grupo; um chat falho + um ok = ok:true =="
run '{"items":[{"id":"5-dm-E","text":"x","chats":[-1,42],"loud":false,"group":false}]}'
ck "só os chats do item (sem -777)"      '[[ "$(tr "\n" " " < "$T/sent")" == "-1 42 " ]]'
ck "ack ok:true (pelo menos um entregou)" '[[ "$(jq -r ".ack[0].ok" "$T/ack.json")" == true ]]'
echo "== chat_id não numérico =="
ALERT_GROUP_CHAT="@grupo"
run '{"items":[{"id":"6-grp-F","text":"y","chats":[],"loud":false,"group":true}]}'
ck "ack ok:false 'não numérico'"         '[[ "$(jq -r ".ack[0].error" "$T/ack.json")" == *"não numérico"* ]]'
echo; echo "RESULT: $pass passed, $fail failed"; exit $(( fail > 0 ))
