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
if store_v2 "$contest"; then
  # v2: conta = diretório; remover = mover p/ .removed-users (submissões preservadas)
  user_exists "$contest" "$login" || fail 404 "Usuário não encontrado" "notfound"
  trash="$CONTESTSDIR/$contest/.removed-users"; mkdir -p "$trash"
  mv "$(user_dir "$contest" "$login")" "$trash/$login-$EPOCHSECONDS" || fail 500 "Falha ao remover" "write_fail"
else
  pw="$CONTESTSDIR/$contest/passwd"
  grep -q "^$login:" "$pw" 2>/dev/null || fail 404 "Usuário não encontrado" "notfound"
  tmp="$(mktemp "${pw}.XXXXXX")" || fail 500 "tmp" "tmp"
  grep -v "^$login:" "$pw" 2>/dev/null > "$tmp"
  cat "$tmp" > "$pw" && rm -f "$tmp" || { rm -f "$tmp"; fail 500 "Falha ao gravar" "write_fail"; }
fi
audit_log_to "$contest" user-remove "login=$login"
ok_json '{removed:true, login:$l}' --arg l "$login"
