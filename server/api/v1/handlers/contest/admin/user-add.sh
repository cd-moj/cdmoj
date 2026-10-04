# POST /contest/admin/user-add?contest=<id>  (admin DO contest)
#   {login,password?,fullname?,email?, univ_short?,univ_full?,country?,region?}
# Adiciona OU atualiza (reset de senha) um usuário do contest. Devolve a credencial.
# `fullname` é o nome do time (campo ÚNICO de nome); os campos de TIME (opcionais)
# mesclam no `.team` do account.json (team_fields_json).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
source "$_LIBDIR/contest-create.sh"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
login="$(jq -r '.login // empty' <<<"$body")"
pass="$(jq -r '.password // empty' <<<"$body")"
full="$(jq -r '.fullname // empty' <<<"$body")"
email="$(jq -r '.email // empty' <<<"$body")"
[[ -n "$login" ]] || fail 400 "Informe o login" "missing"
valid_id "$login" || fail 422 "login inválido" "login_invalid"
[[ -z "$pass" ]] && pass="$(cc_genpass)"
[[ -z "$full" ]] && full="$login"
case "$pass$full$email" in *:*) fail 422 "senha/nome/email não podem conter ':'" "colon";; esac

# account.json é a fonte (auth/placar leem direto dele)
teamj="$(team_fields_json "$body")"
RESET=0
if user_exists "$contest" "$login"; then
  # reset de senha = reabilitar (tira a marca `disabled`) E derrubar as sessões abertas: o token antigo de uma conta
  # com senha vazada seguia valendo (auditoria do painel, 03/10/2026)
  account_merge "$contest" "$login" '.password=$p|.fullname=$f|.email=$e|.updated_at=$t|del(.disabled)' \
    --arg p "$pass" --arg f "$full" --arg e "$email" --argjson t "$EPOCHSECONDS" \
    || fail 500 "Falha ao gravar" "write_fail"
  RESET=1
else
  user_create "$contest" "$login" "$full" "$pass" "$email" || fail 500 "Falha ao criar" "write_fail"
fi
account_team_merge "$contest" "$login" "$teamj" || fail 500 "Falha ao gravar time" "write_fail"
(( RESET )) && [[ "$login" != "$SESSION_LOGIN" ]] && remove_contest_sessions "$contest" "$login" >/dev/null 2>&1
audit_log_to "$contest" user-add "login=$login$( (( RESET )) && echo ' reset=1')"
ok_json '{saved:true, user:{login:$l, password:$p, fullname:$f, email:$e}}' \
  --arg l "$login" --arg p "$pass" --arg f "$full" --arg e "$email"
