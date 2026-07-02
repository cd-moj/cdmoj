# POST /treino/telegram/link-start   (Bearer — sessão do treino)
# Uma conta logada (ex.: um .admin que quer receber alertas, ou um usuário legado sem vínculo)
# gera um nonce + deep-link para vincular o próprio Telegram no bot. O verify (purpose=link)
# associa o telegram_id à conta logada (bind_login), sem criar conta nova.
require_method POST
require_auth_contest treino
[[ -n "$SESSION_LOGIN" ]] || fail 401 "Not authenticated" "auth_required"
nonce="$(tg_nonce_new link "$(jq -cn --arg b "$SESSION_LOGIN" '{bind_login:$b}')")"
ok_json '{nonce:$n, deep_link:$dl, expires_at:$e}' \
  --arg n "$nonce" --arg dl "$(tg_deeplink "$nonce")" --argjson e "$(( EPOCHSECONDS + TG_NONCE_TTL ))"
