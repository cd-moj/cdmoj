# POST /ops/updateproblemset   (Bearer, admin)   body: {repo}
# Modelo pull: vira um PEDIDO de atualização que UM worker livre reivindica no
# heartbeat e executa (NFS compartilhado: um host roda o git pull e todos enxergam).
# O worker devolve o resultado por /judge/update-report (visível por juiz no admin).
require_method POST
require_admin
source "$_DIR/../../judge-gw/sched-lib.sh"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
repo="$(jq -r '.repo // empty' <<<"$body")"
[[ -n "$repo" ]] || fail 400 "Missing repo" "repo_missing"

reqid="$(upd_request "$repo" "$SESSION_LOGIN" "ops/updateproblemset")"
audit_log "updateproblemset" "repo=$repo reqid=$reqid"
ok_json '{action:"updateproblemset", repo:$r, reqid:$id, status:"queued"}' \
  --arg r "$repo" --arg id "$reqid"
