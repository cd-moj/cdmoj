#!/bin/bash
# Penalidade configurável do placar ICPC: PENALTY_MINUTES (peso, default 20) e
# PENALTY_VERDICTS (quais verdicts contam no `counted`, default wa tle mle rte).
# Exercita o pipeline inteiro: history -> metrics_recompute -> score/build.sh -> placar.txt
# (o valor da penalidade não aparece no TXT — é chave de ordenação; o teste verifica a ORDEM
# e as células tries/min), incluindo o recompute em massa via var/.metrics-stamp ao mudar o conf.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX"
C="$FIX/pen"; mkdir -p "$C/var"
START=1000

conf(){ # $1 = linhas extras (opcional)
  { printf 'CONTEST_ID=pen\nCONTEST_TYPE=icpc\nCONTEST_NAME=Pen\nCONTEST_START=%s\nCONTEST_END=%s\n' "$START" 999999999
    printf "PROBS=( cdmoj p/a 'Prob A' A 'p#a' )\n"
    [[ -n "${1:-}" ]] && printf '%s\n' "$1"; } > "$C/conf"
}

fx_user "$C" alice x "Alice"
fx_user "$C" bob x "Bob"
# alice: WA + CE antes do AC aos 10 min. bob: AC direto aos 25 min.
{ printf '10:p#a:c:Wrong,0p:%s:1\n' "$START"
  printf '20:p#a:c:Compilation Error:%s:2\n' "$START"
  printf '30:p#a:c:Accepted,100p:%s:3\n' $(( START + 600 )); } > "$C/users/alice/history"
printf '10:p#a:c:Accepted,100p:%s:9\n' $(( START + 1500 )) > "$C/users/bob/history"

pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: $(cat "$C/var/placar.txt" 2>/dev/null | tr '\n' '|')"; ((fail++)); fi; }
build(){ bash "$ROOT/score/build.sh" pen >/dev/null || { echo "build.sh FALHOU"; exit 1; }; }
row(){ sed -n "$((2+$1))p" "$C/var/placar.txt"; }   # linha de dados N (1 = primeiro colocado)
cell(){ row "$1" | cut -d: -f6; }
login(){ row "$1" | cut -d: -f2; }

echo "== default: 20 min, CE não conta =="
conf ""
build
ck "alice cell 2/10* (CE fora do counted; * = first to solve)" '[[ "$(row 1)$(row 2)" == *":alice:"*  && "$(grep ":alice:" "$C/var/placar.txt" | cut -d: -f6)" == "2/10*" ]]'
ck "bob primeiro (25 < 1*20+10=30), SEM estrela" '[[ "$(login 1)" == "bob" && "$(login 2)" == "alice" && "$(grep ":bob:" "$C/var/placar.txt" | cut -d: -f6)" == "1/25" ]]'

echo "== PENALTY_MINUTES=10 muda a ordem =="
conf 'PENALTY_MINUTES=10'
build
ck "alice primeiro (1*10+10=20 < 25)"     '[[ "$(login 1)" == "alice" ]]'

echo "== PENALTY_VERDICTS com ce: CE volta a contar (recompute em massa via .metrics-stamp) =="
conf 'PENALTY_MINUTES=10
PENALTY_VERDICTS=wa\ tle\ mle\ rte\ ce'
build
ck "alice cell 3/10* (CE conta)"          '[[ "$(grep ":alice:" "$C/var/placar.txt" | cut -d: -f6)" == "3/10*" ]]'
ck "bob primeiro de novo (2*10+10=30 > 25)" '[[ "$(login 1)" == "bob" ]]'

echo "== PENALTY_VERDICTS='' : nada penaliza (só o minuto do AC) =="
conf "PENALTY_VERDICTS=''"
build
ck "alice cell 1/10* (só o AC conta)"     '[[ "$(grep ":alice:" "$C/var/placar.txt" | cut -d: -f6)" == "1/10*" ]]'
ck "alice primeiro (10 < 25)"             '[[ "$(login 1)" == "alice" ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
