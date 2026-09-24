#!/bin/bash
# smoke-verdict-scored.sh — o CONTRATO entre o mojtools (score-summary.sh) e o servidor p/ problema
# pontuado por GRUPOS (tests/score).
#
# Até 24/09/2026 o juiz mandava "Wrong,<n>p. Pontos | …" (e verdict_canon "Wrong Answer") em TODA falha
# de grupo — o aluno lia "resposta errada" num TLE/RE/MLE (relato do Ribas). Agora a string é
# "<veredicto canônico>,<n>p. Pontos | … quantitativos …" e pacote quebrado é "Judge Error,0p. …".
# O que o aluno vê é o PREFIXO dessa string (o history a guarda; os handlers a canonizam na leitura),
# então este teste prende, do lado do servidor:
#   1. canon/canon_team (awk) e vcanon (jq) — os GÊMEOS — dão a classe certa p/ as strings novas E as
#      legadas ("Wrong,60p. …", "Wrong. Pontos | …"; o history é imutável e fica como está);
#   2. metrics_recompute tira a NOTA certa (1º NNp) e não marca resolvido o que não é Accepted;
#   3. PENALTY_VERDICTS passa a valer pela classe real (TLE pontuado não conta com só "wa").
# Rode também com o jq 1.7 (o jq do canon mora em variável — o jq-portability.sh não o compila).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX"
source "$ROOT/api/v1/lib/users.sh"      # sourceia o lib/verdict.sh
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:-}"; ((fail++)); fi; }

# string do juiz <TAB> classe esperada <TAB> nota esperada (o legado "Wrong. Pontos" não tem NNp: tentativa = 0)
CASES="$(cat <<'EOF'
Accepted,100p. Pontos | 30 | 70 |	Accepted	100
Wrong Answer,30p. Pontos | 30 | 0 | quantitativos WA(2) AC(8)	Wrong Answer	30
Time Limit Exceeded,30p. Pontos | 30 | 0 | quantitativos TLE(1) AC(3)	Time Limit Exceeded	30
Time Limit Exceeded,100p. Pontos | 0 | 30 | 70 | quantitativos TLE(1) AC(2)	Time Limit Exceeded	100
Runtime Error,30p. Pontos | 30 | 0 | quantitativos RE_NZEC(1) AC(2)	Runtime Error	30
Memory Limit Exceeded,30p. Pontos | 30 | 0 | quantitativos MLE(1) AC(2)	Memory Limit Exceeded	30
Judge Error,0p. teste 'extra1' sem grupo em tests/score (erro do pacote)	Judge Error	0
Judge Error,0p. grupo sem teste em tests/score (erro do pacote). Pontos | 30 | -1 | quantitativos AC(2)	Judge Error	0
Wrong,60p. Pontos | 30 | 0 | 30 |	Wrong Answer	60
Wrong. Pontos | 0 | quantitativos WA(10) AC(20)	Wrong Answer	0
Accepted,100p. Pontos | 100 |	Accepted	100
EOF
)"

echo "== canon (awk) × vcanon (jq): as duas implementações dão a MESMA classe =="
while IFS=$'\t' read -r s want _; do
  a="$(printf '%s\n' "$s" | awk "$VERDICT_CANON_AWK"'{ print canon($0) "|" canon_team($0) }')"
  j="$(jq -rn --arg s "$s" "$VERDICT_CANON_JQ"'$s | vcanon')"
  DBG="awk=$a jq=$j"
  ck "${s:0:48}… → $want" '[[ "$a" == "$want|$want" && "$j" == "$want" ]]'
done <<<"$CASES"

echo "== metrics_recompute: a nota é o 1º NNp; só Accepted resolve =="
C="$FIX/obi"; mkdir -p "$C/var"
printf 'CONTEST_ID=obi\nCONTEST_TYPE=obi\nCONTEST_START=1000\nCONTEST_END=999999999\n' > "$C/conf"
fx_user "$C" aluno x "Aluno"
i=0; : > "$C/users/aluno/history"
while IFS=$'\t' read -r s want pts; do
  i=$((i+1)); printf '%s:p#%s:c:%s:%s:%s\n' "$((1000+i))" "$i" "$s" "$((1000+i))" "$i" >> "$C/users/aluno/history"
done <<<"$CASES"
metrics_recompute obi aluno
M="$C/users/aluno/metrics.json"
i=0
while IFS=$'\t' read -r s want pts; do
  i=$((i+1))
  got="$(jq -r --arg p "p#$i" '.by_problem[$p] | "\(.best_score // "null")|\(.solved)"' "$M" 2>/dev/null)"
  exp_solved=false; [[ "$want" == Accepted ]] && exp_solved=true
  DBG="got=$got"
  ck "${s:0:40}… → nota $pts, resolvido=$exp_solved" '[[ "${got%%|*}" == "$pts" && "${got#*|}" == "$exp_solved" ]]'
done <<<"$CASES"

echo "== PENALTY_VERDICTS vale pela classe REAL (consequência deliberada do conserto) =="
C2="$FIX/pen"; mkdir -p "$C2/var"
{ printf 'CONTEST_ID=pen\nCONTEST_TYPE=icpc\nCONTEST_START=1000\nCONTEST_END=999999999\n'
  printf "PENALTY_VERDICTS='wa'\n"; } > "$C2/conf"
fx_user "$C2" novo x "Novo"; fx_user "$C2" velho x "Velho"
{ printf '1:p#a:c:Time Limit Exceeded,30p. Pontos | 30 | 0 | quantitativos TLE(1) AC(3):1100:1\n'
  printf '2:p#a:c:Accepted,100p. Pontos | 30 | 70 |:1200:2\n'; } > "$C2/users/novo/history"
{ printf '1:p#a:c:Wrong,30p. Pontos | 30 | 0 | quantitativos TLE(1) AC(3):1100:1\n'
  printf '2:p#a:c:Accepted,100p. Pontos | 30 | 70 |:1200:2\n'; } > "$C2/users/velho/history"
metrics_recompute pen novo; metrics_recompute pen velho
cn="$(jq -r '.by_problem["p#a"].counted' "$C2/users/novo/metrics.json")"
cv="$(jq -r '.by_problem["p#a"].counted' "$C2/users/velho/metrics.json")"
DBG="novo=$cn velho=$cv"
ck "só \"wa\" penaliza: o TLE pontuado NÃO conta (1 = só o AC)"          '[[ "$cn" == 1 ]]'
ck "…o \"Wrong,\" legado segue lido como WA e conta (2) — history imutável" '[[ "$cv" == 2 ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
