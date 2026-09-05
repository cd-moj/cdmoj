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

echo "== spec UNIFICADO: todas as seções gravam arquivo/conf e voltam no export (sem segredo) =="
SPEC3="$(jq -cn --argjson s "$((NOW+600))" --argjson e "$((NOW+4200))" '{id:"novo3", name:"Novo 3", mode:"icpc", start:$s, end:$e, allow_empty:true,
  modules:{
    sedes:{regions:[{name:"Sorocaba",regex:"^teambrspso"}], teams_meta:[{regex:"^teambr",country:"BR"}], time_overrides:[{regex:"^teambrspso",end:($e+600),reason:"queda"}]},
    baloes:{colors:{A:"FF0000"}, during_freeze:true},
    coortes:{cohorts:[{id:"ccl",name:"Convidados",regex:"^ccl",public:false}]},
    maquinas:{ua_gate:{mode:"enforce",from_login:{regex:"^team([a-z]{6})",expect:"\\1"}}, site_lock:{enabled:true,grace:1200}, nutella_url:"https://nb.example/api"},
    rodadas:{active:"aq", rounds:[{slug:"aq",name:"Aquecimento",kind:"warmup",start:$s,end:$e,state:"active"},{slug:"prova",name:"Prova",kind:"official",start:($e+3600),end:($e+7200),state:"pending"}]},
    documentos:{config:{caderno_version:"v2", cover_note:"nota", published:["x"]}},
    inscricoes:{enabled:true, window:{open:($s-86400), close:$s, late_minutes:30, team_max:40, teams:false, warmup_open:true}},
    telao:{views:[{view:"public",label:"telão"}]},
    classificacao:{algorithm:"sbc-fase1", config:{r1:4, region:"Brasil"}}}}')"
call /treino/contest-create/create POST "$SPEC3" tadm ''
ck "create unificado: sucesso"               '[[ "$(J .success)" == true ]]'
N3="$FIX/novo3"
ck "conf: 9 módulos ligados"                 '[[ "$(confmods "$N3")" == "sedes,maquinas,rodadas,documentos,baloes,coortes,inscricoes,telao,classificacao" ]]'
ck "conf: BALLOONS_DURING_FREEZE/SITE_LOCK/GRACE/NUTELLA/REG_*" 'grep -q "^BALLOONS_DURING_FREEZE=1" "$N3/conf" && grep -q "^SITE_LOCK=1" "$N3/conf" && grep -q "^SITE_LOCK_GRACE=1200" "$N3/conf" && grep -q "^NUTELLABOOT_URL=" "$N3/conf" && grep -q "^REG_LATE_MINUTES=30" "$N3/conf" && grep -q "^REG_TEAM_MAX=40" "$N3/conf" && grep -q "^REG_TEAMS=n" "$N3/conf" && grep -q "^REG_WARMUP_OPEN=y" "$N3/conf"'
ck "arquivos: regions/teams-meta/time-overrides" '[[ "$(jq -r ".[0].name" "$N3/regions.json")" == Sorocaba && "$(jq -r ".rules[0].country" "$N3/teams-meta.json")" == BR && "$(jq -r ".[0].reason" "$N3/time-overrides.json")" == queda ]]'
ck "arquivos: balloons/cohorts/ua-gate"      '[[ "$(jq -r ".A" "$N3/balloons.json")" == FF0000 && "$(jq -r ".cohorts[0].public" "$N3/cohorts.json")" == false && "$(jq -r ".from_login.regex" "$N3/ua-gate.json")" == "^team([a-z]{6})" ]]'
ck "arquivos: rounds (ativa=aq, prova pending)" '[[ "$(jq -r ".active" "$N3/rounds.json")" == aq && "$(jq -r ".rounds[1].state" "$N3/rounds.json")" == pending ]]'
ck "arquivos: docs/config sem published; registrations vazio" '[[ "$(jq -r ".caderno_version" "$N3/docs/config.json")" == v2 && "$(jq -r ".published|length" "$N3/docs/config.json")" == 0 && "$(jq -r ".entries|length" "$N3/registrations.json")" == 0 ]]'
ck "arquivos: webcast com CHAVE NOVA (mojwc_) p/ a view" '[[ "$(jq -r ".keys[0].key" "$N3/webcast.json")" == mojwc_* && "$(jq -r ".keys[0].view" "$N3/webcast.json")" == public ]]'
ck "arquivos: classification stage draft com algorithm" '[[ "$(jq -r ".stages[0].status" "$N3/classification.json")" == draft && "$(jq -r ".stages[0].config.algorithm" "$N3/classification.json")" == sbc-fase1 && "$(jq -r ".stages[0].config.r1" "$N3/classification.json")" == 4 ]]'
call /treino/contest-create/export GET '' tadm 'id=novo3'
ck "export: 9 seções"                        '[[ "$(J ".modules|length")" == 9 ]]'
ck "export: sedes/baloes/coortes com dados"  '[[ "$(J ".modules.sedes.regions[0].name")" == Sorocaba && "$(J ".modules.sedes.time_overrides|length")" == 1 && "$(J ".modules.baloes.colors.A")" == FF0000 && "$(J ".modules.baloes.during_freeze")" == true && "$(J ".modules.coortes.cohorts[0].id")" == ccl ]]'
ck "export: maquinas com ua_gate/site_lock/nutella_url" '[[ "$(J ".modules.maquinas.ua_gate.mode")" == enforce && "$(J ".modules.maquinas.site_lock.grace")" == 1200 && "$(J ".modules.maquinas.nutella_url")" == "https://nb.example/api" ]]'
ck "export: rodadas/documentos/inscricoes"   '[[ "$(J ".modules.rodadas.rounds|length")" == 2 && "$(J ".modules.documentos.config.caderno_version")" == v2 && "$(J ".modules.inscricoes.enabled")" == true && "$(J ".modules.inscricoes.window.team_max")" == 40 && "$(J ".modules.inscricoes.window.teams")" == false ]]'
ck "export: telao só view/label — NENHUMA chave" '[[ "$(J ".modules.telao.views[0].view")" == public && "$(grep -c mojwc_ <<<"$BODY")" == 0 ]]'
ck "export: classificacao algorithm+config"  '[[ "$(J ".modules.classificacao.algorithm")" == sbc-fase1 && "$(J ".modules.classificacao.config.r1")" == 4 ]]'
ck "export: nada de regions/colors no TOPO"  '[[ "$(J "has(\"regions\") or has(\"colors\") or has(\"teams_meta\")")" == false ]]'
EXP3="$BODY"
echo "== duplicate desloca rodadas; template tira o que é preso a data =="
call /treino/contest-create/duplicate POST "$(jq -cn --argjson s "$((NOW+90000))" '{from:"novo3", id:"novo3b", start:$s}')" tadm ''
ck "duplicate: sucesso"                      '[[ "$(J .success)" == true ]]'
ck "duplicate: rounds deslocadas pelo delta (+89400)" '[[ "$(jq -r ".rounds[0].start" "$FIX/novo3b/rounds.json")" == "$((NOW+90000))" && "$(jq -r ".rounds[1].start" "$FIX/novo3b/rounds.json")" == "$((NOW+90000+3600+3600))" ]]'
ck "duplicate: sem time-overrides; módulos iguais" '[[ ! -e "$FIX/novo3b/time-overrides.json" && "$(confmods "$FIX/novo3b")" == "$(confmods "$N3")" ]]'
ck "duplicate: webcast com chave DIFERENTE"  '[[ "$(jq -r ".keys[0].key" "$FIX/novo3b/webcast.json")" != "$(jq -r ".keys[0].key" "$N3/webcast.json")" ]]'
call /treino/contest-create/templates POST '{"op":"save","name":"t3","from_contest":"novo3"}' tadm ''
ck "template salvo"                          '[[ "$(J .success)" == true ]]'
call /treino/contest-create/templates GET '' tadm 'name=t3'
ck "template: modules presente, sem rounds/time_overrides/active" '[[ "$(J ".template.spec.modules|length")" == 9 && "$(J ".template.spec.modules.rodadas|has(\"rounds\")")" == false && "$(J ".template.spec.modules.sedes|has(\"time_overrides\")")" == false && "$(J ".template.spec.modules.baloes.colors.A")" == FF0000 ]]'
call /treino/contest-create/create POST "$(jq -cn '{modules:{sedes:"sim"}, id:"ruim", name:"Ruim", mode:"icpc", end:9999999999, allow_empty:true}')" tadm ''
ck "seção com tipo errado => 422 modules_spec_invalid" '[[ "$OUT" == *"Status: 422"* && "$(J .error.code)" == modules_spec_invalid ]]'
ck "422 não deixa staging"                   '[[ -z "$(ls -d "$FIX"/.staging-ruim-* 2>/dev/null)" && ! -e "$FIX/ruim" ]]'
echo "== classificação: catálogo de algoritmos =="
printf 'CONTEST=novo3\nLOGIN=novo3.admin\nLOGINAT=1\n' > "$SESS/adm-novo3"
fx_user "$N3" novo3.admin p Admin 2>/dev/null || true
call /contest/admin/classify GET '' adm-novo3 'contest=novo3'
ck "GET classify: algorithms[] com sbc-fase1" '[[ "$(J ".algorithms[0].id")" == sbc-fase1 && "$(J ".stages[0].config.algorithm")" == sbc-fase1 ]]'
call /contest/admin/classify POST '{"action":"preview","config":{"algorithm":"pda-2030"}}' adm-novo3 'contest=novo3'
ck "preview com algoritmo desconhecido => 422 algorithm_invalid" '[[ "$OUT" == *"Status: 422"* && "$(J .error.code)" == algorithm_invalid ]]'

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
