# POST /contest/admin/user-disqualify?contest=<id>  (admin) {login, undo?}
# DESCLASSIFICA o time: seta .disqualified=true no account.json — a conta continua
# existindo (auditoria/gestão/histórico), mas SOME do placar (sc_users) E da estatística
# (stats-gen pula o login por inteiro), juntos — placar e estatística nunca podem contar
# populações diferentes (a lição do relato da LATAM 2026). {undo:true} reverte.
# Não mexe em senha/sessões: desclassificar ≠ desabilitar (use user-disable p/ barrar login).
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
login="$(jq -r '.login // empty' <<<"$body")"
undo=false; jq -e '.undo == true' >/dev/null 2>&1 <<<"$body" && undo=true
[[ -n "$login" ]] || fail 400 "Informe o login" "missing"
valid_id "$login" || fail 422 "login inválido" "login_invalid"
[[ "$login" == "$SESSION_LOGIN" ]] && fail 409 "Você não pode desclassificar a si mesmo" "self"
is_reserved_role_login "$login" && fail 403 "Conta privilegiada não é time" "privileged"
user_exists "$contest" "$login" || fail 404 "Usuário não encontrado" "notfound"
af="$(account_file "$contest" "$login")"
[[ -f "$af" ]] || fail 409 "Conta compartilhada (USERS_FROM) não pode ser desclassificada daqui" "shared_account"
tmp="$af.tmp.${BASHPID}"
if [[ "$undo" == true ]]; then
  jq -c 'del(.disqualified) | .updated_at = now | .updated_at |= floor' "$af" > "$tmp" 2>/dev/null
else
  jq -c '.disqualified = true | .updated_at = now | .updated_at |= floor' "$af" > "$tmp" 2>/dev/null
fi
[[ -s "$tmp" ]] || { rm -f "$tmp"; fail 500 "Falha ao gravar" "write_fail"; }
mv -f "$tmp" "$af"
# mutação user-visível de conta ⇒ placar/estatística regeneram (regra do .score-dirty)
touch "$CONTESTSDIR/$contest/var/.score-dirty" 2>/dev/null
audit_log_to "$contest" user-disqualify "login=$login undo=$undo"
ok_json '{disqualified:$d, login:$l}' --argjson d "$([[ "$undo" == true ]] && echo false || echo true)" --arg l "$login"
