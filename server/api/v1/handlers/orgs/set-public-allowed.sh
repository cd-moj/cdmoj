# POST /orgs/set-public-allowed  (Bearer)  body: {name, public_allowed:bool}
# Trava anti-vazamento: se OFF (padrão), NENHUM problema da org pode ficar público. Só admin da org
# (ou admin global). A org IMPLÍCITA nunca liga. Desligar DESPUBLICA em cascata os problemas públicos
# da org — a cascata entra no rework de set-public (Fase 4); por ora, vira só a flag.
require_method POST
require_auth
source "$_DIR/lib/orgs.sh"
body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
name="$(jq -r '.name // empty' <<<"$body")"
[[ -n "$name" ]] || fail 400 "Missing name" "name_missing"
org_exists "$name" || fail 404 "Org não encontrada" "not_found"
org_can_manage "$name" "$SESSION_LOGIN" || fail 403 "Só um admin da org muda a trava de público" "forbidden"
pa="$(jq -r 'if .public_allowed==true then "true" elif .public_allowed==false then "false" else "" end' <<<"$body")"
[[ -n "$pa" ]] || fail 400 "public_allowed deve ser bool" "bad_value"
org_set_public_allowed "$name" "$pa"; rc=$?
case "$rc" in
  0) ;;
  3) fail 409 "Org implícita é sempre privada (não permite público)" "implicit_private" ;;
  *) fail 500 "Falha ao gravar a trava" "write_failed" ;;
esac
# TODO Fase 4: se pa==false, despublicar em cascata os problemas públicos desta org (tira do treino).
audit_log "org-public-allowed" "name=$name public_allowed=$pa by=$SESSION_LOGIN"
ok_json '{action:"org-set-public-allowed", name:$n, public_allowed:$pa}' --arg n "$name" --argjson pa "$pa"
