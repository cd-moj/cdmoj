# GET /treino/admin/sessions  (.admin) -> sessões ativas do treino (login, ip, user-agent, hora)
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"
emit_json 200 OK
set +o noglob; shopt -s nullglob
out=()
for f in "$SESSIONDIR"/*; do
  [[ -f "$f" ]] || continue
  j="$(
    CONTEST=""; LOGIN=""; USERFULLNAME=""; LOGINAT=""; IP=""; UA_B64=""
    source "$f" 2>/dev/null
    [[ "$CONTEST" == treino ]] || exit 0
    jq -cn --arg l "$LOGIN" --arg n "$USERFULLNAME" --arg ip "$IP" \
       --arg ua "$(printf '%s' "$UA_B64" | base64 -d 2>/dev/null)" --argjson at "${LOGINAT:-0}" \
       '{login:$l, name:$n, ip:$ip, user_agent:$ua, login_at:$at}'
  )"
  [[ -n "$j" ]] && out+=("$j")
done
shopt -u nullglob
if (( ${#out[@]} )); then
  printf '%s\n' "${out[@]}" | jq -cs '{success:true, count:length, sessions:(sort_by(-.login_at))}'
else
  jq -cn '{success:true, count:0, sessions:[]}'
fi
