# lib/alerts.sh — subsistema de ALERTAS de incidente (a API decide o quê/quando; o bot entrega).
#
# alerts_evaluate() lê os sinais (juízes online, fila, daemon) e aplica uma máquina de estados
# por condição (histerese/debounce/cooldown) gravando MENSAGENS no outbox (run/alerts/outbox/).
# O handler GET /ops/alerts (bot-token) chama alerts_evaluate (throttled por .eval-stamp) e
# DRENA o outbox, devolvendo {items:[{id,text,chats}]} — o bot só envia. Estado por condição em
# run/alerts/cond-<nome>.json. Sem cron: o poll do bot é o relógio.

: "${RUNDIR:=/home/ribas/moj/run}"
: "${REGISTRYDIR:=$RUNDIR/registry}"
: "${QUEUEDIR:=$RUNDIR/queue}"
: "${SPOOLDIR:=$RUNDIR/spool/submissions}"
: "${REG_TTL:=30}"
: "${ALERT_EVAL_THROTTLE:=30}"    # s entre avaliações
: "${ALERT_NOJUDGE_AFTER:=120}"   # s de "sem juiz + fila" antes de disparar
: "${ALERT_COOLDOWN:=900}"        # s entre re-lembretes enquanto ruim
: "${ALERT_QUEUE_HI:=50}"         # entra em backlog acima disso
: "${ALERT_QUEUE_LO:=20}"         # sai do backlog abaixo disso
: "${ALERT_DAEMON_AFTER:=60}"     # s de daemon caído antes de disparar

_alert_dir(){ printf '%s/alerts' "$RUNDIR"; }

# --- sinais ---------------------------------------------------------------
_alert_judges_online(){
  local now="$EPOCHSECONDS" n=0 ls
  [[ -d "$REGISTRYDIR" ]] || { echo 0; return; }
  ( set +o noglob; shopt -s nullglob
    for rf in "$REGISTRYDIR"/*.json; do
      ls="$(jq -r '.last_seen // 0' "$rf" 2>/dev/null)"; [[ "$ls" =~ ^[0-9]+$ ]] || ls=0
      (( ls >= now - REG_TTL )) && ((n++))
    done; echo "$n" )
}
_alert_work_pending(){   # submissões esperando: spool bruto + bandas da fila pull
  local sp=0 bq=0
  [[ -d "$SPOOLDIR" ]] && sp="$(find "$SPOOLDIR" -maxdepth 1 -type f ! -name '.*' 2>/dev/null | wc -l)"
  [[ -d "$QUEUEDIR" ]] && bq="$(find "$QUEUEDIR" -mindepth 2 -name '*.json' 2>/dev/null | wc -l)"
  echo $(( sp + bq ))
}
_alert_daemon_up(){ daemon_judged_alive && echo 1 || echo 0; }   # lib/common.sh (pgrep OU heartbeat)

# --- destinos: .admin do treino com Telegram vinculado --------------------
# alerts_admin_chats -> ecoa chat_ids (um por linha) dos .admin com by-login/<login>.
alerts_admin_chats(){
  local login cid
  while IFS= read -r login; do
    [[ "$login" == *.admin ]] || continue
    cid="$(tg_id_of_login treino "$login" 2>/dev/null)"
    [[ -n "$cid" ]] && printf '%s\n' "$cid"
  done < <(list_users treino) | sort -u
}

# --- máquina de estados por condição --------------------------------------
# alert_step <cond> <bad 0|1> <fire_after> <bad_text> <ok_text> — grava no outbox quando
# DISPARA (entrou em ruim há >= fire_after e passou o cooldown) ou RECUPERA.
alert_step(){
  local cond="$1" bad="$2" fire="$3" btxt="$4" otxt="$5"
  local d; d="$(_alert_dir)"; mkdir -p "$d/outbox"
  local f="$d/cond-$cond.json" now="$EPOCHSECONDS" st since lastn
  if [[ -f "$f" ]]; then
    st="$(jq -r '.state//"ok"' "$f" 2>/dev/null)"; since="$(jq -r '.since//0' "$f" 2>/dev/null)"; lastn="$(jq -r '.last_notified//0' "$f" 2>/dev/null)"
  else st=ok; since=0; lastn=0; fi
  [[ "$since" =~ ^[0-9]+$ ]] || since=0; [[ "$lastn" =~ ^[0-9]+$ ]] || lastn=0
  local emit=""
  if (( bad )); then
    [[ "$st" == bad ]] || { st=bad; since=$now; lastn=0; }
    if (( now - since >= fire )) && { (( lastn == 0 )) || (( now - lastn >= ALERT_COOLDOWN )); }; then
      emit="$btxt"; lastn=$now
    fi
  else
    [[ "$st" == bad && "$lastn" -gt 0 ]] && emit="$otxt"
    st=ok; since=$now; lastn=0
  fi
  jq -cn --arg s "$st" --argjson si "$since" --argjson ln "$lastn" \
     '{state:$s, since:$si, last_notified:$ln}' > "$f.tmp" 2>/dev/null && mv -f "$f.tmp" "$f"
  if [[ -n "$emit" ]]; then
    ( umask 077; printf '%s' "$emit" > "$d/outbox/$now-$cond-$$.txt" )
  fi
}

# --- avaliação (throttled) ------------------------------------------------
alerts_evaluate(){
  local d; d="$(_alert_dir)"; mkdir -p "$d/outbox"
  local stamp="$d/.eval-stamp"
  if [[ -f "$stamp" ]]; then
    local age=$(( EPOCHSECONDS - $(stat -c %Y "$stamp" 2>/dev/null || echo 0) ))
    (( age < ALERT_EVAL_THROTTLE )) && return 0
  fi
  : > "$stamp"

  local online pending daemonup
  online="$(_alert_judges_online)"; pending="$(_alert_work_pending)"; daemonup="$(_alert_daemon_up)"

  # no_judges: online==0 && pending>0
  local bad=0; (( online == 0 && pending > 0 )) && bad=1
  alert_step no_judges "$bad" "$ALERT_NOJUDGE_AFTER" \
    "⚠️ <b>MOJ</b>: nenhum juiz online e há <b>$pending</b> submissão(ões) na fila." \
    "✅ <b>MOJ</b>: juiz(es) de volta — a fila está sendo processada."

  # queue_backlog: histerese HI/LO (bad enquanto acima; sai abaixo do LO)
  local qprev qbad=0
  qprev="$(jq -r '.state//"ok"' "$d/cond-queue_backlog.json" 2>/dev/null)"
  if [[ "$qprev" == bad ]]; then (( pending > ALERT_QUEUE_LO )) && qbad=1
  else (( pending > ALERT_QUEUE_HI )) && qbad=1; fi
  alert_step queue_backlog "$qbad" 600 \
    "⚠️ <b>MOJ</b>: fila grande — <b>$pending</b> submissões pendentes (limiar $ALERT_QUEUE_HI)." \
    "✅ <b>MOJ</b>: fila normalizou (<b>$pending</b> pendentes)."

  # daemon_judged: caído
  bad=0; (( daemonup == 0 )) && bad=1
  alert_step daemon_judged "$bad" "$ALERT_DAEMON_AFTER" \
    "🛑 <b>MOJ</b>: o daemon de julgamento (judged) parece PARADO — submissões não são processadas." \
    "✅ <b>MOJ</b>: daemon de julgamento de volta."
}

# --- claim do outbox ------------------------------------------------------
# alerts_claim -> ecoa um array JSON [{id,text,chats:[...]}] e REMOVE os itens entregues.
alerts_claim(){
  local d; d="$(_alert_dir)"; local ob="$d/outbox"
  [[ -d "$ob" ]] || { echo '[]'; return; }
  local chats_json
  chats_json="$(alerts_admin_chats | jq -R . | jq -cs 'map(tonumber? // .)')"
  ( set +o noglob; shopt -s nullglob
    local first=1; printf '['
    for f in "$ob"/*.txt; do
      local id text; id="${f##*/}"; id="${id%.txt}"; text="$(cat "$f")"
      (( first )) || printf ','; first=0
      jq -cn --arg id "$id" --arg t "$text" --argjson c "$chats_json" '{id:$id, text:$t, chats:$c}'
      rm -f "$f"
    done
    printf ']' )
}
