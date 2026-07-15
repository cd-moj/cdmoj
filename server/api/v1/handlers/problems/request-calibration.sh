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
  # DEDUP direcionado: calibrate ainda não entregue ao host p/ o mesmo id não é duplicado
  sent='[]'
  while IFS= read -r h; do
    valid_hostname "$h" || continue
    st="queued"
    cid="$(cmd_find_calibrate "$h" "$id")"
    if [[ -n "$cid" ]]; then st="already_queued"
    else cid="$(cmd_request "$h" calibrate "$SESSION_LOGIN" "$id")"; fi
    [[ -n "$cid" ]] && sent="$(jq -c --arg h "$h" --arg c "$cid" --arg s "$st" \
                               '. + [{host:$h, cmdid:$c, status:$s}]' <<<"$sent")"
  done < <(jq -r '.[]' <<<"$hosts")
  audit_log "calibrate" "id=$id targeted_hosts=$(jq 'length' <<<"$sent")"
  ok_json '{action:"calibrate", id:$i, hosts:$h, status:"queued"}' --arg i "$id" --argjson h "$sent"
else
  # DEDUP global: já há calibração pendente/em execução p/ o id => devolve o reqid existente
  # (cal_request também dedupa por dentro — aqui só distinguimos o status p/ o cliente avisar)
  st="queued"; [[ -n "$(upd_find_calibrate "$id")" ]] && st="already_queued"
  reqid="$(cal_request "$repo" "$id" "$SESSION_LOGIN")"
  audit_log "calibrate" "id=$id reqid=$reqid status=$st"
  ok_json '{action:"calibrate", id:$i, reqid:$r, status:$s}' --arg i "$id" --arg r "$reqid" --arg s "$st"
fi
