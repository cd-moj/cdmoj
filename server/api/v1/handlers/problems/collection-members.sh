# /problems/collection-members   (Bearer)
#   GET ?name=<col>  -> {name, owner, title, members, admins, mine, can_manage}
#   POST {name, add?, remove?, admins_add?, admins_remove?}  -> idem
# O DONO e os co-ADMINS (e admin global) gerenciam o grupo de setters E os admins. Mudanças
# propagam o acesso aos repos com problema na coleção.
require_auth
source "$_DIR/lib/gitea.sh"; source "$_DIR/lib/problems.sh"

if [[ "$REQUEST_METHOD" == GET ]]; then name="$(param name)"
else body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"; name="$(jq -r '.name // empty' <<<"$body")"; fi
[[ "$name" =~ ^[a-z0-9][a-z0-9._-]{1,63}$ ]] || fail 400 "Coleção inválida" "name_invalid"
owner="$(collection_owner "$name")"; [[ -n "$owner" ]] || fail 404 "Coleção não existe (crie antes)" "missing"

if [[ "$REQUEST_METHOD" == POST ]]; then
  collection_can_manage "$name" "$SESSION_LOGIN" || fail 403 "Só o dono ou um co-admin gerencia a coleção" "forbidden"
  add="$(jq -c '(.add // []) | map(select(test("^[A-Za-z0-9][A-Za-z0-9._-]*$")))' <<<"$body")"
  rem="$(jq -c '(.remove // [])' <<<"$body")"
  aadd="$(jq -c '(.admins_add // []) | map(select(test("^[A-Za-z0-9][A-Za-z0-9._-]*$")))' <<<"$body")"
  arem="$(jq -c '(.admins_remove // [])' <<<"$body")"
  newm="$(jq -cn --argjson c "$(collection_members "$name")" --argjson a "$add" --argjson r "$rem" '(($c+$a)-$r)|unique')"
  newa="$(jq -cn --argjson c "$(collection_admins "$name")" --argjson a "$aadd" --argjson r "$arem" --arg o "$owner" '((($c+$a)-$r)|unique) - [$o]')"
  collection_set_members "$name" "$newm"; collection_set_admins "$name" "$newa"
  while IFS= read -r u; do [[ -n "$u" ]] && gitea_ensure_user "$u" "$u" "$u@moj.local"; done < <(jq -r '.[]?' <<<"$(jq -cn --argjson a "$add" --argjson b "$aadd" '$a+$b')")
  # propaga aos repos que têm um problema NESTA coleção (e que o ator pode gerenciar)
  alldrop="$(jq -cn --argjson r "$rem" --argjson a "$arem" '($r+$a)|unique')"
  while IFS= read -r repo; do [[ -n "$repo" ]] || continue
    ro="$(repo_owner "$repo")"; [[ -n "$ro" ]] || continue
    { [[ "$SESSION_LOGIN" == "$ro" ]] || is_admin; } || continue
    collection_grant_repo "$name" "$repo" "$SESSION_LOGIN"
    while IFS= read -r u; do [[ -n "$u" && "$u" != "$ro" ]] && gitea_rm_collaborator "$ro" "$repo" "$u"; done < <(jq -r '.[]?' <<<"$alldrop")
    cur="$(repo_collabs "$repo")"; pruned="$(jq -cn --argjson c "${cur:-[]}" --argjson r "$alldrop" '($c-$r)|unique')"
    repo_set_collabs "$repo" "$pruned"; authored_set_repo_collabs "$repo" "$pruned"
  done < <(owners_merged | jq -r --arg n "$name" '[.problems[]|select(.collections|index($n))|.repo]|unique[]' 2>/dev/null)
  audit_log "collection-members" "name=$name by=$SESSION_LOGIN"
fi

cm=false; collection_can_manage "$name" "$SESSION_LOGIN" && cm=true
ok_json '{name:$n, owner:$o, members:$m, admins:$a, mine:($o==$me), can_manage:$cm}' \
  --arg n "$name" --arg o "$owner" --arg me "$SESSION_LOGIN" --argjson cm "$cm" \
  --argjson m "$(collection_members "$name")" --argjson a "$(collection_admins "$name")"
