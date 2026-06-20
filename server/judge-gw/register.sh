#!/bin/bash
# server/judge-gw/register.sh — Registro + heartbeat de WORKER no master.
#
# PROBLEMA QUE RESOLVE — a lista MOJPORTS hardcoded e o poll-storm de `islocked`.
# Hoje escalonador.sh/enviar-newcdmoj.sh têm um array fixo de host:port e
# descobrem quem está livre mandando `{"cmd":"islocked"}` para TODOS, em loop.
# Aqui cada worker se ANUNCIA ao subir e manda heartbeat com seu estado, gravando
# num REGISTRO em arquivo que o escalonador lê. Sem MOJPORTS fixo, sem poll-storm:
# o master tem um free-set vivo. A afinidade contest_servers vira match por
# CAPACIDADE (pos/gpu/cm/hu), substituindo o hack de 2 passos.
#
# REGISTRO (uma linha por worker, atômico via flock):  $RUNDIR/registry/workers
#   host:port:capability:state:epoch
#   ex.: pos1:41050:pos:free:1718800000
# state ∈ {free,busy}. Linhas com epoch mais velho que $REG_TTL (default 30s)
# são consideradas mortas pelo escalonador (worker caiu sem desregistrar).
#
# COMO O WORKER USA (no lancar-juizes.sh, ao subir cada worker; ver README.md):
#   # anuncia capacidade ao subir
#   register.sh up   pos1 41050 pos
#   # ...e manda heartbeat de estado a cada poucos segundos (loop em paralelo):
#   register.sh beat pos1 41050 pos free      # quando ocioso
#   register.sh beat pos1 41050 pos busy      # ao pegar um job
#   # ao terminar/derrubar:
#   register.sh down pos1 41050
#
# Como o ESCALONADOR usa (substitui o array MOJPORTS):
#   mapfile -t MOJPORTS < <(register.sh list)             # host:port dos vivos
#   mapfile -t LIVRES   < <(register.sh list free)        # só os livres
#   mapfile -t GPUS     < <(register.sh list free gpu)    # livres com capacidade gpu
#
# Aditivo: NÃO altera os scripts vivos; eles passam a CHAMAR este. file-based,
# sem DB/broker. Funciona local (mesma máquina) ou via ssh do worker p/ o master.

set -u

REG_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
SERVER_DIR="$(cd "$REG_DIR/.." && pwd)"
_COMMON_CONF="$SERVER_DIR/etc/common.conf"
[[ -r "$_COMMON_CONF" ]] && source "$_COMMON_CONF"

: "${RUNDIR:=/home/ribas/moj/run}"
: "${REGISTRYDIR:=$RUNDIR/registry}"
: "${REGISTRY_FILE:=$REGISTRYDIR/workers}"
: "${REG_TTL:=30}"          # segundos: heartbeat mais velho que isso = morto
: "${REG_LOCK:=$REGISTRYDIR/.lock}"

mkdir -p "$REGISTRYDIR" 2>/dev/null
[[ -e "$REGISTRY_FILE" ]] || : > "$REGISTRY_FILE"

# upsert <host> <port> <capability> <state> — substitui/insere a linha do worker.
_upsert() {
  local host="$1" port="$2" cap="$3" state="$4"
  local key="$host:$port"
  local now=$EPOCHSECONDS
  (
    flock 9
    local tmp="$REGISTRY_FILE.tmp.$$"
    # remove linha antiga deste host:port, mantém o resto, acrescenta a nova.
    grep -v "^$key:" "$REGISTRY_FILE" 2>/dev/null > "$tmp"
    printf '%s:%s:%s:%s:%s\n' "$host" "$port" "$cap" "$state" "$now" >> "$tmp"
    mv -f "$tmp" "$REGISTRY_FILE"
  ) 9>"$REG_LOCK"
}

# remove <host> <port>
_remove() {
  local key="$1:$2"
  (
    flock 9
    local tmp="$REGISTRY_FILE.tmp.$$"
    grep -v "^$key:" "$REGISTRY_FILE" 2>/dev/null > "$tmp"
    mv -f "$tmp" "$REGISTRY_FILE"
  ) 9>"$REG_LOCK"
}

# list [state] [capability] — imprime host:port dos workers VIVOS que casam.
# vivos = epoch >= now - REG_TTL.
_list() {
  local want_state="${1:-}" want_cap="${2:-}"
  local now=$EPOCHSECONDS cutoff
  cutoff=$(( now - REG_TTL ))
  (
    flock -s 9
    awk -F: -v cutoff="$cutoff" -v st="$want_state" -v cap="$want_cap" '
      { host=$1; port=$2; c=$3; state=$4; ts=$5 }
      ts < cutoff           { next }                 # morto (heartbeat velho)
      st  != "" && state!=st { next }
      cap != "" && c   !=cap { next }
      { print host":"port }
    ' "$REGISTRY_FILE" 2>/dev/null
  ) 9>"$REG_LOCK"
}

# dump — registro inteiro (debug / rota ops/judges).
_dump() {
  ( flock -s 9; cat "$REGISTRY_FILE" 2>/dev/null ) 9>"$REG_LOCK"
}

# gc — remove linhas mortas (chame periodicamente no master, opcional).
_gc() {
  local now=$EPOCHSECONDS cutoff
  cutoff=$(( now - REG_TTL ))
  (
    flock 9
    local tmp="$REGISTRY_FILE.tmp.$$"
    awk -F: -v cutoff="$cutoff" '$5 >= cutoff' "$REGISTRY_FILE" 2>/dev/null > "$tmp"
    mv -f "$tmp" "$REGISTRY_FILE"
  ) 9>"$REG_LOCK"
}

usage() {
  cat >&2 <<EOF
uso:
  $0 up    <host> <port> <capability>              # registra worker como free
  $0 beat  <host> <port> <capability> <free|busy>  # heartbeat de estado
  $0 down  <host> <port>                           # desregistra
  $0 list  [free|busy] [capability]                # host:port dos vivos
  $0 dump                                          # registro completo (debug)
  $0 gc                                            # remove mortos do arquivo
capabilities sugeridas: pos gpu cm hu
EOF
}

case "${1:-}" in
  up)    [[ $# -eq 4 ]] || { usage; exit 2; }; _upsert "$2" "$3" "$4" free ;;
  beat)  [[ $# -eq 5 ]] || { usage; exit 2; }; _upsert "$2" "$3" "$4" "$5" ;;
  down)  [[ $# -eq 3 ]] || { usage; exit 2; }; _remove "$2" "$3" ;;
  list)  _list "${2:-}" "${3:-}" ;;
  dump)  _dump ;;
  gc)    _gc ;;
  -h|--help) usage ;;
  *) usage; exit 2 ;;
esac
