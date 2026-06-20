# GET /treino/admin/judges  (.admin) -> estado do juiz via :27000 (JUDGE_HOST/JUDGE_PORT)
# Usa o comando agregado `listmachines` (master novo, consulta cada worker). Se o master
# ainda não tiver esse comando, cai para reportmachine/islocked + lista configurada local.
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"
host="${JUDGE_HOST:-localhost}"; port="${JUDGE_PORT:-27000}"

machines='[]'; mcount=0; monline=0; have_list=0
lm="$(printf '{ "cmd": "listmachines" }\n' | timeout 20 nc -w 15 "$host" "$port" 2>/dev/null)"
if [[ -n "$lm" ]] && jq -e '.machines' >/dev/null 2>&1 <<<"$lm"; then
  machines="$(jq -c '.machines' <<<"$lm")"
  mcount="$(jq -r '.count // 0' <<<"$lm")"
  monline="$(jq -r '.online_count // 0' <<<"$lm")"
  have_list=1
fi

# master report (confirma que o :27000 está no ar)
report="$(printf '{ "cmd": "reportmachine" }\n' | timeout 6 nc -w 4 "$host" "$port" 2>/dev/null)"
locked="$(printf '{ "cmd": "islocked" }\n'      | timeout 6 nc -w 4 "$host" "$port" 2>/dev/null | jq -r '.status // empty' 2>/dev/null)"
online=false; master=null
if [[ -n "$report" ]] && jq -e 'has("hostname")' >/dev/null 2>&1 <<<"$report"; then online=true; master="$report"; fi
busy=false; [[ "$locked" == "true" ]] && busy=true

# lista configurada local (fallback quando listmachines não veio)
MOJROOT="${CONTESTSDIR%/contests}"
configured="$(grep -E '^[[:space:]]*MOJPORTS\+=\(' "$MOJROOT/judge/sistema_escalonador/escalonador.sh" 2>/dev/null \
  | sed -E 's/.*\(([^)]+)\).*/\1/' | tr ' ' '\n' | grep -v '^$' | jq -R . | jq -cs '.' 2>/dev/null)"
[[ -z "$configured" || "$configured" == "null" ]] && configured='[]'

ok_json '{online:$on, busy:$busy, master:$m, master_host:$h, master_port:$p,
          has_machine_list:($hl==1), machines:$machines, machines_count:$mc, machines_online:$mo,
          configured_workers:$cfg, configured_count:($cfg|length)}' \
  --argjson on "$online" --argjson busy "$busy" --argjson m "$master" \
  --arg h "$host" --argjson p "$port" \
  --argjson hl "$have_list" --argjson machines "$machines" \
  --argjson mc "${mcount:-0}" --argjson mo "${monline:-0}" --argjson cfg "$configured"
