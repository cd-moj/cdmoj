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
FREEZE="${FREEZE_TIME:-0}"; [[ "$FREEZE" =~ ^[0-9]+$ ]] || FREEZE=0   # >= freeze: submissão escondida
[[ "${MOJ_NOFREEZE:-}" == 1 ]] && FREEZE=0   # placar COMPLETO (privilegiados): ignora freeze

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
        best=$(awk -F: -v P="$pidx" -v PT="${SC_CANON[p]:-}" -v FREEZE="$FREEZE" '
          function probmatch(f3,   b1,b2) {
            if (f3 == P) return 1               # offset numérico (legado)
            if (PT == "") return 0
            if (f3 == PT) return 1              # id canônico "coleção#problema" (pipeline novo)
            b1=f3; sub(/.*[#\/]/,"",b1)         # nome simples (tolera barra/ponto legados)
            b2=PT; sub(/.*[#\/]/,"",b2)
            return (b1==b2)
          }
          probmatch($3) && (FREEZE+0<=0 || $1+0 < FREEZE+0) {
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
