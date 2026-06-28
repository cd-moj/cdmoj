# GET /contest/admin/audit-log?contest=<id>[&since=&action=&user=&limit=]  (admin DO contest)
# Feed cronológico UNIFICADO de tudo que aconteceu no contest, juntando 3 fontes:
#   - var/admin-audit.log  (ações de admin: epoch\twho\taction\tdetails)            -> kind=admin
#   - var/access.log       (logins: epoch\tlogin\tip\tua_b64)                       -> kind=login
#   - controle/history     (submissões: tempo:login:prob:lang:verdict:sub_epoch:id) -> kind=submit
# Filtros: since (epoch), action/user (substring, case-insensitive), limit (default 500).
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"

since="$(param since)"; [[ "$since" =~ ^[0-9]+$ ]] || since=0
limit="$(param limit)"; [[ "$limit" =~ ^[0-9]+$ ]] || limit=500
(( limit > 5000 )) && limit=5000
action="$(param action)"; user="$(param user)"
SRC_MAX=20000   # teto de linhas lidas por fonte (limita memória; feed recente)

cdir="$CONTESTSDIR/$contest"
read_tail() { [[ -f "$1" ]] && tail -n "$SRC_MAX" "$1" 2>/dev/null || true; }

admin_json="$(read_tail "$cdir/var/admin-audit.log" | jq -R -cs '
  split("\n") | map(select(length>0) | split("\t")
    | { time:(.[0]|tonumber? // 0), who:(.[1]//"?"), kind:"admin", action:(.[2]//""), details:(.[3]//"") })')"
access_json="$(read_tail "$cdir/var/access.log" | jq -R -cs '
  split("\n") | map(select(length>0) | split("\t")
    | { time:(.[0]|tonumber? // 0), who:(.[1]//"?"), kind:"login", action:"login",
        details:("\(.[2]//"") · \((.[3]//"")|@base64d)") })')"
hist_json="$(read_tail "$cdir/controle/history" | jq -R -cs '
  split("\n") | map(select(length>0) | split(":") | select(length>=6)
    | { time:(.[-2]|tonumber? // 0), who:(.[1]//"?"), kind:"submit",
        action:(.[4:-2]|join(":")), details:("\(.[2]//"") (\(.[3]//"")) #\(.[-1]//"")") })')"

[[ -n "$admin_json"  ]] || admin_json='[]'
[[ -n "$access_json" ]] || access_json='[]'
[[ -n "$hist_json"   ]] || hist_json='[]'

emit_json 200 OK
jq -cn --argjson a "$admin_json" --argjson b "$access_json" --argjson h "$hist_json" \
  --argjson since "$since" --arg act "$action" --arg usr "$user" --argjson lim "$limit" '
  ($a + $b + $h)
  | map(select(.time >= $since))
  | (if $act=="" then . else map(select((.action//"")|ascii_downcase|contains($act|ascii_downcase))) end)
  | (if $usr=="" then . else map(select((.who//"")|ascii_downcase|contains($usr|ascii_downcase))) end)
  | sort_by(-.time) | .[:$lim]
  | {success:true, count:length, events:.}'
