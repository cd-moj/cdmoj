# /problems/collection-members   (Bearer)
#   GET  ?name=<col>  -> {name, owner, members, admins, mine, can_manage, repo_course:false}
#   POST {name, add?, remove?, admins_add?, admins_remove?} -> idem
# Coleção = ORG (modelo MOJ-nativo): membros escrevem em qualquer problema; admins gerem o grupo.
# Alias de /orgs/members. Só admin da org (ou admin global) gerencia; criador blindado.
require_auth
source "$_DIR/lib/orgs.sh"
if [[ "$REQUEST_METHOD" == GET ]]; then name="$(param name)"
else body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"; name="$(jq -r '.name // empty' <<<"$body")"; fi
[[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$ ]] || fail 400 "Coleção inválida" "name_invalid"
org_exists "$name" || fail 404 "Coleção não existe (crie antes)" "missing"
{ org_is_member "$name" "$SESSION_LOGIN" || { declare -F is_admin >/dev/null && is_admin; }; } || fail 404 "Coleção não existe" "missing"
cb="$(jq -r --arg n "$name" '.[$n].created_by // ""' "$ORGS_REGISTRY" 2>/dev/null)"

if [[ "$REQUEST_METHOD" == POST ]]; then
  org_can_manage "$name" "$SESSION_LOGIN" || fail 403 "Só o dono ou um co-admin gerencia a coleção" "forbidden"
  org_is_implicit "$name" && fail 409 "Coleção implícita não tem gestão" "implicit"
  add="$(jq -c '(.add // []) | map(select(test("^[A-Za-z0-9][A-Za-z0-9._-]*$")))' <<<"$body")"
  rem="$(jq -c '(.remove // [])' <<<"$body")"
  aadd="$(jq -c '(.admins_add // []) | map(select(test("^[A-Za-z0-9][A-Za-z0-9._-]*$")))' <<<"$body")"
  arem="$(jq -c '(.admins_remove // [])' <<<"$body")"
  newm="$(jq -cn --argjson c "$(org_members "$name")" --argjson a "$add" --argjson aa "$aadd" --argjson r "$rem" --arg cb "$cb" '((($c+$a+$aa)-$r)+[$cb])|unique')"
  newa="$(jq -cn --argjson c "$(org_admins "$name")" --argjson aa "$aadd" --argjson ar "$arem" --argjson r "$rem" --arg cb "$cb" '(((($c+$aa)-$ar)-$r)+[$cb])|unique')"
  org_set_members "$name" "$newm"; org_set_admins "$name" "$newa"
  audit_log "collection-members" "name=$name by=$SESSION_LOGIN"
fi
cm=false; org_can_manage "$name" "$SESSION_LOGIN" && cm=true
ok_json '{name:$n, owner:$o, members:$m, admins:$a, mine:($o==$me), can_manage:$cm, repo_course:false}' \
  --arg n "$name" --arg o "$cb" --arg me "$SESSION_LOGIN" --argjson cm "$cm" \
  --argjson m "$(org_members "$name")" --argjson a "$(org_admins "$name")"
