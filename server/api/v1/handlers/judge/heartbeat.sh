# POST /judge/heartbeat   (Bearer mojw_<token>)
# Pulso do worker: atualiza last_seen+state e, se o worker tem SLOT livre, reivindica
# trabalho da fila (por prioridade + capacidade + tem-o-problema + LARGURA) e devolve. É o
# ESCALONADOR: a atribuição acontece aqui, sem loop nem poll-storm.
# body: {host, state:"free"|"busy", inv_hash, free_slots?, total_slots?, cfg_hash?,
#        status?:"ok"|"draining"|"disabled", slot_cpus?, max_free_group?}
#   (agente antigo não manda slots: free_slots = state==free ? 1 : 0; status distingue
#    "drenando/desabilitado" de "rodando job" — fim do unknown_busy indecifrável;
#    slot_cpus = cpus do MENOR slot (1 em produção) e max_free_group = maior nº de slots livres
#    num nó NUMA — sem slot_cpus o juiz é LEGADO: só jobs k=1, sem campos de largura no job)
# resp: {success, assigned:[<job>…]|<job>|null, update, command, reregister,
#        config?:{partition,reserve,disabled,cfg_hash}, holding?:true}
#   command URGENTE (action kill|restart, de /ops/judge-reset) é entregue MESMO com o juiz
#   ocupado/desabilitado — canal de recuperação sem SSH.
#   assigned é ARRAY (lote de até free_slots SLOTS — um job de CPUNEEDED=k ocupa k_slots; cada
#   job leva {test_cpus, same_numa, slots, par_max, par_cap}); p/ agente ANTIGO também aceita o
#   1º como escalar (o agente novo trata os dois). config só vem quando o cfg_hash do
#   agente difere do vigente (config por juiz de contests/treino/var/judges-config.json,
#   editada por POST /ops/judge-config — 'moj judges config' / aba Máquinas).
#   holding:true = este juiz está SEGURADO p/ um job largo (run/hold/<host>.json): não recebe
#   jobs/updates novos até ter k_slots livres; comandos do admin passam. Ver sched-lib.sh.
require_method POST
require_worker
source "$_DIR/../../judge-gw/sched-lib.sh"

body="$(read_body)"
# dieta 2026-08-30: eram 8 jq re-parseando o mesmo corpo A CADA BEAT de CADA juiz —
# UMA extração (validação inclusa: JSON ruim quebra o próprio jq; campos sem \x01)
_hb="$(jq -j '[ (.host // ""), (.state // "free"), (.inv_hash // ""),
                ((.free_slots // "") | tostring), ((.total_slots // 1) | tostring),
                (.cfg_hash // ""), (.status // ""),
                ((.slot_cpus // "") | tostring), ((.max_free_group // "") | tostring) ] | join("\u0001")' <<<"$body" 2>/dev/null)" \
  || fail 400 "Invalid JSON body" "bad_json"
IFS=$'\x01' read -r host state inv_hash free_slots total_slots agent_cfg_hash agent_status slot_cpus mfg <<<"$_hb"
valid_hostname "$host" || fail 400 "Invalid host" "host_invalid"
[[ "$state" == free || "$state" == busy ]] || state=free
batch=true   # agente novo (manda free_slots) recebe assigned como ARRAY; antigo, escalar
[[ "$free_slots" =~ ^[0-9]+$ ]] || { batch=false; free_slots=0; [[ "$state" == free ]] && free_slots=1; }
[[ "$total_slots" =~ ^[0-9]+$ ]] || total_slots=1
[[ "$agent_status" =~ ^(ok|draining|disabled)$ ]] || agent_status=""
[[ "$slot_cpus" =~ ^[0-9]+$ && "$slot_cpus" -ge 1 ]] || slot_cpus=""   # vazio = juiz LEGADO
[[ "$mfg" =~ ^[0-9]+$ ]] || mfg=""

# worker desconhecido (registro expirou) -> pede re-registro
if ! reg_touch_state "$host" "$state"; then
  ok_json '{assigned:null, reregister:true}'
  exit 0
fi
# status honesto do agente novo (UI/CLI mostram "drenando" em vez de unknown_busy)
[[ -n "$agent_status" ]] && reg_set "$host" '.status=$s' --arg s "$agent_status" 2>/dev/null || true

# manutenção barata e auto-throttled (promove famintos, requeue de jobs E calibrações de mortos,
# holds p/ jobs largos famintos, Judge Error p/ job largo sem juiz capaz)
q_promote_starved
q_reconcile
upd_reconcile
hold_sweep
infeasible_sweep
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

# LARGURA / paralelismo: o que o claim precisa saber do juiz (registro + beat + política)
IFS=$'\x01' read -r pol cushion share pmax < <(sched_policy "$host")
memkb="$(jq -r '.mem_kb // ""' "$REGISTRYDIR/$host.json" 2>/dev/null)"
export QC_SLOT_CPUS="${slot_cpus:-0}" QC_MAX_FREE_GROUP="$mfg" QC_TOTAL_SLOTS="$total_slots" QC_MEM_KB="$memkb" \
       QC_POLICY="$pol" QC_CUSHION="$cushion" QC_SHARE_MAX="$share" QC_PARALLEL_MAX="$pmax" QC_FREE="$free_slots"

assigned=null
update=null
command=null
claimed=0        # SLOTS reivindicados neste beat (job largo conta k_slots × grupos)
holding=false
JOBSF="$(mktemp)"
# comando URGENTE (kill/restart) FURA o gate de ocupado/desabilitado: um juiz wedgado com os
# slots presos nunca teria free_slots>0 — e era exatamente ele que precisava receber o reset.
ucmd="$(cmd_claim_urgent "$host" 2>/dev/null)"
if [[ -n "$ucmd" ]] && jq -e . >/dev/null 2>&1 <<<"$ucmd"; then
  command="$ucmd"
fi
if [[ "$command" == null && "$disabled" != true ]] && (( free_slots > 0 )); then
  # HOLD: juiz segurado p/ um job largo — entrega o segurado assim que cabe; senão nada novo
  hold="$(hold_get "$host")"
  hold_ks=0
  if [[ -n "$hold" && -n "$slot_cpus" ]]; then
    hold_ks="$(jq -r '.k_slots // 1' <<<"$hold")"; hold_nm="$(jq -r '.numa // false' <<<"$hold")"
    [[ "$hold_ks" =~ ^[0-9]+$ ]] || hold_ks=1
    if (( free_slots >= hold_ks )) && { [[ "$hold_nm" != true ]] || [[ -n "$mfg" && "$mfg" -ge "$hold_ks" ]]; }; then
      hj="$(q_claim_id "$host" "$(jq -r '.job' <<<"$hold")" 2>/dev/null)"
      hold_clear "$host"
      if [[ -n "$hj" ]] && jq -e . >/dev/null 2>&1 <<<"$hj"; then
        printf '%s\n' "$hj" >> "$JOBSF"; claimed=$hold_ks
      else hold_ks=0; fi
    else
      holding=true
    fi
  elif [[ -n "$hold" ]]; then hold_clear "$host"; fi   # hold num juiz legado não faz sentido
  # 0) comando por-host do admin (ex.: limpar cache) tem precedência e é exclusivo do beat
  #    (passa MESMO com hold: é o canal do admin)
  if [[ "$holding" == true ]]; then
    cmd="$(cmd_claim "$host" 2>/dev/null)"
    if [[ -n "$cmd" ]] && jq -e . >/dev/null 2>&1 <<<"$cmd"; then
      command="$cmd"; claimed="$(jq -r '.slots // 1' <<<"$cmd")"; [[ "$claimed" =~ ^[0-9]+$ ]] || claimed=1
    fi
  elif cmd="$(cmd_claim "$host" 2>/dev/null)"; [[ -n "$cmd" ]] && jq -e . >/dev/null 2>&1 <<<"$cmd"; then
    command="$cmd"; claimed="$(jq -r '.slots // 1' <<<"$cmd")"; [[ "$claimed" =~ ^[0-9]+$ ]] || claimed=1
  # 1) atualização/calibração pendente tem precedência sobre jobs (ocupa k_slots)
  elif (( claimed == 0 )) && upd="$(upd_claim "$host")"; [[ -n "$upd" ]] && jq -e . >/dev/null 2>&1 <<<"$upd"; then
    update="$upd"; claimed="$(jq -r '.slots // 1' <<<"$upd")"; [[ "$claimed" =~ ^[0-9]+$ ]] || claimed=1
  else
    # 2) LOTE: reivindica até free_slots SLOTS da fila de prioridade (o segurado, se houve, já
    #    está no arquivo e conta no `claimed`).
    # Os jobs agregam por ARQUIVO (1/linha + jq -s), NUNCA por --argjson: job com fonte
    # grande (base64 >128 KiB) estourava o teto por-argumento do jq, o beat saía 200 com
    # corpo VAZIO e o job — que o q_claim JÁ tinha movido p/ assigned/ — quicava
    # assigned→TTL→fila p/ sempre (4ª instância da classe ARG_MAX, pega pela prova de
    # fogo do incidente 2026-08-19: fonte de 200 KiB julgável de ponta a ponta).
    cap="$(jq -r '.capability // "pos"' "$REGISTRYDIR/$host.json" 2>/dev/null)"
    probs="$(jq -c '.problems // {}' "$REGISTRYDIR/$host.json" 2>/dev/null)"
    langs="$(jq -c '.langs // []' "$REGISTRYDIR/$host.json" 2>/dev/null)"
    left_for_claim=$(( free_slots - claimed )); (( left_for_claim < 0 )) && left_for_claim=0
    # claim em LOTE (2026-08-30): UMA varredura colhe até free_slots — o laço antigo
    # re-varria a fila (e o prefixo preso por pool) p/ CADA slot; um job por linha
    if (( left_for_claim > 0 )); then
      q_claim "$host" "$cap" "$probs" "$langs" "$left_for_claim" 2>/dev/null \
        | while IFS= read -r job; do
            [[ -n "$job" ]] || continue
            jq -e . >/dev/null 2>&1 <<<"$job" && printf '%s\n' "$job"
          done >> "$JOBSF"
    fi
    claimed="$(jq -s 'map(.slots // 1) | add // 0' "$JOBSF" 2>/dev/null)"; claimed="${claimed//[^0-9]/}"; claimed="${claimed:-0}"
  fi
fi
if [[ -s "$JOBSF" ]]; then
  assigned="$(jq -cs 'if $batch then . else .[0] end' --argjson batch "$batch" "$JOBSF")"
  [[ -n "$assigned" ]] || assigned=null
fi
rm -f "$JOBSF"

# estado no registro: busy quando não sobra slot; guarda free/total/slot_cpus/max_free_group p/ os painéis
left=$(( free_slots - claimed )); (( left < 0 )) && left=0
st=free; { (( left == 0 )) || [[ "$disabled" == true ]]; } && st=busy
reg_touch_state "$host" "$st"
reg_set "$host" '.free_slots=$f | .total_slots=$t
   | (if $sc == "" then . else .slot_cpus=($sc|tonumber) end)
   | (if $mfg == "" then . else .max_free_group=($mfg|tonumber) end)' \
  --argjson f "$left" --argjson t "$total_slots" --arg sc "$slot_cpus" --arg mfg "$mfg" 2>/dev/null || true

# assigned entra por --slurpfile (ok_json_slurp): pode passar de 128 KiB e o corpo é
# montado ANTES do cabeçalho — falha do jq vira 500 build_fail, nunca 200 vazio.
ok_json_slurp '{assigned:$a[0], update:$u, reregister:$rr, command:$cmd}
   + (if $cfg == null then {} else {config:$cfg} end)
   + (if $hold then {holding:true} else {} end)' \
  a "$assigned" \
  --argjson u "$update" --argjson rr "$reregister" \
  --argjson cmd "$command" --argjson cfg "$config" --argjson hold "$holding"
