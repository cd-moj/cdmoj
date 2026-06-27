# /problems/collection-members   (Bearer)
#   GET ?name=<col>  -> {name, owner, members, admins, mine, can_manage, repo_course}
#   POST {name, add?, remove?, admins_add?, admins_remove?}  -> idem
# Coleção REGISTRADA: dono + co-admins (e admin global) gerenciam setters+admins; muda o acesso
# aos repos da coleção. REPO-CURSO (coleção = repo homônimo): setters = colaboradores do repo
# (sem co-admins); add/remove aqui = colaborador do repo (mesmo efeito do "Compartilhar").
require_auth
source "$_DIR/lib/gitea.sh"; source "$_DIR/lib/problems.sh"

if [[ "$REQUEST_METHOD" == GET ]]; then name="$(param name)"
else body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"; name="$(jq -r '.name // empty' <<<"$body")"; fi
[[ "$name" =~ ^[a-z0-9][a-z0-9._-]{1,63}$ ]] || fail 400 "Coleção inválida" "name_invalid"
owner="$(collection_owner "$name")"

if [[ -z "$owner" ]]; then
  # ===== repo-curso: a "coleção" é um REPO homônimo -> setters = colaboradores do repo (sem co-admins).
  # Gerenciar setter aqui = add/remove colaborador do repo (mesmo efeito do "Compartilhar"). =====
  rowner="$(repo_owner "$name")"; [[ -n "$rowner" ]] || fail 404 "Coleção não existe (crie antes)" "missing"
  if [[ "$REQUEST_METHOD" == POST ]]; then
    { [[ "$SESSION_LOGIN" == "$rowner" ]] || is_admin; } || fail 403 "Só o dono do diretório gerencia os setters" "forbidden"
    while IFS= read -r u; do [[ -n "$u" ]] || continue; [[ "$u" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || continue
      gitea_ensure_user "$u" "$u" "$u@moj.local" && gitea_set_collaborator "$rowner" "$name" "$u" write
    done < <(jq -r '(.add // [])[]' <<<"$body")
    while IFS= read -r u; do [[ -n "$u" ]] || continue; gitea_rm_collaborator "$rowner" "$name" "$u"; done < <(jq -r '(.remove // [])[]' <<<"$body")
    mem="$(gitea_api GET "/repos/$rowner/$name/collaborators" | jq -c '[.[]?.login] // []' 2>/dev/null)"; [[ -n "$mem" ]] || mem='[]'
    repo_set_collabs "$name" "$mem"; authored_set_repo_collabs "$name" "$mem"
    audit_log "collection-members" "repo-curso name=$name by=$SESSION_LOGIN"
  fi
  mem="$(gitea_api GET "/repos/$rowner/$name/collaborators" | jq -c '[.[]?.login] // []' 2>/dev/null)"; [[ -n "$mem" ]] || mem='[]'
  cm=false; { [[ "$SESSION_LOGIN" == "$rowner" ]] || is_admin; } && cm=true
  ok_json '{name:$n, owner:$o, members:$m, admins:[], mine:($o==$me), can_manage:$cm, repo_course:true}' \
    --arg n "$name" --arg o "$rowner" --arg me "$SESSION_LOGIN" --argjson cm "$cm" --argjson m "$mem"
else
  # ===== coleção REGISTRADA (grupo de setters + co-admins próprios) =====
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
  ok_json '{name:$n, owner:$o, members:$m, admins:$a, mine:($o==$me), can_manage:$cm, repo_course:false}' \
    --arg n "$name" --arg o "$owner" --arg me "$SESSION_LOGIN" --argjson cm "$cm" \
    --argjson m "$(collection_members "$name")" --argjson a "$(collection_admins "$name")"
fi
