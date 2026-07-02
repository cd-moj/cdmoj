# GET /treino/signup/status?nonce=<nonce>   (PÚBLICO)
# Polling da página: {status: pending|created|already_linked|linked|expired, login?}.
# NUNCA devolve a senha (a senha vai só por DM do bot — posse do Telegram = prova).
nonce="$(param nonce)"
[[ -n "$nonce" ]] || fail 400 "Missing nonce" "nonce_missing"
emit_json 200 OK
jq -cn --argjson s "$(tg_nonce_status "$nonce")" '{success:true} + $s'
