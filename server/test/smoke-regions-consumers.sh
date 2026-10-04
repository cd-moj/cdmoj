#!/bin/bash
# smoke-regions-consumers.sh — os consumidores de ESCOPO e CREDENCIAL (fase F3a) usam a regra única de sedes
# (lib/regions.sh). Numa árvore em que as regras antigas erravam:
#   • escopo do staff `region:<nó>` = pertença: `region:Sudeste` vê SP e RJ (antes: só quem tinha a sede
#     gravada igual a "Sudeste" — ninguém); sede derivada pela regex conta (antes: só a gravada); recorte;
#   • staff_regions de escopo por regex colhe a sede derivada;
#   • etiquetas: a sede é a FOLHA (antes: o 1º nó do topo — "Brasil") e o recorte do .cstaff é pela pertença;
#   • gate de UA: a sede do login é a folha (by_region da folha vale); o LOTE (Máquinas/anomalias/preflight)
#     usa a MESMA sede derivada que o login (antes: só a gravada — "esperado" divergia);
#   • materialize de times carimba a folha (antes: "Brasil");
#   • balão "1º da sede": quem só tem sede derivada entra no mapa.
set -u
TD="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"; ROOT="$TD/.."; ROUTER="$ROOT/api/v1/router.sh"
source "$TD/fixture.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" SCOREDIR="$ROOT/score"
NOW="$(date +%s)"
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-x}" \
    MOJ_JOBS_SYNC=1 bash "$ROUTER" <<<"${3:-}" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
J(){ jq -r "$1" <<<"$BODY" 2>/dev/null; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 ${3:-}"; ((fail++)); fi; }
mkses(){ printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=1\n' "$2" "$3" "$3" > "$SESS/$1"; }
mkdir -p "$FIX/treino/users"; printf 'CONTEST_ID=treino\nCONTEST_MODULES=sedes,maquinas,baloes,coortes,inscricoes\n' > "$FIX/treino/conf"
C="$FIX/rc"; mkdir -p "$C/users" "$C/var" "$C/print-requests"
printf 'CONTEST_ID=rc\nCONTEST_MODULES=sedes,maquinas,baloes,coortes,inscricoes\nCONTEST_NAME=Rc\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\n' "$((NOW-600))" "$((NOW+3600))" > "$C/conf"
jq -n '[{name:"Brasil",regex:"^team",subregions:[
          {name:"Sudeste",regex:"^team(sp|rj)",subregions:[{name:"SP",regex:"^teamsp"},{name:"RJ",regex:"^teamrj"}]},
          {name:"Norte",regex:"^teamam",subregions:[{name:"AM",regex:"^teamam"}]}]},
        {name:"Femininos",view:true,regex:"^teamsp01$"}]' > "$C/regions.json"
for u in teamsp01 teamsp02 teamrj01 teamam01 teampe01 rc.admin n.cstaff s.staff f.cstaff x.staff sp.staff; do fx_user "$C" "$u" "pw-$u" "Nome $u" >/dev/null; done
echo '{"n.cstaff":["region:Sudeste"],"s.staff":["region:sp"],"f.cstaff":["region:Femininos"],"x.staff":["^teamrj"],"sp.staff":["region:SP"]}' > "$C/print-requests/staff-filters.json"
mkses adm rc rc.admin; mkses ncs rc n.cstaff; mkses fcs rc f.cstaff

echo "== escopo do staff (lib/print.sh) =="
vis(){ ( source "$ROOT/api/v1/lib/common.sh"; source "$ROOT/api/v1/lib/auth.sh" 2>/dev/null; source "$ROOT/api/v1/lib/print.sh"
         staff_visible_logins rc "$1" | sort | tr '\n' ' ' ); }
cansee(){ ( source "$ROOT/api/v1/lib/common.sh"; source "$ROOT/api/v1/lib/auth.sh" 2>/dev/null; source "$ROOT/api/v1/lib/print.sh"
            is_admin(){ return 1; }; staff_can_see rc "$1" "$2" ) && echo sim || echo nao; }
ck "region:Sudeste vê as sedes do Sudeste (SP e RJ, derivadas pela regex)" '[[ "$(vis n.cstaff)" == "teamrj01 teamsp01 teamsp02 " ]]' "[$(vis n.cstaff)]"
ck "region:sp (minúsculas) vê só SP" '[[ "$(vis s.staff)" == "teamsp01 teamsp02 " ]]' "[$(vis s.staff)]"
ck "region:Femininos (recorte) vê teamsp01" '[[ "$(vis f.cstaff)" == "teamsp01 " ]]' "[$(vis f.cstaff)]"
ck "entrada regex (^teamrj) segue igual" '[[ "$(vis x.staff)" == "teamrj01 " ]]'
ck "staff_can_see: s.staff vê teamsp02, não teamrj01; n.cstaff vê teamrj01" '[[ "$(cansee s.staff teamsp02)" == sim && "$(cansee s.staff teamrj01)" == nao && "$(cansee n.cstaff teamrj01)" == sim ]]'
sreg(){ ( source "$ROOT/api/v1/lib/common.sh"; source "$ROOT/api/v1/lib/auth.sh" 2>/dev/null; source "$ROOT/api/v1/lib/print.sh"
          SESSION_LOGIN="$1"; staff_regions rc | tr '\n' ' ' ); }
ck "staff_regions de escopo por regex colhe a sede DERIVADA (RJ)" '[[ "$(sreg x.staff)" == "RJ " ]]' "[$(sreg x.staff)]"
ck "staff_regions de region: responde o token" '[[ "$(sreg n.cstaff)" == "Sudeste " ]]'

echo "== etiquetas (/contest/badges) =="
call /contest/badges GET '' adm 'contest=rc'
ck "a sede de teamsp01 é a FOLHA SP (antes: Brasil); teampe01 parou em Brasil" '[[ "$(J ".users[] | select(.login == \"teamsp01\") | .region")" == SP && "$(J ".users[] | select(.login == \"teampe01\") | .region")" == Brasil ]]'
call /contest/badges GET '' ncs 'contest=rc'
ck ".cstaff com region:Sudeste recebe as etiquetas de SP e RJ (3 alunos + o .staff sp.staff do escopo)" '[[ "$(J "[.users[] | select(.login | test(\"^team\")) | .login] | sort | join(\",\")")" == "teamrj01,teamsp01,teamsp02" ]]' "$(J '[.users[].login] | join(",")')"
call /contest/badges GET '' fcs 'contest=rc'
ck ".cstaff de recorte (Femininos) recebe só teamsp01" '[[ "$(J "[.users[] | select(.login | test(\"^team\")) | .login] | join(\",\")")" == teamsp01 ]]'

echo "== gate de UA (lib/ua-gate.sh) =="
cat > "$C/ua-gate.json" <<'EOF'
{ "mode":"enforce", "by_region":{"sp":"img-sp","Brasil":"img-br"}, "fallback":"img-geral", "by_regex":[], "exempt":[] }
EOF
ug(){ ( source "$ROOT/api/v1/lib/common.sh"; source "$ROOT/api/v1/lib/ua-gate.sh"; "$@" ); }
ck "ug_region_of teamsp02 = SP (a folha)" '[[ "$(ug ug_region_of rc teamsp02)" == SP ]]'
ck "by_region da FOLHA vale (e sem diferenciar maiúsculas: \"sp\"): teamsp02 → img-sp" '[[ "$(ug ug_expected rc teamsp02)" == img-sp ]]'
ck "teampe01 (parou em Brasil) → img-br; teamam01 (AM, sem regra) → fallback" '[[ "$(ug ug_expected rc teampe01)" == img-br && "$(ug ug_expected rc teamam01)" == img-geral ]]'
LOTE="$(ug ug_expected_map rc '["teamsp02","teampe01","teamam01","teamrj01"]')"
ck "o LOTE diz o mesmo que o login (a sede derivada entra no lote)" '[[ "$(jq -r .teamsp02 <<<"$LOTE")" == img-sp && "$(jq -r .teampe01 <<<"$LOTE")" == img-br && "$(jq -r .teamam01 <<<"$LOTE")" == img-geral ]]' "$LOTE"

echo "== materialize de times e balão 1º da sede =="
call /contest/admin/teams POST '{"action":"materialize"}' adm 'contest=rc'
ck "materialize carimba a FOLHA: teamsp02 → SP, teamam01 → AM (antes: Brasil)" '[[ "$(jq -r .team.region "$C/users/teamsp02/account.json")" == SP && "$(jq -r .team.region "$C/users/teamam01/account.json")" == AM ]]' "$(J .)"
rm -f "$C/users/teamsp02/account.json.bak"; jq 'del(.team.region)' "$C/users/teamsp01/account.json" > "$C/t" && mv "$C/t" "$C/users/teamsp01/account.json"
SF="$( source "$ROOT/api/v1/lib/common.sh"; source "$ROOT/api/v1/lib/print.sh"; pr_site_first_map rc | gawk -F'\t' '$1 == "R"' )"
ck "1º da sede: teamsp01 (só sede DERIVADA) está no mapa, em SP" '[[ "$SF" == *"R	teamsp01	SP"* ]]' "$SF"

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail > 0 ? 1 : 0 ))
