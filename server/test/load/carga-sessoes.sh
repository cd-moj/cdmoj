#!/bin/bash
# carga-sessoes.sh <contest> — cria uma SESSÃO REAL por conta da fixture (times eq-* e staff
# s*.staff) e lista os tokens em /tmp/carga-tokens-{teams,staff}.txt. O token é o NOME do
# arquivo de sessão; prefixo `zc` p/ a limpeza ser um glob (`rm $RUNDIR/sessions/zc*`).
# RODA DENTRO DO CONTAINER (como a fixture). Reexecutar recria tudo (rm zc* primeiro).
set -u
export CONTESTSDIR="${CONTESTSDIR:-/data/contests}" RUNDIR="${RUNDIR:-/data/run}"
C="${1:?uso: carga-sessoes.sh <contest>}"
CD="$CONTESTSDIR/$C"
grep -q '^DEMO=1' "$CD/conf" || { echo "ABORTO: não é DEMO"; exit 1; }
set +o noglob; shopt -s nullglob          # ⚠ noglob do common… aqui nem sourceamos, mas o hábito fica
rm -f "$RUNDIR/sessions/zc"*
: > /tmp/carga-tokens-teams.txt; : > /tmp/carga-tokens-staff.txt
mk(){ local tok="zc$(od -An -N15 -tx1 /dev/urandom | tr -d ' \n')"
  printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' "$C" "$1" "$1" "$EPOCHSECONDS" > "$RUNDIR/sessions/$tok"
  echo "$tok" >> "$2"; }
for d in "$CD"/users/eq-*/;     do u="${d%/}"; mk "${u##*/}" /tmp/carga-tokens-teams.txt; done
for d in "$CD"/users/s*.staff/; do u="${d%/}"; mk "${u##*/}" /tmp/carga-tokens-staff.txt; done
wc -l /tmp/carga-tokens-teams.txt /tmp/carga-tokens-staff.txt
