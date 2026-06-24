# /problems/repo-collaborators   (Bearer)
#   GET ?repo=<repo>            -> {repo, owner, collaborators:[login]}
#   POST {repo, add?:[login], remove?:[login]}  -> idem (só o DONO ou admin gerencia)
# Compartilhar um diretório = adicionar colaborador no Gitea (disparado pela UI do MOJ).
require_auth
source "$_DIR/lib/gitea.sh"; source "$_DIR/lib/problems.sh"

if [[ "$REQUEST_METHOD" == GET ]]; then
  repo="$(param repo)"
else
  body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
  repo="$(jq -r '.repo // empty' <<<"$body")"
fi
[[ "$repo" =~ ^[a-z0-9][a-z0-9._-]{1,63}$ ]] || fail 400 "Diretório inválido" "repo_invalid"
owner="$(repo_owner "$repo")"; [[ -n "$owner" ]] || fail 404 "Diretório não existe no Gitea" "repo_missing"

if [[ "$REQUEST_METHOD" == POST ]]; then
  { [[ "$SESSION_LOGIN" == "$owner" ]] || is_admin; } || fail 403 "Só o dono gerencia o compartilhamento" "forbidden"
  while IFS= read -r u; do [[ -n "$u" ]] || continue
    [[ "$u" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || continue
    gitea_ensure_user "$u" "$u" "$u@moj.local" && gitea_set_collaborator "$owner" "$repo" "$u" write
  done < <(jq -r '(.add // [])[]' <<<"$body")
  while IFS= read -r u; do [[ -n "$u" ]] || continue
    gitea_rm_collaborator "$owner" "$repo" "$u"
  done < <(jq -r '(.remove // [])[]' <<<"$body")
  audit_log "repo-collaborators" "repo=$repo by=$SESSION_LOGIN"
fi

collabs="$(gitea_api GET "/repos/$owner/$repo/collaborators" | jq -c '[.[]?.login] // []' 2>/dev/null)"
[[ -n "$collabs" ]] || collabs='[]'
# espelha colaboradores no registro + overlay (p/ a aba "Compartilhados" ver na hora)
if [[ "$REQUEST_METHOD" == POST ]]; then
  repo_set_collabs "$repo" "$collabs"; authored_set_repo_collabs "$repo" "$collabs"
fi
ok_json '{repo:$r, owner:$o, collaborators:$c}' --arg r "$repo" --arg o "$owner" --argjson c "$collabs"
