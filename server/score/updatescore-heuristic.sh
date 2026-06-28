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
set -u
SC_PROG="updatescore-heuristic"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/score-common.sh"

sc_load "${1:-}"
FREEZE="${FREEZE_TIME:-0}"; [[ "$FREEZE" =~ ^[0-9]+$ ]] || FREEZE=0   # >= freeze: submissão escondida

# --- header ----------------------------------------------------------------
{
  printf 'heuristic\n'
  printf 'desc:username:team name'
  for ((p=0; p<SC_NPROB; p++)); do printf ':%s' "${SC_SHORT[p]}"; done
  printf ':Total\n'
}

# --- rows ------------------------------------------------------------------
{
  while IFS=$'\t' read -r login full team us uf flag; do
    dataf="$CONTESTDIR/data/$login"
    total=0
    adjtotal=0
    cells=""
    for ((p=0; p<SC_NPROB; p++)); do
      pidx="${SC_PIDX[p]}"
      ptxt="${PROBS[pidx+4]:-}"            # bare textual probid (treino-style data)
      # Emit "score<TAB>adjusted" for the best attempt, or empty if untried.
      read -r best adj < <(awk -F: -v P="$pidx" -v PT="$ptxt" -v FREEZE="$FREEZE" '
        function probmatch(f3,   bare) {
          if (f3 == P) return 1
          if (PT != "") {
            # data may carry the textual probid (e.g. flia-problems#campominado)
            bare = f3
            sub(/.*[#\/]/, "", bare)
            if (bare == PT || f3 == PT) return 1
          }
          return 0
        }
        probmatch($3) && (FREEZE+0<=0 || $1+0 < FREEZE+0) {
          line = $0
          s = ""; a = ""
          if (match(line, /Score[ \t]+-?[0-9]+/)) {
            tok = substr(line, RSTART, RLENGTH); sub(/Score[ \t]+/, "", tok); s = tok + 0
          }
          if (match(line, /Score Ajustado[ \t]+-?[0-9]+(\.[0-9]+)?/)) {
            tok = substr(line, RSTART, RLENGTH); sub(/Score Ajustado[ \t]+/, "", tok); a = tok + 0
          }
          if (s == "" && line ~ /Accepted/) s = 0
          if (s != "") {
            seen = 1
            if (!have || s > bs || (s == bs && a > ba)) { bs = s; ba = a; have = 1 }
          }
        }
        END { if (seen) printf "%d %s", bs, (ba=="" ? "0" : ba) }
      ' "$dataf" 2>/dev/null)

      if [[ -z "${best:-}" ]]; then
        cells+=":-"
      else
        cells+=":${best}"
        total=$(( total + best ))
        # accumulate adjusted (float) via awk to keep precision
        adjtotal=$(awk -v a="$adjtotal" -v b="${adj:-0}" 'BEGIN{printf "%.4f", a+b}')
      fi
      unset best adj
    done
    # sort keys: total Score desc, then summed Score Ajustado desc
    printf '%d\t%s\t%s:%s%s:%d\n' \
      "$total" "$adjtotal" "$login" "$team" "$cells" "$total"
  done < <(sc_users)
} | sort -t $'\t' -k1,1nr -k2,2nr | cut -f3-
