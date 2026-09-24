# GET/POST /ops/judge-config   (Bearer, admin)
# CONFIG FINA por juiz (estado desejado; o heartbeat entrega ao agente quando muda):
#   GET  [?host=<h>]                       -> {configs:{<host>:{partition,reserve,disabled,...}}}
#   POST {host, partition?, reserve?, disabled?, parallel_max?} -> grava/FUNDE a entrada do host
#     partition: off | numa | cpus:<X>   (particiona a máquina em slots c/ pinning)
#     reserve:   int >= 0                (cpus iniciais fora dos slots, p/ SO/agente)
#     disabled:  bool                    (drena e para de receber trabalho)
#     parallel_max: int 1..64            (teto de testes ao mesmo tempo por job NESTE juiz; só o
#                                         servidor lê — não entra no cfg_hash nem vai ao agente)
#   POST {host:"*", parallel?:off|auto, cushion?:0..1, share_max?:0..1} -> POLÍTICA GLOBAL de
#     paralelismo (chave "*"): off = todo job com par_max 1 (recomendado em prova); auto = a
#     sobra de slots além do colchão (ceil(total×cushion)) vira testes em paralelo, até
#     share_max×total slots por job. Ver judge-gw/sched-lib.sh (q_claim).
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
mkdir -p "$(dirname "$JCONF")" 2>/dev/null
lk="$JCONF.lock"

# ---- política GLOBAL ("*") ----
if [[ "$host" == "*" ]]; then
  par="$(jq -r '.parallel // empty' <<<"$body")"
  [[ -z "$par" || "$par" =~ ^(off|auto)$ ]] || fail 400 "parallel inválido (off | auto)" "parallel_invalid"
  cus="$(jq -r 'if has("cushion") then (.cushion|tostring) else "" end' <<<"$body")"
  [[ -z "$cus" || "$cus" =~ ^(0|1|0?\.[0-9]+)$ ]] || fail 400 "cushion inválido (0..1)" "cushion_invalid"
  shr="$(jq -r 'if has("share_max") then (.share_max|tostring) else "" end' <<<"$body")"
  [[ -z "$shr" || "$shr" =~ ^(0|1|0?\.[0-9]+)$ ]] || fail 400 "share_max inválido (0..1)" "share_invalid"
  [[ -n "$par$cus$shr" ]] || fail 400 "nada a alterar (parallel/cushion/share_max)" "empty_change"
  (
    flock 9
    cur="$(jq -c . "$JCONF" 2>/dev/null)"; [[ -n "$cur" ]] || cur='{}'
    jq -c --arg p "$par" --arg c "$cus" --arg s "$shr" --arg by "$SESSION_LOGIN" --argjson now "$EPOCHSECONDS" '
      .["*"] = ((.["*"] // {parallel:"off", cushion:0.25, share_max:0.5})
        + (if $p != "" then {parallel:$p} else {} end)
        + (if $c != "" then {cushion:($c|tonumber)} else {} end)
        + (if $s != "" then {share_max:($s|tonumber)} else {} end)
        + {updated_at:$now, by:$by})' <<<"$cur" > "$JCONF.tmp" && mv -f "$JCONF.tmp" "$JCONF"
  ) 9>"$lk"
  audit_log "judge-config" "host=* parallel=${par:-·} cushion=${cus:-·} share_max=${shr:-·}"
  entry="$(jq -c '.["*"]' "$JCONF" 2>/dev/null)"
  ok_json '{action:"judge-config", host:"*", config:$c}' --argjson c "${entry:-null}"
  exit 0
fi
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
pmax="$(jq -r '.parallel_max // empty' <<<"$body")"
if [[ -n "$pmax" && ! ( "$pmax" =~ ^[0-9]+$ && "$pmax" -ge 1 && "$pmax" -le 64 ) ]]; then
  fail 400 "parallel_max inválido (int 1..64)" "parallel_max_invalid"
fi
[[ -n "$partition$reserve$disabled$pmax" ]] || fail 400 "nada a alterar (partition/reserve/disabled/parallel_max)" "empty_change"

(
  flock 9
  cur="$(jq -c . "$JCONF" 2>/dev/null)"; [[ -n "$cur" ]] || cur='{}'
  jq -c --arg h "$host" --arg p "$partition" --arg r "$reserve" --arg d "$disabled" --arg pm "$pmax" \
     --arg by "$SESSION_LOGIN" --argjson now "$EPOCHSECONDS" '
    .[$h] = ((.[$h] // {partition:"off", reserve:0, disabled:false})
      + (if $p != "" then {partition:$p} else {} end)
      + (if $r != "" then {reserve:($r|tonumber)} else {} end)
      + (if $d != "" then {disabled:($d == "true")} else {} end)
      + (if $pm != "" then {parallel_max:($pm|tonumber)} else {} end)
      + {updated_at:$now, by:$by})' <<<"$cur" > "$JCONF.tmp" && mv -f "$JCONF.tmp" "$JCONF"
) 9>"$lk"

audit_log "judge-config" "host=$host partition=${partition:-·} reserve=${reserve:-·} disabled=${disabled:-·} parallel_max=${pmax:-·}"
entry="$(jq -c --arg h "$host" '.[$h]' "$JCONF" 2>/dev/null)"
ok_json '{action:"judge-config", host:$h, config:$c}' --arg h "$host" --argjson c "${entry:-null}"
