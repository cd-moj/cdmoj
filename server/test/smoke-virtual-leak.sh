#!/bin/bash
# PARTICIPAÇÃO VIRTUAL — MATRIZ HOSTIL. Pedido do Ribas (2026-09-18): "muito cuidado para não vazar
# prova; as APIs precisam ter gates fortes para ninguém acessar contest secreto/rodando e pegar
# enunciado e resultados". Para CADA rota do virtual × CADA contest que não pode virar virtual:
#   • 404 `virtual_unavailable` com corpo BYTE-IDÊNTICO ao de contest inexistente
#     (não confirma existência, fase, título, nº de problemas);
#   • nenhum byte de título/letra/nome de problema/time/placar na resposta;
#   • cache de feed/board PRÉ-EXISTENTE não é servido e é APAGADO;
#   • /submit virtual:<cid> recusa e não etiqueta nada.
# E: problema que vira privado DEPOIS de ligado derruba o virtual; ligar o módulo com problema
# privado é 422 sem vazar id.
set -u
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(cd "$HERE/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$HERE/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" \
       SPOOLDIR="$RUN/spool/submissions" SPOOLDONEDIR="$RUN/spool/submissions-done"
mkdir -p "$SPOOLDIR" "$SPOOLDONEDIR"
NOW="$EPOCHSECONDS"
T="$FIX/treino"; mkdir -p "$T/var/jsons" "$T/var/jsons-private"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\nUSER_STORE=v2\nCONTEST_END=%s\n' "$((NOW+86400))" > "$T/conf"
printf '{"id":"col#pa","title":"SEGREDOTITULO","public":true,"languages":["c"]}' > "$T/var/jsons/col#pa.json"
printf '{"id":"col#pv","title":"SEGREDOPRIV","public":false,"languages":["c"]}'  > "$T/var/jsons-private/col#pv.json"
printf '{"id":"col#pf","title":"SEGREDOFALSE","public":false,"languages":["c"]}' > "$T/var/jsons/col#pf.json"   # vazou p/ jsons/ mas é public:false
printf '{"problems":[{"id":"col#pa","owner":"dona","public":true},{"id":"col#pv","owner":"dona","public":false},{"id":"col#pf","owner":"dona","public":false}]}' > "$T/var/problem-owners.json"
fx_user "$T" ana s Ana; printf 'CONTEST=treino\nLOGIN=ana\nUSERFULLNAME=Ana\nLOGINAT=1\n' > "$SESS/tok-ana"

mk(){ # <cid> <start> <end> <linhas extras do conf> [probs]
  local c="$FIX/$1"; mkdir -p "$c/var"
  { printf 'CONTEST_ID=%s\nCONTEST_NAME=SEGREDONOME\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\n' "$1" "$2" "$3"
    printf '%b' "$4"; printf 'PROBS=( %s )\n' "${5:-x col/pa SEGREDOPROB Q col#pa}"; } > "$c/conf"
  fx_user "$c" timesegredo s "SEGREDOTIME"
  printf '%s:col#pa:C:Accepted:%s:zz1\n' "$(( $2 + 60 ))" "$(( $2 + 60 ))" > "$c/users/timesegredo/history"
  # cache PLANTADO: se qualquer rota o servir, o segredo aparece
  printf '{"success":true,"title":"SEGREDOCACHE","teams":[["timesegredo"]],"runs":[[60,0,0,"Y"]]}' > "$c/var/virtual-feed.json"
  gzip -c "$c/var/virtual-feed.json" > "$c/var/virtual-feed.json.gz"
  mkdir -p "$c/virtual/runs"; printf '{"login":"SEGREDOVIRT","name":"x","solved":1,"penalty":1,"runs":[]}' > "$c/virtual/runs/x.json"
  printf '[{"login":"SEGREDOVIRT"}]' > "$c/var/virtual-board.json"; }
ON='CONTEST_MODULES=virtual\n'
mk vrun    $((NOW-3600))  $((NOW+3600))  "$ON"
mk vfut    $((NOW+3600))  $((NOW+7200))  "$ON"
mk vsecrun $((NOW-3600))  $((NOW+3600))  "${ON}SECRET=1\n"
mk vsec    $((NOW-9000))  $((NOW-3600))  "${ON}SECRET=1\n"
mk vfrz    $((NOW-9000))  $((NOW-3600))  "${ON}FREEZE_TIME=$((NOW-5000))\n"
mk vpriv   $((NOW-9000))  $((NOW-3600))  "$ON" "x col/pa SEGREDOPROB Q col#pa x col/pv SEGREDOPROB2 R col#pv"
mk vpfalse $((NOW-9000))  $((NOW-3600))  "$ON" "x col/pf SEGREDOPROB Q col#pf"
mk voff    $((NOW-9000))  $((NOW-3600))  ""
mk vobi    $((NOW-9000))  $((NOW-3600))  "$ON"; sed -i 's/^CONTEST_TYPE=.*/CONTEST_TYPE=obi/' "$FIX/vobi/conf"
mk vext    $((NOW-9000))  $((NOW-3600))  "$ON"; printf '[{"regex":"^sede","end":%s,"reason":"x"}]' "$((NOW+600))" > "$FIX/vext/time-overrides.json"   # sede prorrogada AINDA rodando
mk vok     $((NOW-9000))  $((NOW-3600))  "$ON"
BAD="vrun vfut vsecrun vsec vfrz vpriv vpfalse voff vobi vext"

call(){ local auth=(); [[ "$1" != - ]] && auth=(HTTP_AUTHORIZATION="Bearer tok-$1")
  OUT="$(env "${auth[@]}" PATH_INFO="$2" REQUEST_METHOD="$3" QUERY_STRING="$4" HTTP_ACCEPT_ENCODING="${AE:-}" bash "$ROUTER" <<<"${5:-}" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
pass=0; fail=0
ck(){ if eval "$2"; then ((pass++)); else echo "  FAIL: $1 :: ${OUT:0:240}"; ((fail++)); fi; }

echo "== referência: contest INEXISTENTE =="
declare -A REF
for r in info run problems feed board; do call ana "/treino/virtual/$r" GET contest=naoexiste; REF[$r]="$OUT"
  ck "ref $r é 404 virtual_unavailable" '[[ "$OUT" == *"Status: 404"* && "$OUT" == *virtual_unavailable* ]]'; done
call ana /treino/virtual/run POST "" '{"contest":"naoexiste","action":"start","accept":true}'; REF[post]="$OUT"

echo "== matriz: rota × contest proibido =="
for c in $BAD; do
  for r in info run problems feed board; do
    for who in ana -; do
      for AE in "" gzip; do
        call "$who" "/treino/virtual/$r" GET "contest=$c"
        if [[ "$who" == - && "$r" != feed && "$r" != board ]]; then
          ck "$c/$r anônimo: 401 sem segredo" '[[ "$OUT" == *"Status: 401"* && "$OUT" != *SEGREDO* ]]'
        else
          [[ "$who" == ana ]] && ck "$c/$r: resposta IDÊNTICA à de inexistente" '[[ "$OUT" == "${REF[$r]}" ]]'
          ck "$c/$r ($who,${AE:-plain}): 404 e nenhum segredo" '[[ "$OUT" == *"Status: 404"* && "$OUT" != *SEGREDO* && "$OUT" != *timesegredo* ]]'
        fi
      done
    done
  done
  AE=""
  call ana /treino/virtual/run POST "" "{\"contest\":\"$c\",\"action\":\"start\",\"accept\":true}"
  ck "$c: start idêntico ao de inexistente"   '[[ "$OUT" == "${REF[post]}" ]]'
  ck "$c: nenhum estado de run foi criado"    '[[ ! -e "$T/users/ana/virtual/$c.json" ]]'
  call ana /submit POST contest=treino "{\"problem_id\":\"col#pa\",\"filename\":\"a.c\",\"code_b64\":\"aW50\",\"virtual\":\"$c\"}"
  ck "$c: /submit virtual recusa (404)"       '[[ "$OUT" == *"Status: 404"* && "$OUT" == *virtual_unavailable* ]]'
  ck "$c: cache plantado foi APAGADO"         '[[ ! -e "$FIX/$c/var/virtual-feed.json" && ! -e "$FIX/$c/var/virtual-feed.json.gz" && ! -e "$FIX/$c/var/virtual-board.json" ]]'
done
ck "nenhuma submissão virtual entrou na fila" '[[ -z "$(find "$SPOOLDIR" -type f)" ]]'

echo "== id hostil =="
# (`%00` some na decodificação: `vsec%00` É `vsec` — tem de cair no mesmo 404)
for c in '../vok' 'vok/../vsec' 'VOK' 'treino' '' 'vsec%00' 'vsec%2F..%2Fvok' 'v*'; do
  call ana /treino/virtual/feed GET "contest=$c"; ck "cid hostil [$c]: 404/400 sem segredo" '[[ ( "$OUT" == *"Status: 404"* || "$OUT" == *"Status: 400"* ) && "$OUT" != *SEGREDO* ]]'
done

echo "== contest elegível funciona — e DEIXA de funcionar quando algo muda =="
rm -f "$FIX/vok/var/"virtual-*; rm -rf "$FIX/vok/virtual"
# COORTE PRIVADA (convidados ocultos do placar público): nem o time, nem o NOME da coorte saem no feed
printf '{"version":1,"cohorts":[{"id":"oficial","name":"Oficiais","default":true,"public":true},{"id":"segredo","name":"SEGREDOCOORTE","regex":"^oculto","public":false,"unranked":true}]}' > "$FIX/vok/cohorts.json"
fx_user "$FIX/vok" ocultotime s "SEGREDOOCULTO"; printf '%s:col#pa:C:Accepted:%s:zz9\n' "$((NOW-8000))" "$((NOW-8000))" > "$FIX/vok/users/ocultotime/history"
call - /treino/virtual/feed GET contest=vok; ck "vok: feed 200" '[[ "$OUT" == *"Status: 200"* && "$(jq -r ".runs|length" <<<"$BODY")" == 1 ]]'
ck "vok: coorte PRIVADA fora do feed (time, nome e runs)" '[[ "$OUT" != *ocultotime* && "$OUT" != *SEGREDOCOORTE* && "$OUT" != *SEGREDOOCULTO* && "$(jq -r ".teams|length" <<<"$BODY")" == 1 ]]'
ck "vok: cache do feed criado"                '[[ -s "$FIX/vok/var/virtual-feed.json" ]]'
jq -c '.public=false' "$T/var/jsons/col#pa.json" > "$T/var/jsons/x" && mv "$T/var/jsons/x" "$T/var/jsons/col#pa.json"
call - /treino/virtual/feed GET contest=vok
ck "problema virou PRIVADO: feed 404 idêntico" '[[ "$OUT" == "${REF[feed]/naoexiste/naoexiste}" || ( "$OUT" == *"Status: 404"* && "$OUT" != *SEGREDO* ) ]]'
ck "…e o cache que existia foi apagado"       '[[ ! -e "$FIX/vok/var/virtual-feed.json" ]]'
jq -c '.public=true' "$T/var/jsons/col#pa.json" > "$T/var/jsons/x" && mv "$T/var/jsons/x" "$T/var/jsons/col#pa.json"
call - /treino/virtual/feed GET contest=vok;   ck "voltou a público: 200" '[[ "$OUT" == *"Status: 200"* ]]'
printf 'SECRET=1\n' >> "$FIX/vok/conf"
call - /treino/virtual/feed GET contest=vok;   ck "dono marcou SECRET: 404 + cache apagado" '[[ "$OUT" == *"Status: 404"* && ! -e "$FIX/vok/var/virtual-feed.json" ]]'
sed -i '/^SECRET=1/d' "$FIX/vok/conf"; sed -i "s/^CONTEST_END=.*/CONTEST_END=$((NOW+600))/" "$FIX/vok/conf"
call - /treino/virtual/feed GET contest=vok;   ck "dono REABRIU a prova: 404" '[[ "$OUT" == *"Status: 404"* ]]'
rm -f "$FIX/vok/conf"; call - /treino/virtual/feed GET contest=vok; ck "conf ilegível: 404 (fail-closed)" '[[ "$OUT" == *"Status: 404"* ]]'

echo "== ligar o módulo com problema privado: 422 sem vazar id =="
fx_user "$FIX/vpriv" vpriv.admin s Adm; printf 'CONTEST=vpriv\nLOGIN=vpriv.admin\nUSERFULLNAME=A\nLOGINAT=1\n' > "$SESS/tok-padm"
sed -i 's/^CONTEST_MODULES=.*/CONTEST_MODULES=/' "$FIX/vpriv/conf"
call padm /contest/admin/modules POST contest=vpriv '{"on":["virtual"]}'
ck "422 virtual_not_eligible"                  '[[ "$OUT" == *"Status: 422"* && "$OUT" == *virtual_not_eligible* ]]'
ck "…sem id nem título do problema privado"    '[[ "$OUT" != *"col#pv"* && "$OUT" != *SEGREDOPRIV* ]]'
ck "…e o módulo NÃO ligou"                     '! grep -q "^CONTEST_MODULES=.*virtual" "$FIX/vpriv/conf"'

echo; echo "RESULT: $pass passed, $fail failed"; (( fail == 0 ))
