# POST /treino/admin/logout-user  {login} | {logins:[...]}  (.admin)
# Remove todas as sessões dos usuários informados (um ou vários).
require_method POST
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
mapfile -t targets < <(jq -r 'if .logins then .logins[] elif .login then .login else empty end' <<<"$body")
(( ${#targets[@]} )) || fail 400 "Informe login ou logins" "missing"
declare -A WANT
for t in "${targets[@]}"; do valid_id "$t" || fail 400 "Login inválido" "login_invalid"; WANT["$t"]=1; done

removed=0; declare -A AFFECTED
set +o noglob; shopt -s nullglob
for f in "$SESSIONDIR"/*; do
  [[ -f "$f" ]] || continue
  lg="$( CONTEST=""; LOGIN=""; source "$f" 2>/dev/null; [[ "$CONTEST" == treino ]] && printf '%s' "$LOGIN" )"
  if [[ -n "$lg" && -n "${WANT[$lg]:-}" ]]; then rm -f "$f"; ((removed++)); AFFECTED["$lg"]=1; fi
done
shopt -u nullglob
users="$( ((${#AFFECTED[@]})) && printf '%s\n' "${!AFFECTED[@]}" | jq -R . | jq -cs . || echo '[]')"
audit_log logout-user "targets=$(IFS=,; echo "${targets[*]}") removed=$removed"
ok_json '{logged_out:true, users:$u, users_count:($u|length), sessions_removed:$n}' \
  --argjson u "$users" --argjson n "$removed"
