# POST /contest/admin/user-disable?contest=<id>  (admin) {login}
# Desabilita o login (senha vira inutilizável, marcada com '!') e encerra as sessões.
# Para reabilitar, use user-add (reset de senha).
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
login="$(jq -r '.login // empty' <<<"$body")"
[[ -n "$login" ]] || fail 400 "Informe o login" "missing"
valid_id "$login" || fail 422 "login inválido" "login_invalid"
[[ "$login" == "$SESSION_LOGIN" ]] && fail 409 "Você não pode desabilitar a si mesmo" "self"
is_reserved_role_login "$login" && fail 403 "Não desabilite contas privilegiadas" "privileged"
newpw="!$(head -c 18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 16)"
if store_v2 "$contest"; then
  # v2: senha '!…' no account.json (passwd derivado herda a marca; user-add reabilita)
  user_exists "$contest" "$login" || fail 404 "Usuário não encontrado" "notfound"
  user_set_password "$contest" "$login" "$newpw" || fail 500 "Falha ao gravar" "write_fail"
else
  grep -q "^$login:" "$CONTESTSDIR/$contest/passwd" 2>/dev/null || fail 404 "Usuário não encontrado" "notfound"
  update_passwd_field "$contest" "$login" 2 "$newpw" || fail 500 "Falha ao gravar" "write_fail"
fi
removed="$(remove_contest_sessions "$contest" "$login")"
audit_log_to "$contest" user-disable "login=$login removed=$removed"
ok_json '{disabled:true, login:$l, sessions_removed:$n}' --arg l "$login" --argjson n "${removed:-0}"
