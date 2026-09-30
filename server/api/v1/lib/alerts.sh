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
: "${ALERT_STUCK_AFTER:=900}"     # s de job PARADO na fila (com juiz online) p/ contar como preso
: "${ALERT_STUCK_COOLDOWN:=3600}" # s entre lembretes enquanto a fila segue parada (dias parados ≠ spam)

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
  [[ -d "$SPOOLDIR" ]] && sp="$(find "$SPOOLDIR" -type f ! -name '.*' 2>/dev/null | wc -l)"
  [[ -d "$QUEUEDIR" ]] && bq="$(find "$QUEUEDIR" -mindepth 2 -name '*.json' 2>/dev/null | wc -l)"
  echo $(( sp + bq ))
}
_alert_daemon_up(){ daemon_judged_alive && echo 1 || echo 0; }   # lib/common.sh (pgrep OU heartbeat)

# _alert_stuck_jobs -> "n\x01idade_do_mais_velho\x01arquivo_do_mais_velho" dos jobs PARADOS na fila pull
# (há ALERT_STUCK_AFTER ou mais desde o enqueued_at), ou nada. Incidente de 30/09/2026: 10 submissões de
# uma lista paradas por mais de 24 h com os três juízes online, e nenhuma condição antiga (sem juiz / fila
# grande / daemon) as via. A idade vem do sidecar .cmeta (campo enq): o NOME do arquivo não serve, a
# promoção de famintos e o decline o renomeiam com epoch novo. Job sem sidecar ainda não passou por
# nenhum claim e cai no enqueued_at do JSON. Leitura por `read` (sem fork por job: roda a cada avaliação).
_alert_stuck_jobs(){
  [[ -d "$QUEUEDIR" ]] || return 0
  ( set +o noglob; shopt -s nullglob
    local now="$EPOCHSECONDS" n=0 oldest=0 of="" f m enq
    for f in "$QUEUEDIR"/*/*.json; do
      m=""; enq=""
      [[ -s "$f.cmeta" ]] && { IFS= read -r m < "$f.cmeta" || true; }
      [[ "$m" == v2$'\x01'* ]] && IFS=$'\x01' read -r _ _ _ _ _ _ _ _ _ _ enq _ <<<"$m"
      [[ "$enq" =~ ^[0-9]+$ ]] || enq="$(jq -r '.enqueued_at // empty' "$f" 2>/dev/null)"
      [[ "$enq" =~ ^[0-9]+$ ]] || continue
      (( now - enq >= ALERT_STUCK_AFTER )) || continue
      n=$((n+1))
      (( oldest == 0 || enq < oldest )) && { oldest=$enq; of="$f"; }
    done
    (( n > 0 )) && printf '%s\x01%s\x01%s' "$n" "$(( now - oldest ))" "$of"
  )
}
# _alert_stuck_why <jobfile> -> "contest\x01problema\x01motivo provável" (p/ a mensagem): cruza o sidecar
# do job (memória, largura, pool, linguagem) com a capacidade dos juízes VIVOS (uma varredura do registro)
_alert_stuck_why(){
  local f="$1" m="" ver prob need jl hosts k numa par mm memmb enq decl contest why h mk cpus lg
  local rows maxmem=0 maxcpu=0 live=" " langs=" " anyl=0 hh
  contest="$(jq -r '.contest // "?"' "$f" 2>/dev/null)"
  [[ -s "$f.cmeta" ]] && { IFS= read -r m < "$f.cmeta" || true; }
  IFS=$'\x01' read -r ver prob need jl hosts k numa par mm memmb enq decl <<<"$m"
  [[ -n "$prob" ]] || prob="$(jq -r '.problem_id // "?"' "$f" 2>/dev/null)"
  rows="$(find "$REGISTRYDIR" -maxdepth 1 -name '*.json' -exec cat {} + 2>/dev/null \
    | jq -r --argjson now "$EPOCHSECONDS" --argjson ttl "$REG_TTL" '
        select((.last_seen // 0) >= ($now - $ttl))
        | [ .host, ((.mem_kb // 0)|tostring), (((.total_slots // 1) * (.slot_cpus // 1))|tostring),
            ((.langs // []) | map(if . == "py2" or . == "py3" then "py" else . end) | join(" ")) ]
        | join("\u0001")' 2>/dev/null)"
  while IFS=$'\x01' read -r h mk cpus lg; do
    [[ -n "$h" ]] || continue
    live+="$h "; langs+="$lg "
    [[ "$mk" =~ ^[0-9]+$ ]] && (( mk / 1024 - 4096 - 64 > maxmem )) && maxmem=$(( mk / 1024 - 4096 - 64 ))
    [[ "$cpus" =~ ^[0-9]+$ ]] && (( cpus > maxcpu )) && maxcpu=$cpus
  done <<<"$rows"
  case "$jl" in py2|py3) jl=py;; esac
  if [[ -n "$hosts" ]]; then for hh in ${hosts//,/ }; do [[ "$live" == *" $hh "* ]] && anyl=1; done; fi
  if [[ "$memmb" =~ ^[0-9]+$ ]] && (( memmb > 0 && maxmem > 0 && memmb > maxmem )); then
    why="o problema pede MEMLIMITMB=$memmb MB e o maior juiz aceita ~$maxmem MB — corrigir o conf do problema"
  elif [[ -n "$hosts" ]] && (( anyl == 0 )); then
    why="o pool de juízes (${hosts//,/, }) está offline"
  elif [[ "$k" =~ ^[0-9]+$ ]] && (( k > 1 && maxcpu > 0 && k > maxcpu )); then
    why="o problema pede $k CPUs (CPUNEEDED) e o maior juiz tem $maxcpu"
  elif [[ "$k" =~ ^[0-9]+$ ]] && (( k > 1 )); then
    why="largura: o problema pede $k CPUs (CPUNEEDED) e nenhum juiz libera tantos slots juntos"
  elif [[ -n "$jl" && "$langs" != *" $jl "* ]]; then
    why="nenhum juiz online tem a linguagem $jl"
  else
    why="não identificado — ver a Fila no painel do treino"
  fi
  printf '%s\x01%s\x01%s' "$contest" "$prob" "$why"
}
_alert_html(){ local s="$1"; s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"; printf '%s' "$s"; }
_alert_dur(){ local s="$1"; (( s >= 3600 )) && printf '%dh%02dm' $(( s / 3600 )) $(( s % 3600 / 60 )) || printf '%d min' $(( s / 60 )); }

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
    ( umask 077; printf '%s' "$emit" > "$d/outbox/$now-$cond-${BASHPID}.txt" )
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
  # 1 a cada chamada e duas DMs no mesmo segundo (mesmo epoch, mesmo ${BASHPID}) se sobrescreviam: a
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

  # queue_stuck: job PARADO na fila há ALERT_STUCK_AFTER+ com juiz online (sem juiz é o no_judges).
  # Dispara na hora (a espera já está no limiar do job) e relembra no máx. a cada ALERT_STUCK_COOLDOWN.
  local st sn sage sf scontest sprob swhy stxt=""
  st="$(_alert_stuck_jobs)"
  bad=0; [[ -n "$st" ]] && (( online > 0 )) && bad=1
  if (( bad )); then
    IFS=$'\x01' read -r sn sage sf <<<"$st"
    IFS=$'\x01' read -r scontest sprob swhy <<<"$(_alert_stuck_why "$sf")"
    stxt="⏳ <b>MOJ</b>: <b>$sn</b> submissão(ões) parada(s) na fila há mais de $(( ALERT_STUCK_AFTER / 60 )) min com juiz(es) online — a mais antiga: <code>$(_alert_html "$scontest")</code> · <code>$(_alert_html "$sprob")</code>, há $(_alert_dur "$sage"). Motivo provável: $(_alert_html "$swhy")."
  fi
  ALERT_COOLDOWN="$ALERT_STUCK_COOLDOWN" alert_step queue_stuck "$bad" 0 "$stxt" \
    "✅ <b>MOJ</b>: a fila voltou a andar — nenhuma submissão parada."

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
# ENTREGA COM ACK (2026-09-14): item .json sai do outbox p/ inflight/<id>.json em vez de ser
# apagado; o bot confirma com POST /ops/alerts {ack:[{id,ok,error}]} (alerts_ack), que apaga o
# inflight. Sem ack em ALERT_INFLIGHT_TTL (600 s — bot caiu entre o claim e o envio, resposta
# HTTP perdida), o item VOLTA ao outbox e é reentregue. O .txt de incidente segue at-most-once
# (rm no claim): alerta repetido é pior que alerta perdido; relatório perdido é o que doía.
alerts_claim(){
  local d; d="$(_alert_dir)"; local ob="$d/outbox" inf="$d/inflight"
  [[ -d "$ob" ]] || { echo '[]'; return; }
  mkdir -p "$inf" 2>/dev/null
  # Reenfileira o inflight vencido. O `mv` PRESERVA o mtime: sem o `touch` na ida e na volta, um
  # item que nunca recebe ack ficava "vencido" a cada poll (reentrega infinita a cada ~25 s).
  # Teto ALERT_MAX_ATTEMPTS (5): depois disso o item é descartado com registro no log.
  local stale att tmpj
  while IFS= read -r stale; do
    [[ -n "$stale" ]] || continue
    att="$(jq -r '(.attempts // 1) + 1' "$stale" 2>/dev/null)"; [[ "$att" =~ ^[0-9]+$ ]] || att=99
    if (( att > ${ALERT_MAX_ATTEMPTS:-5} )); then
      printf '%s\tdrop\t%s\tsem ack após %s tentativas\n' "$EPOCHSECONDS" "${stale##*/}" "$(( att - 1 ))" >> "$d/relatorio.log" 2>/dev/null
      rm -f "$stale"; continue
    fi
    tmpj="$stale.tmp.${BASHPID}"
    if jq -c --argjson a "$att" '. + {attempts:$a}' "$stale" > "$tmpj" 2>/dev/null; then mv -f "$tmpj" "$ob/${stale##*/}" 2>/dev/null
    else rm -f "$tmpj"; mv -f "$stale" "$ob/" 2>/dev/null; fi
    touch "$ob/${stale##*/}" 2>/dev/null
  done < <(find "$inf" -maxdepth 1 -name '*.json' -mmin +"$(( ${ALERT_INFLIGHT_TTL:-600} / 60 ))" 2>/dev/null)
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
    if [[ "$f" == *.json && -n "$out" ]]; then { mv -f "$f" "$inf/$id.json" && touch "$inf/$id.json"; } 2>/dev/null || rm -f "$f"; else rm -f "$f"; fi
    [[ -n "$out" ]] || continue
    (( first )) || printf ','; first=0
    printf '%s' "$out"; n=$(( n + 1 ))
  done
  printf ']'
}
# alerts_ack <json-array [{id,ok,error}]> -> n confirmados. Apaga o inflight e avisa o relatório
# (rel_ack marca sent/outcome). Id fora do padrão é ignorado (nome de arquivo).
alerts_ack(){
  local d n=0 id ok err; d="$(_alert_dir)"
  declare -F rel_ack >/dev/null || source "${BASH_SOURCE[0]%/*}/relatorio.sh"
  while IFS=$'\t' read -r id ok err; do
    [[ "$id" =~ ^[0-9]+-[a-z]+-[A-Za-z0-9_-]+$ ]] || continue
    rm -f "$d/inflight/$id.json" 2>/dev/null
    rel_ack "$id" "$ok" "$err"
    n=$(( n + 1 ))
  done < <(jq -r '.[]? | select(type=="object") | [(.id // ""), (if .ok == true then "true" else "false" end), ((.error // "") | tostring | gsub("[\t\n]"; " "))] | @tsv' <<<"$1" 2>/dev/null)
  printf '%s' "$n"
}
