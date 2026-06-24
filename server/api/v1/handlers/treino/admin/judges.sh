# GET /treino/admin/judges  (.admin) -> juízes do modelo PULL (registro + heartbeat).
# Lê $REGISTRYDIR/<host>.json (capacidade + state + last_seen) — fonte da verdade atual,
# sem o master legado :27000. Mantém a forma {machines:[...]} esperada pelo painel.
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"
: "${RUNDIR:=/home/ribas/moj/run}"; : "${REGISTRYDIR:=$RUNDIR/registry}"; : "${REG_TTL:=30}"
now="$EPOCHSECONDS"

set +o noglob
total=0; online_count=0; busy_any=false
ms=()
while IFS= read -r rf; do
  ((total++)); j="$(cat "$rf" 2>/dev/null)"; [[ -n "$j" ]] || continue
  ls="$(jq -r '.last_seen // 0' <<<"$j" 2>/dev/null)"; [[ "$ls" =~ ^[0-9]+$ ]] || ls=0
  on=false; (( ls >= now - REG_TTL )) && { on=true; ((online_count++)); }
  bz=false; [[ "$(jq -r '.state // "free"' <<<"$j" 2>/dev/null)" == busy ]] && { bz=true; [[ "$on" == true ]] && busy_any=true; }
  ms+=("$(jq -c --argjson on "$on" --argjson bz "$bz" '{
      host:.host, port:null, online:$on, busy:$bz, last_seen:(.last_seen//0),
      report:{hostname:.host, arch:.arch, cpu:((.cpu // "")|tostring), memory:.mem_kb,
              gpu:.gpu, problems:(.problems_count // 0)} }' <<<"$j" 2>/dev/null)")
done < <(find "$REGISTRYDIR" -maxdepth 1 -name '*.json' 2>/dev/null)
machines='[]'; ((${#ms[@]})) && machines="$(printf '%s\n' "${ms[@]}" | jq -cs 'sort_by(.online|not)')"
online=false; (( online_count > 0 )) && online=true

ok_json '{online:$on, busy:$busy, master:null, master_host:"pull", master_port:null, model:"pull",
          has_machine_list:true, machines:$machines, machines_count:$tc, machines_online:$oc,
          configured_workers:[], configured_count:0}' \
  --argjson on "$online" --argjson busy "$busy_any" --argjson machines "$machines" \
  --argjson tc "$total" --argjson oc "$online_count"
