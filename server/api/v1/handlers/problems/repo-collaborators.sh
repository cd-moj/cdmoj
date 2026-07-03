# /problems/repo-collaborators   (Bearer)
#   GET  ?repo=<org>                          -> {repo, owner, collaborators:[login]}
#   POST {repo, add?:[login], remove?:[login]} -> idem (só admin da org ou admin global)
# "Compartilhar um diretório" = adicionar MEMBRO à ORG (modelo MOJ-nativo). Alias histórico de
# /orgs/members; o CLI/editor ainda chamam este nome. `collaborators` = os membros da org.
require_auth
source "$_DIR/lib/orgs.sh"

if [[ "$REQUEST_METHOD" == GET ]]; then repo="$(param repo)"
else body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"; repo="$(jq -r '.repo // empty' <<<"$body")"; fi
[[ "$repo" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$ ]] || fail 400 "Org inválida" "repo_invalid"
org_exists "$repo" || fail 404 "Org não existe" "repo_missing"
owner="$(jq -r --arg n "$repo" '.[$n].created_by // ""' "$ORGS_REGISTRY" 2>/dev/null)"

if [[ "$REQUEST_METHOD" == POST ]]; then
  org_can_manage "$repo" "$SESSION_LOGIN" || fail 403 "Só um admin da org gerencia o compartilhamento" "forbidden"
  org_is_implicit "$repo" && fail 409 "Org implícita não compartilha" "implicit"
  add="$(jq -c '(.add // []) | map(select(test("^[A-Za-z0-9][A-Za-z0-9._-]*$")))' <<<"$body")"
  rem="$(jq -c '(.remove // [])' <<<"$body")"
  newm="$(jq -cn --argjson c "$(org_members "$repo")" --argjson a "$add" --argjson r "$rem" --arg o "$owner" '((($c+$a)-$r)+[$o])|unique')"
  org_set_members "$repo" "$newm"
  audit_log "repo-collaborators" "org=$repo by=$SESSION_LOGIN"
fi
ok_json '{repo:$r, owner:$o, collaborators:$c}' \
  --arg r "$repo" --arg o "$owner" --argjson c "$(org_members "$repo")"
