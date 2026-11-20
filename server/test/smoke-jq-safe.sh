#!/bin/bash
# smoke-jq-safe.sh — o embrulho do jq (lib/jq-safe.sh, 20/11/2026). Afirma:
#   • caminho normal transparente: mesma saída e o MESMO rc (0, 1 do -e, 2, 3, 5); nada a mais no stdout/stderr;
#   • argumento grande (200 KB) em --arg / --argjson vira arquivo e o resultado é o do jq com argumento pequeno — com
#     `def` no topo do programa, com `-f programa`, com o programa depois das opções; o jq cru morreria (rc 126);
#   • falha calada vai ao log (classe + quem chamou + nomes e tamanhos), NUNCA o valor dos argumentos; arquivo de entrada
#     ausente e validação de entrada (`jq -e . <<<"lixo"`) são esperados e ficam de fora;
#   • JQ_SAFE=0 = o jq cru; `set -e` não derruba quem chama; o locale do chamador não muda; o shim de jq no PATH (o
#     contador do smoke-contest-review) segue vendo as chamadas. Rode também com o jq 1.7 (receita jq17-local).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; LIB="$ROOT/api/v1/lib/jq-safe.sh"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:-}"; ((fail++)); fi; }
export JQ_SAFE_LOG="$W/jq.log"; : > "$JQ_SAFE_LOG"
# shellcheck disable=SC1090
source "$LIB"
ck "jq é a função do embrulho" '[[ "$(type -t jq)" == function ]]'
echo "usando: $(command jq --version)"

echo "== caminho normal: transparente =="
ck "saída igual"                       '[[ "$(jq -cn --arg a x --argjson b "[1,2]" "{a:\$a,b:\$b}")" == "$(command jq -cn --arg a x --argjson b "[1,2]" "{a:\$a,b:\$b}")" ]]'
jq -en 'false' >/dev/null 2>&1; r=$?; ck "-e falso: rc 1" '[[ $r == 1 ]]'
jq -n --argjson a '' . >/dev/null 2>&1; r=$?; ck "--argjson inválido: rc 2" '[[ $r == 2 ]]'
jq -n '1 +' >/dev/null 2>&1; r=$?; ck "compilação: rc 3" '[[ $r == 3 ]]'
jq -n '"x" | .a' >/dev/null 2>&1; r=$?; ck "execução: rc 5" '[[ $r == 5 ]]'
o="$(jq -n '1 +' 2>&1 >/dev/null)"; ck "o stderr é só o do jq (o embrulho não escreve nada)" '[[ "$o" == "$(command jq -n "1 +" 2>&1 >/dev/null)" ]]'

echo "== argumento grande vira arquivo =="
head -c 150000 /dev/urandom | base64 -w0 > "$W/big.txt"; BIG="$(cat "$W/big.txt")"
command jq -cn --rawfile s "$W/big.txt" '{s:$s, n:[range(3)]}' > "$W/big.json"; BIGJ="$(cat "$W/big.json")"
DBG="$(command jq -cn --arg s "$BIG" '$s|length' 2>&1)"; ck "o jq cru morre com esse argumento (o teste vale)" '[[ "$DBG" == *"Argument list too long"* ]]'
ck "--arg grande: o mesmo texto"       '[[ "$(jq -rn --arg s "$BIG" "\$s")" == "$BIG" ]]'
ck "--argjson grande: o mesmo valor"   '[[ "$(jq -cn --argjson j "$BIGJ" "\$j.n")" == "[0,1,2]" && "$(jq -rn --argjson j "$BIGJ" "\$j.s|length")" == "${#BIG}" ]]'
ck "…com def no topo do programa"      '[[ "$(jq -rn --argjson j "$BIGJ" "def f: \$j.n | add; f")" == 3 ]]'
ck "…com o programa antes das opções"  '[[ "$(jq -c "\$j.n" -n --argjson j "$BIGJ" --arg k v)" == "[0,1,2]" ]]'
printf '%s\n' 'def g: $j.n | length;' 'g' > "$W/p.jq"
ck "…com -f programa"                  '[[ "$(jq -n --argjson j "$BIGJ" -f "$W/p.jq")" == 3 ]]'
ck "…lendo a entrada padrão"           '[[ "$(printf "[5]" | jq -c --argjson j "$BIGJ" ". + \$j.n")" == "[5,0,1,2]" ]]'
ck "…grande e pequeno juntos"          '[[ "$(jq -cn --arg s "$BIG" --argjson k 7 "[(\$s|length), \$k]")" == "[${#BIG},7]" ]]'
ck "o temporário some"                 '! ls "${TMPDIR:-/tmp}"/jqsafe.* >/dev/null 2>&1 || [[ -z "$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name "jqsafe.*" -newer "$W/big.txt" 2>/dev/null)" ]]'
ck "a conversão foi ao log (nome e tamanho, sem o valor)" 'grep -q "argv-convertido" "$JQ_SAFE_LOG" && grep -q "arg:s=" "$JQ_SAFE_LOG" && ! grep -qF "${BIG:0:40}" "$JQ_SAFE_LOG"'

echo "== erro calado vai ao log =="
: > "$JQ_SAFE_LOG"
f_chama(){ jq -n '1 +' 2>/dev/null; }; f_chama
DBG="$(cat "$JQ_SAFE_LOG")"
ck "compilação com 2>/dev/null: logada, com quem chamou" 'grep -qP "^\d+\t3\tcompilacao\t" "$JQ_SAFE_LOG" && grep -q "smoke-jq-safe.sh:[0-9]*:f_chama" "$JQ_SAFE_LOG"'
: > "$JQ_SAFE_LOG"; v="$(jq -n --argjson x '' '$x' 2>/dev/null)"
ck "--argjson vazio (o dano do teams-meta): logado como uso" 'grep -qP "\t2\tuso\t" "$JQ_SAFE_LOG" && grep -q "argjson:x=0B" "$JQ_SAFE_LOG"'
: > "$JQ_SAFE_LOG"; v="$(jq -n '"x"|.a' 2>/dev/null)"
ck "execução: logada"                  'grep -qP "\t5\texecucao\t" "$JQ_SAFE_LOG"'
: > "$JQ_SAFE_LOG"; jq -r .x "$W/nao-existe.json" >/dev/null 2>&1; jq -e . >/dev/null 2>&1 <<<"lixo{"; jq -e .a >/dev/null 2>&1 <<<"[1"
DBG="$(cat "$JQ_SAFE_LOG")"; ck "arquivo de entrada ausente e validação de entrada: fora do log" '[[ ! -s "$JQ_SAFE_LOG" ]]'
: > "$JQ_SAFE_LOG"; jq -e 'type == "object"' >/dev/null 2>&1 <<<"x"; jq -n 'range(200000)' 2>/dev/null | head -1 >/dev/null
DBG="$(cat "$JQ_SAFE_LOG")"; jq -n --arg r '([' '"x" | test($r)' >/dev/null 2>&1; JQ_SAFE_EXPECT=1 jq -r .a 2>/dev/null <<<'"x"' >/dev/null
DBG="$(cat "$JQ_SAFE_LOG")"
ck "teste (saída descartada, com ou sem -e), JQ_SAFE_EXPECT=1 e SIGPIPE (| head): fora do log" '[[ ! -s "$JQ_SAFE_LOG" ]]'
: > "$JQ_SAFE_LOG"; v="$(jq -r .a 2>/dev/null <<<'"x"')"
ck "rc 5 com a saída USADA (o resultado errado e calado): logado" 'grep -qP "\t5\texecucao\t" "$JQ_SAFE_LOG"'
SENHA="s3nh4-secreta"; : > "$JQ_SAFE_LOG"; jq -n --arg p "$SENHA" '$p | 1 +' >/dev/null 2>&1
ck "o valor do argumento nunca vai ao log" '! grep -q "$SENHA" "$JQ_SAFE_LOG"'
( unset JQ_SAFE_LOG; RUNDIR="$W/run"; jq -n '1 +' >/dev/null 2>&1 ); ck "sem JQ_SAFE_LOG: o arquivo do dia em \$RUNDIR/jq-errors/" '[[ -s "$W/run/jq-errors/$(date +%F).log" ]]'
( JQ_SAFE_LOG=/proc/nao/grava; jq -n '1 +' >/dev/null 2>&1; echo "rc=$?" ) > "$W/o" 2>&1; DBG="$(cat "$W/o")"
ck "log que não se grava: ignorado, rc intacto, nada no stderr" '[[ "$DBG" == "rc=3" ]]'

echo "== chaves e convivência =="
DBG="$(JQ_SAFE=0 jq -cn --arg s "$BIG" '$s|length' 2>&1)"; ck "JQ_SAFE=0: o jq cru (morre no argv)" '[[ "$DBG" == *"Argument list too long"* ]]'
cat > "$W/se.sh" <<EOF
set -euo pipefail
source "$LIB"
x="\$(jq -cn '[1]')"; jq -en 'false' >/dev/null || true; y="\$(jq -rn --arg s "\$(cat $W/big.txt)" '\$s|length')"
echo "fim \$x \$y"
EOF
DBG="$(bash "$W/se.sh" 2>&1)"; ck "set -euo pipefail: quem chama não morre" '[[ "$DBG" == "fim [1] ${#BIG}" ]]'
DBG="$(LC_ALL=C.UTF-8 bash -c 'source "$1"; x="ação"; a=${#x}; jq -n 1 >/dev/null; b=${#x}; echo "$a $b ${LC_ALL}"' _ "$LIB")"
ck "o locale do chamador não muda (o tamanho em bytes é medido por dentro)" '[[ "$DBG" == "4 4 C.UTF-8" ]]'
mkdir -p "$W/shim"; printf '#!/bin/bash\necho x >> "%s/n"\nexec %s "$@"\n' "$W" "$(type -P jq)" > "$W/shim/jq"; chmod +x "$W/shim/jq"   # type -P: aqui `jq` é a função (command -v diria "jq")
( PATH="$W/shim:$PATH"; jq -n 1 >/dev/null; jq -n 2 >/dev/null ); ck "shim de jq no PATH segue contando" '[[ "$(wc -l < "$W/n")" == 2 ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
