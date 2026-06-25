# POST /problems/request-calibration   (Bearer)   body: {id}
# Pede CALIBRAÇÃO: 1 juiz livre pega no heartbeat, roda mojtools/calibreitor.sh no
# pacote (gera tl.<host>) e re-indexa. Reaproveita o mecanismo pull (kind=calibrate).
require_method POST
require_auth
source "$_DIR/../../judge-gw/sched-lib.sh"
source "$_DIR/lib/problems.sh"   # ensure_repo_materialized

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
id="$(jq -r '.id // empty' <<<"$body")"
[[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"

repo="${id%%#*}"; [[ "$repo" == "$id" ]] && repo="${id%%/*}"
ensure_repo_materialized "$repo" "$SESSION_LOGIN"        # espelha o Gitea -> MOJ_PROBLEMS_DIR antes de calibrar
reqid="$(cal_request "$repo" "$id" "$SESSION_LOGIN")"
audit_log "calibrate" "id=$id reqid=$reqid"
ok_json '{action:"calibrate", id:$i, reqid:$r, status:"queued"}' --arg i "$id" --arg r "$reqid"
