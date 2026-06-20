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
# Total column = number of solved problems.
#
# Ported from old/moj-prod/moj/scripts/updatescore.sh and
# old/cdmoj/server/scripts/updatedotscore.sh (PENALTYCOST=20).
set -u
SC_PROG="updatescore-icpc"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/score-common.sh"

PENALTYCOST=20

sc_load "${1:-}"

# --- header ----------------------------------------------------------------
{
  printf 'icpc\n'
  printf 'desc:asc:flag:username:univ short:team name:univ full'
  for ((p=0; p<SC_NPROB; p++)); do printf ':%s' "${SC_SHORT[p]}"; done
  printf ':Total\n'
}

# --- rows ------------------------------------------------------------------
# Build each row prefixed with "solved:penalty" sort keys, sort, then strip.
{
  while IFS=$'\t' read -r login full team us uf flag; do
    solved=0
    penalty=0
    cells=""
    for ((p=0; p<SC_NPROB; p++)); do
      pidx="${SC_PIDX[p]}"
      JAACERTOU=0; TENTATIVAS=0; PENDING=0
      statef="$CONTESTDIR/controle/$login.d/$pidx"
      if [[ -f "$statef" ]]; then
        # shellcheck disable=SC1090
        source "$statef" 2>/dev/null
      fi
      : "${JAACERTOU:=0}"; : "${TENTATIVAS:=0}"; : "${PENDING:=0}"
      if (( TENTATIVAS == 0 && PENDING == 0 )); then
        cells+=":"                       # untried -> empty cell
      elif (( JAACERTOU > 0 )); then
        min=$(( JAACERTOU / 60 ))
        (( solved++ ))
        (( penalty += (TENTATIVAS-1)*PENALTYCOST + min ))
        cells+=":${TENTATIVAS}/${min}"   # solved
      else
        cells+=":${TENTATIVAS}/-"        # tried, unsolved
      fi
    done
    # sort keys + the visible row
    printf '%d\t%d\t%s:%s:%s:%s:%s%s:%d\n' \
      "$solved" "$penalty" \
      "$flag" "$login" "$us" "$team" "$uf" "$cells" "$solved"
  done < <(sc_users)
} | sort -t $'\t' -k1,1nr -k2,2n | cut -f3-
