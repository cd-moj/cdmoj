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
# Per problem the cell = best points (0..100) parsed from the verdicts in
# data/<user>:
#   Accepted,100p             -> 100
#   Wrong Answer,40p / ...,NNp -> NN   (partial)
# The best (maximum) NNp seen for the problem wins. Untried -> "-".
# Total = sum of the per-problem bests.
#
# Ported from old/moj-prod/moj/scripts/updatescore-obi.sh (partial points).
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

# --- rows ------------------------------------------------------------------
{
  while IFS=$'\t' read -r login full team us uf flag; do
    dataf="$CONTESTDIR/data/$login"
    total=0
    cells=""
    for ((p=0; p<SC_NPROB; p++)); do
      pidx="${SC_PIDX[p]}"
      best=""            # "" => untried
      if [[ -f "$dataf" ]]; then
        # lines: epoch:hash:probid:verdict....   (verdict may contain commas)
        # keep this problem's attempts, pull the NNp token, take the max.
        best=$(awk -F: -v P="$pidx" '
          $3 == P {
            v = $0
            if (match(v, /[0-9]+p/)) {
              n = substr(v, RSTART, RLENGTH-1) + 0
              if (n > mx) mx = n
              seen = 1
            } else if (v ~ /Accepted/) {
              if (100 > mx) mx = 100
              seen = 1
            } else {
              if (0 > mx) mx = 0
              seen = 1
            }
          }
          END { if (seen) print mx }
        ' "$dataf")
      fi
      if [[ -z "$best" ]]; then
        cells+=":-"
      else
        (( total += best ))
        cells+=":${best}"
      fi
    done
    printf '%d\t%s:%s%s:%d\n' "$total" "$login" "$team" "$cells" "$total"
  done < <(sc_users)
} | sort -t $'\t' -k1,1nr | cut -f2-
