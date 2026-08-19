#!/bin/bash
# TLOVERRIDE — o autor decide o TL "na marra" pelo conf do PACOTE (por linguagem + default).
# Garante: parse por grep (nunca source), efetivo = override[lang]//override[default]//calibrado,
# tl_store_served (o que treino/contest/docs exibem) aplica o overlay, /problems/tl mostra os
# três (efetivo + calibrado + override) e SEM override nada muda.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; PROBS="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN" "$PROBS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" \
       MOJ_PROBLEMS_DIR="$PROBS" TL_STORE_DIR="$RUN/tl"
mkdir -p "$RUN/tl" "$FIX/treino/var"

NOW="$EPOCHSECONDS"
# problema col#pa: org col com membro autor; pacote com conf SEM override (começa cru)
echo '{"col":{"members":["autor"],"admins":[],"public_allowed":true,"title":"Col"}}' > "$FIX/treino/var/orgs.json"
P="$PROBS/col/pa"; mkdir -p "$P/sols/good" "$P/tests/input"
printf 'CALIBRATIONTL=5\n' > "$P/conf"
printf '{"owner":"autor","public":true,"display_title":"PA"}\n' > "$P/.moj-meta.json"
printf 'int main(){return 0;}\n' > "$P/sols/good/sol.c"
printf '1\n' > "$P/tests/input/t1"
fx_user "$FIX/treino" autor s "Autor"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' treino autor Autor "$NOW" > "$SESS/aut"

pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }
tlget(){ OUT="$(PATH_INFO=/problems/tl REQUEST_METHOD=GET QUERY_STRING="id=col%23pa" \
    HTTP_AUTHORIZATION="Bearer aut" bash "$ROUTER" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }

source "$ROOT/api/v1/lib/tl-store.sh"
CKS="$(pkg_tl_checksum "$P")"
tl_store_record juiz1 "col#pa" "$CKS" '{"c":"0.033","java":"0.371","default":"0.033"}' >/dev/null

echo "== sem override: served = calibrado cru (nada muda) =="
BODY="$(tl_store_served "col#pa")"
ck "served == calibrado"            '[[ "$(jq -r .c <<<"$BODY")" == "0.033" && "$(jq -r .java <<<"$BODY")" == "0.371" ]]'
tlget
ck "/problems/tl efetivo = calibrado" '[[ "$(jq -r .time_limits.c <<<"$BODY")" == "0.033" ]]'
ck "tl_override vazio"              '[[ "$(jq -r ".tl_override | length" <<<"$BODY")" == 0 ]]'

echo "== com override: efetivo = override[lang] // override[default] // calibrado =="
{ printf 'CALIBRATIONTL=5\nTLOVERRIDE[default]=1.5\nTLOVERRIDE[java]=3.0\n'
  printf 'TLOVERRIDE[lixo]=abc\necho nunca-rode-isto\n'; } > "$P/conf"
BODY="$(tl_conf_overrides "$P")"
ck "parse pega default+java"        '[[ "$(jq -r .default <<<"$BODY")" == "1.5" && "$(jq -r .java <<<"$BODY")" == "3.0" ]]'
ck "valor não-numérico é rejeitado" '! jq -e .lixo <<<"$BODY" >/dev/null 2>&1'
# o conf mudou ⇒ checksum novo ⇒ recalibra (staleness fica como está — comportamento desenhado)
CKS2="$(pkg_tl_checksum "$P")"
tl_store_record juiz1 "col#pa" "$CKS2" '{"c":"0.033","java":"0.371","default":"0.033"}' >/dev/null
BODY="$(tl_store_served "col#pa")"
ck "served: java = override"        '[[ "$(jq -r .java <<<"$BODY")" == "3.0" ]]'
ck "served: c cai no default do override" '[[ "$(jq -r .c <<<"$BODY")" == "1.5" ]]'
ck "served: default = override"     '[[ "$(jq -r .default <<<"$BODY")" == "1.5" ]]'
tlget
ck "/problems/tl: efetivo = override" '[[ "$(jq -r .time_limits.java <<<"$BODY")" == "3.0" && "$(jq -r .time_limits.default <<<"$BODY")" == "1.5" ]]'
ck "/problems/tl expõe o override"  '[[ "$(jq -r .tl_override.java <<<"$BODY")" == "3.0" ]]'
ck "/problems/tl expõe o calibrado cru" 'jq -e "has(\"time_limits_calibrated\")" <<<"$BODY" >/dev/null'

echo "== override SEM default: só a linguagem citada muda; o resto segue o calibrado =="
printf 'CALIBRATIONTL=5\nTLOVERRIDE[java]=3.0\n' > "$P/conf"
CKS3="$(pkg_tl_checksum "$P")"
tl_store_record juiz1 "col#pa" "$CKS3" '{"c":"0.033","java":"0.371","default":"0.033"}' >/dev/null
BODY="$(tl_store_served "col#pa")"
ck "java = override"                '[[ "$(jq -r .java <<<"$BODY")" == "3.0" ]]'
ck "c segue o calibrado"            '[[ "$(jq -r .c <<<"$BODY")" == "0.033" ]]'
ck "default segue o calibrado"      '[[ "$(jq -r .default <<<"$BODY")" == "0.033" ]]'

echo "== conf é código do autor: o parse NUNCA executa =="
printf 'echo nunca-rode-isto > nunca-rode-isto\nTLOVERRIDE[c]=9\n' > "$P/conf"
BODY="$(tl_conf_overrides "$P")"
ck "parse leu o override"           '[[ "$(jq -r .c <<<"$BODY")" == "9" ]]'
ck "grep não executou o echo"       '[[ ! -e nunca-rode-isto ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
