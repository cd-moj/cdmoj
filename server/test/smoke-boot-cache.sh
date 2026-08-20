#!/bin/bash
# Cache do LOTE DE BOOT (/contest/balloons, /contest/basic, /contest/navbuttons).
#
# Toda página de contest abre pedindo este lote, e o aluno aperta F5 na contagem regressiva em
# vez de esperar — então são as rotas mais repetidas do dia. Duas delas só podem ser cacheadas
# com uma trava, e é ISSO que este teste guarda:
#
#   navbuttons — a variante é POR PAPEL. Um GET do admin enche o cache com "⚙ Administração",
#                "jplag", "Todas Submissões"; o competidor não pode receber esse corpo (nem
#                deve saber que esses caminhos existem). Testado nas DUAS ordens.
#   basic      — COM sessão o corpo é PESSOAL (fim prorrogado por sede, coorte do login). Só o
#                caminho ANÔNIMO — o do boot/contagem regressiva — é cacheado; a resposta
#                pessoal não pode nem ser servida do cache nem envenená-lo.
#   balloons   — sem variante (o mapa de cores é o mesmo p/ todos): só frescor.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"

C="$FIX/bc"; mkdir -p "$C/var" "$C/enunciados"
T0=$(( $(date +%s) - 3600 )); TE=$(( T0 + 18000 ))
{ printf 'CONTEST_ID=bc\nCONTEST_TYPE=icpc\nCONTEST_NAME=Prova\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\n' "$T0" "$TE"
  printf 'PROBS=( x col#pa Alfa A col#pa )\n'; } > "$C/conf"
for u in bc.admin bc.judge bc.cjudge bc.staff bc.cstaff bc.animeitor bc.mon time01 time02; do
  fx_user "$C" "$u" p "Conta $u"
  printf 'CONTEST=bc\nLOGIN=%s\nUSERFULLNAME=X\nLOGINAT=1\n' "$u" > "$SESS/$u"
done
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD=GET QUERY_STRING="contest=bc" \
    HTTP_AUTHORIZATION="Bearer ${2:-}" CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$FIX/run" \
    bash "$ROUTER" </dev/null 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
labels(){ printf '%s' "$BODY" | jq -r '[.buttons[].label]|join("|")'; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }

echo "== navbuttons: a nav do ADMIN não vaza p/ o competidor (o teste que motiva a variante) =="
call /contest/navbuttons bc.admin
ck "admin vê Administração"        '[[ "$(labels)" == *"Administração"* ]]'
ck "cache do admin gravado"        '[[ -s "$C/var/nav-cache.admin.json" ]]'
call /contest/navbuttons time01
ck "competidor NÃO vê Administração" '[[ "$(labels)" != *"Administração"* ]]'
ck "nem jplag/Todas Submissões"    '[[ "$(labels)" != *jplag* && "$(labels)" != *"Todas Submissões"* ]]'
ck "e tem variante própria"        '[[ -s "$C/var/nav-cache.time.json" ]]'
ck "o arquivo do time não cita admin" '! grep -q "contest/admin" "$C/var/nav-cache.time.json"'
# ordem inversa: competidor primeiro
rm -f "$C/var/nav-cache."*.json
call /contest/navbuttons time01; ck "time primeiro: sem Administração" '[[ "$(labels)" != *"Administração"* ]]'
call /contest/navbuttons bc.admin; ck "admin depois: COM Administração" '[[ "$(labels)" == *"Administração"* ]]'
call /contest/navbuttons time02; ck "outro time segue sem"             '[[ "$(labels)" != *"Administração"* ]]'

echo "== navbuttons: cada papel tem a SUA variante (nenhum herda a do outro) =="
call /contest/navbuttons bc.cjudge
ck "chefe vê Juiz-chefe"           '[[ "$(labels)" == *"Juiz-chefe"* ]]'
call /contest/navbuttons bc.judge
ck "juiz puro NÃO vê Juiz-chefe"   '[[ "$(labels)" != *"Juiz-chefe"* && "$(labels)" == *Avaliar* ]]'
call /contest/navbuttons bc.cstaff
ck "cstaff vê Etiquetas"           '[[ "$(labels)" == *"Etiquetas"* ]]'
call /contest/navbuttons bc.staff
ck "staff NÃO vê Etiquetas"        '[[ "$(labels)" != *"Etiquetas"* && "$(labels)" == *"Impressão"* ]]'
call /contest/navbuttons bc.animeitor
ck "telão vê Animeitor, não Contest" '[[ "$(labels)" == *Animeitor* && "$(labels)" != *Contest* ]]'
call /contest/navbuttons bc.mon
ck "monitor: só leitura"           '[[ "$(labels)" == *"Todas Submissões"* && "$(labels)" != *Avaliar* ]]'
ck "8 papéis, 8 variantes distintas"   '[[ "$(ls "$C/var/"nav-cache.*.json | wc -l)" == 8 ]] && [[ "$(md5sum "$C/var/"nav-cache.*.json | cut -d" " -f1 | sort -u | wc -l)" == 8 ]]'
ck "todo mundo tem Logout"         '[[ "$(labels)" == *Logout* ]]'

echo "== basic: a resposta PESSOAL não é servida do cache nem o envenena =="
# time01 ganha prorrogação de sede: o fim EFETIVO dele é maior que o do contest
jq -cn --argjson e "$(( TE + 1800 ))" '[{regex:"^time01$", end:$e, reason:"queda de energia"}]' \
  > "$C/time-overrides.json"
call /contest/basic ''                       # anônimo: popula o cache
ANON_END="$(jq -r .end_time <<<"$BODY")"
ck "anônimo tem o fim do contest"  '[[ "$ANON_END" == "'"$TE"'" ]]'
ck "cache anônimo gravado"         '[[ -s "$C/var/basic-cache.anon.json" ]]'
SNAP="$(cat "$C/var/basic-cache.anon.json")"
call /contest/basic time01
ck "com sessão: fim PRORROGADO"    '[[ "$(jq -r .end_time <<<"$BODY")" == "'"$(( TE + 1800 ))"'" ]]'
ck "e o cache anônimo NÃO mudou"   '[[ "$(cat "$C/var/basic-cache.anon.json")" == "$SNAP" ]]'
call /contest/basic ''
ck "anônimo segue com o fim normal" '[[ "$(jq -r .end_time <<<"$BODY")" == "'"$TE"'" ]]'
# ordem inversa: sessão primeiro, com o cache limpo, não pode CRIAR o arquivo anônimo
rm -f "$C/var/basic-cache.anon.json"
call /contest/basic time01
ck "sessão não cria cache anônimo" '[[ ! -e "$C/var/basic-cache.anon.json" ]]'
call /contest/basic ''
ck "anônimo depois: fim do contest" '[[ "$(jq -r .end_time <<<"$BODY")" == "'"$TE"'" ]]'
sleep 1; printf 'CONTEST_NAME=Outro\n' >> "$C/conf"
call /contest/basic ''
ck "conf novo invalida"            '[[ "$(jq -r .contest_name <<<"$BODY")" == Outro ]]'

echo "== balloons: sem variante, só frescor =="
call /contest/balloons time01
ck "A é branco (paleta padrão)"    '[[ "$(jq -r ".balloons.A" <<<"$BODY")" == FFFFFF ]]'
ck "cache gravado"                 '[[ -s "$C/var/balloons-cache.json" ]]'
call /contest/balloons time01; A="$BODY"
call /contest/balloons bc.admin
ck "admin recebe o MESMO corpo"    '[[ "$BODY" == "$A" ]]'
sleep 1; printf '{"A":"123456"}' > "$C/balloons.json"
call /contest/balloons time01
ck "trocar a cor aparece na hora"  '[[ "$(jq -r ".balloons.A" <<<"$BODY")" == 123456 ]]'
ck "e o resto da paleta continua"  '[[ "$(jq -r ".balloons.B" <<<"$BODY")" != null ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
