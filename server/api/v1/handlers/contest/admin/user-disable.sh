# POST /contest/admin/user-disable?contest=<id>  (admin) {login, undo?}
# Desabilita o login (senha vira inutilizável, marcada com '!') e encerra as sessões.
# Para reabilitar uma conta PRÓPRIA do contest, use user-add (reset de senha).
# Participante COMPARTILHADO (USERS_FROM, entra com a conta do treino): antes dava 404 — não havia
# account.json local onde gravar — e o admin não conseguia barrar um trapaceiro. Agora ganha um overlay
# local (shared_overlay_ensure) com a senha `!…`, que é AUTORITATIVA (lib/auth.sh verify_password).
# {undo:true} reabilita o compartilhado (apaga a senha do overlay: volta a entrar com a do treino).
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
undo=false; jq -e '.undo == true' >/dev/null 2>&1 <<<"$body" && undo=true
if [[ "$undo" == true ]]; then
  user_exists "$contest" "$login" || fail 404 "Usuário não encontrado" "notfound"
  # TIME de inscrição: a senha é sempre `!<uuid>` (quem entra são os membros, pelo alias) — reabilitar é só tirar a
  # marca. Compartilhado: apaga a senha do overlay (volta a entrar com a do treino). Conta própria: senha nova.
  if [[ "$(account_field "$contest" "$login" '.is_team')" == true ]]; then
    account_merge "$contest" "$login" 'del(.disabled) | .updated_at=$t' --argjson t "$EPOCHSECONDS" \
      || fail 500 "Falha ao gravar" "write_fail"
  else
  [[ "$(account_field "$contest" "$login" '.shared_overlay')" == true ]] \
    || fail 409 "Conta própria do contest: reabilite com uma senha nova (user-add)" "use_user_add"
  account_merge "$contest" "$login" 'del(.password) | del(.disabled) | .updated_at=$t' --argjson t "$EPOCHSECONDS" \
    || fail 500 "Falha ao gravar" "write_fail"
  fi
  audit_log_to "$contest" user-disable "login=$login undo=true"
  ok_json '{disabled:false, login:$l}' --arg l "$login"
  exit 0
fi
newpw="!$(head -c 18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 16)"
# senha '!…' no account.json (o literal nunca casa no login; user-add reabilita). Compartilhado: overlay.
user_exists "$contest" "$login" || shared_overlay_ensure "$contest" "$login" \
  || fail 404 "Usuário não encontrado" "notfound"
# a marca `disabled` é o que vale p/ o TIME (o membro entra pelo alias com a senha DELE — trocar a senha `!<uuid>` do
# time não barrava ninguém; auditoria do painel, 03/10/2026); nas outras contas acompanha a senha `!…`
if [[ "$(account_field "$contest" "$login" '.is_team')" != true ]]; then
  user_set_password "$contest" "$login" "$newpw" || fail 500 "Falha ao gravar" "write_fail"
fi
account_merge "$contest" "$login" '.disabled=true | .updated_at=$t' --argjson t "$EPOCHSECONDS" || fail 500 "Falha ao gravar" "write_fail"
removed="$(remove_contest_sessions "$contest" "$login")"
audit_log_to "$contest" user-disable "login=$login removed=$removed"
ok_json '{disabled:true, login:$l, sessions_removed:$n}' --arg l "$login" --argjson n "${removed:-0}"
