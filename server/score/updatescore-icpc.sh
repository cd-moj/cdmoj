#!/usr/bin/env bash
#
# updatescore-icpc.sh <contest>
#
# ICPC scoreboard generator. Prints ONE TXT to stdout:
#
#   icpc
#   desc:asc:flag:username:univ short:team name:univ full:A:B:...:Total
#   <rows, already sorted: solved desc, then penalty asc>
#
# Per team / per problem the cell is:
#   ""              untried
#   tries/minutes   solved (minutes from CONTEST_START; painted by balloon color)
#   tries/-         tried but unsolved
#
# Penalty = sum over solved problems of (tries-1)*PENALTYCOST + accepted-minute.
# PENALTYCOST comes from the conf (PENALTY_MINUTES, default 20); which verdicts count a
# try is decided at metrics time (PENALTY_VERDICTS -> metrics.json `counted`).
# Total column = number of solved problems.
#
# Data source: users/*/metrics.json via sc_cells (frozen view unless MOJ_NOFREEZE=1).
set -u
SC_PROG="updatescore-icpc"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/score-common.sh"

PENALTY_MINUTES=""
sc_load "${1:-}"
PENALTYCOST="${PENALTY_MINUTES:-20}"
[[ "$PENALTYCOST" =~ ^[0-9]+$ ]] || PENALTYCOST=20
START="${CONTEST_START:-0}"; [[ "$START" =~ ^[0-9]+$ ]] || START=0

# --- header ----------------------------------------------------------------
{
  printf 'icpc\n'
  printf 'desc:asc:flag:username:univ short:team name:univ full'
  for ((p=0; p<SC_NPROB; p++)); do printf ':%s' "${SC_SHORT[p]}"; done
  printf ':Total\n'
}

# --- cells from metrics (one pass over users/*/metrics.json) ----------------
declare -A CSOL CFAC CCNT CPEND
while IFS=$'\t' read -r l pr s fac cnt pend _rest; do
  CSOL["$l|$pr"]=$s; CFAC["$l|$pr"]=$fac; CCNT["$l|$pr"]=$cnt; CPEND["$l|$pr"]=$pend
done < <(sc_cells)

# --- rows ------------------------------------------------------------------
# Build each row prefixed with "solved:penalty" sort keys, sort, then strip.
{
  while IFS=$'\t' read -r login full team us uf flag; do
    solved=0
    penalty=0
    cells=""
    for ((p=0; p<SC_NPROB; p++)); do
      key="$login|${SC_CANON[p]}"
      sol="${CSOL[$key]:-0}"; fac="${CFAC[$key]:-0}"
      tent="${CCNT[$key]:-0}"; pend="${CPEND[$key]:-0}"
      if (( tent == 0 && pend == 0 )); then
        cells+=":"                       # untried -> empty cell
      elif (( sol == 1 )); then
        min=$(( (fac - START) / 60 )); (( min < 0 )) && min=0
        (( solved++ ))
        (( penalty += (tent-1)*PENALTYCOST + min ))
        cells+=":${tent}/${min}"         # solved
      else
        cells+=":${tent}/-"              # tried, unsolved
      fi
    done
    # sort keys + the visible row
    printf '%d\t%d\t%s:%s:%s:%s:%s%s:%d\n' \
      "$solved" "$penalty" \
      "$flag" "$login" "$us" "$team" "$uf" "$cells" "$solved"
  done < <(sc_users)
} | sort -t $'\t' -k1,1nr -k2,2n | cut -f3-
