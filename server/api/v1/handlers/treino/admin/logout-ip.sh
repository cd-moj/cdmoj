# POST /treino/admin/logout-ip  {ip}  (.admin)
# Remove todas as sessões do treino que vieram de um IP (encerra acesso daquele IP).
require_method POST
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
ip="$(jq -r '.ip // empty' <<<"$body")"
[[ -n "$ip" ]] || fail 400 "Informe o IP" "missing"
[[ "$ip" =~ ^[0-9a-fA-F.:]+$ ]] || fail 400 "IP inválido" "ip_invalid"

removed=0; declare -A AFFECTED
set +o noglob; shopt -s nullglob
for f in "$SESSIONDIR"/*; do
  [[ -f "$f" ]] || continue
  m="$( CONTEST=""; LOGIN=""; IP=""; source "$f" 2>/dev/null; [[ "$CONTEST" == treino && "$IP" == "$ip" ]] && printf '1\t%s' "$LOGIN" )"
  if [[ "$m" == 1$'\t'* ]]; then rm -f "$f"; ((removed++)); lg="${m#*$'\t'}"; [[ -n "$lg" ]] && AFFECTED["$lg"]=1; fi
done
shopt -u nullglob
users="$( ((${#AFFECTED[@]})) && printf '%s\n' "${!AFFECTED[@]}" | jq -R . | jq -cs . || echo '[]')"
audit_log logout-ip "ip=$ip removed=$removed"
ok_json '{logged_out:true, ip:$ip, sessions_removed:$n, users:$u, users_count:($u|length)}' \
  --arg ip "$ip" --argjson n "$removed" --argjson u "$users"
