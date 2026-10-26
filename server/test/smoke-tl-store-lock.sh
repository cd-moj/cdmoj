#!/bin/bash
# smoke-tl-store-lock.sh — os LOCKS por problema do store de TL e do sumário de calibração (26/10/2026).
# Antes, tl_store_record/tl_store_set_method liam e regravavam run/tl/<id>.json sem lock: dois juízes
# reportando juntos (calibração dirigida em vários juízes, ou todo agente re-reportando o cache no boot) perdiam
# a entrada de um deles — o último `mv` vencia. O mesmo no calx_summary_write (sumário das soluções) e na junção
# do arquivo do host no /judge/calib-report. E o carimbo fresco (_tl_fresh_edit) seguia SEM lock depois de 5 s.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
export RUNDIR="$FIX/run" TL_STORE_DIR="$FIX/run/tl" CALIB_DIR="$FIX/run/calib" CALX_SUM_DIR="$FIX/run/calib-sum" \
       CAL_SUMMARY="$FIX/run/calib-summary.json" MOJ_PROBLEMS_DIR="$FIX/probs" CONTESTSDIR="$FIX/contests"
mkdir -p "$TL_STORE_DIR" "$CALIB_DIR" "$MOJ_PROBLEMS_DIR/col/pa/tests/input" "$CONTESTSDIR/treino/var"
: "${MOJTOOLS_DIR:=$(cd "$ROOT/../../mojtools" 2>/dev/null && pwd)}"; export MOJTOOLS_DIR
source "$ROOT/api/v1/lib/tl-store.sh"; source "$ROOT/api/v1/lib/calib-expect.sh"
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:-}"; ((fail++)); fi; }

echo "== 20 juízes reportando o MESMO problema ao mesmo tempo: nenhum se perde =="
for i in $(seq 1 20); do
  tl_store_record "juiz$i" "col#pa" "abcdef12" "{\"c\":\"0.$i\",\"default\":\"0.$i\"}" "" '{"c":"1","default":"1"}' moj &
done
wait
SF="$TL_STORE_DIR/col#pa.json"; DBG="$(jq -c '.hosts | keys' "$SF" 2>&1)"
ck "as 20 entradas de host estão no store"         '[[ "$(jq -r ".hosts | length" "$SF")" == 20 ]]'
ck "cada uma com o seu TL e a metade Kattis"        '[[ "$(jq -r ".hosts.juiz7.tl.c" "$SF")" == 0.7 && "$(jq -r ".hosts.juiz13.tl_kattis.c" "$SF")" == 1 ]]'
ck "sumário do Painel com o máx NUMÉRICO entre eles (0.9; o \"0.20\" vale 0,2)" '[[ "$(jq -r ".[\"col#pa\"].tl.c" "$RUNDIR/tl-summary.json")" == 0.9 ]]'
ck "o lock é por problema (run/tl/<id>.lock)"       '[[ -e "$TL_STORE_DIR/col#pa.lock" ]]'

echo "== troca de método concorrente com reports: o método e os hosts ficam =="
for i in $(seq 21 30); do
  tl_store_record "juiz$i" "col#pa" "abcdef12" '{"c":"0.1","default":"0.1"}' &
  tl_store_set_method "col#pa" kattis &
done
wait
ck "30 hosts e o método kattis"                    '[[ "$(jq -r ".hosts | length" "$SF")" == 30 && "$(jq -r .method "$SF")" == kattis ]]'

echo "== lock ocupado: tl_store_record devolve 75 (o handler responde 500) e não grava =="
before="$(md5sum < "$SF")"
( exec 9>>"$TL_STORE_DIR/col#pa.lock"; flock 9; sleep 12 ) &
sleep 0.5
tl_store_record "juizX" "col#pa" "abcdef12" '{"c":"9"}'; rc=$?
wait
ck "rc 75 depois de esperar 10 s"                   '[[ $rc -eq 75 ]]'
ck "o store não mudou"                              '[[ "$(md5sum < "$SF")" == "$before" ]]'

echo "== carimbo fresco: lock ocupado = não grava (antes gravava sem lock) =="
FF="$(tl_fresh_file)"; mkdir -p "${FF%/*}"
( exec 9>"$FF.lock"; flock 9; sleep 7 ) &
sleep 0.5
tl_fresh_set "col#pa" "abcdef12"
wait
ck "nada gravado sob lock alheio"                   '[[ ! -s "$FF" ]]'
tl_fresh_set "col#pa" "abcdef12"
ck "livre, grava"                                   '[[ "$(jq -r ".[\"col#pa\"]" "$FF")" == abcdef12 ]]'

echo "== sumário de calibração: N calib de hosts gravados juntos, o sumário vê todos =="
P="$MOJ_PROBLEMS_DIR/col/pa"; mkdir -p "$P/sols/good"; printf 'int main(){}\n' > "$P/sols/good/a.c"; : > "$P/conf"
printf '1\n' > "$P/tests/input/t1"
mkdir -p "$CALIB_DIR/col#pa"
for i in $(seq 1 8); do
  printf '{"host":"juiz%s","checksum":"","sols":[{"file":"a.c","lang":"c","category":"good","verdict":"Accepted,100p","tests":[{"name":"t1","code":"AC","time":0.1,"tl":5}]}]}' "$i" \
    > "$CALIB_DIR/col#pa/juiz$i.json"
  calx_summary_write "col#pa" &
done
wait
DBG="$(cat "$(calx_summary_file "col#pa")" 2>&1)"
ck "o sumário final conta os 8 hosts"               '[[ "$(jq -r .hosts "$(calx_summary_file "col#pa")")" == 8 ]]'
ck "o lock do calib-sum existe"                     '[[ -e "$CALX_SUM_DIR/col#pa.lock" ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
