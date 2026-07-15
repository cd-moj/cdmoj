# POST /judge/heartbeat   (Bearer mojw_<token>)
# Pulso do worker: atualiza last_seen+state e, se o worker tem SLOT livre, reivindica
# trabalho da fila (por prioridade + capacidade + tem-o-problema) e devolve. É o
# ESCALONADOR: a atribuição acontece aqui, sem loop nem poll-storm.
# body: {host, state:"free"|"busy", inv_hash, free_slots?, total_slots?, cfg_hash?,
#        status?:"ok"|"draining"|"disabled"}
#   (agente antigo não manda slots: free_slots = state==free ? 1 : 0; status distingue
#    "drenando/desabilitado" de "rodando job" — fim do unknown_busy indecifrável)
# resp: {success, assigned:[<job>…]|<job>|null, update, command, reregister,
#        config?:{partition,reserve,disabled,cfg_hash}}
#   command URGENTE (action kill|restart, de /ops/judge-reset) é entregue MESMO com o juiz
#   ocupado/desabilitado — canal de recuperação sem SSH.
#   assigned é ARRAY (lote de até free_slots jobs); p/ agente ANTIGO também aceita o
#   1º como escalar (o agente novo trata os dois). config só vem quando o cfg_hash do
#   agente difere do vigente (config por juiz de contests/treino/var/judges-config.json,
#   editada por POST /ops/judge-config — 'moj judges config' / aba Máquinas).
require_method POST
require_worker
source "$_DIR/../../judge-gw/sched-lib.sh"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
host="$(jq -r '.host // empty' <<<"$body")"
valid_hostname "$host" || fail 400 "Invalid host" "host_invalid"
state="$(jq -r '.state // "free"' <<<"$body")"
[[ "$state" == free || "$state" == busy ]] || state=free
inv_hash="$(jq -r '.inv_hash // empty' <<<"$body")"
batch=true   # agente novo (manda free_slots) recebe assigned como ARRAY; antigo, escalar
free_slots="$(jq -r '.free_slots // empty' <<<"$body")"
[[ "$free_slots" =~ ^[0-9]+$ ]] || { batch=false; free_slots=0; [[ "$state" == free ]] && free_slots=1; }
total_slots="$(jq -r '.total_slots // 1' <<<"$body")"; [[ "$total_slots" =~ ^[0-9]+$ ]] || total_slots=1
agent_cfg_hash="$(jq -r '.cfg_hash // ""' <<<"$body")"
agent_status="$(jq -r '.status // ""' <<<"$body")"
[[ "$agent_status" =~ ^(ok|draining|disabled)$ ]] || agent_status=""

# worker desconhecido (registro expirou) -> pede re-registro
if ! reg_touch_state "$host" "$state"; then
  ok_json '{assigned:null, reregister:true}'
  exit 0
fi
# status honesto do agente novo (UI/CLI mostram "drenando" em vez de unknown_busy)
[[ -n "$agent_status" ]] && reg_set "$host" '.status=$s' --arg s "$agent_status" 2>/dev/null || true

# manutenção barata e auto-throttled (promove famintos, requeue de jobs E calibrações de mortos)
q_promote_starved
q_reconcile
upd_reconcile
# agente NOVO (manda status) vivo: re-carimba as calibrações em execução dele — calibração longa
# LEGÍTIMA (> UPD_TTL) não é re-enfileirada em duplicidade; o TTL vira proteção só de host morto.
[[ -n "$agent_status" ]] && upd_touch_host "$host"

# inventário mudou? pede re-registro
stored_hash="$(jq -r '.inv_hash // empty' "$REGISTRYDIR/$host.json" 2>/dev/null)"
reregister=false
[[ -n "$inv_hash" && "$inv_hash" != "$stored_hash" ]] && reregister=true

# CONFIG por juiz (estado desejado do admin): entrega quando o hash do agente difere.
# Sem entrada p/ o host, o default é {partition:off,reserve:0,disabled:false} com hash "".
# Fonte única do objeto/hash: judges_config_for (o register entrega o MESMO no boot).
config=null
cfgj="$(judges_config_for "$host")"
srv_hash="$(jq -r '.cfg_hash // ""' <<<"$cfgj")"
disabled="$(jq -r '.disabled // false' <<<"$cfgj")"
[[ "$agent_cfg_hash" != "$srv_hash" ]] && config="$cfgj"

assigned=null
update=null
command=null
claimed=0
# comando URGENTE (kill/restart) FURA o gate de ocupado/desabilitado: um juiz wedgado com os
# slots presos nunca teria free_slots>0 — e era exatamente ele que precisava receber o reset.
ucmd="$(cmd_claim_urgent "$host" 2>/dev/null)"
if [[ -n "$ucmd" ]] && jq -e . >/dev/null 2>&1 <<<"$ucmd"; then
  command="$ucmd"
fi
if [[ "$command" == null && "$disabled" != true ]] && (( free_slots > 0 )); then
  # 0) comando por-host do admin (ex.: limpar cache) tem precedência e é exclusivo do beat
  cmd="$(cmd_claim "$host" 2>/dev/null)"
  if [[ -n "$cmd" ]] && jq -e . >/dev/null 2>&1 <<<"$cmd"; then
    command="$cmd"
  # 1) atualização/calibração pendente tem precedência sobre jobs (ocupa 1 slot)
  elif upd="$(upd_claim "$host")"; [[ -n "$upd" ]] && jq -e . >/dev/null 2>&1 <<<"$upd"; then
    update="$upd"
    claimed=1
  else
    # 2) LOTE: reivindica até free_slots jobs da fila de prioridade
    cap="$(jq -r '.capability // "pos"' "$REGISTRYDIR/$host.json" 2>/dev/null)"
    probs="$(jq -c '.problems // {}' "$REGISTRYDIR/$host.json" 2>/dev/null)"
    langs="$(jq -c '.langs // []' "$REGISTRYDIR/$host.json" 2>/dev/null)"
    assigned='[]'
    while (( claimed < free_slots )); do
      job="$(q_claim "$host" "$cap" "$probs" "$langs")"
      [[ -n "$job" ]] && jq -e . >/dev/null 2>&1 <<<"$job" || break
      assigned="$(jq -c --argjson j "$job" '. + [$j]' <<<"$assigned")"
      claimed=$((claimed+1))
    done
    if [[ "$assigned" == '[]' ]]; then assigned=null
    elif [[ "$batch" != true ]]; then assigned="$(jq -c '.[0]' <<<"$assigned")"   # agente antigo: escalar
    fi
  fi
fi

# estado no registro: busy quando não sobra slot; guarda free/total p/ os painéis
left=$(( free_slots - claimed )); (( left < 0 )) && left=0
st=free; { (( left == 0 )) || [[ "$disabled" == true ]]; } && st=busy
reg_touch_state "$host" "$st"
reg_set "$host" '.free_slots=$f | .total_slots=$t' \
  --argjson f "$left" --argjson t "$total_slots" 2>/dev/null || true

emit_json 200 OK
jq -cn --argjson a "$assigned" --argjson u "$update" --argjson rr "$reregister" \
   --argjson cmd "$command" --argjson cfg "$config" \
  '{success:true, assigned:$a, update:$u, reregister:$rr, command:$cmd}
   + (if $cfg == null then {} else {config:$cfg} end)'
