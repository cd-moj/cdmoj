#!/bin/bash
# server/judge-gw/sched-lib.sh — biblioteca do escalonador in-daemon + registro de
# workers. Sourced por server/api/v1/handlers/judge/* e por server/daemons/judged.sh.
# Tudo é bash + arquivos: registro JSON por host, fila por bandas de prioridade,
# claim atômico por flock+mv. Sem DB/broker. NÃO usa globs (a API roda com -o noglob).

: "${RUNDIR:=/home/ribas/moj/run}"
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
: "${REGISTRYDIR:=$RUNDIR/registry}"        # <host>.json por worker (vivo = last_seen recente)
: "${QUEUEDIR:=$RUNDIR/queue}"              # bandas de prioridade
: "${ASSIGNEDDIR:=$RUNDIR/assigned}"        # <host>/<ts>_<id>.json reivindicados
: "${RESULTSDIR:=$RUNDIR/results}"          # results/<id>.json
: "${UPDATESDIR:=$RUNDIR/updates}"          # pedidos de atualização de repositório
: "${REG_TTL:=30}"                          # s; heartbeat mais velho = worker morto
# ⚠ ASSIGN_TTL é o TETO DE PACIÊNCIA com um juiz VIVO, não o detector de juiz morto — e por isso
# tem de caber a correção INTEIRA, incluindo o download do pacote. Era 120s e mordeu no ensaio da
# Maratona (24/08/2026): `mdp-unb-xii#areias-da-anarquia` pesa **737 MB / 362 testes**; a correção
# em si levou **67 s**, mas o time esperou **915 s** porque o job foi revogado no meio e recomeçou
# em outro juiz (visto no `judge` 19:34 e no `judge-sp1` 19:36). O agente NÃO tem como dizer "ainda
# estou trabalhando": o heartbeat manda só `{state, free_slots, total_slots}`, então o relógio
# corre desde a reivindicação. Cada revogação DUPLICA o trabalho e ocupa mais um slot — é assim que
# a fila cresce em vez de drenar, num problema pesado com muitos times.
# Quem detecta juiz morto continua sendo o heartbeat (REG_TTL=30s ⇒ requeue NA HORA) e o
# `register boot:true` (agente que reinicia devolve tudo). O teto só cobre o caso raro de juiz
# vivo que perdeu o job em silêncio — e a calibração, que é o mesmo tipo de trabalho, já tinha
# 1800s (UPD_TTL). A assimetria é que era o descuido.
: "${ASSIGN_TTL:=900}"                      # s; juiz VIVO que não devolveu resultado nesse prazo
: "${UPD_TTL:=1800}"                         # s; calibração reivindicada e não terminada volta p/ pending
: "${STARVE_SECS:=300}"                     # s; promove de banda após esse tempo
: "${COLD_GRACE:=8}"                        # s; modelo cache: juiz que NÃO tem o problema
                                            # só reivindica após isso (dá vez aos quentes)
: "${LANG_GRACE:=90}"                       # s; route-by-language: juiz SEM o toolchain da
                                            # linguagem do job só pega depois disso (fallback
                                            # p/ não travar se nenhum juiz suporta a linguagem)
: "${POOL_GRACE:=0}"                        # s; pool de juízes do contest/problema: 0 = ESTRITO
                                            # (job com allowed_hosts espera um host do pool —
                                            # consistência de hardware); >0 = qualquer juiz
                                            # pega após esse tempo (fallback)

# bandas, prioridade ALTA -> BAIXA. 'rejulgar' entre privada e pública.
SCHED_BANDS=(000-super 020-prova 040-lista-privada 060-rejulgar 080-lista-publica)

sched_band_of() {  # $1 = CONTEST_PRIORITY -> nome da banda
  case "$1" in
    super)         echo 000-super;;
    prova)         echo 020-prova;;
    lista-privada) echo 040-lista-privada;;
    rejulgar)      echo 060-rejulgar;;
    *)             echo 080-lista-publica;;
  esac
}

valid_hostname() { [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] && [[ "$1" != *..* ]]; }

sched_init_dirs() {
  mkdir -p "$REGISTRYDIR" "$ASSIGNEDDIR" "$RESULTSDIR" "$QUEUEDIR" 2>/dev/null
  local b; for b in "${SCHED_BANDS[@]}"; do mkdir -p "$QUEUEDIR/$b" 2>/dev/null; done
}

# ----------------------------------------------------------- registro de workers
# reg_write <host> <json-completo> : grava atômico $REGISTRYDIR/<host>.json
reg_write() {
  local host="$1" json="$2"
  valid_hostname "$host" || return 1
  mkdir -p "$REGISTRYDIR" 2>/dev/null
  local tmp="$REGISTRYDIR/.$host.$$.tmp"
  printf '%s' "$json" > "$tmp" && mv -f "$tmp" "$REGISTRYDIR/$host.json"
}

# reg_touch_state <host> <state> : atualiza state + last_seen, preservando o resto.
# Retorna 1 se o host não está registrado.
reg_touch_state() {
  local host="$1" state="$2" f="$REGISTRYDIR/$host.json"
  valid_hostname "$host" || return 1
  [[ -f "$f" ]] || return 1
  local tmp="$REGISTRYDIR/.$host.$$.tmp"
  jq -c --arg s "$state" --argjson now "$EPOCHSECONDS" '.state=$s | .last_seen=$now' "$f" \
    > "$tmp" 2>/dev/null && mv -f "$tmp" "$f"
}

# reg_set <host> <jq-filter> [jq-args...] : aplica um filtro jq ao registro do host.
reg_set() {
  local host="$1"; shift
  local filter="$1"; shift
  local f="$REGISTRYDIR/$host.json"
  valid_hostname "$host" || return 1
  [[ -f "$f" ]] || return 1
  local tmp="$REGISTRYDIR/.$host.$$.tmp"
  jq -c "$@" "$filter" "$f" > "$tmp" 2>/dev/null && mv -f "$tmp" "$f"
}

reg_get() { local f="$REGISTRYDIR/$1.json"; [[ -f "$f" ]] && cat "$f"; }

# judges_config_for <host> : ecoa a config VIGENTE do juiz {partition,reserve,disabled,cfg_hash}
# (de judges-config.json; sem entrada => defaults com hash ""). Fonte única p/ heartbeat E
# register — os dois entregam exatamente o mesmo objeto/hash.
judges_config_for() {
  local host="$1" jconf entry srv_hash
  jconf="${JUDGES_CONFIG_FILE:-$CONTESTSDIR/treino/var/judges-config.json}"
  entry="$(jq -c --arg h "$host" '.[$h] // empty' "$jconf" 2>/dev/null)"
  if [[ -n "$entry" ]]; then srv_hash="$(printf '%s' "$entry" | md5sum | cut -c1-16)"; else srv_hash=""; fi
  jq -cn --argjson e "${entry:-null}" --arg hh "$srv_hash" \
    '{partition:($e.partition // "off"), reserve:($e.reserve // 0),
      disabled:($e.disabled // false), cfg_hash:$hh}'
}

# sched_requeue_host <host> : devolve à fila TUDO que estava atribuído ao host — jobs
# (assigned/<host>/ -> banda de origem) e calibrações (updates/inprogress/<host>/ -> pending).
# Usado pelo register boot:true: um agente que REINICIOU devolve o trabalho em voo NA HORA
# (os processos morreram no restart), sem esperar ASSIGN_TTL/UPD_TTL — restart não perde fila.
sched_requeue_host() {
  local host="$1" f base id prio band now=$EPOCHSECONDS
  valid_hostname "$host" || return 1
  sched_init_dirs; mkdir -p "$UPDATESDIR/pending" 2>/dev/null
  (
    flock 9 || exit 0
    while IFS= read -r f; do
      [[ -f "$f" ]] || continue
      base="$(basename "$f")"; id="${base#*_}"; id="${id%.json}"
      prio="$(jq -r '.priority // "lista-publica"' "$f" 2>/dev/null)"
      band="$(sched_band_of "$prio")"
      mv -f "$f" "$QUEUEDIR/$band/${now}_${id}.json" 2>/dev/null
    done < <(find "$ASSIGNEDDIR/$host" -maxdepth 1 -name '*.json' 2>/dev/null)
  ) 9>"$QUEUEDIR/.lock"
  (
    flock 9 || exit 0
    while IFS= read -r f; do
      [[ -f "$f" ]] || continue
      mv -f "$f" "$UPDATESDIR/pending/$(basename "$f")" 2>/dev/null
    done < <(find "$UPDATESDIR/inprogress/$host" -maxdepth 1 -name '*.json' 2>/dev/null)
  ) 9>"$UPDATESDIR/.lock"
  return 0
}

# reg_live_hosts [state] [capability] : hosts vivos (last_seen >= now-REG_TTL), 1/linha.
reg_live_hosts() {
  local want_state="${1:-}" want_cap="${2:-}" now=$EPOCHSECONDS f
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    jq -e --argjson now "$now" --argjson ttl "$REG_TTL" \
       --arg st "$want_state" --arg cap "$want_cap" '
       (.last_seen // 0) >= ($now - $ttl)
       and ($st  == "" or .state      == $st)
       and ($cap == "" or .capability == $cap)' "$f" >/dev/null 2>&1 \
      && basename "$f" .json
  done < <(find "$REGISTRYDIR" -maxdepth 1 -name '*.json' 2>/dev/null)
}

# ------------------------------------------------------------------- fila de jobs
# q_enqueue <id> <priority> <job-json> : enfileira na banda da prioridade.
q_enqueue() {
  local id="$1" prio="$2" json="$3" band
  band="$(sched_band_of "$prio")"
  sched_init_dirs
  local base="${EPOCHSECONDS}_${id}.json"
  local tmp="$QUEUEDIR/$band/.${base}.tmp"
  printf '%s' "$json" > "$tmp" && mv -f "$tmp" "$QUEUEDIR/$band/$base"
}

# q_claim <host> <capability> <problems-json> [langs-json] [max=1] : reivindica até MAX
# jobs que o worker pode rodar (capacidade + pool + linguagem + cache), atômico sob
# flock. Ecoa um job POR LINHA (jq -c; o enqueue grava single-line).
#
# COMPLEXIDADE (a lição da bancada, 30/08): a versão original fazia 2-6 jq POR JOB
# EXAMINADO e recomeçava a varredura DO ZERO a cada job reivindicado — com um prefixo de
# jobs presos por pool (o retrato da Maratona: 500 presos na frente), o custo era
# O(prefixo) POR CLAIM e a vazão medida caiu a 30 veredictos/min. Agora:
#   1. a decisão ESTÁTICA de cada job (problema, capacidade, pool, linguagem) mora num
#      sidecar `<job>.cmeta` escrito na PRIMEIRA visita (self-heal: 1 jq por job NA VIDA;
#      requeue/promote que renomeiam o .json só custam mais uma visita) — as varreduras
#      seguintes leem o sidecar com $(<…), ZERO processos por job pulado;
#   2. o claim é em LOTE: UMA varredura por chamada colhe até MAX jobs (o heartbeat pedia
#      1 por vez e re-varria o prefixo p/ cada slot);
#   3. glob ordenado (epoch de 10 dígitos ⇒ ordem lexical = cronológica) no lugar de
#      find|sort. Os GRACEs (relógio) continuam no bash. Semântica dos gates preservada
#      1:1 — provada pelos testes de gate e pelo smoke do pipeline.
q_claim() {
  local host="$1" cap="$2" probs="$3" langs="${4:-[]}" max="${5:-1}"
  valid_hostname "$host" || return 1
  [[ "$max" =~ ^[0-9]+$ ]] || max=1
  sched_init_dirs
  (
    flock 9 || exit 0
    set +o noglob   # subshell: o noglob da API não vaza; glob = listagem ordenada s/ fork
    local band f dest base ts meta prob need jl hosts probhot
    local claimed=0 pk v
    # conjuntos do JUIZ, calculados UMA vez por chamada (2 jq no total)
    local -A PH=()
    while IFS= read -r pk; do [[ -n "$pk" ]] && PH["$pk"]=1; done \
      < <(jq -r 'keys[]? // empty' <<<"$probs" 2>/dev/null)
    local LSET=""
    while IFS= read -r pk; do
      [[ -n "$pk" ]] || continue
      case "$pk" in py2|py3) pk=py;; esac
      LSET+=" $pk"
    done < <(jq -r '.[]? // empty' <<<"$langs" 2>/dev/null)
    [[ -n "$LSET" ]] && LSET+=" "
    for band in "${SCHED_BANDS[@]}"; do
      for f in "$QUEUEDIR/$band"/*.json; do
        [[ -f "$f" ]] || continue
        (( claimed >= max )) && break 2
        # sidecar de decisão estática: prob \x01 need \x01 lang \x01 hosts-csv
        if [[ -s "$f.cmeta" ]]; then
          meta="$(<"$f.cmeta")"
        else
          meta="$(jq -j '[ (.problem_id // ""),
                           (.need_capability // ""),
                           ((.lang // "") | ascii_downcase),
                           ((.allowed_hosts // []) | join(",")) ] | join("\u0001")' "$f" 2>/dev/null)" \
            || continue
          printf '%s' "$meta" > "$f.cmeta" 2>/dev/null
        fi
        IFS=$'\x01' read -r prob need jl hosts <<<"$meta"
        [[ -z "$need" || "$need" == "$cap" ]] || continue
        base="${f##*/}"
        # pool de juízes (allowed_hosts): ESTRITO por default (POOL_GRACE=0) — pool
        # offline segura a fila de propósito; POOL_GRACE>0 libera como fallback.
        if [[ -n "$hosts" && ",$hosts," != *",$host,"* ]]; then
          ts="${base%%_*}"
          { (( POOL_GRACE > 0 )) && [[ "$ts" =~ ^[0-9]+$ ]] \
              && (( EPOCHSECONDS - ts > POOL_GRACE )); } || continue
        fi
        # route by language: sem o toolchain espera LANG_GRACE; depois pega como fallback.
        if [[ -n "$LSET" ]]; then
          case "$jl" in py2|py3) jl=py;; esac
          if [[ -n "$jl" && "$LSET" != *" $jl "* ]]; then
            ts="${base%%_*}"
            [[ "$ts" =~ ^[0-9]+$ ]] && (( EPOCHSECONDS - ts <= LANG_GRACE )) && continue
          fi
        fi
        # modelo cache: juiz "quente" (tem o problema) reivindica na hora; frio espera
        # COLD_GRACE — a vantagem dos caches calibrados. Tolerante à convenção de id.
        probhot=0
        v="${prob//#/\/}"
        [[ -n "${PH[$prob]:-}" || -n "${PH[$v]:-}" ]] && probhot=1
        v="${prob//\//#}"
        [[ -n "${PH[$v]:-}" ]] && probhot=1
        if (( probhot == 0 )); then
          ts="${base%%_*}"
          [[ "$ts" =~ ^[0-9]+$ ]] && (( EPOCHSECONDS - ts <= COLD_GRACE )) && continue
        fi
        mkdir -p "$ASSIGNEDDIR/$host" 2>/dev/null
        dest="$ASSIGNEDDIR/$host/$base"
        if mv "$f" "$dest" 2>/dev/null; then
          rm -f "$f.cmeta" 2>/dev/null
          local tmp="$dest.tmp"
          jq -c --arg h "$host" --argjson now "$EPOCHSECONDS" \
             '. + {assigned_to:$h, assigned_at:$now}' "$dest" > "$tmp" 2>/dev/null \
             && mv -f "$tmp" "$dest"
          cat "$dest"; printf '\n'
          claimed=$(( claimed + 1 ))
        fi
      done
      # sidecar órfão (job saiu por requeue/promote sem levar o cmeta): gc barato
      for f in "$QUEUEDIR/$band"/*.cmeta; do
        [[ -e "$f" && ! -f "${f%.cmeta}" ]] && rm -f "$f" 2>/dev/null
      done
    done
    exit 0
  ) 9>"$QUEUEDIR/.lock"
}

# q_done <host> <id> : remove o job reivindicado (chamado após ingerir o resultado).
q_done() {
  local host="$1" id="$2" f
  while IFS= read -r f; do rm -f "$f"; done \
    < <(find "$ASSIGNEDDIR/$host" -maxdepth 1 -name "*_$id.json" 2>/dev/null)
}

# q_promote_starved : promove jobs parados (>STARVE_SECS) p/ a banda anterior.
# Throttle por stamp (roda no máx 1x/30s).
q_promote_starved() {
  sched_init_dirs
  local stamp="$QUEUEDIR/.starve-stamp" now=$EPOCHSECONDS last=0
  [[ -f "$stamp" ]] && last="$(<"$stamp")"
  (( now - last < 30 )) && return 0
  printf '%s' "$now" > "$stamp"
  (
    flock 9 || exit 0
    local i band prev f base ts id
    for (( i=${#SCHED_BANDS[@]}-1; i>0; i-- )); do
      band="${SCHED_BANDS[i]}"; prev="${SCHED_BANDS[i-1]}"
      while IFS= read -r f; do
        [[ -f "$f" ]] || continue
        base="$(basename "$f")"; ts="${base%%_*}"
        [[ "$ts" =~ ^[0-9]+$ ]] || continue
        (( now - ts > STARVE_SECS )) || continue
        id="${base#*_}"
        mv -f "$f" "$QUEUEDIR/$prev/${now}_${id}" 2>/dev/null
      done < <(find "$QUEUEDIR/$band" -maxdepth 1 -name '*.json' 2>/dev/null)
    done
  ) 9>"$QUEUEDIR/.lock"
}

# q_reconcile : devolve à fila jobs reivindicados por workers mortos (host não vivo,
# ou assigned_at velho demais). Idempotente — o result é guardado por id. Auto-throttle
# (~15s) porque varre o registro; um worker morto espera no máx ASSIGN_TTL de qualquer jeito.
q_reconcile() {
  sched_init_dirs
  local now=$EPOCHSECONDS stamp="$QUEUEDIR/.reconcile-stamp" last=0
  [[ -f "$stamp" ]] && last="$(<"$stamp")"
  (( now - last < 15 )) && return 0
  printf '%s' "$now" > "$stamp"
  local live; live=" $(reg_live_hosts | tr '\n' ' ') "   # set de vivos, 1 só varredura
  local hostdir host f base id prio band aat
  while IFS= read -r hostdir; do
    [[ -d "$hostdir" ]] || continue
    host="$(basename "$hostdir")"
    while IFS= read -r f; do
      [[ -f "$f" ]] || continue
      base="$(basename "$f")"; id="${base#*_}"; id="${id%.json}"
      aat="$(jq -r '.assigned_at // 0' "$f" 2>/dev/null)"
      if [[ "$live" != *" $host "* ]] || (( now - aat > ASSIGN_TTL )); then
        prio="$(jq -r '.priority // "lista-publica"' "$f" 2>/dev/null)"
        band="$(sched_band_of "$prio")"
        mv -f "$f" "$QUEUEDIR/$band/${now}_${id}.json" 2>/dev/null
      fi
    done < <(find "$hostdir" -maxdepth 1 -name '*.json' 2>/dev/null)
  done < <(find "$ASSIGNEDDIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
}

# --------------------------------------------------- pedidos de calibração/índice
# Modelo cache: o servidor mantém o store dos pacotes e indexa; o juiz baixa o pacote
# por problema, CALIBRA e reporta o TL. "update problems" = pedir calibração dos
# problemas novos/alterados. O pedido vira um marcador entregue a UM worker livre.
upd_request() {  # $1=repo $2=requested_by [$3=note] [$4=kind] [$5=target] -> ecoa o reqid
  # kind ∈ {calibrate,index,update}; target = problem_id. calibrate = juiz roda o
  # calibreitor no cache e reporta o TL (kind=index/update são legados: o servidor indexa).
  mkdir -p "$UPDATESDIR/pending" 2>/dev/null
  local reqid; reqid="$(printf '%s%s%s' "$1" "$EPOCHSECONDS" "$RANDOM" | md5sum | cut -c1-16)"
  local tmp="$UPDATESDIR/pending/.$reqid.tmp"
  jq -cn --arg id "$reqid" --arg r "$1" --arg by "${2:-?}" --arg n "${3:-}" \
     --arg kind "${4:-update}" --arg target "${5:-}" --argjson now "$EPOCHSECONDS" \
     '{reqid:$id, repo:$r, requested_by:$by, note:$n, kind:$kind, target:$target, requested_at:$now}' > "$tmp" \
     && mv -f "$tmp" "$UPDATESDIR/pending/$reqid.json"
  printf '%s' "$reqid"
}

# upd_find_calibrate <problem_id> : ecoa o reqid de uma calibração JÁ pendente ou em execução
# p/ esse problema (ou nada). Base do dedup do cal_request. Conteúdo via stdin (find -exec cat),
# nunca por argv — ARG_MAX-safe com qualquer tamanho de fila.
upd_find_calibrate() {
  local r
  r="$( { find "$UPDATESDIR/pending"    -maxdepth 1 -name '*.json' -exec cat {} + 2>/dev/null
          find "$UPDATESDIR/inprogress" -mindepth 2 -name '*.json' -exec cat {} + 2>/dev/null; } \
        | jq -r --arg t "$1" 'select(.kind=="calibrate" and .target==$t) | .reqid' 2>/dev/null \
        | head -n1)"
  printf '%s' "$r"
}

# cal_request <repo> <problem_id> <by> : pede CALIBRAÇÃO (1 juiz roda calibreitor).
# IDEMPOTENTE (lição do incidente 2026-07-15): se já existe calibração pendente/em execução p/ o
# MESMO problema, devolve o reqid EXISTENTE em vez de criar outro job — re-disparar "Calibrar"
# (ou publicar em massa) nunca multiplica jobs nem entope os slots dos juízes. Checagem+criação
# sob o MESMO lock do upd_claim p/ não haver janela entre dois pedidos simultâneos.
cal_request() {
  mkdir -p "$UPDATESDIR/pending" 2>/dev/null
  (
    flock 9 || exit 1
    local ex; ex="$(upd_find_calibrate "$2")"
    if [[ -n "$ex" ]]; then printf '%s' "$ex"
    else upd_request "$1" "$3" "calibrate $2" calibrate "$2"; fi
  ) 9>"$UPDATESDIR/.lock"
}
# idx_request <repo> <problem_id> <by> : pede VALIDAÇÃO+INDEX (publish).
idx_request() { upd_request "$1" "$3" "index $2" index "$2"; }

# upd_claim <host> : reivindica 1 update pendente (atômico) e o ecoa, ou nada.
# SERIALIZAÇÃO POR PROBLEMA: calibrate cujo target JÁ está em execução (em QUALQUER host)
# fica esperando em pending — nunca dois slots/hosts calibrando o MESMO problema ao mesmo
# tempo (duplicata pendente só sai depois, e o agente a resolve num skip se o pedido for
# mais velho que a calibração concluída). O loop segue p/ o próximo pendente (outro problema
# não é bloqueado).
upd_claim() {
  local host="$1" f base dest t busy
  valid_hostname "$host" || return 1
  mkdir -p "$UPDATESDIR/pending" "$UPDATESDIR/inprogress/$host" 2>/dev/null
  (
    flock 9 || exit 0
    while IFS= read -r f; do
      [[ -f "$f" ]] || continue
      if jq -e '.kind=="calibrate"' "$f" >/dev/null 2>&1; then
        t="$(jq -r '.target // ""' "$f" 2>/dev/null)"
        if [[ -n "$t" ]]; then
          busy="$(find "$UPDATESDIR/inprogress" -mindepth 2 -name '*.json' -exec cat {} + 2>/dev/null \
                  | jq -r --arg t "$t" 'select(.kind=="calibrate" and .target==$t) | .reqid' 2>/dev/null | head -n1)"
          [[ -n "$busy" ]] && continue   # já calibrando em algum lugar: espera a vez
        fi
      fi
      base="$(basename "$f")"; dest="$UPDATESDIR/inprogress/$host/$base"
      if mv "$f" "$dest" 2>/dev/null; then
        local tmp="$dest.tmp"   # carimba claimed_at p/ o upd_reconcile detectar pedido preso
        jq -c --argjson now "$EPOCHSECONDS" '. + {claimed_at:$now}' "$dest" > "$tmp" 2>/dev/null && mv -f "$tmp" "$dest"
        cat "$dest"; exit 0
      fi
    done < <(find "$UPDATESDIR/pending" -maxdepth 1 -name '*.json' 2>/dev/null | sort)
  ) 9>"$UPDATESDIR/.lock"
}

upd_done() { rm -f "$UPDATESDIR/inprogress/$1/$2.json" 2>/dev/null; }   # $1=host $2=reqid

# upd_touch_host <host> : re-carimba o MTIME das calibrações em execução deste host.
# Chamado a cada heartbeat de agente NOVO (que manda `status` e tem teto dinâmico + kill):
# enquanto o juiz está VIVO, uma calibração longa LEGÍTIMA (que pode passar de UPD_TTL) não é
# re-enfileirada — o UPD_TTL vira proteção só contra host morto/agente antigo.
# `touch -c` (NUNCA cria): a versão anterior reescrevia o JSON (jq > tmp && mv) e RESSUSCITAVA
# o arquivo quando o upd_done o removia entre a leitura e o mv — nascia um claim FANTASMA que,
# re-tocado a cada beat, nunca expirava e (com a serialização por-target) bloqueava calibrações
# futuras do problema. O claimed_at do JSON fica intacto (idade real na UI); o TTL lê o mtime.
upd_touch_host() {
  local host="$1"
  [[ -d "$UPDATESDIR/inprogress/$host" ]] || return 0
  find "$UPDATESDIR/inprogress/$host" -maxdepth 1 -name '*.json' -exec touch -c {} + 2>/dev/null
  return 0
}

# upd_reconcile : devolve à fila (pending) calibrações que ficaram presas em inprogress —
# host morreu (reiniciou no meio) ou passou de UPD_TTL sem terminar. Sem isto, uma calibração
# interrompida trava p/ sempre e a fila seca ("calibração não é refeita"). Auto-throttle (~15s).
upd_reconcile() {
  mkdir -p "$UPDATESDIR/pending" "$UPDATESDIR/inprogress" 2>/dev/null
  local now=$EPOCHSECONDS stamp="$UPDATESDIR/.reconcile-stamp" last=0
  [[ -f "$stamp" ]] && last="$(<"$stamp")"
  (( now - last < 15 )) && return 0
  printf '%s' "$now" > "$stamp"
  local live; live=" $(reg_live_hosts | tr '\n' ' ') "
  (
    flock 9 || exit 0
    local hostdir host f base cat_at
    while IFS= read -r hostdir; do
      [[ -d "$hostdir" ]] || continue
      host="$(basename "$hostdir")"
      while IFS= read -r f; do
        [[ -f "$f" ]] || continue
        base="$(basename "$f")"
        # TTL sobre o carimbo mais RECENTE: o MTIME (touch -c do heartbeat de agente novo)
        # mantém viva a calibração longa legítima; no claim o mtime ≈ claimed_at (agente
        # antigo nunca é tocado => expira como sempre). claimed_at do JSON = idade real na UI.
        cat_at="$(stat -c %Y "$f" 2>/dev/null)"
        [[ "$cat_at" =~ ^[0-9]+$ ]] || cat_at="$(jq -r '.claimed_at // .requested_at // 0' "$f" 2>/dev/null)"
        if [[ "$live" != *" $host "* ]] || (( now - cat_at > UPD_TTL )); then
          mv -f "$f" "$UPDATESDIR/pending/$base" 2>/dev/null
        fi
      done < <(find "$hostdir" -maxdepth 1 -name '*.json' 2>/dev/null)
    done < <(find "$UPDATESDIR/inprogress" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
  ) 9>"$UPDATESDIR/.lock"
}

# upd_pending_count : nº de updates pendentes (não reivindicados).
upd_pending_count() { find "$UPDATESDIR/pending" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l; }

# upd_pending_kind_count <kind> / upd_inprogress_kind_count <kind> — contagem FILTRADA por kind.
# pending mistura kind=="calibrate" e kind=="index"; separar é essencial p/ o contador EXPLÍCITO de
# calibração na fila do .admin. jq -s em stdin vazio -> [] -> length 0. Saneia a dígitos (lição do
# outage do grep -c: nunca deixar não-dígito escapar p/ aritmética).
upd_pending_kind_count() { local n
  n="$(find "$UPDATESDIR/pending" -maxdepth 1 -name '*.json' -exec cat {} + 2>/dev/null \
       | jq -s --arg k "$1" '[.[]|select(.kind==$k)]|length' 2>/dev/null)"; n="${n//[^0-9]/}"; printf '%s' "${n:-0}"; }
upd_inprogress_kind_count() { local n
  n="$(find "$UPDATESDIR/inprogress" -mindepth 2 -name '*.json' -exec cat {} + 2>/dev/null \
       | jq -s --arg k "$1" '[.[]|select(.kind==$k)]|length' 2>/dev/null)"; n="${n//[^0-9]/}"; printf '%s' "${n:-0}"; }

# --------------------------------------------------- comandos POR-HOST (cache, etc.)
# Diferente de update/job (que QUALQUER juiz pega): comando é entregue a UM host específico
# no heartbeat dele. Uso: gerência de cache (limpar) pelo admin.
: "${CMDDIR:=$RUNDIR/commands}"
cmd_request() {  # <host> <action> [by] [problem-id] -> ecoa o cmdid
  local host="$1" action="$2" by="${3:-?}" target="${4:-}" cmdid tmp
  valid_hostname "$host" || return 1
  mkdir -p "$CMDDIR/$host" 2>/dev/null
  cmdid="$(printf '%s%s%s' "$host" "$EPOCHSECONDS" "$RANDOM" | md5sum | cut -c1-12)"
  tmp="$CMDDIR/$host/.$cmdid.tmp"
  jq -cn --arg id "$cmdid" --arg a "$action" --arg by "$by" --arg t "$target" --argjson now "$EPOCHSECONDS" \
     '{cmdid:$id, action:$a, by:$by, at:$now} + (if $t=="" then {} else {id:$t} end)' > "$tmp" && mv -f "$tmp" "$CMDDIR/$host/$cmdid.json"
  printf '%s' "$cmdid"
}
cmd_claim_urgent() {  # <host> : reivindica 1 comando URGENTE (kill|restart), deixando os demais.
  # Entregue MESMO com o juiz ocupado/desabilitado — é o canal de recuperação sem SSH
  # (`moj judges reset/restart`) que faltou no incidente 2026-07-15.
  local host="$1" f a
  valid_hostname "$host" || return 1
  [[ -d "$CMDDIR/$host" ]] || return 0
  (
    flock 9 || exit 0
    while IFS= read -r f; do
      [[ -f "$f" ]] || continue
      a="$(jq -r '.action // ""' "$f" 2>/dev/null)"
      [[ "$a" == kill || "$a" == restart ]] || continue
      cat "$f"; rm -f "$f"; exit 0
    done < <(find "$CMDDIR/$host" -maxdepth 1 -name '*.json' 2>/dev/null | sort)
  ) 9>"$CMDDIR/$host/.lock"
}
cmd_claim() {  # <host> : reivindica 1 comando pendente do host (ecoa + remove), atômico.
  local host="$1" f
  valid_hostname "$host" || return 1
  [[ -d "$CMDDIR/$host" ]] || return 0
  mkdir -p "$CMDDIR/$host" 2>/dev/null
  (
    flock 9 || exit 0
    while IFS= read -r f; do
      [[ -f "$f" ]] || continue
      cat "$f"; rm -f "$f"; exit 0
    done < <(find "$CMDDIR/$host" -maxdepth 1 -name '*.json' 2>/dev/null | sort)
  ) 9>"$CMDDIR/$host/.lock"
}
# cmd_find_calibrate <host> <problem_id> : ecoa o cmdid de um calibrate direcionado AINDA NÃO
# entregue a esse host p/ o problema (dedup do caminho targeted; comando entregue some do dir,
# então "em execução" não é visível aqui — o dedup do agente cobre esse resto).
cmd_find_calibrate() {
  local r
  r="$(find "$CMDDIR/$1" -maxdepth 1 -name '*.json' -exec cat {} + 2>/dev/null \
       | jq -r --arg t "$2" 'select(.action=="calibrate" and .id==$t) | .cmdid' 2>/dev/null \
       | head -n1)"
  printf '%s' "$r"
}
cmd_pending_count() { find "$CMDDIR/$1" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l; }
# cmd_action_count <action> — comandos direcionados de TODOS os hosts com esse action (ex.: calibrate,
# recalibração fixada num CPU). Saneia a dígitos como acima.
cmd_action_count() { local n
  n="$(find "$CMDDIR" -mindepth 2 -name '*.json' -exec cat {} + 2>/dev/null \
       | jq -s --arg a "$1" '[.[]|select(.action==$a)]|length' 2>/dev/null)"; n="${n//[^0-9]/}"; printf '%s' "${n:-0}"; }
