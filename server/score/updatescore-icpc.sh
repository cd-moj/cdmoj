#!/usr/bin/env bash
#
# updatescore-icpc.sh <contest>
#
# ICPC scoreboard generator. Prints ONE TXT to stdout:
#
#   icpc
#   desc:asc:flag:username:univ short:team name:univ full:A:B:...:Total:Penalty:LastAC
#   <rows, already sorted: solved desc, penalty asc, last-AC-minute asc>
#
# Total = resolvidos; Penalty = SOMA das penalidades (visível no placar); LastAC = minuto de
# prova do ÚLTIMO problema resolvido — coluna de SISTEMA (a UI usa p/ empate exato, não exibe).
# Classificação: 1º resolvidos (desc), 2º penalidade (asc), 3º último AC (asc).
#
# Per team / per problem the cell is:
#   ""              untried
#   tries/minutes   solved (minutes from CONTEST_START; painted by balloon color)
#   tries/minutes*  solved FIRST-TO-SOLVE (menor first_ac_epoch do problema ENTRE os
#                   times do placar, na MESMA visão frozen/full — o front destaca com ★)
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
  printf ':Total:Penalty:LastAC\n'
}

# --- cells from metrics (one pass over users/*/metrics.json) ----------------
declare -A CSOL CFAC CCNT CPEND
while IFS=$'\t' read -r l pr s fac cnt pend _rest; do
  CSOL["$l|$pr"]=$s; CFAC["$l|$pr"]=$fac; CCNT["$l|$pr"]=$cnt; CPEND["$l|$pr"]=$pend
done < <(sc_cells)

# --- first to solve ----------------------------------------------------------
# Menor first_ac_epoch por problema SÓ entre os times do placar (sc_users já exclui
# .admin/.judge/.cjudge/.mon — um juiz que resolve antes não rouba o FTS). Mesma visão
# do resto do placar (frozen/full), então o freeze não vaza FTS de AC escondido.
mapfile -t SC_ROWS < <(sc_users)
declare -A FTSMIN
for row in "${SC_ROWS[@]}"; do
  IFS=$'\t' read -r login _rest <<<"$row"
  for ((p=0; p<SC_NPROB; p++)); do
    key="$login|${SC_CANON[p]}"
    [[ "${CSOL[$key]:-0}" == 1 ]] || continue
    fac="${CFAC[$key]:-}"; [[ "$fac" =~ ^[0-9]+$ ]] || continue
    cur="${FTSMIN[${SC_CANON[p]}]:-}"
    if [[ -z "$cur" ]] || (( fac < cur )); then FTSMIN[${SC_CANON[p]}]=$fac; fi
  done
done

# --- rows ------------------------------------------------------------------
# Cada linha sai prefixada com as CHAVES de ordenação "solved \t penalty \t lastmin",
# ordena (resolvidos desc, penalidade asc, último-AC asc) e descarta as chaves — mas
# penalty e lastmin agora TAMBÉM vão no corpo visível (colunas Penalty/LastAC).
{
  for row in "${SC_ROWS[@]}"; do
    IFS=$'\t' read -r login full team us uf flag <<<"$row"
    solved=0
    penalty=0
    lastmin=0        # minuto de prova do ÚLTIMO problema resolvido (3º desempate)
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
        (( min > lastmin )) && lastmin=$min
        fts=""
        [[ -n "${FTSMIN[${SC_CANON[p]}]:-}" ]] && (( fac == FTSMIN[${SC_CANON[p]}] )) && fts="*"
        cells+=":${tent}/${min}${fts}"   # solved (* = first to solve)
      else
        cells+=":${tent}/-"              # tried, unsolved
      fi
    done
    # chaves de ordenação + a linha visível (com Penalty e LastAC no corpo)
    printf '%d\t%d\t%d\t%s:%s:%s:%s:%s%s:%d:%d:%d\n' \
      "$solved" "$penalty" "$lastmin" \
      "$flag" "$login" "$us" "$team" "$uf" "$cells" "$solved" "$penalty" "$lastmin"
  done
} | sort -t $'\t' -k1,1nr -k2,2n -k3,3n | cut -f4-
