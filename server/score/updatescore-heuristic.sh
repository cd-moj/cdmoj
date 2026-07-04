#!/usr/bin/env bash
#
# updatescore-heuristic.sh <contest>
#
# Heuristic / FLIA scoreboard generator. Prints ONE TXT to stdout:
#
#   heuristic
#   desc:username:team name:A:B:...:Total
#   <rows, already sorted by Total (sum of best Score) desc,
#    ties broken by the summed "Score Ajustado">
#
# Like OBI, but each cell is the best Score for that problem, parsed from
# verdicts of the form:
#
#   Accepted, Score 51950, Score Ajustado 51949493.99, ....
#
# Best = the attempt with the highest Score; "Score Ajustado" is the
# tie-break. Untried -> "-". Total = sum of the per-problem best Scores.
#
# Data source: users/*/metrics.json heur via sc_cells (frozen view unless
# MOJ_NOFREEZE=1 — submissions at/after FREEZE_TIME stay hidden).
set -u
SC_PROG="updatescore-heuristic"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/score-common.sh"

sc_load "${1:-}"

# --- header ----------------------------------------------------------------
{
  printf 'heuristic\n'
  printf 'desc:username:team name'
  for ((p=0; p<SC_NPROB; p++)); do printf ':%s' "${SC_SHORT[p]}"; done
  printf ':Total\n'
}

# --- cells from metrics (one pass over users/*/metrics.json) ----------------
declare -A CHS CHA
while IFS=$'\t' read -r l pr _s _fac _cnt _pend _best hs ha; do
  CHS["$l|$pr"]=$hs; CHA["$l|$pr"]=$ha
done < <(sc_cells)

# --- rows ------------------------------------------------------------------
{
  while IFS=$'\t' read -r login full team us uf flag; do
    total=0
    adjtotal=0
    cells=""
    for ((p=0; p<SC_NPROB; p++)); do
      key="$login|${SC_CANON[p]}"
      best="${CHS[$key]:-}"
      if [[ -z "$best" || "$best" == "-" ]]; then
        cells+=":-"
      else
        cells+=":${best}"
        total=$(( total + best ))
        # accumulate adjusted (float) via awk to keep precision
        adjtotal=$(awk -v a="$adjtotal" -v b="${CHA[$key]:-0}" 'BEGIN{printf "%.4f", a+b}')
      fi
    done
    # sort keys: total Score desc, then summed Score Ajustado desc
    printf '%d\t%s\t%s:%s%s:%d\n' \
      "$total" "$adjtotal" "$login" "$team" "$cells" "$total"
  done < <(sc_users)
} | sort -t $'\t' -k1,1nr -k2,2nr | cut -f3-
