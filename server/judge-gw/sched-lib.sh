#!/bin/bash
# server/judge-gw/sched-lib.sh — biblioteca do escalonador in-daemon + registro de
# workers. Sourced por server/api/v1/handlers/judge/* e por server/daemons/judged.sh.
# Tudo é bash + arquivos: registro JSON por host, fila por bandas de prioridade,
# claim atômico por flock+mv. Sem DB/broker. NÃO usa globs (a API roda com -o noglob).

: "${RUNDIR:=/home/ribas/moj/run}"
: "${REGISTRYDIR:=$RUNDIR/registry}"        # <host>.json por worker (vivo = last_seen recente)
: "${QUEUEDIR:=$RUNDIR/queue}"              # bandas de prioridade
: "${ASSIGNEDDIR:=$RUNDIR/assigned}"        # <host>/<ts>_<id>.json reivindicados
: "${RESULTSDIR:=$RUNDIR/results}"          # results/<id>.json
: "${UPDATESDIR:=$RUNDIR/updates}"          # pedidos de atualização de repositório
: "${REG_TTL:=30}"                          # s; heartbeat mais velho = worker morto
: "${ASSIGN_TTL:=120}"                      # s; job reivindicado sem novo beat volta p/ fila
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

# q_claim <host> <capability> <problems-json> : reivindica 1 job que o worker pode
# rodar (capacidade + tem-o-problema), atômico sob flock. Ecoa o job (ou nada).
q_claim() {
  local host="$1" cap="$2" probs="$3" langs="${4:-[]}"
  valid_hostname "$host" || return 1
  sched_init_dirs
  (
    flock 9 || exit 0
    local band f prob need dest base ts joblang
    for band in "${SCHED_BANDS[@]}"; do
      while IFS= read -r f; do
        [[ -f "$f" ]] || continue
        prob="$(jq -r '.problem_id // empty' "$f" 2>/dev/null)"
        need="$(jq -r '.need_capability // empty' "$f" 2>/dev/null)"
        [[ -n "$need" && "$need" != "$cap" ]] && continue
        base="$(basename "$f")"
        # pool de juízes (allowed_hosts, resolvido no enqueue: problema -> contest): job só
        # sai p/ host listado. ESTRITO por default (POOL_GRACE=0) — pool offline segura a
        # fila de propósito (consistência de hardware); POOL_GRACE>0 libera como fallback.
        if jq -e --arg h "$host" '((.allowed_hosts // [])|length) > 0
              and (((.allowed_hosts // [])|index($h))|not)' "$f" >/dev/null 2>&1; then
          ts="${base%%_*}"
          { (( POOL_GRACE > 0 )) && [[ "$ts" =~ ^[0-9]+$ ]] \
              && (( EPOCHSECONDS - ts > POOL_GRACE )); } || continue
        fi
        # route by language: só julga se o host TEM o toolchain da linguagem do job. Sem ele,
        # espera LANG_GRACE (dá vez a quem tem); depois pega como fallback (juiz incapaz ->
        # CE, mas a submissão não fica presa p/ sempre). langs vazio = filtro desligado.
        if [[ -n "$langs" && "$langs" != "[]" ]]; then
          joblang="$(jq -r '.lang // empty' "$f" 2>/dev/null | tr 'A-Z' 'a-z')"
          # python unificado: rejulgamento de .py2/.py3 legado casa com o 'py' dos juízes
          case "$joblang" in py2|py3) joblang=py;; esac
          if [[ -n "$joblang" ]] && ! printf '%s' "$langs" | jq -e --arg l "$joblang" 'index($l)' >/dev/null 2>&1; then
            ts="${base%%_*}"
            [[ "$ts" =~ ^[0-9]+$ ]] && (( EPOCHSECONDS - ts <= LANG_GRACE )) && continue
          fi
        fi
        # modelo cache: QUALQUER juiz capaz pode julgar (baixa o pacote + calibra sob
        # demanda). Preferência "quente": quem JÁ tem o problema (cache calibrado)
        # reivindica na hora; quem não tem só pega após COLD_GRACE, dando vantagem aos
        # juízes quentes. Tolerante à convenção de id (repo#prob vs repo/prob).
        if ! printf '%s' "$probs" | jq -e --arg p "$prob" '
              . as $obj
              | ([$p, ($p|gsub("#";"/")), ($p|gsub("/";"#"))] | unique) as $vs
              | any($vs[]; in($obj))' >/dev/null 2>&1; then
          ts="${base%%_*}"
          [[ "$ts" =~ ^[0-9]+$ ]] && (( EPOCHSECONDS - ts <= COLD_GRACE )) && continue
        fi
        mkdir -p "$ASSIGNEDDIR/$host" 2>/dev/null
        dest="$ASSIGNEDDIR/$host/$base"
        if mv "$f" "$dest" 2>/dev/null; then
          local tmp="$dest.tmp"
          jq -c --arg h "$host" --argjson now "$EPOCHSECONDS" \
             '. + {assigned_to:$h, assigned_at:$now}' "$dest" > "$tmp" 2>/dev/null \
             && mv -f "$tmp" "$dest"
          cat "$dest"
          exit 0
        fi
      done < <(find "$QUEUEDIR/$band" -maxdepth 1 -name '*.json' 2>/dev/null | sort)
    done
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

# cal_request <repo> <problem_id> <by> : pede CALIBRAÇÃO (1 juiz roda calibreitor).
cal_request() { upd_request "$1" "$3" "calibrate $2" calibrate "$2"; }
# idx_request <repo> <problem_id> <by> : pede VALIDAÇÃO+INDEX (publish).
idx_request() { upd_request "$1" "$3" "index $2" index "$2"; }

# upd_claim <host> : reivindica 1 update pendente (atômico) e o ecoa, ou nada.
upd_claim() {
  local host="$1" f base dest
  valid_hostname "$host" || return 1
  mkdir -p "$UPDATESDIR/pending" "$UPDATESDIR/inprogress/$host" 2>/dev/null
  (
    flock 9 || exit 0
    while IFS= read -r f; do
      [[ -f "$f" ]] || continue
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
        cat_at="$(jq -r '.claimed_at // .requested_at // 0' "$f" 2>/dev/null)"
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
cmd_pending_count() { find "$CMDDIR/$1" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l; }
# cmd_action_count <action> — comandos direcionados de TODOS os hosts com esse action (ex.: calibrate,
# recalibração fixada num CPU). Saneia a dígitos como acima.
cmd_action_count() { local n
  n="$(find "$CMDDIR" -mindepth 2 -name '*.json' -exec cat {} + 2>/dev/null \
       | jq -s --arg a "$1" '[.[]|select(.action==$a)]|length' 2>/dev/null)"; n="${n//[^0-9]/}"; printf '%s' "${n:-0}"; }
