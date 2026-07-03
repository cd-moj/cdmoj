# GET /orgs/get?name=<org>  (Bearer) -> detalhe de UMA org. Só membro/admin da org ou admin global;
# senão 404 (não revela a existência de uma org alheia — provas em elaboração não vazam).
require_method GET
require_auth
source "$_DIR/lib/orgs.sh"
name="$(param name)"
[[ -n "$name" ]] || fail 400 "Missing name" "name_missing"
org_exists "$name" || fail 404 "Org não encontrada" "not_found"
{ org_is_member "$name" "$SESSION_LOGIN" || { declare -F is_admin >/dev/null && is_admin; }; } \
  || fail 404 "Org não encontrada" "not_found"
cm=false; org_can_manage "$name" "$SESSION_LOGIN" && cm=true
ok_json '{name:$n, title:$t, members:$m, admins:$a, public_allowed:$pa, implicit:$im,
          mine:($cb==$me), can_manage:$cm}' \
  --arg n "$name" --arg t "$(org_title "$name")" --arg me "$SESSION_LOGIN" \
  --arg cb "$(jq -r --arg n "$name" '.[$n].created_by // ""' "$ORGS_REGISTRY" 2>/dev/null)" \
  --argjson m "$(org_members "$name")" --argjson a "$(org_admins "$name")" \
  --argjson pa "$(org_public_allowed "$name" && echo true || echo false)" \
  --argjson im "$(org_is_implicit "$name" && echo true || echo false)" \
  --argjson cm "$cm"
