#!/bin/bash
# ch_ctx × (ch_enabled + ch_of + ch_view_for_login) — teste DIFERENCIAL.
#
# O `ch_ctx` existe porque o trio se chama em cascata e custava 28 processos por requisição no
# /contest/basic (toda página de contest paga essa rota). Ele responde as três perguntas num jq
# só — o mesmo remédio do `ug_expected_map` do gate de UA — e o preço é ter DUAS implementações
# da mesma regra no arquivo. Este teste é o que impede as duas de divergirem: para cada
# configuração × login, o par tem de dar exatamente a mesma resposta.
#
# Divergir aqui não é detalhe: a visão de coorte decide QUAL PLACAR o competidor vê.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
export CONTESTSDIR="$FIX"; C="$FIX/co"; mkdir -p "$C/users"
source "$ROOT/api/v1/lib/cohorts.sh"

mkuser(){ mkdir -p "$C/users/$1"; printf '%s' "${2:-{\}}" > "$C/users/$1/account.json"; }
for u in time01 guest01 outro01 co.admin co.judge co.cstaff co.animeitor co.mon; do mkuser "$u"; done
mkuser fixado '{"team":{"cohort":"convidado"}}'      # override VÁLIDO no account.json
mkuser errado '{"team":{"cohort":"nao-existe"}}'     # override que não casa coorte nenhuma

pass=0; fail=0
# compara ch_ctx com o trio; um processo NOVO por chamada do trio, senão a memoização mascara
dif(){ # <rótulo> <login>
  local lbl="$1" l="$2" en co vw ctx cen cco cvw
  if ch_enabled co; then en=1; else en=0; fi
  co="$(ch_of co "$l")"; vw="$(ch_view_for_login co "$l")"
  ctx="$(ch_ctx co "$l")"; IFS=$'\x01' read -r cen cco cvw <<<"$ctx"
  if [[ "$en/$co/$vw" == "$cen/$cco/$cvw" ]]; then
    echo "  ok: $lbl [$l] => en=$en co='$co' vw=$vw"; return 0
  else
    echo "  FAIL: $lbl [$l] trio='$en/$co/$vw' ctx='$cen/$cco/$cvw'"; return 1
  fi
}
# cada cenário roda numa SUBSHELL: as libs memoizam por processo, e reaproveitar o valor de um
# cenário no seguinte esconderia justamente o bug que este teste procura
# ...e o placar do teste é contado AQUI, no pai: `((pass++))` dentro do subshell se perderia
cen(){ if ( unset "${!_CH_@}"; declare -gA _CH_J=() _CH_EN=() _CH_OF=() _CH_VW=(); "$@" )
       then ((pass++)); else ((fail++)); fi; }

echo "== sem cohorts.json (o caso dos 1482 contests) =="
cen dif "sem arquivo" time01

echo "== arquivo inválido / vazio =="
printf 'nao é json' > "$C/cohorts.json";  cen dif "json quebrado" time01
printf '{}' > "$C/cohorts.json";          cen dif "objeto vazio"  time01
printf '{"cohorts":[]}' > "$C/cohorts.json"; cen dif "lista vazia" time01

echo "== coortes públicas com ranking (times × convidados) =="
jq -cn '{results_released:false, cohorts:[
  {id:"oficial",  name:"Oficiais",  regex:"^time", public:true, ranking:true, default:true},
  {id:"convidado",name:"Convidados",regex:"^guest",public:true, ranking:true, unranked:true}]}' \
  > "$C/cohorts.json"
cen dif "casa a 1ª regex"   time01
cen dif "casa a 2ª regex"   guest01
cen dif "não casa => default" outro01
cen dif "override do account" fixado
cen dif "override inválido"   errado
for r in co.admin co.judge co.cstaff co.animeitor co.mon; do cen dif "papel vê tudo" "$r"; done

echo "== coorte PRIVADA (a visão passa a ser a da coorte) =="
jq -cn '{results_released:false, cohorts:[
  {id:"oficial", name:"Oficiais", regex:"^time",  public:true,  ranking:true},
  {id:"ccl",     name:"CCL",      regex:"^guest", public:false}]}' > "$C/cohorts.json"
cen dif "público segue public" time01
cen dif "privado vê a própria" guest01
cen dif "papel vê tudo"        co.admin

echo "== resultados LIBERADOS: todo mundo vê tudo =="
jq -cn '{results_released:true, cohorts:[
  {id:"oficial", regex:"^time",  public:true, ranking:true},
  {id:"ccl",     regex:"^guest", public:false}]}' > "$C/cohorts.json"
cen dif "liberado => all" time01
cen dif "liberado => all" guest01

echo "== coortes sem ranking e todas públicas: o mecanismo fica DESLIGADO =="
jq -cn '{cohorts:[{id:"a", regex:"^time", public:true}, {id:"b", regex:"^guest", public:true}]}' \
  > "$C/cohorts.json"
cen dif "desligado" time01

echo "== regex inválida não pode explodir (try/catch dos dois lados) =="
jq -cn '{cohorts:[{id:"ruim", regex:"[", public:false}, {id:"ok", regex:"^time", public:true, ranking:true}]}' \
  > "$C/cohorts.json"
cen dif "regex quebrada" time01

echo "== sem regex nenhuma: cai na 1ª da lista =="
jq -cn '{cohorts:[{id:"um", public:false}, {id:"dois", public:true, ranking:true}]}' > "$C/cohorts.json"
cen dif "primeira da lista" time01

echo "== id com caractere fora do padrão (vira nome de arquivo no cache do basic) =="
jq -cn '{cohorts:[{id:"a/b", regex:"^time", public:false}, {id:"ok", public:true, ranking:true}]}' \
  > "$C/cohorts.json"
cen dif "id esquisito" time01

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
