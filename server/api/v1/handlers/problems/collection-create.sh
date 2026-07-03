# POST /problems/collection-create   (Bearer)   body: {name, members?:[], admins?:[], title?}
# Cria uma COLEÇÃO/curso = uma ORG (grupo de setters + admins). Alias de /orgs/create — no modelo
# MOJ-nativo a ORG é a unidade de acesso. Requer permissão de criação (mesma regra de criar contest).
require_method POST
require_auth
source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar (igual a criar contest)" "create_forbidden"

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
name="$(jq -r '.name // empty' <<<"$body")"
[[ "$name" =~ ^[a-z0-9][a-z0-9._-]{1,63}$ ]] || fail 400 "Nome de coleção inválido (use [a-z0-9._-])" "name_invalid"
if org_exists "$name"; then org_can_manage "$name" "$SESSION_LOGIN" || fail 409 "Coleção já existe" "taken"; fi
title="$(jq -r '.title // empty' <<<"$body")"
members_csv="$(jq -r '(.members // []) | map(select(test("^[A-Za-z0-9][A-Za-z0-9._-]*$"))) | join(",")' <<<"$body")"
admins_csv="$(jq -r '(.admins // []) | map(select(test("^[A-Za-z0-9][A-Za-z0-9._-]*$"))) | join(",")' <<<"$body")"
org_register "$name" "$SESSION_LOGIN" "$members_csv" "$admins_csv" "$title"
audit_log "collection-create" "name=$name owner=$SESSION_LOGIN"
ok_json '{action:"collection-create", name:$n, owner:$o, title:($t|if .=="" then $n else . end),
          members:$m, admins:$a, mine:true, can_manage:true}' \
  --arg n "$name" --arg o "$SESSION_LOGIN" --arg t "$title" \
  --argjson m "$(org_members "$name")" --argjson a "$(org_admins "$name")"
