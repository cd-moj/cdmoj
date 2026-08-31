#!/bin/bash
# smoke-classify-br.sh — motor das regras da Final Brasileira (classify-br.sh). Cobre:
#   r0: campeão de sede com 2 problemas ELEGÍVEL; 2 problemas sem ser campeão NÃO
#       (inclusive na regra 4 — feminina inelegível fica de fora e a vaga sobra);
#   r1: ≤2 por escola (o 3º da mesma escola pula p/ o próximo elegível);
#   r2 sede normal: escola com time na r1 BLOQUEADA; ≤1 por escola nesta regra;
#   r2 supersede: ≤1 por sede membra + resolve o pai certo (nó regional ≠ supersede);
#   r4: ignora limite de escola e não repete classificado; convidado não consome nada.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
export CONTESTSDIR="$FIX"
C="$FIX/cb"; mkdir -p "$C/var" "$C/enunciados"
NOW=$(date +%s); T0=$(( NOW - 7200 ))
{ printf 'CONTEST_ID=cb\nCONTEST_TYPE=icpc\nCONTEST_NAME=Classify\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$T0" "$(( NOW + 3600 ))"
  printf 'PROBS=( x col#p1 P1 A col#p1 x col#p2 P2 B col#p2 x col#p3 P3 C col#p3 x col#p4 P4 D col#p4 x col#p5 P5 E col#p5 )\n'
} > "$C/conf"
jq -cn '{version:1, results_released:true, cohorts:[
  {id:"oficial", name:"Oficiais", regex:"", public:true, unranked:false, ranking:false, default:true},
  {id:"conv", name:"Convidados", regex:"^teamspg", public:false, unranked:true, ranking:false, default:false, sees:["oficial","conv"]}]}' \
  > "$C/cohorts.json"

jq -n '[
  {name:"Brasil", regex:"^team", subregions:[
    {name:"Sudeste", regex:"^team(sp|rj)", subregions:[
      {name:"SP, Capital", regex:"^teamsp"},
      {name:"RJ, Rio", regex:"^teamrj"}]},
    {name:"Norte", regex:"^team(am|ac)", subregions:[
      {name:"AM, Manaus", regex:"^teamam"},
      {name:"AC, Rio Branco", regex:"^teamac"}]},
    {name:"Supersede Norte", regex:"^team(am|ac)", view:true, subregions:[
      {name:"AM, Manaus", regex:"^teamam"},
      {name:"AC, Rio Branco", regex:"^teamac"}]}]},
  {name:"Times femininos", regex:"^(teamsp03|teamam01|teamsp05|teamrj03)", view:true, subregions:[
    {name:"3 competidoras", regex:"^(teamsp03)", view:true,
     subregions:[{name:"Brasil", regex:"^(teamsp03)"}]},
    {name:"2 competidoras", regex:"^(teamam01|teamsp05)", view:true,
     subregions:[{name:"Brasil", regex:"^(teamam01|teamsp05)"}]},
    {name:"1 competidora", regex:"^(teamrj03)", view:true,
     subregions:[{name:"Brasil", regex:"^(teamrj03)"}]}]}]' > "$C/regions.json"

# times pelo STORE REAL (history -> build.sh -> placar), como em produção.
# mkteam <login> <univ> <nome> <min,min,...> : 1 AC por problema (col#p1..pk) nos minutos dados
mkteam(){
  local login="$1" univ="$2" name="$3" mins="$4"
  mkdir -p "$C/users/$login"
  jq -cn --arg l "$login" --arg u "$univ" --arg n "$name" \
    '{login:$l, fullname:$n, password:"x", team:{univ_short:$u, univ_full:("Univ "+$u), flag:"br", region:""}}' \
    > "$C/users/$login/account.json"
  : > "$C/users/$login/history"
  local i=0 m se
  for m in ${mins//,/ }; do
    i=$((i+1)); se=$(( T0 + m*60 ))
    printf '%s:col#p%d:C:Accepted:%s:id%s%d\n' "$se" "$i" "$se" "$login" "$i" >> "$C/users/$login/history"
  done
}
mkteam teamspg  GUEST   "Convidado"           "1,1,1,1,1"   # convidado (coorte conv)
mkteam teamsp01 USP     "USP Alfa"            "1,2,3,4,5"   # 5 probs pen15
mkteam teamsp02 USP     "USP Beta"            "2,3,4,5,6"   # 5 probs pen20
mkteam teamsp03 USP     "USP Gama Fem3"       "1,2,3,4"     # 4 pen10 (3ª da USP: fora da r1)
mkteam teamrj01 UFRJ    "UFRJ Alfa"           "2,3,4,5"     # 4 pen14 (r1 #3)
mkteam teamsp04 UNICAMP "UNICAMP Alfa"        "3,4,5,6"     # 4 pen18 (r2 SP)
mkteam teamsp05 UNICAMP "UNICAMP Beta Fem2"   "4,5,6,7"     # 4 pen22 (r4 f2)
mkteam teamsp06 MACK    "MACK Alfa"           "1,2,3"       # 3 pen6  (r2 SP 2ª vaga)
mkteam teamrj02 UFF     "UFF Alfa"            "3,4,5"       # 3 pen12 (r2 RJ)
mkteam teamam01 UFAM    "UFAM Alfa Fem2"      "4,5,6"       # 3 pen15 (r2 supersede)
mkteam teamam02 UFAM    "UFAM Beta"           "5,6,7"       # 3 pen18 (fora: sede AM usada)
mkteam teamac01 CACO    "CACO Campeao"        "1,2"         # 2 pen3  campeão AC (r2 supersede)
mkteam teamrj03 PUC     "PUC Fem1 NaoCampeao" "2,3"         # 2 pen5  (fora: r0)

( cd "$ROOT/score" && CONTESTSDIR="$FIX" bash build.sh cb >/dev/null 2>&1 )
[[ -s "$C/var/placar-full.txt" || -s "$C/var/placar.txt" ]] || { echo "build.sh não gerou placar"; exit 1; }

jq -n '{region:"Brasil", r1:3, r4:{f3:1,f2:1,f1:1},
        sedes:{"SP, Capital":2, "RJ, Rio":1},
        supersedes:{"Supersede Norte":2}}' > "$FIX/cfg.json"

OUT="$FIX/out.json"
bash "$ROOT/score/classify-br.sh" cb "$FIX/cfg.json" "$OUT" || { echo "motor falhou"; exit 1; }

PASS=0; FAIL=0
ck(){ if jq -e "$1" "$OUT" >/dev/null 2>&1; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FALHOU: $2  [$1]" >&2; fi }
via(){ jq -r --arg l "$1" '.classified[] | select(.login==$l) | .via' "$OUT"; }

ck '.total == 10' "total de classificados = 10 (veio $(jq -r .total "$OUT"))"
[[ "$(via teamsp01)" == regra1 ]] && ok=1 || ok=0; (( ok )) && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU sp01 regra1"; }
[[ "$(via teamsp02)" == regra1 ]] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU sp02 regra1"; }
[[ "$(via teamrj01)" == regra1 ]] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU rj01 regra1 (cap USP devia pular sp03)"; }
[[ "$(via teamsp03)" == regra4 ]] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU sp03 regra4-f3 (USP bloqueada na r2, fem ignora escola)"; }
[[ "$(via teamsp04)" == regra2 ]] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU sp04 regra2 sede SP"; }
[[ "$(via teamsp05)" == regra4 ]] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU sp05 regra4-f2 (UNICAMP já tinha r2; fem ignora)"; }
[[ "$(via teamsp06)" == regra2 ]] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU sp06 regra2 sede SP 2ª vaga"; }
[[ "$(via teamrj02)" == regra2 ]] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU rj02 regra2 sede RJ"; }
[[ "$(via teamam01)" == regra2 ]] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU am01 regra2 supersede"; }
[[ "$(via teamac01)" == regra2 ]] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU ac01 campeão-com-2 na supersede (1/sede membra)"; }
ck '([.classified[] | select(.login=="teamam02")] | length) == 0' "am02 FORA (sede AM já usada na supersede)"
ck '([.classified[] | select(.login=="teamrj03")] | length) == 0' "rj03 FORA (2 problemas sem ser campeão — r0 vale na r4)"
ck '([.classified[] | select(.login=="teamspg")] | length) == 0' "convidado fora"
ck '.unused.regra1 == 0 and .unused.regra2 == 0 and .unused.regra4 == 1' "unused {r1:0,r2:0,r4:1 (f1 sem elegível)}"
ck '(.classified[] | select(.login=="teamac01") | .detail) | test("Supersede Norte")' "detail da supersede"

# ---- parte 2: RELATÓRIO (chip ↑BR no placar + página classificados.html) ----------------
# classification.json no shape do apply (published) a partir da saída do motor
jq -c '{version:1, stages:[{id:"final-br", status:"published",
  name:"Final Brasileira", venue:"Uberlândia", when:"novembro/2026", region:.region,
  teams:(.classified | map({key:.login, value:{via, sede, place, total, detail}}) | from_entries)}]}' \
  "$OUT" > "$C/classification.json"
REP="$FIX/rep"
bash "$ROOT/score/report-gen.sh" cb "$REP" >/dev/null 2>&1 || { echo "report-gen falhou"; exit 1; }
rk(){ if grep -q "$1" "$2" 2>/dev/null; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FALHOU: $3" >&2; fi }
rk '&#8593;BR' "$REP/index.html" "chip ↑BR no placar do relatório"
rk 'classificados.html' "$REP/index.html" "aba Classificados na nav"
[[ -s "$REP/classificados.html" ]] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU: classificados.html ausente" >&2; }
rk 'Regra 1' "$REP/classificados.html" "seção regra 1"
rk 'Supersede Norte' "$REP/classificados.html" "detalhe da supersede na página"
rk 'Uberl' "$REP/classificados.html" "nome/venue do stage na nota"
# rascunho NÃO vaza: com status draft, nem chip nem página
jq -c '.stages[0].status="draft"' "$C/classification.json" > "$C/cl.tmp" && mv "$C/cl.tmp" "$C/classification.json"
REP2="$FIX/rep2"
bash "$ROOT/score/report-gen.sh" cb "$REP2" >/dev/null 2>&1
grep -q '&#8593;BR' "$REP2/index.html" 2>/dev/null && { FAIL=$((FAIL+1)); echo "FALHOU: chip vazou com stage em RASCUNHO" >&2; } || PASS=$((PASS+1))
[[ -f "$REP2/classificados.html" ]] && { FAIL=$((FAIL+1)); echo "FALHOU: página vazou em rascunho" >&2; } || PASS=$((PASS+1))

# ---- parte 3: /contest/classification — rascunho SÓ p/ o admin (marcado draft) ----------
ROUTER="$ROOT/api/v1/router.sh"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
mkdir -p "$C/users/cb.admin"
jq -cn '{login:"cb.admin", fullname:"Admin", password:"x"}' > "$C/users/cb.admin/account.json"
NOWE=$(date +%s)
mktok(){ printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' cb "$1" "$1" "$NOWE" > "$SESS/$2"; }
mktok cb.admin t-adm; mktok teamsp01 t-team
callc(){ PATH_INFO=/contest/classification REQUEST_METHOD=GET QUERY_STRING="contest=cb" \
    HTTP_AUTHORIZATION="${1:+Bearer $1}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" 2>/dev/null | awk 'f{print} /^\r?$/{f=1}'; }
# estado atual do fixture: stage em DRAFT (parte 2 terminou assim)
B_ANON="$(callc "")"; B_TEAM="$(callc t-team)"; B_ADM="$(callc t-adm)"
jq -e '.stages == []' <<<"$B_ANON" >/dev/null && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU: anônimo viu rascunho" >&2; }
jq -e '.stages == []' <<<"$B_TEAM" >/dev/null && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU: competidor viu rascunho" >&2; }
jq -e '.stages[0].draft == true and (.stages[0].teams | length) == 10' <<<"$B_ADM" >/dev/null \
  && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU: admin não viu o rascunho marcado ($B_ADM)" >&2; }
# publicado: todos veem, SEM flag draft
jq -c '.stages[0].status="published"' "$C/classification.json" > "$C/cl.tmp" && mv "$C/cl.tmp" "$C/classification.json"
B_ANON2="$(callc "")"
jq -e '(.stages[0].draft // false) == false and (.stages[0].teams | length) == 10' <<<"$B_ANON2" >/dev/null \
  && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FALHOU: publicado não chegou ao anônimo" >&2; }

echo "smoke-classify-br: PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
