# GET/POST /ops/judge-config   (Bearer, admin)
# CONFIG FINA por juiz (estado desejado; o heartbeat entrega ao agente quando muda):
#   GET  [?host=<h>]                       -> {configs:{<host>:{partition,reserve,disabled,...}}}
#   POST {host, partition?, reserve?, disabled?} -> grava/mescla a entrada do host
#     partition: off | numa | cpus:<X>   (particiona a máquina em slots c/ pinning)
#     reserve:   int >= 0                (cpus iniciais fora dos slots, p/ SO/agente)
#     disabled:  bool                    (drena e para de receber trabalho)
# Config vive em contests/treino/var/judges-config.json (NÃO no registry — o register do
# agente sobrescreve o registry inteiro). CLI: `moj judges config <host> …`; web: aba Máquinas.
require_admin
source "$_DIR/../../judge-gw/sched-lib.sh"   # valid_hostname

JCONF="${JUDGES_CONFIG_FILE:-$CONTESTSDIR/treino/var/judges-config.json}"

if [[ "$REQUEST_METHOD" == GET ]]; then
  h="$(param host)"
  all="$(jq -c . "$JCONF" 2>/dev/null)"; [[ -n "$all" ]] || all='{}'
  emit_json 200 OK
  if [[ -n "$h" ]]; then
    jq -cn --argjson all "$all" --arg h "$h" '{success:true, configs:{($h): ($all[$h] // {partition:"off",reserve:0,disabled:false})}}'
  else
    jq -cn --argjson all "$all" '{success:true, configs:$all}'
  fi
  exit 0
fi

require_method POST
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
host="$(jq -r '.host // empty' <<<"$body")"
valid_hostname "$host" || fail 400 "Invalid host" "host_invalid"

partition="$(jq -r '.partition // empty' <<<"$body")"
if [[ -n "$partition" && ! "$partition" =~ ^(off|numa|cpus:[1-9][0-9]*)$ ]]; then
  fail 400 "partition inválida (off | numa | cpus:<X>)" "partition_invalid"
fi
reserve="$(jq -r '.reserve // empty' <<<"$body")"
if [[ -n "$reserve" && ! "$reserve" =~ ^[0-9]+$ ]]; then
  fail 400 "reserve inválido (int >= 0)" "reserve_invalid"
fi
disabled="$(jq -r 'if has("disabled") then (.disabled|tostring) else "" end' <<<"$body")"
[[ -z "$disabled" || "$disabled" == true || "$disabled" == false ]] || fail 400 "disabled inválido (bool)" "disabled_invalid"
[[ -n "$partition$reserve$disabled" ]] || fail 400 "nada a alterar (partition/reserve/disabled)" "empty_change"

mkdir -p "$(dirname "$JCONF")" 2>/dev/null
lk="$JCONF.lock"
(
  flock 9
  cur="$(jq -c . "$JCONF" 2>/dev/null)"; [[ -n "$cur" ]] || cur='{}'
  jq -c --arg h "$host" --arg p "$partition" --arg r "$reserve" --arg d "$disabled" \
     --arg by "$SESSION_LOGIN" --argjson now "$EPOCHSECONDS" '
    .[$h] = ((.[$h] // {partition:"off", reserve:0, disabled:false})
      + (if $p != "" then {partition:$p} else {} end)
      + (if $r != "" then {reserve:($r|tonumber)} else {} end)
      + (if $d != "" then {disabled:($d == "true")} else {} end)
      + {updated_at:$now, by:$by})' <<<"$cur" > "$JCONF.tmp" && mv -f "$JCONF.tmp" "$JCONF"
) 9>"$lk"

audit_log "judge-config" "host=$host partition=${partition:-·} reserve=${reserve:-·} disabled=${disabled:-·}"
entry="$(jq -c --arg h "$host" '.[$h]' "$JCONF" 2>/dev/null)"
ok_json '{action:"judge-config", host:$h, config:$c}' --arg h "$host" --argjson c "${entry:-null}"
