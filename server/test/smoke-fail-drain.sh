#!/bin/bash
# smoke-fail-drain.sh — a recusa ANTES de ler o corpo consome o corpo (07/11/2026, Chile: 24 × 502 no upload de foto).
#
# O handler que falha antes do read_body (sem login, papel errado) saía sem ler o stdin, e o fcgiwrap trocava o
# 401/403 por um 502 opaco ("An error occurred while reading the request"). O mesmo mecanismo aparece num pipe:
# quem escreve o corpo leva SIGPIPE (rc 141) quando o leitor sai sem ler. Com o `fail` drenando, o escritor termina
# (rc 0) e a resposta é o erro com o motivo.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
NOW="$EPOCHSECONDS"; C="$FIX/fd"; mkdir -p "$C/var"
printf 'CONTEST_ID=fd\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nPROBS=( x col#pa Alfa A col#pa )\n' $(( NOW - 60 )) $(( NOW + 3600 )) > "$C/conf"
fx_user "$C" time-a a "Time A"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' fd time-a time-a "$NOW" > "$SESS/tok-a"
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:-}"; ((fail++)); fi; }
N=4000000
# post <path> <token|""> — 4 MB de corpo por PIPE; devolve o rc do escritor em W_RC e a resposta em OUT
post(){
  local o; o="$(mktemp)"
  head -c "$N" /dev/zero | PATH_INFO="$1" REQUEST_METHOD=POST QUERY_STRING="contest=fd" CONTENT_LENGTH="$N" \
    CONTENT_TYPE=application/json HTTP_AUTHORIZATION="${2:+Bearer $2}" REMOTE_ADDR=127.0.0.9 \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" > "$o" 2>/dev/null
  W_RC="${PIPESTATUS[0]}"; OUT="$(cat "$o")"; rm -f "$o"; DBG="writer rc=$W_RC; ${OUT:0:160}"
}
echo "== recusa antes do read_body: o corpo é consumido e o motivo chega =="
post /contest/animeitor/photo ""
ck "sem login: 401 com o motivo"            '[[ "$OUT" == *"Status: 401"* ]]'
ck "sem login: o corpo de 4 MB foi lido"    '[[ "$W_RC" == 0 ]]'
post /contest/animeitor/photo tok-a
ck "time no upload do telão: 403 com o motivo" '[[ "$OUT" == *"Status: 403"* && "$OUT" == *animeitor_required* ]]'
ck "time: o corpo foi lido"                 '[[ "$W_RC" == 0 ]]'
echo "== fail dentro de \$(…) NÃO drena: o handler ainda lê o corpo =="
R="$(mktemp)"
printf '{"x":1}' | CONTENT_LENGTH=7 REQUEST_METHOD=POST bash -c '
  source "$1/api/v1/lib/common.sh" 2>/dev/null
  v="$(fail 422 "teste" "t")"            # recusa num subshell (ex.: validação auxiliar)
  printf "%s" "$(cat -)"' _ "$ROOT" > "$R" 2>/dev/null
ck "o corpo segue inteiro p/ o processo principal" '[[ "$(cat "$R")" == "{\"x\":1}" ]]'
rm -f "$R"
echo "== GET e corpo vazio: nada muda =="
OUT="$(PATH_INFO=/contest/animeitor/photo REQUEST_METHOD=GET QUERY_STRING=contest=fd CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" </dev/null 2>/dev/null)"
ck "GET recusado responde na hora"          '[[ "$OUT" == *"Status: 4"* ]]'
echo; echo "RESULT: $pass passed, $fail failed"; (( fail == 0 ))
