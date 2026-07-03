# POST /problems/set-collections   (Bearer)   body: {id, collections:[...]}
# Define as coleções (tags de exibição) do problema no .moj-meta.json. Acesso = MEMBRO da org.
# (No modelo por org, o acesso É a org; coleções são só rótulos, sem propagar colaborador.)
require_method POST
require_auth
source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/problems.sh"

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
id="$(jq -r '.id // empty' <<<"$body")"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
jq -e 'has("collections")' >/dev/null 2>&1 <<<"$body" || fail 400 "Missing collections" "collections_missing"
colls="$(jq -c '.collections' <<<"$body")"
org="${id%%#*}"; prob="${id##*#}"
require_problem_edit "$id"
pdir="$MOJ_PROBLEMS_DIR/$org/$prob"; [[ -d "$pdir" ]] || fail 404 "Problema não existe" "prob_missing"
owner="$(problem_owner "$id")"; [[ -n "$owner" ]] || owner="$SESSION_LOGIN"
# CURADA: toda coleção marcada tem de EXISTIR no registro (senão vira tag solta).
while IFS= read -r cn; do [[ -n "$cn" ]] || continue
  coll_exists "$cn" || fail 400 "Coleção '$cn' não existe — crie antes (aba Coleções / moj collection create)" "coll_unknown"
done < <(jq -r '.[]?' <<<"$colls")
write_meta "$pdir" "$owner" "$org" "" "$colls" ""
problem_commit "$pdir" "$SESSION_LOGIN" "coleções de $prob" >/dev/null
authored_patch "$id" '.collections=$c' --argjson c "$colls"
audit_log "set-collections" "id=$id"
ok_json '{action:"set-collections", id:$id, collections:$c}' --arg id "$id" --argjson c "$colls"
