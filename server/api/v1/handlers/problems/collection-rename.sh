# POST /problems/collection-rename   (Bearer)   body: {name, to}
# Renomeia uma COLEÇÃO: atualiza o registro E a tag em TODOS os problemas que a têm (bulk retag +
# re-index dos públicos). Só o DONO da coleção ou admin global. `to` é texto livre (pode ter espaços).
require_method POST
require_auth
source "$_DIR/lib/problems.sh"
body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
name="$(jq -r '.name // empty' <<<"$body")"
to="$(jq -r '.to // empty' <<<"$body" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
[[ -n "$name" ]] || fail 400 "Missing name" "name_missing"
coll_exists "$name" || fail 404 "Coleção não existe" "not_found"
coll_can_manage "$name" "$SESSION_LOGIN" || fail 403 "Só o dono da coleção (ou admin) renomeia" "forbidden"
coll_valid_name "$to" || fail 400 "Novo nome inválido (1–80 caracteres, sem controle)" "name_invalid"
[[ "$to" == "$name" ]] && fail 400 "Mesmo nome" "same"
coll_exists "$to" && fail 409 "Já existe uma coleção '$to'" "taken"
coll_rename "$name" "$to"
n="$(coll_bulk_retag "$name" "$to" "$SESSION_LOGIN")"
audit_log "collection-rename" "from=$name to=$to n=$n by=$SESSION_LOGIN"
ok_json '{action:"collection-rename", name:$to, from:$from, retagged:$n}' \
  --arg to "$to" --arg from "$name" --argjson n "${n:-0}"
