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

# ----- largura (CPUNEEDED) / paralelismo por slot (24/09/2026) -----
: "${HOLDDIR:=$RUNDIR/hold}"                 # run/hold/<host>.json — juiz SEGURADO p/ um job largo
: "${HOLD_AFTER:=20}"                        # s pendente antes de segurar um juiz p/ um job largo
: "${HOLD_TTL:=600}"                         # s; hold vence (recriado se o job segue pendente)
: "${INFEASIBLE_AFTER:=120}"                 # s pendente sem juiz vivo com a largura ⇒ Judge Error
: "${DECLINE_BACKOFF:=60}"                   # s; host que recusou (decline) pula o job por isso
: "${DECLINE_MAX:=3}"                        # recusas ⇒ Judge Error
: "${PARALLEL_MAX_DEFAULT:=4}"               # teto de testes ao mesmo tempo por job (por juiz)
: "${SWEEP_THROTTLE:=5}"                     # s entre varreduras de hold/infactível

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

# Só cria o que falta, e num mkdir só: roda em TODO heartbeat (via q_claim e amigos), e os `mkdir -p`
# incondicionais daqui, do upd_claim e do upd_reconcile eram 20 forks por beat (XIV Maratona UnB,
# 25/09/2026: 54.668 beats no dia, mediana de 0,21 s no servidor).
_mkd() {  # <dir…> : mkdir -p só dos que faltam (existência por builtin; nenhum fork no caso comum)
  local d miss=()
  for d in "$@"; do [[ -d "$d" ]] || miss+=("$d"); done
  (( ${#miss[@]} )) && mkdir -p "${miss[@]}" 2>/dev/null
  return 0
}
sched_init_dirs() {
  local b bands=()
  for b in "${SCHED_BANDS[@]}"; do bands+=("$QUEUEDIR/$b"); done
  _mkd "$REGISTRYDIR" "$ASSIGNEDDIR" "$RESULTSDIR" "$QUEUEDIR" "${bands[@]}"
}

# q_has_jobs : 0 se há ao menos um job em alguma banda da fila. Glob do bash (zero fork) — é o que deixa o
# heartbeat de fila VAZIA (o caso comum) pular o registro inteiro e o q_claim.
q_has_jobs() {
  local b
  for b in "${SCHED_BANDS[@]}"; do compgen -G "$QUEUEDIR/$b/*.json" >/dev/null && return 0; done
  return 1
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

# reg_touch_state <host> <state> [status] : atualiza state + last_seen (e o `status` do agente novo, se
# vier — ok|draining|disabled), preservando o resto. Retorna 1 se o host não está registrado.
reg_touch_state() {
  local host="$1" state="$2" status="${3:-}"; local f="$REGISTRYDIR/$host.json"   # (dois `local`: ver judged.sh route_root_file)
  valid_hostname "$host" || return 1
  [[ -f "$f" ]] || return 1
  local tmp="$REGISTRYDIR/.$host.$$.tmp"
  jq -c --arg s "$state" --arg st "$status" --argjson now "$EPOCHSECONDS" \
     '.state=$s | .last_seen=$now | if $st != "" then .status=$st else . end' "$f" \
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
# ⚠ O `cfg_hash` cobre SÓ os três campos que o agente APLICA (normalizados) — nunca a entrada
# inteira: ela carrega `updated_at`/`by` (e, desde 24/09/2026, campos de escalonamento como
# `parallel_max`, que são do SERVIDOR), e hashear tudo fazia QUALQUER edição da entrada DRENAR
# o juiz p/ reaplicar a mesma partição (bug (d)).
judges_config_for() {
  # UM jq (eram três a CADA heartbeat de cada juiz — TCP 2026, 03/10/2026): a 1ª linha diz se há entrada p/ o host,
  # a 2ª é o objeto normalizado (-S: chaves ordenadas, é ele que vira o hash). O `cfg_hash` entra por texto no fim
  # — byte a byte o que o `. + {cfg_hash}` do jq escrevia (smoke-judge-config.sh).
  local host="$1" jconf out has="" norm="" srv_hash=""
  jconf="${JUDGES_CONFIG_FILE:-$CONTESTSDIR/treino/var/judges-config.json}"
  out="$(jq -cS --arg h "$host" '(.[$h] // null) as $e | ($e != null),
          ({partition:($e.partition // "off"), reserve:(($e.reserve // 0) | tonumber? // 0),
            disabled:(($e.disabled // false) == true)})' "$jconf" 2>/dev/null)"
  { IFS= read -r has; IFS= read -r norm; } <<<"$out"
  [[ "$norm" == '{'*'}' ]] || { norm='{"disabled":false,"partition":"off","reserve":0}'; has=false; }
  [[ "$has" == true ]] && srv_hash="$(printf '%s' "$norm" | md5sum | cut -c1-16)"
  printf '%s\n' "${norm%\}},\"cfg_hash\":\"$srv_hash\"}"
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


# ============================ LARGURA k / paralelismo (24/09/2026) ============================
# Vocabulário (cdmoj/docs/PACOTE.md "Problemas paralelos" e judge-gw/PULL.md): k = CPUNEEDED (CPUs por
# teste), slot_cpus = cpus do MENOR slot do juiz (1 em produção), k_slots = ceil(k/slot_cpus) = slots
# que UM grupo ocupa; P = grupos (testes ao mesmo tempo); par_max = P concedido por este servidor.
# Juiz LEGADO (heartbeat sem slot_cpus): só jobs k=1, sem campos novos no job.

# sched_pkg_par <problem_id> : ecoa "k\x01numa\x01par\x01m\x01memmb" lidos do conf do PACOTE por
# regex (conf de autor NUNCA é sourced no servidor). Sem pacote/MOJ_PROBLEMS_DIR ⇒ defaults.
sched_pkg_par() {
  _pkg_par_v "$1"
  printf '%s\x01%s\x01%s\x01%s\x01%s' "$_PP_K" "$_PP_NUMA" "$_PP_PAR" "$_PP_M" "$_PP_MEM"
}
# _pkg_par_v <problem_id> : o MESMO parse, SEM fork (lê com `read -d ''`), em _PP_K _PP_NUMA _PP_PAR
# _PP_M _PP_MEM — p/ quem percorre muitos problemas (o Painel de um .admin lista centenas)
_pkg_par_v() {
  local id="${1//\//#}" dir conf c="" k=1 numa=n par=y m="" mem=0 re v
  if [[ -n "${MOJ_PROBLEMS_DIR:-}" && "$id" == *#* ]]; then
    dir="$MOJ_PROBLEMS_DIR/${id%%#*}/${id#*#}"; conf="$dir/conf"
    if [[ -f "$conf" ]]; then
      IFS= read -r -d '' c < "$conf" || true; c=$'\n'"$c"
      re=$'\n[[:space:]]*CPUNEEDED=["\x27]?([0-9]+)';        [[ "$c" =~ $re ]] && k="${BASH_REMATCH[1]}"
      re=$'\n[[:space:]]*SAMENUMA=["\x27]?([a-zA-Z]+)';      [[ "$c" =~ $re ]] && numa="${BASH_REMATCH[1]}"
      re=$'\n[[:space:]]*ALLOWPARALLELTEST=["\x27]?([a-zA-Z]+)'; [[ "$c" =~ $re ]] && par="${BASH_REMATCH[1]}"
      re=$'\n[[:space:]]*MAXPARALLELTESTS=["\x27]?([0-9]+)'; [[ "$c" =~ $re ]] && m="${BASH_REMATCH[1]}"
      re=$'\n[[:space:]]*MEMLIMITMB=["\x27]?([0-9]+)';       [[ "$c" =~ $re ]] && mem="${BASH_REMATCH[1]}"
    fi
  fi
  [[ "$k" =~ ^[0-9]+$ && "$k" -ge 1 && "$k" -le 64 ]] || k=1
  [[ "$numa" == y ]] || numa=n
  [[ "$par" == n ]] && par=n || par=y
  [[ "$m" =~ ^[0-9]+$ && "$m" -ge 1 ]] || m=""
  [[ "$mem" =~ ^[0-9]+$ ]] || mem=0
  _PP_K=$k; _PP_NUMA=$numa; _PP_PAR=$par; _PP_M=$m; _PP_MEM=$mem
}
# _kslots <k> <slot_cpus> -> ceil(k/slot_cpus) (slot_cpus<1 ⇒ 1)
_kslots() { local k="$1" sc="$2"; [[ "$sc" =~ ^[0-9]+$ && "$sc" -ge 1 ]] || sc=1; printf '%s' "$(( (k + sc - 1) / sc ))"; }

# _eff_width <k> <memmb> <slot_cpus> <total_slots> <mem_kb> : a LARGURA EFETIVA do job NESTE juiz, em
# _EK (cpus = o test_cpus que vai ao agente) e _EKS (slots). MEMÓRIA TAMBÉM É LARGURA: cada slot
# comporta (mem−4 GB)/total_slots da máquina; o job cujo HARDMEM (max(600, MEMLIMITMB+64), a regra da
# jaula) não cabe em ceil(k/slot_cpus) slots leva os slots que o comportam — e o test_cpus sobe junto,
# porque é pelo test_cpus que o agente reserva (alloc_slots). _EKS=0 = nem a máquina INTEIRA comporta:
# o claim pula e o infeasible_sweep fecha com Judge Error (antes o job ficava na fila PARA SEMPRE — 10
# submissões de uma lista presas por MEMLIMITMB=262144, incidente de 30/09/2026). Sem mem_kb/total
# (juiz legado ou registro incompleto) vale só a largura de CPU. Sem fork: roda no laço do claim.
_eff_width() {
  local k="$1" mem="$2" sc="$3" tot="$4" memkb="$5" usable hm mks
  [[ "$k" =~ ^[0-9]+$ && "$k" -ge 1 ]] || k=1
  [[ "$sc" =~ ^[0-9]+$ && "$sc" -ge 1 ]] || sc=1
  _EK=$k; _EKS=$(( (k + sc - 1) / sc ))
  [[ "$mem" =~ ^[0-9]+$ ]] && (( mem > 0 )) || return 0
  [[ "$tot" =~ ^[0-9]+$ && "$memkb" =~ ^[0-9]+$ ]] && (( tot >= 1 )) || return 0
  usable=$(( memkb / 1024 - 4096 )); (( usable > 0 )) || return 0
  hm=$(( mem + 64 )); (( hm < 600 )) && hm=600
  mks=$(( (hm * tot + usable - 1) / usable ))
  (( mks > tot )) && { _EKS=0; return 0; }
  (( mks > _EKS )) && { _EKS=$mks; _EK=$(( mks * sc )); }
  return 0
}

# ---------------------------------------------------------- VIABILIDADE (gestão de problemas)
# O problema pode ser julgado pelos juízes que a plataforma TEM? É a pergunta do Painel da gestão e do
# "Pronto" (o incidente de 30/09/2026 só apareceu quando um aluno reclamou: 15 problemas com
# MEMLIMITMB=262144 eram impossíveis e nada os apontava). A regra é a do claim (_eff_width), não uma cópia.
# sched_cap_load [janela_s=604800] : carrega a capacidade dos juízes REGISTRADOS vistos na janela (7 dias:
# juiz reiniciando não pode fazer o Painel piscar), fora os desabilitados. Arrays paralelos SCAP_TOT
# (slots) SCAP_SC (cpus/slot) SCAP_NODE (maior nó, slots) SCAP_MEM (mem_kb); SCAP_N = quantos. 1 jq.
sched_cap_load() {
  local win="${1:-604800}" t sc nd mk
  SCAP_TOT=(); SCAP_SC=(); SCAP_NODE=(); SCAP_MEM=(); SCAP_N=0
  while IFS=$'\x01' read -r t sc nd mk; do
    [[ "$t" =~ ^[0-9]+$ ]] || continue
    SCAP_TOT+=("$t"); SCAP_SC+=("$sc"); SCAP_NODE+=("$nd"); SCAP_MEM+=("$mk"); SCAP_N=$(( SCAP_N + 1 ))
  done < <(find "$REGISTRYDIR" -maxdepth 1 -name '*.json' -exec cat {} + 2>/dev/null \
    | jq -r --argjson now "$EPOCHSECONDS" --argjson w "$win" '
        select((.last_seen // 0) >= ($now - $w) and (.status // "") != "disabled")
        | [ ((.total_slots // 1)|tostring), ((.slot_cpus // 1)|tostring),
            (((.slots_by_node // {}) | [.[]] | max) // (.total_slots // 1) | tostring), ((.mem_kb // "")|tostring) ]
        | join("\u0001")' 2>/dev/null)
}
# sched_judgeable <k> <numa y|n> <memmb> : contra os juízes de sched_cap_load. _NJ_CODE vazio = cabe em algum
# (ou nenhum juiz conhecido: não se afirma nada); senão memory|numa|cpus, com _NJ_NEED (o que o problema pede:
# MEMLIMITMB ou CPUs) e _NJ_MAX (o máximo que um juiz dá: MEMLIMITMB aceito, CPUs no maior nó ou na máquina).
sched_judgeable() {
  local k="$1" numa="$2" mem="$3" i t sc nd mk kc cpuok=0 maxmem=0 maxcpu=0 maxnode=0 v
  _NJ_CODE=""; _NJ_NEED=""; _NJ_MAX=""
  (( ${SCAP_N:-0} > 0 )) || return 0
  [[ "$k" =~ ^[0-9]+$ && "$k" -ge 1 ]] || k=1
  for (( i = 0; i < SCAP_N; i++ )); do
    t="${SCAP_TOT[i]}"; sc="${SCAP_SC[i]}"; nd="${SCAP_NODE[i]}"; mk="${SCAP_MEM[i]}"
    [[ "$sc" =~ ^[0-9]+$ && "$sc" -ge 1 ]] || sc=1
    [[ "$nd" =~ ^[0-9]+$ ]] || nd="$t"
    (( t * sc > maxcpu )) && maxcpu=$(( t * sc ))
    (( nd * sc > maxnode )) && maxnode=$(( nd * sc ))
    [[ "$mk" =~ ^[0-9]+$ ]] && { v=$(( mk / 1024 - 4096 - 64 )); (( v > maxmem )) && maxmem=$v; }
    kc=$(( (k + sc - 1) / sc ))                       # a CPU sozinha cabe neste juiz?
    if [[ "$numa" == y ]]; then (( kc <= nd )) || continue; else (( kc <= t )) || continue; fi
    cpuok=1
    _eff_width "$k" "$mem" "$sc" "$t" "$mk"            # e com a memória (a largura efetiva do claim)?
    (( _EKS >= 1 )) || continue
    if [[ "$numa" == y ]]; then (( _EKS <= nd )) && return 0; else (( _EKS <= t )) && return 0; fi
  done
  if (( cpuok )); then _NJ_CODE=memory; _NJ_NEED="$mem"; _NJ_MAX="$maxmem"
  elif [[ "$numa" == y ]] && (( k <= maxcpu )); then _NJ_CODE=numa; _NJ_NEED="$k"; _NJ_MAX="$maxnode"
  else _NJ_CODE=cpus; _NJ_NEED="$k"; _NJ_MAX="$maxcpu"; fi
  return 0
}
# sched_cap_json -> {judges, max_mem_mb, slot_mem_mb, max_cpus, max_node_cpus} dos juízes de sched_cap_load:
# o maior MEMLIMITMB que um juiz aceita (máquina inteira), o maior que cabe em UM slot (acima disso o
# problema ocupa mais slots por teste), e as CPUs da maior máquina / do maior nó. Para o aviso do editor.
sched_cap_json() {
  local i t sc nd mk v mm=0 ms=0 mc=0 mn=0
  for (( i = 0; i < ${SCAP_N:-0}; i++ )); do
    t="${SCAP_TOT[i]}"; sc="${SCAP_SC[i]}"; nd="${SCAP_NODE[i]}"; mk="${SCAP_MEM[i]}"
    [[ "$sc" =~ ^[0-9]+$ && "$sc" -ge 1 ]] || sc=1; [[ "$nd" =~ ^[0-9]+$ ]] || nd="$t"
    (( t * sc > mc )) && mc=$(( t * sc )); (( nd * sc > mn )) && mn=$(( nd * sc ))
    if [[ "$mk" =~ ^[0-9]+$ ]]; then
      v=$(( mk / 1024 - 4096 )); (( v - 64 > mm )) && mm=$(( v - 64 ))
      (( t >= 1 )) && { v=$(( v / t - 64 )); (( v > ms )) && ms=$v; }
    fi
  done
  printf '{"judges":%d,"max_mem_mb":%d,"slot_mem_mb":%d,"max_cpus":%d,"max_node_cpus":%d}' "${SCAP_N:-0}" "$mm" "$ms" "$mc" "$mn"
}

# sched_policy <host> : ecoa "parallel\x01cushion\x01share_max\x01parallel_max" de judges-config.json:
# a chave "*" guarda a política global {parallel:off|auto, cushion, share_max}; a entrada do host,
# `parallel_max`. Nada disso vai ao agente (fora do cfg_hash — ver judges_config_for).
sched_policy() {
  local host="$1" jconf out
  jconf="${JUDGES_CONFIG_FILE:-$CONTESTSDIR/treino/var/judges-config.json}"
  out="$(jq -j --arg h "$host" --argjson pmd "$PARALLEL_MAX_DEFAULT" '
      [ ((.["*"].parallel // "off") | if . == "auto" then "auto" else "off" end),
        ((.["*"].cushion // 0.25) | tonumber? // 0.25 | tostring),
        ((.["*"].share_max // 0.5) | tonumber? // 0.5 | tostring),
        ((.[$h].parallel_max // $pmd) | tonumber? // $pmd | floor | if . < 1 then 1 else . end | tostring) ]
      | join("\u0001")' "$jconf" 2>/dev/null)"
  [[ -n "$out" ]] || out=$'off\x010.25\x010.5\x01'"$PARALLEL_MAX_DEFAULT"
  printf '%s' "$out"
}

# _cmeta_v2 <jobfile> : (re)escreve e ecoa o sidecar v2 do job:
#   v2\x01prob\x01need\x01lang\x01hosts\x01k\x01numa\x01par\x01m\x01memmb\x01enq\x01decl
# (decl = "host:epoch,…" das recusas). k/numa/par/m/memmb do conf do pacote (memo por problema,
# PKGPAR — o chamador declara `local -A PKGPAR` p/ o escopo de um claim).
_cmeta_v2() {
  local f="$1" base prob need jl hosts enq decl pp
  base="$(jq -j '[ (.problem_id // ""), (.need_capability // ""), ((.lang // "") | ascii_downcase),
                   ((.allowed_hosts // []) | join(",")), ((.enqueued_at // "") | tostring),
                   ((.declined // {}) | to_entries | map("\(.key):\(.value)") | join(",")) ]
                 | join("\u0001")' "$f" 2>/dev/null)" || return 1
  IFS=$'\x01' read -r prob need jl hosts enq decl <<<"$base"
  if [[ -n "${PKGPAR[$prob]+x}" ]]; then pp="${PKGPAR[$prob]}"
  else pp="$(sched_pkg_par "$prob")"; PKGPAR[$prob]="$pp"; fi
  [[ "$enq" =~ ^[0-9]+$ ]] || { enq="${f##*/}"; enq="${enq%%_*}"; [[ "$enq" =~ ^[0-9]+$ ]] || enq=0; }
  local meta; meta="$(printf 'v2\x01%s\x01%s\x01%s\x01%s\x01%s\x01%s\x01%s' "$prob" "$need" "$jl" "$hosts" "$pp" "$enq" "$decl")"
  printf '%s' "$meta" > "$f.cmeta" 2>/dev/null
  printf '%s' "$meta"
}
# _cmeta_load <jobfile> : põe em _CMETA o sidecar v2 do job — o guardado, ou REFEITO quando falta, é de
# versão velha ou o conf do PACOTE mudou depois dele. Sem a comparação com o conf, corrigir o
# MEMLIMITMB/CPUNEEDED de um problema não destravava o job que já estava na fila (o sidecar guardava o
# valor velho para sempre — incidente de 30/09/2026). É a leitura dos TRÊS leitores (q_claim,
# _wide_jobs, q_claim_id). Custo no caminho comum: um `-nt` (stat, sem fork). rc 1 = job ilegível.
_cmeta_load() {
  local f="$1" rest prob conf
  _CMETA=""; [[ -s "$f.cmeta" ]] && _CMETA="$(<"$f.cmeta")"
  if [[ "$_CMETA" == v2$'\x01'* ]]; then
    rest="${_CMETA#v2$'\x01'}"; prob="${rest%%$'\x01'*}"; prob="${prob//\//#}"
    [[ -n "${MOJ_PROBLEMS_DIR:-}" && "$prob" == *#* ]] || return 0
    conf="$MOJ_PROBLEMS_DIR/${prob%%#*}/${prob#*#}/conf"
    [[ "$conf" -nt "$f.cmeta" ]] || return 0
  fi
  _CMETA="$(_cmeta_v2 "$f")" || return 1
  return 0
}

# _hardmem <memmb> -> MB que a jaula pode pedir ao cgroup (regra do cage-run/b-a-t: max(600, MEMLIMITMB+64))
_hardmem() { local m="$1"; [[ "$m" =~ ^[0-9]+$ ]] || m=0; local h=$(( m + 64 )); (( h < 600 )) && h=600; printf '%s' "$h"; }

# ------------------------------------------------------------------- fila de jobs
# q_enqueue <id> <priority> <job-json> [atraso-s] : enfileira na banda da prioridade. A banda é FIFO
# pelo NOME (`<epoch>_<id>.json`); com ATRASO o nome leva `agora+atraso` — o job entra na MESMA banda
# como se tivesse chegado depois (menos prioridade p/ o time da prova com muitas pendentes, judged.sh
# intake_enqueue). Atraso NÃO é idade: as carências do q_claim usam o `enq` real do `.cmeta`
# (`enqueued_at` do job); só a ordem da fila e a promoção de famintos leem o nome.
q_enqueue() {
  local id="$1" prio="$2" json="$3" delay="${4:-0}" band
  [[ "$delay" =~ ^[0-9]+$ ]] || delay=0
  band="$(sched_band_of "$prio")"
  sched_init_dirs
  local base="$(( EPOCHSECONDS + delay ))_${id}.json"
  local tmp="$QUEUEDIR/$band/.${base}.tmp"
  printf '%s' "$json" > "$tmp" && mv -f "$tmp" "$QUEUEDIR/$band/$base"
}

# q_claim <host> <capability> <problems-json> [langs-json] [max=1] : reivindica até MAX SLOTS de
# jobs que o worker pode rodar (capacidade + pool + linguagem + cache + LARGURA), atômico sob
# flock. Ecoa um job POR LINHA (jq -c; o enqueue grava single-line).
#
# COMPLEXIDADE (a lição da bancada, 30/08): a versão original fazia 2-6 jq POR JOB
# EXAMINADO e recomeçava a varredura DO ZERO a cada job reivindicado — com um prefixo de
# jobs presos por pool (o retrato da Maratona: 500 presos na frente), o custo era
# O(prefixo) POR CLAIM e a vazão medida caiu a 30 veredictos/min. Agora:
#   1. a decisão ESTÁTICA de cada job (problema, capacidade, pool, linguagem, LARGURA k/numa/
#      par/m/mem do conf do pacote, época de entrada, recusas) mora num sidecar `<job>.cmeta`
#      v2 escrito na PRIMEIRA visita (self-heal: 1 jq por job NA VIDA; sidecar v1 é reescrito, e o
#      de job cujo conf de pacote mudou depois dele também — _cmeta_load);
#      as varreduras seguintes leem o sidecar com $(<…), ZERO processos por job pulado;
#   2. o claim é em LOTE: UMA varredura por chamada colhe até MAX SLOTS (era MAX jobs);
#   3. glob ordenado (epoch de 10 dígitos ⇒ ordem lexical = cronológica) no lugar de
#      find|sort. Os GRACEs (relógio) continuam no bash.
#
# LARGURA (24/09/2026; env do chamador — o heartbeat as tira do registro/beat/judges-config):
#   QC_SLOT_CPUS       cpus do menor slot do juiz (vazio/0 = juiz LEGADO: só k=1, sem campos novos)
#   QC_MAX_FREE_GROUP  maior nº de slots livres num nó (job SAMENUMA só cabe se k_slots ≤ isso)
#   QC_TOTAL_SLOTS / QC_MEM_KB   p/ a regra de memória: HARDMEM ≤ (mem−4 GB)×k_slots/total_slots — e
#                      a MEMÓRIA É LARGURA (_eff_width): o job leva os slots que comportam o
#                      MEMLIMITMB (test_cpus sobe junto); nem a máquina inteira ⇒ pula (infeasible_sweep)
#   QC_POLICY (off|auto) QC_CUSHION QC_SHARE_MAX QC_PARALLEL_MAX   → par_max (expansão)
# Um job cabe se passa nas 4 portas de sempre E k_slots ≤ slots restantes (E nó, E memória);
# não cabe ⇒ pula (backfill: um job mais estreito passa na frente — o HOLD cuida do largo).
# SEM teto de varredura (pular custa zero forks; teto deixaria a fila atrás de um prefixo preso).
# Job reivindicado leva {test_cpus, same_numa, slots (= P×k_slots), par_max, par_cap}; a soma
# de `.slots` dos ecoados é o que o juiz ocupou. par_max > 1 SÓ com política auto, job que
# permite (ALLOWPARALLELTEST), varredura terminada com a FILA VAZIA e sem job pulado por porta de
# TEMPO/largura (quem foi pulado vai querer slot em segundos): a sobra além do colchão
# (ceil(total×cushion)) é repartida em rodízio (+k_slots por vez) até min(m, parallel_max) grupos
# e share_max×total slots por job. Fora disso par_max = 1.
q_claim() {
  local host="$1" cap="$2" probs="$3" langs="${4:-[]}" max="${5:-1}"
  valid_hostname "$host" || return 1
  [[ "$max" =~ ^[0-9]+$ ]] || max=1
  sched_init_dirs
  (
    flock 9 || exit 0
    set +o noglob   # subshell: o noglob da API não vaza; glob = listagem ordenada s/ fork
    local band f dest base ts meta ver prob need jl hosts probhot k numa par m enq memmb decl
    local pk v ks korig now=$EPOCHSECONDS
    local slots_left="$max" skipped_time=0 queue_empty=1 legacy=0 sc="${QC_SLOT_CPUS:-0}"
    local mfg="${QC_MAX_FREE_GROUP:-}" tot="${QC_TOTAL_SLOTS:-}" memkb="${QC_MEM_KB:-}"
    [[ "$sc" =~ ^[0-9]+$ && "$sc" -ge 1 ]] || { legacy=1; sc=1; }
    [[ "$mfg" =~ ^[0-9]+$ ]] || mfg=""
    [[ "$tot" =~ ^[0-9]+$ && "$tot" -ge 1 ]] || tot=""
    [[ "$memkb" =~ ^[0-9]+$ ]] || memkb=""
    local -A PKGPAR=()
    # lote reivindicado (p/ o par_max no fim): dest, k_slots, k, numa, par, m
    local -a C_DEST=() C_KS=() C_K=() C_KORIG=() C_NUMA=() C_PAR=() C_M=() C_GROUPS=()
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
        (( slots_left <= 0 )) && { queue_empty=0; break 2; }
        # sidecar de decisão estática (v2); v1/ausente/conf do pacote mais novo ⇒ reescrito
        _cmeta_load "$f" || continue; meta="$_CMETA"
        IFS=$'\x01' read -r ver prob need jl hosts k numa par m memmb enq decl <<<"$meta"
        [[ -z "$need" || "$need" == "$cap" ]] || continue
        base="${f##*/}"
        # pool de juízes (allowed_hosts): ESTRITO por default (POOL_GRACE=0) — pool
        # offline segura a fila de propósito; POOL_GRACE>0 libera como fallback.
        # As carências contam a idade REAL (`enq` do .cmeta = enqueued_at do job, o relógio do
        # _wide_jobs e do queue_stuck), nunca o prefixo do nome: o nome é ordem de fila — vem
        # adiantado no job com atraso (q_enqueue) e é refeito na promoção/devolução.
        if [[ -n "$hosts" && ",$hosts," != *",$host,"* ]]; then
          ts="$enq"
          { (( POOL_GRACE > 0 )) && [[ "$ts" =~ ^[0-9]+$ ]] \
              && (( now - ts > POOL_GRACE )); } || continue
        fi
        # route by language: sem o toolchain espera LANG_GRACE; depois pega como fallback.
        if [[ -n "$LSET" ]]; then
          case "$jl" in py2|py3) jl=py;; esac
          if [[ -n "$jl" && "$LSET" != *" $jl "* ]]; then
            ts="$enq"
            [[ "$ts" =~ ^[0-9]+$ ]] && (( now - ts <= LANG_GRACE )) && { skipped_time=1; continue; }
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
          ts="$enq"
          [[ "$ts" =~ ^[0-9]+$ ]] && (( now - ts <= COLD_GRACE )) && { skipped_time=1; continue; }
        fi
        # recusa recente DESTE host (decline): pula por DECLINE_BACKOFF
        if [[ -n "$decl" && ",$decl," == *",$host:"* ]]; then
          v=",$decl"; v="${v##*,$host:}"; v="${v%%,*}"
          [[ "$v" =~ ^[0-9]+$ ]] && (( now - v < DECLINE_BACKOFF )) && { skipped_time=1; continue; }
        fi
        # LARGURA EFETIVA (CPU e MEMÓRIA, _eff_width): juiz legado só 1 slot; nem a máquina inteira
        # comporta a memória ⇒ pula (o infeasible_sweep dá o Judge Error); k_slots ≤ sobra;
        # SAMENUMA ⇒ ≤ maior grupo livre
        [[ "$k" =~ ^[0-9]+$ && "$k" -ge 1 ]] || k=1
        korig=$k                                          # o CPUNEEDED; o resto da largura é da memória
        _eff_width "$k" "$memmb" "$sc" "$tot" "$memkb"
        (( _EKS == 0 )) && { skipped_time=1; continue; }
        k=$_EK; ks=$_EKS
        (( legacy && ks > 1 )) && continue
        (( ks > slots_left )) && { skipped_time=1; continue; }
        [[ "$numa" == y && -n "$mfg" ]] && (( ks > mfg )) && { skipped_time=1; continue; }
        mkdir -p "$ASSIGNEDDIR/$host" 2>/dev/null
        dest="$ASSIGNEDDIR/$host/$base"
        if mv "$f" "$dest" 2>/dev/null; then
          rm -f "$f.cmeta" 2>/dev/null
          C_DEST+=("$dest"); C_KS+=("$ks"); C_K+=("$k"); C_KORIG+=("$korig"); C_NUMA+=("$numa"); C_PAR+=("$par"); C_M+=("$m"); C_GROUPS+=(1)
          slots_left=$(( slots_left - ks ))
          [[ "$numa" == y && -n "$mfg" ]] && mfg=$(( mfg - ks ))
        fi
      done
      # sidecar órfão (job saiu por requeue/promote sem levar o cmeta): gc barato
      for f in "$QUEUEDIR/$band"/*.cmeta; do
        [[ -e "$f" && ! -f "${f%.cmeta}" ]] && rm -f "$f" 2>/dev/null
      done
    done
    # ---- par_max: expansão SÓ com política auto, fila vazia e nada pulado por tempo/largura ----
    local n=${#C_DEST[@]} i pmax="${QC_PARALLEL_MAX:-$PARALLEL_MAX_DEFAULT}" cushion sobra share limit grew
    [[ "$pmax" =~ ^[0-9]+$ && "$pmax" -ge 1 ]] || pmax=$PARALLEL_MAX_DEFAULT
    if (( n > 0 && legacy == 0 )) && [[ "${QC_POLICY:-off}" == auto ]] && (( queue_empty && skipped_time == 0 )) && [[ -n "$tot" ]]; then
      cushion="$(awk -v t="$tot" -v c="${QC_CUSHION:-0.25}" 'BEGIN{x=t*c; printf "%d", (x==int(x))?x:int(x)+1}')"
      share="$(awk -v t="$tot" -v s="${QC_SHARE_MAX:-0.5}" 'BEGIN{printf "%d", t*s}')"
      sobra=$(( slots_left - cushion ))
      grew=1
      while (( sobra > 0 && grew )); do
        grew=0
        for (( i=0; i<n; i++ )); do
          [[ "${C_PAR[i]}" == y ]] || continue
          limit="${C_M[i]:-$pmax}"; (( limit > pmax )) && limit=$pmax
          (( C_GROUPS[i] >= limit )) && continue
          (( (C_GROUPS[i] + 1) * C_KS[i] > share )) && continue
          (( sobra < C_KS[i] )) && continue
          C_GROUPS[i]=$(( C_GROUPS[i] + 1 )); sobra=$(( sobra - C_KS[i] )); grew=1
        done
      done
    fi
    # ---- carimba e ecoa (campos novos só p/ juiz NOVO) ----
    for (( i=0; i<n; i++ )); do
      dest="${C_DEST[i]}"; local tmp="$dest.tmp" cap_i="${C_M[i]:-$pmax}"
      (( cap_i > pmax )) && cap_i=$pmax
      if (( legacy )); then
        jq -c --arg h "$host" --argjson now "$now" '. + {assigned_to:$h, assigned_at:$now}' "$dest" > "$tmp" 2>/dev/null && mv -f "$tmp" "$dest"
      else
        # cpu_needed (o CPUNEEDED) só p/ as TELAS: test_cpus > cpu_needed = slots a mais pela memória
        jq -c --arg h "$host" --argjson now "$now" --argjson k "${C_K[i]}" --argjson nm "$([[ "${C_NUMA[i]}" == y ]] && echo true || echo false)" \
           --argjson sl "$(( C_GROUPS[i] * C_KS[i] ))" --argjson pm "${C_GROUPS[i]}" --argjson pc "$cap_i" --argjson kn "${C_KORIG[i]}" \
           '. + {assigned_to:$h, assigned_at:$now, test_cpus:$k, same_numa:$nm, slots:$sl, par_max:$pm, par_cap:$pc, cpu_needed:$kn}' "$dest" > "$tmp" 2>/dev/null && mv -f "$tmp" "$dest"
      fi
      cat "$dest"; printf '\n'
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

# upd_find_calibrate <problem_id> [pending] : ecoa o reqid de uma calibração JÁ pendente (e, sem o
# 2º argumento, também em execução) p/ esse problema (ou nada). Conteúdo via stdin (find -exec cat),
# nunca por argv — ARG_MAX-safe com qualquer tamanho de fila.
#
# ⚠ O DEDUP DO cal_request OLHA SÓ O PENDENTE (21/09/2026). O pedido que está na FILA ainda vai
# baixar a versão ATUAL quando for reivindicado — deduplicar contra ele continua certo. Mas o que já
# está EM EXECUÇÃO baixou a versão ANTERIOR: se o autor salva de novo no meio (o fluxo normal de quem
# está consertando solução) e pede outra calibração, engolir o pedido significa que a versão nova
# NUNCA é calibrada — o relatório que chega é da velha, a tela marca tudo `stale` e o autor fica
# clicando sem entender (relatos do José Leite e do Arthur Botelho). No pior caso isto põe 1 job
# extra por job em voo (o clique seguinte volta a deduplicar contra o pendente), e a trava de verdade
# contra o entupimento de 15/07 segue sendo o dedup do AGENTE: full do MESMO checksum = "pedido
# satisfeito", pulada sem rodar nada.
upd_find_calibrate() {
  local r
  r="$( { find "$UPDATESDIR/pending" -maxdepth 1 -name '*.json' -exec cat {} + 2>/dev/null
          [[ "${2:-}" == pending ]] || find "$UPDATESDIR/inprogress" -mindepth 2 -name '*.json' -exec cat {} + 2>/dev/null; } \
        | jq -r --arg t "$1" 'select(.kind=="calibrate" and .target==$t and ((.origin // "") != "command")) | .reqid' 2>/dev/null \
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
    local ex; ex="$(upd_find_calibrate "$2" pending)"
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
# LARGURA (24/09/2026): calibração de problema com CPUNEEDED=k ocupa k_slots (um teste por vez em
# k CPUs); só é entregue se cabe (env QC_SLOT_CPUS/QC_FREE/QC_MAX_FREE_GROUP do heartbeat; juiz
# legado só k=1) e sai com {test_cpus, same_numa, slots}. Não cabe ⇒ segue p/ o próximo pendente.
upd_claim() {
  local host="$1" f base dest t busy k numa par m mem ks legacy=0 sc="${QC_SLOT_CPUS:-0}" free="${QC_FREE:-1}" mfg="${QC_MAX_FREE_GROUP:-}"
  valid_hostname "$host" || return 1
  [[ "$sc" =~ ^[0-9]+$ && "$sc" -ge 1 ]] || { legacy=1; sc=1; }
  [[ "$free" =~ ^[0-9]+$ ]] || free=1
  [[ "$mfg" =~ ^[0-9]+$ ]] || mfg=""
  _mkd "$UPDATESDIR/pending" "$UPDATESDIR/inprogress/$host"      # todo beat com slot livre
  (
    flock 9 || exit 0
    while IFS= read -r f; do
      [[ -f "$f" ]] || continue
      k=1; numa=n
      if jq -e '.kind=="calibrate"' "$f" >/dev/null 2>&1; then
        t="$(jq -r '.target // ""' "$f" 2>/dev/null)"
        if [[ -n "$t" ]]; then
          # marcador de calibração DIRIGIDA (origin=="command") não serializa nada: ele só existe
          # p/ aparecer na tela, e o caminho targeted sempre correu em paralelo com o genérico.
          busy="$(find "$UPDATESDIR/inprogress" -mindepth 2 -name '*.json' -exec cat {} + 2>/dev/null \
                  | jq -r --arg t "$t" 'select(.kind=="calibrate" and .target==$t and ((.origin // "") != "command")) | .reqid' 2>/dev/null | head -n1)"
          [[ -n "$busy" ]] && continue   # já calibrando em algum lugar: espera a vez
          IFS=$'\x01' read -r k numa par m mem < <(sched_pkg_par "$t")
          (( legacy && k > 1 )) && continue
          ks="$(_kslots "$k" "$sc")"
          (( ks > free )) && continue
          [[ "$numa" == y && -n "$mfg" ]] && (( ks > mfg )) && continue
        fi
      fi
      base="$(basename "$f")"; dest="$UPDATESDIR/inprogress/$host/$base"
      if mv "$f" "$dest" 2>/dev/null; then
        local tmp="$dest.tmp"   # carimba claimed_at p/ o upd_reconcile detectar pedido preso
        if (( legacy )); then
          jq -c --argjson now "$EPOCHSECONDS" '. + {claimed_at:$now}' "$dest" > "$tmp" 2>/dev/null && mv -f "$tmp" "$dest"
        else
          jq -c --argjson now "$EPOCHSECONDS" --argjson k "$k" --argjson nm "$([[ "$numa" == y ]] && echo true || echo false)" \
             --argjson sl "$(_kslots "$k" "$sc")" '. + {claimed_at:$now, test_cpus:$k, same_numa:$nm, slots:$sl}' "$dest" > "$tmp" 2>/dev/null && mv -f "$tmp" "$dest"
        fi
        cat "$dest"; exit 0
      fi
    done < <(find "$UPDATESDIR/pending" -maxdepth 1 -name '*.json' 2>/dev/null | sort)
  ) 9>"$UPDATESDIR/.lock"
}

upd_done() { rm -f "$UPDATESDIR/inprogress/$1/$2.json" 2>/dev/null; }   # $1=host $2=reqid

# ===== MARCADOR da calibração DIRECIONADA (`hosts:[…]`) — só p/ APARECER ========================
# O comando `calibrate` SOME do diretório ao ser entregue no heartbeat, e a partir daí o servidor
# não sabia mais que aquele juiz está calibrando: o Painel não dizia "calibrando…", o contador
# `calib_targeted` voltava a 0 e o `moj judges show` dizia "rodando: nada" — enquanto o juiz gastava
# minutos (relato do Ribas, 20/09/2026; medido: pedido às 20:19:57, contador nunca saiu de 0, os
# juízes reportaram às 20:20:05). O agente não conta no heartbeat o que está rodando, então quem tem
# de lembrar é quem entregou: `cmd_claim` deixa um `cmd-<cmdid>.json` em inprogress/<host>/, no MESMO
# formato de um update, e as três telas passam a vê-lo sem uma linha de código novo.
# ⚠ É DISPLAY-ONLY, e as três regras abaixo é que o mantêm inofensivo:
#   1. o ESCALONAMENTO o ignora (`origin=="command"` é filtrado no dedup do cal_request e na
#      serialização por target do upd_claim) — o caminho direcionado segue exatamente como era;
#   2. o heartbeat NÃO o re-carimba (upd_touch_host pula `cmd-*`): marcador órfão (juiz morreu no
#      meio, calibração falhou sem reportar) morre no UPD_TTL em vez de virar "calibrando…" eterno;
#   3. NUNCA volta p/ `pending` (upd_reconcile o APAGA): o trabalho de verdade já foi entregue —
#      re-enfileirar criaria uma calibração fantasma que ninguém pediu.
# Quem o apaga no caso feliz é o próprio juiz, ao REPORTAR a calibração (tl-report/calib-report).
upd_cmd_mark() {  # <host> <problem_id> <cmdid> [by]
  local host="$1" id="$2" cmdid="$3" by="${4:-?}" d tmp
  valid_hostname "$host" || return 0
  [[ -n "$id" && -n "$cmdid" ]] || return 0
  d="$UPDATESDIR/inprogress/$host"; mkdir -p "$d" 2>/dev/null || return 0
  tmp="$d/.cmd-$cmdid.tmp"
  jq -cn --arg r "cmd-$cmdid" --arg t "$id" --arg by "$by" --argjson now "$EPOCHSECONDS" \
    '{reqid:$r, kind:"calibrate", origin:"command", repo:"", target:$t, requested_by:$by,
      note:"calibrate dirigida", requested_at:$now, claimed_at:$now}' > "$tmp" 2>/dev/null \
    && mv -f "$tmp" "$d/cmd-$cmdid.json" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  return 0
}
# upd_cmd_clear <host> <problem_id> : o juiz reportou a calibração -> o marcador cumpriu o papel.
upd_cmd_clear() {
  local host="$1" id="$2" f
  valid_hostname "$host" || return 0
  [[ -n "$id" && -d "$UPDATESDIR/inprogress/$host" ]] || return 0
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    [[ "$(jq -r '.target // ""' "$f" 2>/dev/null)" == "$id" ]] && rm -f "$f"
  done < <(find "$UPDATESDIR/inprogress/$host" -maxdepth 1 -name 'cmd-*.json' 2>/dev/null)
  return 0
}

# upd_touch_host <host> : re-carimba o MTIME das calibrações em execução deste host.
# Chamado a cada heartbeat de agente NOVO (que manda `status` e tem teto dinâmico + kill):
# enquanto o juiz está VIVO, uma calibração longa LEGÍTIMA (que pode passar de UPD_TTL) não é
# re-enfileirada — o UPD_TTL vira proteção só contra host morto/agente antigo.
# `touch -c` (NUNCA cria): a versão anterior reescrevia o JSON (jq > tmp && mv) e RESSUSCITAVA
# o arquivo quando o upd_done o removia entre a leitura e o mv — nascia um claim FANTASMA que,
# re-tocado a cada beat, nunca expirava e (com a serialização por-target) bloqueava calibrações
# futuras do problema. O claimed_at do JSON fica intacto (idade real na UI); o TTL lê o mtime.
# ⚠ MARCADOR de dirigida (`cmd-*.json`) NÃO é tocado: ele não tem quem o feche em caso de falha
# (o agente só reporta calibração que terminou), então tem de poder expirar sozinho.
upd_touch_host() {
  local host="$1"
  [[ -d "$UPDATESDIR/inprogress/$host" ]] || return 0
  find "$UPDATESDIR/inprogress/$host" -maxdepth 1 -name '*.json' ! -name 'cmd-*.json' -exec touch -c {} + 2>/dev/null
  return 0
}

# upd_reconcile : devolve à fila (pending) calibrações que ficaram presas em inprogress —
# host morreu (reiniciou no meio) ou passou de UPD_TTL sem terminar. Sem isto, uma calibração
# interrompida trava p/ sempre e a fila seca ("calibração não é refeita"). Auto-throttle (~15s).
upd_reconcile() {
  _mkd "$UPDATESDIR/pending" "$UPDATESDIR/inprogress"                 # todo beat (antes do throttle)
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
          # marcador de dirigida: o trabalho JÁ foi entregue ao juiz — re-enfileirar criaria uma
          # calibração que ninguém pediu. Vencido, ele só some da tela.
          if [[ "$base" == cmd-*.json ]]; then rm -f "$f" 2>/dev/null
          else mv -f "$f" "$UPDATESDIR/pending/$base" 2>/dev/null; fi
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
  # LARGURA: `calibrate` de problema com CPUNEEDED=k só sai se k_slots cabe (QC_* do heartbeat);
  # não cabe ⇒ fica no diretório e o próximo comando é examinado. Sai com {test_cpus,same_numa,slots}.
  local host="$1" f out k numa par m mem ks legacy=0 sc="${QC_SLOT_CPUS:-0}" free="${QC_FREE:-1}" mfg="${QC_MAX_FREE_GROUP:-}"
  valid_hostname "$host" || return 1
  [[ -d "$CMDDIR/$host" ]] || return 0
  [[ "$sc" =~ ^[0-9]+$ && "$sc" -ge 1 ]] || { legacy=1; sc=1; }
  [[ "$free" =~ ^[0-9]+$ ]] || free=1
  [[ "$mfg" =~ ^[0-9]+$ ]] || mfg=""
  _mkd "$CMDDIR/$host"
  out="$( (
    flock 9 || exit 0
    while IFS= read -r f; do
      [[ -f "$f" ]] || continue
      if [[ "$(jq -r '.action // ""' "$f" 2>/dev/null)" == calibrate ]]; then
        IFS=$'\x01' read -r k numa par m mem < <(sched_pkg_par "$(jq -r '.id // ""' "$f" 2>/dev/null)")
        (( legacy && k > 1 )) && continue
        ks="$(_kslots "$k" "$sc")"
        (( ks > free )) && continue
        [[ "$numa" == y && -n "$mfg" ]] && (( ks > mfg )) && continue
        if (( legacy )); then cat "$f"
        else jq -c --argjson k "$k" --argjson nm "$([[ "$numa" == y ]] && echo true || echo false)" --argjson sl "$ks" \
               '. + {test_cpus:$k, same_numa:$nm, slots:$sl}' "$f" 2>/dev/null; fi
        rm -f "$f"; exit 0
      fi
      cat "$f"; rm -f "$f"; exit 0
    done < <(find "$CMDDIR/$host" -maxdepth 1 -name '*.json' 2>/dev/null | sort)
  ) 9>"$CMDDIR/$host/.lock" )"
  [[ -n "$out" ]] || return 0
  # calibrate ENTREGUE deixa MARCADOR (o comando some do diretório; sem isto ninguém mais sabe
  # que este juiz está calibrando — ver upd_cmd_mark).
  if [[ "$(jq -r '.action // ""' <<<"$out" 2>/dev/null)" == calibrate ]]; then
    upd_cmd_mark "$host" "$(jq -r '.id // ""' <<<"$out" 2>/dev/null)" \
                 "$(jq -r '.cmdid // ""' <<<"$out" 2>/dev/null)" "$(jq -r '.by // "?"' <<<"$out" 2>/dev/null)"
  fi
  printf '%s\n' "$out"
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

# =========================== HOLD / DECLINE / INFACTÍVEL (largura k, 24/09/2026) ===================
# Job largo (k_slots > 1) nunca acha k slots livres num juiz que vive cheio de jobs de 1 slot: o
# claim por largura o PULA (backfill) e ele morreria de fome. O HOLD segura UM juiz: enquanto há
# `run/hold/<host>.json {job,k_slots,numa,since}` o juiz não recebe jobs/updates novos (comandos de
# admin passam) e, assim que tem `k_slots` livres (no nó, se numa), recebe o job segurado. Regras:
# 1 hold por juiz; com a banda 020-prova não vazia, 1 hold no total (prova é delicada); solta
# quando o job foi reivindicado por qualquer juiz, o juiz saiu de reg_live_hosts ou HOLD_TTL
# venceu (recriado se o job segue pendente). Juiz único: um hold pausa o claim por até a duração
# de um job — é o preço de não deixar o largo morrer.
# INFACTÍVEL: job largo pendente há INFEASIBLE_AFTER com ≥1 juiz vivo e NENHUM juiz vivo com a
# capacidade (total_slots×slot_cpus ≥ k; numa: maior nó ≥ k) ⇒ Judge Error pelo spool, como o
# /judge/result faria (host "scheduler"). Sem juiz vivo nenhum: espera, como sempre.

# _reg_rows : uma linha por juiz do registry, "host\x01cap\x01langs\x01total\x01free\x01slot_cpus\x01maxnode\x01mfg\x01status\x01live\x01mem_kb"
# (langs separadas por espaço; slot_cpus 0 = legado; maxnode = maior slots_by_node; live 1|0)
_reg_rows() {
  local now=$EPOCHSECONDS
  find "$REGISTRYDIR" -maxdepth 1 -name '*.json' -exec cat {} + 2>/dev/null \
    | jq -r --argjson now "$now" --argjson ttl "$REG_TTL" '
        [ .host, (.capability // "pos"), ((.langs // []) | map(if .=="py2" or .=="py3" then "py" else . end) | join(" ")),
          ((.total_slots // 1)|tostring), ((.free_slots // 0)|tostring), ((.slot_cpus // 0)|tostring),
          (((.slots_by_node // {}) | [.[]] | max) // (.total_slots // 1) | tostring),
          ((.max_free_group // 0)|tostring), (.status // ""),
          (if (.last_seen // 0) >= ($now - $ttl) then "1" else "0" end),
          ((.mem_kb // "")|tostring) ] | join("\u0001")' 2>/dev/null
}

# _wide_jobs : jobs POSSIVELMENTE largos pendentes (k>1, ou com MEMLIMITMB — a memória também é largura e
# depende do juiz: quem decide é o _eff_width de cada varredura), "file\x01prob\x01need\x01lang\x01hosts\x01k\x01numa\x01enq\x01memmb"
_wide_jobs() {
  local band f meta ver prob need jl hosts k numa par m enq memmb decl
  local -A PKGPAR=()
  set +o noglob
  for band in "${SCHED_BANDS[@]}"; do
    for f in "$QUEUEDIR/$band"/*.json; do
      [[ -f "$f" ]] || continue
      _cmeta_load "$f" || continue; meta="$_CMETA"
      IFS=$'\x01' read -r ver prob need jl hosts k numa par m memmb enq decl <<<"$meta"
      { [[ "$k" =~ ^[0-9]+$ && "$k" -gt 1 ]] || [[ "$memmb" =~ ^[0-9]+$ && "$memmb" -gt 0 ]]; } || continue
      printf '%s\x01%s\x01%s\x01%s\x01%s\x01%s\x01%s\x01%s\x01%s\n' "$f" "$prob" "$need" "$jl" "$hosts" "$k" "$numa" "$enq" "$memmb"
    done
  done
}

# hold_get <host> : ecoa o hold do host (JSON) se ele ainda vale; poda hold vencido ou cujo job
# já saiu da fila. Nada ecoado = sem hold.
hold_get() {
  local host="$1" f="$HOLDDIR/$1.json" id since now=$EPOCHSECONDS
  [[ -f "$f" ]] || return 0
  id="$(jq -r '.job // ""' "$f" 2>/dev/null)"; since="$(jq -r '.since // 0' "$f" 2>/dev/null)"
  [[ "$since" =~ ^[0-9]+$ ]] || since=0
  if [[ -z "$id" ]] || (( now - since > HOLD_TTL )) || [[ -z "$(find "$QUEUEDIR" -mindepth 2 -name "*_$id.json" -print -quit 2>/dev/null)" ]]; then
    rm -f "$f" 2>/dev/null; return 0
  fi
  cat "$f"
}
hold_clear() { rm -f "$HOLDDIR/$1.json" 2>/dev/null; return 0; }

# q_claim_id <host> <id> : reivindica UM job específico da fila (o job segurado), com largura
# k_slots do QC_SLOT_CPUS, par_max 1 — e o ecoa. Nada ecoado = o job não está mais na fila.
q_claim_id() {
  local host="$1" id="$2" f dest base meta ver prob need jl hosts k numa par m enq memmb decl ks tmp
  local sc="${QC_SLOT_CPUS:-1}"; [[ "$sc" =~ ^[0-9]+$ && "$sc" -ge 1 ]] || sc=1
  local -A PKGPAR=()
  valid_hostname "$host" || return 1
  (
    flock 9 || exit 0
    f="$(find "$QUEUEDIR" -mindepth 2 -name "*_$id.json" -print -quit 2>/dev/null)"
    [[ -n "$f" && -f "$f" ]] || exit 0
    _cmeta_load "$f"; meta="$_CMETA"
    IFS=$'\x01' read -r ver prob need jl hosts k numa par m memmb enq decl <<<"$meta"
    [[ "$k" =~ ^[0-9]+$ && "$k" -ge 1 ]] || k=1
    # a mesma largura EFETIVA do q_claim (CPU e memória); o hold só nasce p/ job que cabe no juiz,
    # mas, se ainda assim não couber, vale a largura de CPU (o job segue, o cgroup é que limita)
    local korig=$k
    _eff_width "$k" "$memmb" "$sc" "${QC_TOTAL_SLOTS:-}" "${QC_MEM_KB:-}"
    if (( _EKS >= 1 )); then k=$_EK; ks=$_EKS; else ks="$(_kslots "$k" "$sc")"; fi
    base="${f##*/}"; mkdir -p "$ASSIGNEDDIR/$host" 2>/dev/null; dest="$ASSIGNEDDIR/$host/$base"
    mv "$f" "$dest" 2>/dev/null || exit 0
    rm -f "$f.cmeta" 2>/dev/null
    tmp="$dest.tmp"
    jq -c --arg h "$host" --argjson now "$EPOCHSECONDS" --argjson k "$k" --argjson nm "$([[ "$numa" == y ]] && echo true || echo false)" \
       --argjson sl "$ks" --argjson pc "${m:-$PARALLEL_MAX_DEFAULT}" --argjson kn "$korig" \
       '. + {assigned_to:$h, assigned_at:$now, test_cpus:$k, same_numa:$nm, slots:$sl, par_max:1, par_cap:$pc, cpu_needed:$kn}' "$dest" > "$tmp" 2>/dev/null && mv -f "$tmp" "$dest"
    cat "$dest"; printf '\n'
  ) 9>"$QUEUEDIR/.lock"
}

# hold_sweep : cria holds p/ jobs largos famintos (throttle SWEEP_THROTTLE). Ver o cabeçalho.
hold_sweep() {
  local stamp="$HOLDDIR/.sweep-stamp" now=$EPOCHSECONDS last=0
  _mkd "$HOLDDIR"                                                  # todo beat (antes do throttle)
  [[ -f "$stamp" ]] && last="$(<"$stamp")"; [[ "$last" =~ ^[0-9]+$ ]] || last=0
  (( now - last < SWEEP_THROTTLE )) && return 0
  printf '%s' "$now" > "$stamp"
  local wide; wide="$(_wide_jobs)"; [[ -n "$wide" ]] || return 0
  local rows; rows="$(_reg_rows)"; [[ -n "$rows" ]] || return 0
  local prova=0; [[ -n "$(find "$QUEUEDIR/020-prova" -maxdepth 1 -name '*.json' -print -quit 2>/dev/null)" ]] && prova=1
  local nholds; nholds="$(find "$HOLDDIR" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l)"
  local -A HELD=()
  local hf; for hf in $(find "$HOLDDIR" -maxdepth 1 -name '*.json' 2>/dev/null); do HELD[$(jq -r '.job // ""' "$hf" 2>/dev/null)]=1; done
  local f prob need jl hosts k numa enq memmb id
  local host cap langs total free sc maxnode mfg status live memkb
  while IFS=$'\x01' read -r f prob need jl hosts k numa enq memmb; do
    [[ "$enq" =~ ^[0-9]+$ ]] && (( now - enq >= HOLD_AFTER )) || continue
    id="${f##*_}"; id="${id%.json}"
    [[ -n "${HELD[$id]:-}" ]] && continue
    (( prova && nholds >= 1 )) && break
    case "$jl" in py2|py3) jl=py;; esac
    local best="" bestfree=-1 bestks=0 fits=0 ks
    while IFS=$'\x01' read -r host cap langs total free sc maxnode mfg status live memkb; do
      [[ "$live" == 1 && "$status" != draining && "$status" != disabled ]] || continue
      [[ "$sc" =~ ^[0-9]+$ && "$sc" -ge 1 ]] || continue                      # legado: nunca largo
      [[ -z "$need" || "$need" == "$cap" ]] || continue
      [[ -z "$hosts" || ",$hosts," == *",$host,"* ]] || continue
      [[ -z "$jl" || -z "$langs" || " $langs " == *" $jl "* ]] || (( now - enq > LANG_GRACE )) || continue
      # largura EFETIVA neste juiz (CPU e memória); nem a máquina inteira ⇒ não segura (o
      # infeasible_sweep fecha); estreito aqui ⇒ o backfill comum resolve, sem hold
      _eff_width "$k" "$memmb" "$sc" "$total" "$memkb"; ks=$_EKS
      (( ks >= 1 && total >= ks )) || continue
      (( ks == 1 )) && { fits=1; break; }
      [[ "$numa" == y ]] && (( maxnode < ks )) && continue
      if (( free >= ks )) && { [[ "$numa" != y ]] || (( mfg >= ks )); }; then fits=1; break; fi
      [[ -f "$HOLDDIR/$host.json" ]] && continue
      (( free > bestfree )) && { best="$host"; bestfree=$free; bestks=$ks; }
    done <<<"$rows"
    (( fits )) && continue
    [[ -n "$best" ]] || continue
    ks=$bestks
    jq -cn --arg j "$id" --argjson ks "$ks" --arg nm "$numa" --argjson now "$now" \
       '{job:$j, k_slots:$ks, numa:($nm=="y"), since:$now}' > "$HOLDDIR/.$best.tmp" 2>/dev/null \
      && mv -f "$HOLDDIR/.$best.tmp" "$HOLDDIR/$best.json"
    HELD[$id]=1; nholds=$((nholds+1))
  done <<<"$wide"
  return 0
}

# sched_spool_judge_error <jobfile> <mensagem> : fecha um job da FILA com Judge Error pelo spool,
# no formato do /judge/result (host "scheduler"); o judged ingere como qualquer resultado.
sched_spool_judge_error() {
  local f="$1" why="$2" login sd name id contest prob tmp
  [[ -f "$f" ]] || return 1
  declare -F spool_shard_dir >/dev/null 2>&1 || source "$(dirname "${BASH_SOURCE[0]}")/../api/v1/lib/spool-shard.sh" 2>/dev/null
  IFS=$'\x01' read -r id contest prob login < <(jq -j '[(.id // ""), (.contest // ""), (.problem_id // ""), (.login // "")] | join("\u0001")' "$f" 2>/dev/null)
  [[ -n "$id" && -n "$contest" ]] || return 1
  mkdir -p "$SPOOLDIR" 2>/dev/null
  sd="$(spool_shard_dir "$login")"; name="$contest:$EPOCHSECONDS:$id:scheduler:result:$prob"
  tmp="$sd/.in.result.$id.${BASHPID}"
  jq -c --arg w "$why" '{host:"scheduler", id, contest, problem_id, login, lang:(.lang // ""),
      verdict:("Judge Error (" + $w + ")"), verdict_canon:"Judge Error", score:0, score_max:0, score_kind:"tests",
      correct:0, total_tests:0, duration_s:0, tl_used:null, tests:[], report_html_b64:null}' "$f" > "$tmp" 2>/dev/null \
    && mv -f "$tmp" "$sd/$name" && { rm -f "$f" "$f.cmeta" 2>/dev/null; return 0; }
  rm -f "$tmp" 2>/dev/null; return 1
}

# infeasible_sweep : Judge Error p/ job sem juiz vivo capaz há INFEASIBLE_AFTER (throttle): largo demais
# (CPU) ou com MEMLIMITMB que nem a máquina INTEIRA de nenhum juiz comporta (a mensagem diz qual, com o
# teto do maior juiz — o autor sabe o que corrigir no conf).
infeasible_sweep() {
  local stamp="$QUEUEDIR/.infeasible-stamp" now=$EPOCHSECONDS last=0
  [[ -f "$stamp" ]] && last="$(<"$stamp")"; [[ "$last" =~ ^[0-9]+$ ]] || last=0
  (( now - last < SWEEP_THROTTLE )) && return 0
  printf '%s' "$now" > "$stamp"
  local wide; wide="$(_wide_jobs)"; [[ -n "$wide" ]] || return 0
  local rows; rows="$(_reg_rows)"; [[ -n "$rows" ]] || return 0
  local f prob need jl hosts k numa enq memmb host cap langs total free sc maxnode mfg status live memkb any cap_ok memfail maxlim v msg
  while IFS=$'\x01' read -r f prob need jl hosts k numa enq memmb; do
    [[ "$enq" =~ ^[0-9]+$ ]] && (( now - enq >= INFEASIBLE_AFTER )) || continue
    [[ "$k" =~ ^[0-9]+$ && "$k" -ge 1 ]] || k=1
    any=0; cap_ok=0; memfail=0; maxlim=0
    while IFS=$'\x01' read -r host cap langs total free sc maxnode mfg status live memkb; do
      [[ "$live" == 1 ]] || continue
      any=1
      [[ -z "$need" || "$need" == "$cap" ]] || continue
      [[ -z "$hosts" || ",$hosts," == *",$host,"* ]] || continue
      # juiz legado (sem slot_cpus): roda job estreito, sem regra de memória
      [[ "$sc" =~ ^[0-9]+$ && "$sc" -ge 1 ]] || { (( k == 1 )) && { cap_ok=1; break; }; continue; }
      _eff_width "$k" "$memmb" "$sc" "$total" "$memkb"
      if (( _EKS == 0 )); then   # sem fork: este laço vê todo job atrasado (backlog de prova)
        memfail=1; v=0; [[ "$memkb" =~ ^[0-9]+$ ]] && v=$(( memkb / 1024 - 4096 - 64 )); (( v > maxlim )) && maxlim=$v
        continue
      fi
      if [[ "$numa" == y ]]; then (( maxnode >= _EKS )) && cap_ok=1
      else (( total >= _EKS )) && cap_ok=1; fi
      (( cap_ok )) && break
    done <<<"$rows"
    (( any && cap_ok == 0 )) || continue
    if (( memfail )); then
      msg="o problema pede MEMLIMITMB=$memmb MB e nenhum juiz comporta (o maior aceita até ~$maxlim MB) — corrija o limite de memória no conf do problema"
    else
      msg="nenhum juiz com $k CPU(s)$([[ "$numa" == y ]] && printf ' num nó NUMA') p/ este problema"
    fi
    (
      flock 9 || exit 0
      [[ -f "$f" ]] || exit 0
      sched_spool_judge_error "$f" "$msg"
    ) 9>"$QUEUEDIR/.lock"
  done <<<"$wide"
  return 0
}

# sched_decline_job <host> <id> <motivo> : o juiz não conseguiu alocar o job (corrida entre o claim e
# a alocação). Volta p/ a banda de origem com epoch novo e `declined.<host>=epoch` (o host o pula
# por DECLINE_BACKOFF); na DECLINE_MAX-ésima recusa vira Judge Error. Ecoa requeued|judge_error|notfound.
sched_decline_job() {
  local host="$1" id="$2" why="$3" f prio band n now=$EPOCHSECONDS
  valid_hostname "$host" || return 1
  f="$(find "$ASSIGNEDDIR/$host" -maxdepth 1 -name "*_$id.json" -print -quit 2>/dev/null)"
  [[ -n "$f" && -f "$f" ]] || { printf 'notfound'; return 0; }
  n="$(jq -r '(.declined // {}) | [.[]] | length' "$f" 2>/dev/null)"; [[ "$n" =~ ^[0-9]+$ ]] || n=0
  if (( n + 1 >= DECLINE_MAX )); then
    ( flock 9; sched_spool_judge_error "$f" "recusado por $((n+1)) juízes: $why" ) 9>"$QUEUEDIR/.lock" && { printf 'judge_error'; return 0; }
  fi
  prio="$(jq -r '.priority // "lista-publica"' "$f" 2>/dev/null)"; band="$(sched_band_of "$prio")"
  (
    flock 9 || exit 1
    jq -c --arg h "$host" --argjson now "$now" 'del(.assigned_to, .assigned_at, .test_cpus, .same_numa, .slots, .par_max, .par_cap)
        | .declined = ((.declined // {}) + {($h): $now})' "$f" > "$f.tmp" 2>/dev/null \
      && mv -f "$f.tmp" "$QUEUEDIR/$band/${now}_${id}.json" && rm -f "$f"
  ) 9>"$QUEUEDIR/.lock" && { printf 'requeued'; return 0; }
  printf 'error'; return 1
}
# sched_decline_update <host> <reqid> : a calibração volta p/ pending (o pedido continua valendo).
sched_decline_update() {
  local host="$1" reqid="$2" f="$UPDATESDIR/inprogress/$1/$2.json"
  valid_hostname "$host" || return 1
  [[ -f "$f" ]] || { printf 'notfound'; return 0; }
  ( flock 9; jq -c 'del(.claimed_at, .test_cpus, .same_numa, .slots)' "$f" > "$f.tmp" 2>/dev/null \
      && mv -f "$f.tmp" "$UPDATESDIR/pending/$reqid.json" && rm -f "$f" ) 9>"$UPDATESDIR/.lock" \
    && { upd_cmd_clear "$host" "$(jq -r '.target // ""' "$UPDATESDIR/pending/$reqid.json" 2>/dev/null)"; printf 'requeued'; return 0; }
  printf 'error'; return 1
}
# sched_decline_command <host> <command-json> : o comando (calibrate dirigido) é reenfileirado
# com cmdid novo; o marcador da entrega anterior sai.
sched_decline_command() {
  local host="$1" c="$2" action id by
  valid_hostname "$host" || return 1
  IFS=$'\x01' read -r action id by < <(jq -j '[(.action // ""), (.id // ""), (.by // "?")] | join("\u0001")' <<<"$c" 2>/dev/null)
  [[ -n "$action" ]] || { printf 'error'; return 1; }
  [[ -n "$id" ]] && upd_cmd_clear "$host" "$id"
  cmd_request "$host" "$action" "$by" "$id" >/dev/null && { printf 'requeued'; return 0; }
  printf 'error'; return 1
}
