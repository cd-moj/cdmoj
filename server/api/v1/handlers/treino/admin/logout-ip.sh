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

# pré-filtro por texto (um grep acha `IP=<ip>`), confirmação por source no MESMO processo — antes era
# um fork por arquivo de sessão (21k em 19/09/2026 ⇒ dezenas de segundos). Mesmo molde de lib/auth.sh.
_ip_sessions(){
  local f CONTEST LOGIN IP USERFULLNAME LOGINAT UA_B64 MKEY ACTOR
  while IFS= read -r -d '' f; do
    CONTEST=""; LOGIN=""; IP=""; source "$f" 2>/dev/null
    [[ "$CONTEST" == treino && "$IP" == "$ip" ]] || continue
    rm -f "$f" && printf '%s\n' "$LOGIN"
  done < <(find "$SESSIONDIR" -maxdepth 1 -type f -print0 2>/dev/null | xargs -0 -r grep -lxZF -e "IP=$ip" 2>/dev/null)
}
removed=0; declare -A AFFECTED
while IFS= read -r lg; do ((removed++)); [[ -n "$lg" ]] && AFFECTED["$lg"]=1; done < <(_ip_sessions)
users="$( ((${#AFFECTED[@]})) && printf '%s\n' "${!AFFECTED[@]}" | jq -R . | jq -cs . || echo '[]')"
audit_log logout-ip "ip=$ip removed=$removed"
ok_json '{logged_out:true, ip:$ip, sessions_removed:$n, users:$u, users_count:($u|length)}' \
  --arg ip "$ip" --argjson n "$removed" --argjson u "$users"
