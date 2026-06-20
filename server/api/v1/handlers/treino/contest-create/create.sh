# POST /treino/contest-create  (auth treino, pode criar) -> cria e publica o contest (no ar na hora)
require_method POST
require_auth_contest treino
source "$_LIBDIR/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar contest" "create_forbidden"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
cc_create "$body" "$SESSION_LOGIN" "$SESSION_NAME"
audit_log contest-create "id=$(jq -r '.contest_id' <<<"$CC_RESULT") mode=$(jq -r '.mode//"?"' <<<"$body") name=$(jq -r '.name//"?"' <<<"$body")"
ok_json '$r' --argjson r "$CC_RESULT"
