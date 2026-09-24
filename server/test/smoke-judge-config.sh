#!/bin/bash
# smoke-judge-config.sh — CONFIG POR JUIZ: o que o agente aplica × o que o servidor guarda.
#
# `cfg_hash` cobre SÓ `{partition,reserve,disabled}` normalizados (bug (d), 24/09/2026): a entrada
# de judges-config.json carrega `updated_at`/`by` (e campos de escalonamento que só o servidor
# lê), e hashear a entrada inteira fazia QUALQUER edição DRENAR o juiz p/ reaplicar a mesma
# partição. Também fixa: o POST FUNDE campos (nunca substitui a entrada) e o heartbeat entrega
# `config` E `assigned` no MESMO beat (o agente despacha o lote — bug (b), do lado dele).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; RUN="$(mktemp -d)"
trap 'rm -rf "$FIX" "$SESS" "$RUN"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$RUN" JUDGES_CONFIG_FILE="$FIX/treino/var/judges-config.json"
mkdir -p "$FIX/treino/var" "$RUN/secrets" "$RUN/registry" "$RUN/queue/080-lista-publica"
printf 'CONTEST_ID=treino\nCONTEST_NAME=Treino\n' > "$FIX/treino/conf"
fx_user "$FIX/treino" hands.admin s "Admin"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' treino hands.admin Admin "$EPOCHSECONDS" > "$SESS/adm"
printf 'mojw_smoketest' > "$RUN/secrets/worker.token"
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }
call(){ # <path> <method> <query> <bearer> [body]
  OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="$3" HTTP_AUTHORIZATION="Bearer $4" \
         bash "$ROUTER" <<<"${5:-}" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
source "$ROOT/judge-gw/sched-lib.sh"

echo "== judges_config_for: o hash é SÓ dos três campos aplicados =="
jq -cn '{j1:{partition:"cpus:1",reserve:0,disabled:false,updated_at:1,by:"a"}}' > "$JUDGES_CONFIG_FILE"
h1="$(judges_config_for j1 | jq -r .cfg_hash)"
jq -c '.j1.updated_at=999 | .j1.by="outro"' "$JUDGES_CONFIG_FILE" > "$FIX/t" && mv "$FIX/t" "$JUDGES_CONFIG_FILE"
BODY="$(judges_config_for j1)"
ck "updated_at/by mudam, hash NÃO (era o bug)"   '[[ "$(jq -r .cfg_hash <<<"$BODY")" == "$h1" && -n "$h1" ]]'
jq -c '.j1.parallel_max=4 | .j1.nota="x"' "$JUDGES_CONFIG_FILE" > "$FIX/t" && mv "$FIX/t" "$JUDGES_CONFIG_FILE"
BODY="$(judges_config_for j1)"
ck "campo do servidor (parallel_max) não entra"  '[[ "$(jq -r .cfg_hash <<<"$BODY")" == "$h1" ]]'
ck "…nem vai no objeto entregue ao agente"       '[[ "$(jq -c "keys" <<<"$BODY")" == "[\"cfg_hash\",\"disabled\",\"partition\",\"reserve\"]" ]]'
jq -c '.j1.reserve="0"' "$JUDGES_CONFIG_FILE" > "$FIX/t" && mv "$FIX/t" "$JUDGES_CONFIG_FILE"
BODY="$(judges_config_for j1)"
ck "reserve \"0\" (string) normaliza p/ 0: mesmo hash" '[[ "$(jq -r .cfg_hash <<<"$BODY")" == "$h1" && "$(jq -r .reserve <<<"$BODY")" == 0 ]]'
jq -c '.j1.reserve=2' "$JUDGES_CONFIG_FILE" > "$FIX/t" && mv "$FIX/t" "$JUDGES_CONFIG_FILE"
BODY="$(judges_config_for j1)"
ck "reserve de verdade diferente ⇒ hash novo"     '[[ "$(jq -r .cfg_hash <<<"$BODY")" != "$h1" ]]'
jq -c '.j1.reserve=0 | .j1.disabled=true' "$JUDGES_CONFIG_FILE" > "$FIX/t" && mv "$FIX/t" "$JUDGES_CONFIG_FILE"
ck "disabled diferente ⇒ hash novo"               '[[ "$(judges_config_for j1 | jq -r .cfg_hash)" != "$h1" ]]'
BODY="$(judges_config_for semEntrada)"
ck "sem entrada: defaults com hash vazio"         '[[ "$(jq -c "del(.cfg_hash)" <<<"$BODY")" == "{\"disabled\":false,\"partition\":\"off\",\"reserve\":0}" && "$(jq -r .cfg_hash <<<"$BODY")" == "" ]]'
jq -cn '{j2:{partition:"cpus:1",reserve:0,disabled:false}, j3:{partition:"cpus:1",reserve:0,disabled:false,by:"b",updated_at:5,parallel_max:2}}' > "$JUDGES_CONFIG_FILE"
ck "hosts com a MESMA config aplicável têm o MESMO hash" '[[ "$(judges_config_for j2 | jq -r .cfg_hash)" == "$(judges_config_for j3 | jq -r .cfg_hash)" ]]'

echo "== POST /ops/judge-config FUNDE (campos que o POST não conhece sobrevivem) =="
jq -cn '{j1:{partition:"cpus:1",reserve:0,disabled:false,parallel_max:4,updated_at:1,by:"a"}}' > "$JUDGES_CONFIG_FILE"
call /ops/judge-config POST "" adm '{"host":"j1","reserve":1}'
ck "200"                                          'jq -e ".success == true" <<<"$BODY" >/dev/null'
ck "reserve gravado, parallel_max PRESERVADO"    '[[ "$(jq -r ".j1.reserve" "$JUDGES_CONFIG_FILE")" == 1 && "$(jq -r ".j1.parallel_max" "$JUDGES_CONFIG_FILE")" == 4 && "$(jq -r ".j1.partition" "$JUDGES_CONFIG_FILE")" == cpus:1 ]]'
call /ops/judge-config POST "" adm '{"host":"j9","partition":"numa"}'
ck "host novo nasce com defaults + o campo"       '[[ "$(jq -c ".j9 | [.partition,.reserve,.disabled]" "$JUDGES_CONFIG_FILE")" == "[\"numa\",0,false]" ]]'
call /ops/judge-config POST "" adm '{"host":"j1","partition":"cpus:0"}'
ck "partition inválida: 400"                      'grep -q partition_invalid <<<"$BODY"'
call /ops/judge-config GET "host=j1" adm
ck "GET devolve a entrada inteira"                '[[ "$(jq -r ".configs.j1.parallel_max" <<<"$BODY")" == 4 ]]'

echo "== heartbeat: config E assigned no MESMO beat =="
jq -cn '{jt:{partition:"cpus:1",reserve:0,disabled:false,updated_at:1,by:"a"}}' > "$JUDGES_CONFIG_FILE"
srv="$(judges_config_for jt | jq -r .cfg_hash)"
jq -cn --argjson now "$EPOCHSECONDS" '{host:"jt", state:"free", last_seen:$now, capability:"pos",
    problems:{"col#pa":1}, langs:[], inv_hash:"ih"}' > "$RUN/registry/jt.json"
jq -cn '{contest:"sp", id:"aaaa", problem_id:"col#pa", login:"aluno", lang:"C", filename:"a.c", code_b64:"aQ=="}' \
  > "$RUN/queue/080-lista-publica/${EPOCHSECONDS}_aaaa.json"
call /judge/heartbeat POST "host=jt" mojw_smoketest '{"host":"jt","state":"free","free_slots":2,"total_slots":2,"inv_hash":"ih","cfg_hash":"velho","status":"ok"}'
ck "config veio (hash do agente difere)"          '[[ "$(jq -r ".config.cfg_hash" <<<"$BODY")" == "$srv" ]]'
ck "…E o job veio junto, no mesmo beat"           '[[ "$(jq -r ".assigned | length" <<<"$BODY")" == 1 && "$(jq -r ".assigned[0].id" <<<"$BODY")" == aaaa ]]'
call /judge/heartbeat POST "host=jt" mojw_smoketest "{\"host\":\"jt\",\"state\":\"free\",\"free_slots\":2,\"total_slots\":2,\"inv_hash\":\"ih\",\"cfg_hash\":\"$srv\",\"status\":\"ok\"}"
ck "hash igual: sem config"                       '[[ "$(jq -r "has(\"config\")" <<<"$BODY")" == false ]]'
jq -c '.jt.by="editor" | .jt.updated_at=77 | .jt.parallel_max=3' "$JUDGES_CONFIG_FILE" > "$FIX/t" && mv "$FIX/t" "$JUDGES_CONFIG_FILE"
call /judge/heartbeat POST "host=jt" mojw_smoketest "{\"host\":\"jt\",\"state\":\"free\",\"free_slots\":2,\"total_slots\":2,\"inv_hash\":\"ih\",\"cfg_hash\":\"$srv\",\"status\":\"ok\"}"
ck "edição que não muda o aplicável: juiz NÃO recebe config (não drena)" '[[ "$(jq -r "has(\"config\")" <<<"$BODY")" == false ]]'
call /judge/register POST "host=jt" mojw_smoketest '{"host":"jt","capability":"pos","problems":{},"langs":[],"inv_hash":"ih"}'
ck "register entrega o MESMO objeto/hash"         '[[ "$(jq -r ".config.cfg_hash" <<<"$BODY")" == "$srv" && "$(jq -c ".config|keys" <<<"$BODY")" == "[\"cfg_hash\",\"disabled\",\"partition\",\"reserve\"]" ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
