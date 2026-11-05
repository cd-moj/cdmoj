#!/bin/bash
# TL ÚNICO (05/11/2026; mojtools tl_unify_table, docs/PACOTE.md "TL único"). Pedido do Roberto p/ a LATAM: o mesmo TL em
# toda linguagem, como se todas as good fossem de uma linguagem só. A tabela dos juízes segue POR LINGUAGEM; o único é o
# MÁX dela (as duas fórmulas crescem com o W), aplicado no tl_eff antes do TLMOD e do override. Garante, do lado do
# servidor:
#   · tl_conf_mods leva `unified: true` com TLUNIFIED=y (sem source; a última linha vence) e o tl_eff unifica;
#   · o servido (tl_store_served: contest, folha de TL) e as rotas de gestão (get/tl/calib/status) unificam e dizem
#     `tl_unified`, nos dois métodos; o TLOVERRIDE por linguagem segue por cima;
#   · TLUNIFIED MUDA o tl_checksum (ligar recalibra: as pass/slow/wrong são julgadas de novo pelo único).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
: "${MOJTOOLS_DIR:=$(cd "$ROOT/../../mojtools" 2>/dev/null && pwd)}"; export MOJTOOLS_DIR
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; PROBS="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN" "$PROBS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" MOJ_PROBLEMS_DIR="$PROBS" TL_STORE_DIR="$RUN/tl" \
       CALIB_DIR="$RUN/calib" UPDATESDIR="$RUN/updates"
mkdir -p "$RUN/tl" "$RUN/calib" "$RUN/secrets" "$FIX/treino/var"; printf 'mojw_smoketest' > "$RUN/secrets/worker.token"
NOW="$EPOCHSECONDS"
echo '{"col":{"members":["autor"],"admins":[],"public_allowed":true,"title":"Col"}}' > "$FIX/treino/var/orgs.json"
P="$PROBS/col/pa"; mkdir -p "$P/sols/good" "$P/tests/input" "$P/tests/output"
printf 'CALIBRATIONTL=5\n' > "$P/conf"
printf '{"owner":"autor","public":true,"display_title":"pa"}\n' > "$P/.moj-meta.json"
printf 'int main(){return 0;}\n' > "$P/sols/good/a.c"; printf 'print(1)\n' > "$P/sols/good/b.py"
printf '1\n' > "$P/tests/input/t1"; printf '1\n' > "$P/tests/output/t1"
git -C "$P" init -q 2>/dev/null; git -C "$P" add -A 2>/dev/null
git -C "$P" -c user.name=t -c user.email=t@t commit -qm init 2>/dev/null
fx_user "$FIX/treino" autor s "Autor"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' treino autor Autor "$NOW" > "$SESS/aut"

pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:300}"; ((fail++)); fi; }
J(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$3" QUERY_STRING="$2" HTTP_AUTHORIZATION="Bearer $4" bash "$ROUTER" <<<"${5:-}" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
source "$ROOT/api/v1/lib/tl-store.sh"; source "$ROOT/api/v1/lib/problems.sh" 2>/dev/null
setconf(){ printf '%s\n' "$1" > "$P/conf"; problem_commit "$P" autor "conf" >/dev/null 2>&1; }
report(){ local c; J /judge/package-meta "id=col%23pa" GET mojw_smoketest; c="$(jq -r '.checksum // ""' <<<"$BODY")"
  J /judge/tl-report "" POST mojw_smoketest "$(jq -cn --arg c "$c" '{host:"juiz1", id:"col#pa", checksum:$c,
    tl:{c:".3035", py:"1.775", default:".3035"}, tl_kattis:{c:"1", py:"3", default:"1"}}')"; }

echo "== tl_conf_mods: o unified vai no mesmo objeto do TLMOD =="
md(){ printf '%s\n' "$1" > "$P/conf"; BODY="$(tl_conf_mods "$P")"; }
md 'CALIBRATIONTL=5';                          ck "sem a chave: {}"                    '[[ "$BODY" == "{}" ]]'
md 'TLUNIFIED=y';                              ck "TLUNIFIED=y: {unified:true}"        '[[ "$(jq -c . <<<"$BODY")" == "{\"unified\":true}" ]]'
md $'TLUNIFIED=y\nTLMOD[spim.sum]=1';          ck "junto com o TLMOD"                   '[[ "$(jq -c . <<<"$BODY")" == "{\"sum\":{\"spim\":1},\"mult\":{},\"unified\":true}" ]]'
md $'TLUNIFIED=y\nTLUNIFIED=n';                ck "a última linha vence"                '[[ "$BODY" == "{}" ]]'
md 'TLUNIFIED="y" # LATAM';                    ck "entre aspas, com comentário"         '[[ "$(jq -r .unified <<<"$BODY")" == true ]]'
md "TLUNIFIED=\$(touch $RUN/pwned)y";          ck "conf envenenado não executa nada"    '[[ ! -e "$RUN/pwned" && "$BODY" == "{}" ]]'

echo "== tl_checksum: a chave está DENTRO (ligar recalibra) =="
printf 'CALIBRATIONTL=5\n' > "$P/conf"; C0="$(pkg_tl_checksum "$P")"
printf 'CALIBRATIONTL=5\nTLUNIFIED=y\n' > "$P/conf"; C1="$(pkg_tl_checksum "$P")"
BODY="$C0 $C1"; ck "TLUNIFIED muda o carimbo estreito" '[[ -n "$C0" && "$C0" != "$C1" ]]'

echo "== o servido: por linguagem × único (MOJ e Kattis) =="
setconf 'CALIBRATIONTL=5'; report
BODY="$(tl_store_served "col#pa")"
ck "sem a chave: por linguagem (c 0,3035, py 1,775, default o menor)" '[[ "$(jq -c "[.c, .py, .default]" <<<"$BODY")" == "[\"0.3035\",\"1.775\",\"0.3035\"]" ]]'
setconf $'CALIBRATIONTL=5\nTLUNIFIED=y'; report
BODY="$(tl_store_served "col#pa")"
ck "TLUNIFIED=y: o máx (1,775) em toda linguagem e no default" '[[ "$(jq -c "[.c, .py, .default]" <<<"$BODY")" == "[\"1.775\",\"1.775\",\"1.775\"]" ]]'
BODY="$(tl_store_served "col#pa" "" "" kattis)"
ck "e no Kattis: 3 em toda linguagem"            '[[ "$(jq -c "[.c, .py, .default]" <<<"$BODY")" == "[\"3\",\"3\",\"3\"]" ]]'
setconf $'CALIBRATIONTL=5\nTLUNIFIED=y\nTLOVERRIDE[c]=0.5'; report
BODY="$(tl_store_served "col#pa")"
ck "o TLOVERRIDE por linguagem segue por cima (c 0,5; py e default 1,775)" '[[ "$(jq -c "[.c, .py, .default]" <<<"$BODY")" == "[\"0.5\",\"1.775\",\"1.775\"]" ]]'

echo "== as rotas de gestão dizem tl_unified e servem o único =="
setconf $'CALIBRATIONTL=5\nTLUNIFIED=y'; report
J /problems/get "id=col%23pa" GET aut
ck "/problems/get: tl_unified e time_limits unificados" '[[ "$(jq -c "[.tl_unified, .time_limits.c, .time_limits.py]" <<<"$BODY")" == "[true,\"1.775\",\"1.775\"]" ]]'
ck "…e o calibrado cru segue por linguagem" '[[ "$(jq -r .time_limits_calibrated.c <<<"$BODY")" == ".3035" || "$(jq -r .time_limits_calibrated.c <<<"$BODY")" == "0.3035" ]]'
ck "…e time_limits_by_method unifica as duas metades" '[[ "$(jq -c "[.time_limits_by_method.moj.effective.c, .time_limits_by_method.kattis.effective.c]" <<<"$BODY")" == "[\"1.775\",\"3\"]" ]]'
J /problems/tl "id=col%23pa" GET aut
ck "/problems/tl: idem"                      '[[ "$(jq -c "[.tl_unified, .time_limits.c]" <<<"$BODY")" == "[true,\"1.775\"]" ]]'
J /problems/calib "id=col%23pa" GET aut
ck "/problems/calib: tl_unified e o efetivo unificado" '[[ "$(jq -c "[.tl_unified, .time_limits.c]" <<<"$BODY")" == "[true,\"1.775\"]" ]]'
bash "$MOJTOOLS_DIR/gen-problem-owners.sh" >/dev/null 2>&1
J /problems/status "" GET aut
BODY="$(jq -c '.problems[] | select(.id=="col#pa")' <<<"$BODY")"
ck "/problems/status: tl_unified (índice de donos) e o TL unificado" '[[ "$(jq -c "[.tl_unified, .time_limits.c]" <<<"$BODY")" == "[true,\"1.775\"]" ]]'
setconf 'CALIBRATIONTL=5'; report
J /problems/get "id=col%23pa" GET aut
ck "de volta ao por linguagem: tl_unified false e c 0,3035" '[[ "$(jq -c "[.tl_unified, .time_limits.c]" <<<"$BODY")" == "[false,\"0.3035\"]" ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
