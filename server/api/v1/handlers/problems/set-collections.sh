# POST /problems/set-collections   (Bearer)   body: {id, collections:[...]}
# Define as coleções (curso/diretório compartilhado) do problema no .moj-meta.json.
require_method POST
require_auth
source "$_DIR/lib/gitea.sh"; source "$_DIR/lib/problems.sh"; source "$MOJTOOLS_DIR/git-broker.sh"

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
id="$(jq -r '.id // empty' <<<"$body")"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
jq -e 'has("collections")' >/dev/null 2>&1 <<<"$body" || fail 400 "Missing collections" "collections_missing"
colls="$(jq -c '.collections' <<<"$body")"
repo="${id%%#*}"; prob="${id##*#}"
owner="$(problem_owner "$id")"; [[ -n "$owner" ]] || fail 404 "Problema não está no Gitea" "not_gitea"
gitea_can_write "$owner" "$repo" "$SESSION_LOGIN" || fail 403 "Sem permissão" "forbidden"

tmp="$(git_broker_open "$SESSION_LOGIN" "$owner" "$repo")" || fail 502 "Falha ao abrir o repositório" "git_open"
trap 'rm -rf "$tmp"' EXIT
wt="$tmp/wt"; [[ -d "$wt/$prob" ]] || fail 404 "Problema não existe" "prob_missing"
write_meta "$wt/$prob" "$owner" "$repo" "" "$colls" ""
git_broker_commit_push "$SESSION_LOGIN" "$owner" "$repo" "$wt" "coleções de $prob" >/dev/null \
  || fail 502 "Falha ao enviar (push)" "git_push"
authored_patch "$id" '.collections=$c' --argjson c "$colls"
grant_problem_collections "$id" "$repo" "$SESSION_LOGIN"   # setters das coleções ganham acesso
audit_log "set-collections" "id=$id"
ok_json '{action:"set-collections", id:$id, collections:$c}' --arg id "$id" --argjson c "$colls"
