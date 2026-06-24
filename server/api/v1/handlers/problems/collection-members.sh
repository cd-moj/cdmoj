# /problems/collection-members   (Bearer)
#   GET ?name=<col>                         -> {name, owner, title, members, mine}
#   POST {name, add?:[logins], remove?:[]}  -> idem (só o DONO da coleção ou admin)
# Gerencia o grupo de setters da coleção e PROPAGA o acesso aos repos que têm problema nela.
require_auth
source "$_DIR/lib/gitea.sh"; source "$_DIR/lib/problems.sh"

if [[ "$REQUEST_METHOD" == GET ]]; then
  name="$(param name)"
else
  body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
  name="$(jq -r '.name // empty' <<<"$body")"
fi
[[ "$name" =~ ^[a-z0-9][a-z0-9._-]{1,63}$ ]] || fail 400 "Coleção inválida" "name_invalid"
owner="$(collection_owner "$name")"; [[ -n "$owner" ]] || fail 404 "Coleção não existe (crie antes)" "missing"

if [[ "$REQUEST_METHOD" == POST ]]; then
  { [[ "$SESSION_LOGIN" == "$owner" ]] || is_admin; } || fail 403 "Só o dono gerencia a coleção" "forbidden"
  add="$(jq -c '(.add // []) | map(select(test("^[A-Za-z0-9][A-Za-z0-9._-]*$")))' <<<"$body")"
  rem="$(jq -c '(.remove // [])' <<<"$body")"
  newm="$(jq -cn --argjson cur "$(collection_members "$name")" --argjson a "$add" --argjson r "$rem" \
            '(($cur + $a) - $r) | unique')"
  collection_set_members "$name" "$newm"
  while IFS= read -r u; do [[ -n "$u" ]] && gitea_ensure_user "$u" "$u" "$u@moj.local"; done < <(jq -r '.[]?' <<<"$add")
  # propaga aos repos que têm um problema NESTA coleção (e que o ator pode gerenciar)
  while IFS= read -r repo; do [[ -n "$repo" ]] || continue
    ro="$(repo_owner "$repo")"; [[ -n "$ro" ]] || continue
    { [[ "$SESSION_LOGIN" == "$ro" ]] || is_admin; } || continue
    collection_grant_repo "$name" "$repo" "$SESSION_LOGIN"           # adiciona os membros atuais
    while IFS= read -r u; do [[ -n "$u" && "$u" != "$ro" ]] && gitea_rm_collaborator "$ro" "$repo" "$u"; done < <(jq -r '.[]?' <<<"$rem")
    cur="$(repo_collabs "$repo")"; pruned="$(jq -cn --argjson c "${cur:-[]}" --argjson r "$rem" '($c - $r)|unique')"
    repo_set_collabs "$repo" "$pruned"; authored_set_repo_collabs "$repo" "$pruned"
  done < <(owners_merged | jq -r --arg n "$name" '[.problems[]|select(.collections|index($n))|.repo]|unique[]' 2>/dev/null)
  audit_log "collection-members" "name=$name by=$SESSION_LOGIN"
fi

ok_json '{name:$n, owner:$o, members:$m, mine:($o==$me)}' \
  --arg n "$name" --arg o "$owner" --arg me "$SESSION_LOGIN" --argjson m "$(collection_members "$name")"
