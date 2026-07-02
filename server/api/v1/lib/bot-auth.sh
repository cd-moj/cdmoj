# lib/bot-auth.sh — autenticação do BOT do Telegram (mojinho) na API.
#
# O bot NÃO usa sessão de usuário nem loga como .admin: ele manda um token DEDICADO
# com prefixo `mojb_` no header `Authorization: Bearer mojb_<segredo>`. O prefixo evita
# colisão com tokens de sessão (lib/auth.sh) e de worker (`mojw_`, lib/worker-auth.sh).
# O segredo fica em $BOT_TOKEN_FILE (modo 600). Reaproveita _bearer_token() de lib/auth.sh
# e a comparação em tempo ~constante de lib/worker-auth.sh (_worker_token_eq).

: "${RUNDIR:=/home/ribas/moj/run}"
: "${BOT_TOKEN_FILE:=$RUNDIR/secrets/bot.token}"

# require_bot — exige Bearer mojb_<token> válido; senão responde e encerra.
require_bot() {
  local got expected
  got="$(_bearer_token 2>/dev/null)"
  [[ "$got" == mojb_* ]] || fail 401 "Bot token required" "bot_unauth"
  [[ -s "$BOT_TOKEN_FILE" ]] || fail 503 "Bot auth not configured" "bot_noconf"
  expected="$(< "$BOT_TOKEN_FILE")"
  _worker_token_eq "$expected" "$got" || fail 401 "Invalid bot token" "bot_badtoken"
  return 0
}
