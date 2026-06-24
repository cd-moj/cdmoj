# POST /problems/collection-create   (Bearer)   body: {name, members?:[], admins?:[], title?}
# Cria uma COLEÇÃO (competição/curso) com um GRUPO de setters e, opcional, co-ADMINS que
# também gerenciam o grupo. Os membros+admins ganham acesso de escrita aos problemas dela.
# Requer permissão de CRIAÇÃO (mesma regra de criar contest).
require_method POST
require_auth
source "$_DIR/lib/gitea.sh"; source "$_DIR/lib/problems.sh"; source "$_DIR/lib/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar (igual a criar contest)" "create_forbidden"

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
name="$(jq -r '.name // empty' <<<"$body")"
[[ "$name" =~ ^[a-z0-9][a-z0-9._-]{1,63}$ ]] || fail 400 "Nome de coleção inválido (use [a-z0-9._-])" "name_invalid"
exist="$(collection_owner "$name")"
if [[ -n "$exist" ]]; then collection_can_manage "$name" "$SESSION_LOGIN" || fail 409 "Coleção já existe (dono: $exist)" "taken"; fi
title="$(jq -r '.title // empty' <<<"$body")"
members_csv="$(jq -r '(.members // []) | map(select(test("^[A-Za-z0-9][A-Za-z0-9._-]*$"))) | join(",")' <<<"$body")"
admins_csv="$(jq -r '(.admins // []) | map(select(test("^[A-Za-z0-9][A-Za-z0-9._-]*$"))) | join(",")' <<<"$body")"
owner="${exist:-$SESSION_LOGIN}"

collection_register "$name" "$owner" "$members_csv" "$title" "$admins_csv"
while IFS= read -r u; do [[ -n "$u" ]] && gitea_ensure_user "$u" "$u" "$u@moj.local"; done \
  < <(jq -r '((.members // []) + (.admins // []))[]?' <<<"$body")
audit_log "collection-create" "name=$name owner=$owner by=$SESSION_LOGIN"
ok_json '{action:"collection-create", name:$n, owner:$o, title:($t|if .=="" then $n else . end),
          members:$m, admins:$a, mine:($o==$me), can_manage:true}' \
  --arg n "$name" --arg o "$owner" --arg me "$SESSION_LOGIN" --arg t "$title" \
  --argjson m "$(collection_members "$name")" --argjson a "$(collection_admins "$name")"
