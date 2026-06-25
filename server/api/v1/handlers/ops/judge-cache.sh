# POST /ops/judge-cache   (Bearer, admin)   body: {host, action}
# Gerência do cache local de um juiz. Hoje: action="clearcache" — enfileira um comando
# POR-HOST que o juiz pega no próximo heartbeat (quando livre), limpa o $JUDGE_CACHE e
# re-registra (inventário vazio). Não bloqueia: o efeito aparece no /judge/list.
require_method POST
require_admin
source "$_DIR/../../judge-gw/sched-lib.sh"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
host="$(jq -r '.host // empty' <<<"$body")"
valid_hostname "$host" || fail 400 "Invalid host" "host_invalid"
action="$(jq -r '.action // "clearcache"' <<<"$body")"
[[ "$action" == clearcache ]] || fail 400 "Ação não suportada (use clearcache)" "action_bad"
[[ -f "$REGISTRYDIR/$host.json" ]] || fail 404 "Juiz desconhecido: $host" "host_unknown"

cmdid="$(cmd_request "$host" "$action" "$SESSION_LOGIN")"
audit_log "judge-cache" "host=$host action=$action cmdid=$cmdid"
ok_json '{action:$a, host:$h, cmdid:$c, status:"queued"}' \
  --arg a "$action" --arg h "$host" --arg c "$cmdid"
