#!/bin/bash
# smoke-tl-mods.sh — o TL EXIBIDO com o TLMOD[<lang>.sum|.mult] do conf (26/10/2026). O juiz faz
# (tabela[L] // tabela[default]) + sum, × mult, e o TLOVERRIDE (final) por cima; o servidor exibia a tabela crua —
# 404 pacotes têm TLMOD[spim.sum]=1, e a página da prova mostrava 1 s a menos do que o juiz cobra.
# Confere: o leitor do conf (sem source), a regra única `tl_eff` contra o PRÓPRIO trecho do build-and-test, as
# rotas que exibem TL (get, tl, calib, ops/problemtl, status), o carimbo `tl_mods` do índice de donos e do json
# servível (mojtools) e a cópia LITERAL da regra no gen-problem-json.sh.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
: "${MOJTOOLS_DIR:=$(cd "$ROOT/../../mojtools" 2>/dev/null && pwd)}"; export MOJTOOLS_DIR
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; PROBS="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN" "$PROBS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" MOJ_PROBLEMS_DIR="$PROBS" TL_STORE_DIR="$RUN/tl"
mkdir -p "$RUN/tl" "$FIX/treino/var/jsons" "$FIX/treino/var/jsons-private"
NOW="$EPOCHSECONDS"
echo '{"col":{"members":["autor"],"admins":[],"public_allowed":true,"title":"Col"}}' > "$FIX/treino/var/orgs.json"
P="$PROBS/col/pa"; mkdir -p "$P/sols/good" "$P/tests/input" "$P/tests/output" "$P/docs"
printf '{"owner":"autor","public":true,"display_title":"PA"}\n' > "$P/.moj-meta.json"
printf 'int main(){return 0;}\n' > "$P/sols/good/sol.c"
printf '1\n' > "$P/tests/input/sample1"; printf '1\n' > "$P/tests/output/sample1"
printf '# PA\n\n## Entrada\n\nx\n\n## Saída\n\ny\n' > "$P/docs/enunciado.md"
fx_user "$FIX/treino" autor s "Autor"; fx_user "$FIX/treino" autor.admin s "Admin"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' treino autor Autor "$NOW" > "$SESS/aut"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' treino autor.admin Admin "$NOW" > "$SESS/adm"

pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:-${BODY:0:300}}"; ((fail++)); fi; DBG=""; }
rota(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD=GET QUERY_STRING="$2" HTTP_AUTHORIZATION="Bearer ${3:-aut}" bash "$ROUTER" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
near(){ awk -v a="$1" -v b="$2" 'BEGIN { d = a - b; if (d < 0) d = -d; exit !(a != "" && b != "" && d < 1e-6) }'; }
source "$ROOT/api/v1/lib/tl-store.sh"

echo "== tl_conf_mods: só sum/mult de linguagem CANÔNICA; a última linha vence; o resto fica de fora =="
cat > "$P/conf" <<'EOF'
CALIBRATIONTL=5
TLMOD[spim.sum]=1
#TLMOD[c.sum]=9
TLMOD[java.drift]=0.02
TLMOD[calibrafactor]=1.35
TLMOD[py3.sum]=7
TLMOD[default.sum]=5
TLMOD[cpp.mult]=1.5
TLMOD[cpp.sum]=.5
TLMOD[spim.sum]=2 # a última vence, como no source do juiz
TLMOD[go.sum]=abc
TLMOD[rs.sum]=-0.1
echo nunca-rode-isto > nunca-rode-isto
EOF
BODY="$(cd "$RUN" && tl_conf_mods "$P")"
ck "sum spim=2 (a última), cpp=0,5, rs=−0,1; mult cpp=1,5" '[[ "$(jq -c . <<<"$BODY")" == "{\"sum\":{\"spim\":2,\"cpp\":0.5,\"rs\":-0.1},\"mult\":{\"cpp\":1.5}}" ]]'
ck "o conf não foi executado"                       '[[ ! -e "$RUN/nunca-rode-isto" ]]'
printf 'CALIBRATIONTL=5\nTLMOD[java.drift]=0.02\n' > "$PROBS/x.conf"; mkdir -p "$PROBS/x"; mv "$PROBS/x.conf" "$PROBS/x/conf"
ck "conf sem sum/mult = {}"                         '[[ "$(tl_conf_mods "$PROBS/x")" == "{}" && "$(tl_conf_mods "$PROBS/nada")" == "{}" ]]'

echo "== a regra é a do JUIZ: o trecho do build-and-test e o tl_eff dão o mesmo TL =="
BAT="$MOJTOOLS_DIR/build-and-test.sh"
blk="$(sed -n '/^\[\[ ! -n "\${TL\[\$LANGUAGE\]}" \]\] && TL\[\$LANGUAGE\]=\${TL\[default\]}$/,/^# TOLERÂNCIA (drift)/p' "$BAT" | sed '$d')"
DBG="$(head -c 300 <<<"$blk")"
ck "achou o trecho (TLMOD sum/mult + TLOVERRIDE) no build-and-test" '[[ "$blk" == *".sum]"* && "$blk" == *".mult]"* && "$blk" == *TLOVERRIDE* ]]'
TABLE='TL[c]=.3035; TL[cpp]=0.2; TL[default]=.3035'
judge_tl(){ # <lang> <linhas do conf> -> o TL[lang] que o juiz cobra (o trecho do b-a-t, sem calibração)
  bash -c 'declare -A TL TLMOD TLOVERRIDE; LOG(){ :; }; LANGUAGE="$1"; eval "$2"; eval "$3"; eval "$4"; printf "%s" "${TL[$LANGUAGE]}"' \
    _ "$1" "$TABLE" "$2" "$blk" 2>/dev/null; }
CAL='{"c":".3035","cpp":"0.2","default":".3035"}'
for conf in 'TLMOD[spim.sum]=2; TLMOD[cpp.sum]=.5; TLMOD[cpp.mult]=1.5; TLMOD[rs.sum]=-0.1; TLMOD[py3.sum]=7' \
            'TLMOD[spim.sum]=1; TLOVERRIDE[cpp]=1' \
            'TLMOD[c.mult]=3; TLOVERRIDE[default]=2'; do
  printf '%s\n' "${conf//; /$'\n'}" > "$P/conf"
  srv="$(tl_override_apply "$CAL" "$(tl_conf_overrides "$P")" "$(tl_conf_mods "$P")")"
  for L in c cpp spim rs java py; do
    j="$(judge_tl "$L" "$conf")"; s="$(jq -r --arg l "$L" '.[$l] // .default' <<<"$srv")"
    DBG="conf=[$conf] L=$L juiz=$j servidor=$s"
    ck "[$conf] $L: juiz $j = servidor $s" 'near "$j" "$s"'
  done
done

echo "== o servido (contest/problems, docs da prova, juízo das soluções): as duas metades =="
printf 'CALIBRATIONTL=5\nTLMOD[spim.sum]=2\nTLMOD[cpp.sum]=.5\nTLMOD[cpp.mult]=1.5\n' > "$P/conf"
( cd "$P" && git init -q && git add -A && git -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm init )
CKS="$(pkg_tl_checksum "$P")"
tl_store_record juiz1 "col#pa" "$CKS" "$CAL" "" '{"c":"1","cpp":"1","default":"1"}' >/dev/null
BODY="$(tl_store_served "col#pa")"
ck "MOJ: spim = 0,3035 + 2; cpp = (0,2 + 0,5) × 1,5; c intocado" '[[ "$(jq -r .spim <<<"$BODY")" == 2.3035 && "$(jq -r .cpp <<<"$BODY")" == 1.05 && "$(jq -r .c <<<"$BODY")" == 0.3035 ]]'
BODY="$(tl_store_served "col#pa" "" "" kattis)"
ck "Kattis: spim = 1 + 2; cpp = (1 + 0,5) × 1,5"   '[[ "$(jq -r .spim <<<"$BODY")" == 3 && "$(jq -r .cpp <<<"$BODY")" == 2.25 ]]'
printf 'CALIBRATIONTL=5\n' > "$P/conf"
BODY="$(tl_store_served "col#pa" "" "$CKS")"
ck "sem TLMOD: o servido é a tabela crua (nada muda)" '[[ -n "$BODY" && "$BODY" == "$(tl_store_served_for "col#pa" "$CKS")" ]]'
printf 'CALIBRATIONTL=5\nTLMOD[spim.sum]=2\nTLMOD[cpp.sum]=.5\nTLMOD[cpp.mult]=1.5\n' > "$P/conf"

echo "== as rotas de gestão: time_limits com o TLMOD, tl_mods ao lado, o calibrado cru intocado =="
CKSIDX="$(pkg_tl_checksum "$P")"
jq -cn --arg c "$CKSIDX" '{generated_at:0, count:1, problems:[
   {id:"col#pa", repo:"col", prob:"pa", owner:"autor", collaborators:[], public:true, title:"PA",
    tl_checksum:$c, good_langs:["c"], tl_override:{}, tl_mods:{sum:{spim:2, cpp:0.5}, mult:{cpp:1.5}}}]}' \
  > "$FIX/treino/var/problem-owners.json"
tl_store_record juiz1 "col#pa" "$CKSIDX" "$CAL" "" '{"c":"1","cpp":"1","default":"1"}' >/dev/null
rota /problems/tl 'id=col%23pa'
ck "/problems/tl: efetivo, tl_mods e as duas metades" '[[ "$(jq -r .time_limits.spim <<<"$BODY")" == 2.3035 && "$(jq -r .tl_mods.sum.spim <<<"$BODY")" == 2 && "$(jq -r .time_limits_by_method.kattis.effective.cpp <<<"$BODY")" == 2.25 && "$(jq -r ".time_limits_calibrated.spim // \"-\"" <<<"$BODY")" == - ]]'
rota /problems/get 'id=col%23pa'
ck "/problems/get: efetivo e tl_mods"              '[[ "$(jq -r .time_limits.cpp <<<"$BODY")" == 1.05 && "$(jq -r .tl_mods.mult.cpp <<<"$BODY")" == 1.5 ]]'
rota /problems/calib 'id=col%23pa'
ck "/problems/calib: efetivo p/ o quadro; hosts[].tl segue a medição" '[[ "$(jq -r .time_limits.spim <<<"$BODY")" == 2.3035 && "$(jq -r .time_limits_by_method.moj.effective.cpp <<<"$BODY")" == 1.05 && "$(jq -r ".hosts[0].tl.cpp" <<<"$BODY")" == 0.2 && "$(jq -r .tl_mods.sum.cpp <<<"$BODY")" == 0.5 ]]'
rota /ops/problemtl 'problem=col%23pa' adm
ck "/ops/problemtl: efetivo e tl_mods"             '[[ "$(jq -r .time_limits.spim <<<"$BODY")" == 2.3035 && "$(jq -r .tl_mods.sum.spim <<<"$BODY")" == 2 ]]'
rota /problems/status ''
ck "/problems/status (Painel): efetivo pelo tl_mods do índice, sem abrir pacote" '[[ "$(jq -r ".problems[0].time_limits.spim" <<<"$BODY")" == 2.3035 && "$(jq -r ".problems[0].time_limits.cpp" <<<"$BODY")" == 1.05 && "$(jq -r ".problems[0].tl_mods.sum.spim" <<<"$BODY")" == 2 ]]'

echo "== mojtools: o índice de donos carimba tl_mods; o json servível do treino aplica a regra =="
if [[ -f "$MOJTOOLS_DIR/gen-problem-owners.sh" && -f "$MOJTOOLS_DIR/gen-problem-json.sh" ]]; then
  printf 'CALIBRATIONTL=5\nTLMOD[spim.sum]=2\nTLMOD[py3.sum]=7\nTLMOD[cpp.mult]=1.5\n' > "$P/conf"
  ( cd "$P" && git add -A && git -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm conf )
  bash "$MOJTOOLS_DIR/gen-problem-owners.sh" >/dev/null 2>&1
  BODY="$(cat "$FIX/treino/var/problem-owners.json" 2>/dev/null)"
  ck "problem-owners: tl_mods (py3 fora: o juiz não o aplica)" '[[ "$(jq -c ".problems[] | select(.id == \"col#pa\") | .tl_mods" <<<"$BODY")" == "{\"sum\":{\"spim\":2},\"mult\":{\"cpp\":1.5}}" ]]'
  tl_store_record juiz1 "col#pa" "$(pkg_tl_checksum "$P")" "$CAL" >/dev/null
  TREINO_JSONS="$FIX/treino/var/jsons" MOJ_TL_STORE="$RUN/tl" bash "$MOJTOOLS_DIR/gen-problem-json.sh" "$P" "col#pa" >/dev/null 2>&1
  J="$FIX/treino/var/jsons-private/col#pa.json"; [[ -s "$J" ]] || J="$FIX/treino/var/jsons/col#pa.json"
  BODY="$(jq -c .time_limits "$J" 2>/dev/null)"
  ck "json servível: spim = 0,3035 + 2; cpp = 0,2 × 1,5 (= o servidor)" '[[ "$(jq -r .spim <<<"$BODY")" == 2.3035 && "$(jq -r .cpp <<<"$BODY")" == 0.3 && "$BODY" == "$(tl_store_served "col#pa" | jq -c .)" ]]'
  DBG="$(diff <(sed -n "/^_TL_EFF_DEF='/,/^'/p" "$MOJTOOLS_DIR/gen-problem-json.sh") <(sed -n "/^_TL_EFF_DEF='/,/^'/p" "$ROOT/api/v1/lib/tl-store.sh"))"
  ck "a cópia da regra no gen-problem-json.sh é LITERAL" '[[ -n "$(sed -n "/^_TL_EFF_DEF=/p" "$MOJTOOLS_DIR/gen-problem-json.sh")" && -z "$DBG" ]]'
else
  echo "  (sem mojtools ao lado: pulado)"
fi

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
