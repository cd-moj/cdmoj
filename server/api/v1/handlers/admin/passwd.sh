# POST /admin/passwd   (Bearer, admin)
# body: {contest, login, newpass}
# Troca a senha no account.json do usuário (demais campos preservados). Reset = REABILITAR (tira o `disabled`) e
# DERRUBAR as sessões abertas da conta (sessão do MOJ não expira), como no /contest/admin/user-add.
# Guardas: no TREINO, conta de PAPEL (o SUPERADMIN incluso) só pelo super-admin numa sessão do treino
# (treino_role_write_ok, conferida antes da existência da conta: a mesma resposta p/ qualquer login de papel). Em
# contest COMPARTILHADO (USERS_FROM), 409 shared_users p/ conta que não tem senha local própria — overlay de
# participante (`shared_overlay`, a regra do admin/users.sh, que inclui a lápide do removido/desabilitado), sem
# senha, ou a conta de TIME da inscrição (`time-<slug>`, senha interna `!<uuid>`). Conta LOCAL desabilitada (`!…`
# sem overlay, ex.: um fiscal de sede) segue reabilitável aqui, como no user-add. Toda troca vai ao audit.
require_method POST
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
contest="$(jq -r '.contest // empty' <<<"$body")"
login="$(jq -r '.login // empty' <<<"$body")"
newpass="$(jq -r '.newpass // empty' <<<"$body")"

[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Admin only" "admin_required"

[[ -n "$login" && -n "$newpass" ]] || fail 400 "Missing login or newpass" "incomplete"
valid_id "$login" || fail 400 "Invalid login" "login_invalid"
[[ "$newpass" == *:* || "$newpass" == *$'\n'* ]] && fail 400 "Invalid newpass" "newpass_invalid"

treino_role_write_ok "$contest" "$login" \
  || fail 403 "Senha de conta de papel do treino: só o super-admin da plataforma" "superadmin_required"
user_exists "$contest" "$login" || fail 404 "User not found" "user_notfound"
if [[ "$(_users_source "$contest")" != "$contest" ]] \
   && ! jq -e --arg l "$login" '(.shared_overlay != true) and ((.password // "") != "")
                                and (($l | startswith("time-")) and ((.password // "") | startswith("!")) | not)' \
          "$(account_file "$contest" "$login")" >/dev/null 2>&1; then
  fail 409 "Conta do Treino Livre: a senha é a do treino. Para contas próprias, converta (Pessoas › Contas)." "shared_users"
fi
account_merge "$contest" "$login" '.password=$p|.updated_at=$t|del(.disabled)' \
    --arg p "$newpass" --argjson t "$EPOCHSECONDS" \
  || fail 500 "Could not set password" "passwd_failed"
[[ "$login" != "$SESSION_LOGIN" ]] && remove_contest_sessions "$contest" "$login" >/dev/null 2>&1
audit_log_to "$contest" "passwd" "login=$login"

ok_json '{action:"passwd", contest:$c, login:$l}' --arg c "$contest" --arg l "$login"
