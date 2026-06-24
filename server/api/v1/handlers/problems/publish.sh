# POST /problems/publish   (Bearer)   body: {id}
# Modelo cache: gera o índice (var/jsons, HTML) NO SERVIDOR em background e pede
# CALIBRAÇÃO a um juiz livre. O juiz baixa o pacote, roda as soluções good (portão
# dinâmico + TL) e reporta o TL/validação — que realimentam o time_limits do treino.
require_method POST
require_auth
source "$_DIR/../../judge-gw/sched-lib.sh"
source "$_DIR/lib/tl-store.sh"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
id="$(jq -r '.id // empty' <<<"$body")"
[[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"

# repo = parte antes de '#' (ou '/')
repo="${id%%#*}"; [[ "$repo" == "$id" ]] && repo="${id%%/*}"
index_problem_bg "$id" 1                                  # portão estático + HTML + var/jsons (servidor)
reqid="$(cal_request "$repo" "$id" "$SESSION_LOGIN")"     # juiz calibra (roda as good) + reporta TL
audit_log "publish" "id=$id reqid=$reqid"
ok_json '{action:"publish", id:$i, reqid:$r, status:"queued"}' --arg i "$id" --arg r "$reqid"
