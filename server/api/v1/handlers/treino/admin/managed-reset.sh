# POST /treino/admin/managed-reset  (.admin) {login} — senha NOVA p/ conta GERIDA.
# A senha (user_genpass) é devolvida UMA vez; as sessões da conta caem. docs/CONTAS-GERIDAS.md.
require_method POST
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"
body="$(read_body)"
login="$(jq -r '.login // empty' <<<"$body" 2>/dev/null)"
[[ -n "$login" ]] || fail 400 "Informe login" "login_missing"
valid_id "$login" || fail 400 "Login inválido" "login_invalid"
user_exists treino "$login" || fail 404 "Usuário não encontrado" "user_notfound"
[[ -n "$(managed_json treino "$login")" ]] || fail 400 "Não é uma conta gerida" "not_managed"

pw="$(user_genpass)"
user_set_password treino "$login" "$pw" || fail 500 "Falha ao trocar a senha" "save_fail"

# sessões da conta caem (pré-filtro por texto: um grep, não um fork por arquivo — ver lib/auth.sh)
removed="$(remove_contest_sessions treino "$login")"

audit_log managed-reset "login=$login"
ok_json '{reset:true, login:$l, password:$p, sessions_removed:$n}' \
  --arg l "$login" --arg p "$pw" --argjson n "$removed"
