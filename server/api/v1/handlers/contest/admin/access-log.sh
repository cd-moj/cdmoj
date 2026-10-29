# GET /contest/admin/access-log?contest=<id>[&day=YYYY-MM-DD]  (admin DO contest)
# Log de acessos (logins) do contest: epoch, login, ip, user-agent. Marca quais logins
# apareceram de >1 IP ou >1 UA (entraram de máquina/navegador diferente). `refused`: as tentativas
# RECUSADAS do mesmo período ({time, login ("" = conta inexistente), ip, user_agent, code, http}).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"

day="$(param day)"
log="$CONTESTSDIR/$contest/var/access.log"
rlog="$CONTESTSDIR/$contest/var/login-refused.log"
start=""
if [[ -n "$day" ]]; then
  [[ "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || fail 400 "Dia inválido (YYYY-MM-DD)" "day_invalid"
  start="$(date -d "$day 00:00:00" +%s 2>/dev/null)" || fail 400 "Dia inválido" "day_invalid"
fi
# _day_rows <arquivo> — as linhas do dia (sem dia: as últimas 2000)
_day_rows(){ [[ -f "$1" ]] || return 0
  if [[ -n "$start" ]]; then awk -F'\t' -v a="$start" -v b="$((start+86400))" '$1>=a && $1<b' "$1"; else tail -n 2000 "$1"; fi; }
# as TENTATIVAS RECUSADAS (auth/login → login_refused_log, lib/auth.sh) vão por arquivo (--rawfile): crescem com o
# evento. Login `?` = a conta não existe (o texto digitado não é gravado).
RF="$(mktemp)" || fail 500 "tmp" "tmp"; trap 'rm -f "$RF"' EXIT
_day_rows "$rlog" > "$RF"
body="$(_day_rows "$log" | jq -R -cs --arg day "$day" --rawfile rf "$RF" '
  ( split("\n") | map(select(length>0) | split("\t")
      | { time:(.[0]|tonumber? // 0), login:.[1], ip:.[2], user_agent:((.[3] // "") | try @base64d catch "") }) ) as $e
  | ( $e | group_by(.login) | map({login:.[0].login, nip:(map(.ip)|unique|length), nua:(map(.user_agent)|unique|length)})
        | map(select(.nip>1 or .nua>1) | {login, multi_ip:(.nip>1), multi_ua:(.nua>1)}) ) as $al
  | ( $rf | split("\n") | map(select(length>0) | split("\t")
      | { time:(.[0]|tonumber? // 0), login:(if (.[1] // "?") == "?" then "" else .[1] end), ip:(.[2] // ""),
          user_agent:((.[3] // "") | try @base64d catch ""), code:(.[4] // ""), http:(.[5]|tonumber? // 0) }) ) as $rj
  | {success:true, day:$day, entries:($e|reverse), alerts:$al, refused:($rj|reverse)}')"
[[ -n "$body" ]] || fail 500 "Falha ao montar o log de acessos" "build_fail"
emit_json 200 OK
printf '%s\n' "$body"
