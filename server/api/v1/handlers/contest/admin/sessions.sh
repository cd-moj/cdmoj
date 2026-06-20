# GET /contest/admin/sessions?contest=<id>  (admin DO contest)
# Sessões ativas do contest + alerta de UA/IP diferentes (mesmo login de máquinas distintas).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"

emit_json 200 OK
set +o noglob; shopt -s nullglob
out=()
for f in "$SESSIONDIR"/*; do
  [[ -f "$f" ]] || continue
  j="$(
    CONTEST=""; LOGIN=""; USERFULLNAME=""; LOGINAT=""; IP=""; UA_B64=""
    source "$f" 2>/dev/null
    [[ "$CONTEST" == "$contest" ]] || exit 0
    jq -cn --arg l "$LOGIN" --arg n "$USERFULLNAME" --arg ip "$IP" \
       --arg ua "$(printf '%s' "$UA_B64" | base64 -d 2>/dev/null)" --argjson at "${LOGINAT:-0}" \
       '{login:$l, name:$n, ip:$ip, user_agent:$ua, login_at:$at}'
  )"
  [[ -n "$j" ]] && out+=("$j")
done
shopt -u nullglob

if (( ${#out[@]} )); then
  printf '%s\n' "${out[@]}" | jq -cs '
    ( group_by(.login) | map({login:.[0].login, nip:(map(.ip)|unique|length), nua:(map(.user_agent)|unique|length)}) | INDEX(.login) ) as $g
    | map(. + {multi_ip:(($g[.login].nip)>1), multi_ua:(($g[.login].nua)>1)})
    | sort_by(-.login_at) as $s
    | {success:true, count:($s|length), sessions:$s,
       alerts:([ $s[] | select(.multi_ip or .multi_ua) | {login, multi_ip, multi_ua} ] | unique_by(.login)) }'
else
  jq -cn '{success:true, count:0, sessions:[], alerts:[]}'
fi
