# POST /treino/signup/start   body: {login?, fullname, university?}   (PÚBLICO)
# Inicia o cadastro web-first: valida o login desejado (se veio) e gera um nonce + deep-link
# para o aluno confirmar no bot (t.me/<bot>?start=<nonce>). NÃO cria a conta aqui — quem cria é
# o /treino/signup/verify (chamado pelo bot, com a identidade Telegram). Anti-enumeração: só
# reporta "em uso" quando o login foi explicitamente escolhido.
require_method POST
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
login="$(jq -r '.login // empty' <<<"$body")"
fullname="$(jq -r '.fullname // empty' <<<"$body")"
university="$(jq -r '.university // empty' <<<"$body")"
[[ -n "$fullname" ]] || fail 400 "Informe seu nome completo" "fullname_missing"
[[ "$fullname" == *:* || "$fullname" == *$'\n'* ]] && fail 400 "Nome inválido" "fullname_invalid"

if [[ -n "$login" ]]; then
  [[ "$login" =~ ^[A-Za-z0-9._-]{2,32}$ ]] || fail 400 "Login inválido (2–32: letras, números, . _ -)" "login_invalid"
  tg_reserved_login "$login" && fail 400 "Sufixo reservado não permitido" "login_reserved"
  user_exists treino "$login" && fail 409 "Esse login já está em uso" "login_taken"
fi

nonce="$(tg_nonce_new signup "$(jq -cn --arg l "$login" --arg n "$fullname" --arg u "$university" \
          '{login:$l, fullname:$n, university:$u}')")"
ok_json '{nonce:$n, deep_link:$dl, expires_at:$e}' \
  --arg n "$nonce" --arg dl "$(tg_deeplink "$nonce")" --argjson e "$(( EPOCHSECONDS + TG_NONCE_TTL ))"
