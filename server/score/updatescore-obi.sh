#!/usr/bin/env bash
#
# updatescore-obi.sh <contest>
#
# OBI scoreboard generator. Prints ONE TXT to stdout:
#
#   obi
#   asc:username:team name:A:B:...:Total
#   <rows, already sorted by Total desc>
#
# Per problem the cell = best points (0..100), the max NNp parsed from the
# verdicts (Accepted without NNp -> 100; non-provisional attempt without
# NNp -> 0). Untried -> "-". Total = sum of the per-problem bests.
#
# Data source: users/*/metrics.json best_score via sc_cells (frozen view
# unless MOJ_NOFREEZE=1 — submissions at/after FREEZE_TIME stay hidden).
set -u
SC_PROG="updatescore-obi"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/score-common.sh"

sc_load "${1:-}"

# --- header ----------------------------------------------------------------
{
  printf 'obi\n'
  printf 'asc:username:team name'
  for ((p=0; p<SC_NPROB; p++)); do printf ':%s' "${SC_SHORT[p]}"; done
  printf ':Total\n'
}

# --- cells from metrics (one pass over users/*/metrics.json) ----------------
declare -A CBEST
while IFS=$'\t' read -r l pr _s _fac _cnt _pend best _rest; do
  CBEST["$l|$pr"]=$best
done < <(sc_cells)

# --- rows ------------------------------------------------------------------
{
  while IFS=$'\t' read -r login full team us uf flag; do
    total=0
    cells=""
    for ((p=0; p<SC_NPROB; p++)); do
      best="${CBEST[$login|${SC_CANON[p]}]:-}"
      if [[ -z "$best" || "$best" == "-" ]]; then
        cells+=":-"
      else
        (( total += best ))
        cells+=":${best}"
      fi
    done
    printf '%d\t%s:%s%s:%d\n' "$total" "$login" "$team" "$cells" "$total"
  done < <(sc_users)
} | sort -t $'\t' -k1,1nr | cut -f2-
