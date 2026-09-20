#!/bin/bash
# DUAS CHAVES DO PACOTE: `tl_checksum` (estreito — o TL da prova) x `pkg_version` (largo — o cache do
# juiz e a identidade de uma calibração). Antes havia só a estreita, que ignora sols/{pass,slow,wrong}:
# o autor editava soluções, salvava, clicava Calibrar — e o juiz, vendo o mesmo checksum, recalibrava
# o `sols/` do CACHE VELHO (julgando solução apagada, ignorando a nova) e reportava sob o checksum
# atual, o que fazia a tela do editor mostrar o conjunto errado como se fosse de agora.
# Relato do Arthur Botelho, 2026-09-20 (mdp-unb-xiv#campinho: 3 juízes, 1 checksum, 3 conjuntos).
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; PROBS="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN" "$PROBS"' EXIT
source "$HERE/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" MOJ_PROBLEMS_DIR="$PROBS" \
       TL_STORE_DIR="$RUN/tl" CALIB_DIR="$RUN/calib"
mkdir -p "$RUN/tl" "$RUN/calib" "$RUN/secrets" "$FIX/treino/var"; printf 'mojw_smoketest' > "$RUN/secrets/worker.token"
NOW="$EPOCHSECONDS"
echo '{"col":{"members":["autor"],"admins":[],"public_allowed":true,"title":"Col"}}' > "$FIX/treino/var/orgs.json"
P="$PROBS/col/pa"; mkdir -p "$P/sols/good" "$P/sols/wrong" "$P/tests/input"
printf 'CALIBRATIONTL=5\n' > "$P/conf"; printf '{"owner":"autor","public":true,"display_title":"PA"}\n' > "$P/.moj-meta.json"
printf 'int main(){return 0;}\n' > "$P/sols/good/sol.c"; printf 'int main(){return 1;}\n' > "$P/sols/wrong/velha.c"; printf '1\n' > "$P/tests/input/t1"
fx_user "$FIX/treino" autor s "Autor"; printf 'CONTEST=treino\nLOGIN=autor\nUSERFULLNAME=A\nLOGINAT=%s\n' "$NOW" > "$SESS/aut"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\nCONTEST_END=%s\n' "$((NOW+86400))" > "$FIX/treino/conf"
# contest que EXIBE o TL deste problema (a regressão que não pode voltar: mexer em `wrong` não pode
# apagar o tempo-limite da prova — commit 41ec3f6)
C="$FIX/ct"; mkdir -p "$C/var" "$C/enunciados"
{ printf 'CONTEST_ID=ct\nCONTEST_NAME=P\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\n' "$((NOW-600))" "$((NOW+3600))"
  printf "PROBS=( cdmoj col/pa Alfa A 'col#pa' )\n"; } > "$C/conf"
fx_user "$C" time1 s T1; printf 'CONTEST=ct\nLOGIN=time1\nUSERFULLNAME=T\nLOGINAT=%s\n' "$NOW" > "$SESS/tk"
printf '{"problems":[{"id":"col#pa","owner":"autor","repo":"col","prob":"pa","title":"PA","public":true,"collaborators":[],"collections":["col"]}]}' > "$FIX/treino/var/problem-owners.json"

_LIBDIR="$ROOT/api/v1/lib"; source "$_LIBDIR/common.sh" 2>/dev/null; source "$_LIBDIR/tl-store.sh"
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:220}"; ((fail++)); fi; }
J(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="${3:-GET}" QUERY_STRING="${2:-}" HTTP_AUTHORIZATION="Bearer ${4:-mojw_smoketest}" bash "$ROUTER" <<<"${5:-}" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
meta(){ J /judge/package-meta "id=col%23pa"; }
calibview(){ J /problems/calib "id=col%23pa" GET aut; }
tlrep(){ J /judge/tl-report "" POST mojw_smoketest "$(jq -cn --arg h "$1" --arg c "$2" '{host:$h, id:"col#pa", checksum:$c, tl:{c:"0.100", default:"0.100"}}')"; }
calibrep(){ J /judge/calib-report "" POST mojw_smoketest "$(jq -cn --arg h "$1" --arg c "$2" --arg s "$3" '{host:$h, id:"col#pa", checksum:$c, log:"log", reports:[], sols:[{file:$s, lang:"c", category:"wrong", verdict:"Wrong Answer", tests:[]}]}')"; }
probs(){ rm -f "$C/var/"problems-cache.* 2>/dev/null; J /contest/problems "contest=ct" GET tk; }

TL0="$(pkg_tl_checksum "$P" 'col#pa')"; PV0="$(pkg_judge_version "$P" 'col#pa')"
echo "== as duas chaves =="
ck "estreito e largo são diferentes e bem formados" '[[ "$TL0" =~ ^[a-f0-9]{16}$ && "$PV0" =~ ^[a-f0-9]{16}$ && "$TL0" != "$PV0" ]]'
meta; ck "package-meta manda a VERSÃO em .checksum (o agente antigo invalida por ela)" '[[ "$(jq -r .checksum <<<"$BODY")" == "$PV0" && "$(jq -r .tl_checksum <<<"$BODY")" == "$TL0" ]]'
echo "== o juiz calibra e reporta; o TL entra sob a chave ESTREITA =="
tlrep juiz1 "$PV0"; ck "tl-report aceito"          '[[ "$(jq -r .recorded <<<"$BODY")" == true ]]'
ck "run/tl guarda o checksum ESTREITO + a versão do host" '[[ "$(jq -r .checksum "$RUN/tl/col#pa.json")" == "$TL0" && "$(jq -r ".hosts.juiz1.pkg_version" "$RUN/tl/col#pa.json")" == "$PV0" ]]'
calibrep juiz1 "$PV0" velha.c >/dev/null
probs; ck "o contest exibe o TL"                   '[[ "$(jq -r ".problems[0].time_limits.c" <<<"$BODY")" == "0.100" ]]'

echo "== autor MEXE numa solução wrong (o caso do relato) =="
rm -f "$P/sols/wrong/velha.c"; printf 'int main(){return 2;}\n' > "$P/sols/wrong/nova.c"
TL1="$(pkg_tl_checksum "$P" 'col#pa')"; PV1="$(pkg_judge_version "$P" 'col#pa')"
ck "tl_checksum NÃO muda (o TL da prova não some)" '[[ "$TL1" == "$TL0" ]]'
ck "pkg_version MUDA (o juiz re-baixa)"            '[[ "$PV1" != "$PV0" ]]'
meta; ck "package-meta já anuncia a versão nova"   '[[ "$(jq -r .checksum <<<"$BODY")" == "$PV1" ]]'
probs; ck "e o contest CONTINUA exibindo o TL"     '[[ "$(jq -r ".problems[0].time_limits.c" <<<"$BODY")" == "0.100" ]]'
calibview
ck "a tela marca o juiz como desatualizado e ESCONDE as soluções velhas" \
   '[[ "$(jq -r ".hosts[]|select(.host==\"juiz1\")|.stale" <<<"$BODY")" == true && "$(jq -r ".hosts[]|select(.host==\"juiz1\")|.sols|length" <<<"$BODY")" == 0 && "$BODY" != *velha.c* ]]'
ck "…mas o TL medido e o log do juiz continuam à vista" '[[ "$(jq -r ".hosts[]|select(.host==\"juiz1\")|.tl.c" <<<"$BODY")" == "0.100" && "$(jq -r ".hosts[]|select(.host==\"juiz1\")|.log" <<<"$BODY")" == "log" ]]'

echo "== juiz teimoso: reporta com a versão VELHA =="
tlrep juiz2 "$PV0"; ck "tl-report da versão velha: stale, nada gravado" '[[ "$(jq -r .stale <<<"$BODY")" == true && "$(jq -r ".hosts.juiz2 // \"nao\"" "$RUN/tl/col#pa.json")" == nao ]]'
echo "== juiz recalibra a versão NOVA =="
tlrep juiz1 "$PV1" >/dev/null; calibrep juiz1 "$PV1" nova.c >/dev/null
calibview
ck "host volta a NÃO estar stale, com a solução nova"  '[[ "$(jq -r ".hosts[]|select(.host==\"juiz1\")|.stale" <<<"$BODY")" == false && "$(jq -r ".hosts[]|select(.host==\"juiz1\")|.sols[0].file" <<<"$BODY")" == nova.c ]]'
ck "a resposta diz a versão atual do pacote"           '[[ "$(jq -r .version <<<"$BODY")" == "$PV1" ]]'
echo "== juiz ANTIGO (report sem versão) não é acusado de nada =="
J /judge/calib-report "" POST mojw_smoketest '{"host":"juizvelho","id":"col#pa","log":"l"}' >/dev/null
calibview; ck "sem versão no report ⇒ stale=false"     '[[ "$(jq -r ".hosts[]|select(.host==\"juizvelho\")|.stale" <<<"$BODY")" == false ]]'
echo "== CHÃO: mojtools um pull atrás (sem --all-sols) cai no estreito, nunca em vazio =="
# valor vazio aqui = `package-meta` sem checksum = o agente recusa o job ("sem checksum p/ <id>").
OLDT="$RUN/oldtools"; mkdir -p "$OLDT"
sed 's/^ALL_SOLS=0$/ALL_SOLS=0/; s/^\[\[ "${1:-}" == --all-sols \]\].*$//' "$MOJTOOLS_DIR/tl-checksum.sh" > "$OLDT/tl-checksum.sh"
rm -f "$RUN/tl/col#pa.pkv"
PVOLD="$(MOJTOOLS_DIR="$OLDT" pkg_judge_version "$P" 'col#pa')"
ck "mojtools velho ⇒ versão = carimbo estreito (status quo)" '[[ "$PVOLD" == "$(pkg_tl_checksum "$P" "col#pa")" && -n "$PVOLD" ]]'
rm -f "$RUN/tl/col#pa.pkv"

echo; echo "RESULT: $pass passed, $fail failed"; (( fail == 0 ))
