#!/bin/bash
# TLOVERRIDE — o autor decide o TL "na marra" pelo conf do PACOTE (por linguagem + default).
# Garante: parse por grep (nunca source), efetivo = override[lang]//override[default]//calibrado,
# tl_store_served (o que treino/contest/docs exibem) aplica o overlay, /problems/tl mostra os
# três (efetivo + calibrado + override) e SEM override nada muda.
#
# E cobre a GESTÃO, que era o buraco (relato de um autor, 24/08/2026: "a web UI do problem
# management faz menção a TL em vários lugares, mas são sempre os calibrated TLs"). Três casos
# que estavam de fora e agora não estão:
#   /problems/get  — a tela do editor. O TL vinha do json servível PÚBLICO, que não existe em
#     problema privado (o estado de quem está calibrando): o campo sumia e o editor caía num
#     fallback client-side que mostra o MÁXIMO CRU entre juízes;
#   /problems/status — o Painel lia o sumário (`run/tl-summary.json`), que só conhece o calibrado;
#   /problems/calib  — o cartão por juiz não tinha como dizer "o julgamento usa outro número".
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

echo "== a GESTÃO mostra o efetivo (o relato de 24/08) =="
printf 'CALIBRATIONTL=5\nTLOVERRIDE[default]=1.5\nTLOVERRIDE[java]=3.0\n' > "$P/conf"
CKS4="$(pkg_tl_checksum "$P")"
tl_store_record juiz1 "col#pa" "$CKS4" '{"c":"0.033","java":"0.371","default":"0.033"}' >/dev/null
# o índice de donos é a fonte do Painel (e do checksum que o /problems/get usa)
jq -cn --arg c "$CKS4" '{generated_at:0, count:1, problems:[
   {id:"col#pa", repo:"col", prob:"pa", owner:"autor", collaborators:[], public:true,
    title:"PA", tl_checksum:$c, good_langs:["c"], tl_override:{"default":"1.5","java":"3.0"}}]}' \
  > "$FIX/treino/var/problem-owners.json"
rota(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD=GET QUERY_STRING="$2" \
    HTTP_AUTHORIZATION="Bearer aut" bash "$ROUTER" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }

rota /problems/get 'id=col%23pa'
ck "/problems/get: efetivo"          '[[ "$(jq -r .time_limits.java <<<"$BODY")" == "3.0" ]]'
ck "/problems/get: expõe o override" '[[ "$(jq -r .tl_override.default <<<"$BODY")" == "1.5" ]]'
ck "/problems/get: expõe o calibrado" '[[ "$(jq -r .time_limits_calibrated.java <<<"$BODY")" == "0.371" ]]'

# ⚠ O CASO QUE QUEBRAVA: problema PRIVADO não tem json servível público. Antes, o time_limits
# sumia da resposta e o editor mostrava o calibrado cru na coluna "servido (aluno)".
jq -c '.public=false' "$P/.moj-meta.json" > "$P/.m.t" && mv -f "$P/.m.t" "$P/.moj-meta.json"
jq -c '.problems[0].public=false' "$FIX/treino/var/problem-owners.json" > "$FIX/o.t" \
  && mv -f "$FIX/o.t" "$FIX/treino/var/problem-owners.json"
rota /problems/get 'id=col%23pa'
ck "/problems/get PRIVADO: ainda dá o efetivo" '[[ "$(jq -r .time_limits.java <<<"$BODY")" == "3.0" ]]'
jq -c '.public=true' "$P/.moj-meta.json" > "$P/.m.t" && mv -f "$P/.m.t" "$P/.moj-meta.json"
jq -c '.problems[0].public=true' "$FIX/treino/var/problem-owners.json" > "$FIX/o.t" \
  && mv -f "$FIX/o.t" "$FIX/treino/var/problem-owners.json"

rota /problems/status ''
ck "/problems/status (Painel): efetivo" \
  '[[ "$(jq -r ".problems[0].time_limits.java" <<<"$BODY")" == "3.0" ]]'
ck "/problems/status: calibrado ao lado" \
  '[[ "$(jq -r ".problems[0].time_limits_calibrated.java" <<<"$BODY")" == "0.371" ]]'
ck "/problems/status: o selo tem de onde sair" \
  '[[ "$(jq -r ".problems[0].tl_override.default" <<<"$BODY")" == "1.5" ]]'

rota /problems/calib 'id=col%23pa'
ck "/problems/calib: efetivo p/ o aviso do cartão" \
  '[[ "$(jq -r .time_limits.java <<<"$BODY")" == "3.0" ]]'
ck "/problems/calib: hosts[].tl segue sendo a MEDIÇÃO" \
  '[[ "$(jq -r ".hosts[0].tl.java" <<<"$BODY")" == "0.371" ]]'

echo "== py3/py2 é chave LEGADA: normaliza p/ py (senão exibe um TL que o juiz não aplica) =="
printf 'CALIBRATIONTL=5\nTLOVERRIDE[py3]=2.5\n' > "$P/conf"
BODY="$(tl_conf_overrides "$P")"
ck "parse normaliza py3 -> py"      '[[ "$(jq -r .py <<<"$BODY")" == "2.5" && "$(jq -r ".py3 // \"\"" <<<"$BODY")" == "" ]]'
ck "o build-and-test tem o shim gêmeo" \
  'grep -q "TLOVERRIDE\[py\]=\"\${TLOVERRIDE\[py3\]}\"" "${MOJTOOLS_DIR:-$ROOT/../../mojtools}/build-and-test.sh" 2>/dev/null'

echo "== conf é código do autor: o parse NUNCA executa =="
printf 'echo nunca-rode-isto > nunca-rode-isto\nTLOVERRIDE[c]=9\n' > "$P/conf"
BODY="$(tl_conf_overrides "$P")"
ck "parse leu o override"           '[[ "$(jq -r .c <<<"$BODY")" == "9" ]]'
ck "grep não executou o echo"       '[[ ! -e nunca-rode-isto ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
