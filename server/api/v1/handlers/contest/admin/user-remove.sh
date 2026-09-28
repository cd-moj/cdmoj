# POST /contest/admin/user-remove?contest=<id>  (admin DO contest) {login}
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
[[ "$login" == "$SESSION_LOGIN" ]] && fail 409 "Você não pode remover a si mesmo" "self_remove"
# conta = diretório; remover = mover p/ .removed-users (submissões preservadas)
# Contest COMPARTILHADO (USERS_FROM): mover o dir não basta — a pessoa voltaria na hora pela conta do
# treino. Fica um TOMBSTONE local (senha `!…` autoritativa + desclassificado: não entra, não aparece).
# Vale também p/ quem nunca entrou (barrar um login do treino de antemão).
shared=false
declare -F _users_source >/dev/null && [[ "$(_users_source "$contest")" != "$contest" ]] && shared=true
ud="$(user_dir "$contest" "$login")"
if ! user_exists "$contest" "$login"; then
  { [[ "$shared" == true ]] && { [[ -d "$ud" ]] || [[ -f "$CONTESTSDIR/$(_users_source "$contest")/users/$login/account.json" ]]; }; } \
    || fail 404 "Usuário não encontrado" "notfound"
fi
trash="$CONTESTSDIR/$contest/.removed-users"; mkdir -p "$trash"
if [[ -d "$ud" ]]; then mv "$ud" "$trash/$login-$EPOCHSECONDS" || fail 500 "Falha ao remover" "write_fail"; fi
if [[ "$shared" == true ]]; then
  shared_overlay_ensure "$contest" "$login" 1 || fail 500 "Falha ao gravar o bloqueio" "write_fail"
  account_merge "$contest" "$login" '.password=$p | .disqualified=true | .removed_at=$t | .updated_at=$t' \
    --arg p "!$(head -c 18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 16)" --argjson t "$EPOCHSECONDS" \
    || fail 500 "Falha ao gravar o bloqueio" "write_fail"
  remove_contest_sessions "$contest" "$login" >/dev/null
fi
touch "$CONTESTSDIR/$contest/var/.score-dirty" 2>/dev/null   # o placar tem de esquecê-lo sozinho
audit_log_to "$contest" user-remove "login=$login"
ok_json '{removed:true, login:$l}' --arg l "$login"
