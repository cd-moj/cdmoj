# POST /treino/signup/verify   (AUTH: bot token — require_bot)
# body: {nonce, telegram_id, telegram_username?, first_name?, last_name?}
# O bot repassa o `/start <nonce>` + a identidade Telegram. Consome o nonce (uso único) e:
#   purpose=signup -> cria a conta (SEM sufixo de papel) e vincula; devolve a senha (só p/ DM).
#   purpose=link   -> vincula o Telegram à conta logada que gerou o nonce (não cria conta).
# Anti-duplicata: 1 telegram_id = no máx 1 conta. Se já vinculado -> already_linked (recuperação).
require_method POST
require_bot
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
nonce="$(jq -r '.nonce // empty' <<<"$body")"
tgid="$(jq -r '.telegram_id // empty' <<<"$body")"
uname="$(jq -r '.telegram_username // empty' <<<"$body")"
first="$(jq -r '.first_name // empty' <<<"$body")"
last="$(jq -r '.last_name // empty' <<<"$body")"
[[ -n "$nonce" ]] || fail 400 "Missing nonce" "nonce_missing"
valid_tgid "$tgid" || fail 400 "telegram_id inválido" "tgid_invalid"

pj="$(tg_nonce_claim "$nonce")"; rc=$?
case "$rc" in
  1) fail 404 "Link de verificação inválido" "nonce_invalid" ;;
  2) fail 410 "Link de verificação expirado" "nonce_expired" ;;
esac
purpose="$(jq -r '.purpose // "signup"' <<<"$pj")"

# anti-duplicata (vale p/ os dois fluxos): já existe conta com este telegram_id?
existing="$(tg_login_of_id treino "$tgid")"
if [[ -n "$existing" ]]; then
  tg_touch treino "$tgid" "$uname"
  tg_nonce_done "$nonce" already_linked "$existing"
  ok_json '{status:"already_linked", login:$l}' --arg l "$existing"
  exit 0
fi

if [[ "$purpose" == link ]]; then
  bind="$(jq -r '.bind_login // empty' <<<"$pj")"
  [[ -n "$bind" ]] && user_exists treino "$bind" || fail 409 "Conta a vincular não existe" "link_no_account"
  tg_link treino "$tgid" "$bind" "$uname" link || fail 409 "Telegram já vinculado a outra conta" "tg_conflict"
  tg_nonce_done "$nonce" linked "$bind"
  ok_json '{status:"linked", login:$l}' --arg l "$bind"
  exit 0
fi

# ----- purpose=signup: cria a conta -----
login="$(jq -r '.login // empty' <<<"$pj")"
fullname="$(jq -r '.fullname // empty' <<<"$pj")"
[[ -n "$fullname" ]] || { fullname="$(printf '%s %s' "$first" "$last")"; fullname="${fullname#"${fullname%%[![:space:]]*}"}"; fullname="${fullname%"${fullname##*[![:space:]]}"}"; }
[[ -n "$fullname" ]] || fullname="$uname"
[[ -n "$login" ]] || login="$(tg_derive_login "$uname" "$tgid")"
tg_reserved_login "$login" && fail 400 "Sufixo reservado não permitido" "login_reserved"
[[ "$login" =~ ^[A-Za-z0-9._-]{2,32}$ ]] || login="$(tg_derive_login "$uname" "$tgid")"
login="$(tg_unique_login treino "$login")"

pw="$(user_genpass)"
user_create treino "$login" "$fullname" "$pw" "" || fail 500 "Falha ao criar a conta" "create_fail"
university="$(jq -r '.university // empty' <<<"$pj")"
[[ -n "$university" ]] && account_merge treino "$login" '.university=$u|.updated_at=$t' --arg u "$university" --argjson t "$EPOCHSECONDS"
tg_link treino "$tgid" "$login" "$uname" signup || { fail 409 "Telegram já vinculado" "tg_conflict"; }
tg_nonce_done "$nonce" created "$login"
ok_json '{status:"created", login:$l, password:$p}' --arg l "$login" --arg p "$pw"
