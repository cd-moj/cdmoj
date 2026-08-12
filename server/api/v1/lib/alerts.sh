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
: "${ALERT_BOT_GONE_AFTER:=300}"  # s sem poll do bot p/ considerá-lo fora (bot.alive)

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

# --- DM dirigida (destino resolvido pelo PRODUTOR) -------------------------
# alert_dm <texto> <chats-um-por-linha> [loud] -> ecoa o id do item enfileirado.
#
# O item `.txt` do alert_step é de INCIDENTE: quem recebe são os .admin, decididos no claim. Uma
# mensagem para UMA pessoa (ex.: convite de time pendente) não cabe nisso — aqui o produtor já
# resolveu o chat_id e ele viaja no próprio item, com `group:false` p/ o bot NÃO copiar no grupo
# de admins. `loud` desliga o disable_notification (lembrete precisa apitar; alerta não).
# Sem destino não enfileira nada (rc≠0): quem chamou usa isso p/ dizer "sem Telegram vinculado".
alert_dm(){
  local text="$1" chats="$2" loud="${3:-}" d cj f id
  [[ -n "$text" ]] || return 1
  cj="$(printf '%s\n' "$chats" | grep -v '^[[:space:]]*$' | jq -R . | jq -cs 'map(tonumber? // .)')"
  [[ -n "$cj" && "$cj" != '[]' ]] || return 1
  d="$(_alert_dir)"; mkdir -p "$d/outbox"
  # UNICIDADE pelo mktemp, nunca por contador de shell: quem chama costuma ser
  # `$(inv_notify …)` — COMMAND SUBSTITUTION, ou seja SUBSHELL —, então um contador voltaria a
  # 1 a cada chamada e duas DMs no mesmo segundo (mesmo epoch, mesmo $$) se sobrescreviam: a
  # segunda pessoa simplesmente não recebia, sem erro nenhum. O nome temporário não termina em
  # .json de propósito (o claim só enxerga *.json ⇒ ninguém lê pela metade).
  f="$(umask 077; mktemp "$d/outbox/$EPOCHSECONDS-dm-XXXXXXXX" 2>/dev/null)" || return 1
  jq -cn --arg t "$text" --argjson c "$cj" \
     --argjson l "$( [[ -n "$loud" ]] && echo true || echo false )" \
     '{text:$t, chats:$c, loud:$l, group:false}' > "$f" 2>/dev/null \
    || { rm -f "$f"; return 1; }
  id="${f##*/}"
  mv -f "$f" "$d/outbox/$id.json" || { rm -f "$f"; return 1; }
  printf '%s' "$id"
}

# alert_group <texto-html> [loud] — mensagem SÓ PARA O GRUPO (relatórios/avisos coletivos):
# chats fica VAZIO e group:true — o bot acrescenta o ALERT_GROUP_CHAT dele como único destino.
# Diferente do .txt de incidente, NINGUÉM recebe DM. Se o bot não tiver ALERT_GROUP_CHAT
# configurado, a mensagem é descartada em silêncio (config do bot é invisível para a API).
# Mesma doutrina de unicidade/parcialidade do alert_dm (mktemp; nome temporário sem .json).
alert_group(){
  local text="$1" loud="${2:-}" d f id
  [[ -n "$text" ]] || return 1
  d="$(_alert_dir)"; mkdir -p "$d/outbox"
  f="$(umask 077; mktemp "$d/outbox/$EPOCHSECONDS-grp-XXXXXXXX" 2>/dev/null)" || return 1
  jq -cn --arg t "$text" \
     --argjson l "$( [[ -n "$loud" ]] && echo true || echo false )" \
     '{text:$t, chats:[], loud:$l, group:true}' > "$f" 2>/dev/null \
    || { rm -f "$f"; return 1; }
  id="${f##*/}"
  mv -f "$f" "$d/outbox/$id.json" || { rm -f "$f"; return 1; }
  printf '%s' "$id"
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

  # (a detecção de "bot fora do ar" NÃO mora aqui de propósito: alerts_evaluate só roda no
  #  poll do bot — com o bot morto ninguém avalia nada. Quem mede a ausência é o handler
  #  ops/alerts, no PRIMEIRO poll da volta, pelo mtime velho do bot.alive.)
}

# --- claim do outbox ------------------------------------------------------
# alerts_claim -> ecoa um array JSON [{id,text,chats:[…],loud,group}] e REMOVE os entregues.
#
# TRÊS tipos de item convivem no outbox:
#   <epoch>-<cond>-<pid>.txt   INCIDENTE — texto puro; destino = os .admin vinculados (resolvidos
#                              AQUI) + o grupo, que o bot acrescenta. É o formato original.
#   <epoch>-dm-<pid>-<n>.json  DM DIRIGIDA (alert_dm) — {text,chats,loud,group:false}.
#   <epoch>-grp-XXXX.json      SÓ GRUPO (alert_group) — {text,chats:[],loud,group:true}; o
#                              único destino é o ALERT_GROUP_CHAT que o bot acrescenta.
# Ordem = nome do arquivo (o prefixo epoch dá FIFO) e TETO de ALERT_CLAIM_MAX por chamada: o bot
# entrega em série e o Telegram corta acima de ~30 msg/s — o resto sai no poll seguinte (~25 s).
# Item ilegível é descartado (rm antes de emitir) p/ não travar a fila para sempre.
alerts_claim(){
  local d; d="$(_alert_dir)"; local ob="$d/outbox"
  [[ -d "$ob" ]] || { echo '[]'; return; }
  local files=() chats_json="" first=1 n=0 f id out
  mapfile -t files < <( set +o noglob; shopt -s nullglob
                        for f in "$ob"/*.txt "$ob"/*.json; do printf '%s\n' "$f"; done | sort )
  printf '['
  for f in "${files[@]}"; do
    (( n >= ${ALERT_CLAIM_MAX:-30} )) && break
    id="${f##*/}"
    if [[ "$f" == *.json ]]; then
      id="${id%.json}"
      # chats vazio SÓ passa com group:true (item "só grupo" do alert_group) — DM sem
      # destino continua sendo descartada.
      out="$(jq -c --arg id "$id" '{id:$id, text:(.text // ""), loud:(.loud == true),
              group:(.group != false), chats:((.chats // []) | map(tonumber? // .))}
             | select((.text != "") and (((.chats | length) > 0) or .group))' "$f" 2>/dev/null)"
    else
      id="${id%.txt}"
      # só resolve os admins se houver item de incidente (varre as contas do treino)
      [[ -n "$chats_json" ]] || chats_json="$(alerts_admin_chats | jq -R . | jq -cs 'map(tonumber? // .)')"
      [[ -n "$chats_json" ]] || chats_json='[]'
      out="$(jq -cn --arg id "$id" --arg t "$(cat "$f")" --argjson c "$chats_json" \
              '{id:$id, text:$t, chats:$c, loud:false, group:true}')"
    fi
    rm -f "$f"
    [[ -n "$out" ]] || continue
    (( first )) || printf ','; first=0
    printf '%s' "$out"; n=$(( n + 1 ))
  done
  printf ']'
}
