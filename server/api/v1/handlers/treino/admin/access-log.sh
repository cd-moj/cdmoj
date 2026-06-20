# GET /treino/admin/access-log[?day=YYYY-MM-DD]  (.admin) -> logins (epoch, login, ip, user-agent)
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"
day="$(param day)"
log="$CONTESTSDIR/treino/var/access.log"
emit_json 200 OK
[[ -f "$log" ]] || { jq -cn '{success:true, day:"", entries:[]}'; exit 0; }

if [[ -n "$day" ]]; then
  [[ "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || fail 400 "Dia inválido (YYYY-MM-DD)" "day_invalid"
  start="$(date -d "$day 00:00:00" +%s 2>/dev/null)" || fail 400 "Dia inválido" "day_invalid"
  rows="$(awk -F'\t' -v a="$start" -v b="$((start+86400))" '$1>=a && $1<b' "$log")"
else
  rows="$(tail -n 1000 "$log")"
fi

printf '%s\n' "$rows" | jq -R -cs --arg day "$day" '
  { success:true, day:$day,
    entries: ( split("\n") | map(select(length>0) | split("\t") |
       { time:(.[0]|tonumber? // 0), login:.[1], ip:.[2],
         user_agent:((.[3] // "") | @base64d) }) | reverse ) }'
