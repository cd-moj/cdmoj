#!/bin/bash
# OS DOIS MÉTODOS DE TL (26/10/2026; mojtools tl-methods.sh, docs/PACOTE.md "Métodos de TL"). Pedido do Ribas: o
# método do Kattis first class ao lado do MOJ; os juízes medem os dois sempre e o conf (TLMETHOD) escolhe.
# Garante, do lado do servidor:
#   · /judge/tl-report guarda as DUAS metades por host (tl, tl_kattis), saneadas (lixo não vira "linguagem"); o
#     agente antigo (sem tl_kattis) segue aceito e o Kattis dele fica "não calibrado";
#   · o SERVIDO (tl_store_served: treino/contest/folha de TL) segue o TLMETHOD do conf; o TLOVERRIDE vence os dois;
#   · TROCAR o método não muda o tl_checksum nem a versão do pacote (o TL não some da prova) e o problem_commit
#     carimba o método no store e no sumário do Painel, RECALCULA o juízo das soluções (code × code_alt) em vez de
#     marcá-lo velho, e — virando kattis sem nenhum juiz com a metade Kattis — pede UMA calibração completa;
#   · /judge/calib-report guarda method/etl/code_alt/tl_alt e, na MESMA versão, JUNTA por categoria/arquivo (a
#     calibração rápida, só good, não apaga o juízo de pass/slow/wrong); com versão NOVA, substitui;
#   · /problems/calib: tl_method, time_limits_by_method, hosts[].tl_kattis, expect + expect_alt, summary_alt;
#     /problems/tl, /problems/get e /problems/status seguem o método.
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
mkpkg(){ local P="$PROBS/col/$1"; mkdir -p "$P/sols/good" "$P/sols/slow" "$P/tests/input" "$P/tests/output"
  printf 'CALIBRATIONTL=5' > "$P/conf"                       # sem \n final: a regra do tl-checksum
  printf '{"owner":"autor","public":true,"display_title":"%s"}\n' "$1" > "$P/.moj-meta.json"
  printf 'int main(){return 0;}\n' > "$P/sols/good/sol.c"; printf 'int main(){for(;;);}\n' > "$P/sols/slow/s.c"
  printf 'int main(){return 0;}\n' > "$P/sols/slow/m.c"
  printf '1\n' > "$P/tests/input/t1"; printf '1\n' > "$P/tests/output/t1"
  git -C "$P" init -q 2>/dev/null; git -C "$P" add -A 2>/dev/null
  git -C "$P" -c user.name=t -c user.email=t@t commit -qm init 2>/dev/null; }
mkpkg pa; mkpkg pb
P="$PROBS/col/pa"
fx_user "$FIX/treino" autor s "Autor"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' treino autor Autor "$NOW" > "$SESS/aut"

pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:300}"; ((fail++)); fi; }
J(){ # <rota> <query> <método> <token> [corpo]
  OUT="$(PATH_INFO="$1" REQUEST_METHOD="$3" QUERY_STRING="$2" HTTP_AUTHORIZATION="Bearer $4" bash "$ROUTER" <<<"${5:-}" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pv(){ J /judge/package-meta "id=col%23$1" GET mojw_smoketest; jq -r '.checksum // ""' <<<"$BODY"; }
tlrep(){ J /judge/tl-report "" POST mojw_smoketest "$1"; }
calrep(){ J /judge/calib-report "" POST mojw_smoketest "$1"; }
source "$ROOT/api/v1/lib/tl-store.sh"; source "$ROOT/api/v1/lib/problems.sh" 2>/dev/null
source "$ROOT/api/v1/lib/calib-expect.sh"
SF="$RUN/tl/col#pa.json"

echo "== /judge/tl-report: as duas metades, saneadas =="
PV="$(pv pa)"; [[ -n "$PV" ]] || { echo "SETUP FAIL: package-meta sem checksum"; exit 1; }
tlrep "$(jq -cn --arg c "$PV" '{host:"juiz1", id:"col#pa", checksum:$c,
  tl:{c:".3035", default:".3035", "kattis.cpp":"9", lixo:"abc"}, tl_kattis:{c:"1", default:"1", "a b":"2", x:"$(id)"}}')"
ck "aceito"                                       '[[ "$(jq -r .recorded <<<"$BODY")" == true ]]'
ck "store: tl e tl_kattis do host, sem lixo"      '[[ "$(jq -c ".hosts.juiz1.tl" "$SF")" == "{\"c\":\".3035\",\"default\":\".3035\"}" && "$(jq -c ".hosts.juiz1.tl_kattis" "$SF")" == "{\"c\":\"1\",\"default\":\"1\"}" ]]'
ck "store: o método do conf carimbado (moj)"      '[[ "$(jq -r .method "$SF")" == moj ]]'
ck "resposta traz os dois servidos"               '[[ "$(jq -r .served.c <<<"$BODY")" == 0.3035 && "$(jq -r .served_kattis.c <<<"$BODY")" == 1 ]]'
tlrep "$(jq -cn --arg c "$PV" '{host:"juiz2", id:"col#pa", checksum:$c, tl:{c:".4", default:".4"}}')"
ck "agente antigo (sem tl_kattis): aceito, sem a metade Kattis" '[[ "$(jq -r .recorded <<<"$BODY")" == true && "$(jq -r ".hosts.juiz2 | has(\"tl_kattis\")" "$SF")" == false ]]'
DBG=""
BODY="$(jq -c ".[\"col#pa\"]" "$RUN/tl-summary.json")"
ck "sumário do Painel: method + as duas metades (máx entre juízes)" '[[ "$(jq -r .method <<<"$BODY")" == moj && "$(jq -r .tl.c <<<"$BODY")" == 0.4 && "$(jq -r .tl_kattis.c <<<"$BODY")" == 1 ]]'

echo "== o servido segue o TLMETHOD do conf; o TLOVERRIDE vence os dois =="
BODY="$(tl_store_served "col#pa")"
ck "moj (sem a linha): o MOJ, máx entre juízes"   '[[ "$(jq -r .c <<<"$BODY")" == 0.4 ]]'
NCK0="$(pkg_tl_checksum "$P")"; PV0="$(pkg_judge_version "$P")"
{ printf 'TLMETHOD=kattis\n'; printf 'CALIBRATIONTL=5'; } > "$P/conf"   # no TOPO (o editor e a CLI fazem assim)
ck "TLMETHOD no conf NÃO muda o tl_checksum nem a versão do pacote" '[[ "$(pkg_tl_checksum "$P")" == "$NCK0" && "$(pkg_judge_version "$P")" == "$PV0" ]]'
BODY="$(tl_store_served "col#pa")"
ck "kattis: a metade Kattis (o juiz2, antigo, não conta)" '[[ "$(jq -c . <<<"$BODY")" == "{\"c\":\"1\",\"default\":\"1\"}" ]]'
BODY="$(tl_store_served "col#pa" "" "" moj)"
ck "o método pode ser forçado (4º arg)"           '[[ "$(jq -r .c <<<"$BODY")" == 0.4 ]]'
{ printf 'TLMETHOD=kattis\nTLOVERRIDE[default]=2.5\n'; printf 'CALIBRATIONTL=5'; } > "$P/conf"
BODY="$(tl_store_served "col#pa" "" "$NCK0")"
ck "TLOVERRIDE vence o Kattis"                    '[[ "$(jq -r .c <<<"$BODY")" == 2.5 ]]'
{ printf 'TLMETHOD=kattis\n'; printf 'CALIBRATIONTL=5'; } > "$P/conf"

echo "== /judge/calib-report: campos novos e a junção na mesma versão =="
SOLS="$(jq -cn '[
  {file:"sol.c", lang:"c", category:"good", verdict:"Accepted,100p", method:"moj", etl:7.2,
   tests:[{name:"t1", code:"AC", time:0.21, tl:5}]},
  {file:"s.c", lang:"c", category:"slow", verdict:"Time Limit Exceeded,0p", method:"moj", etl:2.5035,
   tests:[{name:"t1", code:"TLE", time:2.5035, tl:0.3035, code_alt:"TLE", tl_alt:1}]},
  {file:"m.c", lang:"c", category:"slow", verdict:"Time Limit Exceeded,0p", method:"moj", etl:2.5035,
   tests:[{name:"t1", code:"TLE", time:0.6, tl:0.3035, code_alt:"AC", tl_alt:1}], estranho:1}]')"
calrep "$(jq -cn --arg c "$PV" --argjson s "$SOLS" '{host:"juiz1", id:"col#pa", checksum:$c, log:"x", sols:$s}')"
CF="$RUN/calib/col#pa/juiz1.json"
ck "aceito"                                       '[[ "$(jq -r .recorded <<<"$BODY")" == true ]]'
ck "method/etl na linha; code_alt/tl_alt no teste; o resto morre" '[[ "$(jq -c ".sols[2] | [.method, .etl, .tests[0].code_alt, .tests[0].tl_alt, has(\"estranho\")]" "$CF")" == "[\"moj\",2.5035,\"AC\",1,false]" ]]'
calrep "$(jq -cn --arg c "$PV" '{host:"juiz1", id:"col#pa", checksum:$c, log:"rápida",
  sols:[{file:"sol.c", lang:"c", category:"good", verdict:"Accepted,100p", method:"kattis", tests:[{name:"t1", code:"AC", time:0.25, tl:5}]}]}')"
ck "MESMA versão, só as good: a good troca, as slow ficam" '[[ "$(jq -r "[.sols[] | .file] | join(\",\")" "$CF")" == "sol.c,s.c,m.c" && "$(jq -r ".sols[0].tests[0].time" "$CF")" == 0.25 ]]'

echo "== /problems/calib pelo método do conf (kattis), com o outro ao lado =="
J /problems/calib "id=col%23pa" GET aut
ck "tl_method kattis; time_limits = a metade Kattis" '[[ "$(jq -r .tl_method <<<"$BODY")" == kattis && "$(jq -r .time_limits.c <<<"$BODY")" == 1 ]]'
ck "time_limits_by_method: as duas, calibrado e efetivo" '[[ "$(jq -r .time_limits_by_method.moj.calibrated.c <<<"$BODY")" == 0.4 && "$(jq -r .time_limits_by_method.kattis.effective.c <<<"$BODY")" == 1 ]]'
ck "hosts[]: tl e tl_kattis de cada juiz"         '[[ "$(jq -r ".hosts[] | select(.host==\"juiz1\") | .tl_kattis.c" <<<"$BODY")" == 1 ]]'
X="$(jq -c '[.hosts[] | select(.host=="juiz1") | .sols[] | {f:.file, e:"\(.expect.state)/\(.expect.why)", a:"\(.expect_alt.state)/\(.expect_alt.why)"}]' <<<"$BODY")"; BODY="$X"
ck "s.c: lenta nos dois (Kattis pelo code_alt: 2,5 s ≥ 1,5 × 1 s)" '[[ "$(jq -r ".[] | select(.f==\"s.c\") | .e + \" \" + .a" <<<"$X")" == "ok/tle ok/tle" ]]'
ck "m.c: pelo Kattis NÃO é lenta (code_alt AC); pelo MOJ é" '[[ "$(jq -r ".[] | select(.f==\"m.c\") | .e + \" \" + .a" <<<"$X")" == "bad/no_tle ok/tle" ]]'
J /problems/calib "id=col%23pa" GET aut
ck "summary (Kattis): 1 divergente; summary_alt (MOJ): nenhum" '[[ "$(jq -r .summary.bad <<<"$BODY")" == 1 && "$(jq -r .summary_alt.bad <<<"$BODY")" == 0 ]]'

echo "== trocar o método (problem_commit): carimbo, sumário recalculado, calibração completa se faltar =="
printf 'CALIBRATIONTL=5' > "$P/conf"; tl_store_set_method "col#pa" moj
calx_summary_write "col#pa"; SUMF="$RUN/calib-sum/col#pa.json"
ck "antes (moj): nenhuma divergente"              '[[ "$(jq -r .bad "$SUMF")" == 0 && "$(jq -r .method "$SUMF")" == moj ]]'
{ printf 'TLMETHOD=kattis\n'; printf 'CALIBRATIONTL=5'; } > "$P/conf"
problem_commit "$P" autor "troca o método" >/dev/null
BODY="$(cat "$SUMF")"
ck "store e sumário do Painel carimbados: kattis" '[[ "$(jq -r .method "$SF")" == kattis && "$(jq -r ".[\"col#pa\"].method" "$RUN/tl-summary.json")" == kattis ]]'
ck "o juízo das soluções foi RECALCULADO (não 'velho'): m.c divergente pelo Kattis" '[[ "$(jq -r .stale "$SUMF")" == false && "$(jq -r .bad "$SUMF")" == 1 && "$(jq -r .method "$SUMF")" == kattis ]]'
ck "nada pedido p/ recalibrar (o col#pa já tem a metade Kattis)" '[[ -z "$(grep -l "col#pa" "$RUN"/updates/pending/*.json 2>/dev/null)" ]]'
J /problems/status "" GET aut
BODY="$(jq -c '.problems[] | select(.id=="col#pa")' <<<"$BODY")"
ck "/problems/status: tl_method e o TL da metade Kattis" '[[ "$(jq -r .tl_method <<<"$BODY")" == kattis && "$(jq -r .time_limits.c <<<"$BODY")" == 1 ]]'
J /problems/tl "id=col%23pa" GET aut
ck "/problems/tl: tl_method, kattis{a,b,r} e o TL Kattis" '[[ "$(jq -r .tl_method <<<"$BODY")" == kattis && "$(jq -r .kattis.b <<<"$BODY")" == 1.5 && "$(jq -r .time_limits.c <<<"$BODY")" == 1 ]]'
J /problems/get "id=col%23pa" GET aut
ck "/problems/get: tl_method e time_limits_by_method" '[[ "$(jq -r .tl_method <<<"$BODY")" == kattis && "$(jq -r .time_limits_by_method.moj.calibrated.c <<<"$BODY")" == 0.4 ]]'
# col#pb: calibrado só por juiz ANTIGO (sem a metade Kattis) — a troca pede a calibração completa
PB="$PROBS/col/pb"; PVB="$(pv pb)"
tlrep "$(jq -cn --arg c "$PVB" '{host:"juiz2", id:"col#pb", checksum:$c, tl:{c:".4", default:".4"}}')"
{ printf 'TLMETHOD=kattis\n'; printf 'CALIBRATIONTL=5'; } > "$PB/conf"
problem_commit "$PB" autor "kattis" >/dev/null
BODY="$(cat "$RUN"/updates/pending/*.json 2>/dev/null)"
ck "kattis sem nenhum juiz com a metade Kattis: UMA calibração completa pedida" '[[ "$(grep -l "\"col#pb\"" "$RUN"/updates/pending/*.json 2>/dev/null | wc -l)" == 1 && "$(jq -r "select(.target==\"col#pb\") | .kind" <<<"$BODY")" == calibrate ]]'
BODY="$(tl_store_served "col#pb")"
ck "…e até lá o Kattis não é servido (nunca o MOJ no lugar)" '[[ "$BODY" == "{}" ]]'
problem_commit "$PB" autor "de novo" >/dev/null
ck "commit seguinte sem troca não pede outra"     '[[ "$(grep -l "\"col#pb\"" "$RUN"/updates/pending/*.json 2>/dev/null | wc -l)" == 1 ]]'

echo "== /judge/calib-report com versão NOVA: substitui (a junção é só na mesma versão) =="
ck "antes: as três linhas do juiz1"               '[[ "$(jq -r "[.sols[] | .file] | join(\",\")" "$CF")" == "sol.c,s.c,m.c" ]]'
calrep "$(jq -cn '{host:"juiz1", id:"col#pa", checksum:"0123456789abcdef", log:"versão nova",
  sols:[{file:"sol.c", lang:"c", category:"good", verdict:"Accepted,100p", method:"kattis", tests:[{name:"t1", code:"AC", time:0.3, tl:5}]}]}')"
ck "só a linha do envio: as da versão velha somem" '[[ "$(jq -r "[.sols[] | .file] | join(\",\")" "$CF")" == "sol.c" && "$(jq -r ".sols[0].tests[0].time" "$CF")" == 0.3 ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
