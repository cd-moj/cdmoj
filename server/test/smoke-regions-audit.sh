#!/bin/bash
# smoke-regions-audit.sh — server/bin/regions-audit.sh (o "o que muda" da regra única de sedes, rodado na
# produção antes de migrar os consumidores) ACHA as diferenças que existem. Fixture com as três famílias:
# o pai que vencia a folha (gate/materialize/etiquetas → "Brasil"), o recorte sem regex que o placar não via,
# e .cstaff com region:<nó interno> que passa a ver MAIS (etiquetas com senha). E numa árvore em que nada
# muda (sede gravada em tudo), a auditoria diz zero.
set -u
TD="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"; AUD="$TD/../bin/regions-audit.sh"
command -v gawk >/dev/null 2>&1 || { echo "regions-audit: gawk ausente — FALHA"; exit 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; export CONTESTSDIR="$T"
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1"; echo "$OUT" | head -30; ((fail++)); fi; }
C="$T/cl"; mkdir -p "$C/users" "$C/print-requests"
jq -n '[{name:"Brasil",regex:"^team",subregions:[{name:"Sudeste",regex:"^team(sp|rj)",subregions:[{name:"SP, Capital",regex:"^teamsp"},{name:"RJ, Rio",regex:"^teamrj"}]},
         {name:"Norte",regex:"^team(am|ac)",subregions:[{name:"AM, Manaus",regex:"^teamam"}]}]},
        {name:"Femininos",view:true,subregions:[{name:"F-SP",regex:"^teamsp0[13]"}]},{name:"Semregex"}]' > "$C/regions.json"
for l in teamsp01 teamsp02 teamsp03 teamrj01 teamam01 teampe01 TEAMSP09 cl.admin sp.cstaff; do mkdir -p "$C/users/$l"; done
mkdir -p "$C/users/x1"; echo '{"team":{"region":"semregex"}}' > "$C/users/x1/account.json"
echo '{"sp.cstaff":["region:Sudeste"],"f.cstaff":["region:Femininos"],"s.staff":["region:SP, Capital"],"r.staff":["^teamrj"]}' > "$C/print-requests/staff-filters.json"
OUT="$(bash "$AUD" cl 2>&1)"
ck "8 logins (sem as contas de papel), 9 nós, 2 recortes" '[[ "$OUT" == *"cl: 8 logins, 9 nós (2 recortes)"* ]]'
ck "NOVO: 1 gravada, 6 por regex numa folha, 1 parou no pai" '[[ "$OUT" == *"gravada 1 · gravada ÓRFÃ 0 · regex numa folha 6 · PAROU NO PAI 1 · sem sede 0"* ]]'
ck "o pai que vencia a folha: 6 sedes mudam no gate/materialize e nas etiquetas (teamsp01: Brasil → SP, Capital)" '[[ "$OUT" == *"SEDE mudaria p/ 6 login(s) no gate de UA/materialize e p/ 6 nas etiquetas"* && "$OUT" == *"teamsp01"*"\"Brasil\""*"NOVO: \"SP, Capital\""* ]]'
ck "recorte sem regex: o placar não via ninguém, o NOVO vê 2" '[[ "$OUT" == *"[recorte] Femininos (sem regex)"*"placar    0 → NOVO    2"* ]]'
ck "staff: 2 .cstaff passam a ver MAIS (etiquetas com senha); entrada regex (r.staff) não muda" '[[ "$OUT" == *"2 .cstaff passam a ver MAIS"* && "$OUT" == *"sp.cstaff"*"NOVO    5"* && "$OUT" != *"r.staff"* ]]'
Z="$T/z"; mkdir -p "$Z/users/a1" "$Z/users/b1"; echo '[{"name":"A","regex":"^a"},{"name":"B","regex":"^b"}]' > "$Z/regions.json"
echo '{"team":{"region":"A"}}' > "$Z/users/a1/account.json"
OUT="$(bash "$AUD" z 2>&1)"
ck "árvore sem mudança: zero em tudo" '[[ "$OUT" == *"SEDE mudaria p/ 0 login(s) no gate de UA/materialize e p/ 0 nas etiquetas"* && "$OUT" == *"MEMBROS: 0 nó(s)"* && "$OUT" == *"STAFF (region:<nome>): 0 conta(s)"* ]]'
echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail > 0 ? 1 : 0 ))
