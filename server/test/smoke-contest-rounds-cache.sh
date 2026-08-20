#!/bin/bash
# Cache do /contest/rounds. Esta rota entra em TODO carregamento de página e era a mais cara do
# lote de boot (275 req/s contra ~900 das outras) — o que pesa porque o aluno aperta F5 na
# contagem regressiva em vez de esperar.
#
# A VARIANTE é regra de segurança: quem pode gerir vê rodada arquivada NÃO PUBLICADA; os demais
# não. Um cache sem variante faria o GET de um juiz vazar a rodada não publicada para o time —
# é isso que este teste impede, nas duas ordens.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"

C="$FIX/rc"; mkdir -p "$C/var"
T0=$(( $(date +%s) - 3600 ))
{ printf 'CONTEST_ID=rc\nCONTEST_TYPE=icpc\nCONTEST_NAME=Prova\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$T0" "$((T0+18000))"
  printf 'PROBS=( x col#pa Alfa A col#pa )\n'; } > "$C/conf"
fx_user "$C" rc.admin p "Admin"; fx_user "$C" rc.judge p "Juiz"; fx_user "$C" time01 t "Time"
# uma rodada arquivada PUBLICADA e outra arquivada NÃO publicada (o segredo)
jq -cn '{active:"prova", rounds:[
  {slug:"aquecimento", name:"Aquecimento", kind:"warmup",  state:"archived", published:true,  start:1, end:2},
  {slug:"ensaio",      name:"SEGREDO",     kind:"extra",   state:"archived", published:false, start:3, end:4},
  {slug:"prova",       name:"Prova",       kind:"official",state:"active",   start:5, end:6}]}' > "$C/rounds.json"
for u in rc.admin rc.judge time01; do printf 'CONTEST=rc\nLOGIN=%s\nUSERFULLNAME=X\nLOGINAT=1\n' "$u" > "$SESS/$u"; done
call(){ OUT="$(PATH_INFO=/contest/rounds REQUEST_METHOD=GET QUERY_STRING="contest=rc" \
    HTTP_AUTHORIZATION="Bearer $1" CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$FIX/run" \
    bash "$ROUTER" </dev/null 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
slugs(){ printf '%s' "$BODY" | jq -r '[.rounds[].slug]|sort|join(",")'; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }

echo "== a rodada NÃO publicada não vaza pelo cache =="
call rc.judge
ck "juiz vê a não publicada"       '[[ "$(slugs)" == *ensaio* ]]'
ck "cache privilegiado gravado"    '[[ -s "$C/var/rounds-cache.priv.json" ]]'
call time01
ck "time NÃO vê a não publicada"   '[[ "$(slugs)" != *ensaio* ]]'
ck "time vê a publicada e a ativa" '[[ "$(slugs)" == "aquecimento,prova" ]]'
ck "cache público é outro arquivo" '[[ -s "$C/var/rounds-cache.pub.json" ]] && ! diff -q "$C/var/rounds-cache.priv.json" "$C/var/rounds-cache.pub.json" >/dev/null'
ck "e não contém o segredo"        '! grep -q SEGREDO "$C/var/rounds-cache.pub.json"'
# ordem inversa: público primeiro
rm -f "$C/var/rounds-cache."*.json
call time01;   ck "público primeiro: sem ensaio" '[[ "$(slugs)" != *ensaio* ]]'
call rc.judge; ck "juiz depois: COM ensaio"      '[[ "$(slugs)" == *ensaio* ]]'
call time01;   ck "público segue sem ensaio"     '[[ "$(slugs)" != *ensaio* ]]'
ck "can_manage certo p/ cada um"   '[[ "$(jq -r .can_manage <<<"$BODY")" == false ]]'

echo "== o cache é usado e invalida pelas entradas =="
call time01; A="$BODY"; call time01
ck "2ª chamada idêntica"           '[[ "$BODY" == "$A" ]]'
sleep 1; jq -c '.rounds[1].published = true' "$C/rounds.json" > "$C/r.tmp" && mv "$C/r.tmp" "$C/rounds.json"
call time01
ck "publicar aparece na hora"      '[[ "$(slugs)" == *ensaio* ]]'
sleep 1; printf 'CONTEST_NAME=Outro\n' >> "$C/conf"
call time01
ck "conf novo também invalida"     '[[ "$(jq -r .success <<<"$BODY")" == true ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
