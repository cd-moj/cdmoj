# POST /problems/publish   (Bearer)   body: {id}
# Pede VALIDAÇÃO + INDEX do problema: 1 juiz livre pega no heartbeat, valida (portão:
# HTML compila + exemplos + good aceita) e, passando, gera o var/jsons (entra no treino).
require_method POST
require_auth
source "$_DIR/../../judge-gw/sched-lib.sh"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
id="$(jq -r '.id // empty' <<<"$body")"
[[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"

# repo = parte antes de '#' (ou '/')
repo="${id%%#*}"; [[ "$repo" == "$id" ]] && repo="${id%%/*}"
reqid="$(idx_request "$repo" "$id" "$SESSION_LOGIN")"
audit_log "publish" "id=$id reqid=$reqid"
ok_json '{action:"publish", id:$i, reqid:$r, status:"queued"}' --arg i "$id" --arg r "$reqid"
