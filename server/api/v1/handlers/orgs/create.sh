# POST /orgs/create  (Bearer)  body: {name, members?:[], admins?:[], title?, public_allowed?:bool}
# Cria uma ORG (curso/competição): membros escrevem em QUALQUER problema da org; admins gerem
# membros/admins e a trava de público. Requer permissão de CRIAÇÃO (mesma regra de criar contest).
# A org implícita <login> (sempre privada) é criada sob demanda em /orgs/list — não por aqui.
require_method POST
require_auth
source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar org (igual a criar contest)" "create_forbidden"

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
name="$(jq -r '.name // empty' <<<"$body")"
[[ "$name" =~ ^[a-z0-9][a-z0-9._-]{1,63}$ ]] || fail 400 "Nome de org inválido (use [a-z0-9._-])" "name_invalid"
if org_exists "$name"; then org_can_manage "$name" "$SESSION_LOGIN" || fail 409 "Org já existe" "taken"; fi
title="$(jq -r '.title // empty' <<<"$body")"
members_csv="$(jq -r '(.members // []) | map(select(test("^[A-Za-z0-9][A-Za-z0-9._-]*$"))) | join(",")' <<<"$body")"
admins_csv="$(jq -r '(.admins // []) | map(select(test("^[A-Za-z0-9][A-Za-z0-9._-]*$"))) | join(",")' <<<"$body")"
pa="$(jq -r 'if .public_allowed==true then "true" else "false" end' <<<"$body")"

org_register "$name" "$SESSION_LOGIN" "$members_csv" "$admins_csv" "$title" "$pa"
audit_log "org-create" "name=$name by=$SESSION_LOGIN public_allowed=$pa"
ok_json '{action:"org-create", name:$n, title:($t|if .=="" then $n else . end),
          members:$m, admins:$a, public_allowed:$pa, implicit:false, mine:true, can_manage:true}' \
  --arg n "$name" --arg t "$title" --argjson pa "$pa" \
  --argjson m "$(org_members "$name")" --argjson a "$(org_admins "$name")"
