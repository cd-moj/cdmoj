# POST /treino/admin/lock-user  {login} | {logins:[...]}  (.admin)
# Trava o acesso: troca a senha por uma aleatória e remove as sessões (um ou vários usuários).
require_method POST
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
mapfile -t targets < <(jq -r 'if .logins then .logins[] elif .login then .login else empty end' <<<"$body")
(( ${#targets[@]} )) || fail 400 "Informe login ou logins" "missing"
for t in "${targets[@]}"; do valid_id "$t" || fail 400 "Login inválido" "login_invalid"; done

declare -A LOCKED
for t in "${targets[@]}"; do
  user_exists treino "$t" || continue
  newpass="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 18)"
  [[ -n "$newpass" ]] && user_set_password treino "$t" "$newpass" && LOCKED["$t"]=1
done
(( ${#LOCKED[@]} )) || fail 404 "Nenhum usuário válido para travar" "user_notfound"

removed=0
set +o noglob; shopt -s nullglob
for f in "$SESSIONDIR"/*; do
  [[ -f "$f" ]] || continue
  lg="$( CONTEST=""; LOGIN=""; source "$f" 2>/dev/null; [[ "$CONTEST" == treino ]] && printf '%s' "$LOGIN" )"
  if [[ -n "$lg" && -n "${LOCKED[$lg]:-}" ]]; then rm -f "$f"; ((removed++)); fi
done
shopt -u nullglob
users="$(printf '%s\n' "${!LOCKED[@]}" | jq -R . | jq -cs .)"
audit_log lock-user "users=$(IFS=,; echo "${!LOCKED[*]}") removed=$removed"
ok_json '{locked:true, users:$u, users_count:($u|length), sessions_removed:$n}' \
  --argjson u "$users" --argjson n "$removed"
