# POST /treino/recover-password   (AUTH: bot token — require_bot)
# body: {telegram_id}
# Recuperação de senha ancorada no vínculo Telegram (a posse do Telegram É a prova de identidade).
# Resolve o login pelo índice, gera nova senha e a devolve (o bot entrega por DM). Sem vínculo:
# {status:"not_linked"} — o bot orienta a criar conta pela página.
require_method POST
require_bot
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
tgid="$(jq -r '.telegram_id // empty' <<<"$body")"
valid_tgid "$tgid" || fail 400 "telegram_id inválido" "tgid_invalid"

login="$(tg_login_of_id treino "$tgid")"
if [[ -z "$login" ]]; then
  ok_json '{status:"not_linked"}'
  exit 0
fi
store_v2 treino || fail 503 "Indisponível (store não migrado)" "store_not_v2"
pw="$(user_genpass)"
user_set_password treino "$login" "$pw" || fail 500 "Falha ao trocar a senha" "passwd_fail"
ok_json '{status:"ok", login:$l, password:$p}' --arg l "$login" --arg p "$pw"
