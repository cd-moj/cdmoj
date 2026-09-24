# POST /judge/decline   (Bearer mojw_<token>)
# O agente NÃO conseguiu alocar o trabalho que acabou de receber (corrida entre o claim do
# heartbeat e a alocação de slots/CPUs no juiz — ex.: um job largo pediu k slots e outro job
# terminou/começou no meio). Devolve ao servidor em vez de segurar até o TTL:
#   {host, reason, id}       job: volta à banda de origem com epoch novo e `declined.<host>`
#                            (o host o pula por DECLINE_BACKOFF s); na DECLINE_MAX-ésima recusa
#                            vira Judge Error (spool, host "scheduler");
#   {host, reason, reqid}    calibração: volta p/ updates/pending (o pedido continua valendo);
#   {host, reason, command}  comando (calibrate dirigido): reenfileirado com cmdid novo.
# resp: {host, result: requeued|judge_error|notfound}
require_method POST
require_worker
source "$_DIR/../../judge-gw/sched-lib.sh"

body="$(read_body)"
_dx="$(jq -j '[ (.host // ""), (.reason // ""), (.id // ""), (.reqid // ""), ((.command // null) | tojson) ] | join("\u0001")' <<<"$body" 2>/dev/null)" \
  || fail 400 "Invalid JSON body" "bad_json"
IFS=$'\x01' read -r host reason id reqid cmdj <<<"$_dx"
valid_hostname "$host" || fail 400 "Invalid host" "host_invalid"
reason="${reason:0:200}"
if [[ -n "$id" ]]; then
  valid_id "$id" || fail 400 "Invalid id" "id_invalid"
  r="$(sched_decline_job "$host" "$id" "$reason")"
elif [[ -n "$reqid" ]]; then
  [[ "$reqid" =~ ^[A-Za-z0-9._-]+$ ]] || fail 400 "Invalid reqid" "reqid_invalid"
  r="$(sched_decline_update "$host" "$reqid")"
elif [[ -n "$cmdj" && "$cmdj" != null ]]; then
  r="$(sched_decline_command "$host" "$cmdj")"
else
  fail 400 "Nada a recusar (id | reqid | command)" "decline_empty"
fi
ok_json '{host:$h, result:$r}' --arg h "$host" --arg r "${r:-error}"
