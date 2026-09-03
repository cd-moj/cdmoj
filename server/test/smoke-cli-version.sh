#!/bin/bash
# smoke-cli-version.sh — aviso de CLI desatualizada (lib/cli-version.sh): toda resposta a uma CLI
# (UA "moj[-tool]/<build>") leva X-Moj-Cli-Status (current|outdated|dev) + X-Moj-Cli-Latest
# (= web/moj.build); CLI ANTIGA (UA curl/* + Bearer, sem marcador) vira "legacy" e ganha a dica
# "rode moj update" NA error.message (é o que ela imprime). Navegador e curl cru: nada.
set -u
cd "$(dirname "$0")"; ROUTER="$(pwd)/../api/v1/router.sh"; BUILDF="$(pwd)/../../web/moj.build"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; mkdir -p "$T/c" "$T/s"
LATEST="$(head -1 "$BUILDF")"; [[ -n "$LATEST" ]] || { echo "FAIL: web/moj.build vazio"; exit 1; }
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD=GET QUERY_STRING="" HTTP_USER_AGENT="${2:-}" HTTP_AUTHORIZATION="${3:-}" HTTP_HOST=moj.test \
    MOJ_CLI_BUILD_FILE="${4:-$BUILDF}" CONTESTSDIR="$T/c" SESSIONDIR="$T/s" bash "$ROUTER" </dev/null 2>&1)"
  HDRS="$(printf '%s\n' "$OUT" | awk '/^\r?$/{exit} {print}')"; BODY="$(printf '%s\n' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: $(printf '%s' "$HDRS" | tr '\r\n' '  ' | cut -c1-200) :: ${BODY:0:160}"; ((fail++)); fi; }
st(){ printf '%s\n' "$HDRS" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-moj-cli-status"{print $2}'; }
lt(){ printf '%s\n' "$HDRS" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-moj-cli-latest"{print $2}'; }
msg(){ jq -r '.error.message // ""' <<<"$BODY" 2>/dev/null; }

echo "== CLI atual (marcador no UA) =="
call /rota-que-nao-existe "moj/0000000-20200101"
ck "build antiga → outdated + Latest=$LATEST"          '[[ "$(st)" == outdated && "$(lt)" == "$LATEST" ]]'
ck "CLI atual NÃO ganha dica na mensagem (lê o cabeçalho)" '[[ "$(msg)" != *"moj update"* ]]'
call /rota-que-nao-existe "Mozilla/5.0 (X11; Linux x86_64) Gecko/20100101 Firefox/148.0 moj-comp/$LATEST"
ck "moj-comp na build servida (UA da máquina na frente) → current" '[[ "$(st)" == current && "$(lt)" == "$LATEST" ]]'
call /rota-que-nao-existe "moj-contest/dev"
ck "build dev → dev (não julga)"                        '[[ "$(st)" == dev ]]'
call /rota-que-nao-existe "moj-judges/abcdef0-29991231"
ck "mais nova que o servidor → current"                 '[[ "$(st)" == current ]]'
call /rota-que-nao-existe "moj/0000000-${LATEST##*-}"
ck "mesma data, hash diferente → outdated"              '[[ "$(st)" == outdated ]]'
call /rota-que-nao-existe "moj/0000000-20200101" "" "$T/nao-existe.build"
ck "sem web/moj.build (sem referência) → nenhum cabeçalho" '[[ -z "$(st)" && -z "$(lt)" ]]'

echo "== CLI antiga (curl/* + Bearer, sem marcador) =="
call /rota-que-nao-existe "curl/8.5.0" "Bearer abc123"
ck "legacy no cabeçalho"                                '[[ "$(st)" == legacy && "$(lt)" == "$LATEST" ]]'
ck "dica anexada à mensagem: update + build servida + URL do /moj" '[[ "$(msg)" == *"moj update"* && "$(msg)" == *"$LATEST"* && "$(msg)" == *"https://moj.test/moj"* ]]'
ck "corpo continua JSON válido com success:false"       '[[ "$(jq -r .success <<<"$BODY")" == false ]]'

echo "== quem não é CLI: nada muda =="
call /rota-que-nao-existe "Mozilla/5.0 (X11; Linux x86_64) Gecko/20100101 Firefox/148.0"
ck "navegador: sem X-Moj-Cli, sem dica"                 '[[ -z "$(st)" && "$(msg)" != *"moj update"* ]]'
call /rota-que-nao-existe "curl/8.5.0"
ck "curl cru sem Bearer: sem X-Moj-Cli, sem dica"       '[[ -z "$(st)" && "$(msg)" != *"moj update"* ]]'
call /rota-que-nao-existe ""
ck "sem UA: nada"                                       '[[ -z "$(st)" ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
