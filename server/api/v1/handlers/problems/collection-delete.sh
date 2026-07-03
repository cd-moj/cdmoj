# POST /problems/collection-delete   (Bearer)   body: {name}
# Exclui uma COLEÇÃO: tira a tag de TODOS os problemas que a têm (bulk untag + re-index dos públicos) e
# remove do registro. Só o DONO da coleção ou admin global.
require_method POST
require_auth
source "$_DIR/lib/problems.sh"
body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
name="$(jq -r '.name // empty' <<<"$body")"
[[ -n "$name" ]] || fail 400 "Missing name" "name_missing"
coll_exists "$name" || fail 404 "Coleção não existe" "not_found"
coll_can_manage "$name" "$SESSION_LOGIN" || fail 403 "Só o dono da coleção (ou admin) exclui" "forbidden"
n="$(coll_bulk_retag "$name" "" "$SESSION_LOGIN")"
coll_delete "$name"
audit_log "collection-delete" "name=$name n=$n by=$SESSION_LOGIN"
ok_json '{action:"collection-delete", name:$n, untagged:$c}' --arg n "$name" --argjson c "${n:-0}"
