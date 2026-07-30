#!/bin/bash
# smoke-cohorts.sh — COORTES de placar (times oficiais × convidados/CCL).
# contest fake com 3 oficiais + 2 convidados (CCL), onde um CONVIDADO
# resolve primeiro (o caso que prova que o corte subiu até sc_users: a estrela do placar público
# tem de ficar com o oficial). Confere placar por visão, posição, coluna guest e a liberação.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # server/
V="$ROOT/api/v1"; SC="$ROOT/score"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CONTESTSDIR="$TMP/contests" SCOREDIR="$SC"
mkdir -p "$CONTESTSDIR/treino/var/jsons"
C="$CONTESTSDIR/prova"; mkdir -p "$C"/{enunciados,var,users}
NOW=$(date +%s); W0=$((NOW-7200))

cat > "$C/conf" <<EOF
CONTEST_ID=prova
CONTEST_NAME='Maratona com Convidados'
CONTEST_TYPE=icpc
CONTEST_START=$W0
CONTEST_END=$((NOW+3600))
PROBS=( cdmoj org#alfa Alfa A org#alfa cdmoj org#beta Beta B org#beta )
EOF

mk(){ # <login> <nome> [cohort]
  local u="$C/users/$1"; mkdir -p "$u"/{submissions,mojlog,results}
  jq -cn --arg l "$1" --arg n "$2" --arg co "${3:-}" \
    '{login:$l,password:"x",fullname:$n,status:"active",created_at:0,updated_at:0,uname_changes:[],
      team:({univ_short:"UNB",region:"Curitiba"} + (if $co=="" then {} else {cohort:$co} end))}' > "$u/account.json"
  : > "$u/history"
}
sub(){ # <login> <prob> <verdict> <epoch> <id>
  printf '%s:%s:c:%s:%s:%s\n' "$(( $4 - W0 ))" "$2" "$3" "$4" "$5" >> "$C/users/$1/history"
}
mk of1 "Oficial Um"; mk of2 "Oficial Dois"; mk of3 "Oficial Tres"
mk ccl1 "Convidado Um"; mk cclzz "Convidado Dois" ccl      # um por regex, um por CAMPO
mk chefe.admin "Admin"

# O CONVIDADO resolve o Alfa ANTES de todos os oficiais (t+600 × t+900/t+1200)
sub ccl1 'org#alfa' 'Accepted'     $((W0+600))  9001
sub of1  'org#alfa' 'Wrong Answer' $((W0+700))  9002
sub of1  'org#alfa' 'Accepted'     $((W0+900))  9003
sub of2  'org#alfa' 'Accepted'     $((W0+1200)) 9004
sub of2  'org#beta' 'Accepted'     $((W0+1500)) 9005
sub cclzz 'org#beta' 'Accepted'    $((W0+1400)) 9006
sub of3  'org#beta' 'Wrong Answer' $((W0+1600)) 9007

cat > "$C/cohorts.json" <<'EOF'
{ "version":1, "results_released":false,
  "cohorts":[
    {"id":"oficial","name":"Oficiais","default":true,"public":true},
    {"id":"ccl","name":"Café com Leite","regex":"^ccl","public":false,"unranked":true,
     "sees":["oficial","ccl"]} ]}
EOF

source "$V/lib/users.sh"
for u in of1 of2 of3 ccl1 cclzz; do metrics_recompute prova "$u" >/dev/null 2>&1; done
source "$V/lib/cohorts.sh"

ok(){ printf '  \033[32m✓\033[0m %s\n' "$1"; }
no(){ printf '  \033[31m✗ %s\033[0m\n' "$1"; FAIL=1; }
FAIL=0

echo "== pertencimento (campo vence regex; resto cai na default):"
for u in of1 ccl1 cclzz chefe.admin; do printf '  %-12s -> %s\n' "$u" "$(ch_of prova "$u")"; done
[[ "$(ch_of prova ccl1)" == ccl && "$(ch_of prova cclzz)" == ccl && "$(ch_of prova of1)" == oficial ]] \
  && ok "coorte por regex e por campo" || no "coorte errada"

echo "== visões:"; ch_views prova | sed 's/^/    /'
echo "    public  -> $(ch_cohorts_of_view prova public)"
echo "    ccl     -> $(ch_cohorts_of_view prova ccl)"
echo "    all     -> '$(ch_cohorts_of_view prova all)' (vazio = todas)"
echo "== visão por login:"
for u in of1 ccl1 chefe.admin; do printf '  %-12s -> %s\n' "$u" "$(ch_view_for_login prova "$u")"; done

echo "== build (deve gerar 3 pares: public + ccl + all):"
bash "$SC/build.sh" prova >/dev/null 2>&1 || no "build falhou"
ls "$C/var/" | grep placar | sed 's/^/    /'

echo "== PLACAR PÚBLICO (não pode ter linha de convidado):"
cat "$C/var/placar.txt" | sed 's/^/    /'
grep -qE '^[^:]*:ccl' "$C/var/placar.txt" && no "convidado apareceu no placar público" || ok "nenhum convidado no placar público"
# a estrela do Alfa tem de ser do of1 (900), não do convidado (600)
if awk -F: 'NR>2 && $2=="of1"' "$C/var/placar.txt" | grep -q '1/15\*\|2/15\*'; then
  ok "estrela do Alfa ficou com o OFICIAL no placar público"
else no "estrela do placar público está errada"; fi
grep -q ':guest' "$C/var/placar.txt" && no "placar público não deveria ter coluna guest" || ok "placar público sem coluna guest"

echo "== PLACAR DA VISÃO CCL (tem de ter os 5 e a coluna guest):"
cat "$C/var/placar-view-ccl.txt" | sed 's/^/    /'
n=$(awk 'NR>2' "$C/var/placar-view-ccl.txt" | grep -c .)
[[ "$n" == 5 ]] && ok "5 times na visão do convidado" || no "visão do convidado tem $n times"
head -2 "$C/var/placar-view-ccl.txt" | tail -1 | grep -q ':guest' && ok "coluna guest no cabeçalho" || no "sem coluna guest"
awk -F: 'NR>2 && $2 ~ /^ccl/ {print $NF}' "$C/var/placar-view-ccl.txt" | grep -qx 1 && ok "linha de convidado marcada guest=1" || no "convidado não marcado"
awk -F: 'NR>2 && $2 !~ /^ccl/ {print $NF}' "$C/var/placar-view-ccl.txt" | grep -qx 1 && no "oficial marcado como guest!" || ok "oficial não marcado como guest"
# na visão do convidado, a estrela do Alfa é do convidado (ele resolveu antes)
awk -F: 'NR>2 && $2=="ccl1"' "$C/var/placar-view-ccl.txt" | grep -q '\*' \
  && ok "estrela do Alfa é do convidado na visão dele" || no "estrela da visão ccl errada"

echo "== LIBERAÇÃO dos resultados (public passa a ser o combinado):"
jq -c '.results_released=true' "$C/cohorts.json" > "$C/cohorts.json.t" && mv "$C/cohorts.json.t" "$C/cohorts.json"
bash "$SC/build.sh" prova >/dev/null 2>&1
n=$(awk 'NR>2' "$C/var/placar.txt" | grep -c .)
[[ "$n" == 5 ]] && ok "placar público liberado tem os 5" || no "placar liberado tem $n"
grep -q ':guest' "$C/var/placar.txt" && ok "coluna guest no placar liberado" || no "sem coluna guest depois de liberar"
echo "    $(sed -n 3p "$C/var/placar.txt")"
[[ "$(ch_view_for_login prova of1)" == all ]] && ok "depois de liberar, todos veem tudo" || no "view_for_login não liberou"

echo "== SEM cohorts.json: exatamente os arquivos de sempre (regressão de custo):"
rm -f "$C/cohorts.json"
bash "$SC/build.sh" prova >/dev/null 2>&1
ls "$C/var/" | grep -c 'placar-view' | grep -qx 0 && ok "nenhum placar-view sobrou" || no "sobrou placar de visão"
n=$(awk 'NR>2' "$C/var/placar.txt" | grep -c .)
[[ "$n" == 5 ]] && ok "placar único com todos (comportamento clássico)" || no "placar clássico tem $n"
echo ""
echo "RESULT: $( [[ "${FAIL:-0}" == 0 ]] && echo "todas as checagens passaram" || echo "FALHOU" )"
exit "${FAIL:-0}"
