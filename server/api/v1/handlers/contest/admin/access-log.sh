# GET /contest/admin/access-log?contest=<id>[&day=YYYY-MM-DD]  (admin DO contest)
# Log de acessos (logins) do contest: epoch, login, ip, user-agent. Marca quais logins
# apareceram de >1 IP ou >1 UA (entraram de máquina/navegador diferente).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"

day="$(param day)"
log="$CONTESTSDIR/$contest/var/access.log"
emit_json 200 OK
[[ -f "$log" ]] || { jq -cn '{success:true, day:"", entries:[], alerts:[]}'; exit 0; }

if [[ -n "$day" ]]; then
  [[ "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || fail 400 "Dia inválido (YYYY-MM-DD)" "day_invalid"
  start="$(date -d "$day 00:00:00" +%s 2>/dev/null)" || fail 400 "Dia inválido" "day_invalid"
  rows="$(awk -F'\t' -v a="$start" -v b="$((start+86400))" '$1>=a && $1<b' "$log")"
else
  rows="$(tail -n 2000 "$log")"
fi

printf '%s\n' "$rows" | jq -R -cs --arg day "$day" '
  ( split("\n") | map(select(length>0) | split("\t")
      | { time:(.[0]|tonumber? // 0), login:.[1], ip:.[2], user_agent:((.[3] // "") | @base64d) }) ) as $e
  | ( $e | group_by(.login) | map({login:.[0].login, nip:(map(.ip)|unique|length), nua:(map(.user_agent)|unique|length)})
        | map(select(.nip>1 or .nua>1) | {login, multi_ip:(.nip>1), multi_ua:(.nua>1)}) ) as $al
  | {success:true, day:$day, entries:($e|reverse), alerts:$al}'
