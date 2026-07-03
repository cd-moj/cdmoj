# POST /problems/request-calibration   (Bearer)   body: {id, hosts?:[...]}
# Pede CALIBRAÇÃO. Sem "hosts": 1 juiz livre pega no heartbeat (kind=calibrate). Com "hosts":
# manda um comando DIRECIONADO a cada juiz escolhido (cada um recalibra full e reporta) — p/ ver
# o comportamento em processadores diferentes. Roda mojtools/calibreitor.sh no pacote.
require_method POST
require_auth
source "$_DIR/../../judge-gw/sched-lib.sh"
source "$_DIR/lib/problems.sh"   # require_problem_edit (acesso por org)

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
id="$(jq -r '.id // empty' <<<"$body")"
[[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
require_problem_edit "$id"   # calibrar é ação de autoria -> só dono/colaborador

repo="${id%%#*}"; [[ "$repo" == "$id" ]] && repo="${id%%/*}"   # org; pacote já está local

hosts="$(jq -c '.hosts // []' <<<"$body" 2>/dev/null)"; [[ -n "$hosts" ]] || hosts='[]'
if (( $(jq 'length' <<<"$hosts") > 0 )); then
  sent='[]'
  while IFS= read -r h; do
    valid_hostname "$h" || continue
    cid="$(cmd_request "$h" calibrate "$SESSION_LOGIN" "$id")"
    [[ -n "$cid" ]] && sent="$(jq -c --arg h "$h" --arg c "$cid" '. + [{host:$h, cmdid:$c}]' <<<"$sent")"
  done < <(jq -r '.[]' <<<"$hosts")
  audit_log "calibrate" "id=$id targeted_hosts=$(jq 'length' <<<"$sent")"
  ok_json '{action:"calibrate", id:$i, hosts:$h, status:"queued"}' --arg i "$id" --argjson h "$sent"
else
  reqid="$(cal_request "$repo" "$id" "$SESSION_LOGIN")"
  audit_log "calibrate" "id=$id reqid=$reqid"
  ok_json '{action:"calibrate", id:$i, reqid:$r, status:"queued"}' --arg i "$id" --arg r "$reqid"
fi
