# /orgs/members  (Bearer)
#   GET  ?name=<org>  -> {name, members, admins, mine, can_manage, implicit}
#   POST {name, add?, remove?, admins_add?, admins_remove?} -> idem
# Só admin da org (ou admin global) gerencia. MEMBROS escrevem em qualquer problema da org; ADMINS
# também gerem a trava de público. O criador nunca perde membro/admin. Org implícita não tem gestão.
require_auth
source "$_DIR/lib/orgs.sh"
if [[ "$REQUEST_METHOD" == GET ]]; then name="$(param name)"
else body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"; name="$(jq -r '.name // empty' <<<"$body")"; fi
[[ -n "$name" ]] || fail 400 "Missing name" "name_missing"
org_exists "$name" || fail 404 "Org não encontrada" "not_found"
{ org_is_member "$name" "$SESSION_LOGIN" || { declare -F is_admin >/dev/null && is_admin; }; } \
  || fail 404 "Org não encontrada" "not_found"   # não vaza org alheia

cb="$(jq -r --arg n "$name" '.[$n].created_by // ""' "$ORGS_REGISTRY" 2>/dev/null)"
if [[ "$REQUEST_METHOD" == POST ]]; then
  org_can_manage "$name" "$SESSION_LOGIN" || fail 403 "Só um admin da org gerencia membros" "forbidden"
  org_is_implicit "$name" && fail 409 "Org implícita não tem gestão de membros" "implicit"
  add="$(jq -c '(.add // []) | map(select(test("^[A-Za-z0-9][A-Za-z0-9._-]*$")))' <<<"$body")"
  rem="$(jq -c '(.remove // [])' <<<"$body")"
  aadd="$(jq -c '(.admins_add // []) | map(select(test("^[A-Za-z0-9][A-Za-z0-9._-]*$")))' <<<"$body")"
  arem="$(jq -c '(.admins_remove // [])' <<<"$body")"
  # remove = sai da org (membro e admin); admins_remove = rebaixa a membro. Criador é blindado.
  newm="$(jq -cn --argjson c "$(org_members "$name")" --argjson a "$add" --argjson aa "$aadd" --argjson r "$rem" --arg cb "$cb" '((($c+$a+$aa)-$r)+[$cb])|unique')"
  newa="$(jq -cn --argjson c "$(org_admins "$name")"  --argjson aa "$aadd" --argjson ar "$arem" --argjson r "$rem" --arg cb "$cb" '(((($c+$aa)-$ar)-$r)+[$cb])|unique')"
  org_set_members "$name" "$newm"; org_set_admins "$name" "$newa"
  audit_log "org-members" "name=$name by=$SESSION_LOGIN"
fi
cm=false; org_can_manage "$name" "$SESSION_LOGIN" && cm=true
ok_json '{name:$n, members:$m, admins:$a, mine:($cb==$me), can_manage:$cm, implicit:$im}' \
  --arg n "$name" --arg me "$SESSION_LOGIN" --arg cb "$cb" \
  --argjson m "$(org_members "$name")" --argjson a "$(org_admins "$name")" \
  --argjson cm "$cm" --argjson im "$(org_is_implicit "$name" && echo true || echo false)"
