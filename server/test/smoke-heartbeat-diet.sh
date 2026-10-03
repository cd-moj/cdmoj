#!/bin/bash
# smoke-heartbeat-diet.sh — POST /judge/heartbeat de fila VAZIA não paga o escalonador.
#
# XIV Maratona UnB (25/09/2026): 54.668 beats no dia, mediana de 0,21 s cada (~20% de um núcleo o dia
# inteiro). Com a fila vazia — o caso comum —, cada beat ainda lia o registro do juiz 3× (75 KB: 1.487
# problemas), montava o mapa de problemas no q_claim, rodava 20 `mkdir -p` e regravava o registro 4×.
# Prende (com um jq/mkdir falso no PATH que conta):
#   · fila vazia, beat aquecido (os diretórios já existem, como na produção): ≤ 8 jq e NENHUM mkdir
#     (eram 16 jq e 20 mkdir; 12 até 03/10/2026); o registro recebe state, last_seen,
#     status e free/total slots — em DUAS regravações;
#   · com job na fila, o beat ainda reivindica (quente na hora; o registro desconta o slot).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; RUN="$(mktemp -d)"; SESS="$(mktemp -d)"; SHIM="$(mktemp -d)"; trap 'rm -rf "$FIX" "$RUN" "$SESS" "$SHIM"' EXIT
mkdir -p "$FIX/treino/var" "$RUN/secrets" "$RUN/registry"; printf 'mojw_smoketest' > "$RUN/secrets/worker.token"
for b in 000-super 020-prova 040-lista-privada 060-rejulgar 080-lista-publica; do mkdir -p "$RUN/queue/$b"; done
mkdir -p "$RUN/assigned" "$RUN/results"
NOW=$EPOCHSECONDS
jq -cn --argjson t $((NOW-60)) '{host:"judge", state:"busy", last_seen:$t, capability:"pos",
  problems:([range(1487) | {key:("col#p\(.)"), value:1}] | from_entries), langs:["c"], inv_hash:"ih", free_slots:0, total_slots:4}' \
  > "$RUN/registry/judge.json"
for c in jq mkdir; do
  printf '#!/bin/bash\necho %s >> "%s/n"\nexec "%s" "$@"\n' "$c" "$SHIM" "$(command -v $c)" > "$SHIM/$c"; chmod +x "$SHIM/$c"
done
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:-${BODY:0:300}}"; ((fail++)); fi; }
beat(){ : > "$SHIM/n"
  OUT="$(PATH="$SHIM:$PATH" PATH_INFO=/judge/heartbeat REQUEST_METHOD=POST QUERY_STRING= HTTP_AUTHORIZATION="Bearer mojw_smoketest" \
         CONTESTSDIR="$FIX" RUNDIR="$RUN" SESSIONDIR="$SESS" bash "$ROUTER" <<<"$1" 2>/dev/null)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"
  NJQ=$(grep -cx jq "$SHIM/n"); NMK=$(grep -cx mkdir "$SHIM/n"); }
R(){ jq -r "$1" "$RUN/registry/judge.json"; }

echo "== fila vazia =="
beat '{"host":"judge","state":"free","free_slots":4,"total_slots":4,"inv_hash":"ih","status":"ok"}'   # aquece (cria updates/…)
beat '{"host":"judge","state":"free","free_slots":4,"total_slots":4,"inv_hash":"ih","status":"draining"}'
ck "200, nada atribuído" '[[ "$(jq -r ".success, .assigned" <<<"$BODY" | tr "\n" " ")" == "true null " ]]'
DBG="$NJQ jq, $NMK mkdir"
ck "≤ 8 jq e nenhum mkdir (eram 16 e 20; 12 até 03/10)" '(( NJQ <= 8 && NMK == 0 ))'
DBG="$(jq -c 'del(.problems)' "$RUN/registry/judge.json")"
ck "registro: free, last_seen agora, status draining, 4/4 slots" '[[ "$(R .state) $(R .status) $(R .free_slots)/$(R .total_slots)" == "free draining 4/4" ]] && (( $(R .last_seen) >= NOW ))'
DBG=""

echo "== com job na fila: reivindica =="
ID=aaaa1111aaaa1111aaaa1111aaaa1111
jq -cn --arg id "$ID" '{contest:"c", id:$id, problem_id:"col#p7", login:"a", lang:"C", filename:"a.c", code_b64:"eA=="}' \
  > "$RUN/queue/020-prova/$((NOW-30))_$ID.json"
beat '{"host":"judge","state":"free","free_slots":4,"total_slots":4,"inv_hash":"ih","status":"ok"}'
ck "o job vem no lote e vai p/ assigned/" '[[ "$(jq -r ".assigned[0].id" <<<"$BODY")" == "$ID" && -e "$RUN/assigned/judge/$((NOW-30))_$ID.json" ]]'
ck "registro desconta o slot (3/4, status ok)" '[[ "$(R .free_slots)/$(R .total_slots) $(R .status)" == "3/4 ok" ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
