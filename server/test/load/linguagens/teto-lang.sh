#!/bin/bash
# teto-lang.sh <label> <cmd...> — MESMA fixture do teto-python.sh, drenada pelo <cmd>.
# O cmd recebe RUNDIR/CONTESTSDIR no env; mede ms e veredictos/min; confere o RESULTADO
# (history substituído + results/<id>.json presentes + spool vazio).
set -u
LABEL="$1"; shift
N="${TETO_N:-2000}"
FIX="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$RUN"' EXIT
export CONTESTSDIR="$FIX" RUNDIR="$RUN"
SPOOL="$RUN/spool/submissions"; mkdir -p "$SPOOL" "$RUN/spool/submissions-done" "$RUN/assigned" "$RUN/results"
C="$FIX/bz"; mkdir -p "$C/var"
NOW=$EPOCHSECONDS
printf 'CONTEST_ID=bz\nCONTEST_TYPE=icpc\nDEMO=1\nCONTEST_START=%s\nCONTEST_END=%s\nPROBS=( x col#pa A A col#pa )\n' "$((NOW-3600))" "$((NOW+86400))" > "$C/conf"
for (( t=0; t<300; t++ )); do
  u="eq-$(printf '%04d' "$t")"; mkdir -p "$C/users/$u/mojlog" "$C/users/$u/results"; : > "$C/users/$u/history"
done
for (( i=0; i<N; i++ )); do
  u="eq-$(printf '%04d' $(( i % 300 )))"
  id="$(printf 'py%030d' "$i")"
  printf '%s:col#pa:C:Not Answered Yet:%s:%s\n' "$NOW" "$NOW" "$id" >> "$C/users/$u/history"
  jq -cn --arg id "$id" --arg u "$u" \
    '{host:"mockj", id:$id, contest:"bz", problem_id:"col#pa", login:$u, lang:"C",
      verdict:"Wrong Answer", verdict_canon:"Wrong Answer", score:0, score_max:100,
      correct:1, total_tests:2, duration_s:1, tl_used:1, report_html_b64:"PGgxPm1vY2s8L2gxPgo="}' \
    > "$SPOOL/bz:$NOW:$id:mockj:result:col#pa"
done
T0N=$(date +%s%N)
"$@" >/dev/null 2>"$RUN/drain.err"
rc=$?
T1N=$(date +%s%N)
NDONE="$(find "$RUN/spool/submissions-done" -maxdepth 1 -type f | wc -l)"
NLEFT="$(find "$SPOOL" -maxdepth 1 -type f | wc -l)"
NRES="$(find "$C"/users/*/results -name '*.json' | wc -l)"
NHIST="$(cat "$C"/users/*/history | grep -c ':Wrong Answer:')"
NLOG="$(find "$C"/users/*/mojlog -name '*.html' | wc -l)"
MS=$(( (T1N-T0N)/1000000 )); (( MS>0 )) || MS=1
OKS="ok"
{ (( NDONE==N && NLEFT==0 && NRES==N && NHIST==N && NLOG==N && rc==0 )); } || OKS="FALHOU(done=$NDONE left=$NLEFT res=$NRES hist=$NHIST log=$NLOG rc=$rc)"
[[ "$OKS" == ok ]] || head -3 "$RUN/drain.err" >&2
printf '%-14s %6s ms  %8s/min  %5s µs/veredicto  %s\n' "$LABEL" "$MS" "$(( N*60000/MS ))" "$(( MS*1000/N ))" "$OKS"
