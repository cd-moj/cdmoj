#!/bin/bash
# smoke-score-ties.sh — RANKING DE COMPETIÇÃO no empate (achado do Carlos, LATAM 2026):
# N times empatados compartilham a posição E CONSOMEM N posições — depois de 3 empatados
# em 2º, o próximo é 5º (a numeração densa dava 3º). O placar nasce do STORE de verdade
# (history→metrics→build.sh) e o teste fixa o data-place do relatório offline (report-gen
# awk — o gêmeo servidor da regra do score-icpc.js) + convidado sem posição no meio do
# grupo (não desloca ninguém).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
export CONTESTSDIR="$FIX"
C="$FIX/tz"; mkdir -p "$C/var" "$C/enunciados"
NOW=$(date +%s); T0=$(( NOW - 7200 ))
{ printf 'CONTEST_ID=tz\nCONTEST_TYPE=icpc\nCONTEST_NAME=Ties\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$T0" "$(( NOW + 3600 ))"
  printf 'PROBS=( x col#pa Alfa A col#pa )\n'; } > "$C/conf"
jq -cn '{version:1, results_released:true, cohorts:[
  {id:"oficial", name:"Oficiais", regex:"", public:true, unranked:false, ranking:false, default:true},
  {id:"conv", name:"Convidados", regex:"^g-", public:false, unranked:true, ranking:false, default:false, sees:["oficial","conv"]}]}' \
  > "$C/cohorts.json"

mkteam(){ # <login> <minuto-do-AC>
  mkdir -p "$C/users/$1"
  jq -cn --arg l "$1" '{login:$l, fullname:("Time "+$l), password:"x",
    team:{univ_short:"U", univ_full:"Univ", flag:"br", region:"Sede"}}' > "$C/users/$1/account.json"
  local se=$(( T0 + $2 * 60 ))
  printf '%s:col#pa:C:Accepted:%s:id%s\n' "$se" "$se" "$1" > "$C/users/$1/history"
}
mkteam t-um 2        # 1 prob, pen 2  -> 1º
mkteam t-dois 6      # empate: 1 prob, pen 6, lastac 6
mkteam t-tres 6
mkteam t-quatro 6
mkteam g-conv 6      # CONVIDADO no meio do grupo (coorte unranked)
mkteam t-cinco 30    # depois do grupo -> tem de ser 5º (não 3º)

( cd "$ROOT/score" && CONTESTSDIR="$FIX" bash build.sh tz >/dev/null 2>&1 )
[[ -s "$C/var/placar.txt" ]] || { echo "build.sh não gerou placar"; exit 1; }

OUT="$FIX/rep"
bash "$ROOT/score/report-gen.sh" tz "$OUT" >/dev/null 2>&1 || { echo "report-gen falhou"; exit 1; }
H="$(grep -rl 'data-place' "$OUT"/*.html 2>/dev/null | head -1)"
[[ -s "$H" ]] || { echo "sem html com data-place em $OUT"; ls "$OUT"; exit 1; }

PASS=0; FAIL=0
seq="$(grep -o 'data-place="[0-9]*"' "$H" | grep -o '[0-9]*' | tr '\n' ' ')"
echo "  posições (ranqueados): $seq"
if [[ "$seq" == "1 2 2 2 5 "* || "$seq" == "1 2 2 2 5" ]]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FALHOU: esperava '1 2 2 2 5', veio '$seq'" >&2; fi
if grep -q 'data-place=""' "$H"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FALHOU: convidado sem data-place vazio" >&2; fi
# o grupo empatado compartilha o MESMO data-tie (3 ocorrências da tupla)
tie3="$(grep -o 'data-tie="[^"]*"' "$H" | sort | uniq -c | sort -rn | head -1)"
if [[ "$tie3" == *" 3 "* ]]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FALHOU: grupo de 3 empatados não compartilha data-tie ($tie3)" >&2; fi

echo "smoke-score-ties: PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
