#!/bin/bash
# server/test/load/daemon-ingest-bench.sh — mede a VAZÃO de ingestão de veredictos do daemon
# (server/daemons/judged.sh), o gargalo real de um contest grande. Cada resultado julgado passa
# pelo caminho quente record_verdict (metrics_recompute de 1 usuário) + rebuild do placar. Antes
# do H1 o rebuild era INLINE por-veredicto (build.sh ~0,7s p/ 1152 users) e travava a entrega em
# ~1/s; o H1 coalesceu o rebuild (schedule_score_rebuild). Este bench isola essa vazão.
#
#   uso: daemon-ingest-bench.sh <contest-fonte> [M=50] [modo=coalesced|inline] [SCORE_COALESCE_S=5]
#
# Roda contra uma CÓPIA scratch (não toca o contest fonte). Precisa das libs do server + build.sh
# no ambiente (rode dentro do container da API: CONTESTSDIR=/data/contests). Read-only p/ o fonte.
set -u
SRC_CONTEST="${1:?uso: daemon-ingest-bench.sh <contest-fonte> [M] [modo] [janela]}"
M="${2:-50}"
MODE="${3:-coalesced}"
export SCORE_COALESCE_S="${4:-5}"

: "${CONTESTSDIR:=/data/contests}"
: "${RUNDIR:=/data/run}"
SERVER_DIR="${SERVER_DIR:-$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)}"
SCORE_BUILD="$SERVER_DIR/score/build.sh"
export CONTESTSDIR RUNDIR
source "$SERVER_DIR/api/v1/lib/common.sh" 2>/dev/null
source "$SERVER_DIR/api/v1/lib/users.sh"  2>/dev/null

SRC="$CONTESTSDIR/$SRC_CONTEST"
[[ -d "$SRC/users" ]] || { echo "contest fonte inexistente: $SRC" >&2; exit 1; }
BENCH="zzbench-ingest-$$"
DST="$CONTESTSDIR/$BENCH"
trap 'rm -rf "$DST"' EXIT
cp -a "$SRC" "$DST"
NUSERS="$(ls "$DST/users" | wc -l)"
mapfile -t USERS < <(ls "$DST/users" | head -"$M")
# se M > nº de usuários, recicla a lista (um usuário pode receber vários veredictos)
while (( ${#USERS[@]} < M )); do USERS+=("${USERS[@]}"); done

# helper coalescido idêntico ao do daemon (schedule_score_rebuild), gate no mtime do placar.txt
score_rebuild_coalesced() {
  local out="$DST/var/placar.txt"
  if (( SCORE_COALESCE_S > 0 )) && [[ -n "$(find "$out" -newermt "-$SCORE_COALESCE_S seconds" 2>/dev/null)" ]]; then return 0; fi
  bash "$SCORE_BUILD" "$BENCH" >/dev/null 2>&1
}

# aquece: 1 build p/ o placar existir + page cache
bash "$SCORE_BUILD" "$BENCH" >/dev/null 2>&1

echo "contest=$SRC_CONTEST users=$NUSERS  M=$M veredictos  modo=$MODE  janela=${SCORE_COALESCE_S}s"
builds=0
t0=$(date +%s.%N)
for ((i=0; i<M; i++)); do
  u="${USERS[$i]}"
  metrics_recompute "$BENCH" "$u" >/dev/null 2>&1          # trabalho por-veredicto (1 usuário)
  touch "$DST/var/.score-dirty" 2>/dev/null
  if [[ "$MODE" == inline ]]; then
    bash "$SCORE_BUILD" "$BENCH" >/dev/null 2>&1; builds=$((builds+1))   # comportamento PRÉ-H1
  else
    before=$(stat -c %Y "$DST/var/placar.txt" 2>/dev/null || echo 0)
    score_rebuild_coalesced
    after=$(stat -c %Y "$DST/var/placar.txt" 2>/dev/null || echo 0)
    [[ "$after" != "$before" ]] && builds=$((builds+1))
  fi
done
t1=$(date +%s.%N)
dur=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.3f", b-a}')
rate=$(awk -v m="$M" -v d="$dur" 'BEGIN{printf "%.1f", (d>0)? m/d : 0}')
echo "  ingeriu $M veredictos em ${dur}s  =>  ${rate} veredictos/s   (rebuilds do placar: $builds)"
