#!/usr/bin/env bash
#
# updatescore-treino.sh <contest>
#
# Training scoreboard generator (no penalty). Prints ONE TXT to stdout:
#
#   treino
#   asc:username:team name:solved:attempts
#   <rows, already sorted by solved desc (ties: more attempts last)>
#
# Per user:
#   solved   = number of problems with an accepted submission
#   attempts = total counting attempts across all problems (up to the 1st AC)
# Total column is the solved count (the JS sorts/uses Total).
#
# Data source: users/*/metrics.json via sc_cells (frozen view unless MOJ_NOFREEZE=1).
set -u
SC_PROG="updatescore-treino"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/score-common.sh"

sc_load "${1:-}"

# --- header ----------------------------------------------------------------
printf 'treino\n'
printf 'asc:username:team name:solved:attempts\n'

# --- cells from metrics (one pass over users/*/metrics.json) ----------------
declare -A CSOL CCNT
while IFS=$'\t' read -r l pr s _fac cnt _rest; do
  CSOL["$l|$pr"]=$s; CCNT["$l|$pr"]=$cnt
done < <(sc_cells)

# --- rows ------------------------------------------------------------------
{
  while IFS=$'\t' read -r login full team us uf flag; do
    solved=0
    attempts=0
    for ((p=0; p<SC_NPROB; p++)); do
      key="$login|${SC_CANON[p]}"
      (( attempts += ${CCNT[$key]:-0} ))
      [[ "${CSOL[$key]:-0}" == 1 ]] && (( solved++ ))
    done
    # sort keys: solved desc, attempts asc (fewer attempts ranks higher on tie)
    printf '%d\t%d\t%s:%s:%d:%d\n' \
      "$solved" "$attempts" "$login" "$team" "$solved" "$attempts"
  done < <(sc_users)
} | sort -t $'\t' -k1,1nr -k2,2n | cut -f3-
