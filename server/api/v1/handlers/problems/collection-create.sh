# POST /problems/collection-create   (Bearer)   body: {name, members?:[logins], title?}
# Cria uma COLEÇÃO (competição/curso) com um GRUPO de setters. Os membros ganham acesso de
# escrita aos problemas que entrarem na coleção (vira colaborador do repo na hora).
require_method POST
require_auth
source "$_DIR/lib/gitea.sh"; source "$_DIR/lib/problems.sh"

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
name="$(jq -r '.name // empty' <<<"$body")"
[[ "$name" =~ ^[a-z0-9][a-z0-9._-]{1,63}$ ]] || fail 400 "Nome de coleção inválido (use [a-z0-9._-])" "name_invalid"
exist="$(collection_owner "$name")"
[[ -n "$exist" && "$exist" != "$SESSION_LOGIN" ]] && { is_admin || fail 409 "Coleção já existe (dono: $exist)" "taken"; }
title="$(jq -r '.title // empty' <<<"$body")"
members_csv="$(jq -r '(.members // []) | map(select(test("^[A-Za-z0-9][A-Za-z0-9._-]*$"))) | join(",")' <<<"$body")"

collection_register "$name" "$SESSION_LOGIN" "$members_csv" "$title"
# provisiona os usuários Gitea dos membros (p/ virarem colaboradores depois)
while IFS= read -r u; do [[ -n "$u" ]] && gitea_ensure_user "$u" "$u" "$u@moj.local"; done \
  < <(jq -r '(.members // [])[]?' <<<"$body")
audit_log "collection-create" "name=$name owner=$SESSION_LOGIN"
ok_json '{action:"collection-create", name:$n, owner:$o, title:($t|if .=="" then $n else . end), members:$m}' \
  --arg n "$name" --arg o "$SESSION_LOGIN" --arg t "$title" --argjson m "$(collection_members "$name")"
