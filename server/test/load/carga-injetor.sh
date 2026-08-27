#!/bin/bash
# carga-injetor.sh <contest> [dur_s=1080] — veredictos sintéticos num contest DEMO, ~3/s: o MESMO gesto do
# judged.sh por veredicto (history + metrics + .score-dirty), sem juiz. É o que faz o placar
# rebuildar, os balões nascerem e os caches invalidarem DURANTE o teste — mundo vivo.
set -u
export CONTESTSDIR=/data/contests RUNDIR=/data/run
cd /opt/moj/cdmoj/server/api/v1
source lib/common.sh 2>/dev/null; source lib/verdict.sh; source lib/users.sh
set +o noglob; shopt -s nullglob
C="${1:?uso: carga-injetor.sh <contest> [dur_s]}"; CD="$CONTESTSDIR/$C"
grep -q '^DEMO=1' "$CD/conf" || { echo "não é DEMO"; exit 1; }
DUR="${2:-1080}"; END=$(( EPOCHSECONDS + DUR )); N=0
mapfile -t CANON < <(bash -c 'set +u; source "'"$CD"'/conf" 2>/dev/null; for ((i=4;i<${#PROBS[@]};i+=5)); do echo "${PROBS[$i]}"; done')
NP=${#CANON[@]}
while (( EPOCHSECONDS < END )); do
  t=$(( (RANDOM % 10000) + 1 )); u="$(printf 'eq-%04d' "$t")"
  [[ -d "$CD/users/$u" ]] || continue
  p=$(( RANDOM % NP )); ep=$EPOCHSECONDS
  r=$(( RANDOM % 100 )); v="Accepted,100p"
  (( r >= 40 )) && v="Wrong Answer"; (( r >= 75 )) && v="Time Limit Exceeded"
  id="$(printf 'inj%05d%06d' "$N" "$(( ep % 1000000 ))")"
  user_history_append "$C" "$u" "$ep:${CANON[$p]}:C:$v:$ep:$id"
  metrics_recompute "$C" "$u"
  N=$(( N + 1 ))
  sleep 0.3
done
echo "injetados: $N veredictos"
