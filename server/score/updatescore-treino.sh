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
#   attempts = total submissions across all problems
# Total column is the solved count (the JS sorts/uses Total).
#
# Reads the per-problem .d state files the judge maintains
# (JAACERTOU>0 => solved; TENTATIVAS => attempts), same source as ICPC.
set -u
SC_PROG="updatescore-treino"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/score-common.sh"

sc_load "${1:-}"

# --- header ----------------------------------------------------------------
printf 'treino\n'
printf 'asc:username:team name:solved:attempts\n'

# --- rows ------------------------------------------------------------------
{
  while IFS=$'\t' read -r login full team us uf flag; do
    solved=0
    attempts=0
    for ((p=0; p<SC_NPROB; p++)); do
      pidx="${SC_PIDX[p]}"
      JAACERTOU=0; TENTATIVAS=0; PENDING=0
      statef="$CONTESTDIR/controle/$login.d/$pidx"
      if [[ -f "$statef" ]]; then
        # shellcheck disable=SC1090
        source "$statef" 2>/dev/null
      fi
      : "${JAACERTOU:=0}"; : "${TENTATIVAS:=0}"
      (( attempts += TENTATIVAS ))
      (( JAACERTOU > 0 )) && (( solved++ ))
    done
    # sort keys: solved desc, attempts asc (fewer attempts ranks higher on tie)
    printf '%d\t%d\t%s:%s:%d:%d\n' \
      "$solved" "$attempts" "$login" "$team" "$solved" "$attempts"
  done < <(sc_users)
} | sort -t $'\t' -k1,1nr -k2,2n | cut -f3-
