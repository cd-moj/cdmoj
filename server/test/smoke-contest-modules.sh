#!/bin/bash
# smoke-contest-modules.sh — MÓDULOS ligáveis do contest (lib/modules.sh + admin/modules.sh):
# catálogo, ligar/desligar (CONTEST_MODULES), exposição em /contest/basic e /contest/admin/settings,
# preflight só com módulo ligado + aviso de "desligado com dados", spec de criação (modules{} e
# compat com regions/colors no topo), export/template carregam, detector dry-run/apply/idempotente.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
NOW="$(date +%s)"; FUT=$(( NOW + 100000 ))
mkdir -p "$FIX/treino/var/jsons" "$FIX/treino/users"
mkc(){ # <id> [extra conf lines]
  local C="$FIX/$1"; mkdir -p "$C/var" "$C/enunciados"
  { printf 'CONTEST_ID=%s\nCONTEST_TYPE=treino\nCONTEST_NAME=%s\nCONTEST_START=%s\nCONTEST_END=%s\n' "$1" "$1" "$((NOW-3600))" "$FUT"
    printf "PROBS=( cdmoj p/a 'Prob A' A 'p#a' )\n"; printf '%s' "${2:-}"; } > "$C/conf"
  fx_user "$C" "$1.admin" p Admin; fx_user "$C" alice a Alice
  printf 'CONTEST=%s\nLOGIN=%s.admin\nLOGINAT=1\n' "$1" "$1" > "$SESS/adm-$1"
  printf 'CONTEST=%s\nLOGIN=alice\nLOGINAT=1\n' "$1" > "$SESS/usr-$1"
}
mkc ev; mkc lista
E="$FIX/ev"
printf '{"cohorts":[{"id":"oficial","name":"Oficiais","default":true,"public":true}]}' > "$E/cohorts.json"
printf '{"mode":"enforce","from_login":{"regex":"^team([a-z]{6})","expect":"\\\\1"}}' > "$E/ua-gate.json"
printf '{"active":"aq","rounds":[{"slug":"aq","name":"Aquecimento","kind":"warmup","start":1,"end":2,"state":"active"}]}' > "$E/rounds.json"
printf '[{"name":"Sorocaba","regex":"^teambrspso"}]' > "$E/regions.json"
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-adm-ev}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" bash "$ROUTER" <<<"${3:-}" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
J(){ jq -r "$1" <<<"$BODY" 2>/dev/null; }
confmods(){ ( CONTEST_MODULES=""; source "$1/conf" 2>/dev/null; printf '%s' "$CONTEST_MODULES" ); }   # %q escapa a vírgula: leia como o sistema lê
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:220}"; ((fail++)); fi; }

echo "== catálogo e detecção =="
call /contest/admin/modules GET '' adm-ev 'contest=ev'
ck "GET: 9 módulos, nenhum ligado"           '[[ "$(J ".modules|length")" == 9 && "$(J ".enabled|length")" == 0 ]]'
ck "detected: coortes/maquinas/rodadas/sedes true, baloes false" '[[ "$(J "[.modules[]|select(.detected)|.id]|join(\",\")")" == "sedes,maquinas,rodadas,coortes" ]]'
ck "reason cita o artefato"                  '[[ "$(J ".modules[]|select(.id==\"maquinas\")|.reason")" == "ua-gate.json" ]]'
call /contest/admin/modules GET '' usr-ev 'contest=ev'
ck "competidor não vê (403)"                 '[[ "$OUT" == *"Status: 403"* ]]'

echo "== ligar / desligar =="
call /contest/admin/modules POST '{"on":["maquinas","coortes","xis"]}' adm-ev 'contest=ev'
ck "id desconhecido => 422 module_invalid"   '[[ "$(J .error.code)" == module_invalid ]]'
call /contest/admin/modules POST '{"on":["coortes","maquinas"]}' adm-ev 'contest=ev'
ck "ligou 2 (ordem do catálogo)"             '[[ "$(J ".enabled|join(\",\")")" == "maquinas,coortes" ]]'
ck "conf CONTEST_MODULES=maquinas,coortes"   '[[ "$(confmods "$E")" == "maquinas,coortes" ]]'
ck "audit modules-set"                       'grep -q "	modules-set	on=coortes,maquinas" "$E/var/admin-audit.log"'
call /contest/admin/modules POST '{"off":["coortes"],"on":["rodadas"]}' adm-ev 'contest=ev'
ck "off+on: maquinas,rodadas"                '[[ "$(J ".enabled|join(\",\")")" == "maquinas,rodadas" ]]'
ck "desligar preserva o arquivo (cohorts.json fica)" '[[ -s "$E/cohorts.json" ]]'

echo "== exposição =="
call /contest/basic GET '' adm-ev 'contest=ev'
ck "basic.modules"                           '[[ "$(J ".modules|join(\",\")")" == "maquinas,rodadas" ]]'
call /contest/admin/settings GET '' adm-ev 'contest=ev'
ck "settings.modules"                        '[[ "$(J ".modules|join(\",\")")" == "maquinas,rodadas" ]]'
call /contest/basic GET '' adm-lista 'contest=lista'
ck "lista: basic.modules = []"               '[[ "$(J ".modules|length")" == 0 ]]'

echo "== preflight por módulo =="
call /contest/admin/preflight GET '' adm-lista 'contest=lista'
ck "lista: sem checagens de evento"          '[[ -z "$(J ".checks[]|select(.id==\"ua_gate\" or .id==\"cohorts\" or .id==\"docs\" or .id==\"next_round\" or .id==\"balloons\")|.id")" ]]'
ck "lista: modules ok 'Sem módulos'"         '[[ "$(J ".checks[]|select(.id==\"modules\")|.level")" == ok ]]'
ck "lista: mode ok mesmo em treino"          '[[ "$(J ".checks[]|select(.id==\"mode\")|.level")" == ok ]]'
call /contest/admin/preflight GET '' adm-ev 'contest=ev'
ck "ev: ua_gate e next_round presentes (módulos ligados)" '[[ -n "$(J ".checks[]|select(.id==\"ua_gate\")|.id")" && -n "$(J ".checks[]|select(.id==\"next_round\")|.id")" ]]'
ck "ev: cohorts OMITIDA (coortes desligado)" '[[ -z "$(J ".checks[]|select(.id==\"cohorts\")|.id")" ]]'
ck "ev: modules warn cita coortes e sedes com dados" '[[ "$(J ".checks[]|select(.id==\"modules\")|.level")" == warn && "$(J ".checks[]|select(.id==\"modules\")|.detail")" == *"coortes (cohorts.json)"* && "$(J ".checks[]|select(.id==\"modules\")|.detail")" == *"sedes (regions.json)"* ]]'
ck "ev: mode em treino com módulo ligado => warn" '[[ "$(J ".checks[]|select(.id==\"mode\")|.level")" == warn ]]'

echo "== spec de criação: modules{} e compat =="
mkdir -p "$FIX/treino/users/criador"; fx_user "$FIX/treino" criador c "Criador"
printf 'CONTEST=treino\nLOGIN=criador\nLOGINAT=1\n' > "$SESS/cri"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=treino\nCONTEST_START=1\nCONTEST_END=%s\nPROBS=( )\n' "$FUT" > "$FIX/treino/conf"
fx_user "$FIX/treino" treino.admin p Admin
printf 'CONTEST=treino\nLOGIN=treino.admin\nLOGINAT=1\n' > "$SESS/tadm"
SPEC="$(jq -cn --argjson s "$((NOW+600))" --argjson e "$((NOW+4200))" '{id:"novo1", name:"Novo 1", mode:"icpc", start:$s, end:$e, allow_empty:true,
  modules:{maquinas:true, rodadas:{on:false}, documentos:{config:{}}}}')"
call /treino/contest-create/create POST "$SPEC" tadm ''
ck "create: sucesso"                         '[[ "$(J .success)" == true ]]'
ck "create: CONTEST_MODULES=maquinas,documentos (rodadas on:false fora)" '[[ "$(confmods "$FIX/novo1")" == "maquinas,documentos" ]]'
SPEC2="$(jq -cn --argjson s "$((NOW+600))" --argjson e "$((NOW+4200))" '{id:"novo2", name:"Novo 2", mode:"icpc", start:$s, end:$e, allow_empty:true,
  regions:[{name:"X", regex:"^x"}], colors:{A:"#f00"}}')"
call /treino/contest-create/create POST "$SPEC2" tadm ''
ck "compat: regions/colors no topo ligam sedes,baloes" '[[ "$(confmods "$FIX/novo2")" == "sedes,baloes" ]]'
call /treino/contest-create/export GET '' tadm 'id=novo1'
ck "export traz modules{maquinas,documentos}" '[[ "$(J ".modules|keys|join(\",\")")" == "documentos,maquinas" ]]'

echo "== detector =="
D="$ROOT/bin/contest-modules-detect.sh"
out="$(CONTESTSDIR="$FIX" RUNDIR="$RUN" bash "$D" 2>"$FIX/det.err")"
ck "dry-run: ev ligaria sedes,coortes (união com maquinas,rodadas)" '[[ "$(grep "^ev	" <<<"$out" | cut -f2,3)" == "ligaria	sedes,maquinas,rodadas,coortes" ]]'
ck "dry-run: lista sem artefato"             '[[ "$(grep "^lista	" <<<"$out" | cut -f2)" == nenhum ]]'
ck "dry-run não grava"                       '[[ "$(confmods "$E")" == "maquinas,rodadas" ]]'
ck "resumo no stderr fala em dry-run"        'grep -q "dry-run" "$FIX/det.err"'
CONTESTSDIR="$FIX" RUNDIR="$RUN" bash "$D" --apply >/dev/null 2>&1
ck "apply grava a união"                     '[[ "$(confmods "$E")" == "sedes,maquinas,rodadas,coortes" ]]'
ck "apply audita"                            'grep -q "	modules-detect	" "$E/var/admin-audit.log"'
out2="$(CONTESTSDIR="$FIX" RUNDIR="$RUN" bash "$D" --apply 2>&1 >/dev/null)"
ck "2º apply: 0 com módulo novo (idempotente)" '[[ "$out2" == *"com módulo novo: 0"* ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
