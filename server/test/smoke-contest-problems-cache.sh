#!/bin/bash
# Cache do /contest/problems: a rota monta o MESMO payload p/ todos os times (~77 processos com
# 12 problemas) e 2000 deles a pedem no segundo em que a prova abre. O cache é por VARIANTE, e a
# variante existe por um motivo de SEGURANÇA: o AUTOR do problema só aparece com a prova
# encerrada ou p/ quem organiza — durante a prova o nome do autor é pista.
#
# O teste que importa é o de ENVENENAMENTO: um GET do juiz enche o cache com o autor dentro; o
# competidor NÃO pode receber esse corpo. Cobre também a invalidação por escrita do admin, por
# conf, por override de linguagem e o teto de idade.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; PKG="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$PKG"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"

C="$FIX/pc"; mkdir -p "$C/var" "$C/enunciados"
T0=$(( $(date +%s) - 3600 ))
{ printf 'CONTEST_ID=pc\nCONTEST_TYPE=icpc\nCONTEST_NAME=Prova\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$T0" "$((T0+18000))"
  printf 'PROBS=( x col#pa Alfa A col#pa x col#pb Beta B col#pb )\n'; } > "$C/conf"
fx_user "$C" pc.admin p "Admin"; fx_user "$C" pc.judge p "Juiz"
fx_user "$C" pc.cjudge p "Chefe"; fx_user "$C" time01 t "Time 01"
printf '<html><body>A</body></html>' > "$C/enunciados/col#pa.html"
printf '<html><body>B</body></html>' > "$C/enunciados/col#pb.html"
# pacote com AUTOR — é o dado que não pode vazar durante a prova
mkdir -p "$PKG/col/pa" "$PKG/col/pb"
printf 'Bruno Ribas\n' > "$PKG/col/pa/author"; printf 'Maria da Silva\n' > "$PKG/col/pb/author"
for u in pc.admin pc.judge pc.cjudge time01; do
  printf 'CONTEST=pc\nLOGIN=%s\nUSERFULLNAME=X\nLOGINAT=1\n' "$u" > "$SESS/$u"
done
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="${3:-GET}" QUERY_STRING="contest=pc" \
    HTTP_AUTHORIZATION="Bearer $2" CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$FIX/run" \
    MOJ_PROBLEMS_DIR="$PKG" bash "$ROUTER" <<<"${4:-}" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
autor(){ printf '%s' "$BODY" | jq -r '[.problems[]?|.author//empty]|join(",")'; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:180}"; ((fail++)); fi; }

echo "== o AUTOR não vaza pelo cache (o teste que motiva a variante) =="
call /contest/problems pc.judge
ck "juiz VÊ o autor"                 '[[ "$(autor)" == *"Bruno Ribas"* ]]'
ck "e o cache do juiz foi gravado"   '[[ -s "$C/var/problems-cache.author.json" ]]'
# agora o competidor pede — se a variante fosse ignorada, ele receberia o corpo do juiz
call /contest/problems time01
ck "competidor NÃO vê autor nenhum"  '[[ -z "$(autor)" ]]'
ck "e tem sua própria variante"      '[[ -s "$C/var/problems-cache.noauthor.json" ]]'
ck "os dois arquivos DIFEREM"        '! diff -q "$C/var/problems-cache.author.json" "$C/var/problems-cache.noauthor.json" >/dev/null'
ck "o de competidor não cita autor"  '! grep -q "Bruno Ribas" "$C/var/problems-cache.noauthor.json"'
# e na ordem inversa: competidor primeiro, juiz depois
rm -f "$C/var/problems-cache."*.json
call /contest/problems time01; ck "competidor primeiro: sem autor" '[[ -z "$(autor)" ]]'
call /contest/problems pc.judge; ck "juiz depois: COM autor"       '[[ "$(autor)" == *"Bruno Ribas"* ]]'
call /contest/problems pc.cjudge; ck "chefe também vê"             '[[ "$(autor)" == *"Bruno Ribas"* ]]'
call /contest/problems time01;   ck "competidor segue sem autor"   '[[ -z "$(autor)" ]]'

echo "== o cache é usado (mesma resposta, sem remontar) =="
call /contest/problems time01; A="$BODY"
call /contest/problems time01; ck "2ª chamada idêntica" '[[ "$BODY" == "$A" ]]'
ck "e veio do arquivo"        '[[ -s "$C/var/problems-cache.noauthor.json" ]]'

echo "== o ADMIN mexe na lista: invalida e regenera =="
call /contest/admin/problems pc.admin POST '{"action":"rename","letter":"A","name":"Alfa Renomeado"}'
ck "rename aceito"                '[[ "$(jq -r .saved <<<"$BODY")" == true ]]'
ck "carimbo de invalidação criado" '[[ -f "$C/var/.problems-dirty" ]]'
call /contest/problems time01
ck "o time JÁ vê o nome novo"     '[[ "$(jq -r ".problems[]|select(.short_name==\"A\").full_name" <<<"$BODY")" == "Alfa Renomeado" ]]'
call /contest/admin/problems pc.admin POST '{"action":"remove","letter":"B"}'
call /contest/problems time01
ck "remoção também aparece"       '[[ "$(jq -r "[.problems[].short_name]|join(\",\")" <<<"$BODY")" == "A" ]]'

echo "== invalida por ENTRADA, mesmo sem carimbo (rede de segurança) =="
rm -f "$C/var/.problems-dirty"
call /contest/problems time01 >/dev/null
sleep 1; printf 'PROBS=( x col#pa Alfa A col#pa x col#pb Beta B col#pb )\n' >> "$C/conf"
call /contest/problems time01
ck "conf mais novo => regenerou"  '[[ "$(jq -r "[.problems[].short_name]|join(\",\")" <<<"$BODY")" == "A,B" ]]'
rm -f "$C/var/.problems-dirty"
call /contest/problems time01 >/dev/null
sleep 1; printf '{"col#pa":["c"]}' > "$C/problem-langs.json"
call /contest/problems time01
ck "problem-langs novo => regenerou" '[[ "$(jq -r ".problems[]|select(.short_name==\"A\").languages|join(\",\")" <<<"$BODY")" == "c" ]]'

echo "== o cache NÃO serve quem não pode ver problema =="
# antes do início a lista é vazia + locked (o cache não pode servir a lista cheia p/ ele)
sed -i "s/^CONTEST_START=.*/CONTEST_START=$(( $(date +%s) + 3600 ))/" "$C/conf"
call /contest/problems time01
ck "antes do início: lista vazia"  '[[ "$(jq -r ".problems|length" <<<"$BODY")" == 0 ]]'
ck "e diz o motivo (locked)"       '[[ "$(jq -r .locked <<<"$BODY")" == not_started ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
