# GET /treino/admin/judges  (.admin) -> juízes do modelo PULL (registro + heartbeat).
# Lê $REGISTRYDIR/<host>.json (capacidade + state + last_seen) — fonte da verdade atual,
# modelo pull, sem master legado. Mantém a forma {machines:[...]} esperada pelo painel.
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"
: "${RUNDIR:=/home/ribas/moj/run}"; : "${REGISTRYDIR:=$RUNDIR/registry}"; : "${REG_TTL:=30}"
: "${TL_STORE_DIR:=$RUNDIR/tl}"
: "${ASSIGNEDDIR:=$RUNDIR/assigned}"; : "${UPDATESDIR:=$RUNDIR/updates}"; : "${CMDDIR:=$RUNDIR/commands}"
JCONF="${JUDGES_CONFIG_FILE:-$CONTESTSDIR/treino/var/judges-config.json}"   # config fina por juiz
now="$EPOCHSECONDS"

set +o noglob
# resumo de TIME-LIMITS por host (do store): nº de problemas calibrados + linguagens com TL.
tlsum="$(find "$TL_STORE_DIR" -maxdepth 1 -name '*.json' 2>/dev/null | while IFS= read -r tf; do
    jq -c '(.hosts // {}) | to_entries[] | {host:.key, langs:((.value.tl//{})|keys|map(select(.!="default")))}' "$tf" 2>/dev/null
  done | jq -s -c 'group_by(.host) | map({key:.[0].host,
        value:{calibrated:length, langs:(map(.langs)|add|unique|sort)}}) | from_entries')"
[[ -n "$tlsum" ]] || tlsum='{}'

total=0; online_count=0; busy_any=false
ms=()
while IFS= read -r rf; do
  ((total++)); j="$(cat "$rf" 2>/dev/null)"; [[ -n "$j" ]] || continue
  ls="$(jq -r '.last_seen // 0' <<<"$j" 2>/dev/null)"; [[ "$ls" =~ ^[0-9]+$ ]] || ls=0
  on=false; (( ls >= now - REG_TTL )) && { on=true; ((online_count++)); }
  bz=false; [[ "$(jq -r '.state // "free"' <<<"$j" 2>/dev/null)" == busy ]] && { bz=true; [[ "$on" == true ]] && busy_any=true; }
  host="$(jq -r '.host // empty' <<<"$j")"
  # o que a máquina roda AGORA: submissão (run/assigned) tem precedência; senão calibração/index
  # (run/updates/inprogress, ramifica .kind); senão, se busy sem marcador = calibração DIRECIONADA já
  # reivindicada (cmd_claim apaga o arquivo -> não dá p/ nomear o problema). queued_calibrate = alvos
  # direcionados AINDA na fila do host.
  # "current" só faz sentido p/ máquina ONLINE (marcador de claim de worker morto é reconciliado, mas
  # pode ficar órfão até o TTL — não pintar job fantasma numa máquina offline).
  # multi-slot: TODOS os jobs correntes (assigned/<host>/* + updates in-progress), não só o 1º
  cur='null'; curs='[]'
  if [[ "$on" == true ]]; then
    curs="$(find "$ASSIGNEDDIR/$host" -maxdepth 1 -name '*.json' -exec cat {} + 2>/dev/null \
      | jq -sc 'map({kind:"submission", problem_id:(.problem_id//.id//""), login:(.login//""), contest:(.contest//""), lang:(.lang//""), since:(.assigned_at//null)})' 2>/dev/null)"
    [[ -n "$curs" ]] || curs='[]'
    upf="$(find "$UPDATESDIR/inprogress/$host" -maxdepth 1 -name '*.json' -exec cat {} + 2>/dev/null \
      | jq -sc 'map({kind:(.kind//"update"), problem_id:(.target//""), by:(.requested_by//""), since:(.claimed_at//null)})' 2>/dev/null)"
    [[ -n "$upf" && "$upf" != '[]' ]] && curs="$(jq -c --argjson u "$upf" '. + $u' <<<"$curs" 2>/dev/null)"
    if [[ "$curs" == '[]' && "$bz" == true ]]; then curs='[{"kind":"unknown_busy"}]'; fi
    jq -e 'type=="array"' >/dev/null 2>&1 <<<"$curs" || curs='[]'
    cur="$(jq -c '.[0] // null' <<<"$curs" 2>/dev/null)"   # compat: 1º job no campo antigo
  fi
  # calibrações DIRECIONADAS na fila do host — só action=="calibrate" (a pasta também tem clearcache).
  qcal="$(find "$CMDDIR/$host" -maxdepth 1 -name '*.json' -exec cat {} + 2>/dev/null | jq -s '[.[]|select(.action=="calibrate")]|length' 2>/dev/null)"; qcal="${qcal//[^0-9]/}"; qcal="${qcal:-0}"
  jcfg="$(jq -c --arg h "$host" '.[$h] // null' "$JCONF" 2>/dev/null)"; [[ -n "$jcfg" ]] || jcfg='null'
  ms+=("$(jq -c --argjson on "$on" --argjson bz "$bz" --argjson tl "$tlsum" --argjson cur "$cur" \
          --argjson curs "$curs" --argjson qcal "$qcal" --argjson jcfg "$jcfg" '{
      host:.host, port:null, online:$on, busy:$bz, last_seen:(.last_seen//0),
      langs:(.langs // []), cage_root:(.cage_root // null),
      cache:{problems:(.problems_count // ((.problems//{})|length)), bytes:(.cache_bytes // 0)},
      tl:($tl[.host] // {calibrated:0, langs:[]}),
      current:$cur, current_jobs:$curs, queued_calibrate:$qcal,
      slots:{free:(.free_slots // null), total:(.total_slots // 1)},
      partition:(.partition // "off"), topology:(.topology // []),
      config:$jcfg,
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
