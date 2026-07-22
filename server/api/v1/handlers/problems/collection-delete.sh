# POST /problems/collection-delete   (Bearer)   body: {name}
# Exclui uma COLEÇÃO: o untag dos N problemas (bulk + commit + re-index dos públicos) roda em
# BACKGROUND (síncrono estourava o timeout do nginx com N grande) e o REGISTRO só sai NO FIM do
# bulk — se morrer no meio, a coleção ainda existe e repetir o delete RETOMA (o untag processa
# só metas que ainda têm a tag). Só o DONO da coleção ou admin global.
require_method POST
require_auth
source "$_DIR/lib/problems.sh"
body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
name="$(jq -r '.name // empty' <<<"$body")"
[[ -n "$name" ]] || fail 400 "Missing name" "name_missing"
coll_exists "$name" || fail 404 "Coleção não existe" "not_found"
coll_can_manage "$name" "$SESSION_LOGIN" || fail 403 "Só o dono da coleção (ou admin) exclui" "forbidden"
job="$(coll_bulk_retag_bg "$name" "" "$SESSION_LOGIN" delete)"
audit_log "collection-delete" "name=$name job=$job by=$SESSION_LOGIN (untag+remoção em background)"
ok_json '{action:"collection-delete", name:$n, untag:"background", retag_job:$job}' --arg n "$name" --arg job "$job"
