# POST /treino/signup/telegram   (AUTH: bot token — require_bot)
# body: {telegram_id, telegram_username?, first_name?, last_name?}
# Fluxo BOT-FIRST (/participar): cria+vincula a conta ancorado no telegram_id (idempotente,
# à prova de troca de @username). Se já vinculado -> already_linked (com o login existente).
require_method POST
require_bot
store_v2 treino || fail 503 "Cadastro indisponível (store não migrado)" "store_not_v2"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
tgid="$(jq -r '.telegram_id // empty' <<<"$body")"
uname="$(jq -r '.telegram_username // empty' <<<"$body")"
first="$(jq -r '.first_name // empty' <<<"$body")"
last="$(jq -r '.last_name // empty' <<<"$body")"
valid_tgid "$tgid" || fail 400 "telegram_id inválido" "tgid_invalid"

existing="$(tg_login_of_id treino "$tgid")"
if [[ -n "$existing" ]]; then
  tg_touch treino "$tgid" "$uname"
  ok_json '{status:"already_linked", login:$l}' --arg l "$existing"
  exit 0
fi

fullname="$(printf '%s %s' "$first" "$last")"; fullname="${fullname#"${fullname%%[![:space:]]*}"}"; fullname="${fullname%"${fullname##*[![:space:]]}"}"
[[ -n "$fullname" ]] || fullname="$uname"
[[ -n "$fullname" ]] || fullname="user$tgid"
login="$(tg_unique_login treino "$(tg_derive_login "$uname" "$tgid")")"
pw="$(user_genpass)"
user_create treino "$login" "$fullname" "$pw" "" || fail 500 "Falha ao criar a conta" "create_fail"
tg_link treino "$tgid" "$login" "$uname" participar || fail 409 "Telegram já vinculado" "tg_conflict"
ok_json '{status:"created", login:$l, password:$p}' --arg l "$login" --arg p "$pw"
