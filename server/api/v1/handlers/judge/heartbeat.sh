# POST /judge/heartbeat   (Bearer mojw_<token>)
# Pulso do worker: atualiza last_seen+state e, se o worker está LIVRE, reivindica
# 1 job da fila (por prioridade + capacidade + tem-o-problema) e o devolve. É o
# ESCALONADOR: a atribuição acontece aqui, sem loop nem poll-storm.
# body: {host, state:"free"|"busy", inv_hash}
# resp: {success, assigned: <job>|null, reregister: bool}
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

# worker desconhecido (registro expirou) -> pede re-registro
if ! reg_touch_state "$host" "$state"; then
  ok_json '{assigned:null, reregister:true}'
  exit 0
fi

# manutenção barata e auto-throttled (promove famintos, requeue de mortos)
q_promote_starved
q_reconcile

# inventário mudou? pede re-registro
stored_hash="$(jq -r '.inv_hash // empty' "$REGISTRYDIR/$host.json" 2>/dev/null)"
reregister=false
[[ -n "$inv_hash" && "$inv_hash" != "$stored_hash" ]] && reregister=true

assigned=null
update=null
if [[ "$state" == free ]]; then
  # 1) atualização de repositório pendente tem precedência (rara; um host basta no NFS)
  upd="$(upd_claim "$host")"
  if [[ -n "$upd" ]] && jq -e . >/dev/null 2>&1 <<<"$upd"; then
    update="$upd"
    reg_touch_state "$host" busy
  else
    # 2) senão, reivindica 1 job da fila de prioridade
    cap="$(jq -r '.capability // "pos"' "$REGISTRYDIR/$host.json" 2>/dev/null)"
    probs="$(jq -c '.problems // {}' "$REGISTRYDIR/$host.json" 2>/dev/null)"
    job="$(q_claim "$host" "$cap" "$probs")"
    if [[ -n "$job" ]] && jq -e . >/dev/null 2>&1 <<<"$job"; then
      assigned="$job"
      reg_touch_state "$host" busy   # marca ocupado já (evita corrida no próximo beat)
    fi
  fi
fi

emit_json 200 OK
jq -cn --argjson a "$assigned" --argjson u "$update" --argjson rr "$reregister" \
  '{success:true, assigned:$a, update:$u, reregister:$rr}'
